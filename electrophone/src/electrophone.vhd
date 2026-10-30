library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use work.ui_layout.all;

-- Tang Primer 25K 双 EC11 单屏中文波形界面。
entity electrophone is
    generic (
        G_CLK_HZ          : positive := 50_000_000;
        G_SPI_HALF_CYCLES : positive := 2;
        G_ROT_FILTER_US   : positive := 100;
        G_KEY_DEBOUNCE_MS : positive := 20;
        G_EDGES_PER_STEP  : positive range 1 to 4 := 4;
        G_ENCODER1_REVERSE: boolean := false;
        G_ENCODER2_REVERSE: boolean := false;
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
        G_STATUS_MS       : positive range 100 to 5000 := 800;
        G_ADC_POLL_DIV    : positive := 1_000;
        G_SENSOR_ON_LEVEL : natural range 0 to 1023 := 64;
        G_SENSOR_OFF_LEVEL: natural range 0 to 1023 := 32;
        G_SENSOR_DEBOUNCE : positive range 1 to 16 := 4;
        G_SENSOR_FILTER_SHIFT: positive range 1 to 5 := 3
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;

        bt_rx : in std_logic;
        bt_tx : out std_logic;

        -- J3-1 through J3-8: high-active LED indicators for notes 0 through 7.
        led_note0 : out std_logic;
        led_note1 : out std_logic;
        led_note2 : out std_logic;
        led_note3 : out std_logic;
        led_note4 : out std_logic;
        led_note5 : out std_logic;
        led_note6 : out std_logic;
        led_note7 : out std_logic;

        enc1_a, enc1_b, enc1_key_n : in std_logic;
        enc2_a, enc2_b, enc2_key_n : in std_logic;

        spi_clk  : out std_logic;
        spi_din  : out std_logic;
        spi_dout : in  std_logic;
        spi_cs_n : out std_logic;

        i2s_lrclk : out std_logic;
        i2s_bclk  : out std_logic;
        i2s_din   : out std_logic;

        lcd_sclk  : out std_logic;
        lcd_mosi  : out std_logic;
        lcd_cs_n  : out std_logic;
        lcd_dc    : out std_logic;
        lcd_rst_n : out std_logic;
        lcd_bl    : out std_logic
    );
end entity;

