library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use work.pitch_lut.all;

-- 八路压力输入驱动 32 个独立声部，输出直接送 I2S 和示波器。
entity synth_engine is
    generic (
        G_GLIDE_SAMPLES_PER_MS : positive := 49
    );
    port (
        clk, rst_n  : in  std_logic;
        sample_tick : in  std_logic;
        settings    : in  settings_t;
        sensor_on   : in  std_logic_vector(7 downto 0);
        sensor_levels : in sensor_array_t;
        pedal_mode    : in std_logic;
        octave_shift  : in std_logic;
        test_mode     : in std_logic;
        mixed_sample  : out signed(15 downto 0);
        voices_idle_o : out std_logic;
        active_count_o : out voice_count_t;
        note_active_o : out std_logic_vector(7 downto 0);
        debug_increment_o : out unsigned(31 downto 0);
        debug_glide_remaining_o : out natural range 0 to 32
    );
end entity;

architecture rtl of synth_engine is
    type sine_table_t is array (0 to 127) of signed(15 downto 0);
    type env_state_t is (ENV_IDLE, ENV_ATTACK, ENV_DECAY, ENV_SUSTAIN, ENV_RELEASE);
    type note_increment_array_t is array (0 to 7) of unsigned(31 downto 0);

    constant SINE_TABLE : sine_table_t := (
        x"0000", x"0648", x"0C8B", x"12C7", x"18F8", x"1F19", x"2527", x"2B1E",
        x"30FB", x"36B9", x"3C56", x"41CD", x"471C", x"4C3F", x"5133", x"55F5",
        x"5A81", x"5ED6", x"62F1", x"66CE", x"6A6D", x"6DC9", x"70E2", x"73B5",
        x"7641", x"7884", x"7A7C", x"7C29", x"7D89", x"7E9C", x"7F62", x"7FD8",
        x"7FFF", x"7FD8", x"7F62", x"7E9C", x"7D89", x"7C29", x"7A7C", x"7884",
        x"7641", x"73B5", x"70E2", x"6DC9", x"6A6D", x"66CE", x"62F1", x"5ED6",
        x"5A81", x"55F5", x"5133", x"4C3F", x"471C", x"41CD", x"3C56", x"36B9",
        x"30FB", x"2B1E", x"2527", x"1F19", x"18F8", x"12C7", x"0C8B", x"0648",
        x"0000", x"F9B8", x"F375", x"ED39", x"E708", x"E0E7", x"DAD9", x"D4E2",
        x"CF05", x"C947", x"C3AA", x"BE33", x"B8E4", x"B3C1", x"AECD", x"AA0B",
        x"A57F", x"A12A", x"9D0F", x"9932", x"9593", x"9237", x"8F1E", x"8C4B",
        x"89BF", x"877C", x"8584", x"83D7", x"8277", x"8164", x"809E", x"8028",
        x"8001", x"8028", x"809E", x"8164", x"8277", x"83D7", x"8584", x"877C",
        x"89BF", x"8C4B", x"8F1E", x"9237", x"9593", x"9932", x"9D0F", x"A12A",
        x"A57F", x"AA0B", x"AECD", x"B3C1", x"B8E4", x"BE33", x"C3AA", x"C947",
        x"CF05", x"D4E2", x"DAD9", x"E0E7", x"E708", x"ED39", x"F375", x"F9B8"
    );

    constant PHASE_INCREMENTS : note_increment_array_t := (
        to_unsigned(23012831, 32), to_unsigned(25831029, 32),
        to_unsigned(28994350, 32), to_unsigned(30718437, 32),
        to_unsigned(34480280, 32), to_unsigned(38702809, 32),
        to_unsigned(43442434, 32), to_unsigned(46025653, 32)
    );
    constant VIBRATO_PHASE_INCREMENT : unsigned(31 downto 0) :=
        to_unsigned(483785, 32);

    signal voice_write_enable : std_logic := '0';
    signal voice_read_address : voice_index_t := 0;
    signal voice_write_address : voice_index_t := 0;
    signal voice_write_data : voice_word_t := (others => '0');
    signal voice_read_data : voice_word_t;
    signal last_note_increment : unsigned(31 downto 0) := PHASE_INCREMENTS(0);
    signal lfo_phase : unsigned(31 downto 0) := (others => '0');
    signal lfo_sample : signed(15 downto 0) := (others => '0');
    signal pitch_factor_global : unsigned(15 downto 0) :=
        to_unsigned(16384, 16);
    signal allocator_held : std_logic_vector(POLYPHONY-1 downto 0);
    signal allocator_trigger : std_logic_vector(POLYPHONY-1 downto 0);
    signal trigger_pending : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal voice_done : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal allocator_meta : std_logic_vector(14 downto 0);
    signal active_count : voice_count_t;
    signal note_active : std_logic_vector(7 downto 0);
    signal debug_increment_reg : unsigned(31 downto 0) := (others => '0');
    signal debug_glide_remaining_reg : natural range 0 to 32 := 0;
    signal mixed_reg : signed(15 downto 0) := (others => '0');
    signal ms_divider : natural range 0 to 48 := 0;
    signal volume_snapshot : natural range 0 to 100 := 0;
    signal master_gain : natural range 0 to 255 := 0;
    signal attack_step, decay_step, release_step : natural range 1 to 255 := 1;
    signal sustain_level : natural range 0 to 4095 := 0;
    signal processing : std_logic := '0';
    signal voice_index : voice_index_t := 0;
    signal voice_phase : natural range 0 to 10 := 0;
    signal sum_accum : signed(22 downto 0) := (others => '0');
    signal ms_tick_active : std_logic := '0';
    signal selected_target_inc : unsigned(31 downto 0) := PHASE_INCREMENTS(0);
    signal selected_active_inc : unsigned(31 downto 0) := PHASE_INCREMENTS(0);
    signal selected_phase : unsigned(31 downto 0) := (others => '0');
    signal selected_envelope : natural range 0 to 4095 := 0;
    signal selected_expression : natural range 0 to 65535 := 0;
    signal selected_level : sensor_level_t := (others => '0');
    signal selected_sensor : std_logic := '0';
    signal selected_trigger : std_logic := '0';
    signal selected_tone : tone_index_t := 0;
    signal selected_state : env_state_t := ENV_IDLE;
    signal selected_glide_step : signed(31 downto 0) := (others => '0');
    signal selected_glide_remaining : natural range 0 to 32 := 0;
    signal selected_glide_interval : natural range 0 to 2047 := 0;
    signal selected_glide_counter : natural range 0 to 2047 := 0;
    signal glide_start_inc : unsigned(31 downto 0) := PHASE_INCREMENTS(0);
    signal computed_inc : unsigned(31 downto 0) := PHASE_INCREMENTS(0);
    signal wave_phase_reg : unsigned(31 downto 0) := (others => '0');
    signal wave_sample_reg : signed(15 downto 0) := (others => '0');
    signal voice_gain_reg : natural range 0 to 255 := 0;
    signal voice_scaled_reg : signed(20 downto 0) := (others => '0');
    signal finalize_level : natural range 0 to 2 := 0;
    signal voice_normalizer : natural range 0 to 256 := 0;
    signal normalizer_divider : natural range 0 to 3 := 0;
    signal normalized_master_gain : natural range 0 to 255 := 0;

    function waveform(tone : natural; phase_value : unsigned(31 downto 0))
        return signed is
        variable index : natural;
        variable saw_value : integer;
        variable tri_value : integer;
    begin
        index := to_integer(phase_value(31 downto 25));
        case tone is
            when 0 => return SINE_TABLE(index);
            when 1 =>
                if index < 64 then
                    return to_signed(30000, 16);
                else
                    return to_signed(-30000, 16);
                end if;
            when 2 =>
                saw_value := index * 508 - 32258;
                return to_signed(saw_value, 16);
            when others =>
                if index < 64 then
                    tri_value := -32000 + index * 1000;
                else
                    tri_value := 31000 - (index - 64) * 1000;
                end if;
                return to_signed(tri_value, 16);
        end case;
    end function;

    function attack_value(ms : natural) return natural is
    begin
        if ms <= 20 then return 255;
        elsif ms <= 40 then return 128;
        elsif ms <= 80 then return 64;
        elsif ms <= 160 then return 32;
        elsif ms <= 320 then return 16;
        elsif ms <= 640 then return 8;
        elsif ms <= 1280 then return 4;
        elsif ms <= 2000 then return 3;
        else return 1;
        end if;
    end function;

    function release_value(ms : natural) return natural is
    begin
        if ms <= 20 then return 255;
        elsif ms <= 40 then return 128;
        elsif ms <= 80 then return 64;
        elsif ms <= 160 then return 32;
        elsif ms <= 320 then return 16;
        elsif ms <= 640 then return 8;
        elsif ms <= 1280 then return 4;
        elsif ms <= 2560 then return 2;
        else return 1;
        end if;
    end function;

    function soft_limiter(value : signed(21 downto 0)) return audio_sample_t is
        constant KNEE : signed(21 downto 0) := to_signed(27000, 22);
        variable magnitude : signed(21 downto 0);
        variable limited_magnitude : signed(15 downto 0);
    begin
        if value >= 0 then
            magnitude := value;
        else
            magnitude := -value;
        end if;

        if magnitude <= KNEE then
            limited_magnitude := magnitude(15 downto 0);
        elsif magnitude <= to_signed(32768, 22) then
            limited_magnitude := to_signed(27000, 16) +
                resize(shift_right(magnitude - KNEE, 1), 16);
        elsif magnitude <= to_signed(65536, 22) then
            limited_magnitude := to_signed(29884, 16) +
                resize(shift_right(magnitude - to_signed(32768, 22), 4), 16);
        elsif magnitude <= to_signed(131072, 22) then
            limited_magnitude := to_signed(31932, 16) +
                resize(shift_right(magnitude - to_signed(65536, 22), 8), 16);
        elsif magnitude <= to_signed(262144, 22) then
            limited_magnitude := to_signed(32188, 16) +
                resize(shift_right(magnitude - to_signed(131072, 22), 10), 16);
        elsif magnitude <= to_signed(524288, 22) then
            limited_magnitude := to_signed(32316, 16) +
                resize(shift_right(magnitude - to_signed(262144, 22), 12), 16);
        elsif magnitude <= to_signed(1048576, 22) then
            limited_magnitude := to_signed(32412, 16) +
                resize(shift_right(magnitude - to_signed(524288, 22), 14), 16);
        else
            limited_magnitude := to_signed(32476, 16) +
                resize(shift_right(magnitude - to_signed(1048576, 22), 16), 16);
        end if;

        if value < 0 then
            return -limited_magnitude;
        else
            return limited_magnitude;
        end if;
    end function;

    function normalizer_for(count : natural) return natural is
    begin
        case count is
            when 0 => return 0;
            when 1 => return 256;
            when 2 => return 181;
            when 3 => return 148;
            when 4 => return 128;
            when 5 => return 114;
            when 6 => return 105;
            when 7 => return 97;
            when 8 => return 91;
            when 9 => return 85;
            when 10 => return 81;
            when 11 => return 77;
            when 12 => return 74;
            when 13 => return 71;
            when 14 => return 68;
            when 15 => return 66;
            when 16 => return 64;
            when 17 => return 62;
            when 18 => return 60;
            when 19 => return 59;
            when 20 => return 57;
            when 21 => return 56;
            when 22 => return 55;
            when 23 => return 53;
            when 24 => return 52;
            when 25 => return 51;
            when 26 => return 50;
            when 27 => return 49;
            when 28 => return 48;
            when 29 => return 48;
            when 30 => return 47;
            when 31 => return 46;
            when others => return 45;
        end case;
    end function;

    function encode_env(state_value : env_state_t) return unsigned is
    begin
        case state_value is
            when ENV_IDLE    => return to_unsigned(0, 3);
            when ENV_ATTACK  => return to_unsigned(1, 3);
            when ENV_DECAY   => return to_unsigned(2, 3);
            when ENV_SUSTAIN => return to_unsigned(3, 3);
            when others      => return to_unsigned(4, 3);
        end case;
    end function;

    function decode_env(code : unsigned(2 downto 0)) return env_state_t is
    begin
        case to_integer(code) is
            when 1 => return ENV_ATTACK;
            when 2 => return ENV_DECAY;
            when 3 => return ENV_SUSTAIN;
            when 4 => return ENV_RELEASE;
            when others => return ENV_IDLE;
        end case;
    end function;
