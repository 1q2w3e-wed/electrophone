library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;
use work.ui_layout.all;

-- 触摸菜单和 EC11 共用的界面状态机。
-- 左旋钮：选择；左键：进入/保存。
-- 右旋钮：调节；右键：取消/返回。
-- 触摸：直接点卡片、音色、加减和保存/返回按钮。
entity touch_menu_ui is
    generic (
        G_DEFAULT_TONE    : natural range 0 to 3 := 0;
        G_DEFAULT_VOLUME  : natural range 0 to 100 := 50;
        G_DEFAULT_ATTACK  : natural range 0 to 2000 := 20;
        G_DEFAULT_DECAY   : natural range 0 to 2000 := 100;
        G_DEFAULT_SUSTAIN : natural range 0 to 100 := 70;
        G_DEFAULT_RELEASE : natural range 0 to 5000 := 200;
        G_TIME_STEP_MS    : positive range 1 to 1000 := 10;
        G_TOUCH_HIT_MARGIN: natural range 0 to 20 := 10
    );
    port (
        clk, reset_n : in std_logic;
        left_next, left_prev, left_press : in std_logic;
        right_next, right_prev, right_press : in std_logic;
        touch_tap : in std_logic;
        touch_x   : in natural range 0 to SCREEN_W-1;
        touch_y   : in natural range 0 to SCREEN_H-1;
        page_o    : out page_t;
        cursor_o  : out natural range 0 to 3;
        view_o    : out settings_t;
        settings_o: out settings_t
    );
end entity;

architecture rtl of touch_menu_ui is
    constant INITIAL : settings_t := (
        G_DEFAULT_TONE, G_DEFAULT_VOLUME, G_DEFAULT_ATTACK,
        G_DEFAULT_DECAY, G_DEFAULT_SUSTAIN, G_DEFAULT_RELEASE);

    signal page : page_t := HOME_PAGE;
    signal home_cursor, adsr_cursor : natural range 0 to 3 := 0;
    signal saved, draft : settings_t := INITIAL;

    function adjusted(value, amount, maximum : integer) return natural is
        variable result : integer := value + amount;
    begin
        if result < 0 then
            return 0;
        elsif result > maximum then
            return maximum;
        else
            return result;
        end if;
    end function;

    function row_top(row : natural) return natural is
    begin
        return ADSR_ROW_Y0 + row * ADSR_ROW_STEP;
    end function;

    -- 按钮外围也接受触摸，抵消电阻屏的少量坐标偏差。
    function hit(x, y, x0, y0, x1, y1 : natural) return boolean is
        variable left, top : natural;
    begin
        if x0 > G_TOUCH_HIT_MARGIN then
            left := x0 - G_TOUCH_HIT_MARGIN;
        else
            left := 0;
        end if;
        if y0 > G_TOUCH_HIT_MARGIN then
            top := y0 - G_TOUCH_HIT_MARGIN;
        else
            top := 0;
        end if;
        return x >= left and x <= x1 + G_TOUCH_HIT_MARGIN and
               y >= top  and y <= y1 + G_TOUCH_HIT_MARGIN;
    end function;
