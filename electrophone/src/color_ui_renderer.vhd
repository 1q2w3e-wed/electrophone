library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use work.ui_layout.all;
use work.cjk_font_rom.all;

-- 480x320 单屏彩色仪表盘。每个像素由当前坐标实时计算，无需帧缓存。
entity color_ui_renderer is
    port (
        clk, reset_n, frame_start_i : in std_logic;
        focus_i   : in focus_t;
        preview_i : in preview_t;
        settings_i: in settings_t;
        status_i  : in status_t;
        pedal_mode_i : in std_logic;
        octave_shift_i : in std_logic;
        playback_active_i : in std_logic;
        score_available_i : in std_logic;
        active_count_i : in voice_count_t;
        audio_sample_i  : in audio_sample_t;
        sensor_levels_i : in sensor_array_t;
        spectrum_level_i : in unsigned(7 downto 0);
        note_active_i : in std_logic_vector(7 downto 0);
        lissajous_pixel_i : in std_logic;
        pixel_x_i : in natural range 0 to SCREEN_W-1;
        pixel_y_i : in natural range 0 to SCREEN_H-1;
        color_o   : out rgb565_t
    );
end entity;

architecture rtl of color_ui_renderer is
    signal focus   : focus_t := FOCUS_TIMBRE;
    signal preview : preview_t := PREVIEW_AUDIO;
    signal cfg     : settings_t := (0,50,20,100,70,200,0,20,80,FX_DRY);
    signal status  : status_t := STATUS_NONE;
    signal pedal_mode : std_logic := '0';
    signal octave_shift : std_logic := '0';
    signal playback_active : std_logic := '0';
    signal score_available : std_logic := '0';
    signal active_count : voice_count_t := 0;
    signal wave_color : rgb565_t;
    signal render_next : rgb565_t := (others => '0');
    signal sensor_levels : sensor_array_t := (others => (others => '0'));
    signal note_active : std_logic_vector(7 downto 0) := (others => '0');
    signal volume_text : string(1 to 4) := "050%";
    signal volume_bar_end : natural range 329 to 456 := 392;

    constant T_TITLE   : cjk_string_t(1 to 6) :=
        (CJK_DIAN, CJK_ZI, CJK_QIN, CJK_CAN, CJK_SHU, CJK_TAI);
    constant T_CURRENT : cjk_string_t(1 to 2) := (CJK_DANG, CJK_QIAN);
    constant T_TIMBRE  : cjk_string_t(1 to 2) := (CJK_YIN, CJK_SE);
    constant T_VOLUME  : cjk_string_t(1 to 2) := (CJK_YIN, CJK_LIANG);
    constant T_WAVE    : cjk_string_t(1 to 4) :=
        (CJK_BO, CJK_XING, CJK_YU, CJK_LAN);
    constant T_AUDIO   : cjk_string_t(1 to 4) :=
        (CJK_YIN, CJK_PIN, CJK_BO, CJK_XING);
    constant T_SPECTRUM : cjk_string_t(1 to 2) := (CJK_PIN, CJK_PU);
    constant T_LISSAJOUS : cjk_string_t(1 to 3) :=
        (CJK_LI2, CJK_SA, CJK_RU);
    constant T_EFFECT   : cjk_string_t(1 to 2) := (CJK_XIAO, CJK_GUO);
    constant T_DRY      : cjk_string_t(1 to 2) := (CJK_YUAN, CJK_SHENG);
    constant T_DELAY    : cjk_string_t(1 to 2) := (CJK_YAN, CJK_CHI3);
    constant T_CHORUS   : cjk_string_t(1 to 2) := (CJK_HE, CJK_CHANG);
    constant T_REVERB   : cjk_string_t(1 to 2) := (CJK_HUN, CJK_XIANG);
    constant T_PRESSURE: cjk_string_t(1 to 4) :=
        (CJK_BA, CJK_LU, CJK_YA, CJK_LI);
    constant T_ENVELOPE_VIEW : cjk_string_t(1 to 4) :=
        (CJK_BAO, CJK_LUO, CJK_YU, CJK_LAN);
    constant T_ENVELOPE : cjk_string_t(1 to 2) := (CJK_BAO, CJK_LUO);
    constant T_SINE     : cjk_string_t(1 to 3) := (CJK_ZHENG, CJK_XIAN, CJK_BO);
    constant T_SQUARE   : cjk_string_t(1 to 2) := (CJK_FANG, CJK_BO);
    constant T_SAW      : cjk_string_t(1 to 3) := (CJK_JU, CJK_CHI2, CJK_BO);
    constant T_TRIANGLE : cjk_string_t(1 to 3) := (CJK_SAN, CJK_JIAO, CJK_BO);
    constant T_ATTACK   : cjk_string_t(1 to 2) := (CJK_QI, CJK_YIN);
    constant T_DECAY    : cjk_string_t(1 to 2) := (CJK_SHUAI, CJK_JIAN);
    constant T_SUSTAIN  : cjk_string_t(1 to 2) := (CJK_CHI, CJK_XU);
    constant T_RELEASE  : cjk_string_t(1 to 2) := (CJK_SHI, CJK_YIN);
    constant T_BEND     : cjk_string_t(1 to 2) := (CJK_WAN, CJK_YIN);
    constant T_VIBRATO  : cjk_string_t(1 to 2) := (CJK_ROU, CJK_YIN);
    constant T_GLIDE    : cjk_string_t(1 to 2) := (CJK_HUA, CJK_YIN);
    constant T_PLUCK    : cjk_string_t(1 to 2) := (CJK_BO2, CJK_XIAN);
    constant T_PEDAL    : cjk_string_t(1 to 2) := (CJK_TA, CJK_BAN);
    constant T_RESET    : cjk_string_t(1 to 5) :=
        (CJK_YI, CJK_HUI, CJK_FU, CJK_MO, CJK_REN);

    function rgb565(r, g, b : natural) return rgb565_t is
        variable rv : natural := r;
        variable gv : natural := g;
        variable bv : natural := b;
        variable result : rgb565_t;
    begin
        if rv > 31 then rv := 31; end if;
        if gv > 63 then gv := 63; end if;
        if bv > 31 then bv := 31; end if;
        result(15 downto 11) := std_logic_vector(to_unsigned(rv, 5));
        result(10 downto 5) := std_logic_vector(to_unsigned(gv, 6));
        result(4 downto 0) := std_logic_vector(to_unsigned(bv, 5));
        return result;
    end function;

    constant C_BG       : rgb565_t := rgb565(3,6,12);
    constant C_HEADER   : rgb565_t := rgb565(4,12,22);
    constant C_HEADER_2 : rgb565_t := rgb565(6,18,30);
    constant C_CARD     : rgb565_t := rgb565(8,18,30);
    constant C_CARD_SEL : rgb565_t := rgb565(17,28,38);
    constant C_DIM      : rgb565_t := rgb565(11,25,34);
    constant C_TEXT     : rgb565_t := rgb565(31,63,42);
    constant C_MUTED    : rgb565_t := rgb565(15,34,34);
    constant C_CYAN     : rgb565_t := rgb565(2,58,54);
    constant C_ORANGE   : rgb565_t := rgb565(31,40,4);
    constant C_PURPLE   : rgb565_t := rgb565(27,14,58);
    constant C_PURPLE_BG: rgb565_t := rgb565(14,9,32);
    constant C_RESET    : rgb565_t := rgb565(31,52,7);

    function glyph_col(ch : character; col : natural) return std_logic_vector is
        variable columns : std_logic_vector(39 downto 0);
    begin
        case ch is
            when 'A' => columns := x"7E1111117E";
            when 'B' => columns := x"7F49494936";
            when 'C' => columns := x"3E41414122";
            when 'D' => columns := x"7F4141221C";
            when 'E' => columns := x"7F49494941";
            when 'F' => columns := x"7F09090901";
            when 'G' => columns := x"3E41495132";
            when 'H' => columns := x"7F0808087F";
            when 'I' => columns := x"00417F4100";
            when 'J' => columns := x"2040413F01";
            when 'K' => columns := x"7F08142241";
            when 'L' => columns := x"7F40404040";
            when 'M' => columns := x"7F020C027F";
            when 'N' => columns := x"7F0408107F";
            when 'O' => columns := x"3E4141413E";
            when 'P' => columns := x"7F09090906";
            when 'Q' => columns := x"3E4151215E";
            when 'R' => columns := x"7F09192946";
            when 'S' => columns := x"4649494931";
            when 'T' => columns := x"01017F0101";
            when 'U' => columns := x"3F4040403F";
            when 'V' => columns := x"1F2040201F";
            when 'W' => columns := x"3F4038403F";
            when 'X' => columns := x"6314081463";
            when 'Y' => columns := x"0304780403";
            when 'Z' => columns := x"6151494543";
            when '0' => columns := x"3E5149453E";
            when '1' => columns := x"00427F4000";
            when '2' => columns := x"4261514946";
            when '3' => columns := x"2141454B31";
            when '4' => columns := x"1814127F10";
            when '5' => columns := x"2745454539";
            when '6' => columns := x"3C4A494930";
            when '7' => columns := x"0171090503";
            when '8' => columns := x"3649494936";
            when '9' => columns := x"064949291E";
            when ':' => columns := x"0036360000";
            when '.' => columns := x"0060600000";
            when '-' => columns := x"0808080808";
            when '+' => columns := x"08083E0808";
            when '%' => columns := x"2313086462";
            when '/' => columns := x"4010080401";
            when others => columns := x"0000000000";
        end case;
        if col >= 5 then
            return "0000000";
        end if;
        return columns(38-col*8 downto 32-col*8);
    end function;

    function ascii_pixel(s : string; x0, y0, scale : natural;
                         px, py : natural) return boolean is
        variable cell_x, cell_y, gx, gy : integer;
        variable bits : std_logic_vector(6 downto 0);
    begin
        for i in s'range loop
            cell_x := x0 + (i-s'low) * 6 * scale;
            if px >= cell_x and px < cell_x + 5*scale and
               py >= y0 and py < y0 + 7*scale then
                cell_y := py - y0;
                gx := (px - cell_x) / scale;
                gy := cell_y / scale;
                bits := glyph_col(s(i), gx);
                if bits(gy) = '1' then
                    return true;
                end if;
            end if;
        end loop;
        return false;
    end function;

    function cjk_pixel(s : cjk_string_t; x0, y0, scale : natural;
                       px, py : natural) return boolean is
        variable cell_x : integer;
        variable rows : std_logic_vector(15 downto 0);
        variable gx, gy : natural;
    begin
        for i in s'range loop
            cell_x := x0 + (i-s'low) * 18 * scale;
            if px >= cell_x and px < cell_x + 16*scale and
               py >= y0 and py < y0 + 16*scale then
                gx := (px - cell_x) / scale;
                gy := (py - y0) / scale;
                rows := cjk_row(s(i), gy);
                if rows(15-gx) = '1' then
                    return true;
                end if;
            end if;
        end loop;
        return false;
    end function;

    function decimal(n : natural; digits : positive) return string is
        variable result : string(1 to digits);
        variable value : natural := n;
    begin
        for i in digits downto 1 loop
            result(i) := character'val(character'pos('0') + value mod 10);
            value := value / 10;
        end loop;
        return result;
    end function;

    function signed_decimal(value : integer; digits : positive) return string is
        variable result : string(1 to digits+1);
        variable magnitude : natural;
    begin
        if value < 0 then
            result(1) := '-';
            magnitude := -value;
        else
            result(1) := '+';
            magnitude := value;
        end if;
        for i in digits downto 1 loop
            result(1+i) := character'val(
                character'pos('0') + magnitude mod 10);
            magnitude := magnitude / 10;
        end loop;
        return result;
    end function;

    function on_border(x, y, x0, y0, x1, y1 : natural) return boolean is
    begin
        return inside(x, y, x0, y0, x1, y1) and
               (x <= x0+1 or x >= x1-1 or y <= y0+1 or y >= y1-1);
    end function;

    function focus_text(which : focus_t) return cjk_string_t is
    begin
        case which is
            when FOCUS_TIMBRE  => return T_TIMBRE;
            when FOCUS_VOLUME  => return T_VOLUME;
            when FOCUS_ATTACK  => return T_ATTACK;
            when FOCUS_DECAY   => return T_DECAY;
            when FOCUS_SUSTAIN => return T_SUSTAIN;
            when FOCUS_RELEASE => return T_RELEASE;
            when FOCUS_BEND    => return T_BEND;
            when FOCUS_VIBRATO => return T_VIBRATO;
            when FOCUS_GLIDE   => return T_GLIDE;
            when FOCUS_PLUCK   => return T_PLUCK;
            when FOCUS_EFFECT  => return T_EFFECT;
            when FOCUS_OCTAVE  => return T_EFFECT;
        end case;
    end function;
begin
    preview_pixels: entity work.wave_preview
        port map (
            clk => clk, reset_n => reset_n,
            settings_i => cfg,
            preview_i => preview,
            focus_i => focus,
            audio_sample_i => audio_sample_i,
            sensor_levels_i => sensor_levels,
            spectrum_level_i => spectrum_level_i,
            note_active_i => note_active,
            octave_shift_i => octave_shift,
            lissajous_pixel_i => lissajous_pixel_i,
            pixel_x_i => pixel_x_i,
            pixel_y_i => pixel_y_i,
            color_o => wave_color
        );

    process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                focus <= FOCUS_TIMBRE;
                preview <= PREVIEW_AUDIO;
                cfg <= (0,50,20,100,70,200,0,20,80,FX_DRY);
                status <= STATUS_NONE;
                pedal_mode <= '0';
                octave_shift <= '0';
                playback_active <= '0';
                score_available <= '0';
                active_count <= 0;
                sensor_levels <= (others => (others => '0'));
                note_active <= (others => '0');
                volume_text <= "050%";
                volume_bar_end <= 392;
            elsif frame_start_i = '1' then
                focus <= focus_i;
                preview <= preview_i;
                cfg <= settings_i;
                status <= status_i;
                pedal_mode <= pedal_mode_i;
                octave_shift <= octave_shift_i;
                playback_active <= playback_active_i;
                score_available <= score_available_i;
                active_count <= active_count_i;
                sensor_levels <= sensor_levels_i;
                note_active <= note_active_i;
                volume_text <= decimal(settings_i.volume, 3) & "%";
                volume_bar_end <=
                    329 + (settings_i.volume * 127) / 100;
            end if;
        end if;
    end process;

    process(focus, preview, cfg, status, pedal_mode, octave_shift,
            playback_active, score_available, active_count,
            spectrum_level_i, note_active, lissajous_pixel_i,
        wave_color, pixel_x_i, pixel_y_i, volume_text, volume_bar_end)
        variable result : rgb565_t;
        variable x, y : natural;
        variable env_focus : boolean;
    begin
        x := pixel_x_i;
        y := pixel_y_i;
        result := C_BG;

        if y < HEADER_H then
            if y < HEADER_H/2 then
                result := C_HEADER;
            else
                result := C_HEADER_2;
            end if;
            if cjk_pixel(T_TITLE, 12, 12, 1, x, y) then
                result := C_TEXT;
            end if;
            if cjk_pixel(T_CURRENT, 326, 12, 1, x, y) then
                result := C_MUTED;
            end if;
            if focus = FOCUS_PLUCK then
                if cjk_pixel(T_PLUCK, 380, 12, 1, x, y) then
                    result := C_ORANGE;
                end if;
                if cfg.sustain = 0 then
                    if ascii_pixel("ON", 422, 16, 1, x, y) then
                        result := C_CYAN;
                    end if;
                else
                    if ascii_pixel("OFF", 416, 16, 1, x, y) then
                        result := C_CYAN;
                    end if;
                end if;
            elsif focus = FOCUS_OCTAVE then
                if ascii_pixel("OCT", 380, 12, 1, x, y) then
                    result := C_ORANGE;
                end if;
                if octave_shift = '0' then
                    if ascii_pixel("0", 422, 12, 1, x, y) then
                        result := C_CYAN;
                    end if;
                else
                    if ascii_pixel("+1", 416, 12, 1, x, y) then
                        result := C_CYAN;
                    end if;
                end if;
            elsif cjk_pixel(focus_text(focus), 380, 12, 1, x, y) then
                result := C_ORANGE;
            end if;
            if focus = FOCUS_OCTAVE then
                if ascii_pixel("SONG", 188, 16, 1, x, y) then
                    result := C_ORANGE;
                end if;
                if score_available = '0' then
                    if ascii_pixel("EMPTY", 224, 16, 1, x, y) then
                        result := C_MUTED;
                    end if;
                elsif playback_active = '1' then
                    if ascii_pixel("STOP", 230, 16, 1, x, y) then
                        result := C_CYAN;
                    end if;
                else
                    if ascii_pixel("PLAY", 230, 16, 1, x, y) then
                        result := C_CYAN;
                    end if;
                end if;
            elsif pedal_mode = '1' then
                if active_count /= POLYPHONY then
                    if cjk_pixel(T_PEDAL, 188, 12, 1, x, y) then
                        result := C_MUTED;
                    end if;
                end if;
                if ascii_pixel("ON", 230, 16, 1, x, y) then
                    result := C_ORANGE;
                end if;
                if ascii_pixel(decimal(active_count,2) & "/32",
                               266, 16, 1, x, y) then
                    result := C_ORANGE;
                end if;
            elsif cfg.sustain = 0 then
                if cjk_pixel(T_PLUCK, 188, 12, 1, x, y) then
                    result := C_ORANGE;
                end if;
                if ascii_pixel("ON", 230, 16, 1, x, y) then
                    result := C_ORANGE;
                end if;
            else
                if cjk_pixel(T_PEDAL, 188, 12, 1, x, y) then
                    result := C_MUTED;
                end if;
                if ascii_pixel("OFF", 230, 16, 1, x, y) then
                    result := C_MUTED;
                end if;
            end if;
            if status = STATUS_RESET and cjk_pixel(T_RESET, 196, 12, 1, x, y) then
                result := C_RESET;
            end if;
        elsif inside(x, y, PREVIEW_X0, PREVIEW_Y0, PREVIEW_X1, PREVIEW_Y1) then
            result := wave_color;
            if preview = PREVIEW_AUDIO then
                if cjk_pixel(T_AUDIO, 24, 56, 1, x, y) then
                    result := C_TEXT;
                end if;
            elsif preview = PREVIEW_SPECTRUM then
                if cjk_pixel(T_SPECTRUM, 24, 56, 1, x, y) then
                    result := C_TEXT;
                end if;
                if ascii_pixel("20", 28, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("50", 98, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("100", 152, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("200", 206, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("500", 278, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("1K", 332, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("2K", 387, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("4K", 441, 146, 1, x, y) then result := C_CYAN; end if;
            elsif preview = PREVIEW_LISSAJOUS then
                if cjk_pixel(T_LISSAJOUS, 24, 56, 1, x, y) then
                    result := C_TEXT;
                end if;
            elsif preview = PREVIEW_PRESSURE then
                if cjk_pixel(T_PRESSURE, 24, 56, 1, x, y) then
                    result := C_TEXT;
                end if;
                if ascii_pixel("CH0", 36, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH1", 88, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH2", 140, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH3", 192, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH4", 244, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH5", 296, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH6", 348, 146, 1, x, y) then result := C_CYAN; end if;
                if ascii_pixel("CH7", 400, 146, 1, x, y) then result := C_CYAN; end if;
            else
                if cjk_pixel(T_ENVELOPE_VIEW, 24, 56, 1, x, y) then
                    result := C_TEXT;
                end if;
                if ascii_pixel("A", 70, 144, 1, x, y) then result := C_PURPLE; end if;
                if ascii_pixel("D", 170, 144, 1, x, y) then result := C_PURPLE; end if;
                if ascii_pixel("S", 270, 144, 1, x, y) then result := C_PURPLE; end if;
                if ascii_pixel("R", 370, 144, 1, x, y) then result := C_PURPLE; end if;
            end if;
        elsif inside(x, y, TIMBRE_X0, TIMBRE_Y0, TIMBRE_X1, TIMBRE_Y1) then
            if focus = FOCUS_TIMBRE then result := C_CARD_SEL; else result := C_CARD; end if;
            if on_border(x, y, TIMBRE_X0, TIMBRE_Y0, TIMBRE_X1, TIMBRE_Y1) then
                if focus = FOCUS_TIMBRE then result := C_ORANGE; else result := C_DIM; end if;
            end if;
            if cjk_pixel(T_TIMBRE, 22, 178, 1, x, y) then result := C_TEXT; end if;
            case cfg.tone is
                when 0 =>
                    if cjk_pixel(T_SINE, 78, 178, 1, x, y) then result := C_CYAN; end if;
                when 1 =>
                    if cjk_pixel(T_SQUARE, 78, 178, 1, x, y) then result := C_CYAN; end if;
                when 2 =>
                    if cjk_pixel(T_SAW, 78, 178, 1, x, y) then result := C_CYAN; end if;
                when others =>
                    if cjk_pixel(T_TRIANGLE, 78, 178, 1, x, y) then result := C_CYAN; end if;
            end case;
        elsif inside(x, y, VOLUME_X0, VOLUME_Y0, VOLUME_X1, VOLUME_Y1) then
            if focus = FOCUS_VOLUME then result := C_CARD_SEL; else result := C_CARD; end if;
            if on_border(x, y, VOLUME_X0, VOLUME_Y0, VOLUME_X1, VOLUME_Y1) then
                if focus = FOCUS_VOLUME then result := C_ORANGE; else result := C_DIM; end if;
            end if;
            if cjk_pixel(T_VOLUME, 258, 176, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(volume_text, 334, 178, 1, x, y) then
                result := C_ORANGE;
            end if;
            if y >= 192 and y <= 199 and x >= 330 and x <= 456 then
                result := C_HEADER;
                -- 进度条有效宽度为 127 像素；0% 不填，100% 填到最右端。
                if x <= volume_bar_end then result := C_ORANGE; end if;
            end if;
        elsif inside(x, y, ENVELOPE_X0, ENVELOPE_Y0, ENVELOPE_X1, ENVELOPE_Y1) then
            result := C_PURPLE_BG;
            if on_border(x, y, ENVELOPE_X0, ENVELOPE_Y0, ENVELOPE_X1, ENVELOPE_Y1) then
                result := C_DIM;
            end if;
            env_focus := focus = FOCUS_ATTACK;
            if env_focus and y >= 218 and y <= 256 and x >= 28 and x <= 136 then
                result := C_PURPLE;
            end if;
            if cjk_pixel(T_ATTACK, 36, 220, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.attack_ms,4) & "MS", 36, 240, 1, x, y) then
                result := C_ORANGE;
            end if;

            env_focus := focus = FOCUS_DECAY;
            if env_focus and y >= 218 and y <= 256 and x >= 136 and x <= 244 then
                result := C_PURPLE;
            end if;
            if cjk_pixel(T_DECAY, 144, 220, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.decay_ms,4) & "MS", 144, 240, 1, x, y) then
                result := C_ORANGE;
            end if;

            env_focus := focus = FOCUS_SUSTAIN;
            if env_focus and y >= 218 and y <= 256 and x >= 244 and x <= 352 then
                result := C_PURPLE;
            end if;
            if cjk_pixel(T_SUSTAIN, 252, 220, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.sustain,3) & "%", 252, 240, 1, x, y) then
                result := C_ORANGE;
            end if;

            env_focus := focus = FOCUS_RELEASE;
            if env_focus and y >= 218 and y <= 256 and x >= 352 and x <= 464 then
                result := C_PURPLE;
            end if;
            if cjk_pixel(T_RELEASE, 360, 220, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.release_ms,4) & "MS", 360, 240, 1, x, y) then
                result := C_ORANGE;
            end if;
        elsif inside(x, y, EXPR_X0, EXPR_Y0, EXPR_X1, EXPR_Y1) then
            result := C_CARD;
            if on_border(x, y, EXPR_X0, EXPR_Y0, EXPR_X1, EXPR_Y1) then
                result := C_DIM;
            end if;

            if focus = FOCUS_BEND then
                if x >= BEND_X0 and x < BEND_X1 and
                   y >= EXPR_Y0+2 and y <= EXPR_Y1-2 then
                    result := C_PURPLE_BG;
                end if;
            end if;
            if cjk_pixel(T_BEND, 22, 274, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(
                signed_decimal(cfg.bend_cents,3) & " CENT",
                22, 292, 1, x, y) then
                result := C_ORANGE;
            end if;

            if focus = FOCUS_VIBRATO then
                if x >= VIB_X0 and x < VIB_X1 and
                   y >= EXPR_Y0+2 and y <= EXPR_Y1-2 then
                    result := C_PURPLE_BG;
                end if;
            end if;
            if cjk_pixel(T_VIBRATO, 131, 274, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.vibrato_cents,3) & " CENT",
                           131, 292, 1, x, y) then
                result := C_ORANGE;
            end if;

            if focus = FOCUS_GLIDE then
                if x >= GLIDE_X0 and x < GLIDE_X1 and
                   y >= EXPR_Y0+2 and y <= EXPR_Y1-2 then
                    result := C_PURPLE_BG;
                end if;
            end if;
            if cjk_pixel(T_GLIDE, 240, 274, 1, x, y) then result := C_TEXT; end if;
            if ascii_pixel(decimal(cfg.glide_ms,4) & " MS",
                           240, 292, 1, x, y) then
                result := C_ORANGE;
            end if;
            if focus = FOCUS_EFFECT then
                if x >= EFFECT_X0 and x < EFFECT_X1 and
                   y >= EXPR_Y0+2 and y <= EXPR_Y1-2 then
                    result := C_PURPLE_BG;
                end if;
            end if;
            if cjk_pixel(T_EFFECT, 349, 274, 1, x, y) then
                result := C_TEXT;
            end if;
            case cfg.effect_mode is
                when FX_DRY =>
                    if cjk_pixel(T_DRY, 349, 292, 1, x, y) then
                        result := C_ORANGE;
                    end if;
                when FX_DELAY =>
                    if cjk_pixel(T_DELAY, 349, 292, 1, x, y) then
                        result := C_ORANGE;
                    end if;
                when FX_CHORUS =>
                    if cjk_pixel(T_CHORUS, 349, 292, 1, x, y) then
                        result := C_ORANGE;
                    end if;
                when others =>
                    if cjk_pixel(T_REVERB, 349, 292, 1, x, y) then
                        result := C_ORANGE;
                    end if;
            end case;
        end if;

        render_next <= result;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                color_o <= C_BG;
            else
                color_o <= render_next;
            end if;
        end if;
    end process;
end architecture;
