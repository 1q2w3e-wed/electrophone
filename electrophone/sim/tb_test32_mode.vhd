library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- End-to-end scoring test: 32 independent oscillators must produce one
-- separate FFT peak in each of the 32 test-mode display bands.
entity tb_test32_mode is
end entity;

architecture sim of tb_test32_mode is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_divider : natural range 0 to 1023 := 0;
    signal mixed_sample : signed(15 downto 0);
    signal display_latch : std_logic := '0';
    signal read_bin : natural range 0 to 63 := 0;
    signal magnitude : unsigned(7 downto 0);
    signal frame_ready : std_logic;
    signal active_count : voice_count_t;
    signal voices_idle : std_logic;
    signal note_active : std_logic_vector(7 downto 0);
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
    signal no_sensors : std_logic_vector(7 downto 0) := (others => '0');
    signal levels : sensor_array_t := (others => (others => '0'));
begin
    clk <= not clk after CLK_PERIOD/2;

    sample_clock: process(clk)
    begin
        if rising_edge(clk) then
            if sample_divider = 1023 then
                sample_divider <= 0;
                sample_tick <= '1';
            else
                sample_divider <= sample_divider + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    synth: entity work.synth_engine
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            settings => settings,
            sensor_on => no_sensors,
            sensor_levels => levels,
            pedal_mode => '0',
            octave_shift => '0',
            test_mode => '1',
            mixed_sample => mixed_sample,
            voices_idle_o => voices_idle,
            active_count_o => active_count,
            note_active_o => note_active,
            debug_increment_o => open,
            debug_glide_remaining_o => open
        );

    analyzer: entity work.spectrum_analyzer
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            sample_in => mixed_sample,
            test_mode => '1',
            display_latch => display_latch,
            read_bin => read_bin,
            magnitude_o => magnitude,
            frame_ready => frame_ready
        );

    stimulus: process
        variable minimum_level : natural := 255;
        variable level : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';

        for frame in 1 to 3 loop
            wait until rising_edge(frame_ready);
        end loop;
        wait until falling_edge(clk);
        display_latch <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        display_latch <= '0';
        wait for 2*CLK_PERIOD;

        assert active_count = POLYPHONY
            report "Test mode did not report 32 active oscillators"
            severity failure;
        assert voices_idle = '0'
            report "Test mode incorrectly reported an idle engine"
            severity failure;

        for index in 0 to 31 loop
            read_bin <= index;
            wait until rising_edge(clk);
            wait for 1 ns;
            level := to_integer(magnitude);
            if level < minimum_level then
                minimum_level := level;
            end if;
        end loop;

        report "Test-mode minimum peak level: " &
               integer'image(minimum_level) severity note;
        assert minimum_level > 80
            report "One or more of the 32 test tones is missing"
            severity failure;

        read_bin <= 32;
        wait until rising_edge(clk);
        wait for 1 ns;
        assert magnitude = 0
            report "Unused test-mode spectrum bands are not blank"
            severity failure;

        report "tb_test32_mode passed" severity note;
        wait;
    end process;
end architecture;