begin
    process(clk)
        variable row_y : natural;
        variable direction : integer range -1 to 1;
        variable card_hit : boolean;
    begin
        if rising_edge(clk) then
            card_hit := false;
            if reset_n = '0' then
                page <= HOME_PAGE;
                home_cursor <= 0;
                adsr_cursor <= 0;
                saved <= INITIAL;
                draft <= INITIAL;
            elsif touch_tap = '1' then
                -- 首页四个卡片
                if page = HOME_PAGE then
                    if hit(touch_x, touch_y, HOME_TONE_X0, HOME_TONE_Y0, HOME_TONE_X1, HOME_TONE_Y1) then
                        page <= TONE_PAGE; card_hit := true;
                    elsif hit(touch_x, touch_y, HOME_VOL_X0, HOME_VOL_Y0, HOME_VOL_X1, HOME_VOL_Y1) then
                        page <= VOLUME_PAGE; card_hit := true;
                    elsif hit(touch_x, touch_y, HOME_ADSR_X0, HOME_ADSR_Y0, HOME_ADSR_X1, HOME_ADSR_Y1) then
                        page <= ADSR_PAGE; card_hit := true;
                    elsif hit(touch_x, touch_y, HOME_SYS_X0, HOME_SYS_Y0, HOME_SYS_X1, HOME_SYS_Y1) then
                        page <= SYSTEM_PAGE; card_hit := true;
                    end if;
                    if card_hit then
                        draft <= saved;
                        adsr_cursor <= 0;
                    end if;
                -- 音色页四个按钮
                elsif page = TONE_PAGE then
                    if hit(touch_x, touch_y, TONE_SINE_X0, TONE_SINE_Y0, TONE_SINE_X1, TONE_SINE_Y1) then
                        draft.tone <= 0;
                    elsif hit(touch_x, touch_y, TONE_SQUARE_X0, TONE_SQUARE_Y0, TONE_SQUARE_X1, TONE_SQUARE_Y1) then
                        draft.tone <= 1;
                    elsif hit(touch_x, touch_y, TONE_SAW_X0, TONE_SAW_Y0, TONE_SAW_X1, TONE_SAW_Y1) then
                        draft.tone <= 2;
                    elsif hit(touch_x, touch_y, TONE_TRI_X0, TONE_TRI_Y0, TONE_TRI_X1, TONE_TRI_Y1) then
                        draft.tone <= 3;
                    elsif hit(touch_x, touch_y, BACK_X0, ACTION_Y0, BACK_X1, ACTION_Y1) then
                        draft <= saved;
                        page <= HOME_PAGE;
                    elsif hit(touch_x, touch_y, SAVE_X0, ACTION_Y0, SAVE_X1, ACTION_Y1) then
                        saved <= draft;
                        page <= HOME_PAGE;
                    end if;
                -- 音量页
                elsif page = VOLUME_PAGE then
                    if hit(touch_x, touch_y, VOL_MINUS_X0, VOL_MINUS_Y0, VOL_MINUS_X1, VOL_MINUS_Y1) then
                        draft.volume <= adjusted(draft.volume, -1, 100);
                    elsif hit(touch_x, touch_y, VOL_PLUS_X0, VOL_PLUS_Y0, VOL_PLUS_X1, VOL_PLUS_Y1) then
                        draft.volume <= adjusted(draft.volume, 1, 100);
                    elsif hit(touch_x, touch_y, BACK_X0, ACTION_Y0, BACK_X1, ACTION_Y1) then
                        draft <= saved;
                        page <= HOME_PAGE;
                    elsif hit(touch_x, touch_y, SAVE_X0, ACTION_Y0, SAVE_X1, ACTION_Y1) then
                        saved <= draft;
                        page <= HOME_PAGE;
                    end if;
                -- ADSR 页：点行选参数，点 +/- 调值
                elsif page = ADSR_PAGE then
                    if inside(touch_x, touch_y, ADSR_ROW_X0, ADSR_ROW_Y0, ADSR_ROW_X1,
                             ADSR_ROW_Y0 + 4*ADSR_ROW_STEP) then
                        for row in 0 to 3 loop
                            row_y := row_top(row);
                            if touch_y >= row_y and touch_y < row_y + ADSR_ROW_STEP then
                                adsr_cursor <= row;
                            end if;
                        end loop;
                    end if;
                    for row in 0 to 3 loop
                        row_y := row_top(row);
                        if touch_y >= row_y and touch_y < row_y + ADSR_ROW_STEP then
                            if hit(touch_x, touch_y, ADSR_MINUS_X0, row_y, ADSR_MINUS_X1, row_y+32) then
                                case row is
                                    when 0 => draft.attack_ms <= adjusted(draft.attack_ms, -G_TIME_STEP_MS, 2000);
                                    when 1 => draft.decay_ms <= adjusted(draft.decay_ms, -G_TIME_STEP_MS, 2000);
                                    when 2 => draft.sustain <= adjusted(draft.sustain, -1, 100);
                                    when others => draft.release_ms <= adjusted(draft.release_ms, -G_TIME_STEP_MS, 5000);
                                end case;
                            elsif hit(touch_x, touch_y, ADSR_PLUS_X0, row_y, ADSR_PLUS_X1, row_y+32) then
                                case row is
                                    when 0 => draft.attack_ms <= adjusted(draft.attack_ms, G_TIME_STEP_MS, 2000);
                                    when 1 => draft.decay_ms <= adjusted(draft.decay_ms, G_TIME_STEP_MS, 2000);
                                    when 2 => draft.sustain <= adjusted(draft.sustain, 1, 100);
                                    when others => draft.release_ms <= adjusted(draft.release_ms, G_TIME_STEP_MS, 5000);
                                end case;
                            end if;
                        end if;
                    end loop;
                    if hit(touch_x, touch_y, BACK_X0, ACTION_Y0, BACK_X1, ACTION_Y1) then
                        draft <= saved;
                        page <= HOME_PAGE;
                    elsif hit(touch_x, touch_y, SAVE_X0, ACTION_Y0, SAVE_X1, ACTION_Y1) then
                        saved <= draft;
                        page <= HOME_PAGE;
                    end if;
                -- 系统页
                else
                    if hit(touch_x, touch_y, BACK_X0, ACTION_Y0, BACK_X1, ACTION_Y1) then
                        page <= HOME_PAGE;
                    end if;
                end if;
            -- 没有触摸时仍保留 EC11 操作
            elsif page = HOME_PAGE then
                if left_press = '1' then
                    draft <= saved;
                    adsr_cursor <= 0;
                    case home_cursor is
                        when 0 => page <= TONE_PAGE;
                        when 1 => page <= VOLUME_PAGE;
                        when 2 => page <= ADSR_PAGE;
                        when others => page <= SYSTEM_PAGE;
                    end case;
                elsif left_next = '1' then
                    home_cursor <= (home_cursor + 1) mod 4;
                elsif left_prev = '1' then
                    home_cursor <= (home_cursor + 3) mod 4;
                end if;
            elsif right_press = '1' then
                draft <= saved;
                page <= HOME_PAGE;
            elsif left_press = '1' then
                if page /= SYSTEM_PAGE then
                    saved <= draft;
                end if;
                page <= HOME_PAGE;
            else
                if page = ADSR_PAGE then
                    if left_next = '1' then
                        adsr_cursor <= (adsr_cursor + 1) mod 4;
                    elsif left_prev = '1' then
                        adsr_cursor <= (adsr_cursor + 3) mod 4;
                    end if;
                end if;
                direction := 0;
                if right_next = '1' then
                    direction := 1;
                elsif right_prev = '1' then
                    direction := -1;
                end if;
                if direction /= 0 then
                    case page is
                        when TONE_PAGE => draft.tone <= (draft.tone + direction + 4) mod 4;
                        when VOLUME_PAGE => draft.volume <= adjusted(draft.volume, direction, 100);
                        when ADSR_PAGE =>
                            case adsr_cursor is
                                when 0 => draft.attack_ms <= adjusted(draft.attack_ms, direction*G_TIME_STEP_MS, 2000);
                                when 1 => draft.decay_ms <= adjusted(draft.decay_ms, direction*G_TIME_STEP_MS, 2000);
                                when 2 => draft.sustain <= adjusted(draft.sustain, direction, 100);
                                when others => draft.release_ms <= adjusted(draft.release_ms, direction*G_TIME_STEP_MS, 5000);
                            end case;
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    page_o <= page;
    cursor_o <= adsr_cursor when page = ADSR_PAGE else home_cursor;
    view_o <= saved when page = HOME_PAGE else draft;
    settings_o <= saved;
end architecture;
