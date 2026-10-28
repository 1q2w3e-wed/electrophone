library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- XPT2046 电阻触摸读取器，使用独立的 SPI 引脚，避免和 LCD 刷新抢总线。
entity xpt2046_touch is
    generic (
        G_CLK_HZ          : positive := 50_000_000;
        G_SPI_HALF_CYCLES : positive := 25;    -- 约 1 MHz
        G_POLL_CYCLES     : positive := 250_000; -- 5 ms 轮询
        G_RAW_MIN_X       : natural := 200;
        G_RAW_MAX_X       : natural := 3900;
        G_RAW_MIN_Y       : natural := 200;
        G_RAW_MAX_Y       : natural := 3900;
        G_SWAP_XY         : boolean := false;
        G_INVERT_X        : boolean := false;
        G_INVERT_Y        : boolean := false
    );
    port (
        clk, reset_n : in  std_logic;
        touch_irq_n  : in  std_logic; -- PENIRQ，低电平表示触摸
        touch_tap    : out std_logic; -- 一次按下脉冲
        touched      : out std_logic;
        touch_x      : out natural range 0 to 479;
        touch_y      : out natural range 0 to 319;
        raw_x_o      : out natural range 0 to 4095;
        raw_y_o      : out natural range 0 to 4095;
        touch_sclk   : out std_logic;
        touch_mosi   : out std_logic;
        touch_miso   : in  std_logic;
        touch_cs_n   : out std_logic
    );
end entity;

architecture rtl of xpt2046_touch is
    constant X_COMMAND : std_logic_vector(7 downto 0) := "10010000"; -- 0x90
    constant Y_COMMAND : std_logic_vector(7 downto 0) := "11010000"; -- 0xD0

    type state_t is (IDLE, X_CMD, X_READ, Y_CMD, Y_READ,
                     FINISH, SCALE_MUL, SCALE_DIV, PUBLISH, WAIT_NEXT);
    signal state        : state_t := IDLE;
    signal half_count   : natural range 0 to G_SPI_HALF_CYCLES-1 := 0;
    signal wait_count   : natural range 0 to G_POLL_CYCLES-1 := 0;
    signal bit_index    : integer range 0 to 15 := 0;
    signal sclk_int     : std_logic := '0';
    signal mosi_int     : std_logic := '0';
    signal cs_n_int     : std_logic := '1';
    signal rx_shift     : std_logic_vector(15 downto 0) := (others => '0');
    signal raw_x, raw_y : natural range 0 to 4095 := 0;
    signal diff_x, diff_y : natural range 0 to 4095 := 0;
    signal prod_x, prod_y : natural range 0 to 2_000_000 := 0;
    signal norm_x, norm_y : natural range 0 to 479 := 0;
    signal touch_level  : std_logic := '0';
    signal last_touch   : std_logic := '0';
    signal press_latched: std_logic := '0';
    signal discard_x    : std_logic := '0';
