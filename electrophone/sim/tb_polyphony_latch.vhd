library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_polyphony_latch is
end entity;

architecture sim of tb_polyphony_latch is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (0,100,0,0,100,20,0,0,0,FX_DRY);
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
        procedure run_samples(
            constant count : in natural;
            variable peak : out natural;
            variable rail_count : out natural
        ) is
            variable value : integer;
        begin
            peak := 0;
            rail_count := 0;
            for sample in 0 to count-1 loop
                wait until falling_edge(clk);
                sample_tick <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                sample_tick <= '0';
                for stage in 0 to 399 loop
                    wait until rising_edge(clk);
                    value := to_integer(mixed_sample);
                    if abs(value) > peak then peak := abs(value); end if;
                    if value = 32767 or value = -32768 then
                        rail_count := rail_count + 1;
                    end if;
                end loop;
            end loop;
        end procedure;

        variable peak, rail_count : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        pedal_mode <= '1';
        sensor_on(0) <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        run_samples(1200, peak, rail_count);
        report "Held pedal voice peak: " & integer'image(peak) severity note;
        assert active_count = 1
            report "Initial pedal-mode attack was not allocated"
            severity failure;

        sensor_on(0) <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        run_samples(600, peak, rail_count);
        report "Released pedal voice peak: " & integer'image(peak) severity note;
        assert active_count = 1
            report "Released pedal voice was not retained"
            severity failure;
        assert note_active = "00000001"
            report "Latched voice did not expose its fundamental marker"
            severity failure;
        assert peak > 100
            report "Released pedal voice became silent"
            severity failure;

        pedal_mode <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        run_samples(1200, peak, rail_count);
        assert active_count = 0
            report "Released pedal voice did not become idle"
            severity failure;

        pedal_mode <= '1';
        for attack in 0 to POLYPHONY-1 loop
            sensor_on(0) <= '1';
            for step in 1 to 35 loop
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
            sensor_on(0) <= '0';
            for step in 1 to 35 loop
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end loop;
        run_samples(1200, peak, rail_count);
        report "32-attack active count: " & integer'image(active_count)
            severity note;
        assert active_count = POLYPHONY
            report "Synthesizer did not reach 32 active voices"
            severity failure;
        assert note_active = "00000001"
            report "Duplicate voices exposed an invalid marker mask"
            severity failure;
        assert peak > 100
            report "32-voice mix produced no audible output"
            severity failure;
        assert rail_count = 0
            report "32-voice mix clipped at the 16-bit output rails"
            severity failure;

        pedal_mode <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        run_samples(1200, peak, rail_count);
        assert active_count = 0
            report "32 pedal voices did not recycle after release"
            severity failure;
        assert voices_idle = '1'
            report "voices_idle stayed active after all voices finished"
            severity failure;
        assert note_active = "00000000"
            report "Finished voices left a stale fundamental marker"
            severity failure;

        report "tb_polyphony_latch passed" severity note;
        wait;
    end process;
end architecture;
