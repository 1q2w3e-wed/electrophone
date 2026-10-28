library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_expression_smoothing is
end entity;

architecture sim of tb_expression_smoothing is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (1,100,0,0,100,0,0,0,0,FX_DRY);
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
        variable value : integer;
        variable min_abs, max_abs : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;
        sensor_on(0) <= '1';

        -- Let the ADSR reach full sustain.
        for sample in 0 to 1199 loop
            wait until falling_edge(clk);
            if sample mod 2 = 0 then
                sensor_levels(0) <= to_unsigned(64, 10);
            else
                sensor_levels(0) <= to_unsigned(192, 10);
            end if;
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for stage in 0 to 399 loop
                wait until rising_edge(clk);
            end loop;
            for wait_clk in 0 to 60 loop
                wait until rising_edge(clk);
            end loop;
        end loop;

        min_abs := 65535;
        max_abs := 0;
        for sample in 0 to 99 loop
            wait until falling_edge(clk);
            if sample mod 2 = 0 then
                sensor_levels(0) <= to_unsigned(64, 10);
            else
                sensor_levels(0) <= to_unsigned(192, 10);
            end if;
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for stage in 0 to 399 loop
                wait until rising_edge(clk);
            end loop;
            value := abs(to_integer(mixed_sample));
            if value < min_abs then min_abs := value; end if;
            if value > max_abs then max_abs := value; end if;
            for wait_clk in 0 to 60 loop
                wait until rising_edge(clk);
            end loop;
        end loop;

        assert max_abs - min_abs < 500
            report "Light-pressure jitter causes excessive amplitude modulation"
            severity failure;
        assert max_abs > 1000
            report "Expression smoothing test did not produce audio"
            severity failure;

        report "tb_expression_smoothing passed" severity note;
        wait;
    end process;
end architecture;
