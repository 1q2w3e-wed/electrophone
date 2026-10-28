library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 标准 I2S 发送器：16 位左声道 + 16 位右声道。
entity i2s_transmitter is
    generic (
        CLK_PER_HALF_BIT : positive := 16
    );
    port (
        clk, rst_n : in std_logic;
        audio_left, audio_right : in signed(15 downto 0);
        frame_tick : out std_logic;
        i2s_lrclk  : out std_logic;
        i2s_bclk   : out std_logic;
        i2s_din    : out std_logic
    );
end entity;

architecture rtl of i2s_transmitter is
    signal phase_counter : natural range 0 to CLK_PER_HALF_BIT-1 := 0;
    signal bit_index     : natural range 0 to 31 := 31;
    signal bclk_int      : std_logic := '0';
    signal lrclk_int     : std_logic := '0';
    signal shift_reg     : std_logic_vector(15 downto 0) := (others => '0');
    signal din_int       : std_logic := '0';
begin
    process(clk)
    begin
        if rising_edge(clk) then
            frame_tick <= '0';
            if rst_n = '0' then
                phase_counter <= 0;
                bit_index <= 31;
                bclk_int <= '0';
                lrclk_int <= '0';
                shift_reg <= (others => '0');
                din_int <= '0';
            else
                if phase_counter = CLK_PER_HALF_BIT-1 then
                    phase_counter <= 0;
                    bclk_int <= not bclk_int;
                    if bclk_int = '1' then
                        if bit_index = 31 then
                            bit_index <= 0;
                            lrclk_int <= '0';
                            shift_reg <= std_logic_vector(audio_left);
                            din_int <= audio_left(15);
                            frame_tick <= '1';
                        elsif bit_index = 15 then
                            bit_index <= 16;
                            lrclk_int <= '1';
                            shift_reg <= std_logic_vector(audio_right);
                            din_int <= audio_right(15);
                        else
                            bit_index <= bit_index + 1;
                            shift_reg <= shift_reg(14 downto 0) & '0';
                            din_int <= shift_reg(14);
                        end if;
                    end if;
                else
                    phase_counter <= phase_counter + 1;
                end if;
            end if;
        end if;
    end process;

    i2s_bclk <= bclk_int;
    i2s_lrclk <= lrclk_int;
    i2s_din <= din_int;
end architecture;