begin
    touch_sclk <= sclk_int;
    touch_mosi <= mosi_int;
    touch_cs_n <= cs_n_int;
    raw_x_o <= raw_x;
    raw_y_o <= raw_y;

    process(clk)
        variable x_final, y_final : natural;
        variable new_touch : std_logic;
    begin
        if rising_edge(clk) then
            touch_tap <= '0';
            if reset_n = '0' then
                state <= IDLE;
                half_count <= 0;
                wait_count <= 0;
                bit_index <= 0;
                sclk_int <= '0';
                mosi_int <= '0';
                cs_n_int <= '1';
                raw_x <= 0;
                raw_y <= 0;
                diff_x <= 0;
                diff_y <= 0;
                prod_x <= 0;
                prod_y <= 0;
                norm_x <= 0;
                norm_y <= 0;
                touch_level <= '0';
                last_touch <= '0';
                press_latched <= '0';
                discard_x <= '0';
                touched <= '0';
                touch_x <= 0;
                touch_y <= 0;
            else
                case state is
                    when IDLE =>
                        sclk_int <= '0';
                        mosi_int <= '0';
                        cs_n_int <= '1';
                        if touch_irq_n = '1' then
                            -- 触摸笔松开后必须清除“上次已按下”；按住时不能清除，
                            -- 否则一次长按会被当成连续点击。
                            last_touch <= '0';
                            touch_level <= '0';
                            touched <= '0';
                        else
                            cs_n_int <= '0';
                            press_latched <= '1';
                            discard_x <= '1';
                            bit_index <= 7;
                            mosi_int <= X_COMMAND(7);
                            half_count <= 0;
                            state <= X_CMD;
                        end if;

                    when X_CMD =>
                        if half_count < G_SPI_HALF_CYCLES-1 then
                            half_count <= half_count + 1;
                        else
                            half_count <= 0;
                            if sclk_int = '0' then
                                sclk_int <= '1';
                            else
                                sclk_int <= '0';
                                if bit_index = 0 then
                                    bit_index <= 15;
                                    rx_shift <= (others => '0');
                                    state <= X_READ;
                                else
                                    mosi_int <= X_COMMAND(bit_index - 1);
                                    bit_index <= bit_index - 1;
                                end if;
                            end if;
                        end if;

                    when X_READ =>
                        if half_count < G_SPI_HALF_CYCLES-1 then
                            half_count <= half_count + 1;
                        else
                            half_count <= 0;
                            if sclk_int = '0' then
                                sclk_int <= '1';
                                rx_shift <= rx_shift(14 downto 0) & touch_miso;
                            else
                                sclk_int <= '0';
                                if bit_index = 0 then
                                    if discard_x = '1' then
                                        -- 唤醒后的第一次 X 转换可能无效，丢弃后重读。
                                        discard_x <= '0';
                                        bit_index <= 7;
                                        mosi_int <= X_COMMAND(7);
                                        state <= X_CMD;
                                    else
                                        raw_x <= to_integer(unsigned(rx_shift(14 downto 3)));
                                        bit_index <= 7;
                                        mosi_int <= Y_COMMAND(7);
                                        state <= Y_CMD;
                                    end if;
                                else
                                    bit_index <= bit_index - 1;
                                end if;
                            end if;
                        end if;

                    when Y_CMD =>
                        if half_count < G_SPI_HALF_CYCLES-1 then
                            half_count <= half_count + 1;
                        else
                            half_count <= 0;
                            if sclk_int = '0' then
                                sclk_int <= '1';
                            else
                                sclk_int <= '0';
                                if bit_index = 0 then
                                    bit_index <= 15;
                                    rx_shift <= (others => '0');
                                    state <= Y_READ;
                                else
                                    mosi_int <= Y_COMMAND(bit_index - 1);
                                    bit_index <= bit_index - 1;
                                end if;
                            end if;
                        end if;

                    when Y_READ =>
                        if half_count < G_SPI_HALF_CYCLES-1 then
                            half_count <= half_count + 1;
                        else
                            half_count <= 0;
                            if sclk_int = '0' then
                                sclk_int <= '1';
                                rx_shift <= rx_shift(14 downto 0) & touch_miso;
                            else
                                sclk_int <= '0';
                                if bit_index = 0 then
                                    raw_y <= to_integer(unsigned(rx_shift(14 downto 3)));
                                    state <= FINISH;
                                else
                                    bit_index <= bit_index - 1;
                                end if;
                            end if;
                        end if;

                    when FINISH =>
                        sclk_int <= '0';
                        mosi_int <= '0';
                        cs_n_int <= '1';
                        if G_SWAP_XY then
                            if raw_y <= G_RAW_MIN_Y then diff_x <= 0;
                            elsif raw_y >= G_RAW_MAX_Y then diff_x <= G_RAW_MAX_Y - G_RAW_MIN_Y;
                            else diff_x <= raw_y - G_RAW_MIN_Y; end if;
                            if raw_x <= G_RAW_MIN_X then diff_y <= 0;
                            elsif raw_x >= G_RAW_MAX_X then diff_y <= G_RAW_MAX_X - G_RAW_MIN_X;
                            else diff_y <= raw_x - G_RAW_MIN_X; end if;
                        else
                            if raw_x <= G_RAW_MIN_X then diff_x <= 0;
                            elsif raw_x >= G_RAW_MAX_X then diff_x <= G_RAW_MAX_X - G_RAW_MIN_X;
                            else diff_x <= raw_x - G_RAW_MIN_X; end if;
                            if raw_y <= G_RAW_MIN_Y then diff_y <= 0;
                            elsif raw_y >= G_RAW_MAX_Y then diff_y <= G_RAW_MAX_Y - G_RAW_MIN_Y;
                            else diff_y <= raw_y - G_RAW_MIN_Y; end if;
                        end if;
                        state <= SCALE_MUL;

                    when SCALE_MUL =>
                        prod_x <= diff_x * 479;
                        prod_y <= diff_y * 319;
                        state <= SCALE_DIV;

                    when SCALE_DIV =>
                        if G_SWAP_XY then
                            norm_x <= prod_x / (G_RAW_MAX_Y - G_RAW_MIN_Y);
                            norm_y <= prod_y / (G_RAW_MAX_X - G_RAW_MIN_X);
                        else
                            norm_x <= prod_x / (G_RAW_MAX_X - G_RAW_MIN_X);
                            norm_y <= prod_y / (G_RAW_MAX_Y - G_RAW_MIN_Y);
                        end if;
                        state <= PUBLISH;

                    when PUBLISH =>
                        x_final := norm_x;
                        y_final := norm_y;
                        if G_INVERT_X then
                            x_final := 479 - x_final;
                        end if;
                        if G_INVERT_Y then
                            y_final := 319 - y_final;
                        end if;
                        touch_x <= x_final;
                        touch_y <= y_final;
                        -- 按下后即使很快松开，也要完成这次点击；
                        -- 否则轻触和人手抖动会让触摸响应时有时无。
                        new_touch := press_latched;
                        touch_level <= new_touch;
                        if new_touch = '1' then
                            if last_touch = '0' then
                                touch_tap <= '1';
                            end if;
                        end if;
                        last_touch <= new_touch;
                        touched <= new_touch;
                        press_latched <= '0';
                        wait_count <= 0;
                        state <= WAIT_NEXT;

                    when WAIT_NEXT =>
                        -- 快速连点时，下次按压可能在本轮等待期间开始。
                        -- 只要检测到已经松开，就立即允许下一次点击。
                        if touch_irq_n = '1' then
                            last_touch <= '0';
                            touch_level <= '0';
                            touched <= '0';
                        end if;
                        if wait_count = G_POLL_CYCLES-1 then
                            wait_count <= 0;
                            state <= IDLE;
                        else
                            wait_count <= wait_count + 1;
                        end if;

                end case;
            end if;
        end if;
    end process;
end architecture;
