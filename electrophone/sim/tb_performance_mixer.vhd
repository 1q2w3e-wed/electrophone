library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use std.env.all;

entity tb_performance_mixer is
end entity;

architecture sim of tb_performance_mixer is
    signal mapped_on : std_logic_vector(7 downto 0) := (others => '0');
    signal mapped_levels : sensor_array_t := (others => (others => '0'));
    signal remote_on : std_logic_vector(7 downto 0) := (others => '0');
    signal remote_levels : sensor_array_t := (others => (others => '0'));
    signal remote_tones : tone_array_t := (others => 0);
    signal remote_effects : effect_array_t := (others => 0);
    signal remote_last_tone : tone_index_t := 0;
    signal remote_last_effect : natural range 0 to 3 := 0;
    signal ui_tone : tone_index_t := 1;
    signal ui_effect : natural range 0 to 3 := 2;
    signal playback_active : std_logic := '0';
    signal virtual_on : std_logic_vector(7 downto 0) := (others => '0');
    signal virtual_levels : sensor_array_t := (others => (others => '0'));
    signal playback_tone : tone_index_t := 0;
    signal playback_effect : natural range 0 to 3 := 0;
    signal effective_on : std_logic_vector(7 downto 0);
    signal effective_levels : sensor_array_t;
    signal effective_tones : tone_array_t;
    signal effective_effects : effect_array_t;
    signal selected_tone : tone_index_t;
    signal selected_effect : natural range 0 to 3;
begin
    dut: entity work.performance_mixer
        port map (
            mapped_on => mapped_on, mapped_levels => mapped_levels,
            remote_on => remote_on, remote_levels => remote_levels,
            remote_tones => remote_tones, remote_effects => remote_effects,
            remote_last_tone => remote_last_tone,
            remote_last_effect => remote_last_effect,
            ui_tone => ui_tone, ui_effect => ui_effect,
            playback_active => playback_active,
            virtual_on => virtual_on, virtual_levels => virtual_levels,
            playback_tone => playback_tone, playback_effect => playback_effect,
            effective_on => effective_on,
            effective_levels => effective_levels,
            effective_tones => effective_tones,
            effective_effects => effective_effects,
            selected_tone => selected_tone,
            selected_effect => selected_effect
        );

    stimulus: process
    begin
        wait for 10 ns;

        mapped_on(0) <= '1';
        mapped_levels(0) <= to_unsigned(320, 10);
        remote_on(0) <= '1';
        remote_levels(0) <= to_unsigned(640, 10);
        remote_tones(0) <= 3;
        remote_effects(0) <= 1;
        remote_last_tone <= 3;
        remote_last_effect <= 1;
        wait for 10 ns;
        assert effective_on = "00000001"
            report "Mapped and remote copies did not merge" severity failure;
        assert effective_levels(0) = to_unsigned(640, 10)
            report "Mixer did not select the larger pressure" severity failure;
        assert effective_tones(0) = 3 and effective_effects(0) = 1
            report "Remote metadata did not take precedence" severity failure;
        assert selected_tone = 3 and selected_effect = 1
            report "Latest remote sound selection was not used"
            severity failure;

        remote_on(0) <= '0';
        wait for 10 ns;
        assert effective_on(0) = '1'
            report "Physical note stopped while still held" severity failure;
        assert effective_tones(0) = 1 and effective_effects(0) = 2
            report "Physical note did not use UI sound settings" severity failure;
        assert selected_tone = 1 and selected_effect = 2
            report "UI sound did not resume after remote release" severity failure;

        playback_active <= '1';
        virtual_on <= "00000100";
        virtual_levels(2) <= to_unsigned(512, 10);
        playback_tone <= 2;
        playback_effect <= 3;
        wait for 10 ns;
        assert effective_on = "00000100"
            report "Playback did not replace live input" severity failure;
        assert selected_tone = 2 and selected_effect = 3
            report "Playback sound selection missing" severity failure;

        report "tb_performance_mixer passed" severity note;
        stop;
        wait;
    end process;
end architecture;
