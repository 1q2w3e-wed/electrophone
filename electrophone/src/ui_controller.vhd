library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

-- 双 EC11 单屏控制器。
-- 左旋：选择参数；右键：调节当前参数。
-- 左按：切换波形/包络预览；右按：恢复默认值或开关踏板模式。
entity ui_controller is
    generic (
        G_CLK_HZ          : positive := 50_000_000;
        G_DEFAULT_TONE    : natural range 0 to 3 := 0;
        G_DEFAULT_VOLUME  : natural range 0 to 100 := 50;
        G_DEFAULT_ATTACK  : natural range 0 to 2000 := 20;
        G_DEFAULT_DECAY   : natural range 0 to 2000 := 100;
        G_DEFAULT_SUSTAIN : natural range 0 to 100 := 70;
        G_DEFAULT_RELEASE : natural range 0 to 5000 := 200;
        G_DEFAULT_BEND    : integer range -200 to 200 := 0;
        G_DEFAULT_VIBRATO : natural range 0 to 50 := 20;
        G_DEFAULT_GLIDE   : natural range 0 to 1000 := 80;
        G_DEFAULT_EFFECT  : effect_mode_t := FX_DRY;
        G_TIME_STEP_MS    : positive range 1 to 1000 := 10;
        G_STATUS_MS       : positive range 100 to 5000 := 800
    );
    port (
        clk, reset_n : in std_logic;
        left_next, left_prev, left_press   : in std_logic;
        right_next, right_prev, right_press: in std_logic;
        voices_idle : in std_logic;
        focus_o   : out focus_t;
        preview_o : out preview_t;
        settings_o: out settings_t;
        status_o  : out status_t;
        pedal_mode_o : out std_logic;
        octave_shift_o : out std_logic;
        score_available : in std_logic;
        score_control_o : out std_logic
    );
end entity;

architecture rtl of ui_controller is
    constant INITIAL : settings_t := (
        G_DEFAULT_TONE, G_DEFAULT_VOLUME, G_DEFAULT_ATTACK,
        G_DEFAULT_DECAY, G_DEFAULT_SUSTAIN, G_DEFAULT_RELEASE,
        G_DEFAULT_BEND, G_DEFAULT_VIBRATO, G_DEFAULT_GLIDE,
        G_DEFAULT_EFFECT);
    constant STATUS_CYCLES : positive := (G_CLK_HZ / 1000) * G_STATUS_MS;

    signal focus   : focus_t := FOCUS_TIMBRE;
    signal preview : preview_t := PREVIEW_AUDIO;
    signal cfg     : settings_t := INITIAL;
    signal status_count : natural range 0 to STATUS_CYCLES := 0;
    signal note_seen : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal octave_shift : std_logic := '0';
    signal pluck_mode : std_logic := '0';
    signal pluck_saved_sustain : natural range 0 to 100 :=
        G_DEFAULT_SUSTAIN;
    signal score_control_pulse : std_logic := '0';

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

    function focus_after(current : focus_t; direction : integer)
        return focus_t is
        constant FOCUS_COUNT : positive := focus_t'pos(focus_t'high) + 1;
        variable index_v : integer := focus_t'pos(current);
    begin
        index_v := (index_v + direction + FOCUS_COUNT) mod FOCUS_COUNT;
        return focus_t'val(index_v);
    end function;

    function effect_after(current : effect_mode_t; direction : integer)
        return effect_mode_t is
        constant EFFECT_COUNT : positive :=
            effect_mode_t'pos(effect_mode_t'high) + 1;
        variable index_v : integer := effect_mode_t'pos(current);
    begin
        index_v := (index_v + direction + EFFECT_COUNT) mod EFFECT_COUNT;
        return effect_mode_t'val(index_v);
    end function;

    function adjusted_signed(value, amount, minimum, maximum : integer)
        return integer is
        variable result : integer := value + amount;
    begin
        if result < minimum then
            return minimum;
        elsif result > maximum then
            return maximum;
        else
            return result;
        end if;
    end function;

