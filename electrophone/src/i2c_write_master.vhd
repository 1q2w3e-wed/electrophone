library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

-- 单主机 I2C 写事务。
-- start_i=1 后装载 data_i；taken_o 表示已装载，调用者可准备下一字节。
-- 当前字节传输期间数据已被锁存，不受下一字节影响。last_i 标记最后字节。
entity i2c_write_master is
    generic (
        G_CLK_HZ : positive := 50_000_000;
        G_I2C_HZ : positive := 100_000;
        G_TIMEOUT_MS : positive := 10
    );
    port (
        clk, reset_n, start_i : in std_logic;
        data_i : in byte_t;
        last_i : in std_logic;
        taken_o, done_o, error_o : out std_logic;
        scl, sda : inout std_logic
    );
end entity;

architecture rtl of i2c_write_master is
    constant QUARTER_CYCLES : positive := G_CLK_HZ / (4 * G_I2C_HZ);
    constant WAIT_TICKS : positive := (4 * G_I2C_HZ / 1000) * G_TIMEOUT_MS;
    type state_t is (IDLE, BUS_FREE, START_HOLD, START_LOW,
        BIT_SETUP, BIT_RISE, BIT_WAIT, BIT_FALL,
        ACK_SETUP, ACK_RISE, ACK_WAIT, ACK_FALL,
        STOP_LOW, STOP_RISE, STOP_WAIT, STOP_RELEASE, STOP_SETTLE, FINISH);
    signal state : state_t := IDLE;
    signal divider : natural range 0 to QUARTER_CYCLES-1 := 0;
    signal wait_count : natural range 0 to WAIT_TICKS-1 := 0;
    signal shift : byte_t := (others => '0');
    signal bit_number : natural range 0 to 7 := 7;
    signal last_byte, failed : std_logic := '0';
    signal scl_low, sda_low : std_logic := '0';
begin
    scl <= '0' when scl_low = '1' else 'Z';
    sda <= '0' when sda_low = '1' else 'Z';
    error_o <= failed;
    process(clk)
    begin
        if rising_edge(clk) then
            taken_o <= '0'; done_o <= '0';
            if reset_n = '0' then
                state <= IDLE; divider <= 0; wait_count <= 0;
                scl_low <= '0'; sda_low <= '0'; failed <= '0';
                shift <= (others => '0'); bit_number <= 7; last_byte <= '0';
            elsif state = IDLE then
                divider <= 0; wait_count <= 0;
                if start_i = '1' then
                    shift <= data_i; last_byte <= last_i; taken_o <= '1';
                    failed <= '0'; bit_number <= 7; state <= BUS_FREE;
                end if;
            elsif divider = QUARTER_CYCLES-1 then
                divider <= 0;
                case state is
                    when BUS_FREE =>
                        if to_x01(scl) = '1' and to_x01(sda) = '1' then
                            wait_count <= 0; state <= START_HOLD;
                        elsif wait_count = WAIT_TICKS-1 then
                            failed <= '1'; state <= FINISH;
                        else wait_count <= wait_count + 1; end if;
                    when START_HOLD => sda_low <= '1'; state <= START_LOW;
                    when START_LOW => scl_low <= '1'; state <= BIT_SETUP;
                    when BIT_SETUP =>
                        if shift(bit_number) = '0' then sda_low <= '1'; else sda_low <= '0'; end if;
                        state <= BIT_RISE;
                    when BIT_RISE => scl_low <= '0'; state <= BIT_WAIT;
                    when BIT_WAIT =>
                        if to_x01(scl) = '1' then wait_count <= 0; state <= BIT_FALL;
                        elsif wait_count = WAIT_TICKS-1 then
                            failed <= '1'; wait_count <= 0; state <= STOP_LOW;
                        else wait_count <= wait_count + 1; end if;
                    when BIT_FALL =>
                        scl_low <= '1';
                        if bit_number = 0 then state <= ACK_SETUP;
                        else bit_number <= bit_number-1; state <= BIT_SETUP; end if;
                    when ACK_SETUP => sda_low <= '0'; state <= ACK_RISE;
                    when ACK_RISE => scl_low <= '0'; state <= ACK_WAIT;
                    when ACK_WAIT =>
                        if to_x01(scl) = '1' then
                            if to_x01(sda) /= '0' then failed <= '1'; end if;
                            wait_count <= 0; state <= ACK_FALL;
                        elsif wait_count = WAIT_TICKS-1 then
                            failed <= '1'; wait_count <= 0; state <= STOP_LOW;
                        else wait_count <= wait_count + 1; end if;
                    when ACK_FALL =>
                        scl_low <= '1';
                        if failed = '1' or last_byte = '1' then state <= STOP_LOW;
                        else
                            shift <= data_i; last_byte <= last_i; taken_o <= '1';
                            bit_number <= 7; state <= BIT_SETUP;
                        end if;
                    when STOP_LOW => scl_low <= '1'; sda_low <= '1'; state <= STOP_RISE;
                    when STOP_RISE => scl_low <= '0'; state <= STOP_WAIT;
                    when STOP_WAIT =>
                        if to_x01(scl) = '1' then wait_count <= 0; state <= STOP_RELEASE;
                        elsif wait_count = WAIT_TICKS-1 then failed <= '1'; state <= FINISH;
                        else wait_count <= wait_count + 1; end if;
                    when STOP_RELEASE => sda_low <= '0'; state <= STOP_SETTLE;
                    when STOP_SETTLE => state <= FINISH;
                    when FINISH =>
                        scl_low <= '0'; sda_low <= '0'; done_o <= '1'; state <= IDLE;
                    when others => state <= IDLE;
                end case;
            else divider <= divider+1;
            end if;
        end if;
    end process;
end architecture;
