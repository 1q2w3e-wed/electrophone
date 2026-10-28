library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Eight phone-controlled live key gates. The app sends one key action at a
-- time, so each new voice can capture its own tone and effect.
entity remote_input is
    port (
        clk, rst_n : in std_logic;
        key_down : in std_logic;
        key_up : in std_logic;
        key_all_up : in std_logic;
        key_note : in note_index_t;
        key_velocity : in natural range 0 to 31;
        key_tone : in tone_index_t;
        key_effect : in natural range 0 to 3;
        clear : in std_logic;

        on_o : out std_logic_vector(7 downto 0);
        levels_o : out sensor_array_t;
        tones_o : out tone_array_t;
        effects_o : out effect_array_t;
        last_tone_o : out tone_index_t;
        last_effect_o : out natural range 0 to 3
    );
end entity;

architecture rtl of remote_input is
    signal on_reg : std_logic_vector(7 downto 0) := (others => '0');
    signal levels_reg : sensor_array_t := (others => (others => '0'));
    signal tones_reg : tone_array_t := (others => 0);
    signal effects_reg : effect_array_t := (others => 0);
    signal last_tone_reg : tone_index_t := 0;
    signal last_effect_reg : natural range 0 to 3 := 0;
begin
    on_o <= on_reg;
    levels_o <= levels_reg;
    tones_o <= tones_reg;
    effects_o <= effects_reg;
    last_tone_o <= last_tone_reg;
    last_effect_o <= last_effect_reg;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                on_reg <= (others => '0');
                levels_reg <= (others => (others => '0'));
                tones_reg <= (others => 0);
                effects_reg <= (others => 0);
                last_tone_reg <= 0;
                last_effect_reg <= 0;
            elsif clear = '1' or key_all_up = '1' then
                on_reg <= (others => '0');
                levels_reg <= (others => (others => '0'));
            elsif key_down = '1' then
                on_reg(key_note) <= '1';
                levels_reg(key_note) <= shift_left(
                    resize(to_unsigned(key_velocity, 5), 10), 5);
                tones_reg(key_note) <= key_tone;
                effects_reg(key_note) <= key_effect;
                last_tone_reg <= key_tone;
                last_effect_reg <= key_effect;
            elsif key_up = '1' then
                on_reg(key_note) <= '0';
                levels_reg(key_note) <= (others => '0');
            end if;
        end if;
    end process;
end architecture;
