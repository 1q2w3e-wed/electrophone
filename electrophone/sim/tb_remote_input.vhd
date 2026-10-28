library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use std.env.all;

entity tb_remote_input is
end entity;

architecture sim of tb_remote_input is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal key_down, key_up, key_all_up, clear : std_logic := '0';
    signal key_note : note_index_t := 0;
    signal key_velocity : natural range 0 to 31 := 0;
    signal key_tone : tone_index_t := 0;
    signal key_effect : natural range 0 to 3 := 0;
    signal on_o : std_logic_vector(7 downto 0);
    signal levels_o : sensor_array_t;
    signal tones_o : tone_array_t;
    signal effects_o : effect_array_t;
    signal last_tone_o : tone_index_t;
    signal last_effect_o : natural range 0 to 3;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.remote_input
        port map (
            clk => clk, rst_n => rst_n,
            key_down => key_down, key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            clear => clear,
            on_o => on_o, levels_o => levels_o,
            tones_o => tones_o, effects_o => effects_o,
            last_tone_o => last_tone_o, last_effect_o => last_effect_o
        );

    stimulus: process
        procedure pulse(constant signal_name : string) is
        begin
            wait until falling_edge(clk);
            if signal_name = "down" then
                key_down <= '1';
            elsif signal_name = "up" then
                key_up <= '1';
            elsif signal_name = "all" then
                key_all_up <= '1';
            else
                clear <= '1';
            end if;
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            key_down <= '0';
            key_up <= '0';
            key_all_up <= '0';
            clear <= '0';
            wait until rising_edge(clk);
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        key_note <= 6;
        key_velocity <= 27;
        key_tone <= 3;
        key_effect <= 1;
        pulse("down");
        assert on_o = "01000000"
            report "KEY DOWN did not set only note 6" severity failure;
        assert levels_o(6) = to_unsigned(864, 10)
            report "KEY DOWN velocity scaling is incorrect" severity failure;
        assert tones_o(6) = 3 and effects_o(6) = 1
            report "KEY DOWN tone/effect was not stored" severity failure;
        assert last_tone_o = 3 and last_effect_o = 1
            report "Latest remote tone/effect was not retained"
            severity failure;

        key_note <= 2;
        key_velocity <= 16;
        key_tone <= 1;
        key_effect <= 2;
        pulse("down");
        assert on_o = "01000100"
            report "Second KEY DOWN did not preserve the first note"
            severity failure;

        key_note <= 6;
        pulse("up");
        assert on_o = "00000100"
            report "KEY UP released the wrong note" severity failure;
        assert levels_o(6) = 0
            report "KEY UP did not clear pressure" severity failure;

        pulse("all");
        assert on_o = (on_o'range => '0')
            report "KEY ALL UP did not release every note" severity failure;

        key_note <= 4;
        key_velocity <= 20;
        pulse("down");
        pulse("clear");
        assert on_o = (on_o'range => '0')
            report "STOP/playback clear did not release remote notes"
            severity failure;

        report "tb_remote_input passed" severity note;
        stop;
        wait;
    end process;
end architecture;
