library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_pluck_mode is
end entity;

architecture sim of tb_pluck_mode is
    constant CLK_PERIOD : time := 50 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal settings : settings_t :=
        (0,100,0,100,0,20,0,0,0,FX_DRY);
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
        alias allocator_trigger is
            << signal .tb_pluck_mode.dut.allocator_trigger :
               std_logic_vector(31 downto 0) >>;
        alias allocator_active is
            << signal .tb_pluck_mode.dut.allocator.active_mask :
               std_logic_vector(31 downto 0) >>;
        alias ram_write_enable is
            << signal .tb_pluck_mode.dut.state_ram.write_enable : std_logic >>;
        alias ram_write_address is
            << signal .tb_pluck_mode.dut.state_ram.write_address :
               natural range 0 to 31 >>;
        alias ram_write_data is
            << signal .tb_pluck_mode.dut.state_ram.write_data : voice_word_t >>;
        procedure run_samples(
            constant count : in natural;
            peak : out natural;
            trigger_count : out natural;
            word0 : out voice_word_t
        ) is
            variable value : integer;
        begin
            peak := 0;
            trigger_count := 0;
            word0 := (others => '0');
            for sample in 0 to count-1 loop
                wait until falling_edge(clk);
                sample_tick <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                sample_tick <= '0';
                for stage in 0 to 399 loop
                    wait until rising_edge(clk);
                    if allocator_trigger(0) = '1' then
                        trigger_count := trigger_count + 1;
                    end if;
                    if ram_write_enable = '1' and ram_write_address = 0 then
                        word0 := ram_write_data;
                    end if;
                    value := abs(to_integer(mixed_sample));
                    if value > peak then
                        peak := value;
                    end if;
                end loop;
            end loop;
        end procedure;

        variable attack_peak, decay_peak, tail_peak : natural;
        variable attack_triggers, decay_triggers, tail_triggers : natural;
        variable attack_word0, decay_word0, tail_word0 : voice_word_t;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 5*CLK_PERIOD;

        sensor_on(0) <= '1';
        sensor_levels(0) <= to_unsigned(1023, 10);
        run_samples(1000, attack_peak, attack_triggers, attack_word0);
        run_samples(6500, decay_peak, decay_triggers, decay_word0);
        run_samples(2500, tail_peak, tail_triggers, tail_word0);

        report "Pluck mode peaks: attack=" & integer'image(attack_peak) &
               " decay=" & integer'image(decay_peak) &
               " tail=" & integer'image(tail_peak) &
               " active=" & integer'image(active_count) &
               " active_mask=" & integer'image(to_integer(unsigned(allocator_active))) &
               " attack_triggers=" & integer'image(attack_triggers) &
               " decay_triggers=" & integer'image(decay_triggers) &
               " tail_triggers=" & integer'image(tail_triggers) &
               " env0=" & integer'image(to_integer(
                   unsigned(tail_word0(75 downto 64)))) &
               " state0=" & integer'image(to_integer(
                   unsigned(tail_word0(94 downto 92))))
            severity note;
        assert attack_peak > 100
            report "Pluck mode did not produce an attack"
            severity failure;
        assert tail_peak = 0
            report "Pluck mode did not decay to silence while the key stayed held"
            severity failure;

        report "tb_pluck_mode passed" severity note;
        wait;
    end process;
end architecture;
