library ieee;
use ieee.std_logic_1164.all;

-- Two 96 by 96 one-bit XY plotting banks.
entity lissajous_bitmap_ram is
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        write_bank : in std_logic;
        write_x, write_y : in natural range 0 to 95;
        write_value : in std_logic;
        read_bank : in std_logic;
        read_x, read_y : in natural range 0 to 95;
        read_value : out std_logic
    );
end entity;

architecture rtl of lissajous_bitmap_ram is
    constant PLOT_SIZE : positive := 96;
    type pixel_array_t is array (0 to PLOT_SIZE*PLOT_SIZE-1) of
        std_logic_vector(7 downto 0);
    signal bank0, bank1 : pixel_array_t := (others => (others => '0'));
    signal write_byte : std_logic_vector(7 downto 0);
begin
    write_byte <= "0000000" & write_value;
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                bank0 <= (others => (others => '0'));
                bank1 <= (others => (others => '0'));
                read_value <= '0';
            else
                if write_bank = '0' then
                    bank0(write_y*PLOT_SIZE + write_x) <= write_byte;
                else
                    bank1(write_y*PLOT_SIZE + write_x) <= write_byte;
                end if;
                if read_bank = '0' then
                    read_value <= bank0(read_y*PLOT_SIZE + read_x)(0);
                else
                    read_value <= bank1(read_y*PLOT_SIZE + read_x)(0);
                end if;
            end if;
        end if;
    end process;
end architecture;
