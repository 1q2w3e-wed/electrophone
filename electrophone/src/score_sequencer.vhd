library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Turns packed score events into virtual pressure-key gates.
entity score_sequencer is
    generic (
        G_EVENT_CAPACITY : positive := 1024
    );
    port (
        clk, rst_n : in std_logic;
        ms_tick : in std_logic;
        play_start : in std_logic;
        stop : in std_logic;
        event_count : in natural range 0 to G_EVENT_CAPACITY;
        read_index : out natural range 0 to G_EVENT_CAPACITY-1;
        read_data : in std_logic_vector(31 downto 0);
        virtual_on : out std_logic_vector(7 downto 0);
        virtual_levels : out sensor_array_t;
        play_tone : out natural range 0 to 3;
        play_effect : out natural range 0 to 3;
        play_active : out std_logic;
        busy : out std_logic
    );
end entity;

architecture rtl of score_sequencer is
    type state_t is (
        STATE_IDLE, STATE_FETCH, STATE_LATCH_WAIT, STATE_LATCH,
        STATE_SCHEDULE,
        STATE_DELAY, STATE_ACTIVATE, STATE_WAIT_END
    );
    type remaining_array_t is array (0 to 7) of
        natural range 0 to 2550;

    signal state : state_t := STATE_IDLE;
    signal event_index : natural range 0 to G_EVENT_CAPACITY := 0;
    signal latched_event : std_logic_vector(31 downto 0) := (others => '0');
    signal delta_remaining : natural range 0 to 4095 := 0;
    signal virtual_on_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal virtual_levels_reg : sensor_array_t := (others => (others => '0'));
    signal remaining : remaining_array_t := (others => 0);
    signal tone_reg : natural range 0 to 3 := 0;
    signal effect_reg : natural range 0 to 3 := 0;
begin
    virtual_on <= virtual_on_reg;
    virtual_levels <= virtual_levels_reg;
    play_tone <= tone_reg;
    play_effect <= effect_reg;
    play_active <= '0' when state = STATE_IDLE else '1';
    busy <= '0' when state = STATE_IDLE else '1';

    process(clk)
        variable note_v : natural range 0 to 7;
        variable duration_v : natural range 0 to 2550;
        variable any_active_v : std_logic;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                state <= STATE_IDLE;
                event_index <= 0;
                latched_event <= (others => '0');
                delta_remaining <= 0;
                virtual_on_reg <= (others => '0');
                virtual_levels_reg <= (others => (others => '0'));
                remaining <= (others => 0);
                tone_reg <= 0;
                effect_reg <= 0;
                read_index <= 0;
            elsif stop = '1' then
                state <= STATE_IDLE;
                event_index <= 0;
                delta_remaining <= 0;
                virtual_on_reg <= (others => '0');
                virtual_levels_reg <= (others => (others => '0'));
                remaining <= (others => 0);
            else
                if ms_tick = '1' then
                    for note in 0 to 7 loop
                        if remaining(note) = 1 then
                            remaining(note) <= 0;
                            virtual_on_reg(note) <= '0';
                            virtual_levels_reg(note) <= (others => '0');
                        elsif remaining(note) > 1 then
                            remaining(note) <= remaining(note) - 1;
                        end if;
                    end loop;
                end if;

                if play_start = '1' then
                    virtual_on_reg <= (others => '0');
                    virtual_levels_reg <= (others => (others => '0'));
                    remaining <= (others => 0);
                    delta_remaining <= 0;
                    event_index <= 0;
                    if event_count = 0 then
                        state <= STATE_IDLE;
                    else
                        read_index <= 0;
                        state <= STATE_FETCH;
                    end if;
                else
                    case state is
                        when STATE_IDLE =>
                            null;
                        when STATE_FETCH =>
                            read_index <= event_index;
                            state <= STATE_LATCH_WAIT;
                        when STATE_LATCH_WAIT =>
                            state <= STATE_LATCH;
                        when STATE_LATCH =>
                            latched_event <= read_data;
                            state <= STATE_SCHEDULE;
                        when STATE_SCHEDULE =>
                            if event_index >= event_count then
                                state <= STATE_WAIT_END;
                            else
                                delta_remaining <= to_integer(unsigned(
                                    latched_event(31 downto 20)));
                                if unsigned(latched_event(31 downto 20)) = 0 then
                                    state <= STATE_ACTIVATE;
                                else
                                    state <= STATE_DELAY;
                                end if;
                            end if;
                        when STATE_DELAY =>
                            if ms_tick = '1' then
                                if delta_remaining <= 1 then
                                    delta_remaining <= 0;
                                    state <= STATE_ACTIVATE;
                                else
                                    delta_remaining <= delta_remaining - 1;
                                end if;
                            end if;
                        when STATE_ACTIVATE =>
                            note_v := to_integer(unsigned(
                                latched_event(11 downto 9)));
                            duration_v := to_integer(unsigned(
                                latched_event(19 downto 12))) * 10;
                            if duration_v = 0 then
                                duration_v := 1;
                            end if;
                            virtual_on_reg(note_v) <= '1';
                            virtual_levels_reg(note_v) <= shift_left(
                                resize(unsigned(latched_event(8 downto 4)), 10),
                                5);
                            remaining(note_v) <= duration_v;
                            tone_reg <= to_integer(unsigned(
                                latched_event(3 downto 2)));
                            effect_reg <= to_integer(unsigned(
                                latched_event(1 downto 0)));
                            event_index <= event_index + 1;
                            state <= STATE_FETCH;
                        when others =>
                            any_active_v := '0';
                            for note in 0 to 7 loop
                                if virtual_on_reg(note) = '1' then
                                    any_active_v := '1';
                                end if;
                            end loop;
                            if any_active_v = '0' then
                                state <= STATE_IDLE;
                            end if;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
