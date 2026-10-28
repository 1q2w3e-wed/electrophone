library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use work.ui_layout.all;

-- 三种预览：真实音频示波器、八路压力柱图、ADSR 包络。
entity wave_preview is
    port (
        clk, reset_n : in  std_logic;
        settings_i : in  settings_t;
        preview_i  : in  preview_t;
        focus_i    : in  focus_t;
        audio_sample_i : in audio_sample_t;
        sensor_levels_i: in sensor_array_t;
        spectrum_level_i : in unsigned(7 downto 0);
        note_active_i : in std_logic_vector(7 downto 0);
        octave_shift_i : in std_logic;
        lissajous_pixel_i : in std_logic;
        pixel_x_i  : in  natural range 0 to SCREEN_W-1;
        pixel_y_i  : in  natural range 0 to SCREEN_H-1;
        color_o    : out rgb565_t
    );
end entity;

architecture rtl of wave_preview is
    function rgb565(r, g, b : natural) return rgb565_t is
        variable result : rgb565_t;
        variable rv : natural := r;
        variable gv : natural := g;
        variable bv : natural := b;
    begin
        if rv > 31 then rv := 31; end if;
        if gv > 63 then gv := 63; end if;
        if bv > 31 then bv := 31; end if;
        result(15 downto 11) := std_logic_vector(to_unsigned(rv, 5));
        result(10 downto 5) := std_logic_vector(to_unsigned(gv, 6));
        result(4 downto 0) := std_logic_vector(to_unsigned(bv, 5));
        return result;
    end function;

    function focus_number(which : focus_t) return natural is
    begin
        case which is
            when FOCUS_TIMBRE  => return 0;
            when FOCUS_VOLUME  => return 1;
            when FOCUS_ATTACK  => return 2;
            when FOCUS_DECAY   => return 3;
            when FOCUS_SUSTAIN => return 4;
            when FOCUS_RELEASE => return 5;
            when FOCUS_BEND    => return 6;
            when FOCUS_VIBRATO => return 7;
            when FOCUS_GLIDE   => return 8;
            when FOCUS_PLUCK   => return 9;
            when FOCUS_EFFECT  => return 10;
            when FOCUS_OCTAVE  => return 11;
        end case;
    end function;

    constant C_BG     : rgb565_t := rgb565(3,6,12);
    constant C_PANEL  : rgb565_t := rgb565(7,15,25);
    constant C_GRID   : rgb565_t := rgb565(10,28,38);
    constant C_AXIS   : rgb565_t := rgb565(14,42,52);
    constant C_WAVE   : rgb565_t := rgb565(2,58,54);
    constant C_PRESS  : rgb565_t := rgb565(4,34,58);
    constant C_PRESS2 : rgb565_t := rgb565(18,12,55);
    constant C_ENV    : rgb565_t := rgb565(20,18,52);
    constant C_ENV_HI : rgb565_t := rgb565(31,18,62);
    constant C_EDGE   : rgb565_t := rgb565(3,42,48);
    constant C_MARK   : rgb565_t := rgb565(31,40,4);
    constant C_SCOPE  : rgb565_t := rgb565(20,63,58);

    signal base_color_next : rgb565_t := C_BG;
    signal base_color_reg  : rgb565_t := C_BG;
    signal color_next : rgb565_t := C_BG;
    signal x_reg, y_reg : natural range 0 to SCREEN_W-1 := 0;
    signal wave_y_reg : integer range PREVIEW_Y0 to PREVIEW_Y1 :=
        (PREVIEW_Y0 + PREVIEW_Y1) / 2;
    signal last_wave_y_reg : integer range PREVIEW_Y0 to PREVIEW_Y1 :=
        (PREVIEW_Y0 + PREVIEW_Y1) / 2;
