library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Shared score/recording event storage. One synchronous read port and one
-- write port allow the sequencer to read while a recording appends.
entity score_event_ram is
    generic (
        G_EVENT_CAPACITY : positive := 1024
    );
    port (
        clk, rst_n : in std_logic;
        clear : in std_logic;
        append_en : in std_logic;
        append_data : in std_logic_vector(31 downto 0);
        update_en : in std_logic;
        update_index : in natural range 0 to G_EVENT_CAPACITY-1;
        update_duration : in std_logic_vector(7 downto 0);
        update_velocity : in std_logic_vector(4 downto 0);
        read_index : in natural range 0 to G_EVENT_CAPACITY-1;
        read_data : out std_logic_vector(31 downto 0);
        event_count : out natural range 0 to G_EVENT_CAPACITY;
        full : out std_logic
    );
end entity;

architecture rtl of score_event_ram is
    type ram_t is array (0 to G_EVENT_CAPACITY-1) of
        std_logic_vector(31 downto 0);
    signal ram : ram_t := (others => (others => '0'));
    signal count_reg : natural range 0 to G_EVENT_CAPACITY := 0;
begin
    event_count <= count_reg;
    full <= '1' when count_reg = G_EVENT_CAPACITY else '0';

    process(clk)
        variable updated_word : std_logic_vector(31 downto 0);
        variable write_enable_v : std_logic;
        variable write_index_v : natural range 0 to G_EVENT_CAPACITY-1;
        variable write_data_v : std_logic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            read_data <= ram(read_index);
            write_enable_v := '0';
            write_index_v := 0;
            write_data_v := (others => '0');
            if rst_n = '0' then
                count_reg <= 0;
            elsif clear = '1' then
                count_reg <= 0;
            else
                if update_en = '1' then
                    updated_word := ram(update_index);
                    updated_word(19 downto 12) := update_duration;
                    updated_word(8 downto 4) := update_velocity;
                    write_enable_v := '1';
                    write_index_v := update_index;
                    write_data_v := updated_word;
                elsif append_en = '1' and count_reg < G_EVENT_CAPACITY then
                    write_enable_v := '1';
                    write_index_v := count_reg;
                    write_data_v := append_data;
                    count_reg <= count_reg + 1;
                end if;
                if write_enable_v = '1' then
                    ram(write_index_v) <= write_data_v;
                end if;
            end if;
        end if;
    end process;
end architecture;
