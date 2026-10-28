library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_sensor_scanner is
end entity;

architecture sim of tb_sensor_scanner is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal spi_clk, spi_din, spi_cs_n : std_logic;
    signal spi_dout : std_logic := '0';
    signal sensor_levels : sensor_array_t;
    signal sensor_on : std_logic_vector(7 downto 0);
    signal transaction_count : natural := 0;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.sensor_scanner
        generic map (
            ADC_POLL_DIV => 20,
            SENSOR_ON_LEVEL => 32,
            SENSOR_OFF_LEVEL => 16
        )
        port map (
            clk => clk, rst_n => rst_n,
            spi_clk => spi_clk, spi_din => spi_din,
            spi_dout => spi_dout, spi_cs_n => spi_cs_n,
            sensor_levels_o => sensor_levels,
            sensor_on_o => sensor_on
        );

    monitor: process(spi_cs_n, spi_clk)
        variable bit_count : natural := 0;
        variable command : std_logic_vector(4 downto 0) := (others => '0');
        variable expected_channel : natural := 0;
    begin
        if falling_edge(spi_cs_n) then
            bit_count := 0;
            command := (others => '0');
        elsif rising_edge(spi_clk) and spi_cs_n = '0' then
            if bit_count < 5 then
                command := command(3 downto 0) & spi_din;
                bit_count := bit_count + 1;
            end if;
        elsif rising_edge(spi_cs_n) and bit_count >= 5 then
            assert command = "11" & std_logic_vector(
                to_unsigned(expected_channel, 3))
                report "Scanner selected the wrong MCP3008 channel"
                severity failure;
            if expected_channel = 7 then
                expected_channel := 0;
            else
                expected_channel := expected_channel + 1;
            end if;
            transaction_count <= transaction_count + 1;
        end if;
    end process;

    stimulus: process
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until transaction_count = 8;
        report "tb_sensor_scanner passed" severity note;
        wait;
    end process;

    timeout: process
    begin
        wait for 2 ms;
        assert transaction_count >= 8
            report "Eight-channel ADC scan timed out" severity failure;
        wait;
    end process;
end architecture;
