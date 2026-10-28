library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_score_event_ram is
end entity;

architecture sim of tb_score_event_ram is
    constant CLK_PERIOD : time := 20 ns;
    constant CAPACITY : positive := 1024;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal clear : std_logic := '0';
    signal append_en : std_logic := '0';
    signal append_data : std_logic_vector(31 downto 0) := (others => '0');
    signal update_en : std_logic := '0';
    signal update_index : natural range 0 to CAPACITY-1 := 0;
    signal update_duration : std_logic_vector(7 downto 0) := (others => '0');
    signal update_velocity : std_logic_vector(4 downto 0) := (others => '0');
    signal read_index : natural range 0 to CAPACITY-1 := 0;
    signal read_data : std_logic_vector(31 downto 0);
    signal event_count : natural range 0 to CAPACITY;
    signal full : std_logic;

    function pack_event(
        constant delta_ms, duration_units, note, velocity, tone, effect
        : natural
    ) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(delta_ms, 12)) &
               std_logic_vector(to_unsigned(duration_units, 8)) &
               std_logic_vector(to_unsigned(note, 3)) &
               std_logic_vector(to_unsigned(velocity, 5)) &
               std_logic_vector(to_unsigned(tone, 2)) &
               std_logic_vector(to_unsigned(effect, 2));
    end function;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.score_event_ram
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

    stimulus: process
        variable expected : std_logic_vector(31 downto 0);
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);
        clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        clear <= '0';
        assert event_count = 0 report "Clear did not empty event RAM" severity failure;
        assert full = '0' report "Empty event RAM reported full" severity failure;

        for index in 0 to CAPACITY-1 loop
            wait until falling_edge(clk);
            append_data <= pack_event(
                index mod 4096,
                (index mod 255) + 1,
                index mod 8,
                index mod 32,
                index mod 4,
                (index / 4) mod 4);
            append_en <= '1';
            wait until rising_edge(clk);
        end loop;
        wait until falling_edge(clk);
        append_en <= '0';
        assert event_count = CAPACITY
            report "Event RAM count did not reach capacity: " &
                   integer'image(event_count)
            severity failure;
        assert full = '1' report "Full event RAM did not report full" severity failure;

        append_data <= x"FFFFFFFF";
        append_en <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        append_en <= '0';
        assert event_count = CAPACITY
            report "Overflow append changed event count"
            severity failure;

        read_index <= 0;
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        expected := pack_event(0, 1, 0, 0, 0, 0);
        assert read_data = expected
            report "First packed event changed after overflow"
            severity failure;

        read_index <= CAPACITY-1;
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        expected := pack_event(
            (CAPACITY-1) mod 4096,
            (CAPACITY-1) mod 255 + 1,
            (CAPACITY-1) mod 8,
            (CAPACITY-1) mod 32,
            (CAPACITY-1) mod 4,
            ((CAPACITY-1) / 4) mod 4);
        assert read_data = expected
            report "Last packed event did not round-trip"
            severity failure;

        update_index <= 0;
        update_duration <= std_logic_vector(to_unsigned(250, 8));
        update_velocity <= std_logic_vector(to_unsigned(25, 5));
        update_en <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        update_en <= '0';
        read_index <= 0;
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        expected := pack_event(0, 1, 0, 0, 0, 0);
        expected(19 downto 12) := std_logic_vector(to_unsigned(250, 8));
        expected(8 downto 4) := std_logic_vector(to_unsigned(25, 5));
        assert read_data = expected
            report "Duration update mismatch: delta=" &
                   integer'image(to_integer(unsigned(read_data(31 downto 20)))) &
                   " duration=" &
                   integer'image(to_integer(unsigned(read_data(19 downto 12)))) &
                   " note=" &
                   integer'image(to_integer(unsigned(read_data(11 downto 9))))
            severity failure;

        clear <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        clear <= '0';
        assert event_count = 0 and full = '0'
            report "Second clear did not reset event RAM"
            severity failure;

        report "tb_score_event_ram passed" severity note;
        stop;
        wait;
    end process;
end architecture;