architecture rtl of electrophone is
    constant RESET_CYCLES : positive := G_CLK_HZ/1000;

    signal reset_count : natural range 0 to RESET_CYCLES := 0;
    signal ui_reset_n : std_logic := '0';
    signal reset_n : std_logic := '0';

    signal l_next, l_prev, l_press : std_logic;
    signal r_next, r_prev, r_press : std_logic;

    signal focus : focus_t;
    signal preview : preview_t;
    signal settings : settings_t;
    signal status : status_t;
    signal pedal_mode : std_logic;
    signal octave_shift : std_logic;
    signal active_count : voice_count_t;
    signal note_active : std_logic_vector(7 downto 0);
    signal voices_idle : std_logic;

    signal sensor_levels : sensor_array_t;
    signal sensor_on : std_logic_vector(7 downto 0);
    signal key_map : note_map_array_t := (0, 1, 2, 3, 4, 5, 6, 7);
    signal note_sources : note_map_array_t := (0, 1, 2, 3, 4, 5, 6, 7);
    signal mapped_on : std_logic_vector(7 downto 0);
    signal mapped_levels : sensor_array_t;
    signal remote_on : std_logic_vector(7 downto 0);
    signal remote_levels : sensor_array_t;
    signal remote_tones : tone_array_t;
    signal remote_effects : effect_array_t;
    signal remote_last_tone : tone_index_t;
    signal remote_last_effect : natural range 0 to 3;
    signal remote_clear : std_logic;
    signal effective_on : std_logic_vector(7 downto 0);
    signal effective_levels : sensor_array_t;
    signal effective_tones : tone_array_t;
    signal effective_effects : effect_array_t;
    signal mixed_tone : tone_index_t;
    signal mixed_effect : natural range 0 to 3;
    signal active_settings : settings_t;

    signal bt_rx_data : std_logic_vector(7 downto 0);
    signal bt_rx_valid : std_logic;
    signal parser_tx_data : std_logic_vector(7 downto 0);
    signal parser_tx_valid : std_logic;
    signal uploader_tx_data : std_logic_vector(7 downto 0);
    signal uploader_tx_valid : std_logic;
    signal bt_tx_data : std_logic_vector(7 downto 0);
    signal bt_tx_valid : std_logic;
    signal bt_tx_ready : std_logic;
    signal map_write_en : std_logic;
    signal map_channel : natural range 0 to 7;
    signal map_note : natural range 0 to 7;
    signal command_clear : std_logic;
    signal command_append : std_logic;
    signal command_append_data : std_logic_vector(31 downto 0);
    signal command_play, command_stop : std_logic;
    signal command_rec_start, command_rec_stop, command_rec_play : std_logic;
    signal command_test_on, command_test_off : std_logic;
    signal test_mode : std_logic := '0';
    signal score_available : std_logic;
    signal physical_score_toggle : std_logic;
    signal physical_score_play : std_logic;
    signal physical_score_stop : std_logic;
    signal key_down, key_up, key_all_up, dump_start : std_logic;
    signal key_note : note_index_t;
    signal key_velocity : natural range 0 to 31;
    signal key_tone : tone_index_t;
    signal key_effect : natural range 0 to 3;

    signal event_clear, event_append_en, event_update_en : std_logic;
    signal event_append_data : std_logic_vector(31 downto 0);
    signal event_update_index : natural range 0 to 1023;
    signal event_update_duration : std_logic_vector(7 downto 0);
    signal event_update_velocity : std_logic_vector(4 downto 0);
    signal event_count : natural range 0 to 1024;
    signal event_full : std_logic;
    signal sequencer_read_index : natural range 0 to 1023;
    signal uploader_read_index : natural range 0 to 1023;
    signal event_read_index : natural range 0 to 1023;
    signal event_read_data : std_logic_vector(31 downto 0);
    signal uploader_active : std_logic;

    signal virtual_on : std_logic_vector(7 downto 0);
    signal virtual_levels : sensor_array_t;
    signal playback_active : std_logic;
    signal playback_tone : natural range 0 to 3;
    signal playback_effect : natural range 0 to 3;
    signal sequencer_stop : std_logic;
    signal recorder_append : std_logic;
    signal recorder_append_data : std_logic_vector(31 downto 0);
    signal recorder_update_en : std_logic;
    signal recorder_update_index : natural range 0 to 1023;
    signal recorder_update_duration : std_logic_vector(7 downto 0);
    signal recorder_update_velocity : std_logic_vector(4 downto 0);
    signal recorder_stop : std_logic;
    signal recording_active : std_logic;

    signal ms_divider : natural range 0 to 47 := 0;
    signal ms_tick : std_logic;
    signal sample_tick : std_logic;
    signal mixed_sample : signed(15 downto 0);
    signal processed_audio : signed(15 downto 0);
    signal audio_sample : audio_sample_t;
    signal audio_read_index : natural range 0 to 479 := 0;
    signal spectrum_level : unsigned(7 downto 0);
    signal spectrum_read_bin : natural range 0 to 63 := 0;
    signal lissajous_pixel : std_logic;
    signal lissajous_read_x, lissajous_read_y : natural range 0 to 95 := 0;

    signal frame_start : std_logic;
    signal pixel_x : natural range 0 to SCREEN_W-1;
    signal pixel_y : natural range 0 to SCREEN_H-1;
    signal pixel_color : rgb565_t;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset_count < RESET_CYCLES then
                reset_count <= reset_count + 1;
                ui_reset_n <= '0';
            else
                ui_reset_n <= '1';
            end if;
        end if;
    end process;

    reset_n <= ui_reset_n and rst_n;

    key_mapping: process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                key_map <= (0, 1, 2, 3, 4, 5, 6, 7);
                note_sources <= (0, 1, 2, 3, 4, 5, 6, 7);
            elsif map_write_en = '1' then
                key_map(map_channel) <= map_note;
                note_sources(map_note) <= map_channel;
            end if;
        end if;
    end process;

    map_physical_inputs: process(clk)
        variable mapped_on_v : std_logic_vector(7 downto 0);
        variable mapped_levels_v : sensor_array_t;
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                mapped_on <= (others => '0');
                mapped_levels <= (others => (others => '0'));
            else
                mapped_on_v := (others => '0');
                mapped_levels_v := (others => (others => '0'));
                for note in 0 to 7 loop
                    mapped_on_v(note) := sensor_on(note_sources(note));
                    mapped_levels_v(note) :=
                        sensor_levels(note_sources(note));
                end loop;
                mapped_on <= mapped_on_v;
                mapped_levels <= mapped_levels_v;
            end if;
        end if;
    end process;

    input_mixer: entity work.performance_mixer
        port map (
            mapped_on => mapped_on,
            mapped_levels => mapped_levels,
            remote_on => remote_on,
            remote_levels => remote_levels,
            remote_tones => remote_tones,
            remote_effects => remote_effects,
            remote_last_tone => remote_last_tone,
            remote_last_effect => remote_last_effect,
            ui_tone => settings.tone,
            ui_effect => effect_mode_t'pos(settings.effect_mode),
            playback_active => playback_active,
            virtual_on => virtual_on,
            virtual_levels => virtual_levels,
            playback_tone => playback_tone,
            playback_effect => playback_effect,
            effective_on => effective_on,
            effective_levels => effective_levels,
            effective_tones => effective_tones,
            effective_effects => effective_effects,
            selected_tone => mixed_tone,
            selected_effect => mixed_effect
        );

    led_note0 <= effective_on(0);
    led_note1 <= effective_on(1);
    led_note2 <= effective_on(2);
    led_note3 <= effective_on(3);
    led_note4 <= effective_on(4);
    led_note5 <= effective_on(5);
    led_note6 <= effective_on(6);
    led_note7 <= effective_on(7);

    select_playback_sound: process(settings, mixed_tone, mixed_effect)
        variable selected_v : settings_t;
    begin
        selected_v := settings;
        selected_v.tone := mixed_tone;
        selected_v.effect_mode := effect_mode_t'val(mixed_effect);
        active_settings <= selected_v;
    end process;

    one_ms_tick: process(clk)
    begin
        if rising_edge(clk) then
            ms_tick <= '0';
            if reset_n = '0' then
                ms_divider <= 0;
            elsif sample_tick = '1' then
                if ms_divider = 47 then
                    ms_divider <= 0;
                    ms_tick <= '1';
                else
                    ms_divider <= ms_divider + 1;
                end if;
            end if;
        end if;
    end process;

    event_clear <= command_clear or command_rec_start;
    event_append_en <= command_append or recorder_append;
    event_append_data <= recorder_append_data when recorder_append = '1'
                         else command_append_data;
    event_update_en <= recorder_update_en;
    event_update_index <= recorder_update_index;
    event_update_duration <= recorder_update_duration;
    event_update_velocity <= recorder_update_velocity;
    score_available <= '1' when event_count /= 0 else '0';
    physical_score_play <= physical_score_toggle when
        playback_active = '0' and test_mode = '0' else '0';
    physical_score_stop <= physical_score_toggle when
        playback_active = '1' else '0';
    sequencer_stop <= command_stop or command_rec_start or command_clear or
                      physical_score_stop;
    recorder_stop <= command_rec_stop or command_rec_play or
                     command_play or command_stop or command_clear or
                     physical_score_play;
    remote_clear <= command_stop or command_play or
                    command_rec_play or command_clear or
                    physical_score_play;
    event_read_index <= uploader_read_index when uploader_active = '1'
                        else sequencer_read_index;
    bt_tx_data <= uploader_tx_data when uploader_active = '1'
                  else parser_tx_data;
    bt_tx_valid <= uploader_tx_valid when uploader_active = '1'
                   else parser_tx_valid;

    test_mode_control: process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' or command_test_off = '1' or command_stop = '1' then
                test_mode <= '0';
            elsif command_test_on = '1' then
                test_mode <= '1';
            end if;
        end if;
    end process;

    left_encoder: entity work.ec11_decoder
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_ROT_FILTER_US => G_ROT_FILTER_US,
            G_KEY_DEBOUNCE_MS => G_KEY_DEBOUNCE_MS,
            G_EDGES_PER_STEP => G_EDGES_PER_STEP,
            G_REVERSE => G_ENCODER1_REVERSE
        )
        port map (
            clk => clk, reset_n => reset_n,
            enc_a => enc1_a, enc_b => enc1_b, key_n => enc1_key_n,
            step_left => l_prev, step_right => l_next, key_press => l_press
        );

    right_encoder: entity work.ec11_decoder
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_ROT_FILTER_US => G_ROT_FILTER_US,
            G_KEY_DEBOUNCE_MS => G_KEY_DEBOUNCE_MS,
            G_EDGES_PER_STEP => G_EDGES_PER_STEP,
            G_REVERSE => G_ENCODER2_REVERSE
        )
        port map (
            clk => clk, reset_n => reset_n,
            enc_a => enc2_a, enc_b => enc2_b, key_n => enc2_key_n,
            step_left => r_prev, step_right => r_next, key_press => r_press
        );

    controller: entity work.ui_controller
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_DEFAULT_TONE => G_DEFAULT_TONE,
            G_DEFAULT_VOLUME => G_DEFAULT_VOLUME,
            G_DEFAULT_ATTACK => G_DEFAULT_ATTACK,
            G_DEFAULT_DECAY => G_DEFAULT_DECAY,
            G_DEFAULT_SUSTAIN => G_DEFAULT_SUSTAIN,
            G_DEFAULT_RELEASE => G_DEFAULT_RELEASE,
            G_DEFAULT_BEND => G_DEFAULT_BEND,
            G_DEFAULT_VIBRATO => G_DEFAULT_VIBRATO,
            G_DEFAULT_GLIDE => G_DEFAULT_GLIDE,
            G_DEFAULT_EFFECT => G_DEFAULT_EFFECT,
            G_TIME_STEP_MS => G_TIME_STEP_MS,
            G_STATUS_MS => G_STATUS_MS
        )
        port map (
            clk => clk, reset_n => reset_n,
            left_next => l_next, left_prev => l_prev, left_press => l_press,
            right_next => r_next, right_prev => r_prev, right_press => r_press,
            voices_idle => voices_idle,
            focus_o => focus, preview_o => preview,
            settings_o => settings, status_o => status,
            pedal_mode_o => pedal_mode,
            octave_shift_o => octave_shift,
            score_available => score_available,
            score_control_o => physical_score_toggle
        );

    sensors: entity work.sensor_scanner
        generic map (
            ADC_POLL_DIV => G_ADC_POLL_DIV,
            SENSOR_ON_LEVEL => G_SENSOR_ON_LEVEL,
            SENSOR_OFF_LEVEL => G_SENSOR_OFF_LEVEL,
            SENSOR_DEBOUNCE => G_SENSOR_DEBOUNCE,
            SENSOR_FILTER_SHIFT => G_SENSOR_FILTER_SHIFT
        )
        port map (
            clk => clk, rst_n => reset_n,
            spi_clk => spi_clk, spi_din => spi_din,
            spi_dout => spi_dout, spi_cs_n => spi_cs_n,
            sensor_levels_o => sensor_levels,
            sensor_on_o => sensor_on
        );

    bluetooth_uart_rx: entity work.uart_rx
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD_RATE => 115_200
        )
        port map (
            clk => clk, rst_n => reset_n,
            rx => bt_rx,
            data_o => bt_rx_data,
            valid_o => bt_rx_valid
        );

    bluetooth_uart_tx: entity work.uart_tx
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_BAUD_RATE => 115_200
        )
        port map (
            clk => clk, rst_n => reset_n,
            data_in => bt_tx_data,
            data_valid => bt_tx_valid,
            ready => bt_tx_ready,
            tx => bt_tx
        );

    bluetooth_commands: entity work.command_parser
        port map (
            clk => clk, rst_n => reset_n,
            rx_data => bt_rx_data,
            rx_valid => bt_rx_valid,
            tx_ready => bt_tx_ready,
            tx_data => parser_tx_data,
            tx_valid => parser_tx_valid,
            map_write_en => map_write_en,
            map_channel => map_channel,
            map_note => map_note,
            score_clear => command_clear,
            append_en => command_append,
            append_data => command_append_data,
            play_score => command_play,
            stop_all => command_stop,
            rec_start => command_rec_start,
            rec_stop => command_rec_stop,
            rec_play => command_rec_play,
            key_down => key_down,
            key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            dump_start => dump_start,
            test_on => command_test_on,
            test_off => command_test_off,
            playback_active => playback_active,
            recording_active => recording_active,
            key_state => mapped_on,
            activity => open,
            event_count => event_count,
            event_full => event_full
        );

    phone_keys: entity work.remote_input
        port map (
            clk => clk, rst_n => reset_n,
            key_down => key_down,
            key_up => key_up,
            key_all_up => key_all_up,
            key_note => key_note,
            key_velocity => key_velocity,
            key_tone => key_tone,
            key_effect => key_effect,
            clear => remote_clear,
            on_o => remote_on,
            levels_o => remote_levels,
            tones_o => remote_tones,
            effects_o => remote_effects,
            last_tone_o => remote_last_tone,
            last_effect_o => remote_last_effect
        );

    score_storage: entity work.score_event_ram
        generic map (G_EVENT_CAPACITY => 1024)
        port map (
            clk => clk, rst_n => reset_n,
            clear => event_clear,
            append_en => event_append_en,
            append_data => event_append_data,
            update_en => event_update_en,
            update_index => event_update_index,
            update_duration => event_update_duration,
            update_velocity => event_update_velocity,
            read_index => event_read_index,
            read_data => event_read_data,
            event_count => event_count,
            full => event_full
        );

    recording_upload: entity work.event_uploader
        generic map (G_EVENT_CAPACITY => 1024)
        port map (
            clk => clk, rst_n => reset_n,
            start => dump_start,
            event_count => event_count,
            read_index => uploader_read_index,
            read_data => event_read_data,
            tx_ready => bt_tx_ready,
            tx_data => uploader_tx_data,
            tx_valid => uploader_tx_valid,
            busy => uploader_active
        );

    score_player: entity work.score_sequencer
        generic map (G_EVENT_CAPACITY => 1024)
        port map (
            clk => clk, rst_n => reset_n,
            ms_tick => ms_tick,
            play_start => command_play or physical_score_play,
            stop => sequencer_stop,
            event_count => event_count,
            read_index => sequencer_read_index,
            read_data => event_read_data,
            virtual_on => virtual_on,
            virtual_levels => virtual_levels,
            play_tone => playback_tone,
            play_effect => playback_effect,
            play_active => playback_active,
            busy => open
        );

    performance_recorder: entity work.score_recorder
        generic map (G_EVENT_CAPACITY => 1024)
        port map (
            clk => clk, rst_n => reset_n,
            ms_tick => ms_tick,
            start => command_rec_start,
            stop => recorder_stop,
            input_on => effective_on,
            input_levels => effective_levels,
            input_tones => effective_tones,
            input_effects => effective_effects,
            full => event_full,
            append_en => recorder_append,
            append_data => recorder_append_data,
            update_en => recorder_update_en,
            update_index => recorder_update_index,
            update_duration => recorder_update_duration,
            update_velocity => recorder_update_velocity,
            recording => recording_active
        );

    synth: entity work.synth_engine
        port map (
            clk => clk, rst_n => reset_n,
            sample_tick => sample_tick,
            settings => active_settings,
            sensor_on => effective_on,
            sensor_levels => effective_levels,
            pedal_mode => pedal_mode,
            octave_shift => octave_shift,
            test_mode => test_mode,
            mixed_sample => mixed_sample,
            voices_idle_o => voices_idle,
            active_count_o => active_count,
            note_active_o => note_active,
            debug_increment_o => open,
            debug_glide_remaining_o => open
        );

    effects: entity work.audio_effects
        port map (
            clk => clk, rst_n => reset_n,
            sample_tick => sample_tick,
            sample_in => mixed_sample,
            effect_mode => active_settings.effect_mode,
            audio_out => processed_audio
        );

    audio_i2s: entity work.i2s_transmitter
        port map (
            clk => clk, rst_n => reset_n,
            audio_left => processed_audio, audio_right => processed_audio,
            frame_tick => sample_tick,
            i2s_lrclk => i2s_lrclk,
            i2s_bclk => i2s_bclk,
            i2s_din => i2s_din
        );

    scope: entity work.audio_scope
        port map (
            clk => clk, rst_n => reset_n,
            sample_tick => sample_tick,
            sample_in => processed_audio,
            frame_start => frame_start,
            read_index => audio_read_index,
            audio_sample => audio_sample
        );

    spectrum: entity work.spectrum_analyzer
        port map (
            clk => clk, rst_n => reset_n,
            sample_tick => sample_tick,
            sample_in => processed_audio,
            test_mode => test_mode,
            display_latch => frame_start,
            read_bin => spectrum_read_bin,
            magnitude_o => spectrum_level,
            frame_ready => open
        );

    lissajous: entity work.lissajous_scope
        port map (
            clk => clk, rst_n => reset_n,
            sample_tick => sample_tick,
            sample_in => processed_audio,
            display_latch => frame_start,
            read_x => lissajous_read_x,
            read_y => lissajous_read_y,
            pixel_o => lissajous_pixel,
            frame_ready => open
        );

    process(pixel_x)
        variable rel_x, index_v : natural;
    begin
        index_v := 0;
        if pixel_x >= PREVIEW_X0+12 and pixel_x <= PREVIEW_X1-12 then
            rel_x := pixel_x - PREVIEW_X0 - 12;
            index_v := rel_x + rel_x / 8;
            if index_v > 479 then
                index_v := 479;
            end if;
        end if;
        audio_read_index <= index_v;
    end process;

    process(pixel_x, test_mode)
        variable rel_x, bin_v : natural;
        variable centered_v : unsigned(8 downto 0);
    begin
        bin_v := 0;
        if pixel_x >= SPECTRUM_X0 and pixel_x <= SPECTRUM_X1 then
            rel_x := pixel_x - SPECTRUM_X0;
            if test_mode = '1' then
                -- Center 32 four-pixel peaks in the spectrum area. The
                -- power-of-two pitch keeps the display logic free of a
                -- multiplier; bin 63 is always zero in test mode.
                if rel_x >= 80 and rel_x < 336 then
                    centered_v := to_unsigned(rel_x - 80, 9);
                    bin_v := to_integer(centered_v(8 downto 3));
                    if centered_v(2) = '1' then
                        bin_v := 63;
                    end if;
                else
                    bin_v := 63;
                end if;
            else
                bin_v := rel_x / 8;
                if bin_v > 51 then
                    bin_v := 51;
                end if;
            end if;
        end if;
        spectrum_read_bin <= bin_v;
    end process;

    process(pixel_x, pixel_y)
    begin
        if pixel_x >= LISSAJOUS_X0 and pixel_x <= LISSAJOUS_X1 and
           pixel_y >= LISSAJOUS_Y0 and pixel_y <= LISSAJOUS_Y1 then
            lissajous_read_x <= pixel_x - LISSAJOUS_X0;
            lissajous_read_y <= pixel_y - LISSAJOUS_Y0;
        else
            lissajous_read_x <= 0;
            lissajous_read_y <= 0;
        end if;
    end process;

    renderer: entity work.color_ui_renderer
        port map (
            clk => clk, reset_n => reset_n, frame_start_i => frame_start,
            focus_i => focus, preview_i => preview,
            settings_i => settings, status_i => status,
            pedal_mode_i => pedal_mode or test_mode,
            octave_shift_i => octave_shift,
            playback_active_i => playback_active,
            score_available_i => score_available,
            active_count_i => active_count,
            audio_sample_i => audio_sample,
            sensor_levels_i => sensor_levels,
            spectrum_level_i => spectrum_level,
            note_active_i => note_active,
            lissajous_pixel_i => lissajous_pixel,
            pixel_x_i => pixel_x, pixel_y_i => pixel_y,
            color_o => pixel_color
        );

    display: entity work.st7796s_display
        generic map (
            G_CLK_HZ => G_CLK_HZ,
            G_SPI_HALF_CYCLES => G_SPI_HALF_CYCLES
        )
        port map (
            clk => clk, reset_n => reset_n,
            frame_start_o => frame_start,
            pixel_x_o => pixel_x, pixel_y_o => pixel_y,
            pixel_data_i => pixel_color,
            lcd_sclk => lcd_sclk, lcd_mosi => lcd_mosi,
            lcd_cs_n => lcd_cs_n, lcd_dc => lcd_dc,
            lcd_rst_n => lcd_rst_n, lcd_bl => lcd_bl
        );
end architecture;
