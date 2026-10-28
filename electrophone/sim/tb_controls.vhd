library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.ui_types.all;

entity tb_controls is end;
architecture test of tb_controls is
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal a, b, key_n : std_logic := '1';
    signal left_step, right_step, key_press, rev_left, rev_right, rev_key : std_logic;
    signal nl, nr, nk, nrl, nrr : natural := 0;
    signal ln, lp, lk, rn, rp, rk : std_logic := '0';
    signal page : page_t;
    signal cursor : natural range 0 to 3;
    signal view, saved : settings_t;
    signal encoder_done, menu_done : boolean := false;
begin
    clk <= not clk after 500 ns;
    encoder: entity work.ec11_decoder
        generic map(1_000_000, 10, 2, 4, false)
        port map(clk, reset_n, a, b, key_n, left_step, right_step, key_press);
    reverse_encoder: entity work.ec11_decoder
        generic map(1_000_000, 10, 2, 2, true)
        port map(clk, reset_n, a, b, key_n, rev_left, rev_right, rev_key);
    menu: entity work.menu_ui
        port map(clk, reset_n, ln, lp, lk, rn, rp, rk, page, cursor, view, saved);
    process(clk)
    begin
        if rising_edge(clk) then
            if left_step = '1' then nl <= nl+1; end if;
            if right_step = '1' then nr <= nr+1; end if;
            if key_press = '1' then nk <= nk+1; end if;
            if rev_left = '1' then nrl <= nrl+1; end if;
            if rev_right = '1' then nrr <= nrr+1; end if;
        end if;
    end process;
    process
        procedure phase(v : std_logic_vector(1 downto 0)) is
        begin a <= v(1); b <= v(0); wait for 30 us; end;
    begin
        wait for 10 us; reset_n <= '1'; wait for 30 us;
        -- Sub-filter glitches must not become rotation events.
        a <= '0'; wait for 2 us; a <= '1'; wait for 30 us;
        assert nl=0 and nr=0 report "Rotation glitch accepted" severity failure;
        phase("01"); phase("00"); phase("10"); phase("11");
        assert nr=1 and nl=0 and nrl=2 and nrr=0 report "Forward/reverse/edge-count decode" severity failure;
        phase("10"); phase("00"); phase("01"); phase("11");
        assert nl=1 and nr=1 and nrr=2 report "Backward decode" severity failure;
        -- A partial forward movement followed by its reverse must cancel.
        phase("01"); phase("11");
        assert nl=1 and nr=1 report "Contact bounce caused a step" severity failure;
        -- Both bits change at once: discard the incomplete movement.
        phase("00"); phase("11");
        assert nl=1 and nr=1 report "Illegal quadrature transition accepted" severity failure;
        key_n <= '0'; wait for 100 us; key_n <= '1'; wait for 3 ms;
        assert nk=0 report "Button glitch accepted" severity failure;
        key_n <= '0'; wait for 5 ms;
        assert nk=1 report "Held button did not emit exactly once" severity failure;
        key_n <= '1'; wait for 3 ms; key_n <= '0'; wait for 3 ms;
        assert nk=2 report "Second key press missing" severity failure;
        encoder_done <= true;
        wait;
    end process;
    process
        procedure pulse(signal s : out std_logic) is
        begin
            wait until falling_edge(clk); s <= '1';
            wait until falling_edge(clk); s <= '0';
            wait until falling_edge(clk);
        end;
    begin
        wait until reset_n='1'; wait for 20 us;
        assert page=HOME_PAGE and cursor=0 and saved.volume=50 severity failure;
        pulse(lp); assert cursor=3 report "Home previous wrap" severity failure;
        pulse(ln); pulse(lk); assert page=TONE_PAGE severity failure;
        pulse(rp); assert view.tone=3 report "Tone backward wrap" severity failure;
        assert saved.tone=0 report "Unconfirmed draft reached saved state" severity failure;
        pulse(lk); assert page=HOME_PAGE and saved.tone=3 severity failure;
        pulse(ln); pulse(lk); assert page=VOLUME_PAGE severity failure;
        for i in 1 to 120 loop pulse(rn); end loop;
        assert view.volume=100 and saved.volume=50 report "Volume saturation/draft isolation" severity failure;
        pulse(lk); assert saved.volume=100 severity failure;
        pulse(lk); for i in 1 to 10 loop pulse(rp); end loop;
        assert view.volume=90 severity failure;
        pulse(rk); assert saved.volume=100 and page=HOME_PAGE report "Cancel changed saved volume" severity failure;
        pulse(ln); pulse(lk); assert page=ADSR_PAGE and cursor=0 severity failure;
        for i in 1 to 250 loop pulse(rn); end loop;
        assert view.attack_ms=2000 report "Attack upper saturation" severity failure;
        for i in 1 to 250 loop pulse(rp); end loop;
        assert view.attack_ms=0 report "Attack lower saturation" severity failure;
        pulse(ln); pulse(rn); assert view.decay_ms=110 severity failure;
        pulse(ln); for i in 1 to 100 loop pulse(rn); end loop;
        assert view.sustain=100 severity failure;
        pulse(ln); pulse(rn); assert view.release_ms=210 severity failure;
        pulse(lk);
        assert saved.attack_ms=0 and saved.decay_ms=110 and saved.sustain=100 and saved.release_ms=210
            report "ADSR save" severity failure;
        pulse(ln); pulse(lk); assert page=SYSTEM_PAGE severity failure;
        pulse(rk); assert page=HOME_PAGE severity failure;
        menu_done <= true;
        wait;
    end process;
    process
    begin
        wait until encoder_done and menu_done;
        report "PASS: quadrature, debounce, reversal, menu save/cancel and parameter bounds" severity note;
        stop; wait;
    end process;
    process
    begin wait for 50 ms; assert false report "Control test timeout" severity failure; end process;
end;
