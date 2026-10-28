library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

entity tb_audio_effects is
end entity;

architecture sim of tb_audio_effects is
    constant CLK_PERIOD : time := 20 ns;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal sample_tick : std_logic := '0';
    signal sample_in : signed(15 downto 0) := (others => '0');
    signal effect_mode : effect_mode_t := FX_DRY;
    signal audio_out : signed(15 downto 0);
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.audio_effects
        port map (
            clk => clk, rst_n => rst_n,
            sample_tick => sample_tick,
            sample_in => sample_in,
            effect_mode => effect_mode,
            audio_out => audio_out
        );

    stimulus: process
        procedure process_sample(
            constant input_value : integer;
            variable output_value : out integer
        ) is
        begin
            wait until falling_edge(clk);
            sample_in <= to_signed(input_value, 16);
            sample_tick <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            sample_tick <= '0';
            for cycle in 0 to 31 loop
                wait until rising_edge(clk);
            end loop;
            output_value := to_integer(audio_out);
        end procedure;

        variable value : integer;
        variable delayed_early : integer;
        variable delayed_echo : integer;
        variable reverb_short : integer;
        variable reverb_long : integer;
    begin
        wait for 5*CLK_PERIOD;
        rst_n <= '1';
        wait until falling_edge(clk);

        effect_mode <= FX_DRY;
        process_sample(1234, value);
        assert value = 1234
            report "Dry mode changed the input sample"
            severity failure;

        effect_mode <= FX_DELAY;
        wait for 100 ns;
        process_sample(30000, value);
        for sample in 1 to 100 loop
            process_sample(0, value);
        end loop;
        delayed_early := value;
        assert abs(delayed_early) < 2000
            report "Delay produced an echo before 120 ms"
            severity failure;
        for sample in 101 to 5860 loop
            process_sample(0, value);
        end loop;
        delayed_echo := value;
        assert abs(delayed_echo) > 200
            report "Delay did not produce an echo near 120 ms"
            severity failure;

        effect_mode <= FX_CHORUS;
        wait for 100 ns;
        for sample in 0 to 40 loop
            process_sample(12000, value);
        end loop;
        assert abs(value - 12000) > 50
            report "Chorus mode did not modulate the signal"
            severity failure;

        effect_mode <= FX_REVERB;
        wait for 100 ns;
        process_sample(30000, value);
        reverb_short := 0;
        for sample in 1 to 4000 loop
            process_sample(0, value);
            if abs(value) > reverb_short then
                reverb_short := abs(value);
            end if;
        end loop;
        for sample in 1 to 6000 loop
            process_sample(0, value);
        end loop;
        reverb_long := value;
        assert reverb_short /= 0
            report "Reverb produced no audible tail"
            severity failure;
        assert abs(reverb_long) <= abs(reverb_short)
            report "Reverb tail did not decay"
            severity failure;

        report "tb_audio_effects passed" severity note;
        wait;
    end process;
end architecture;
