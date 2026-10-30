library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use work.ui_layout.all;

entity tb_volume_bar is
end entity;

architecture sim of tb_volume_bar is
    constant CLK_PERIOD : time := 20 ns;
    constant C_ORANGE : rgb565_t := "1111110100000100";
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal frame_start : std_logic := '0';
    signal focus : focus_t := FOCUS_VOLUME;
    signal preview : preview_t := PREVIEW_AUDIO;
    signal cfg : settings_t := (0,100,20,100,70,200,0,20,80,FX_DRY);
    signal status : status_t := STATUS_NONE;
    signal pedal_mode : std_logic := '0';
    signal playback_active : std_logic := '0';
    signal score_available : std_logic := '0';
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
            octave_shift_i => '0',
            playback_active_i => playback_active,
            score_available_i => score_available,
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
        procedure render_pixel(x, y : natural) is
        begin
            wait until falling_edge(clk);
            pixel_x <= x;
            pixel_y <= y;
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait for 1 ns;
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait for 3*CLK_PERIOD;
        frame_start <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        frame_start <= '0';

        render_pixel(455, 195);
        assert color = C_ORANGE
            report "Volume bar is not full at 100 percent"
            severity failure;

        report "tb_volume_bar passed" severity note;
        wait;
    end process;
end architecture;