begin
    process(clk)
        variable direction : integer range -1 to 1;
    begin
        if rising_edge(clk) then
            score_control_pulse <= '0';
            if reset_n = '0' then
                focus <= FOCUS_TIMBRE;
                preview <= PREVIEW_AUDIO;
                cfg <= INITIAL;
                status_count <= 0;
                note_seen <= '0';
                pedal_mode <= '0';
                octave_shift <= '0';
                pluck_mode <= '0';
                pluck_saved_sustain <= G_DEFAULT_SUSTAIN;
                score_control_pulse <= '0';
            else
                if status_count /= 0 then
                    status_count <= status_count - 1;
                end if;

                direction := 0;
                if right_next = '1' then
                    direction := 1;
                elsif right_prev = '1' then
                    direction := -1;
                end if;

                if right_press = '1' then
                    if pedal_mode = '1' then
                        pedal_mode <= '0';
                    elsif focus = FOCUS_TIMBRE then
                        pedal_mode <= '1';
                        if pluck_mode = '1' then
                            pluck_mode <= '0';
                            cfg.sustain <= pluck_saved_sustain;
                        end if;
                    else
                        case focus is
                            when FOCUS_TIMBRE  => cfg.tone <= G_DEFAULT_TONE;
                            when FOCUS_VOLUME  => cfg.volume <= G_DEFAULT_VOLUME;
                            when FOCUS_ATTACK  => cfg.attack_ms <= G_DEFAULT_ATTACK;
                            when FOCUS_DECAY   => cfg.decay_ms <= G_DEFAULT_DECAY;
                            when FOCUS_SUSTAIN => cfg.sustain <= G_DEFAULT_SUSTAIN;
                            when FOCUS_RELEASE => cfg.release_ms <= G_DEFAULT_RELEASE;
                            when FOCUS_BEND    => cfg.bend_cents <= G_DEFAULT_BEND;
                            when FOCUS_VIBRATO => cfg.vibrato_cents <= G_DEFAULT_VIBRATO;
                            when FOCUS_GLIDE   => cfg.glide_ms <= G_DEFAULT_GLIDE;
                            when FOCUS_PLUCK   =>
                                if pluck_mode = '1' then
                                    pluck_mode <= '0';
                                    cfg.sustain <= pluck_saved_sustain;
                                else
                                    pluck_saved_sustain <= cfg.sustain;
                                    cfg.sustain <= 0;
                                    pluck_mode <= '1';
                                    pedal_mode <= '0';
                                end if;
                            when FOCUS_EFFECT  => cfg.effect_mode <= G_DEFAULT_EFFECT;
                            when FOCUS_OCTAVE  =>
                                if score_available = '1' then
                                    score_control_pulse <= '1';
                                else
                                    octave_shift <= '0';
                                end if;
                        end case;
                        status_count <= STATUS_CYCLES;
                    end if;
                elsif left_press = '1' then
                    case preview is
                        when PREVIEW_AUDIO => preview <= PREVIEW_SPECTRUM;
                        when PREVIEW_SPECTRUM => preview <= PREVIEW_LISSAJOUS;
                        when PREVIEW_LISSAJOUS => preview <= PREVIEW_PRESSURE;
                        when PREVIEW_PRESSURE => preview <= PREVIEW_ENVELOPE;
                        when others => preview <= PREVIEW_AUDIO;
                    end case;
                elsif left_next = '1' then
                    focus <= focus_after(focus, 1);
                elsif left_prev = '1' then
                    focus <= focus_after(focus, -1);
                elsif direction /= 0 then
                    if pedal_mode = '1' then
                        cfg.tone <= (cfg.tone + direction + 4) mod 4;
                    else
                        case focus is
                            when FOCUS_TIMBRE =>
                                cfg.tone <= (cfg.tone + direction + 4) mod 4;
                            when FOCUS_VOLUME =>
                                cfg.volume <= adjusted(cfg.volume, direction, 100);
                            when FOCUS_ATTACK =>
                                cfg.attack_ms <= adjusted(
                                    cfg.attack_ms, direction*G_TIME_STEP_MS, 2000);
                            when FOCUS_DECAY =>
                                cfg.decay_ms <= adjusted(
                                    cfg.decay_ms, direction*G_TIME_STEP_MS, 2000);
                            when FOCUS_SUSTAIN =>
                                if pluck_mode = '1' then
                                    pluck_mode <= '0';
                                end if;
                                cfg.sustain <= adjusted(cfg.sustain, direction, 100);
                            when FOCUS_RELEASE =>
                                cfg.release_ms <= adjusted(
                                    cfg.release_ms, direction*G_TIME_STEP_MS, 5000);
                            when FOCUS_BEND =>
                                cfg.bend_cents <= adjusted_signed(
                                    cfg.bend_cents, direction*10, -200, 200);
                            when FOCUS_VIBRATO =>
                                cfg.vibrato_cents <= adjusted(
                                    cfg.vibrato_cents, direction*2, 50);
                            when FOCUS_GLIDE =>
                                cfg.glide_ms <= adjusted(
                                    cfg.glide_ms, direction*G_TIME_STEP_MS, 1000);
                            when FOCUS_PLUCK =>
                                if direction > 0 and pluck_mode = '0' then
                                    pluck_saved_sustain <= cfg.sustain;
                                    cfg.sustain <= 0;
                                    pluck_mode <= '1';
                                    pedal_mode <= '0';
                                elsif direction < 0 and pluck_mode = '1' then
                                    cfg.sustain <= pluck_saved_sustain;
                                    pluck_mode <= '0';
                                end if;
                            when FOCUS_EFFECT =>
                                cfg.effect_mode <= effect_after(
                                    cfg.effect_mode, direction);
                            when FOCUS_OCTAVE =>
                                octave_shift <= not octave_shift;
                        end case;
                    end if;
                end if;

                if voices_idle = '0' then
                    note_seen <= '1';
                elsif note_seen = '1' then
                    cfg.bend_cents <= 0;
                    note_seen <= '0';
                end if;
            end if;
        end if;
    end process;

    focus_o <= focus;
    preview_o <= preview;
    settings_o <= cfg;
    status_o <= STATUS_RESET when status_count /= 0 else STATUS_NONE;
    pedal_mode_o <= pedal_mode;
    octave_shift_o <= octave_shift;
    score_control_o <= score_control_pulse;
end architecture;
