library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_sensor_noise is
end entity;

architecture sim of tb_sensor_noise is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal spi_clk, spi_din, spi_cs_n : std_logic;
    signal spi_dout : std_logic := '0';
    signal sensor_levels : sensor_array_t;
    signal sensor_on : std_logic_vector(7 downto 0);
    signal transaction_count : natural := 0;
    signal ch0_rising_edges : natural := 0;
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

    -- CH0 alternates between a low-noise sample and a noisy sample.
    adc_model: process
        variable stream : std_logic_vector(15 downto 0);
        variable adc_value : natural;
    begin
        wait until falling_edge(spi_cs_n);
        if transaction_count mod 8 = 0 then
            if (transaction_count / 8) mod 2 = 0 then
                adc_value := 10;
            else
                adc_value := 80;
            end if;
        else
            adc_value := 0;
        end if;

        stream := "000000" & std_logic_vector(to_unsigned(adc_value, 10));
        spi_dout <= stream(15);
        for bit_index in 0 to 15 loop
            wait until rising_edge(spi_clk);
            if bit_index < 15 then
                wait until falling_edge(spi_clk);
                spi_dout <= stream(14-bit_index);
            end if;
        end loop;
        spi_dout <= '0';
        wait until rising_edge(spi_cs_n);
        transaction_count <= transaction_count + 1;
    end process;

    monitor: process(clk)
        variable previous : std_logic := '0';
    begin
        if rising_edge(clk) then
            if previous = '0' and sensor_on(0) = '1' then
                ch0_rising_edges <= ch0_rising_edges + 1;
            end if;
            previous := sensor_on(0);
        end if;
    end process;

    stimulus: process
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until transaction_count >= 80;
        wait for 20*CLK_PERIOD;

        assert sensor_on(0) = '0'
            report "Unpressed noisy CH0 incorrectly triggered a note"
            severity failure;
        assert to_integer(sensor_levels(0)) = 0
            report "Unpressed noisy CH0 is displayed as pressure"
            severity failure;
        assert ch0_rising_edges = 0
            report "Unpressed noisy CH0 caused repeated gate triggers"
            severity failure;

        report "tb_sensor_noise passed" severity note;
        wait;
    end process;
end architecture;
