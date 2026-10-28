library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spectrum_tables.all;

-- Simple dual-port capture RAM for the real FFT input samples.
entity spectrum_capture_ram is
    port (
        clk : in std_logic;
        write_enable : in std_logic;
        write_address : in natural range 0 to SPECTRUM_FFT_SIZE-1;
        write_data : in signed(15 downto 0);
        read_address : in natural range 0 to SPECTRUM_FFT_SIZE-1;
        read_data : out signed(15 downto 0)
    );
end entity;

architecture rtl of spectrum_capture_ram is
    type ram_t is array (0 to SPECTRUM_FFT_SIZE-1) of signed(15 downto 0);
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
