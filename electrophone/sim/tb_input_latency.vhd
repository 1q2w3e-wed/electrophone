library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Measures a complete pressure-input path: MCP3008-like samples, the
-- scanner/debounce stage, and the first non-zero mixed-audio sample.
entity tb_input_latency is
end entity;

architecture sim of tb_input_latency is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal spi_clk, spi_din, spi_cs_n : std_logic;
    signal spi_dout : std_logic := '0';
    signal sensor_levels : sensor_array_t;
    signal sensor_on : std_logic_vector(7 downto 0);
    signal sample_tick : std_logic := '0';
    signal pedal_mode : std_logic := '0';
    signal settings : settings_t := (0,100,0,0,100,0,0,0,0,FX_DRY);
    signal mixed_sample : signed(15 downto 0);
    signal voices_idle : std_logic;
    signal active_count : voice_count_t;
    signal note_active : std_logic_vector(7 downto 0);
    signal pressed : std_logic := '0';
    signal transaction_count : natural := 0;
    signal finished : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD/2;

    scanner: entity work.sensor_scanner
        port map (
            clk => clk, rst_n => rst_n,
            spi_clk => spi_clk, spi_din => spi_din,
            spi_dout => spi_dout, spi_cs_n => spi_cs_n,
            sensor_levels_o => sensor_levels,
            sensor_on_o => sensor_on
        );

    synth: entity work.synth_engine
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            settings => settings,
            sensor_on => sensor_on,
            sensor_levels => sensor_levels,
            pedal_mode => pedal_mode,
            octave_shift => '0',
            test_mode => '0',
            mixed_sample => mixed_sample,
            voices_idle_o => voices_idle,
            active_count_o => active_count,
            note_active_o => note_active,
            debug_increment_o => open,
            debug_glide_remaining_o => open
        );

    sample_rate_divider: process(clk)
        variable count : natural range 0 to 1023 := 0;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                count := 0;
                sample_tick <= '0';
            elsif count = 1023 then
                count := 0;
                sample_tick <= '1';
            else
                count := count + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    -- CH0 is idle until the test presses it. A full-scale sample on every
    -- CH0 conversion drives the scanner through its real four-sample debounce.
    adc_model: process
        variable stream : std_logic_vector(15 downto 0);
        variable adc_value : natural;
    begin
        wait until falling_edge(spi_cs_n);
        if transaction_count mod 8 = 0 and pressed = '1' then
            adc_value := 900;
        else
            adc_value := 0;
        end if;

        stream := "000000" & std_logic_vector(to_unsigned(adc_value, 10));
        spi_dout <= stream(15);
        for bit_index in 0 to 15 loop
            wait until rising_edge(spi_clk);
            if bit_index < 15 then
                wait until falling_edge(spi_clk);
                spi_dout <= stream(14-bit_index);
            end if;
        end loop;
        spi_dout <= '0';
        wait until rising_edge(spi_cs_n);
        transaction_count <= transaction_count + 1;
    end process;

    stimulus: process
        variable press_time : time;
        variable trigger_time : time;
        variable audio_time : time;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';

        -- Press immediately after the first CH0 conversion. This is the
        -- worst phase because CH0 will not be sampled again for a full sweep.
        wait until rising_edge(spi_cs_n);
        press_time := now;
        pressed <= '1';

        wait until sensor_on(0) = '1';
        trigger_time := now;
        wait until mixed_sample /= 0;
        audio_time := now;

        report "Pressure to trigger: " & time'image(trigger_time - press_time)
            severity note;
        report "Pressure to audio: " & time'image(audio_time - press_time)
            severity note;

        assert trigger_time - press_time <= 5 ms
            report "Pressure-to-trigger latency exceeds 5 ms"
            severity failure;
        assert audio_time - press_time <= 5 ms
            report "Pressure-to-audio latency exceeds 5 ms"
            severity failure;

        report "tb_input_latency passed" severity note;
        finished <= '1';
        wait;
    end process;

    timeout: process
    begin
        wait for 30 ms;
        assert finished = '1'
            report "Input latency test timed out"
            severity failure;
        wait;
    end process;
end architecture;
