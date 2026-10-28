library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Merges mapped pressure input with remote phone keys and selects playback
-- input when the score sequencer is active.
entity performance_mixer is
    port (
        mapped_on : in std_logic_vector(7 downto 0);
        mapped_levels : in sensor_array_t;
        remote_on : in std_logic_vector(7 downto 0);
        remote_levels : in sensor_array_t;
        remote_tones : in tone_array_t;
        remote_effects : in effect_array_t;
        remote_last_tone : in tone_index_t;
        remote_last_effect : in natural range 0 to 3;
        ui_tone : in tone_index_t;
        ui_effect : in natural range 0 to 3;

        playback_active : in std_logic;
        virtual_on : in std_logic_vector(7 downto 0);
        virtual_levels : in sensor_array_t;
        playback_tone : in tone_index_t;
        playback_effect : in natural range 0 to 3;

        effective_on : out std_logic_vector(7 downto 0);
        effective_levels : out sensor_array_t;
        effective_tones : out tone_array_t;
        effective_effects : out effect_array_t;
        selected_tone : out tone_index_t;
        selected_effect : out natural range 0 to 3
    );
end entity;

architecture rtl of performance_mixer is
begin
    process(
        mapped_on, mapped_levels, remote_on, remote_levels,
        remote_tones, remote_effects, remote_last_tone, remote_last_effect,
        ui_tone, ui_effect, playback_active,
        virtual_on, virtual_levels, playback_tone, playback_effect)
    begin
        if playback_active = '1' then
            effective_on <= virtual_on;
            effective_levels <= virtual_levels;
            effective_tones <= (others => playback_tone);
            effective_effects <= (others => playback_effect);
            selected_tone <= playback_tone;
            selected_effect <= playback_effect;
        else
            for note in 0 to 7 loop
                effective_on(note) <= mapped_on(note) or remote_on(note);
                if remote_levels(note) > mapped_levels(note) then
                    effective_levels(note) <= remote_levels(note);
                else
                    effective_levels(note) <= mapped_levels(note);
                end if;
                if remote_on(note) = '1' then
                    effective_tones(note) <= remote_tones(note);
                    effective_effects(note) <= remote_effects(note);
                else
                    effective_tones(note) <= ui_tone;
                    effective_effects(note) <= ui_effect;
                end if;
            end loop;
            if remote_on /= "00000000" then
                selected_tone <= remote_last_tone;
                selected_effect <= remote_last_effect;
            else
                selected_tone <= ui_tone;
                selected_effect <= ui_effect;
            end if;
        end if;
    end process;
end architecture;
