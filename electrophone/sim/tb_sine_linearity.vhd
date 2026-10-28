library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.ui_types.all;

-- The sine tone must remain spectrally pure. In particular, the loudness
-- compensation attempt must not introduce noticeable third-harmonic content.
entity tb_sine_linearity is
end entity;

architecture sim of tb_sine_linearity is
    constant CLK_PERIOD : time := 20 ns;
    constant SAMPLE_COUNT : positive := 2048;
    constant FUNDAMENTAL_BIN : positive := 11;
    constant THIRD_HARMONIC_BIN : positive := 33;
    type sample_array_t is array (0 to SAMPLE_COUNT-1) of integer;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal sensor_levels : sensor_array_t :=
        (others => to_unsigned(1023, 10));
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
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
            pedal_mode => '0',
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
        procedure run_sample(value : out integer) is
        begin
            wait until falling_edge(clk);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for stage in 0 to 399 loop
                wait until rising_edge(clk);
            end loop;
            value := to_integer(mixed_sample);
            for stage in 0 to 623 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure dft_level(
            constant bin_index : in positive;
            constant samples : in sample_array_t;
            variable level : out real
        ) is
            variable real_sum, imag_sum : real := 0.0;
            variable angle : real;
        begin
            for sample in 0 to SAMPLE_COUNT-1 loop
                angle := 2.0 * MATH_PI * real(bin_index * sample) /
                         real(SAMPLE_COUNT);
                real_sum := real_sum + real(samples(sample)) * cos(angle);
                imag_sum := imag_sum + real(samples(sample)) * sin(angle);
            end loop;
            level := sqrt(real_sum*real_sum + imag_sum*imag_sum);
        end procedure;

        variable samples : sample_array_t;
        variable sample_value : integer;
        variable fundamental, third : real;
        variable harmonic_ratio : real;
        variable peak : natural := 0;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        sensor_on(0) <= '1';

        for sample in 0 to 199 loop
            run_sample(sample_value);
        end loop;
        for sample in 0 to SAMPLE_COUNT-1 loop
            run_sample(sample_value);
            samples(sample) := sample_value;
            if abs(sample_value) > peak then
                peak := abs(sample_value);
            end if;
        end loop;

        dft_level(FUNDAMENTAL_BIN, samples, fundamental);
        dft_level(THIRD_HARMONIC_BIN, samples, third);
        harmonic_ratio := third / fundamental;
        report "Sine third-harmonic ratio: " &
               real'image(harmonic_ratio) severity note;
        report "Sine peak sample: " & integer'image(peak) severity note;
        assert harmonic_ratio < 0.05
            report "Sine waveform contains excessive harmonic distortion"
            severity failure;

        report "tb_sine_linearity passed" severity note;
        wait;
    end process;
end architecture;
