library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

-- 左旋钮：选择项目/包络参数；左按：进入或确认保存。
-- 右旋钮：修改草稿值；右按：取消本页修改并返回。
entity menu_ui is
    generic (
        G_DEFAULT_TONE    : natural range 0 to 3 := 0;
        G_DEFAULT_VOLUME  : natural range 0 to 100 := 50;
        G_DEFAULT_ATTACK  : natural range 0 to 2000 := 20;
        G_DEFAULT_DECAY   : natural range 0 to 2000 := 100;
        G_DEFAULT_SUSTAIN : natural range 0 to 100 := 70;
        G_DEFAULT_RELEASE : natural range 0 to 5000 := 200;
        G_TIME_STEP_MS    : positive range 1 to 1000 := 10
    );
    port (
        clk, reset_n : in std_logic;
        left_next, left_prev, left_press : in std_logic;
        right_next, right_prev, right_press : in std_logic;
        page_o : out page_t;
        cursor_o : out natural range 0 to 3;
        view_o, settings_o : out settings_t
    );
end entity;

architecture rtl of menu_ui is
    constant INITIAL : settings_t := (G_DEFAULT_TONE, G_DEFAULT_VOLUME,
        G_DEFAULT_ATTACK, G_DEFAULT_DECAY, G_DEFAULT_SUSTAIN, G_DEFAULT_RELEASE);
    signal page : page_t := HOME_PAGE;
    signal home_cursor, adsr_cursor : natural range 0 to 3 := 0;
    signal saved, draft : settings_t := INITIAL;
    function adjusted(value, amount, maximum : integer) return natural is
        variable result : integer := value + amount;
    begin
        if result < 0 then return 0;
        elsif result > maximum then return maximum;
        else return result; end if;
    end function;
begin
    process(clk)
        variable direction : integer range -1 to 1;
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                page <= HOME_PAGE; home_cursor <= 0; adsr_cursor <= 0;
                saved <= INITIAL; draft <= INITIAL;
            elsif page = HOME_PAGE then
                if left_press = '1' then
                    draft <= saved; adsr_cursor <= 0;
                    case home_cursor is
                        when 0 => page <= TONE_PAGE;
                        when 1 => page <= VOLUME_PAGE;
                        when 2 => page <= ADSR_PAGE;
                        when others => page <= SYSTEM_PAGE;
                    end case;
                elsif left_next = '1' then home_cursor <= (home_cursor + 1) mod 4;
                elsif left_prev = '1' then home_cursor <= (home_cursor + 3) mod 4;
                end if;
            elsif right_press = '1' then
                draft <= saved; page <= HOME_PAGE;
            elsif left_press = '1' then
                if page /= SYSTEM_PAGE then saved <= draft; end if;
                page <= HOME_PAGE;
            else
                if page = ADSR_PAGE then
                    if left_next = '1' then adsr_cursor <= (adsr_cursor + 1) mod 4;
                    elsif left_prev = '1' then adsr_cursor <= (adsr_cursor + 3) mod 4;
                    end if;
                end if;
                direction := 0;
                if right_next = '1' then direction := 1;
                elsif right_prev = '1' then direction := -1; end if;
                if direction /= 0 then
                    case page is
                        when TONE_PAGE => draft.tone <= (draft.tone + direction + 4) mod 4;
                        when VOLUME_PAGE => draft.volume <= adjusted(draft.volume, direction, 100);
                        when ADSR_PAGE =>
                            case adsr_cursor is
                                when 0 => draft.attack_ms <= adjusted(draft.attack_ms, direction * G_TIME_STEP_MS, 2000);
                                when 1 => draft.decay_ms <= adjusted(draft.decay_ms, direction * G_TIME_STEP_MS, 2000);
                                when 2 => draft.sustain <= adjusted(draft.sustain, direction, 100);
                                when others => draft.release_ms <= adjusted(draft.release_ms, direction * G_TIME_STEP_MS, 5000);
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
