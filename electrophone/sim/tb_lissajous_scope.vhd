library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_lissajous_scope is
end entity;

architecture sim of tb_lissajous_scope is
    constant CLK_PERIOD : time := 20 ns;
    constant SAMPLE_RATE : real := 48828.125;
    constant TONE_HZ : real := 262.0;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_in : signed(15 downto 0) := (others => '0');
    signal display_latch : std_logic := '0';
    signal read_x, read_y : natural range 0 to 95 := 0;
    signal pixel_value : std_logic;
    signal frame_ready : std_logic;
    signal amplitude : natural := 18000;
    signal finished : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.lissajous_scope
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            sample_in => sample_in,
            display_latch => display_latch,
            read_x => read_x, read_y => read_y,
            pixel_o => pixel_value,
            frame_ready => frame_ready
        );

    sample_driver: process
        variable divider : natural range 0 to 1023 := 0;
        variable phase : real := 0.0;
    begin
        wait until rising_edge(clk);
        if rst_n = '0' then
            divider := 0;
            phase := 0.0;
            sample_tick <= '0';
            sample_in <= (others => '0');
        else
            if divider = 1023 then
                divider := 0;
                sample_tick <= '1';
                sample_in <= to_signed(
                    integer(real(amplitude) * sin(phase)), 16);
                phase := phase + 2.0 * 3.141592653589793 *
                         TONE_HZ / SAMPLE_RATE;
                if phase >= 2.0 * 3.141592653589793 then
                    phase := phase - 2.0 * 3.141592653589793;
                end if;
            else
                divider := divider + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    stimulus: process
        procedure capture_frame is
        begin
            wait until rising_edge(frame_ready);
            wait until falling_edge(clk);
            display_latch <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            display_latch <= '0';
        end procedure;

        procedure scan_bitmap(
            variable count : out natural;
            variable min_x, max_x, min_y, max_y : out integer
        ) is
            variable seen : boolean;
        begin
            count := 0;
            min_x := 95;
            max_x := 0;
            min_y := 95;
            max_y := 0;
            for y in 0 to 95 loop
                for x in 0 to 95 loop
                    wait until falling_edge(clk);
                    read_x <= x;
                    read_y <= y;
                    wait until rising_edge(clk);
                    wait until falling_edge(clk);
                    seen := pixel_value = '1';
                    if seen then
                        count := count + 1;
                        if x < min_x then min_x := x; end if;
                        if x > max_x then max_x := x; end if;
                        if y < min_y then min_y := y; end if;
                        if y > max_y then max_y := y; end if;
                    end if;
                end loop;
            end loop;
        end procedure;

        variable pixel_count : natural;
        variable min_x, max_x, min_y, max_y : integer;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';

        capture_frame;
        scan_bitmap(pixel_count, min_x, max_x, min_y, max_y);
        report "Lissajous high-amplitude pixels: " &
               integer'image(pixel_count) severity note;
        assert pixel_count > 100
            report "Lissajous trajectory is not visible"
            severity failure;
        assert max_x - min_x > 40 and max_y - min_y > 40
            report "Lissajous trajectory is not a visible loop"
            severity failure;

        rst_n <= '0';
        amplitude <= 2000;
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        capture_frame;
        capture_frame;
        scan_bitmap(pixel_count, min_x, max_x, min_y, max_y);
        report "Lissajous low-amplitude pixels: " &
               integer'image(pixel_count) severity note;
        assert max_x - min_x > 20 and max_y - min_y > 20
            report "Automatic gain did not enlarge a quiet trajectory"
            severity failure;

        rst_n <= '0';
        amplitude <= 0;
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        capture_frame;
        scan_bitmap(pixel_count, min_x, max_x, min_y, max_y);
        report "Lissajous silence pixels: " &
               integer'image(pixel_count) severity note;
        assert pixel_count = 0
            report "Silence left a stale Lissajous trajectory"
            severity failure;

        finished <= '1';
        report "tb_lissajous_scope passed" severity note;
        wait;
    end process;

    timeout: process
    begin
        wait for 350 ms;
        assert finished = '1'
            report "Lissajous test timed out" severity failure;
        wait;
    end process;
end architecture;
