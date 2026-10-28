library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Captures merged physical/remote performance as packed note-on/off events.
entity score_recorder is
    generic (
        G_EVENT_CAPACITY : positive := 1024
    );
    port (
        clk, rst_n : in std_logic;
        ms_tick : in std_logic;
        start : in std_logic;
        stop : in std_logic;
        input_on : in std_logic_vector(7 downto 0);
        input_levels : in sensor_array_t;
        input_tones : in tone_array_t;
        input_effects : in effect_array_t;
        full : in std_logic;

        append_en : out std_logic;
        append_data : out std_logic_vector(31 downto 0);
        update_en : out std_logic;
        update_index : out natural range 0 to G_EVENT_CAPACITY-1;
        update_duration : out std_logic_vector(7 downto 0);
        update_velocity : out std_logic_vector(4 downto 0);
        recording : out std_logic
    );
end entity;

architecture rtl of score_recorder is
    type held_array_t is array (0 to 7) of natural range 0 to 2550;
    type index_array_t is array (0 to 7) of
        natural range 0 to G_EVENT_CAPACITY-1;

    signal recording_reg : std_logic := '0';
    signal input_prev : std_logic_vector(7 downto 0) := (others => '0');
    signal pending_on : std_logic_vector(7 downto 0) := (others => '0');
    signal finish_pending : std_logic_vector(7 downto 0) := (others => '0');
    signal held_ms : held_array_t := (others => 0);
    signal peak_levels : sensor_array_t := (others => (others => '0'));
    signal open_index : index_array_t := (others => 0);
    signal gap_ms : natural range 0 to 4095 := 0;
    signal next_index : natural range 0 to G_EVENT_CAPACITY := 0;
begin
    recording <= recording_reg;

    process(clk)
        variable pending_v : std_logic_vector(7 downto 0);
        variable chosen_v : natural range 0 to 7;
        variable duration_units_v : natural range 1 to 255;
        variable found_v : boolean;
    begin
        if rising_edge(clk) then
            append_en <= '0';
            update_en <= '0';

            if rst_n = '0' then
                recording_reg <= '0';
                input_prev <= (others => '0');
                pending_on <= (others => '0');
                finish_pending <= (others => '0');
                held_ms <= (others => 0);
                peak_levels <= (others => (others => '0'));
                open_index <= (others => 0);
                gap_ms <= 0;
                next_index <= 0;
                append_data <= (others => '0');
                update_index <= 0;
                update_duration <= (others => '0');
                update_velocity <= (others => '0');
            elsif stop = '1' then
                recording_reg <= '0';
                pending_on <= (others => '0');
                finish_pending <= input_on;
            elsif start = '1' then
                recording_reg <= '1';
                input_prev <= input_on;
                pending_on <= (others => '0');
                finish_pending <= (others => '0');
                held_ms <= (others => 0);
                peak_levels <= (others => (others => '0'));
                open_index <= (others => 0);
                gap_ms <= 0;
                next_index <= 0;
            elsif finish_pending /= "00000000" then
                found_v := false;
                chosen_v := 0;
                for key in 0 to 7 loop
                    if finish_pending(key) = '1' and not found_v then
                        chosen_v := key;
                        found_v := true;
                    end if;
                end loop;
                if found_v then
                    if held_ms(chosen_v) = 0 then
                        duration_units_v := 1;
                    elsif held_ms(chosen_v) >= 2550 then
                        duration_units_v := 255;
                    else
                        duration_units_v := held_ms(chosen_v) / 10;
                        if duration_units_v = 0 then
                            duration_units_v := 1;
                        end if;
                    end if;
                    update_en <= '1';
                    update_index <= open_index(chosen_v);
                    update_duration <= std_logic_vector(to_unsigned(
                        duration_units_v, 8));
                    update_velocity <= std_logic_vector(
                        peak_levels(chosen_v)(9 downto 5));
                    finish_pending(chosen_v) <= '0';
                end if;
            elsif recording_reg = '1' then
                pending_v := pending_on or
                             (input_on and not input_prev);
                pending_on <= pending_v;

                if ms_tick = '1' then
                    if gap_ms < 4095 then
                        gap_ms <= gap_ms + 1;
                    end if;
                    for key in 0 to 7 loop
                        if input_on(key) = '1' and held_ms(key) < 2550 then
                            held_ms(key) <= held_ms(key) + 1;
                        end if;
                        if input_on(key) = '1' and
                           input_levels(key) > peak_levels(key) then
                            peak_levels(key) <= input_levels(key);
                        end if;
                    end loop;
                end if;

                if pending_v /= "00000000" then
                    found_v := false;
                    chosen_v := 0;
                    for key in 0 to 7 loop
                        if pending_v(key) = '1' and not found_v then
                            chosen_v := key;
                            found_v := true;
                        end if;
                    end loop;
                    pending_on(chosen_v) <= '0';

                    if full = '0' then
                        append_en <= '1';
                        append_data <= std_logic_vector(to_unsigned(gap_ms, 12)) &
                                       std_logic_vector(to_unsigned(1, 8)) &
                                       std_logic_vector(to_unsigned(
                                           chosen_v, 3)) &
                                       std_logic_vector(
                                           input_levels(chosen_v)(9 downto 5)) &
                                       std_logic_vector(to_unsigned(
                                           input_tones(chosen_v), 2)) &
                                       std_logic_vector(to_unsigned(
                                           input_effects(chosen_v), 2));
                        open_index(chosen_v) <= next_index;
                        if next_index < G_EVENT_CAPACITY then
                            next_index <= next_index + 1;
                        end if;
                    end if;
                    gap_ms <= 0;
                    held_ms(chosen_v) <= 0;
                    peak_levels(chosen_v) <= input_levels(chosen_v);
                    input_prev <= input_on;
                else
                    for key in 0 to 7 loop
                        if input_on(key) = '0' and input_prev(key) = '1' then
                            if held_ms(key) = 0 then
                                duration_units_v := 1;
                            elsif held_ms(key) >= 2550 then
                                duration_units_v := 255;
                            else
                                duration_units_v := held_ms(key) / 10;
                                if duration_units_v = 0 then
                                    duration_units_v := 1;
                                end if;
                            end if;
                            update_en <= '1';
                            update_index <= open_index(key);
                            update_duration <= std_logic_vector(to_unsigned(
                                duration_units_v, 8));
                            update_velocity <= std_logic_vector(
                                peak_levels(key)(9 downto 5));
                        end if;
                    end loop;
                    input_prev <= input_on;
                end if;
            end if;
        end if;
    end process;
end architecture;
