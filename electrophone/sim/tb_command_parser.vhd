library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_command_parser is
end entity;

architecture sim of tb_command_parser is
    constant CLK_PERIOD : time := 20 ns;
    type byte_array_t is array (0 to 511) of std_logic_vector(7 downto 0);
    type natural_array_t is array (0 to 7) of natural;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal rx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_valid : std_logic := '0';
    signal tx_ready : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal map_write_en : std_logic;
    signal map_channel : natural range 0 to 7;
    signal map_note : natural range 0 to 7;
    signal score_clear, append_en : std_logic;
    signal append_data : std_logic_vector(31 downto 0);
    signal play_score, stop_all, rec_start, rec_stop, rec_play : std_logic;
    signal key_down, key_up, key_all_up, dump_start : std_logic;
    signal test_on, test_off : std_logic;
    signal key_note : natural range 0 to 7;
    signal key_velocity : natural range 0 to 31;
    signal key_tone, key_effect : natural range 0 to 3;
    signal activity : std_logic;
    signal event_count : natural range 0 to 1024 := 0;
    signal event_full : std_logic := '0';
    signal playback_active : std_logic := '0';
    signal recording_active : std_logic := '0';
    signal key_state : std_logic_vector(7 downto 0) := "10100101";

    signal response_bytes : byte_array_t := (others => (others => '0'));
    signal response_count : natural := 0;
    signal map_values : natural_array_t := (others => 0);
    signal clear_count, append_count, play_count, stop_count : natural := 0;
    signal rec_start_count, rec_stop_count, rec_play_count : natural := 0;
    signal key_down_count, key_up_count, key_all_up_count : natural := 0;
    signal dump_start_count : natural := 0;
    signal test_on_count, test_off_count : natural := 0;
    signal last_key_note : natural range 0 to 7 := 0;
    signal last_key_velocity : natural range 0 to 31 := 0;
    signal last_key_tone, last_key_effect : natural range 0 to 3 := 0;
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

    dut: entity work.command_parser
        port map (
            clk => clk, rst_n => rst_n,
            rx_data => rx_data, rx_valid => rx_valid,
            tx_ready => tx_ready,
            tx_data => tx_data, tx_valid => tx_valid,
            map_write_en => map_write_en,
            map_channel => map_channel,
            map_note => map_note,
            score_clear => score_clear,
            append_en => append_en,
            append_data => append_data,
            play_score => play_score,
            stop_all => stop_all,
            rec_start => rec_start,
            rec_stop => rec_stop,
            rec_play => rec_play,
            key_down => key_down,
            key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            dump_start => dump_start,
            test_on => test_on,
            test_off => test_off,
            playback_active => playback_active,
            recording_active => recording_active,
            key_state => key_state,
            activity => activity,
            event_count => event_count,
            event_full => event_full
        );

    monitor: process(clk)
    begin
        if rising_edge(clk) then
            if tx_valid = '1' and tx_ready = '1' then
                response_bytes(response_count) <= tx_data;
                response_count <= response_count + 1;
            end if;
            if map_write_en = '1' then
                map_values(map_channel) <= map_note;
            end if;
            if score_clear = '1' then clear_count <= clear_count + 1; end if;
            if append_en = '1' then append_count <= append_count + 1; end if;
            if play_score = '1' then play_count <= play_count + 1; end if;
            if stop_all = '1' then stop_count <= stop_count + 1; end if;
            if rec_start = '1' then rec_start_count <= rec_start_count + 1; end if;
            if rec_stop = '1' then rec_stop_count <= rec_stop_count + 1; end if;
            if rec_play = '1' then rec_play_count <= rec_play_count + 1; end if;
            if key_down = '1' then
                key_down_count <= key_down_count + 1;
                last_key_note <= key_note;
                last_key_velocity <= key_velocity;
                last_key_tone <= key_tone;
                last_key_effect <= key_effect;
            end if;
            if key_up = '1' then key_up_count <= key_up_count + 1; end if;
            if key_all_up = '1' then key_all_up_count <= key_all_up_count + 1; end if;
            if dump_start = '1' then dump_start_count <= dump_start_count + 1; end if;
            if test_on = '1' then test_on_count <= test_on_count + 1; end if;
            if test_off = '1' then test_off_count <= test_off_count + 1; end if;
        end if;
    end process;

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
                feed_byte(std_logic_vector(to_unsigned(character'pos(text(index)), 8)));
            end loop;
        end procedure;

        procedure expect_response(constant text : string) is
            variable start_index : natural;
        begin
            start_index := response_count;
            wait until response_count >= start_index + text'length + 2 for 20 us;
            assert response_count >= start_index + text'length + 2
                report "Command response timed out: " & text
                severity failure;
            for index in text'range loop
                assert response_bytes(start_index + index - text'low) =
                       std_logic_vector(to_unsigned(character'pos(text(index)), 8))
                    report "Unexpected command response, expected " & text &
                           ", received code " &
                           integer'image(to_integer(unsigned(
                               response_bytes(start_index + index - text'low))))
                    severity failure;
            end loop;
            assert response_bytes(start_index + text'length) = x"0D" and
                   response_bytes(start_index + text'length + 1) = x"0A"
                report "Command response is not terminated by CRLF"
                severity failure;
        end procedure;

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

        variable maps_before : natural_array_t;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        send_text("ping" & LF);
        expect_response("PONG");

        send_text("VERSION" & CR & LF);
        expect_response("VERSION 3");

        send_text("KEYSTATE" & LF);
        expect_response("KS A5");

        send_text("MAP 7,6,5,4,3,2,1,0" & CR & LF);
        expect_response("OK");
        for channel in 0 to 7 loop
            assert map_values(channel) = 7-channel
                report "MAP did not update every channel"
                severity failure;
        end loop;

        maps_before := map_values;
        send_text("MAP 0,1,2,3,4,5,6,8" & LF);
        expect_response("ERR");
        wait for 100 ns;
        assert map_values = maps_before
            report "Invalid MAP changed key assignment"
            severity failure;

        send_text("NOTE 12,340,5,17,2,3" & LF);
        expect_response("OK");
        assert append_count = 1
            report "Valid NOTE did not append exactly one event"
            severity failure;
        assert append_data = pack_event(12, 34, 5, 17, 2, 3)
            report "NOTE packed fields are incorrect"
            severity failure;

        send_text("NOTE 12,345,5,17,2,3" & LF);
        expect_response("ERR");
        assert append_count = 1
            report "Invalid NOTE appended an event"
            severity failure;

        event_full <= '1';
        send_text("NOTE 0,10,0,1,0,0" & LF);
        expect_response("FULL");
        assert append_count = 1
            report "Full event RAM appended a NOTE"
            severity failure;
        event_full <= '0';

        send_text("SCORE CLEAR" & LF);
        expect_response("OK");
        assert clear_count = 1
            report "SCORE CLEAR did not request one RAM clear"
            severity failure;

        send_text("PLAY SCORE" & LF);
        expect_response("OK");
        assert play_count = 1 report "PLAY SCORE control missing" severity failure;

        send_text("STOP" & LF);
        expect_response("OK");
        assert stop_count = 1 report "STOP control missing" severity failure;

        send_text("TEST 32" & LF);
        expect_response("OK");
        assert test_on_count = 1
            report "TEST 32 control missing" severity failure;

        send_text("TEST OFF" & LF);
        expect_response("OK");
        assert test_off_count = 1
            report "TEST OFF control missing" severity failure;

        send_text("REC START" & LF);
        expect_response("OK");
        assert rec_start_count = 1 and clear_count = 1
            report "REC START incorrectly emitted SCORE CLEAR"
            severity failure;

        send_text("REC STOP" & LF);
        expect_response("OK");
        assert rec_stop_count = 1 report "REC STOP control missing" severity failure;

        send_text("REC PLAY" & LF);
        expect_response("OK");
        assert rec_play_count = 1 report "REC PLAY control missing" severity failure;

        send_text("KEY DOWN 6,27,3,1" & LF);
        expect_response("OK");
        assert key_down_count = 1 and last_key_note = 6 and
               last_key_velocity = 27 and last_key_tone = 3 and
               last_key_effect = 1
            report "KEY DOWN fields were not parsed correctly"
            severity failure;

        send_text("KEY DOWN 8,20,0,0" & LF);
        expect_response("ERR");
        assert key_down_count = 1
            report "Invalid KEY DOWN changed remote input"
            severity failure;

        send_text("KEY UP 6" & LF);
        expect_response("OK");
        assert key_up_count = 1 report "KEY UP control missing" severity failure;

        send_text("KEY ALL UP" & LF);
        expect_response("OK");
        assert key_all_up_count = 1
            report "KEY ALL UP control missing"
            severity failure;

        recording_active <= '1';
        send_text("REC DUMP" & LF);
        expect_response("ERR");
        assert dump_start_count = 0
            report "REC DUMP started while recording"
            severity failure;
        recording_active <= '0';

        playback_active <= '1';
        send_text("REC DUMP" & LF);
        expect_response("ERR");
        assert dump_start_count = 0
            report "REC DUMP started while playback was active"
            severity failure;
        playback_active <= '0';

        send_text("REC DUMP" & LF);
        wait for 100 ns;
        assert dump_start_count = 1
            report "REC DUMP did not request the event uploader"
            severity failure;

        send_text("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" & LF);
        expect_response("ERR");

        report "tb_command_parser passed" severity note;
        stop;
        wait;
    end process;
end architecture;
