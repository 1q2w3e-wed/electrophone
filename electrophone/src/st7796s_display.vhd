library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ST7796S 480x320 4线 SPI 显示屏驱动。
-- 显示内容由 color_ui_renderer 按当前像素坐标实时生成。
entity st7796s_display is
    generic (
        G_CLK_HZ          : positive := 50_000_000;
        G_SPI_HALF_CYCLES : positive := 1; -- 50MHz / 2 = 25MHz SPI
        G_RESET_MS        : positive := 10;
        G_INIT_DELAY_MS   : positive := 1;
        G_FULL_REFRESH_EVERY : positive := 4;
        G_PARTIAL_Y0      : natural range 0 to 319 := 48;
        G_PARTIAL_Y1      : natural range 0 to 319 := 158
    );
    port (
        clk, reset_n       : in  std_logic;
        frame_start_o      : out std_logic;
        pixel_x_o          : out natural range 0 to 479;
        pixel_y_o          : out natural range 0 to 319;
        pixel_data_i       : in  std_logic_vector(15 downto 0);
        lcd_sclk, lcd_mosi : out std_logic;
        lcd_cs_n           : out std_logic;
        lcd_dc             : out std_logic;
        lcd_rst_n          : out std_logic;
        lcd_bl             : out std_logic
    );
end entity;

architecture rtl of st7796s_display is
    type init_entry_t is record
        value    : std_logic_vector(7 downto 0);
        is_cmd   : boolean;
        delay_ms : natural;
    end record;
    type init_array_t is array(natural range <>) of init_entry_t;

    -- 初始化序列来自 ST7796 常用参数。命令和参数分开编码。
    constant INIT_ROM : init_array_t := (
        (x"01", true, 120), -- software reset
        (x"11", true, 120), -- sleep out
        (x"F0", true, 0), (x"C3", false, 0),
        (x"F0", true, 0), (x"96", false, 0),
        -- MV=1 进行行列交换；4.0 寸 ST7796S 常见原生方向为 320x480，
        -- 交换后按本工程的 480x320 横屏窗口写入。
        (x"36", true, 0), (x"28", false, 0), -- landscape, BGR
        (x"3A", true, 0), (x"55", false, 0), -- RGB565
        (x"B4", true, 0), (x"01", false, 0),
        (x"B6", true, 0), (x"80", false, 0), (x"02", false, 0), (x"3B", false, 0),
        (x"E8", true, 0), (x"40", false, 0), (x"8A", false, 0),
        (x"00", false, 0), (x"00", false, 0), (x"29", false, 0),
        (x"19", false, 0), (x"A5", false, 0), (x"33", false, 0),
        (x"C1", true, 0), (x"06", false, 0),
        (x"C2", true, 0), (x"A7", false, 0),
        (x"C5", true, 0), (x"18", false, 120),
        (x"E0", true, 0),
        (x"F0", false, 0), (x"09", false, 0), (x"0B", false, 0),
        (x"06", false, 0), (x"04", false, 0), (x"15", false, 0),
        (x"2F", false, 0), (x"54", false, 0), (x"42", false, 0),
        (x"3C", false, 0), (x"17", false, 0), (x"14", false, 0),
        (x"18", false, 0), (x"1B", false, 0),
        (x"E1", true, 0),
        (x"E0", false, 0), (x"09", false, 0), (x"0B", false, 0),
        (x"06", false, 0), (x"04", false, 0), (x"03", false, 0),
        (x"2B", false, 0), (x"43", false, 0), (x"42", false, 0),
        (x"3B", false, 0), (x"16", false, 0), (x"14", false, 0),
        (x"17", false, 0), (x"1B", false, 120),
        (x"F0", true, 0), (x"3C", false, 0),
        (x"F0", true, 0), (x"69", false, 120),
        (x"20", true, 0), -- invert off
        (x"29", true, 0)  -- display on
    );

    constant WINDOW_ROM : init_array_t := (
        (x"2A", true, 0), (x"00", false, 0), (x"00", false, 0),
        (x"01", false, 0), (x"DF", false, 0),
        (x"2B", true, 0), (x"00", false, 0), (x"00", false, 0),
        (x"01", false, 0), (x"3F", false, 0),
        (x"2C", true, 0)
    );

    type main_state_t is (POWER_LOW, POWER_WAIT, INIT_SEND, INIT_WAIT, INIT_DELAY,
                          FRAME_START, WINDOW_SEND, WINDOW_WAIT,
                          PIXEL_PREP,
                          PIXEL_HI_SEND, PIXEL_HI_WAIT,
                          PIXEL_LO_SEND, PIXEL_LO_WAIT);
    type spi_state_t is (IDLE, BIT_HIGH, BIT_LOW);

    signal main_state : main_state_t := POWER_LOW;
    signal spi_state  : spi_state_t := IDLE;
    signal init_index : natural range 0 to INIT_ROM'length-1 := 0;
    signal win_index  : natural range 0 to WINDOW_ROM'length-1 := 0;
    signal pixel_x : natural range 0 to 479 := 0;
    signal pixel_y : natural range 0 to 319 := 0;
    signal frame_slot : natural range 0 to G_FULL_REFRESH_EVERY-1 := 0;
    signal frame_y_last : natural range 0 to 319 := 319;
    signal delay_count : natural range 0 to G_CLK_HZ/1000*130 := 0;
    signal prep_count  : natural range 0 to 3 := 0;
    signal half_count  : natural range 0 to G_SPI_HALF_CYCLES-1 := 0;
    signal bit_index   : integer range 0 to 7 := 7;
    signal send_start  : std_logic := '0';
    signal send_done   : std_logic := '0';
    signal send_data   : std_logic_vector(7 downto 0) := (others => '0');
    signal send_is_cmd : std_logic := '1';
    signal tx_shift    : std_logic_vector(7 downto 0) := (others => '0');
    signal sclk_int    : std_logic := '0';
    signal mosi_int    : std_logic := '0';
    signal dc_int      : std_logic := '0';
    signal cs_n_int    : std_logic := '1';
    signal rst_n_int   : std_logic := '0';
    signal bl_int      : std_logic := '0';
