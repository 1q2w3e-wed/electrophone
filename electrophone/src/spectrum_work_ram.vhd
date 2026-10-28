library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spectrum_tables.all;

-- Simple dual-port complex work RAM for the FFT butterfly engine.
entity spectrum_work_ram is
    port (
        clk : in std_logic;
        write_enable : in std_logic;
        write_address : in natural range 0 to SPECTRUM_FFT_SIZE-1;
        write_real, write_imag : in signed(31 downto 0);
        read_address : in natural range 0 to SPECTRUM_FFT_SIZE-1;
        read_real, read_imag : out signed(31 downto 0)
    );
end entity;

architecture rtl of spectrum_work_ram is
    type ram_t is array (0 to SPECTRUM_FFT_SIZE-1) of signed(31 downto 0);
    signal real_ram, imag_ram : ram_t := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if write_enable = '1' then
                real_ram(write_address) <= write_real;
                imag_ram(write_address) <= write_imag;
            end if;
            read_real <= real_ram(read_address);
            read_imag <= imag_ram(read_address);
        end if;
    end process;
end architecture;
