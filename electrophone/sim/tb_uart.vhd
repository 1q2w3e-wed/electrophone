library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_uart is
end entity;

architecture sim of tb_uart is
    constant CLK_HZ    : positive := 50_000_000;
    constant BAUD_RATE : positive := 115_200;
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal tx_data : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_valid : std_logic := '0';
    signal tx_ready : std_logic;
    signal serial_line : std_logic;
    signal rx_data : std_logic_vector(7 downto 0);
    signal rx_valid : std_logic;
    signal valid_count : natural := 0;
begin
    clk <= not clk after CLK_PERIOD/2;

    transmitter: entity work.uart_tx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            data_in => tx_data,
            data_valid => tx_valid,
            ready => tx_ready,
            tx => serial_line
        );

    receiver: entity work.uart_rx
        generic map (
            G_CLK_HZ => CLK_HZ,
            G_BAUD_RATE => BAUD_RATE
        )
        port map (
            clk => clk, rst_n => rst_n,
            rx => serial_line,
            data_o => rx_data,
            valid_o => rx_valid
        );

    stimulus: process
        procedure send_and_check(constant value : std_logic_vector(7 downto 0)) is
        begin
            if tx_ready = '0' then
                wait until tx_ready = '1';
            end if;
            wait until falling_edge(clk);
            assert tx_ready = '1' report "UART transmitter not ready" severity failure;
            tx_data <= value;
            tx_valid <= '1';
            wait until falling_edge(clk);
            tx_valid <= '0';
            wait until rx_valid = '1' for 200 us;
            assert rx_valid = '1' report "UART byte timed out" severity failure;
            assert rx_data = value
                report "UART loopback mismatch: received " &
                       integer'image(to_integer(unsigned(rx_data)))
                severity failure;
            valid_count <= valid_count + 1;
            wait until falling_edge(clk);
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        send_and_check(x"00");
        send_and_check(x"55");
        send_and_check(x"AA");
        send_and_check(x"FF");

        wait for 200 us;
        assert valid_count = 4
            report "UART emitted duplicate or missing byte-valid pulses"
            severity failure;
        report "tb_uart passed" severity note;
        stop;
        wait;
    end process;

    timeout: process
    begin
        wait for 8 ms;
        assert false report "UART test timeout" severity failure;
        wait;
    end process;
end architecture;
