library ieee;
use ieee.std_logic_1164.all;

-- 115200 bps 8N1 transmitter with a single-byte handshake.
entity uart_tx is
    generic (
        G_CLK_HZ   : positive := 50_000_000;
        G_BAUD_RATE: positive := 115_200
    );
    port (
        clk, rst_n : in std_logic;
        data_in    : in std_logic_vector(7 downto 0);
        data_valid : in std_logic;
        ready      : out std_logic;
        tx         : out std_logic
    );
end entity;

architecture rtl of uart_tx is
    constant BAUD_DIV : positive := G_CLK_HZ / G_BAUD_RATE;

    signal busy : std_logic := '0';
    signal baud_count : natural range 0 to BAUD_DIV-1 := 0;
    signal bit_index : natural range 0 to 9 := 0;
    signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_reg : std_logic := '1';
begin
    ready <= not busy;
    tx <= tx_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                busy <= '0';
                baud_count <= 0;
                bit_index <= 0;
                shift_reg <= (others => '0');
                tx_reg <= '1';
            elsif busy = '0' then
                if data_valid = '1' then
                    shift_reg <= data_in;
                    bit_index <= 0;
                    baud_count <= BAUD_DIV-1;
                    tx_reg <= '0';
                    busy <= '1';
                end if;
            elsif baud_count = 0 then
                baud_count <= BAUD_DIV-1;
                if bit_index < 8 then
                    tx_reg <= shift_reg(bit_index);
                    bit_index <= bit_index + 1;
                elsif bit_index = 8 then
                    tx_reg <= '1';
                    bit_index <= 9;
                else
                    busy <= '0';
                end if;
            else
                baud_count <= baud_count - 1;
            end if;
        end if;
    end process;
end architecture;
