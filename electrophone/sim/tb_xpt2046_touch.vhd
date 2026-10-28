library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_xpt2046_touch is
end entity;

architecture sim of tb_xpt2046_touch is
    constant CLK_PERIOD : time := 1 us;

    -- 第一次 X 转换模拟 XPT2046 唤醒后的无效值 0；
    -- 丢弃它以后，应使用第二次 X=238、随后 Y=2050 的有效数据。
    constant SAMPLE_STREAM : std_logic_vector(71 downto 0) :=
        x"00" & x"0000" & x"00" & x"0770" & x"00" & x"4010";

    signal clk        : std_logic := '0';
    signal reset_n    : std_logic := '0';
    signal touch_irq_n: std_logic := '1';
    signal touch_sclk : std_logic;
    signal touch_mosi : std_logic;
    signal touch_miso : std_logic := '0';
    signal touch_cs_n : std_logic;
    signal touch_tap  : std_logic;
    signal touched    : std_logic;
    signal touch_x    : natural range 0 to 479;
    signal touch_y    : natural range 0 to 319;
    signal tap_count  : natural := 0;
    signal miso_shift : std_logic_vector(71 downto 0) := (others => '0');
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.xpt2046_touch
        generic map (
            G_CLK_HZ => 1_000_000,
            G_SPI_HALF_CYCLES => 1,
            G_POLL_CYCLES => 20,
            G_RAW_MIN_X => 200,
            G_RAW_MAX_X => 3900,
            G_RAW_MIN_Y => 200,
            G_RAW_MAX_Y => 3900,
            G_SWAP_XY => true,
            G_INVERT_X => true,
            G_INVERT_Y => true
        )
        port map (
            clk => clk, reset_n => reset_n,
            touch_irq_n => touch_irq_n,
            touch_tap => touch_tap,
            touched => touched,
            touch_x => touch_x,
            touch_y => touch_y,
            touch_sclk => touch_sclk,
            touch_mosi => touch_mosi,
            touch_miso => touch_miso,
            touch_cs_n => touch_cs_n
        );

    -- 模拟 XPT2046：片选有效时装入固定数据，之后每个 SCLK 下降沿送下一位。
    touch_model: process(touch_cs_n, touch_sclk)
    begin
        if touch_cs_n = '1' then
            miso_shift <= SAMPLE_STREAM;
            touch_miso <= '0';
        elsif falling_edge(touch_sclk) then
            touch_miso <= miso_shift(70);
            miso_shift <= miso_shift(70 downto 0) & '0';
        end if;
    end process;

    -- 锁定正确的命令字节，防止把 X/Y 通道再次写反。
    command_check: process(touch_cs_n, touch_sclk)
        variable slot : natural := 0;
        variable command : std_logic_vector(7 downto 0) := (others => '0');
    begin
        if touch_cs_n = '1' then
            slot := 0;
        elsif rising_edge(touch_sclk) then
            if slot rem 24 < 8 then
                command := command(6 downto 0) & touch_mosi;
                if slot rem 24 = 7 then
                    if slot < 24 then
                        assert command = x"90"
                            report "First X command must be 0x90, got " &
                                   integer'image(to_integer(unsigned(command)))
                            severity failure;
                    elsif slot < 48 then
                        assert command = x"90"
                            report "Repeated X command must be 0x90"
                            severity failure;
                    else
                        assert command = x"D0"
                            report "Y command must be 0xD0"
                            severity failure;
                    end if;
                end if;
            end if;
            slot := slot + 1;
        end if;
    end process;

    monitor: process(clk)
    begin
        if rising_edge(clk) and touch_tap = '1' then
            tap_count <= tap_count + 1;
        end if;
    end process;

    stimulus: process
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait for 5*CLK_PERIOD;

        -- 原始 X=238，原始 Y=2050。横屏需要交换轴后，
        -- 再反转两个方向，应换算为屏幕 X=240、Y=316。
        touch_irq_n <= '0';
        wait until touched = '1';
        wait for 2*CLK_PERIOD;
        assert touch_x = 240 and touch_y = 316
            report "XPT2046 coordinate scaling failed"
            severity failure;
        assert tap_count = 1
            report "First touch press did not produce exactly one tap pulse"
            severity failure;
        assert touch_mosi = '0' or touch_cs_n = '0'
            report "SPI data pin behaves unexpectedly"
            severity failure;

        -- 松开后必须清除“上次按下”状态，否则第二次触摸会被吞掉。
        touch_irq_n <= '1';
        wait for 100*CLK_PERIOD;
        touch_irq_n <= '0';
        wait for 250*CLK_PERIOD;
        assert tap_count = 2
            report "Second touch press did not produce a new tap pulse"
            severity failure;

        -- 按住不放时仍应只算一次点击，不能每轮读取都重复触发。
        wait for 500*CLK_PERIOD;
        assert tap_count = 2
            report "Holding the pen produced repeated tap pulses"
            severity failure;

        -- 轻触可能在坐标读取完成前就松开；已经开始的点击不能因此丢失。
        touch_irq_n <= '1';
        wait for 100*CLK_PERIOD;
        touch_irq_n <= '0';
        wait for 10*CLK_PERIOD;
        touch_irq_n <= '1';
        wait for 250*CLK_PERIOD;
        assert tap_count = 3
            report "A short touch was lost before coordinate conversion completed"
            severity failure;

        -- 快速连点时，新按压可能在上一轮 5 ms 等待中开始；
        -- 只要中间出现过释放，下一次按压就必须重新产生点击。
        touch_irq_n <= '1';
        wait for 100*CLK_PERIOD;
        touch_irq_n <= '0';
        wait until tap_count = 4;
        touch_irq_n <= '1';
        wait for CLK_PERIOD;
        touch_irq_n <= '0';
        wait for 250*CLK_PERIOD;
        assert tap_count = 5
            report "Rapid touch after release was ignored"
            severity failure;

        report "tb_xpt2046_touch passed" severity note;
        wait;
    end process;
end architecture;
