library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_parser_uart is
end entity;

architecture sim of tb_parser_uart is
    constant CLK_HZ : positive := 50_000_000;
    constant BAUD_RATE : positive := 115_200;
    constant CLK_PERIOD : time := 20 ns;
    type byte_array_t is array (0 to 15) of std_logic_vector(7 downto 0);

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';

    signal host_tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal host_tx_valid : std_logic := '0';
    signal host_tx_ready : std_logic;
    signal host_serial : std_logic;

    signal fpga_rx_data : std_logic_vector(7 downto 0);
    signal fpga_rx_valid : std_logic;
    signal fpga_tx_data : std_logic_vector(7 downto 0);
    signal fpga_tx_valid : std_logic;
    signal fpga_tx_ready : std_logic;
    signal fpga_serial : std_logic;

    signal host_rx_data : std_logic_vector(7 downto 0);
    signal host_rx_valid : std_logic;
    signal response_bytes : byte_array_t := (others => (others => '0'));
    signal response_count : natural := 0;
begin
    clk <= not clk after CLK_PERIOD/2;

    host_transmitter: entity work.uart_tx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            data_in => host_tx_data,
            data_valid => host_tx_valid,
            ready => host_tx_ready,
            tx => host_serial
        );

    fpga_receiver: entity work.uart_rx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            rx => host_serial,
            data_o => fpga_rx_data,
            valid_o => fpga_rx_valid
        );

    parser: entity work.command_parser
        port map (
            clk => clk, rst_n => rst_n,
            rx_data => fpga_rx_data,
            rx_valid => fpga_rx_valid,
            tx_ready => fpga_tx_ready,
            tx_data => fpga_tx_data,
            tx_valid => fpga_tx_valid,
            map_write_en => open,
            map_channel => open,
            map_note => open,
            score_clear => open,
            append_en => open,
            append_data => open,
            play_score => open,
            stop_all => open,
            rec_start => open,
            rec_stop => open,
            rec_play => open,
            key_down => open,
            key_up => open,
            key_all_up => open,
            key_note => open,
            key_velocity => open,
            key_tone => open,
            key_effect => open,
            dump_start => open,
            test_on => open,
            test_off => open,
            playback_active => '0',
            recording_active => '0',
            key_state => "00000000",
            activity => open,
            event_count => 0,
            event_full => '0'
        );

    fpga_transmitter: entity work.uart_tx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            data_in => fpga_tx_data,
            data_valid => fpga_tx_valid,
            ready => fpga_tx_ready,
            tx => fpga_serial
        );

    host_receiver: entity work.uart_rx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            rx => fpga_serial,
            data_o => host_rx_data,
            valid_o => host_rx_valid
        );

    capture_response: process(clk)
    begin
        if rising_edge(clk) then
            if host_rx_valid = '1' then
                response_bytes(response_count) <= host_rx_data;
                response_count <= response_count + 1;
            end if;
        end if;
    end process;

    stimulus: process
        procedure send_byte(constant value : std_logic_vector(7 downto 0)) is
        begin
            wait until falling_edge(clk);
            assert host_tx_ready = '1'
                report "Host UART transmitter not ready"
                severity failure;
            host_tx_data <= value;
            host_tx_valid <= '1';
            wait until falling_edge(clk);
            host_tx_valid <= '0';
            wait until host_tx_ready = '1';
        end procedure;

        procedure send_text(constant text : string) is
        begin
            for index in text'range loop
                send_byte(std_logic_vector(
                    to_unsigned(character'pos(text(index)), 8)));
            end loop;
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        send_text("PING" & CR & LF);
        wait until response_count = 6 for 2 ms;
        assert response_count = 6
            report "FPGA did not return six response bytes, got " &
                   integer'image(response_count)
            severity failure;
        assert response_bytes(0) = x"50" and
               response_bytes(1) = x"4F" and
               response_bytes(2) = x"4E" and
               response_bytes(3) = x"47" and
               response_bytes(4) = x"0D" and
               response_bytes(5) = x"0A"
            report "FPGA response was not ASCII PONG"
            severity failure;

        wait for 200 us;
        assert response_count = 6
            report "FPGA returned extra bytes after PONG"
            severity failure;
        report "tb_parser_uart passed" severity note;
        stop;
        wait;
    end process;
end architecture;
