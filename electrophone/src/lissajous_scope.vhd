library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Real-audio XY display with a 48-sample delayed Y axis.
entity lissajous_scope is
    port (
        clk, rst_n : in std_logic;
        sample_tick : in std_logic;
        sample_in : in signed(15 downto 0);
        display_latch : in std_logic;
        read_x, read_y : in natural range 0 to 95;
        pixel_o : out std_logic;
        frame_ready : out std_logic
    );
end entity;

architecture rtl of lissajous_scope is
    constant FRAME_POINTS : positive := 1024;
    constant DELAY_SAMPLES : positive := 48;
    constant PLOT_SIZE : positive := 96;
    constant PLOT_CENTER : positive := 48;

    constant ST_CLEAR       : natural := 0;
    constant ST_WAIT_SAMPLE : natural := 1;
    constant ST_DRAW        : natural := 2;
    constant ST_WAIT_LATCH  : natural := 3;

    type delay_array_t is array (0 to DELAY_SAMPLES-1) of signed(15 downto 0);

    signal delay_history : delay_array_t := (others => (others => '0'));
    signal state : natural range 0 to 3 := ST_CLEAR;
    signal clear_x, clear_y : natural range 0 to 95 := 0;
    signal point_x, point_y : natural range 0 to 95 := PLOT_CENTER;
    signal point_valid : std_logic := '0';
    signal draw_step : natural range 0 to 3 := 0;
    signal point_count : natural range 0 to FRAME_POINTS-1 := 0;
    signal write_bank, display_bank : std_logic := '0';
    signal write_x, write_y : natural range 0 to 95 := 0;
    signal write_value : std_logic := '0';
    signal frame_ready_reg : std_logic := '0';
    signal previous_peak : unsigned(15 downto 0) := to_unsigned(16384, 16);
    signal current_peak : unsigned(15 downto 0) := (others => '0');

    function magnitude(value : signed(15 downto 0)) return unsigned is
        variable result : unsigned(15 downto 0);
    begin
        if value(15) = '1' then
            result := unsigned(not std_logic_vector(value)) + 1;
        else
            result := unsigned(value);
        end if;
        return result;
    end function;

    function gain_shift(peak : unsigned(15 downto 0)) return natural is
    begin
        if peak < 2048 then
            return 4;
        elsif peak < 4096 then
            return 3;
        elsif peak < 8192 then
            return 2;
        elsif peak < 16384 then
            return 1;
        else
            return 0;
        end if;
    end function;

    function scaled_sample(value : signed(15 downto 0);
                           shift_amount : natural) return signed is
        variable wide : signed(21 downto 0);
    begin
        wide := resize(value, 22) sll shift_amount;
        if wide > to_signed(32767, 22) then
            return to_signed(32767, 16);
        elsif wide < to_signed(-32768, 22) then
            return to_signed(-32768, 16);
        else
            return wide(15 downto 0);
        end if;
    end function;

    function to_coordinate(value : signed(15 downto 0)) return natural is
        variable scaled : integer;
        variable coordinate : integer;
    begin
        scaled := to_integer(shift_right(value, 9));
        scaled := scaled - to_integer(shift_right(to_signed(scaled, 8), 2));
        coordinate := PLOT_CENTER + scaled;
        if coordinate < 0 then
            return 0;
        elsif coordinate > 95 then
            return 95;
        else
            return coordinate;
        end if;
    end function;
begin
    frame_ready <= frame_ready_reg;

    bitmap: entity work.lissajous_bitmap_ram
        port map (
            clk => clk,
            rst_n => rst_n,
            write_bank => write_bank,
            write_x => write_x,
            write_y => write_y,
            write_value => write_value,
            read_bank => display_bank,
            read_x => read_x,
            read_y => read_y,
            read_value => pixel_o
        );

    draw_frame: process(clk)
        variable delayed_sample : signed(15 downto 0);
        variable x_scaled, y_scaled : signed(15 downto 0);
        variable point_magnitude : unsigned(15 downto 0);
        variable candidate_x, candidate_y : integer;
        variable valid_pixel : boolean;
        variable next_peak : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            frame_ready_reg <= '0';
            write_value <= '0';
            if rst_n = '0' then
                delay_history <= (others => (others => '0'));
                state <= ST_CLEAR;
                clear_x <= 0;
                clear_y <= 0;
                point_x <= PLOT_CENTER;
                point_y <= PLOT_CENTER;
                point_valid <= '0';
                draw_step <= 0;
                point_count <= 0;
                write_bank <= '0';
                display_bank <= '1';
                write_x <= 0;
                write_y <= 0;
                previous_peak <= to_unsigned(16384, 16);
                current_peak <= (others => '0');
            else
                case state is
                    when ST_CLEAR =>
                        write_x <= clear_x;
                        write_y <= clear_y;
                        write_value <= '0';
                        if clear_x = 95 then
                            clear_x <= 0;
                            if clear_y = 95 then
                                clear_y <= 0;
                                point_count <= 0;
                                current_peak <= (others => '0');
                                state <= ST_WAIT_SAMPLE;
                            else
                                clear_y <= clear_y + 1;
                            end if;
                        else
                            clear_x <= clear_x + 1;
                        end if;
                    when ST_WAIT_SAMPLE =>
                        if sample_tick = '1' then
                            delayed_sample := delay_history(DELAY_SAMPLES-1);
                            for index in DELAY_SAMPLES-1 downto 1 loop
                                delay_history(index) <= delay_history(index-1);
                            end loop;
                            delay_history(0) <= sample_in;

                            x_scaled := scaled_sample(
                                sample_in, gain_shift(previous_peak));
                            y_scaled := scaled_sample(
                                delayed_sample, gain_shift(previous_peak));
                            point_x <= to_coordinate(x_scaled);
                            point_y <= to_coordinate(y_scaled);
                            if x_scaled = 0 and y_scaled = 0 then
                                point_valid <= '0';
                            else
                                point_valid <= '1';
                            end if;

                            point_magnitude := magnitude(sample_in);
                            if magnitude(delayed_sample) > point_magnitude then
                                point_magnitude := magnitude(delayed_sample);
                            end if;
                            if point_magnitude > current_peak then
                                current_peak <= point_magnitude;
                            end if;
                            draw_step <= 0;
                            state <= ST_DRAW;
                        end if;
                    when ST_DRAW =>
                        candidate_x := point_x;
                        candidate_y := point_y;
                        valid_pixel := point_valid = '1';
                        case draw_step is
                            when 1 => candidate_x := candidate_x + 1;
                            when 2 => candidate_y := candidate_y + 1;
                            when others => candidate_x := candidate_x + 1;
                                           candidate_y := candidate_y + 1;
                        end case;
                        if candidate_x < 0 or candidate_x > 95 or
                           candidate_y < 0 or candidate_y > 95 then
                            valid_pixel := false;
                        end if;
                        if valid_pixel then
                            write_x <= candidate_x;
                            write_y <= candidate_y;
                            write_value <= '1';
                        end if;

                        if draw_step = 3 then
                            if point_count = FRAME_POINTS-1 then
                                previous_peak <= current_peak;
                                frame_ready_reg <= '1';
                                state <= ST_WAIT_LATCH;
                            else
                                point_count <= point_count + 1;
                                state <= ST_WAIT_SAMPLE;
                            end if;
                        else
                            draw_step <= draw_step + 1;
                        end if;
                    when others =>
                        if display_latch = '1' then
                            display_bank <= write_bank;
                            write_bank <= not write_bank;
                            clear_x <= 0;
                            clear_y <= 0;
                            state <= ST_CLEAR;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;
