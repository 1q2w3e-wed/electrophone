library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Human-readable JDY-31 command parser. It never touches audio directly.
entity command_parser is
    port (
        clk, rst_n : in std_logic;
        rx_data : in std_logic_vector(7 downto 0);
        rx_valid : in std_logic;
        tx_ready : in std_logic;
        tx_data : out std_logic_vector(7 downto 0);
        tx_valid : out std_logic;

        map_write_en : out std_logic;
        map_channel : out natural range 0 to 7;
        map_note : out natural range 0 to 7;

        score_clear : out std_logic;
        append_en : out std_logic;
        append_data : out std_logic_vector(31 downto 0);
        play_score : out std_logic;
        stop_all : out std_logic;
        rec_start : out std_logic;
        rec_stop : out std_logic;
        rec_play : out std_logic;

        key_down : out std_logic;
        key_up : out std_logic;
        key_all_up : out std_logic;
        key_note : out natural range 0 to 7;
        key_velocity : out natural range 0 to 31;
        key_tone : out natural range 0 to 3;
        key_effect : out natural range 0 to 3;
        dump_start : out std_logic;
        test_on : out std_logic;
        test_off : out std_logic;

        playback_active : in std_logic;
        recording_active : in std_logic;
        key_state : in std_logic_vector(7 downto 0);
        activity : out std_logic;
        event_count : in natural range 0 to 1024;
        event_full : in std_logic
    );
end entity;