begin
    process(pixel_x_i, pixel_y_i)
    begin
        base_color_next <= C_BG;
        if inside(pixel_x_i, pixel_y_i,
                  PREVIEW_X0, PREVIEW_Y0, PREVIEW_X1, PREVIEW_Y1) then
            base_color_next <= C_PANEL;
            if pixel_x_i <= PREVIEW_X0+1 or pixel_x_i >= PREVIEW_X1-1 or
               pixel_y_i <= PREVIEW_Y0+1 or pixel_y_i >= PREVIEW_Y1-1 then
                base_color_next <= C_EDGE;
            elsif ((pixel_x_i - PREVIEW_X0) mod 48 = 0) or
                  ((pixel_y_i - PREVIEW_Y0) mod 24 = 0) then
                base_color_next <= C_GRID;
            end if;
        end if;
    end process;

    process(settings_i, preview_i, focus_i, sensor_levels_i,
            spectrum_level_i, note_active_i, octave_shift_i,
            lissajous_pixel_i, base_color_reg, x_reg, y_reg, wave_y_reg,
            last_wave_y_reg)
        variable x, y : natural;
        variable center_y : integer;
        variable bar_index : natural;
        variable bar_x, bar_top, height_live : natural;
        variable segment_top, segment_bottom : integer;
    begin
        x := x_reg;
        y := y_reg;
        center_y := (PREVIEW_Y0 + PREVIEW_Y1) / 2;
        bar_index := 99;
        bar_x := 0;
        bar_top := PREVIEW_Y1;
        height_live := 0;
        color_next <= base_color_reg;

        if inside(x, y, PREVIEW_X0, PREVIEW_Y0, PREVIEW_X1, PREVIEW_Y1) then
            if preview_i = PREVIEW_AUDIO then
                if x >= PREVIEW_X0+12 and x <= PREVIEW_X1-12 and
                   y >= PREVIEW_Y0+16 and y <= PREVIEW_Y1-8 then
                    segment_top := wave_y_reg;
                    segment_bottom := wave_y_reg;
                    -- 用相邻列之间的小竖线补齐陡峭波形，避免轨迹断成点。
                    if x > PREVIEW_X0+13 then
                        if last_wave_y_reg < segment_top then
                            segment_top := last_wave_y_reg;
                        end if;
                        if last_wave_y_reg > segment_bottom then
                            segment_bottom := last_wave_y_reg;
                        end if;
                    end if;
                    if segment_top > PREVIEW_Y0 then
                        segment_top := segment_top - 1;
                    end if;
                    if segment_bottom < PREVIEW_Y1 then
                        segment_bottom := segment_bottom + 1;
                    end if;
                    if y >= segment_top and y <= segment_bottom then
                        color_next <= C_WAVE;
                    elsif y = center_y then
                        color_next <= C_AXIS;
                    end if;
                end if;
            elsif preview_i = PREVIEW_SPECTRUM then
                if x >= SPECTRUM_X0 and x <= SPECTRUM_X1 then
                    height_live :=
                        (to_integer(spectrum_level_i) * 72) / 255;
                    bar_top := SPECTRUM_BOTTOM - height_live;
                    if y >= bar_top and y <= SPECTRUM_BOTTOM then
                        color_next <= C_WAVE;
                    end if;
                end if;
                if y <= SPECTRUM_BOTTOM and octave_shift_i = '0' then
                    if note_active_i(0) = '1' and x = 233 then color_next <= C_MARK; end if;
                    if note_active_i(1) = '1' and x = 242 then color_next <= C_MARK; end if;
                    if note_active_i(2) = '1' and x = 251 then color_next <= C_MARK; end if;
                    if note_active_i(3) = '1' and x = 256 then color_next <= C_MARK; end if;
                    if note_active_i(4) = '1' and x = 265 then color_next <= C_MARK; end if;
                    if note_active_i(5) = '1' and x = 274 then color_next <= C_MARK; end if;
                    if note_active_i(6) = '1' and x = 283 then color_next <= C_MARK; end if;
                    if note_active_i(7) = '1' and x = 288 then color_next <= C_MARK; end if;
                elsif y <= SPECTRUM_BOTTOM then
                    if note_active_i(0) = '1' and x = 288 then color_next <= C_MARK; end if;
                    if note_active_i(1) = '1' and x = 297 then color_next <= C_MARK; end if;
                    if note_active_i(2) = '1' and x = 306 then color_next <= C_MARK; end if;
                    if note_active_i(3) = '1' and x = 310 then color_next <= C_MARK; end if;
                    if note_active_i(4) = '1' and x = 319 then color_next <= C_MARK; end if;
                    if note_active_i(5) = '1' and x = 328 then color_next <= C_MARK; end if;
                    if note_active_i(6) = '1' and x = 337 then color_next <= C_MARK; end if;
                    if note_active_i(7) = '1' and x = 342 then color_next <= C_MARK; end if;
                end if;
            elsif preview_i = PREVIEW_LISSAJOUS then
                if x >= LISSAJOUS_X0 and x <= LISSAJOUS_X1 and
                   y >= LISSAJOUS_Y0 and y <= LISSAJOUS_Y1 then
                    if x = (LISSAJOUS_X0+LISSAJOUS_X1)/2 or
                       y = (LISSAJOUS_Y0+LISSAJOUS_Y1)/2 then
                        color_next <= C_AXIS;
                    end if;
                    if x = LISSAJOUS_X0 or x = LISSAJOUS_X1 or
                       y = LISSAJOUS_Y0 or y = LISSAJOUS_Y1 then
                        color_next <= C_EDGE;
                    end if;
                    if lissajous_pixel_i = '1' then
                        color_next <= C_SCOPE;
                    end if;
                end if;
            elsif preview_i = PREVIEW_PRESSURE then
                bar_index := 99;
                if x >= 28 and x < 62 then
                    bar_index := 0; bar_x := 28;
                elsif x >= 80 and x < 114 then
                    bar_index := 1; bar_x := 80;
                elsif x >= 132 and x < 166 then
                    bar_index := 2; bar_x := 132;
                elsif x >= 184 and x < 218 then
                    bar_index := 3; bar_x := 184;
                elsif x >= 236 and x < 270 then
                    bar_index := 4; bar_x := 236;
                elsif x >= 288 and x < 322 then
                    bar_index := 5; bar_x := 288;
                elsif x >= 340 and x < 374 then
                    bar_index := 6; bar_x := 340;
                elsif x >= 392 and x < 426 then
                    bar_index := 7; bar_x := 392;
                else
                    bar_x := 0;
                end if;
                if bar_index /= 99 then
                    height_live := 10 +
                        to_integer(sensor_levels_i(bar_index)(9 downto 3));
                    bar_top := PREVIEW_Y1 - 14 - height_live;
                    if x >= bar_x and x < bar_x+34 and
                       y >= bar_top and y <= PREVIEW_Y1-14 then
                        if bar_index mod 2 = 0 then
                            color_next <= C_PRESS;
                        else
                            color_next <= C_PRESS2;
                        end if;
                    end if;
                    if x >= bar_x and x < bar_x+34 and y = bar_top then
                        color_next <= C_WAVE;
                    end if;
                end if;
            else
                bar_index := 99;
                if x >= 52 and x < 92 then
                    bar_index := 0; bar_x := 52;
                    height_live := 16 + settings_i.attack_ms / 32;
                elsif x >= 152 and x < 192 then
                    bar_index := 1; bar_x := 152;
                    height_live := 16 + settings_i.decay_ms / 32;
                elsif x >= 252 and x < 292 then
                    bar_index := 2; bar_x := 252;
                    height_live := 16 + settings_i.sustain / 2;
                elsif x >= 352 and x < 392 then
                    bar_index := 3; bar_x := 352;
                    height_live := 16 + settings_i.release_ms / 64;
                else
                    bar_x := 0;
                end if;
                if bar_index /= 99 then
                    bar_top := PREVIEW_Y1 - 14 - height_live;
                    if x >= bar_x and x < bar_x+40 and
                       y >= bar_top and y <= PREVIEW_Y1-14 then
                        if focus_number(focus_i) = bar_index + 2 then
                            color_next <= C_ENV_HI;
                        else
                            color_next <= C_ENV;
                        end if;
                    end if;
                    if x >= bar_x and x < bar_x+40 and
                       (y = bar_top or y = PREVIEW_Y1-14) then
                        color_next <= C_WAVE;
                    end if;
                end if;
            end if;
        end if;
    end process;

    process(clk)
        variable sample_top : signed(5 downto 0);
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                color_o <= C_BG;
                base_color_reg <= C_BG;
                x_reg <= 0;
                y_reg <= 0;
                wave_y_reg <= (PREVIEW_Y0 + PREVIEW_Y1) / 2;
                last_wave_y_reg <= (PREVIEW_Y0 + PREVIEW_Y1) / 2;
            else
                x_reg <= pixel_x_i;
                y_reg <= pixel_y_i;
                base_color_reg <= base_color_next;
                color_o <= color_next;
                if preview_i = PREVIEW_AUDIO and
                   x_reg >= PREVIEW_X0+12 and
                   x_reg <= PREVIEW_X1-12 then
                    last_wave_y_reg <= wave_y_reg;
                    sample_top := audio_sample_i(15 downto 10);
                    wave_y_reg <= (PREVIEW_Y0 + PREVIEW_Y1) / 2 -
                                  to_integer(sample_top) * 2;
                end if;
            end if;
        end if;
    end process;
end architecture;
