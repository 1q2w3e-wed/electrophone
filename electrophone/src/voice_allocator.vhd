library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Allocates 32 voices using bit masks and one allocation event per clock.
entity voice_allocator is
    port (
        clk, rst_n : in std_logic;
        sensor_on : in std_logic_vector(7 downto 0);
        sensor_levels : in sensor_array_t;
        pedal_mode : in std_logic;
        selected_tone : in tone_index_t;
        voice_done : in std_logic_vector(POLYPHONY-1 downto 0);
        meta_read_address : in voice_index_t;
        voice_meta_o : out std_logic_vector(14 downto 0);
        voice_held_o : out std_logic_vector(POLYPHONY-1 downto 0);
        voice_trigger_o : out std_logic_vector(POLYPHONY-1 downto 0);
        note_active_o : out std_logic_vector(7 downto 0);
        active_count_o : out voice_count_t
    );
end entity;

architecture rtl of voice_allocator is
    type note_mask_array_t is array (0 to 7) of
        std_logic_vector(POLYPHONY-1 downto 0);
    type note_array_t is array (voice_index_t) of note_index_t;
    type tone_array_t is array (voice_index_t) of tone_index_t;
    type meta_level_array_t is array (voice_index_t) of sensor_level_t;
    type age_array_t is array (voice_index_t) of unsigned(15 downto 0);
    type note_count_array_t is array (0 to 7) of natural range 0 to POLYPHONY;

    signal active_mask : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal held_mask : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal latched_mask : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal releasing_mask : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal note_held_mask : note_mask_array_t :=
        (others => (others => '0'));
    signal voice_note : note_array_t := (others => 0);
    signal voice_tone : tone_array_t := (others => 0);
    signal voice_level : meta_level_array_t :=
        (others => (others => '0'));
    signal voice_age : age_array_t := (others => (others => '0'));
    signal next_age_reg : unsigned(15 downto 0) := (others => '0');
    signal sensor_prev : std_logic_vector(7 downto 0) := (others => '0');
    signal pending_on : std_logic_vector(7 downto 0) := (others => '0');
    signal trigger_reg : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal active_count_reg : voice_count_t := 0;
    signal note_counts : note_count_array_t := (others => 0);
    signal pending_done : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal alloc_key : natural range 0 to 7 := 0;
    signal alloc_age : unsigned(15 downto 0) := (others => '0');
    signal alloc_slot : voice_index_t := 0;
    signal alloc_slot_free : std_logic := '0';
    signal allocator_state : natural range 0 to 2 := 0;
    signal scan_index : voice_index_t := 0;
    signal scan_free_found : std_logic := '0';
    signal scan_free_slot : voice_index_t := 0;
    signal scan_oldest_slot : voice_index_t := 0;
    signal scan_oldest_age : unsigned(15 downto 0) := (others => '0');

    function first_voice(mask : std_logic_vector(POLYPHONY-1 downto 0))
        return voice_index_t is
        variable result : voice_index_t := 0;
    begin
        for voice in voice_index_t loop
            if mask(voice) = '1' then
                return voice;
            end if;
        end loop;
        return result;
    end function;

    function first_key(mask : std_logic_vector(7 downto 0)) return natural is
    begin
        for key in 0 to 7 loop
            if mask(key) = '1' then
                return key;
            end if;
        end loop;
        return 0;
    end function;