architecture rtl of command_parser is
    constant LINE_DEPTH : positive := 32;
    type line_buffer_t is array (0 to LINE_DEPTH-1) of
        std_logic_vector(7 downto 0);
    type field_array_t is array (0 to 7) of natural range 0 to 4095;
    type command_t is (
        CMD_NONE, CMD_MAP, CMD_NOTE, CMD_KEY_DOWN, CMD_KEY_UP
    );
    type response_t is (
        RESP_NONE, RESP_PONG, RESP_OK, RESP_ERR, RESP_FULL,
        RESP_VERSION_3, RESP_KEYSTATE
    );

    constant PONG_TEXT : string := "PONG";
    constant OK_TEXT : string := "OK";
    constant ERR_TEXT : string := "ERR";
    constant FULL_TEXT : string := "FULL";
    constant VERSION_TEXT : string := "VERSION 3";

    signal line_buffer : line_buffer_t := (others => (others => '0'));
    signal line_length : natural range 0 to LINE_DEPTH := 0;
    signal line_overflow : std_logic := '0';

    signal parsing : std_logic := '0';
    signal command : command_t := CMD_NONE;
    signal command_length : natural range 0 to LINE_DEPTH := 0;
    signal fields : field_array_t := (others => 0);
    signal field_count : natural range 0 to 8 := 0;
    signal parse_cursor : natural range 0 to LINE_DEPTH := 0;
    signal parse_number : natural range 0 to 4095 := 0;
    signal digit_seen : std_logic := '0';
    signal finish_pending : std_logic := '0';

    signal map_emit_count : natural range 0 to 8 := 0;
    signal map_emit_index : natural range 0 to 7 := 0;
    signal map_waiting_response : std_logic := '0';

    signal response_kind : response_t := RESP_NONE;
    signal response_index : natural range 0 to 15 := 0;
    signal response_sending : std_logic := '0';
    signal response_tx_hold : std_logic := '0';

    function to_upper(value : std_logic_vector(7 downto 0)) return character is
        variable code : natural;
    begin
        code := to_integer(unsigned(value));
        if code >= character'pos('a') and code <= character'pos('z') then
            code := code - 32;
        end if;
        if code < 0 or code > 255 then
            return '?';
        end if;
        return character'val(code);
    end function;

    function matches(
        constant line : line_buffer_t;
        constant start_index : natural;
        constant text : string
    ) return boolean is
    begin
        for offset in 0 to text'length-1 loop
            if start_index + offset > LINE_DEPTH-1 then
                return false;
            end if;
            if to_upper(line(start_index + offset)) /=
               text(text'low + offset) then
                return false;
            end if;
        end loop;
        return true;
    end function;

    function response_length(kind : response_t) return natural is
    begin
        case kind is
            when RESP_PONG => return PONG_TEXT'length + 2;
            when RESP_OK => return OK_TEXT'length + 2;
            when RESP_ERR => return ERR_TEXT'length + 2;
            when RESP_FULL => return FULL_TEXT'length + 2;
            when RESP_VERSION_3 => return VERSION_TEXT'length + 2;
            when RESP_KEYSTATE => return 7;
            when others => return 0;
        end case;
    end function;

    function hex_character(value : natural range 0 to 15) return character is
    begin
        if value < 10 then
            return character'val(character'pos('0') + value);
        else
            return character'val(character'pos('A') + value - 10);
        end if;
    end function;

    function response_character(
        kind : response_t;
        index : natural;
        state_value : std_logic_vector(7 downto 0)
    ) return character is
        variable text_length : natural;
    begin
        case kind is
            when RESP_PONG => text_length := PONG_TEXT'length;
            when RESP_OK => text_length := OK_TEXT'length;
            when RESP_ERR => text_length := ERR_TEXT'length;
            when RESP_FULL => text_length := FULL_TEXT'length;
            when RESP_VERSION_3 => text_length := VERSION_TEXT'length;
            when RESP_KEYSTATE => text_length := 5;
            when others => return '?';
        end case;
        if index < text_length then
            case kind is
                when RESP_PONG =>
                    return PONG_TEXT(PONG_TEXT'low + index);
                when RESP_OK =>
                    return OK_TEXT(OK_TEXT'low + index);
                when RESP_ERR =>
                    return ERR_TEXT(ERR_TEXT'low + index);
                when RESP_FULL =>
                    return FULL_TEXT(FULL_TEXT'low + index);
                when RESP_VERSION_3 =>
                    return VERSION_TEXT(VERSION_TEXT'low + index);
                when RESP_KEYSTATE =>
                    case index is
                        when 0 => return 'K';
                        when 1 => return 'S';
                        when 2 => return ' ';
                        when 3 => return hex_character(
                            to_integer(unsigned(state_value(7 downto 4))));
                        when 4 => return hex_character(
                            to_integer(unsigned(state_value(3 downto 0))));
                        when others => return '?';
                    end case;
                when others =>
                    return '?';
            end case;
        elsif index = text_length then
            return CR;
        else
            return LF;
        end if;
    end function;

    function is_digit(value : std_logic_vector(7 downto 0)) return boolean is
    begin
        return value >= x"30" and value <= x"39";
    end function;

    function pack_note_event(
        constant values : field_array_t
    ) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(values(0), 12)) &
               std_logic_vector(to_unsigned(values(1) / 10, 8)) &
               std_logic_vector(to_unsigned(values(2), 3)) &
               std_logic_vector(to_unsigned(values(3), 5)) &
               std_logic_vector(to_unsigned(values(4), 2)) &
               std_logic_vector(to_unsigned(values(5), 2));
    end function;
begin
    process(clk)
        variable byte_v : std_logic_vector(7 downto 0);
        variable digit_v : natural;
        variable next_number_v : natural;
        variable valid_fields_v : boolean;
    begin
        if rising_edge(clk) then
            tx_valid <= '0';
            map_write_en <= '0';
            score_clear <= '0';
            append_en <= '0';
            play_score <= '0';
            stop_all <= '0';
            rec_start <= '0';
            rec_stop <= '0';
            rec_play <= '0';
            key_down <= '0';
            key_up <= '0';
            key_all_up <= '0';
            dump_start <= '0';
            test_on <= '0';
            test_off <= '0';
            activity <= '0';

            if rst_n = '0' then
                line_length <= 0;
                line_overflow <= '0';
                parsing <= '0';
                command <= CMD_NONE;
                command_length <= 0;
                fields <= (others => 0);
                field_count <= 0;
                parse_cursor <= 0;
                parse_number <= 0;
                digit_seen <= '0';
                finish_pending <= '0';
                map_emit_count <= 0;
                map_emit_index <= 0;
                map_waiting_response <= '0';
                response_kind <= RESP_NONE;
                response_index <= 0;
                response_sending <= '0';
                response_tx_hold <= '0';
                key_note <= 0;
                key_velocity <= 0;
                key_tone <= 0;
                key_effect <= 0;
                tx_data <= (others => '0');
            else
                -- One response byte at a time; uart_tx supplies back-pressure.
                if response_sending = '1' then
                    if response_tx_hold = '1' then
                        if tx_ready = '0' then
                            response_tx_hold <= '0';
                        end if;
                    elsif tx_ready = '1' and
                          response_index < response_length(response_kind) then
                        tx_data <= std_logic_vector(to_unsigned(
                            character'pos(response_character(
                                response_kind, response_index, key_state)), 8));
                        tx_valid <= '1';
                        response_index <= response_index + 1;
                        response_tx_hold <= '1';
                    elsif tx_ready = '1' then
                        response_sending <= '0';
                    end if;
                end if;

                if map_emit_count /= 0 then
                    map_write_en <= '1';
                    map_channel <= map_emit_index;
                    map_note <= fields(map_emit_index);
                    if map_emit_count = 1 then
                        map_emit_count <= 0;
                        map_waiting_response <= '0';
                        response_kind <= RESP_OK;
                        response_index <= 0;
                        response_sending <= '1';
                    else
                        map_emit_count <= map_emit_count - 1;
                        map_emit_index <= map_emit_index + 1;
                    end if;
                end if;

                if finish_pending = '1' then
                    finish_pending <= '0';
                    parsing <= '0';
                    if command = CMD_MAP then
                        valid_fields_v := field_count = 8;
                        for index in 0 to 7 loop
                            if fields(index) > 7 then
                                valid_fields_v := false;
                            end if;
                        end loop;
                        if valid_fields_v then
                            map_emit_count <= 8;
                            map_emit_index <= 0;
                            map_waiting_response <= '1';
                        else
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        end if;
                    elsif command = CMD_NOTE then
                        valid_fields_v :=
                            field_count = 6 and
                            fields(0) <= 4095 and
                            fields(1) >= 10 and fields(1) <= 2550 and
                            fields(1) mod 10 = 0 and
                            fields(2) <= 7 and fields(3) <= 31 and
                            fields(4) <= 3 and fields(5) <= 3;
                        if not valid_fields_v then
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        elsif event_full = '1' then
                            response_kind <= RESP_FULL;
                            response_index <= 0;
                            response_sending <= '1';
                        else
                            append_en <= '1';
                            append_data <= pack_note_event(fields);
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                        end if;
                    elsif command = CMD_KEY_DOWN then
                        valid_fields_v :=
                            field_count = 4 and
                            fields(0) <= 7 and fields(1) <= 31 and
                            fields(2) <= 3 and fields(3) <= 3;
                        if valid_fields_v then
                            key_down <= '1';
                            key_note <= fields(0);
                            key_velocity <= fields(1);
                            key_tone <= fields(2);
                            key_effect <= fields(3);
                            response_kind <= RESP_OK;
                        else
                            response_kind <= RESP_ERR;
                        end if;
                        response_index <= 0;
                        response_sending <= '1';
                    elsif command = CMD_KEY_UP then
                        valid_fields_v := field_count = 1 and fields(0) <= 7;
                        if valid_fields_v then
                            key_up <= '1';
                            key_note <= fields(0);
                            response_kind <= RESP_OK;
                        else
                            response_kind <= RESP_ERR;
                        end if;
                        response_index <= 0;
                        response_sending <= '1';
                    else
                        response_kind <= RESP_ERR;
                        response_index <= 0;
                        response_sending <= '1';
                    end if;
                elsif parsing = '1' then
                    if parse_cursor = command_length then
                        if digit_seen = '0' then
                            parsing <= '0';
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        else
                            fields(field_count) <= parse_number;
                            field_count <= field_count + 1;
                            finish_pending <= '1';
                        end if;
                    else
                        byte_v := line_buffer(parse_cursor);
                        parse_cursor <= parse_cursor + 1;
                        if is_digit(byte_v) then
                            digit_v := to_integer(unsigned(byte_v)) - 48;
                            if parse_number > (4095 - digit_v) / 10 then
                                parsing <= '0';
                                response_kind <= RESP_ERR;
                                response_index <= 0;
                                response_sending <= '1';
                            else
                                next_number_v := parse_number * 10 + digit_v;
                                parse_number <= next_number_v;
                                digit_seen <= '1';
                            end if;
                        elsif byte_v = x"2C" then
                            if digit_seen = '0' or field_count = 7 then
                                parsing <= '0';
                                response_kind <= RESP_ERR;
                                response_index <= 0;
                                response_sending <= '1';
                            else
                                fields(field_count) <= parse_number;
                                field_count <= field_count + 1;
                                parse_number <= 0;
                                digit_seen <= '0';
                            end if;
                        else
                            parsing <= '0';
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        end if;
                    end if;
                elsif rx_valid = '1' then
                    if rx_data = x"0D" then
                        null;
                    elsif rx_data = x"0A" then
                        if line_overflow = '1' or line_length = 0 then
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        elsif line_length = 4 and
                              matches(line_buffer, 0, "PING") then
                            response_kind <= RESP_PONG;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 4 and
                              matches(line_buffer, 0, "STOP") then
                            stop_all <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 11 and
                              matches(line_buffer, 0, "SCORE CLEAR") then
                            score_clear <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 10 and
                              matches(line_buffer, 0, "PLAY SCORE") then
                            play_score <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 7 and
                              matches(line_buffer, 0, "TEST 32") then
                            test_on <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 8 and
                              matches(line_buffer, 0, "TEST OFF") then
                            test_off <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 9 and
                              matches(line_buffer, 0, "REC START") then
                            rec_start <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 8 and
                              matches(line_buffer, 0, "REC STOP") then
                            rec_stop <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 8 and
                              matches(line_buffer, 0, "REC PLAY") then
                            rec_play <= '1';
                            play_score <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 7 and
                              matches(line_buffer, 0, "VERSION") then
                            response_kind <= RESP_VERSION_3;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 8 and
                              matches(line_buffer, 0, "KEYSTATE") then
                            response_kind <= RESP_KEYSTATE;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 10 and
                              matches(line_buffer, 0, "KEY ALL UP") then
                            key_all_up <= '1';
                            response_kind <= RESP_OK;
                            response_index <= 0;
                            response_sending <= '1';
                            activity <= '1';
                        elsif line_length = 8 and
                              matches(line_buffer, 0, "REC DUMP") then
                            if playback_active = '1' or recording_active = '1' then
                                response_kind <= RESP_ERR;
                                response_index <= 0;
                                response_sending <= '1';
                            else
                                dump_start <= '1';
                            end if;
                            activity <= '1';
                        elsif line_length > 5 and
                              matches(line_buffer, 0, "NOTE ") then
                            command <= CMD_NOTE;
                            command_length <= line_length;
                            fields <= (others => 0);
                            field_count <= 0;
                            parse_cursor <= 5;
                            parse_number <= 0;
                            digit_seen <= '0';
                            parsing <= '1';
                        elsif line_length > 9 and
                              matches(line_buffer, 0, "KEY DOWN ") then
                            command <= CMD_KEY_DOWN;
                            command_length <= line_length;
                            fields <= (others => 0);
                            field_count <= 0;
                            parse_cursor <= 9;
                            parse_number <= 0;
                            digit_seen <= '0';
                            parsing <= '1';
                        elsif line_length > 7 and
                              matches(line_buffer, 0, "KEY UP ") then
                            command <= CMD_KEY_UP;
                            command_length <= line_length;
                            fields <= (others => 0);
                            field_count <= 0;
                            parse_cursor <= 7;
                            parse_number <= 0;
                            digit_seen <= '0';
                            parsing <= '1';
                        elsif line_length > 4 and
                              matches(line_buffer, 0, "MAP ") then
                            command <= CMD_MAP;
                            command_length <= line_length;
                            fields <= (others => 0);
                            field_count <= 0;
                            parse_cursor <= 4;
                            parse_number <= 0;
                            digit_seen <= '0';
                            parsing <= '1';
                        else
                            response_kind <= RESP_ERR;
                            response_index <= 0;
                            response_sending <= '1';
                        end if;
                        line_length <= 0;
                        line_overflow <= '0';
                    elsif line_overflow = '1' then
                        null;
                    elsif line_length = LINE_DEPTH then
                        line_overflow <= '1';
                    else
                        line_buffer(line_length) <= rx_data;
                        line_length <= line_length + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
