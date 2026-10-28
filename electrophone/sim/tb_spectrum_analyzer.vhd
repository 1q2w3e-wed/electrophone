library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.spectrum_tables.all;

entity tb_spectrum_analyzer is
end entity;

architecture sim of tb_spectrum_analyzer is
    constant CLK_PERIOD : time := 20 ns;
    constant SAMPLE_RATE : real := 48828.125;
    constant TONE_HZ : real := 262.0;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_in : signed(15 downto 0) := (others => '0');
    signal display_latch : std_logic := '0';
    signal read_bin : natural range 0 to 63 := 0;
    signal magnitude : unsigned(7 downto 0);
    signal frame_ready : std_logic;
    signal frame_seen : std_logic := '0';
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
        variable sample_index : natural := 0;
        variable phase : real := 0.0;
    begin
        wait until rising_edge(clk);
        if rst_n = '0' then
            divider := 0;
            sample_index := 0;
            phase := 0.0;
            sample_tick <= '0';
            sample_in <= (others => '0');
        else
            if divider = 1023 then
                divider := 0;
                sample_tick <= '1';
                sample_in <= to_signed(integer(18000.0 * sin(phase)), 16);
                phase := phase + 2.0 * 3.141592653589793 * TONE_HZ / SAMPLE_RATE;
                if phase >= 2.0 * 3.141592653589793 then
                    phase := phase - 2.0 * 3.141592653589793;
                end if;
                sample_index := sample_index + 1;
            else
                divider := divider + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    stimulus: process
        variable peak_bin : natural := 8;
        variable peak_level : natural := 0;
        variable value : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';

        wait until rising_edge(frame_ready);
        wait until falling_edge(clk);
        display_latch <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        display_latch <= '0';
        frame_seen <= '1';

        for bin_index in 0 to 51 loop
            read_bin <= bin_index;
            wait until rising_edge(clk);
            wait for 1 ns;
            value := to_integer(magnitude);
            if value > peak_level then
                peak_level := value;
                peak_bin := bin_index;
            end if;
        end loop;

        report "262 Hz peak bin: " & integer'image(peak_bin) &
               " level " & integer'image(peak_level) severity note;
        assert peak_level > 0
            report "Spectrum analyzer produced an empty frame"
            severity failure;
        assert peak_bin >= 24 and peak_bin <= 26
            report "262 Hz tone peak is in the wrong FFT bin"
            severity failure;

        report "tb_spectrum_analyzer passed" severity note;
        wait;
    end process;

    timeout: process
    begin
        wait for 80 ms;
        assert frame_seen = '1'
            report "Spectrum analyzer frame timed out"
            severity failure;
        wait;
    end process;
end architecture;
