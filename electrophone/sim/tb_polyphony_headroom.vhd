library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_polyphony_headroom is
end entity;

architecture sim of tb_polyphony_headroom is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '1');
    signal sensor_levels : sensor_array_t := (others => to_unsigned(1023, 10));
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
        variable rail_count : natural := 0;
        variable peak : natural := 0;
        variable value : integer;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;

        for sample in 0 to 1199 loop
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

        assert rail_count = 0
            report "Polyphonic mix clips at the 16-bit output rails"
            severity failure;
        assert peak > 1000
            report "Polyphonic test did not generate audio"
            severity failure;

        report "tb_polyphony_headroom passed" severity note;
        wait;
    end process;
end architecture;
