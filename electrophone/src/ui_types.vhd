library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- 单屏界面、控制器和绘制器共用的数据类型。
package ui_types is
    type focus_t is (
        FOCUS_TIMBRE, FOCUS_VOLUME,
        FOCUS_ATTACK, FOCUS_DECAY, FOCUS_SUSTAIN, FOCUS_RELEASE,
        FOCUS_BEND, FOCUS_VIBRATO, FOCUS_GLIDE, FOCUS_PLUCK, FOCUS_EFFECT,
        FOCUS_OCTAVE
    );
    type preview_t is (
        PREVIEW_AUDIO, PREVIEW_SPECTRUM, PREVIEW_LISSAJOUS,
        PREVIEW_PRESSURE, PREVIEW_ENVELOPE
    );
    type status_t is (STATUS_NONE, STATUS_RESET);
    type effect_mode_t is (FX_DRY, FX_DELAY, FX_CHORUS, FX_REVERB);
    type settings_t is record
        tone       : natural range 0 to 3;
        volume     : natural range 0 to 100;
        attack_ms  : natural range 0 to 2000;
        decay_ms   : natural range 0 to 2000;
        sustain    : natural range 0 to 100;
        release_ms : natural range 0 to 5000;
        bend_cents : integer range -200 to 200;
        vibrato_cents : natural range 0 to 50;
        glide_ms   : natural range 0 to 1000;
        effect_mode: effect_mode_t;
    end record;
    subtype byte_t is std_logic_vector(7 downto 0);
    subtype rgb565_t is std_logic_vector(15 downto 0);
    subtype audio_sample_t is signed(15 downto 0);
    type audio_frame_t is array (0 to 479) of audio_sample_t;
    subtype sensor_level_t is unsigned(9 downto 0);
    type sensor_array_t is array (0 to 7) of sensor_level_t;

    constant POLYPHONY : positive := 32;
    subtype voice_index_t is natural range 0 to POLYPHONY-1;
    subtype voice_count_t is natural range 0 to POLYPHONY;
    subtype note_index_t is natural range 0 to 7;
    subtype tone_index_t is natural range 0 to 3;
    type note_map_array_t is array (0 to 7) of note_index_t;
    type tone_array_t is array (0 to 7) of tone_index_t;
    type effect_array_t is array (0 to 7) of natural range 0 to 3;
    type poly_level_array_t is array (voice_index_t) of sensor_level_t;
    type poly_note_array_t is array (voice_index_t) of note_index_t;
    type poly_tone_array_t is array (voice_index_t) of tone_index_t;
    subtype voice_word_t is std_logic_vector(156 downto 0);
end package;
