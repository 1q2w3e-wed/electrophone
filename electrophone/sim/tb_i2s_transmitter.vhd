library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_i2s_transmitter is
end entity;

architecture sim of tb_i2s_transmitter is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal audio_left : signed(15 downto 0) := x"8000";
    signal audio_right : signed(15 downto 0) := x"4000";
    signal frame_tick, i2s_lrclk, i2s_bclk, i2s_din : std_logic;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.i2s_transmitter
        generic map (CLK_PER_HALF_BIT => 2)
        port map (
            clk => clk, rst_n => rst_n,
            audio_left => audio_left, audio_right => audio_right,
            frame_tick => frame_tick,
            i2s_lrclk => i2s_lrclk,
            i2s_bclk => i2s_bclk,
            i2s_din => i2s_din
        );

    stimulus: process
        variable left_capture, right_capture : std_logic_vector(15 downto 0);
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until rising_edge(clk) and frame_tick = '1';
        assert i2s_lrclk = '0' severity failure;
        for bit_index in 0 to 15 loop
            wait until rising_edge(i2s_bclk);
            left_capture := left_capture(14 downto 0) & i2s_din;
        end loop;
        assert left_capture = std_logic_vector(audio_left)
            report "I2S left channel mismatch" severity failure;

        wait until i2s_lrclk = '1';
        for bit_index in 0 to 15 loop
            wait until rising_edge(i2s_bclk);
            right_capture := right_capture(14 downto 0) & i2s_din;
        end loop;
        assert right_capture = std_logic_vector(audio_right)
            report "I2S right channel mismatch" severity failure;

        report "tb_i2s_transmitter passed" severity note;
        wait;
    end process;
end architecture;
