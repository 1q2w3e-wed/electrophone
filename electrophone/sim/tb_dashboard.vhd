library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use work.ui_types.all;
use work.ui_layout.all;

entity tb_dashboard is
end entity;

architecture sim of tb_dashboard is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal frame_start : std_logic := '0';
    signal focus : focus_t := FOCUS_TIMBRE;
    signal preview : preview_t := PREVIEW_AUDIO;
    signal cfg : settings_t := (0,50,20,100,70,200,0,20,80,FX_DRY);
    signal status : status_t := STATUS_NONE;
    signal pedal_mode : std_logic := '0';
    signal octave_shift : std_logic := '0';
    signal active_count : voice_count_t := 0;
    signal audio_sample : audio_sample_t := (others => '0');
    signal sensor_levels : sensor_array_t := (others => (others => '0'));
    signal spectrum_level : unsigned(7 downto 0) := (others => '0');
    signal note_active : std_logic_vector(7 downto 0) := (others => '0');
    signal lissajous_pixel : std_logic := '0';
    signal pixel_x : natural range 0 to SCREEN_W-1 := 0;
    signal pixel_y : natural range 0 to SCREEN_H-1 := 0;
    signal color : rgb565_t;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.color_ui_renderer
        port map (
            clk => clk, reset_n => reset_n, frame_start_i => frame_start,
            focus_i => focus, preview_i => preview,
            settings_i => cfg, status_i => status,
            pedal_mode_i => pedal_mode,
            octave_shift_i => octave_shift,
            active_count_i => active_count,
            audio_sample_i => audio_sample,
            sensor_levels_i => sensor_levels,
            spectrum_level_i => spectrum_level,
            note_active_i => note_active,
            lissajous_pixel_i => lissajous_pixel,
            pixel_x_i => pixel_x, pixel_y_i => pixel_y,
            color_o => color
        );

    stimulus: process
        procedure render_scene(
            filename : string;
            f : focus_t;
            p : preview_t;
            s : settings_t;
            st : status_t;
            checksum : out natural
        ) is
            file output : text;
            variable ln : line;
            variable c : rgb565_t;
            variable r, g, b : natural;
            variable acc : natural := 0;
        begin
            focus <= f;
            preview <= p;
            cfg <= s;
            status <= st;
            wait until falling_edge(clk);
            frame_start <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            frame_start <= '0';
            wait until falling_edge(clk);

            file_open(output, "sim/output/" & filename & ".ppm", write_mode);
            write(ln, string'("P3"));
            writeline(output, ln);
            write(ln, string'("480 320"));
            writeline(output, ln);
            write(ln, string'("255"));
            writeline(output, ln);

            for y in 0 to SCREEN_H-1 loop
                for x in 0 to SCREEN_W-1 loop
                    wait until falling_edge(clk);
                    pixel_x <= x;
                    pixel_y <= y;
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                    wait until rising_edge(clk);
                    wait for 1 ns;
                    c := color;
                    r := to_integer(unsigned(c(15 downto 11))) * 255 / 31;
                    g := to_integer(unsigned(c(10 downto 5))) * 255 / 63;
                    b := to_integer(unsigned(c(4 downto 0))) * 255 / 31;
                    write(ln, integer'image(r));
                    write(ln, string'(" "));
                    write(ln, integer'image(g));
                    write(ln, string'(" "));
                    write(ln, integer'image(b));
                    write(ln, string'(" "));
                    if y >= PREVIEW_Y0 and y <= PREVIEW_Y1 and
                       x >= PREVIEW_X0 and x <= PREVIEW_X1 then
                        acc := acc + (r + g + b);
                    end if;
                end loop;
                writeline(output, ln);
            end loop;
            file_close(output);
            checksum := acc;
        end procedure;

        variable audio_sum, spectrum_sum, lissajous_sum, pressure_sum : natural;
        variable expression_sum, pedal_sum : natural;
        variable effect_sum, octave_sum, pluck_sum : natural;
        variable env_short_sum, env_long_sum : natural;
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait for 3*CLK_PERIOD;

        for i in 0 to 7 loop
            sensor_levels(i) <= to_unsigned(120 + i*120, 10);
        end loop;

        render_scene("dashboard_audio", FOCUS_TIMBRE, PREVIEW_AUDIO,
                     (0,72,20,100,70,200,0,20,80,FX_DRY), STATUS_NONE, audio_sum);
        render_scene("dashboard_pressure", FOCUS_ATTACK, PREVIEW_PRESSURE,
                     (0,72,20,100,70,200,0,20,80,FX_DRY), STATUS_NONE, pressure_sum);
        render_scene("dashboard_envelope_short", FOCUS_ATTACK,
                     PREVIEW_ENVELOPE, (0,72,20,100,70,200,0,20,80,FX_DRY),
                     STATUS_NONE, env_short_sum);
        render_scene("dashboard_envelope_long", FOCUS_RELEASE,
                     PREVIEW_ENVELOPE, (0,72,1800,1600,35,4000,0,20,80,FX_DRY),
                     STATUS_NONE, env_long_sum);
        render_scene("dashboard_expression", FOCUS_BEND, PREVIEW_AUDIO,
                     (0,72,20,100,70,200,-120,50,1000,FX_DRY),
                     STATUS_NONE, expression_sum);
        pedal_mode <= '1';
        active_count <= 12;
        render_scene("dashboard_pedal", FOCUS_TIMBRE, PREVIEW_AUDIO,
                     (1,72,20,100,70,200,0,20,80,FX_DRY),
                     STATUS_NONE, pedal_sum);
        note_active <= (others => '1');
        render_scene("dashboard_spectrum", FOCUS_TIMBRE, PREVIEW_SPECTRUM,
                     (1,72,20,100,70,200,0,20,80,FX_DRY),
                     STATUS_NONE, spectrum_sum);
        octave_shift <= '1';
        render_scene("dashboard_octave", FOCUS_OCTAVE, PREVIEW_AUDIO,
                     (1,72,20,100,70,200,0,20,80,FX_DRY),
                     STATUS_NONE, octave_sum);
        octave_shift <= '0';
        render_scene("dashboard_lissajous", FOCUS_TIMBRE, PREVIEW_LISSAJOUS,
                     (1,72,20,100,70,200,0,20,80,FX_DRY),
                     STATUS_NONE, lissajous_sum);
        pedal_mode <= '0';
        active_count <= 0;
        render_scene("dashboard_effect", FOCUS_EFFECT, PREVIEW_AUDIO,
                     (1,72,20,100,70,200,0,20,80,FX_REVERB),
                     STATUS_NONE, effect_sum);
        render_scene("dashboard_pluck", FOCUS_PLUCK, PREVIEW_ENVELOPE,
                     (0,72,20,100,0,80,0,0,0,FX_DRY),
                     STATUS_NONE, pluck_sum);

        assert audio_sum /= pressure_sum
            report "Audio and pressure previews are identical"
            severity failure;
        assert spectrum_sum /= audio_sum
            report "Spectrum preview is identical to the audio scope"
            severity failure;
        assert lissajous_sum /= 0
            report "Lissajous preview is blank"
            severity failure;
        assert effect_sum /= 0
            report "Effect preview is blank"
            severity failure;
        assert env_short_sum /= env_long_sum
            report "ADSR parameters did not change envelope pixels"
            severity failure;
        assert expression_sum /= 0
            report "Expression panel is blank"
            severity failure;
        assert pedal_sum /= 0
            report "Pedal voice-count panel is blank"
            severity failure;
        assert octave_sum /= 0
            report "Octave parameter display is blank"
            severity failure;
        assert pluck_sum /= 0
            report "Pluck mode display is blank"
            severity failure;

        report "tb_dashboard passed" severity note;
        wait;
    end process;

    audio_model: process(pixel_x)
        variable sample_value : integer;
    begin
        sample_value := integer(
            20000.0 * sin(2.0 * 3.1415926 * real(pixel_x mod 80) / 80.0));
        audio_sample <= to_signed(sample_value, 16);
    end process;

    spectrum_model: process(pixel_x)
        variable level : natural := 20;
    begin
        case pixel_x is
            when 233 to 234 => level := 220;
            when 288 to 289 => level := 180;
            when 351 to 352 => level := 145;
            when 393 to 394 => level := 115;
            when 424 to 425 => level := 90;
            when others => level := 20;
        end case;
        spectrum_level <= to_unsigned(level, 8);
    end process;

    lissajous_model: process(pixel_x, pixel_y)
        variable dx, dy, distance : integer;
    begin
        dx := pixel_x - 240;
        dy := pixel_y - 104;
        distance := dx*dx + dy*dy;
        if distance > 22*22 and distance < 30*30 then
            lissajous_pixel <= '1';
        else
            lissajous_pixel <= '0';
        end if;
    end process;
end architecture;
