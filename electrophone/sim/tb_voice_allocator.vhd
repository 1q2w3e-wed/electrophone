library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_voice_allocator is
end entity;

architecture sim of tb_voice_allocator is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sensor_on : std_logic_vector(7 downto 0) := (others => '0');
    signal sensor_levels : sensor_array_t := (others => (others => '0'));
    signal pedal_mode : std_logic := '0';
    signal selected_tone : tone_index_t := 0;
    signal voice_done : std_logic_vector(POLYPHONY-1 downto 0) :=
        (others => '0');
    signal meta_read_address : voice_index_t := 0;
    signal voice_meta : std_logic_vector(14 downto 0);
    signal voice_held : std_logic_vector(POLYPHONY-1 downto 0);
    signal voice_trigger : std_logic_vector(POLYPHONY-1 downto 0);
    signal note_active : std_logic_vector(7 downto 0);
    signal active_count : voice_count_t;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.voice_allocator
        port map (
            clk => clk, rst_n => rst_n,
            sensor_on => sensor_on,
            sensor_levels => sensor_levels,
            pedal_mode => pedal_mode,
            selected_tone => selected_tone,
            voice_done => voice_done,
            meta_read_address => meta_read_address,
            voice_meta_o => voice_meta,
            voice_held_o => voice_held,
            voice_trigger_o => voice_trigger,
            note_active_o => note_active,
            active_count_o => active_count
        );

    stimulus: process
        procedure press_key(constant note : natural; constant level : natural) is
        begin
            wait until falling_edge(clk);
            sensor_on(note) <= '1';
            sensor_levels(note) <= to_unsigned(level, 10);
            for step in 1 to 35 loop
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end procedure;

        procedure release_key(constant note : natural) is
        begin
            wait until falling_edge(clk);
            sensor_on(note) <= '0';
            sensor_levels(note) <= (others => '0');
            for step in 1 to 35 loop
                wait until rising_edge(clk);
                wait until falling_edge(clk);
            end loop;
        end procedure;

        procedure finish_voice(constant index : natural) is
        begin
            wait until falling_edge(clk);
            voice_done(index) <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            voice_done(index) <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            wait until rising_edge(clk);
            wait until falling_edge(clk);
        end procedure;

    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        press_key(0, 700);
        assert active_count = 1
            report "Normal note attack did not allocate one voice"
            severity failure;
        assert voice_held(0) = '1'
            report "Allocated voice is not held"
            severity failure;
        assert note_active = "00000001"
            report "Allocated note marker is missing"
            severity failure;

        release_key(0);
        assert voice_held(0) = '0'
            report "Normal mode did not release the voice"
            severity failure;
        assert active_count = 1
            report "Release tail was removed before voice_done"
            severity failure;
        finish_voice(0);
        assert active_count = 0
            report "voice_done did not recycle the slot"
            severity failure;
        assert note_active = "00000000"
            report "Finished voice did not clear its note marker"
            severity failure;

        pedal_mode <= '1';
        selected_tone <= 1;
        press_key(0, 700);
        release_key(0);
        meta_read_address <= 0;
        wait for 1 ns;
        assert active_count = 1 and voice_held(0) = '1'
            report "Pedal mode did not retain the released voice"
            severity failure;
        assert unsigned(voice_meta(14 downto 5)) = to_unsigned(700, 10)
            report "Latched voice did not retain its pressure"
            severity failure;
        assert unsigned(voice_meta(4 downto 3)) = to_unsigned(1, 2)
            report "Latched voice did not retain its timbre"
            severity failure;

        selected_tone <= 2;
        press_key(0, 500);
        release_key(0);
        assert active_count = 2
            report "Repeated same-pitch attack did not allocate a new voice"
            severity failure;
        assert note_active = "00000001"
            report "Duplicate same-pitch voices produced duplicate markers"
            severity failure;
        meta_read_address <= 0;
        wait for 1 ns;
        assert unsigned(voice_meta(4 downto 3)) = to_unsigned(1, 2) and
               unsigned(voice_meta(14 downto 5)) = to_unsigned(700, 10)
            report "First same-note voice changed its captured metadata"
            severity failure;
        meta_read_address <= 1;
        wait for 1 ns;
        assert unsigned(voice_meta(4 downto 3)) = to_unsigned(2, 2) and
               unsigned(voice_meta(14 downto 5)) = to_unsigned(500, 10)
            report "New timbre changed an older voice or was not captured"
            severity failure;

        pedal_mode <= '0';
        wait until falling_edge(clk);
        assert active_count = 2
            report "Pedal exit removed voices before release completed"
            severity failure;
        assert voice_held(0) = '0' and voice_held(1) = '0'
            report "Pedal exit did not start releasing latched voices"
            severity failure;
        finish_voice(0);
        assert note_active = "00000001"
            report "One remaining same-pitch voice lost its marker"
            severity failure;
        finish_voice(1);
        assert active_count = 0
            report "Pedal voices were not recycled after release"
            severity failure;
        assert note_active = "00000000"
            report "Released pedal voices left a stale note marker"
            severity failure;

        pedal_mode <= '1';
        for attack in 0 to POLYPHONY-1 loop
            selected_tone <= attack mod 4;
            press_key(attack mod 8, 600 + attack);
            release_key(attack mod 8);
        end loop;
        assert active_count = POLYPHONY
            report "Thirty-two attacks did not occupy 32 voices"
            severity failure;

        selected_tone <= 3;
        press_key(1, 900);
        release_key(1);
        assert active_count = POLYPHONY
            report "33rd attack increased the voice count above 32"
            severity failure;
        meta_read_address <= 0;
        wait for 1 ns;
        assert unsigned(voice_meta(2 downto 0)) = to_unsigned(1, 3) and
               unsigned(voice_meta(4 downto 3)) = to_unsigned(3, 2)
            report "33rd attack did not steal the oldest voice"
            severity failure;

        pedal_mode <= '0';
        wait until falling_edge(clk);
        for voice in 0 to POLYPHONY-1 loop
            finish_voice(voice);
        end loop;
        assert active_count = 0
            report "Complete voice_done sweep did not empty the pool"
            severity failure;

        report "tb_voice_allocator passed" severity note;
        wait;
    end process;
end architecture;
