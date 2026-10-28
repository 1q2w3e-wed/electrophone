library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- 依次扫描 MCP3008 CH0~CH7，并输出原始压力值与按下状态。
entity sensor_scanner is
    generic (
        ADC_POLL_DIV       : positive := 1_000;
        SENSOR_ON_LEVEL    : natural range 0 to 1023 := 32;
        SENSOR_OFF_LEVEL   : natural range 0 to 1023 := 16;
        SENSOR_DEBOUNCE    : positive range 1 to 16 := 4;
        SENSOR_FILTER_SHIFT: positive range 1 to 5 := 3
    );
    port (
        clk, rst_n : in std_logic;
        spi_clk    : out std_logic;
        spi_din    : out std_logic;
        spi_dout   : in std_logic;
        spi_cs_n   : out std_logic;
        sensor_levels_o : out sensor_array_t;
        sensor_on_o     : out std_logic_vector(7 downto 0)
    );
end entity;

architecture rtl of sensor_scanner is
    signal channel : unsigned(2 downto 0) := (others => '0');
    signal adc_start, adc_busy, adc_valid : std_logic;
    signal adc_code : unsigned(9 downto 0);
    signal poll_count : natural range 0 to ADC_POLL_DIV-1 := 0;
    signal sensor_levels : sensor_array_t := (others => (others => '0'));
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal filtered_levels : sensor_array_t := (others => (others => '0'));
    type count_array_t is array (0 to 7) of natural range 0 to SENSOR_DEBOUNCE;
    signal on_count, off_count : count_array_t := (others => 0);
    constant FILTER_DIV : positive := 2 ** SENSOR_FILTER_SHIFT;
begin
    sensor_levels_o <= sensor_levels;
    sensor_on_o <= sensor_on;

    reader: entity work.mcp3008_reader
        port map (
            clk => clk, rst_n => rst_n,
            start => adc_start, channel => channel,
            spi_clk => spi_clk, spi_din => spi_din,
            spi_dout => spi_dout, spi_cs_n => spi_cs_n,
            adc_code => adc_code, valid => adc_valid, busy => adc_busy
        );

    process(clk)
        variable index_v : natural range 0 to 7;
        variable filtered_v : unsigned(9 downto 0);
        variable new_on : std_logic;
    begin
        if rising_edge(clk) then
            adc_start <= '0';
            if rst_n = '0' then
                channel <= (others => '0');
                poll_count <= 0;
                sensor_levels <= (others => (others => '0'));
                sensor_on <= (others => '0');
                filtered_levels <= (others => (others => '0'));
                on_count <= (others => 0);
                off_count <= (others => 0);
            elsif adc_valid = '1' then
                index_v := to_integer(channel);
                filtered_v := resize(
                    (filtered_levels(index_v) * (FILTER_DIV-1) + adc_code) /
                    FILTER_DIV, 10);
                filtered_levels(index_v) <= filtered_v;
                new_on := sensor_on(index_v);

                if adc_code > to_unsigned(SENSOR_ON_LEVEL, 10) then
                    off_count(index_v) <= 0;
                    if on_count(index_v) = SENSOR_DEBOUNCE-1 then
                        new_on := '1';
                    else
                        on_count(index_v) <= on_count(index_v) + 1;
                    end if;
                elsif adc_code < to_unsigned(SENSOR_OFF_LEVEL, 10) then
                    on_count(index_v) <= 0;
                    if off_count(index_v) = SENSOR_DEBOUNCE-1 then
                        new_on := '0';
                    else
                        off_count(index_v) <= off_count(index_v) + 1;
                    end if;
                else
                    on_count(index_v) <= 0;
                    off_count(index_v) <= 0;
                end if;

                sensor_on(index_v) <= new_on;
                if new_on = '1' then
                    sensor_levels(index_v) <= filtered_v;
                else
                    sensor_levels(index_v) <= (others => '0');
                end if;

                if channel = 7 then
                    channel <= (others => '0');
                else
                    channel <= channel + 1;
                end if;
            elsif adc_busy = '0' then
                if poll_count = ADC_POLL_DIV-1 then
                    poll_count <= 0;
                    adc_start <= '1';
                else
                    poll_count <= poll_count + 1;
                end if;
            end if;
        end if;
    end process;
end architecture;
