library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 8192-word shared effect delay memory with a 4-bit mode epoch tag.
entity effects_delay_ram is
    port (
        clk : in std_logic;
        write_enable : in std_logic;
        write_address : in unsigned(12 downto 0);
        write_data : in std_logic_vector(19 downto 0);
        read_address : in unsigned(12 downto 0);
        read_data : out std_logic_vector(19 downto 0)
    );
end entity;

architecture rtl of effects_delay_ram is
    type ram_t is array (0 to 8191) of std_logic_vector(19 downto 0);
    signal ram : ram_t := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if write_enable = '1' then
                ram(to_integer(write_address)) <= write_data;
            end if;
            read_data <= ram(to_integer(read_address));
        end if;
    end process;
end architecture;
