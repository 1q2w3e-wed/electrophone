library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Adding a voice must not step the shared polyphony gain in one sample.
entity tb_normalizer_smoothing is
end entity;

architecture sim of tb_normalizer_smoothing is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal settings : settings_t :=
        (0,100,0,100,100,20,0,0,0,FX_DRY);
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
        alias gain is
            << signal .tb_normalizer_smoothing.dut.voice_normalizer :
               natural range 0 to 256 >>;

        procedure run_sample is
        begin
            wait until falling_edge(clk);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for stage in 0 to 1023 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        variable previous_gain : natural;
        variable current_gain : natural;
        variable maximum_drop : natural := 0;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;

        sensor_on(0) <= '1';
        for sample in 0 to 199 loop
            run_sample;
        end loop;
        assert gain = 256
            report "One-voice gain did not reach 256"
            severity failure;

        previous_gain := gain;
        sensor_on(1) <= '1';
        for sample in 0 to 499 loop
            run_sample;
            current_gain := gain;
            if previous_gain > current_gain and
               previous_gain - current_gain > maximum_drop then
                maximum_drop := previous_gain - current_gain;
            end if;
            previous_gain := current_gain;
        end loop;

        report "Normalizer maximum per-sample drop: " &
               integer'image(maximum_drop) &
               ", final gain: " & integer'image(current_gain)
            severity note;
        assert maximum_drop <= 1
            report "Adding a voice produced a gain step"
            severity failure;
        assert current_gain = 181
            report "Two-voice gain did not settle at 181"
            severity failure;

        report "tb_normalizer_smoothing passed" severity note;
        wait;
    end process;
end architecture;
