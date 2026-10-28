library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Streams the packed recording RAM as a compact binary packet:
-- A5 5A COUNT_HI COUNT_LO, followed by COUNT big-endian 32-bit events.
entity event_uploader is
    generic (
        G_EVENT_CAPACITY : positive := 1024
    );
    port (
        clk, rst_n : in std_logic;
        start : in std_logic;
        event_count : in natural range 0 to G_EVENT_CAPACITY;
        read_index : out natural range 0 to G_EVENT_CAPACITY-1;
        read_data : in std_logic_vector(31 downto 0);
        tx_ready : in std_logic;
        tx_data : out std_logic_vector(7 downto 0);
        tx_valid : out std_logic;
        busy : out std_logic
    );
end entity;

architecture rtl of event_uploader is
    type state_t is (
        STATE_IDLE, STATE_HEADER, STATE_READ_WAIT,
        STATE_READ_LATCH, STATE_EVENT, STATE_FINISH
    );
    signal state : state_t := STATE_IDLE;
    signal active : std_logic := '0';
    signal total : natural range 0 to G_EVENT_CAPACITY := 0;
    signal event_index : natural range 0 to G_EVENT_CAPACITY := 0;
    signal byte_index : natural range 0 to 3 := 0;
    signal latched_event : std_logic_vector(31 downto 0) := (others => '0');
    signal tx_hold : std_logic := '0';
begin
    busy <= active;

    process(clk)
    begin
        if rising_edge(clk) then
            tx_valid <= '0';
            if rst_n = '0' then
                state <= STATE_IDLE;
                active <= '0';
                total <= 0;
                event_index <= 0;
                byte_index <= 0;
                latched_event <= (others => '0');
                read_index <= 0;
                tx_data <= (others => '0');
                tx_hold <= '0';
            else
                if active = '1' then
                    if tx_hold = '1' then
                        if tx_ready = '0' then
                            tx_hold <= '0';
                        end if;
                    elsif tx_ready = '1' then
                        case state is
                            when STATE_HEADER =>
                                case byte_index is
                                    when 0 => tx_data <= x"A5";
                                    when 1 => tx_data <= x"5A";
                                    when 2 => tx_data <= std_logic_vector(
                                        to_unsigned(total / 256, 8));
                                    when others => tx_data <= std_logic_vector(
                                        to_unsigned(total mod 256, 8));
                                end case;
                                tx_valid <= '1';
                                tx_hold <= '1';
                                if byte_index = 3 then
                                    byte_index <= 0;
                                    if total = 0 then
                                        state <= STATE_FINISH;
                                    else
                                        event_index <= 0;
                                        read_index <= 0;
                                        state <= STATE_READ_WAIT;
                                    end if;
                                else
                                    byte_index <= byte_index + 1;
                                end if;
                            when STATE_READ_WAIT =>
                                state <= STATE_READ_LATCH;
                            when STATE_READ_LATCH =>
                                latched_event <= read_data;
                                byte_index <= 0;
                                state <= STATE_EVENT;
                            when STATE_EVENT =>
                                case byte_index is
                                    when 0 => tx_data <= latched_event(31 downto 24);
                                    when 1 => tx_data <= latched_event(23 downto 16);
                                    when 2 => tx_data <= latched_event(15 downto 8);
                                    when others => tx_data <= latched_event(7 downto 0);
                                end case;
                                tx_valid <= '1';
                                tx_hold <= '1';
                                if byte_index = 3 then
                                    byte_index <= 0;
                                    if event_index + 1 < total then
                                        event_index <= event_index + 1;
                                        read_index <= event_index + 1;
                                        state <= STATE_READ_WAIT;
                                    else
                                        state <= STATE_FINISH;
                                    end if;
                                else
                                    byte_index <= byte_index + 1;
                                end if;
                            when STATE_FINISH =>
                                active <= '0';
                                state <= STATE_IDLE;
                            when others =>
                                null;
                        end case;
                    end if;
                end if;

                if start = '1' and active = '0' then
                    total <= event_count;
                    event_index <= 0;
                    byte_index <= 0;
                    active <= '1';
                    state <= STATE_HEADER;
                    tx_hold <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture;
