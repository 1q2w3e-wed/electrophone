library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_event_uploader is
end entity;

architecture sim of tb_event_uploader is
    constant CLK_PERIOD : time := 20 ns;
    type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal start : std_logic := '0';
    signal event_count : natural range 0 to 1024 := 2;
    signal read_index : natural range 0 to 1023;
    signal read_data : std_logic_vector(31 downto 0);
    signal tx_ready : std_logic := '1';
    signal tx_data : std_logic_vector(7 downto 0);
    signal tx_valid : std_logic;
    signal busy : std_logic;
    signal stream_valid : std_logic;
    signal response_count : natural := 0;
    signal max_read_index : natural range 0 to 1023 := 0;
    signal clear_counts : std_logic := '0';
    signal response : byte_array_t(0 to 127) := (others => (others => '0'));
begin
    clk <= not clk after CLK_PERIOD/2;
    read_data <= std_logic_vector(to_unsigned(read_index, 32));
    stream_valid <= tx_valid when busy = '1' else '0';

    dut: entity work.event_uploader
        generic map (G_EVENT_CAPACITY => 1024)
        port map (
            clk => clk, rst_n => rst_n,
            start => start,
            event_count => event_count,
            read_index => read_index,
            read_data => read_data,
            tx_ready => tx_ready,
            tx_data => tx_data,
            tx_valid => tx_valid,
            busy => busy
        );

    monitor: process(clk)
    begin
        if rising_edge(clk) then
            if clear_counts = '1' then
                response_count <= 0;
                max_read_index <= 0;
                tx_ready <= '1';
            else
                if stream_valid = '1' then
                    tx_ready <= '0';
                else
                    tx_ready <= '1';
                end if;
                if stream_valid = '1' and tx_ready = '1' then
                    if response_count < response'length then
                        response(response_count) <= tx_data;
                    end if;
                    response_count <= response_count + 1;
                end if;
                if read_index > max_read_index then
                    max_read_index <= read_index;
                end if;
            end if;
        end if;
    end process;

    stimulus: process
        procedure run_dump is
        begin
            wait until falling_edge(clk);
            start <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            start <= '0';
            wait for 1 ns;
            assert busy = '1' report "Event uploader did not start" severity failure;
            wait until busy = '0' for 5 ms;
            assert busy = '0' report "Event uploader did not finish" severity failure;
            wait for 2*CLK_PERIOD;
        end procedure;

        constant EXPECTED : byte_array_t(0 to 11) := (
            x"A5", x"5A", x"00", x"02",
            x"00", x"00", x"00", x"00",
            x"00", x"00", x"00", x"01"
        );
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        run_dump;
        assert response_count = EXPECTED'length
            report "Unexpected binary dump length: " &
                   integer'image(response_count)
            severity failure;
        for index in EXPECTED'range loop
            assert response(index) = EXPECTED(index)
                report "Unexpected binary dump byte at position " &
                       integer'image(index)
                severity failure;
        end loop;

        wait until falling_edge(clk);
        clear_counts <= '1';
        wait until rising_edge(clk);
        wait until falling_edge(clk);
        clear_counts <= '0';
        wait until rising_edge(clk);
        event_count <= 1024;
        run_dump;
        assert response_count = 4 + 1024*4
            report "Full binary dump length is incorrect" severity failure;
        assert max_read_index = 1023
            report "Full dump did not read the final event"
            severity failure;

        report "tb_event_uploader passed" severity note;
        stop;
        wait;
    end process;
end architecture;
