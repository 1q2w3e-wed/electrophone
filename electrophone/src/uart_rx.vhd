library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 115200 bps 8N1 receiver. The start and each data bit are sampled at the
-- centre of their bit periods.
entity uart_rx is
    generic (
        G_CLK_HZ   : positive := 50_000_000;
        G_BAUD_RATE: positive := 115_200
    );
    port (
        clk, rst_n : in std_logic;
        rx         : in std_logic;
        data_o     : out std_logic_vector(7 downto 0);
        valid_o    : out std_logic
    );
end entity;

architecture rtl of uart_rx is
    constant BAUD_DIV : positive := G_CLK_HZ / G_BAUD_RATE;
    constant HALF_DIV : positive := BAUD_DIV / 2;

    signal rx_meta, rx_sync : std_logic := '1';
    signal receiving : std_logic := '0';
    signal start_checked : std_logic := '0';
    signal baud_count : natural range 0 to BAUD_DIV-1 := 0;
    signal bit_index : natural range 0 to 8 := 0;
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            rx_meta <= rx;
            rx_sync <= rx_meta;
            valid_o <= '0';

            if rst_n = '0' then
                receiving <= '0';
                start_checked <= '0';
                baud_count <= 0;
                bit_index <= 0;
                shift_reg <= (others => '0');
                data_o <= (others => '0');
            elsif receiving = '0' then
                if rx_sync = '0' then
                    receiving <= '1';
                    start_checked <= '0';
                    baud_count <= HALF_DIV-1;
                    bit_index <= 0;
                end if;
            elsif baud_count = 0 then
                if start_checked = '0' then
                    start_checked <= '1';
                    baud_count <= BAUD_DIV-1;
                    if rx_sync = '1' then
                        receiving <= '0';
                    end if;
                elsif bit_index < 8 then
                    shift_reg(bit_index) <= rx_sync;
                    bit_index <= bit_index + 1;
                    baud_count <= BAUD_DIV-1;
                else
                    receiving <= '0';
                    if rx_sync = '1' then
                        data_o <= shift_reg;
                        valid_o <= '1';
                    end if;
                end if;
            else
                baud_count <= baud_count - 1;
            end if;
        end if;
    end process;
end architecture;
