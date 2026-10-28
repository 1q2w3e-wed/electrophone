library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_spectrum_multi_tone is
end entity;

architecture sim of tb_spectrum_multi_tone is
    constant CLK_PERIOD : time := 20 ns;
    constant SAMPLE_RATE : real := 48828.125;
    type frequency_array_t is array (0 to 7) of real;
    constant FREQUENCIES : frequency_array_t :=
        (262.0, 294.0, 330.0, 349.0, 392.0, 440.0, 494.0, 523.0);

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_in : signed(15 downto 0) := (others => '0');
    signal display_latch : std_logic := '0';
    signal read_bin : natural range 0 to 63 := 0;
    signal magnitude : unsigned(7 downto 0);
    signal frame_ready : std_logic;
    signal tone_mask : std_logic_vector(7 downto 0) := (others => '0');
    signal frame_seen : natural := 0;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.spectrum_analyzer
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            sample_in => sample_in,
            test_mode => '0',
            display_latch => display_latch,
            read_bin => read_bin,
            magnitude_o => magnitude,
            frame_ready => frame_ready
        );

    sample_driver: process
        variable divider : natural range 0 to 1023 := 0;
        variable phases : frequency_array_t := (others => 0.0);
        variable active_count : natural;
        variable sample_value : real;
    begin
        wait until rising_edge(clk);
        if rst_n = '0' then
            divider := 0;
            phases := (others => 0.0);
            sample_tick <= '0';
            sample_in <= (others => '0');
        else
            if divider = 1023 then
                divider := 0;
                sample_tick <= '1';
                active_count := 0;
                sample_value := 0.0;
                for tone in 0 to 7 loop
                    if tone_mask(tone) = '1' then
                        sample_value := sample_value + sin(phases(tone));
                        active_count := active_count + 1;
                    end if;
                    phases(tone) := phases(tone) +
                        2.0 * 3.141592653589793 * FREQUENCIES(tone) /
                        SAMPLE_RATE;
                    if phases(tone) >= 2.0 * 3.141592653589793 then
                        phases(tone) := phases(tone) -
                                        2.0 * 3.141592653589793;
                    end if;
                end loop;
                if active_count /= 0 then
                    sample_value := sample_value / real(active_count);
                end if;
                sample_in <= to_signed(
                    integer(16000.0 * sample_value), 16);
            else
                divider := divider + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    frame_monitor: process(frame_ready)
    begin
        if rising_edge(frame_ready) then
            frame_seen <= frame_seen + 1;
        end if;
    end process;

    stimulus: process
        procedure capture_case(constant mask_value : std_logic_vector(7 downto 0)) is
        begin
            rst_n <= '0';
            tone_mask <= mask_value;
            wait for 4*CLK_PERIOD;
            rst_n <= '1';
            wait until rising_edge(frame_ready);
            wait until falling_edge(clk);
            display_latch <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            display_latch <= '0';
        end procedure;

        procedure read_level(constant bin_index : natural;
                             variable level : out natural) is
        begin
            read_bin <= bin_index;
            wait until rising_edge(clk);
            wait for 1 ns;
            level := to_integer(magnitude);
        end procedure;

        variable c4_level, e4_level : natural;
        variable previous_level, current_level, next_level : natural;
        variable peak_count : natural;
    begin
        wait for 5*CLK_PERIOD;

        capture_case("00000101");
        read_level(25, c4_level);
        read_level(27, e4_level);
        report "Two-tone C4/E4 levels: " & integer'image(c4_level) &
               " / " & integer'image(e4_level) severity note;
        assert c4_level > 100 and e4_level > 100
            report "Two-tone spectrum did not show both tones"
            severity failure;

        capture_case("11111111");
        peak_count := 0;
        read_level(0, previous_level);
        read_level(1, current_level);
        for bin_index in 2 to 50 loop
            read_level(bin_index+1, next_level);
            if current_level > 100 and current_level >= previous_level and
               current_level > next_level then
                peak_count := peak_count + 1;
            end if;
            previous_level := current_level;
            current_level := next_level;
        end loop;
        report "Eight-tone local peak count: " & integer'image(peak_count)
            severity note;
        assert peak_count >= 2
            report "Eight-tone spectrum lost too many independent peaks"
            severity failure;

        report "tb_spectrum_multi_tone passed" severity note;
        wait;
    end process;

    timeout: process
    begin
        wait for 180 ms;
        assert frame_seen >= 2
            report "Multi-tone spectrum frames timed out"
            severity failure;
        wait;
    end process;
end architecture;