begin
    lcd_sclk  <= sclk_int;
    lcd_mosi  <= mosi_int;
    lcd_cs_n  <= cs_n_int;
    lcd_dc    <= dc_int;
    lcd_rst_n <= rst_n_int;
    lcd_bl    <= bl_int;
    pixel_x_o <= pixel_x;
    pixel_y_o <= pixel_y;

    -- 8 bit SPI 移位器。CS 在整帧期间保持低，DC 在启动字节时锁存。
    process(clk)
    begin
        if rising_edge(clk) then
            send_done <= '0';
            if reset_n = '0' then
                spi_state <= IDLE;
                half_count <= 0;
                bit_index <= 7;
                sclk_int <= '0';
                mosi_int <= '0';
                dc_int <= '0';
            else
                case spi_state is
                    when IDLE =>
                        sclk_int <= '0';
                        if send_start = '1' then
                            tx_shift <= send_data;
                            dc_int <= not send_is_cmd;
                            mosi_int <= send_data(7);
                            bit_index <= 7;
                            half_count <= 0;
                            spi_state <= BIT_HIGH;
                        end if;
                    when BIT_HIGH =>
                        if half_count = G_SPI_HALF_CYCLES-1 then
                            half_count <= 0;
                            sclk_int <= '1';
                            spi_state <= BIT_LOW;
                        else
                            half_count <= half_count + 1;
                        end if;
                    when BIT_LOW =>
                        if half_count = G_SPI_HALF_CYCLES-1 then
                            half_count <= 0;
                            sclk_int <= '0';
                            if bit_index = 0 then
                                send_done <= '1';
                                spi_state <= IDLE;
                            else
                                bit_index <= bit_index - 1;
                                mosi_int <= tx_shift(bit_index-1);
                                spi_state <= BIT_HIGH;
                            end if;
                        else
                            half_count <= half_count + 1;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- 初始化、窗口和像素流主状态机。
    process(clk)
    begin
        if rising_edge(clk) then
            send_start <= '0';
            frame_start_o <= '0';
            if reset_n = '0' then
                main_state <= POWER_LOW;
                init_index <= 0;
                win_index <= 0;
                pixel_x <= 0; pixel_y <= 0;
                frame_slot <= 0;
                frame_y_last <= 319;
                delay_count <= 0;
                prep_count <= 0;
                rst_n_int <= '0';
                cs_n_int <= '1';
                bl_int <= '0';
            else
                case main_state is
                    when POWER_LOW =>
                        rst_n_int <= '0';
                        cs_n_int <= '1';
                        if delay_count = G_CLK_HZ/1000*G_RESET_MS-1 then
                            delay_count <= 0;
                            rst_n_int <= '1';
                            main_state <= POWER_WAIT;
                        else
                            delay_count <= delay_count + 1;
                        end if;
                    when POWER_WAIT =>
                        if delay_count = G_CLK_HZ/1000*120-1 then
                            delay_count <= 0;
                            cs_n_int <= '0';
                            init_index <= 0;
                            main_state <= INIT_SEND;
                        else
                            delay_count <= delay_count + 1;
                        end if;
                    when INIT_SEND =>
                        send_data <= INIT_ROM(init_index).value;
                        if INIT_ROM(init_index).is_cmd then
                            send_is_cmd <= '1';
                        else
                            send_is_cmd <= '0';
                        end if;
                        send_start <= '1';
                        main_state <= INIT_WAIT;
                    when INIT_WAIT =>
                        if send_done = '1' then
                            if INIT_ROM(init_index).delay_ms = 0 then
                                if init_index = INIT_ROM'length-1 then
                                    bl_int <= '1';
                                    main_state <= FRAME_START;
                                else
                                    init_index <= init_index + 1;
                                    main_state <= INIT_SEND;
                                end if;
                            else
                                delay_count <= 0;
                                main_state <= INIT_DELAY;
                            end if;
                        end if;
                    when INIT_DELAY =>
                        if delay_count = (G_CLK_HZ/1000) * INIT_ROM(init_index).delay_ms - 1 then
                            delay_count <= 0;
                            if init_index = INIT_ROM'length-1 then
                                bl_int <= '1';
                                main_state <= FRAME_START;
                            else
                                init_index <= init_index + 1;
                                main_state <= INIT_SEND;
                            end if;
                        else
                            delay_count <= delay_count + 1;
                        end if;
                    when FRAME_START =>
                        pixel_x <= 0;
                        win_index <= 0;
                        frame_start_o <= '1';
                        if frame_slot = 0 then
                            pixel_y <= 0;
                            frame_y_last <= 319;
                        else
                            pixel_y <= G_PARTIAL_Y0;
                            frame_y_last <= G_PARTIAL_Y1;
                        end if;
                        main_state <= WINDOW_SEND;
                    when WINDOW_SEND =>
                        if win_index = 7 then
                            if frame_slot = 0 then
                                send_data <= x"00";
                            else
                                send_data <= std_logic_vector(
                                    to_unsigned(G_PARTIAL_Y0, 8));
                            end if;
                        elsif win_index = 9 then
                            if frame_slot = 0 then
                                send_data <= x"3F";
                            else
                                send_data <= std_logic_vector(
                                    to_unsigned(G_PARTIAL_Y1, 8));
                            end if;
                        else
                            send_data <= WINDOW_ROM(win_index).value;
                        end if;
                        if WINDOW_ROM(win_index).is_cmd then
                            send_is_cmd <= '1';
                        else
                            send_is_cmd <= '0';
                        end if;
                        send_start <= '1';
                        main_state <= WINDOW_WAIT;
                    when WINDOW_WAIT =>
                        if send_done = '1' then
                            if win_index = WINDOW_ROM'length-1 then
                                prep_count <= 0;
                                main_state <= PIXEL_PREP;
                            else
                                win_index <= win_index + 1;
                                main_state <= WINDOW_SEND;
                            end if;
                        end if;
                    when PIXEL_PREP =>
                        -- 等待波形计算和绘制器两级流水完成，再取样像素。
                        if prep_count = 3 then
                            prep_count <= 0;
                            main_state <= PIXEL_HI_SEND;
                        else
                            prep_count <= prep_count + 1;
                        end if;
                    when PIXEL_HI_SEND =>
                        send_data <= pixel_data_i(15 downto 8);
                        send_is_cmd <= '0';
                        send_start <= '1';
                        main_state <= PIXEL_HI_WAIT;
                    when PIXEL_HI_WAIT =>
                        if send_done = '1' then
                            main_state <= PIXEL_LO_SEND;
                        end if;
                    when PIXEL_LO_SEND =>
                        send_data <= pixel_data_i(7 downto 0);
                        send_is_cmd <= '0';
                        send_start <= '1';
                        main_state <= PIXEL_LO_WAIT;
                    when PIXEL_LO_WAIT =>
                        if send_done = '1' then
                            if pixel_x = 479 then
                                pixel_x <= 0;
                                if pixel_y = frame_y_last then
                                    if frame_slot = G_FULL_REFRESH_EVERY-1 then
                                        frame_slot <= 0;
                                    else
                                        frame_slot <= frame_slot + 1;
                                    end if;
                                    main_state <= FRAME_START;
                                else
                                    pixel_y <= pixel_y + 1;
                                    prep_count <= 0;
                                    main_state <= PIXEL_PREP;
                                end if;
                            else
                                pixel_x <= pixel_x + 1;
                                prep_count <= 0;
                                main_state <= PIXEL_PREP;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
