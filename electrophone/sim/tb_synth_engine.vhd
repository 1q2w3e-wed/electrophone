library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_synth_engine is
end entity;

architecture sim of tb_synth_engine is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal sensor_levels : sensor_array_t := (others => (others => '0'));
    signal mixed_sample : signed(15 downto 0);
    signal voices_idle : std_logic;
    signal active_count : voice_count_t;
    signal note_active : std_logic_vector(7 downto 0);
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.synth_engine
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            settings => settings,
            sensor_on => sensor_on,
            sensor_levels => sensor_levels,
            pedal_mode => pedal_mode,
            octave_shift => '0',
            test_mode => '0',
            mixed_sample => mixed_sample,
            voices_idle_o => voices_idle,
            active_count_o => active_count,
            note_active_o => note_active,
            debug_increment_o => open,
            debug_glide_remaining_o => open
        );

    stimulus: process
        procedure run_samples(constant count : in natural; peak : out natural) is
            variable value : integer;
        begin
            peak := 0;
            for i in 0 to count-1 loop
                wait until falling_edge(clk);
                sample_tick <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                sample_tick <= '0';
                for stage in 0 to 399 loop
                    wait until rising_edge(clk);
                    value := abs(to_integer(mixed_sample));
                    if value > peak then peak := value; end if;
                end loop;
            end loop;
        end procedure;

        variable silent_peak, one_peak, eight_peak : natural;
        variable low_pressure_peak, high_pressure_peak : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;

        run_samples(100, silent_peak);
        assert silent_peak = 0 report "Silent engine is not silent" severity failure;

        sensor_on(0) <= '1';
        sensor_levels(0) <= to_unsigned(1023, 10);
        run_samples(1200, one_peak);
        assert one_peak > 100 report "Single voice did not produce audio" severity failure;

        for i in 0 to 7 loop
            sensor_on(i) <= '1';
            sensor_levels(i) <= to_unsigned(1023, 10);
        end loop;
        run_samples(1200, eight_peak);
        assert eight_peak > 100
            report "Eight voices did not produce a mixed signal" severity failure;

        sensor_on <= (others => '0');
        run_samples(400, silent_peak);
        sensor_on(0) <= '1';
        sensor_levels(0) <= to_unsigned(100, 10);
        run_samples(1200, low_pressure_peak);
        sensor_levels(0) <= to_unsigned(1000, 10);
        run_samples(1200, high_pressure_peak);
        assert high_pressure_peak > low_pressure_peak
            report "Pressure does not change voice amplitude" severity failure;

        report "tb_synth_engine passed" severity note;
        wait;
    end process;
end architecture;
