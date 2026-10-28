library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;
use std.env.all;

entity tb_score_recorder is
end entity;

architecture sim of tb_score_recorder is
    constant CLK_PERIOD : time := 20 ns;
    constant CAPACITY : positive := 1024;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal ms_tick : std_logic := '0';
    signal start, stop_recording : std_logic := '0';
    signal input_on : std_logic_vector(7 downto 0) := (others => '0');
    signal input_levels : sensor_array_t := (others => (others => '0'));
    signal input_tones : tone_array_t := (others => 0);
    signal input_effects : effect_array_t := (others => 0);
    signal full : std_logic;
    signal append_en, update_en : std_logic;
    signal append_data : std_logic_vector(31 downto 0);
    signal update_index : natural range 0 to CAPACITY-1;
    signal update_duration : std_logic_vector(7 downto 0);
    signal update_velocity : std_logic_vector(4 downto 0);
    signal recording : std_logic;
    signal clear : std_logic := '0';
    signal event_count : natural range 0 to CAPACITY;
    signal read_index : natural range 0 to CAPACITY-1 := 0;
    signal read_data : std_logic_vector(31 downto 0);
begin
    clk <= not clk after CLK_PERIOD/2;

    events: entity work.score_event_ram
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            clear => clear,
            append_en => append_en,
            append_data => append_data,
            update_en => update_en,
            update_index => update_index,
            update_duration => update_duration,
            update_velocity => update_velocity,
            read_index => read_index,
            read_data => read_data,
            event_count => event_count,
            full => full
        );

    dut: entity work.score_recorder
        generic map (G_EVENT_CAPACITY => CAPACITY)
        port map (
            clk => clk, rst_n => rst_n,
            ms_tick => ms_tick,
            start => start,
            stop => stop_recording,
            input_on => input_on,
            input_levels => input_levels,
            input_tones => input_tones,
            input_effects => input_effects,
            full => full,
            append_en => append_en,
            append_data => append_data,
            update_en => update_en,
            update_index => update_index,
            update_duration => update_duration,
            update_velocity => update_velocity,
            recording => recording
        );

    stimulus: process
        procedure pulse_ms(constant count : natural) is
        begin
            for tick in 1 to count loop
                wait until falling_edge(clk);
                ms_tick <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                ms_tick <= '0';
                for cycle in 1 to 4 loop
                    wait until rising_edge(clk);
                end loop;
            end loop;
        end procedure;

        procedure read_event(
            constant index : natural;
            variable value : out std_logic_vector(31 downto 0)
        ) is
        begin
            wait until falling_edge(clk);
            read_index <= index;
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            value := read_data;
        end procedure;

        variable first_event, second_event : std_logic_vector(31 downto 0);
        variable duration_units : natural;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        clear <= '0';

        input_tones(0) <= 2;
        input_effects(0) <= 1;
        start <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        start <= '0';
        assert recording = '1' report "REC START did not arm recorder" severity failure;

        input_levels(0) <= to_unsigned(64, 10);
        input_on(0) <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        pulse_ms(10);
        input_levels(0) <= to_unsigned(640, 10);
        pulse_ms(20);
        input_on(0) <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);

        pulse_ms(20);
        input_tones(1) <= 3;
        input_effects(1) <= 2;
        input_levels(1) <= to_unsigned(992, 10);
        input_on(1) <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        pulse_ms(60);
        input_on(1) <= '0';
        wait until rising_edge(clk);
        wait until falling_edge(clk);

        stop_recording <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        stop_recording <= '0';
        assert recording = '0' report "REC STOP left recorder armed" severity failure;
        assert event_count = 2 report "Recorder did not create two events" severity failure;

        read_event(0, first_event);
        assert first_event(31 downto 20) = std_logic_vector(to_unsigned(0, 12))
            report "First recorded delta was not zero" severity failure;
        assert to_integer(unsigned(first_event(19 downto 12))) = 3
            report "First recorded duration was not 30 ms" severity failure;
        assert first_event(11 downto 9) = std_logic_vector(to_unsigned(0, 3))
            report "Recorder did not capture performance note 0" severity failure;
        assert first_event(8 downto 4) = std_logic_vector(to_unsigned(20, 5))
            report "Recorder did not capture pressure velocity" severity failure;
        assert first_event(3 downto 2) = "10"
            report "Recorder did not capture timbre" severity failure;
        assert first_event(1 downto 0) = "01"
            report "Recorder did not capture effect" severity failure;

        read_event(1, second_event);
        duration_units := to_integer(unsigned(second_event(19 downto 12)));
        assert second_event(31 downto 20) = std_logic_vector(to_unsigned(50, 12))
            report "Second recorded delta was not 50 ms from the prior note-on: " &
                   integer'image(to_integer(unsigned(second_event(31 downto 20))))
            severity failure;
        assert second_event(11 downto 9) = std_logic_vector(to_unsigned(1, 3))
            report "Second performance note was not recorded" severity failure;
        assert second_event(8 downto 4) = std_logic_vector(to_unsigned(31, 5))
            report "Second velocity was not saturated to 31" severity failure;
        assert second_event(3 downto 2) = "11"
            report "Second timbre was not captured" severity failure;
        assert second_event(1 downto 0) = "10"
            report "Second effect was not captured" severity failure;
        assert duration_units = 6
            report "Second recorded duration was not 60 ms, got " &
                   integer'image(duration_units)
            severity failure;

        report "tb_score_recorder passed" severity note;
        stop;
        wait;
    end process;
end architecture;
