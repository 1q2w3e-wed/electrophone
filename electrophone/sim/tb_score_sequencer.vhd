library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use std.env.all;

entity tb_score_sequencer is
end entity;

architecture sim of tb_score_sequencer is
    constant CLK_PERIOD : time := 20 ns;
    constant CAPACITY : positive := 1024;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal ms_tick : std_logic := '0';
    signal play_start, stop_play : std_logic := '0';
    signal clear, append_en : std_logic := '0';
    signal append_data : std_logic_vector(31 downto 0) := (others => '0');
    signal event_count : natural range 0 to CAPACITY;
    signal full : std_logic;
    signal read_index : natural range 0 to CAPACITY-1;
    signal read_data : std_logic_vector(31 downto 0);
    signal virtual_on : std_logic_vector(7 downto 0);
    signal virtual_levels : sensor_array_t;
    signal play_tone : natural range 0 to 3;
    signal play_effect : natural range 0 to 3;
    signal play_active, busy : std_logic;

    function pack_event(
        constant delta_ms, duration_units, note, velocity, tone, effect
        : natural
    ) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(delta_ms, 12)) &
               std_logic_vector(to_unsigned(duration_units, 8)) &
               std_logic_vector(to_unsigned(note, 3)) &
               std_logic_vector(to_unsigned(velocity, 5)) &
               std_logic_vector(to_unsigned(tone, 2)) &
               std_logic_vector(to_unsigned(effect, 2));
    end function;
begin
    clk <= not clk after CLK_PERIOD/2;

    events: entity work.score_event_ram
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            clear => clear,
            append_en => append_en,
            append_data => append_data,
            update_en => '0',
            update_index => 0,
            update_duration => (others => '0'),
            update_velocity => (others => '0'),
            read_index => read_index,
            read_data => read_data,
            event_count => event_count,
            full => full
        );

    dut: entity work.score_sequencer
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            ms_tick => ms_tick,
            play_start => play_start,
            stop => stop_play,
            event_count => event_count,
            read_index => read_index,
            read_data => read_data,
            virtual_on => virtual_on,
            virtual_levels => virtual_levels,
            play_tone => play_tone,
            play_effect => play_effect,
            play_active => play_active,
            busy => busy
        );

    stimulus: process
        procedure append_event(
            constant delta_ms, duration_units, note, velocity, tone, effect
            : natural
        ) is
        begin
            wait until falling_edge(clk);
            append_data <= pack_event(
                delta_ms, duration_units, note, velocity, tone, effect);
            append_en <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            append_en <= '0';
        end procedure;

        procedure pulse_ms(constant count : natural) is
        begin
            for tick in 1 to count loop
                wait until falling_edge(clk);
                ms_tick <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                ms_tick <= '0';
                for cycle in 1 to 4 loop
                    wait until rising_edge(clk);
                end loop;
            end loop;
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        clear <= '0';

        append_event(0, 10, 0, 8, 1, 2);
        append_event(20, 5, 2, 16, 3, 0);
        append_event(0, 5, 4, 31, 3, 0);
        assert event_count = 3 report "Sequencer test events missing" severity failure;

        play_start <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        play_start <= '0';
        wait until virtual_on(0) = '1' for 5 us;
        assert virtual_on(0) = '1'
            report "Zero-delta event did not start immediately"
            severity failure;
        assert play_active = '1' and busy = '1'
            report "Playback state did not become active"
            severity failure;
        assert virtual_levels(0) = 8*32
            report "Velocity was not converted to pressure level"
            severity failure;
        assert play_tone = 1 and play_effect = 2
            report "Event timbre/effect were not exposed"
            severity failure;

        pulse_ms(21);
        wait until virtual_on(4) = '1' for 1 us;
        assert virtual_on(2) = '1' and virtual_on(4) = '1'
            report "Delayed note or zero-delta chord note did not start: " &
                   integer'image(to_integer(unsigned(virtual_on)))
            severity failure;
        assert virtual_on(0) = '1'
            report "Earlier duration ended too early"
            severity failure;

        pulse_ms(80);
        assert virtual_on = "00000000"
            report "Completed score did not release all virtual notes"
            severity failure;
        assert play_active = '0' and busy = '0'
            report "Completed score did not become idle"
            severity failure;

        play_start <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        play_start <= '0';
        wait until virtual_on(0) = '1' for 5 us;
        stop_play <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        stop_play <= '0';
        assert virtual_on = "00000000" and play_active = '0'
            report "STOP did not release virtual notes"
            severity failure;

        report "tb_score_sequencer passed" severity note;
        stop;
        wait;
    end process;

    timeout: process
    begin
        wait for 2 ms;
        assert false report "Score sequencer test timeout" severity failure;
        wait;
    end process;
end architecture;
