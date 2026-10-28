library ieee;
use ieee.std_logic_1164.all;

entity tb_st7796s_display is
end entity;

architecture sim of tb_st7796s_display is
    constant CLK_PERIOD : time := 1 us;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal frame_start : std_logic;
    signal pixel_x : natural range 0 to 479;
    signal pixel_y : natural range 0 to 319;
    signal lcd_sclk, lcd_mosi, lcd_cs_n, lcd_dc, lcd_rst_n, lcd_bl : std_logic;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.st7796s_display
        generic map (
            G_CLK_HZ => 1_000_000,
            G_SPI_HALF_CYCLES => 1,
            G_RESET_MS => 1
        )
        port map (
            clk => clk, reset_n => reset_n,
            frame_start_o => frame_start,
            pixel_x_o => pixel_x, pixel_y_o => pixel_y,
            pixel_data_i => x"F800",
            lcd_sclk => lcd_sclk, lcd_mosi => lcd_mosi,
            lcd_cs_n => lcd_cs_n, lcd_dc => lcd_dc,
            lcd_rst_n => lcd_rst_n, lcd_bl => lcd_bl
        );

    stimulus: process
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait until lcd_bl = '1';
        assert lcd_cs_n = '0' severity failure;
        wait until rising_edge(frame_start);
        assert pixel_x = 0 and pixel_y = 0 severity failure;
        for i in 0 to 200 loop
            wait until rising_edge(lcd_sclk);
        end loop;
        assert pixel_x > 0 and pixel_y = 0
            report "Display did not advance to the first line"
            severity failure;
        report "tb_st7796s_display passed" severity note;
        wait;
    end process;
end architecture;
