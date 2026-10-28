library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

entity tb_touch_menu_ui is
end entity;

architecture sim of tb_touch_menu_ui is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal left_next, left_prev, left_press : std_logic := '0';
    signal right_next, right_prev, right_press : std_logic := '0';
    signal touch_tap : std_logic := '0';
    signal touch_x : natural range 0 to 479 := 0;
    signal touch_y : natural range 0 to 319 := 0;
    signal page : page_t;
    signal cursor : natural range 0 to 3;
    signal view, saved : settings_t;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.touch_menu_ui
        port map (
            clk => clk, reset_n => reset_n,
            left_next => left_next, left_prev => left_prev, left_press => left_press,
            right_next => right_next, right_prev => right_prev, right_press => right_press,
            touch_tap => touch_tap, touch_x => touch_x, touch_y => touch_y,
            page_o => page, cursor_o => cursor, view_o => view, settings_o => saved
        );

    stimulus: process
        procedure tap(x, y : natural) is
        begin
            wait until falling_edge(clk);
            touch_x <= x;
            touch_y <= y;
            wait until rising_edge(clk);
            touch_tap <= '1';
            wait until rising_edge(clk);
            touch_tap <= '0';
            wait until rising_edge(clk);
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait for 3*CLK_PERIOD;
        assert page = HOME_PAGE severity failure;

        -- 触摸坐标会有少量偏差，卡片外侧留出容错范围也应能点中。
        tap(14, 130); -- just outside HOME TONE
        assert page = TONE_PAGE severity failure;
        tap(350, 120); -- SQUARE
        assert view.tone = 1 severity failure;
        tap(390, 289); -- SAVE
        assert page = HOME_PAGE and saved.tone = 1 severity failure;

        tap(350, 130); -- HOME VOLUME
        assert page = VOLUME_PAGE severity failure;
        tap(410, 220); -- PLUS
        assert view.volume = 51 severity failure;
        tap(390, 289); -- SAVE
        assert page = HOME_PAGE and saved.volume = 51 severity failure;

        tap(120, 230); -- HOME ADSR
        assert page = ADSR_PAGE severity failure;
        tap(100, 166); -- select SUSTAIN row
        assert cursor = 2 severity failure;
        tap(400, 170); -- plus sustain
        assert view.sustain = 71 severity failure;
        tap(390, 289); -- save
        assert page = HOME_PAGE and saved.sustain = 71 severity failure;

        tap(350, 230); -- HOME SYSTEM
        assert page = SYSTEM_PAGE severity failure;
        tap(80, 289); -- BACK
        assert page = HOME_PAGE severity failure;

        report "tb_touch_menu_ui passed" severity note;
        wait;
    end process;
end architecture;
