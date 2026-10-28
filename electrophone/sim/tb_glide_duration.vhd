library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_glide_duration is
end entity;

architecture sim of tb_glide_duration is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (1,100,0,0,100,20,0,0,0,FX_DRY);
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal sensor_levels : sensor_array_t :=
        (others => to_unsigned(1023, 10));
    signal mixed_sample : signed(15 downto 0);
    signal voices_idle : std_logic;
    signal active_count : voice_count_t;
    signal note_active : std_logic_vector(7 downto 0);
    signal debug_increment : unsigned(31 downto 0);
    signal debug_glide_remaining : natural range 0 to 32;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.synth_engine
        generic map (G_GLIDE_SAMPLES_PER_MS => 1)
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
            debug_increment_o => debug_increment,
            debug_glide_remaining_o => debug_glide_remaining
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

        procedure run_samples(constant count : in natural) is
        begin
            for sample in 0 to count-1 loop
                run_sample;
            end loop;
        end procedure;

        procedure wait_for_idle(constant limit : in natural) is
        begin
            for sample in 0 to limit-1 loop
                run_sample;
                if active_count = 0 then
                    return;
                end if;
            end loop;
            assert false report "Base note did not become idle" severity failure;
        end procedure;

        procedure measure_glide(
            constant glide_ms : in natural;
            constant minimum_samples, maximum_samples : in natural;
            variable arrival_sample : out natural
        ) is
            variable glide_seen : boolean := false;
        begin
            rst_n <= '0';
            wait for 5*CLK_PERIOD;
            settings.glide_ms <= glide_ms;
            rst_n <= '1';
            wait until falling_edge(clk);

            sensor_on(0) <= '1';
            run_samples(500);
            sensor_on(0) <= '0';
            wait_for_idle(3000);

            sensor_on(1) <= '1';
            run_sample;
            arrival_sample := maximum_samples;
            for sample in 1 to maximum_samples+500 loop
                run_sample;
                if debug_glide_remaining /= 0 then
                    glide_seen := true;
                elsif glide_seen then
                    arrival_sample := sample;
                    exit;
                end if;
            end loop;
            sensor_on(1) <= '0';
        end procedure;

        variable arrival_80, arrival_1000 : natural;
    begin
        wait for 5*CLK_PERIOD;

        measure_glide(80, 64, 96, arrival_80);
        report "80 ms glide duration: " &
               integer'image(arrival_80) severity note;
        assert arrival_80 >= 64 and arrival_80 <= 96
            report "80 ms glide timing is outside the accepted range"
            severity failure;

        measure_glide(1000, 800, 1000, arrival_1000);
        report "1000 ms glide duration: " &
               integer'image(arrival_1000) severity note;
        assert arrival_1000 >= 800 and arrival_1000 <= 1000
            report "1000 ms glide timing is outside the accepted range"
            severity failure;

        report "tb_glide_duration passed" severity note;
        wait;
    end process;
end architecture;
