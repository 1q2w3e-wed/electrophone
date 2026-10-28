library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use std.env.all;

entity tb_bluetooth_session is
end entity;

architecture sim of tb_bluetooth_session is
    constant CLK_PERIOD : time := 20 ns;
    constant CAPACITY : positive := 1024;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal rx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid : std_logic := '0';
    signal tx_ready : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;

    signal command_clear, command_append : std_logic;
    signal command_append_data : std_logic_vector(31 downto 0);
    signal command_play, command_stop : std_logic;
    signal command_rec_start, command_rec_stop, command_rec_play : std_logic;
    signal key_down, key_up, key_all_up, dump_start : std_logic;
    signal key_note : natural range 0 to 7;
    signal key_velocity : natural range 0 to 31;
    signal key_tone, key_effect : natural range 0 to 3;
    signal event_clear, event_append_en, event_update_en : std_logic;
    signal event_append_data : std_logic_vector(31 downto 0);
    signal event_update_index : natural range 0 to CAPACITY-1;
    signal event_update_duration : std_logic_vector(7 downto 0);
    signal event_update_velocity : std_logic_vector(4 downto 0);
    signal event_count : natural range 0 to CAPACITY;
    signal event_full : std_logic;
    signal recorder_append, recorder_update_en : std_logic;
    signal recorder_append_data : std_logic_vector(31 downto 0);
    signal recorder_update_index : natural range 0 to CAPACITY-1;
    signal recorder_update_duration : std_logic_vector(7 downto 0);
    signal recorder_update_velocity : std_logic_vector(4 downto 0);
    signal recorder_stop : std_logic;

    signal ms_tick : std_logic := '0';
    signal physical_on : std_logic_vector(7 downto 0) := (others => '0');
    signal physical_levels : sensor_array_t := (others => (others => '0'));
    signal remote_on : std_logic_vector(7 downto 0);
    signal remote_levels : sensor_array_t;
    signal remote_tones : tone_array_t;
    signal remote_effects : effect_array_t;
    signal remote_last_tone : natural range 0 to 3;
    signal remote_last_effect : natural range 0 to 3;
    signal effective_on : std_logic_vector(7 downto 0);
    signal effective_levels : sensor_array_t;
    signal effective_tones : tone_array_t;
    signal effective_effects : effect_array_t;
    signal selected_tone : natural range 0 to 3;
    signal selected_effect : natural range 0 to 3;
    signal recording : std_logic;
    signal read_index : natural range 0 to CAPACITY-1 := 0;
    signal read_data : std_logic_vector(31 downto 0);
    signal remote_clear : std_logic;