begin
    voice_held_o <= held_mask or latched_mask;
    voice_trigger_o <= trigger_reg;
    note_markers: for key in 0 to 7 generate
        note_active_o(key) <= '1' when note_counts(key) /= 0 else '0';
    end generate;
    active_count_o <= active_count_reg;

    meta_output: process(meta_read_address, held_mask, active_mask,
                         voice_note, voice_tone, voice_level, sensor_levels)
        variable level_v : sensor_level_t;
    begin
        if active_mask(meta_read_address) = '0' then
            level_v := (others => '0');
        elsif held_mask(meta_read_address) = '1' then
            level_v := sensor_levels(voice_note(meta_read_address));
        else
            level_v := voice_level(meta_read_address);
        end if;
        voice_meta_o <= std_logic_vector(level_v) &
                        std_logic_vector(to_unsigned(
                            voice_tone(meta_read_address), 2)) &
                        std_logic_vector(to_unsigned(
                            voice_note(meta_read_address), 3));
    end process;

    allocate: process(clk)
        variable active_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable held_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable latched_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable releasing_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable note_held_v : note_mask_array_t;
        variable note_v : note_array_t;
        variable tone_v : tone_array_t;
        variable level_v : meta_level_array_t;
        variable age_v : age_array_t;
        variable note_mask_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable pending_v : std_logic_vector(7 downto 0);
        variable trigger_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable done_v : std_logic_vector(POLYPHONY-1 downto 0);
        variable slot_v : voice_index_t;
        variable key_v : natural;
        variable count_v : voice_count_t;
        variable distance_v : unsigned(15 downto 0);
        variable free_found_v : std_logic;
        variable free_slot_v : voice_index_t;
        variable oldest_slot_v : voice_index_t;
        variable oldest_age_v : unsigned(15 downto 0);
        variable note_counts_v : note_count_array_t;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                active_mask <= (others => '0');
                held_mask <= (others => '0');
                latched_mask <= (others => '0');
                releasing_mask <= (others => '0');
                note_held_mask <= (others => (others => '0'));
                voice_note <= (others => 0);
                voice_tone <= (others => 0);
                voice_level <= (others => (others => '0'));
                voice_age <= (others => (others => '0'));
                next_age_reg <= (others => '0');
                sensor_prev <= (others => '0');
                pending_on <= (others => '0');
                trigger_reg <= (others => '0');
                active_count_reg <= 0;
                note_counts <= (others => 0);
                pending_done <= (others => '0');
                alloc_key <= 0;
                alloc_age <= (others => '0');
                alloc_slot <= 0;
                alloc_slot_free <= '0';
                allocator_state <= 0;
                scan_index <= 0;
                scan_free_found <= '0';
                scan_free_slot <= 0;
                scan_oldest_slot <= 0;
                scan_oldest_age <= (others => '0');
            else
                trigger_reg <= (others => '0');
                pending_done <= pending_done or voice_done;
                sensor_prev <= sensor_on;
                pending_on <= pending_on or
                              (sensor_on and not sensor_prev);
                pending_v := pending_on or
                             (sensor_on and not sensor_prev);

                case allocator_state is
                    when 0 =>
                        active_v := active_mask;
                        held_v := held_mask;
                        latched_v := latched_mask;
                        releasing_v := releasing_mask;
                        note_held_v := note_held_mask;
                        note_v := voice_note;
                        tone_v := voice_tone;
                        level_v := voice_level;
                        age_v := voice_age;
                        count_v := active_count_reg;
                        note_counts_v := note_counts;

                        done_v := pending_done and releasing_v;
                        if done_v /= (done_v'range => '0') then
                            slot_v := first_voice(done_v);
                            active_v(slot_v) := '0';
                            releasing_v(slot_v) := '0';
                            pending_done(slot_v) <= '0';
                            note_counts_v(note_v(slot_v)) :=
                                note_counts_v(note_v(slot_v)) - 1;
                            count_v := count_v - 1;
                        end if;

                        if pedal_mode = '0' then
                            releasing_v := releasing_v or latched_v;
                            latched_v := (others => '0');
                        end if;

                        for key in 0 to 7 loop
                            if sensor_prev(key) = '1' and
                               sensor_on(key) = '0' then
                                note_mask_v := note_held_v(key);
                                held_v := held_v and not note_mask_v;
                                note_held_v(key) := (others => '0');
                                if pedal_mode = '1' then
                                    latched_v := latched_v or note_mask_v;
                                else
                                    releasing_v := releasing_v or note_mask_v;
                                end if;
                            end if;
                        end loop;

                        if pending_v /= "00000000" then
                            key_v := first_key(pending_v);
                            pending_v(key_v) := '0';
                            alloc_key <= key_v;
                            alloc_age <= next_age_reg + 1;
                            next_age_reg <= next_age_reg + 1;
                            scan_index <= 0;
                            scan_free_found <= '0';
                            scan_oldest_age <= (others => '0');
                            allocator_state <= 1;
                        end if;

                        active_mask <= active_v;
                        held_mask <= held_v;
                        latched_mask <= latched_v;
                        releasing_mask <= releasing_v;
                        note_held_mask <= note_held_v;
                        voice_note <= note_v;
                        voice_tone <= tone_v;
                        voice_level <= level_v;
                        voice_age <= age_v;
                        note_counts <= note_counts_v;
                        active_count_reg <= count_v;
                        pending_on <= pending_v;
                    when 1 =>
                        free_found_v := scan_free_found;
                        free_slot_v := scan_free_slot;
                        oldest_slot_v := scan_oldest_slot;
                        oldest_age_v := scan_oldest_age;

                        if active_mask(scan_index) = '0' and
                           free_found_v = '0' then
                            free_found_v := '1';
                            free_slot_v := scan_index;
                        end if;
                        if active_mask(scan_index) = '1' then
                            distance_v := alloc_age - voice_age(scan_index);
                            if distance_v > oldest_age_v then
                                oldest_age_v := distance_v;
                                oldest_slot_v := scan_index;
                            end if;
                        end if;

                        if scan_index = POLYPHONY-1 then
                            if free_found_v = '1' then
                                alloc_slot <= free_slot_v;
                                alloc_slot_free <= '1';
                            else
                                alloc_slot <= oldest_slot_v;
                                alloc_slot_free <= '0';
                            end if;
                            allocator_state <= 2;
                        else
                            scan_index <= scan_index + 1;
                            scan_free_found <= free_found_v;
                            scan_free_slot <= free_slot_v;
                            scan_oldest_slot <= oldest_slot_v;
                            scan_oldest_age <= oldest_age_v;
                        end if;
                    when others =>
                        active_v := active_mask;
                        held_v := held_mask;
                        latched_v := latched_mask;
                        releasing_v := releasing_mask;
                        note_held_v := note_held_mask;
                        note_v := voice_note;
                        tone_v := voice_tone;
                        level_v := voice_level;
                        age_v := voice_age;
                        count_v := active_count_reg;
                        note_counts_v := note_counts;

                        slot_v := alloc_slot;
                        if alloc_slot_free = '0' then
                            note_mask_v := note_held_v(note_v(slot_v));
                            note_mask_v(slot_v) := '0';
                            note_held_v(note_v(slot_v)) := note_mask_v;
                            held_v(slot_v) := '0';
                            latched_v(slot_v) := '0';
                            releasing_v(slot_v) := '0';
                            note_counts_v(note_v(slot_v)) :=
                                note_counts_v(note_v(slot_v)) - 1;
                        else
                            count_v := count_v + 1;
                        end if;
                        active_v(slot_v) := '1';
                        held_v(slot_v) := '1';
                        note_held_v(alloc_key)(slot_v) := '1';
                        note_v(slot_v) := alloc_key;
                        tone_v(slot_v) := selected_tone;
                        level_v(slot_v) := sensor_levels(alloc_key);
                        age_v(slot_v) := alloc_age;
                        note_counts_v(alloc_key) :=
                            note_counts_v(alloc_key) + 1;
                        trigger_v(slot_v) := '1';
                        trigger_reg <= trigger_v;
                        active_mask <= active_v;
                        held_mask <= held_v;
                        latched_mask <= latched_v;
                        releasing_mask <= releasing_v;
                        note_held_mask <= note_held_v;
                        voice_note <= note_v;
                        voice_tone <= tone_v;
                        voice_level <= level_v;
                        voice_age <= age_v;
                        note_counts <= note_counts_v;
                        active_count_reg <= count_v;
                        allocator_state <= 0;
                end case;
            end if;
        end if;
    end process;
end architecture;
