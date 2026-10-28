library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Checks that bend, vibrato and portamento change the generated audio,
-- rather than only changing values shown on the screen.
entity tb_pitch_expression is
end entity;

architecture sim of tb_pitch_expression is
    constant CLK_PERIOD : time := 20 ns;
    constant SAMPLE_RATE : natural := 48_000;
    constant C4_HZ : natural := 262;
    constant D4_HZ : natural := 294;
    constant C5_HZ : natural := 523;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal octave_shift : std_logic := '0';
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal sensor_levels : sensor_array_t :=
        (others => to_unsigned(1023, 10));
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
            octave_shift => octave_shift,
            test_mode => '0',
            mixed_sample => mixed_sample,
            voices_idle_o => voices_idle,
            active_count_o => active_count,
            note_active_o => note_active,
            debug_increment_o => open,
            debug_glide_remaining_o => open
        );

    stimulus: process
        procedure process_one_sample is
        begin
            wait until falling_edge(clk);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            -- Thirty-two voices take 352 clocks, then mixing takes three clocks.
            for stage in 0 to 399 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure run_samples(constant count : in natural) is
        begin
            for i in 0 to count-1 loop
                process_one_sample;
            end loop;
        end procedure;

        procedure measure_frequency(
            constant count : in natural;
            variable frequency : out natural
        ) is
            variable previous_value : integer := to_integer(mixed_sample);
            variable current_value : integer;
            variable first_cross, last_cross : integer := 0;
            variable crossings : natural := 0;
        begin
            for sample in 0 to count-1 loop
                process_one_sample;
                current_value := to_integer(mixed_sample);
                if previous_value < 0 and current_value >= 0 then
                    if crossings = 0 then
                        first_cross := sample;
                    else
                        last_cross := sample;
                    end if;
                    crossings := crossings + 1;
                end if;
                previous_value := current_value;
            end loop;
            assert crossings >= 2
                report "Not enough zero crossings to measure frequency"
                severity failure;
            frequency := (crossings-1) * SAMPLE_RATE /
                         (last_cross-first_cross);
        end procedure;

        procedure measure_frequency_range(
            constant count : in natural;
            variable minimum_hz, maximum_hz : out natural
        ) is
            variable previous_value : integer := to_integer(mixed_sample);
            variable current_value : integer;
            variable last_cross : integer := 0;
            variable have_cross : boolean := false;
            variable period, frequency : natural;
        begin
            minimum_hz := 65535;
            maximum_hz := 0;
            for sample in 0 to count-1 loop
                process_one_sample;
                current_value := to_integer(mixed_sample);
                if previous_value < 0 and current_value >= 0 then
                    if have_cross then
                        period := sample - last_cross;
                        frequency := SAMPLE_RATE / period;
                        if frequency < minimum_hz then
                            minimum_hz := frequency;
                        end if;
                        if frequency > maximum_hz then
                            maximum_hz := frequency;
                        end if;
                    end if;
                    last_cross := sample;
                    have_cross := true;
                end if;
                previous_value := current_value;
            end loop;
            assert maximum_hz /= 0
                report "Vibrato test did not observe repeated cycles"
                severity failure;
        end procedure;

        procedure reset_engine(constant glide_ms : in natural) is
        begin
            rst_n <= '0';
            sample_tick <= '0';
            sensor_on <= (others => '0');
            settings <= (0,100,0,0,100,0,0,0,glide_ms,FX_DRY);
            wait for 5*CLK_PERIOD;
            rst_n <= '1';
            wait for 5*CLK_PERIOD;
        end procedure;

        variable base_hz, octave_hz, bend_up_hz, bend_down_hz : natural;
        variable vibrato_min_hz, vibrato_max_hz : natural;
        variable glide_early_hz, glide_late_hz, glide_zero_hz : natural;
    begin
        reset_engine(0);

        -- Measure the unmodified C4 reference.
        sensor_on(0) <= '1';
        run_samples(2400);
        measure_frequency(4800, base_hz);
        report "C4 measured: " & integer'image(base_hz) & " Hz" severity note;
        assert abs(base_hz - C4_HZ) <= 8
            report "C4 reference frequency is outside tolerance"
            severity failure;

        -- The octave switch must double the actual output frequency.
        octave_shift <= '1';
        run_samples(100);
        measure_frequency(4800, octave_hz);
        report "High octave measured: " & integer'image(octave_hz) & " Hz"
            severity note;
        assert abs(octave_hz - C5_HZ) <= 12
            report "High octave did not reach C5"
            severity failure;
        octave_shift <= '0';
        run_samples(100);

        -- A 200-cent bend must raise the actual output pitch by about 12.2%.
        settings.bend_cents <= 200;
        run_samples(100);
        measure_frequency(4800, bend_up_hz);
        report "+200 cent measured: " & integer'image(bend_up_hz) & " Hz"
            severity note;
        assert bend_up_hz > base_hz * 108 / 100 and
               bend_up_hz < base_hz * 117 / 100
            report "Positive bend did not raise the audio frequency"
            severity failure;

        settings.bend_cents <= -200;
        run_samples(100);
        measure_frequency(4800, bend_down_hz);
        report "-200 cent measured: " & integer'image(bend_down_hz) & " Hz"
            severity note;
        assert bend_down_hz > base_hz * 83 / 100 and
               bend_down_hz < base_hz * 92 / 100
            report "Negative bend did not lower the audio frequency"
            severity failure;

        -- At 50 cents the instantaneous frequency must move both above and
        -- below the unmodulated C4 frequency.
        settings.bend_cents <= 0;
        settings.vibrato_cents <= 50;
        run_samples(200);
        measure_frequency_range(18_000, vibrato_min_hz, vibrato_max_hz);
        report "Vibrato range measured: " & integer'image(vibrato_min_hz) &
               " to " & integer'image(vibrato_max_hz) & " Hz" severity note;
        assert vibrato_min_hz < base_hz - 3 and
               vibrato_max_hz > base_hz + 3
            report "Vibrato did not modulate the audio frequency"
            severity failure;

        -- Portamento must pass through intermediate pitches before D4.
        reset_engine(100);
        sensor_on(1) <= '1';
        run_samples(3000);
        measure_frequency(1200, glide_early_hz);
        run_samples(15_000);
        measure_frequency(2400, glide_late_hz);
        report "Portamento measured: " & integer'image(glide_early_hz) &
               " Hz early, " & integer'image(glide_late_hz) & " Hz late"
            severity note;
        assert glide_early_hz > C4_HZ + 4 and
               glide_early_hz < D4_HZ - 3
            report "Portamento jumped instead of gliding"
            severity failure;
        -- Compare with the measured C4 reference so sample-period rounding
        -- does not make the absolute frequency test depend on VHDL division.
        assert glide_late_hz >= base_hz * 109 / 100 and
               glide_late_hz <= base_hz * 115 / 100
            report "Portamento did not reach the target note"
            severity failure;

        -- Zero milliseconds is an immediate pitch change.
        reset_engine(0);
        sensor_on(1) <= '1';
        run_samples(50);
        measure_frequency(2400, glide_zero_hz);
        report "Zero portamento measured: " & integer'image(glide_zero_hz) &
               " Hz" severity note;
        assert glide_zero_hz >= base_hz * 109 / 100 and
               glide_zero_hz <= base_hz * 115 / 100
            report "Zero portamento did not change pitch immediately"
            severity failure;

        assert voices_idle = '0'
            report "Voice was not marked active while a sensor was held"
            severity failure;
        sensor_on(1) <= '0';
        run_samples(1000);
        assert voices_idle = '1'
            report "Voice did not become idle after release"
            severity failure;

        report "tb_pitch_expression passed" severity note;
        wait;
    end process;
end architecture;
