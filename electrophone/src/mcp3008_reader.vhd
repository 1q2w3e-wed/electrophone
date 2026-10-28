library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- MCP3008 单通道读取器。16 个 SPI 时钟后输出 10 位 ADC 结果。
entity mcp3008_reader is
    generic (
        HALF_PERIOD_CYCLES : positive := 25
    );
    port (
        clk, rst_n : in std_logic;
        start      : in std_logic;
        channel    : in unsigned(2 downto 0);
        spi_clk    : out std_logic;
        spi_din    : out std_logic;
        spi_dout   : in std_logic;
        spi_cs_n   : out std_logic;
        adc_code   : out unsigned(9 downto 0);
        valid      : out std_logic;
        busy       : out std_logic
    );
end entity;

architecture rtl of mcp3008_reader is
    type state_t is (IDLE, HIGH_PHASE, LOW_PHASE, STOP_HIGH);
    signal state        : state_t := IDLE;
    signal half_counter : natural range 0 to HALF_PERIOD_CYCLES-1 := 0;
    signal bit_index    : natural range 0 to 15 := 0;
    signal rx_shift     : std_logic_vector(15 downto 0) := (others => '0');
    signal tx_shift     : std_logic_vector(4 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            valid <= '0';
            if rst_n = '0' then
                state <= IDLE;
                half_counter <= 0;
                bit_index <= 0;
                rx_shift <= (others => '0');
                tx_shift <= (others => '0');
                spi_clk <= '0';
                spi_din <= '0';
                spi_cs_n <= '1';
                adc_code <= (others => '0');
                busy <= '0';
            else
                case state is
                    when IDLE =>
                        spi_clk <= '0';
                        spi_din <= '0';
                        spi_cs_n <= '1';
                        busy <= '0';
                        if start = '1' then
                            half_counter <= 0;
                            bit_index <= 0;
                            rx_shift <= (others => '0');
                            tx_shift <= "11" & std_logic_vector(channel);
                            spi_cs_n <= '0';
                            spi_din <= '1';
                            busy <= '1';
                            state <= HIGH_PHASE;
                        end if;
                    when HIGH_PHASE =>
                        if half_counter = HALF_PERIOD_CYCLES-1 then
                            half_counter <= 0;
                            spi_clk <= '1';
                            rx_shift <= rx_shift(14 downto 0) & spi_dout;
                            if bit_index = 15 then
                                adc_code <= unsigned(
                                    rx_shift(8 downto 0) & spi_dout);
                                state <= STOP_HIGH;
                            else
                                state <= LOW_PHASE;
                            end if;
                        else
                            half_counter <= half_counter + 1;
                        end if;
                    when LOW_PHASE =>
                        if half_counter = HALF_PERIOD_CYCLES-1 then
                            half_counter <= 0;
                            spi_clk <= '0';
                            bit_index <= bit_index + 1;
                            if bit_index < 4 then
                                tx_shift <= tx_shift(3 downto 0) & '0';
                                spi_din <= tx_shift(3);
                            else
                                spi_din <= '0';
                            end if;
                            state <= HIGH_PHASE;
                        else
                            half_counter <= half_counter + 1;
                        end if;
                    when STOP_HIGH =>
                        if half_counter = HALF_PERIOD_CYCLES-1 then
                            half_counter <= 0;
                            spi_clk <= '0';
                            spi_cs_n <= '1';
                            busy <= '0';
                            valid <= '1';
                            state <= IDLE;
                        else
                            half_counter <= half_counter + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