begin
    allocator: entity work.voice_allocator
        port map (
            clk => clk, rst_n => rst_n,
            sensor_on => sensor_on,
            sensor_levels => sensor_levels,
            pedal_mode => pedal_mode,
            selected_tone => settings.tone,
            voice_done => voice_done,
            meta_read_address => voice_index,
            voice_meta_o => allocator_meta,
            voice_held_o => allocator_held,
            voice_trigger_o => allocator_trigger,
            note_active_o => note_active,
            active_count_o => active_count
        );

    state_ram: entity work.voice_state_ram
        port map (
            clk => clk,
            read_address => voice_read_address,
            write_enable => voice_write_enable,
            write_address => voice_write_address,
            write_data => voice_write_data,
            read_data => voice_read_data
        );

    -- 每个声部使用多级流水线：
    -- 0 读取状态 -> 1 记录新按键起点 -> 2~4 计算滑音 ->
    -- 5 叠加弯音/揉音 -> 6 计算包络和波形 -> 7~8 缩放与混音。
    -- 这样 50 MHz 时钟不需要在一个周期内完成全部运算。
    process(clk)
        variable next_phase : unsigned(31 downto 0);
        variable env8 : unsigned(7 downto 0);
        variable amp8 : unsigned(7 downto 0);
        variable gain_product : unsigned(15 downto 0);
        variable gain8 : unsigned(7 downto 0);
        variable scaled_voice : signed(24 downto 0);
        variable master_product : signed(31 downto 0);
        variable target_expression : natural range 0 to 65535;
        variable expression_delta : natural range 0 to 65535;
        variable next_lfo_phase : unsigned(31 downto 0);
        variable lfo_cents : integer;
        variable total_cents : integer;
        variable next_inc : unsigned(31 downto 0);
        variable factor_product : unsigned(47 downto 0);
        variable glide_diff : signed(32 downto 0);
        variable glide_step_v : signed(31 downto 0);
        variable glide_interval_v : natural range 0 to 2047;
        variable glide_sum : signed(32 downto 0);
        variable env_value : natural range 0 to 4095;
        variable expression_value : natural range 0 to 65535;
        variable normalizer_target_v : natural range 0 to 256;
        variable state_value : env_state_t;
    begin
        if rising_edge(clk) then
            trigger_pending <= trigger_pending or allocator_trigger;
            voice_done <= (others => '0');
            voice_write_enable <= '0';
            volume_snapshot <= settings.volume;
            if rst_n = '0' then
                voice_read_address <= 0;
                voice_write_address <= 0;
                voice_write_data <= (others => '0');
                last_note_increment <= PHASE_INCREMENTS(0);
                lfo_phase <= (others => '0');
                lfo_sample <= (others => '0');
                pitch_factor_global <= to_unsigned(16384, 16);
                mixed_reg <= (others => '0');
                ms_divider <= 0;
                volume_snapshot <= 0;
                master_gain <= 0;
                processing <= '0';
                voice_index <= 0;
                voice_phase <= 0;
                sum_accum <= (others => '0');
                ms_tick_active <= '0';
                wave_phase_reg <= (others => '0');
                wave_sample_reg <= (others => '0');
                voice_gain_reg <= 0;
                voice_scaled_reg <= (others => '0');
                finalize_level <= 0;
                voice_normalizer <= 0;
                normalizer_divider <= 0;
                normalized_master_gain <= 0;
                debug_increment_reg <= (others => '0');
                debug_glide_remaining_reg <= 0;
                selected_target_inc <= PHASE_INCREMENTS(0);
                selected_active_inc <= PHASE_INCREMENTS(0);
                selected_phase <= (others => '0');
                selected_envelope <= 0;
                selected_expression <= 0;
                selected_level <= (others => '0');
                selected_sensor <= '0';
                selected_trigger <= '0';
                selected_tone <= 0;
                selected_state <= ENV_IDLE;
                selected_glide_step <= (others => '0');
                selected_glide_remaining <= 0;
                selected_glide_interval <= 0;
                selected_glide_counter <= 0;
                glide_start_inc <= PHASE_INCREMENTS(0);
                computed_inc <= PHASE_INCREMENTS(0);
            elsif sample_tick = '1' then
                next_lfo_phase := lfo_phase + VIBRATO_PHASE_INCREMENT;
                lfo_phase <= next_lfo_phase;
                lfo_sample <= SINE_TABLE(to_integer(next_lfo_phase(31 downto 25)));

                lfo_cents :=
                    (to_integer(lfo_sample) * settings.vibrato_cents) / 32768;
                total_cents := settings.bend_cents + lfo_cents;
                if total_cents > 250 then
                    total_cents := 250;
                elsif total_cents < -250 then
                    total_cents := -250;
                end if;
                pitch_factor_global <= pitch_factor(total_cents);

                processing <= '1';
                voice_index <= 0;
                voice_phase <= 0;
                sum_accum <= (others => '0');
                finalize_level <= 0;
                master_gain <= volume_snapshot * 141 / 100;
                attack_step <= attack_value(settings.attack_ms);
                decay_step <= attack_value(settings.decay_ms);
                release_step <= release_value(settings.release_ms);
                sustain_level <= settings.sustain * 40;
                if ms_divider = 48 then
                    ms_divider <= 0;
                    ms_tick_active <= '1';
                else
                    ms_divider <= ms_divider + 1;
                    ms_tick_active <= '0';
                end if;

                if normalizer_divider = 3 then
                    normalizer_divider <= 0;
                else
                    normalizer_divider <= normalizer_divider + 1;
                end if;
                if test_mode = '1' then
                    normalizer_target_v := normalizer_for(POLYPHONY);
                else
                    normalizer_target_v := normalizer_for(active_count);
                end if;
                if normalizer_target_v >= voice_normalizer then
                    voice_normalizer <= normalizer_target_v;
                elsif normalizer_divider = 3 then
                    voice_normalizer <= voice_normalizer - 1;
                end if;
            elsif processing = '1' then
                case voice_phase is
                    when 0 =>
                        voice_read_address <= voice_index;
                        if test_mode = '1' then
                            selected_target_inc <= to_unsigned(18_874_368, 32) +
                                shift_left(to_unsigned(voice_index, 32), 22);
                            selected_level <= to_unsigned(1023, 10);
                            selected_sensor <= '1';
                            selected_trigger <= '0';
                            selected_tone <= 0;
                        else
                            if octave_shift = '1' then
                                selected_target_inc <= shift_left(
                                    PHASE_INCREMENTS(to_integer(
                                        unsigned(allocator_meta(2 downto 0)))), 1);
                            else
                                selected_target_inc <=
                                    PHASE_INCREMENTS(to_integer(
                                        unsigned(allocator_meta(2 downto 0))));
                            end if;
                            selected_level <= unsigned(allocator_meta(14 downto 5));
                            selected_sensor <= allocator_held(voice_index);
                            selected_trigger <= trigger_pending(voice_index) or
                                                allocator_trigger(voice_index);
                        end if;
                        trigger_pending(voice_index) <= '0';
                        voice_phase <= 1;
                    when 1 =>
                        voice_phase <= 2;
                    when 2 =>
                        selected_phase <= unsigned(voice_read_data(31 downto 0));
                        selected_active_inc <=
                            unsigned(voice_read_data(63 downto 32));
                        selected_envelope <=
                            to_integer(unsigned(voice_read_data(75 downto 64)));
                        selected_expression <=
                            to_integer(unsigned(voice_read_data(91 downto 76)));
                        selected_state <= decode_env(
                            unsigned(voice_read_data(94 downto 92)));
                        selected_tone <=
                            to_integer(unsigned(voice_read_data(96 downto 95)));
                        selected_glide_step <=
                            signed(voice_read_data(128 downto 97));
                        selected_glide_remaining <=
                            to_integer(unsigned(voice_read_data(134 downto 129)));
                        selected_glide_interval <=
                            to_integer(unsigned(voice_read_data(145 downto 135)));
                        selected_glide_counter <=
                            to_integer(unsigned(voice_read_data(156 downto 146)));
                        voice_phase <= 3;
                    when 3 =>
                        if selected_trigger = '1' then
                            glide_start_inc <= last_note_increment;
                            last_note_increment <= selected_target_inc;
                        else
                            glide_start_inc <= selected_active_inc;
                        end if;
                        voice_phase <= 4;
                    when 4 =>
                        if test_mode = '1' then
                            selected_active_inc <= selected_target_inc;
                            selected_glide_remaining <= 0;
                            computed_inc <= selected_target_inc;
                        elsif selected_trigger = '1' then
                            if settings.glide_ms = 0 then
                                selected_active_inc <= selected_target_inc;
                                selected_glide_step <= (others => '0');
                                selected_glide_remaining <= 0;
                                selected_glide_interval <= 0;
                                selected_glide_counter <= 0;
                                computed_inc <= selected_target_inc;
                            else
                                glide_diff :=
                                    signed(resize(selected_target_inc, 33)) -
                                    signed(resize(glide_start_inc, 33));
                                if glide_diff >= 0 then
                                    glide_step_v := resize(shift_right(
                                        glide_diff + 31, 5), 32);
                                else
                                    glide_step_v := -resize(shift_right(
                                        (-glide_diff) + 31, 5), 32);
                                end if;
                                glide_interval_v :=
                                    (settings.glide_ms *
                                     G_GLIDE_SAMPLES_PER_MS) / 32;
                                if glide_interval_v = 0 then
                                    glide_interval_v := 1;
                                end if;
                                selected_active_inc <= glide_start_inc;
                                selected_glide_step <= glide_step_v;
                                selected_glide_remaining <= 32;
                                selected_glide_interval <= glide_interval_v;
                                selected_glide_counter <= glide_interval_v;
                                computed_inc <= glide_start_inc;
                            end if;
                        else
                            if selected_glide_remaining /= 0 then
                                if selected_glide_counter <= 1 then
                                    glide_sum :=
                                        signed(resize(selected_active_inc, 33)) +
                                        resize(selected_glide_step, 33);
                                    if selected_glide_step > 0 and
                                       glide_sum >= signed(resize(
                                           selected_target_inc, 33)) then
                                        next_inc := selected_target_inc;
                                    elsif selected_glide_step < 0 and
                                          glide_sum <= signed(resize(
                                              selected_target_inc, 33)) then
                                        next_inc := selected_target_inc;
                                    else
                                        next_inc := unsigned(glide_sum(31 downto 0));
                                    end if;
                                    selected_active_inc <= next_inc;
                                    selected_glide_remaining <=
                                        selected_glide_remaining - 1;
                                    selected_glide_counter <=
                                        selected_glide_interval;
                                    computed_inc <= next_inc;
                                else
                                    selected_glide_counter <=
                                        selected_glide_counter - 1;
                                    computed_inc <= selected_active_inc;
                                end if;
                            else
                                selected_active_inc <= selected_target_inc;
                                computed_inc <= selected_target_inc;
                            end if;
                        end if;
                        voice_phase <= 5;
                    when 5 =>
                        voice_phase <= 6;
                    when 6 =>
                        voice_phase <= 7;
                    when 7 =>
                        factor_product := computed_inc * pitch_factor_global;
                        if selected_trigger = '1' then
                            next_phase := (others => '0');
                        else
                            next_phase := selected_phase +
                                          factor_product(45 downto 14);
                        end if;
                        selected_active_inc <= computed_inc;
                        selected_phase <= next_phase;
                        if selected_trigger = '1' then
                            selected_tone <= to_integer(
                                unsigned(allocator_meta(4 downto 3)));
                        end if;
                        wave_phase_reg <= next_phase;
                        voice_phase <= 8;
                    when 8 =>
                        env_value := selected_envelope;
                        expression_value := selected_expression;
                        state_value := selected_state;
                        if test_mode = '1' and selected_state = ENV_IDLE then
                            state_value := ENV_SUSTAIN;
                            env_value := 4095;
                        elsif selected_trigger = '1' then
                            state_value := ENV_ATTACK;
                            env_value := 0;
                            expression_value := 0;
                        elsif selected_sensor = '0' and
                              selected_state /= ENV_IDLE and
                              selected_state /= ENV_RELEASE then
                            state_value := ENV_RELEASE;
                        elsif ms_tick_active = '1' then
                            case selected_state is
                                when ENV_ATTACK =>
                                    if env_value + attack_step >= 4095 then
                                        env_value := 4095;
                                        state_value := ENV_DECAY;
                                    else
                                        env_value := env_value + attack_step;
                                    end if;
                                when ENV_DECAY =>
                                    if env_value <= sustain_level + decay_step then
                                        env_value := sustain_level;
                                        state_value := ENV_SUSTAIN;
                                    else
                                        env_value := env_value - decay_step;
                                    end if;
                                when ENV_SUSTAIN =>
                                    env_value := sustain_level;
                                when ENV_RELEASE =>
                                    if env_value <= release_step then
                                        env_value := 0;
                                        state_value := ENV_IDLE;
                                        voice_done(voice_index) <= '1';
                                    else
                                        env_value := env_value - release_step;
                                    end if;
                                when others =>
                                    env_value := 0;
                            end case;
                        end if;

                        env8 := to_unsigned(env_value / 16, 8);
                        amp8 := to_unsigned(expression_value / 256, 8);
                        gain_product := env8 * amp8;
                        gain8 := gain_product(15 downto 8);
                        voice_gain_reg <= to_integer(gain8);
                        wave_sample_reg <= waveform(selected_tone, wave_phase_reg);

                        target_expression :=
                            to_integer(selected_level(9 downto 2)) * 256;
                        if expression_value < target_expression then
                            expression_delta :=
                                target_expression - expression_value;
                            if expression_delta > 2048 then
                                expression_value :=
                                    expression_value +
                                    expression_delta / 2048;
                            else
                                expression_value := expression_value + 1;
                            end if;
                        elsif expression_value > target_expression then
                            expression_delta :=
                                expression_value - target_expression;
                            if expression_delta > 2048 then
                                expression_value :=
                                    expression_value -
                                    expression_delta / 2048;
                            else
                                expression_value := expression_value - 1;
                            end if;
                        end if;
                        selected_state <= state_value;
                        selected_envelope <= env_value;
                        selected_expression <= expression_value;
                        voice_phase <= 9;
                    when 9 =>
                        scaled_voice := wave_sample_reg *
                                        signed('0' & to_unsigned(voice_gain_reg, 8));
                        voice_scaled_reg <= resize(
                            shift_left(scaled_voice(24 downto 8), 1), 21);
                        voice_phase <= 10;
                    when others =>
                        if voice_index = 0 then
                            debug_increment_reg <= selected_active_inc;
                            debug_glide_remaining_reg <=
                                selected_glide_remaining;
                        end if;
                        voice_write_enable <= '1';
                        voice_write_address <= voice_index;
                        voice_write_data <=
                            std_logic_vector(to_unsigned(
                                selected_glide_counter, 11)) &
                            std_logic_vector(to_unsigned(
                                selected_glide_interval, 11)) &
                            std_logic_vector(to_unsigned(
                                selected_glide_remaining, 6)) &
                            std_logic_vector(selected_glide_step) &
                            std_logic_vector(to_unsigned(selected_tone, 2)) &
                            std_logic_vector(encode_env(selected_state)) &
                            std_logic_vector(to_unsigned(
                                selected_expression, 16)) &
                            std_logic_vector(to_unsigned(
                                selected_envelope, 12)) &
                            std_logic_vector(selected_active_inc) &
                            std_logic_vector(selected_phase);
                        sum_accum <= sum_accum +
                                     resize(voice_scaled_reg, sum_accum'length);
                        if voice_index = POLYPHONY-1 then
                            processing <= '0';
                            finalize_level <= 1;
                        else
                            voice_index <= voice_index + 1;
                            voice_phase <= 0;
                        end if;
                end case;
            elsif finalize_level = 1 then
                normalized_master_gain <=
                    (master_gain * voice_normalizer) / 256;
                finalize_level <= 2;
            elsif finalize_level = 2 then
                master_product := sum_accum *
                                  signed('0' & to_unsigned(normalized_master_gain, 8));
                mixed_reg <= soft_limiter(master_product(29 downto 8));
                finalize_level <= 0;
            end if;
        end if;
    end process;

    mixed_sample <= mixed_reg;
    active_count_o <= POLYPHONY when test_mode = '1' else active_count;
    note_active_o <= note_active when test_mode = '0' else (others => '0');
    debug_increment_o <= debug_increment_reg;
    debug_glide_remaining_o <= debug_glide_remaining_reg;
    voices_idle_o <= '1' when test_mode = '0' and active_count = 0 else '0';
end architecture;
