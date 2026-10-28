library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_audio_scope is
end entity;

architecture sim of tb_audio_scope is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_in : signed(15 downto 0) := (others => '0');
    signal frame_start : std_logic := '0';
    signal read_index : natural range 0 to 479 := 0;
    signal audio_sample : signed(15 downto 0);
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.audio_scope
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            sample_in => sample_in,
            frame_start => frame_start,
            read_index => read_index,
            audio_sample => audio_sample
        );

    stimulus: process
        procedure check_sample(index : natural; expected : integer) is
        begin
            wait until falling_edge(clk);
            read_index <= index;
            wait until rising_edge(clk);
            wait for 1 ns;
            assert to_integer(audio_sample) = expected
                report "Scope sample mismatch" severity failure;
        end procedure;

        procedure tick_sample(value : integer) is
        begin
            wait until falling_edge(clk);
            sample_in <= to_signed(value, 16);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            wait until rising_edge(clk);
        end procedure;

        procedure start_frame is
        begin
            frame_start <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            frame_start <= '0';
            wait for 1 ns;
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait for 3*CLK_PERIOD;

        -- Arm capture, then begin at the first positive zero crossing.
        start_frame;
        tick_sample(-100);
        tick_sample(0);
        for i in 0 to 511 loop
            tick_sample(i);
        end loop;

        start_frame;
        check_sample(0, 0);
        check_sample(1, 1);
        check_sample(479, 479);

        -- The read bank must remain stable during the next capture.
        start_frame;
        tick_sample(-100);
        tick_sample(0);
        for i in 0 to 100 loop
            tick_sample(-1000-i);
        end loop;
        check_sample(479, 479);
        assert to_integer(audio_sample) = 479
            report "Display bank changed during capture" severity failure;

        for i in 101 to 511 loop
            tick_sample(-1000-i);
        end loop;
        start_frame;
        check_sample(0, -1000);
        assert to_integer(audio_sample) = -1000
            report "Second scope bank was not selected" severity failure;

        report "tb_audio_scope passed" severity note;
        wait;
    end process;
end architecture;
