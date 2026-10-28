library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Latching more notes in pedal mode must not make the complete mix collapse
-- in perceived loudness. A 1/sqrt(N) gain law keeps uncorrelated tones near
-- equal output energy while the final limiter prevents hard clipping.
entity tb_pedal_loudness is
end entity;

architecture sim of tb_pedal_loudness is
    constant CLK_PERIOD : time := 20 ns;
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
            pedal_mode => '1',
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
        procedure run_sample is
        begin
            wait until falling_edge(clk);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for stage in 0 to 399 loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        procedure measure_energy(
            constant count : in positive;
            variable energy : out real
        ) is
            variable value : integer;
        begin
            energy := 0.0;
            for sample in 0 to count-1 loop
                run_sample;
                value := to_integer(mixed_sample);
                energy := energy + real(value * value);
            end loop;
        end procedure;

        procedure reset_engine is
        begin
            rst_n <= '0';
            sample_tick <= '0';
            wait for 5*CLK_PERIOD;
            rst_n <= '1';
            wait for 5*CLK_PERIOD;
        end procedure;

        variable single_energy, eight_energy : real;
    begin
        reset_engine;
        sensor_on <= "00000001";
        for sample in 0 to 99 loop
            run_sample;
        end loop;
        measure_energy(1000, single_energy);

        reset_engine;
        sensor_on <= (others => '1');
        for sample in 0 to 99 loop
            run_sample;
        end loop;
        measure_energy(1000, eight_energy);

        report "Pedal energy ratio eight/single: " &
               real'image(eight_energy / single_energy) severity note;
        assert eight_energy > single_energy / 4.0
            report "Eight latched notes became more than 6 dB quieter"
            severity failure;

        report "tb_pedal_loudness passed" severity note;
        wait;
    end process;
end architecture;
