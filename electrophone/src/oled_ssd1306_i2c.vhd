library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- SSD1306 控制器：上电等待 -> 初始化 -> 逐页写一整帧 -> 开屏 -> 循环刷新。
-- 屏幕断线/NACK/时钟超时后释放总线，等待一段时间再重新初始化。
entity oled_ssd1306_i2c is
    generic (
        G_CLK_HZ : positive := 50_000_000;
        G_I2C_HZ : positive := 100_000;
        G_ADDRESS : natural range 0 to 127 := 16#3C#;
        G_CONTRAST : natural range 0 to 255 := 127;
        G_FLIP_X : boolean := true;
        G_FLIP_Y : boolean := true;
        G_POWER_WAIT_MS : positive := 100;
        G_FRAME_PAUSE_MS : positive := 10
    );
    port (
        clk, reset_n : in std_logic;
        frame_start_o : out std_logic;
        pixel_address_o : out natural range 0 to 1023;
        pixel_i : in byte_t;
        scl, sda : inout std_logic
    );
end entity;

architecture rtl of oled_ssd1306_i2c is
    type byte_array_t is array(natural range <>) of byte_t;
    -- 0x20,0x02 为页寻址，和 B0..B7/00/10 页命令配套。
    constant INIT_BYTES : byte_array_t(0 to 23) := (
        x"AE",x"D5",x"80",x"A8",x"3F",x"D3",x"00",x"40",
        x"8D",x"14",x"20",x"02",x"A1",x"C8",x"DA",x"12",
        x"81",x"7F",x"D9",x"F1",x"DB",x"40",x"A4",x"A6");
    type task_t is (INITIALIZE, PAGE_COMMAND, PAGE_PIXELS, DISPLAY_ON);
    type state_t is (POWER_WAIT, NEW_FRAME, LAUNCH, TRANSFER, FRAME_PAUSE);
    signal task : task_t := INITIALIZE;
    signal state : state_t := POWER_WAIT;
    signal wait_count : natural range 0 to (G_CLK_HZ/1000)*G_POWER_WAIT_MS-1 := 0;
    signal pause_count : natural range 0 to (G_CLK_HZ/1000)*G_FRAME_PAUSE_MS-1 := 0;
    signal page : natural range 0 to 7 := 0;
    signal byte_index : natural range 0 to 130 := 0;
    signal byte_count : natural range 3 to 130;
    signal data : byte_t;
    signal start, taken, done, error, last_byte : std_logic := '0';
    signal display_enabled : std_logic := '0';
begin
    master: entity work.i2c_write_master
        generic map(G_CLK_HZ => G_CLK_HZ, G_I2C_HZ => G_I2C_HZ)
        port map(clk => clk, reset_n => reset_n, start_i => start,
            data_i => data, last_i => last_byte, taken_o => taken,
            done_o => done, error_o => error, scl => scl, sda => sda);

    byte_count <= 26 when task = INITIALIZE else 5 when task = PAGE_COMMAND
                  else 130 when task = PAGE_PIXELS else 3;
    last_byte <= '1' when byte_index = byte_count-1 else '0';
    -- byte_index 装载最后一字节后会前进到 130；限制地址，避免越界。
    pixel_address_o <= page*128 + byte_index-2
        when task = PAGE_PIXELS and byte_index >= 2 and byte_index <= 129 else page*128;

    process(task, byte_index, page, pixel_i)
        variable n : natural;
    begin
        data <= x"00";
        if byte_index = 0 then
            data <= std_logic_vector(to_unsigned(G_ADDRESS*2,8)); -- 0x3C -> 0x78，写位为0
        elsif byte_index = 1 then
            if task = PAGE_PIXELS then data <= x"40"; else data <= x"00"; end if;
        else
            case task is
                when INITIALIZE =>
                    n := byte_index-2;
                    if n <= 23 then data <= INIT_BYTES(n); end if;
                    if n = 12 and not G_FLIP_X then data <= x"A0"; end if;
                    if n = 13 and not G_FLIP_Y then data <= x"C0"; end if;
                    if n = 17 then data <= std_logic_vector(to_unsigned(G_CONTRAST,8)); end if;
                when PAGE_COMMAND =>
                    if byte_index = 2 then data <= std_logic_vector(to_unsigned(16#B0#+page,8));
                    elsif byte_index = 4 then data <= x"10"; end if;
                when PAGE_PIXELS => data <= pixel_i;
                when DISPLAY_ON => data <= x"AF";
            end case;
        end if;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then
            start <= '0'; frame_start_o <= '0';
            if reset_n = '0' then
                state <= POWER_WAIT; task <= INITIALIZE; wait_count <= 0;
                pause_count <= 0; byte_index <= 0; page <= 0; display_enabled <= '0';
            else
                if taken = '1' and byte_index < 130 then byte_index <= byte_index+1; end if;
                case state is
                    when POWER_WAIT =>
                        if wait_count = (G_CLK_HZ/1000)*G_POWER_WAIT_MS-1 then
                            task <= INITIALIZE; byte_index <= 0; state <= LAUNCH;
                        else wait_count <= wait_count+1; end if;
                    when NEW_FRAME =>
                        frame_start_o <= '1'; page <= 0;
                        task <= PAGE_COMMAND; byte_index <= 0; state <= LAUNCH;
                    when LAUNCH => start <= '1'; state <= TRANSFER;
                    when TRANSFER =>
                        if done = '1' then
                            byte_index <= 0;
                            if error = '1' then
                                wait_count <= 0; display_enabled <= '0'; state <= POWER_WAIT;
                            else
                                case task is
                                    when INITIALIZE => state <= NEW_FRAME;
                                    when PAGE_COMMAND => task <= PAGE_PIXELS; state <= LAUNCH;
                                    when PAGE_PIXELS =>
                                        if page < 7 then
                                            page <= page+1; task <= PAGE_COMMAND; state <= LAUNCH;
                                        elsif display_enabled = '0' then
                                            task <= DISPLAY_ON; state <= LAUNCH;
                                        else pause_count <= 0; state <= FRAME_PAUSE; end if;
                                    when DISPLAY_ON =>
                                        display_enabled <= '1'; pause_count <= 0; state <= FRAME_PAUSE;
                                end case;
                            end if;
                        end if;
                    when FRAME_PAUSE =>
                        if pause_count = (G_CLK_HZ/1000)*G_FRAME_PAUSE_MS-1 then state <= NEW_FRAME;
                        else pause_count <= pause_count+1; end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
