library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

-- Simple dual-port inferred RAM for one complete 32-voice state record.
entity voice_state_ram is
    port (
        clk : in std_logic;
        read_address : in voice_index_t;
        write_enable : in std_logic;
        write_address : in voice_index_t;
        write_data : in voice_word_t;
        read_data : out voice_word_t
    );
end entity;

architecture rtl of voice_state_ram is
    type ram_t is array (voice_index_t) of voice_word_t;
    signal ram : ram_t := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if write_enable = '1' then
                ram(write_address) <= write_data;
            end if;
            read_data <= ram(read_address);
        end if;
    end process;
end architecture;