begin
    clk <= not clk after CLK_PERIOD/2;

    tx_flow_control: process(clk)
    begin
        if rising_edge(clk) then
            if tx_valid = '1' then
                tx_ready <= '0';
            else
                tx_ready <= '1';
            end if;
        end if;
    end process;

    parser: entity work.command_parser
        port map (
            clk => clk, rst_n => rst_n,
            rx_data => rx_data, rx_valid => rx_valid,
            tx_ready => tx_ready,
            tx_data => tx_data, tx_valid => tx_valid,
            map_write_en => open,
            map_channel => open,
            map_note => open,
            score_clear => command_clear,
            append_en => command_append,
            append_data => command_append_data,
            play_score => command_play,
            stop_all => command_stop,
            rec_start => command_rec_start,
            rec_stop => command_rec_stop,
            rec_play => command_rec_play,
            key_down => key_down,
            key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            dump_start => dump_start,
            test_on => open,
            test_off => open,
            playback_active => '0',
            recording_active => recording,
            key_state => "00000000",
            activity => open,
            event_count => event_count,
            event_full => event_full
        );

    remote_clear <= command_stop or command_play or
                    command_rec_play or command_clear;

    remote: entity work.remote_input
        port map (
            clk => clk, rst_n => rst_n,
            key_down => key_down, key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            clear => remote_clear,
            on_o => remote_on, levels_o => remote_levels,
            tones_o => remote_tones, effects_o => remote_effects,
            last_tone_o => remote_last_tone,
            last_effect_o => remote_last_effect
        );

    mixer: entity work.performance_mixer
        port map (
            mapped_on => physical_on,
            mapped_levels => physical_levels,
            remote_on => remote_on, remote_levels => remote_levels,
            remote_tones => remote_tones, remote_effects => remote_effects,
            remote_last_tone => remote_last_tone,
            remote_last_effect => remote_last_effect,
            ui_tone => 1, ui_effect => 0,
            playback_active => '0',
            virtual_on => "00000000",
            virtual_levels => (others => (others => '0')),
            playback_tone => 0, playback_effect => 0,
            effective_on => effective_on,
            effective_levels => effective_levels,
            effective_tones => effective_tones,
            effective_effects => effective_effects,
            selected_tone => selected_tone,
            selected_effect => selected_effect
        );

    event_clear <= command_clear or command_rec_start;
    event_append_en <= command_append or recorder_append;
    event_append_data <= recorder_append_data when recorder_append = '1'
                         else command_append_data;
    event_update_en <= recorder_update_en;
    event_update_index <= recorder_update_index;
    event_update_duration <= recorder_update_duration;
    event_update_velocity <= recorder_update_velocity;
    recorder_stop <= command_rec_stop or command_rec_play or
                     command_play or command_stop or command_clear;

    events: entity work.score_event_ram
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            clear => event_clear,
            append_en => event_append_en,
            append_data => event_append_data,
            update_en => event_update_en,
            update_index => event_update_index,
            update_duration => event_update_duration,
            update_velocity => event_update_velocity,
            read_index => read_index,
            read_data => read_data,
            event_count => event_count,
            full => event_full
        );

    recorder: entity work.score_recorder
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            ms_tick => ms_tick,
            start => command_rec_start,
            stop => recorder_stop,
            input_on => effective_on,
            input_levels => effective_levels,
            input_tones => effective_tones,
            input_effects => effective_effects,
            full => event_full,
            append_en => recorder_append,
            append_data => recorder_append_data,
            update_en => recorder_update_en,
            update_index => recorder_update_index,
            update_duration => recorder_update_duration,
            update_velocity => recorder_update_velocity,
            recording => recording
        );

    stimulus: process
        procedure feed_byte(constant value : std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(clk);
            rx_data <= value;
            rx_valid <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            rx_valid <= '0';
        end procedure;

        procedure send_text(constant text : string) is
        begin
            for index in text'range loop
                feed_byte(std_logic_vector(
                    to_unsigned(character'pos(text(index)), 8)));
            end loop;
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

        procedure read_event(
            constant index : natural;
            variable value : out std_logic_vector(31 downto 0)
        ) is
        begin
            wait until falling_edge(clk);
            read_index <= index;
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            value := read_data;
        end procedure;

        variable first_event, second_event : std_logic_vector(31 downto 0);
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        send_text("REC START" & CR & LF);
        wait for 2 us;
        assert recording = '1'
            report "REC START did not arm the performance recorder"
            severity failure;

        send_text("KEY DOWN 6,27,3,1" & CR & LF);
        wait for 1 us;
        assert remote_on = "01000000"
            report "KEY DOWN did not reach remote input"
            severity failure;
        pulse_ms(30);
        send_text("KEY UP 6" & CR & LF);
        wait for 1 us;
        assert remote_on = "00000000"
            report "KEY UP did not release remote note"
            severity failure;

        physical_levels(0) <= to_unsigned(640, 10);
        physical_on(0) <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        pulse_ms(10);
        physical_on(0) <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);

        send_text("REC STOP" & CR & LF);
        wait for 2 us;
        assert recording = '0'
            report "REC STOP did not stop the performance recorder"
            severity failure;
        assert event_count = 2
            report "Recorded performance did not create an event"
            severity failure;

        read_event(0, first_event);
        assert first_event(11 downto 9) = std_logic_vector(to_unsigned(6, 3))
            report "Remote note was not recorded" severity failure;
        assert first_event(8 downto 4) = std_logic_vector(to_unsigned(27, 5))
            report "Remote velocity was not recorded" severity failure;
        assert first_event(3 downto 2) = "11"
            report "Remote tone was not recorded" severity failure;
        assert first_event(1 downto 0) = "01"
            report "Remote effect was not recorded" severity failure;

        read_event(1, second_event);
        assert second_event(11 downto 9) = std_logic_vector(to_unsigned(0, 3))
            report "Physical note was not recorded after remote note"
            severity failure;

        report "tb_bluetooth_session passed" severity note;
        stop;
        wait;
    end process;
end architecture;
