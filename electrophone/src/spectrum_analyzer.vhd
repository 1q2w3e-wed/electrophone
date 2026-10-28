library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spectrum_tables.all;

-- Captures real audio and computes a time-multiplexed 2048-point FFT.
-- The 52 display bins use a logarithmic 20 Hz to 4 kHz frequency axis.
entity spectrum_analyzer is
    port (
        clk, rst_n : in std_logic;
        sample_tick : in std_logic;
        sample_in : in signed(15 downto 0);
        test_mode : in std_logic;
        display_latch : in std_logic;
        read_bin : in natural range 0 to 63;
        magnitude_o : out unsigned(7 downto 0);
        frame_ready : out std_logic
    );
end entity;

architecture rtl of spectrum_analyzer is
    type spectrum_bank_t is array (0 to 63) of unsigned(7 downto 0);
    type output_bin_table_t is array (0 to 51) of natural range 0 to 1023;

    -- 20 Hz to 4 kHz, logarithmically spaced. Repeated low-frequency bins
    -- are inevitable because one 2048-point FFT bin is about 23.8 Hz wide.
    constant OUTPUT_BINS : output_bin_table_t := (
        1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3,
        3, 4, 4, 4, 5, 5, 6, 7, 7, 8, 9, 10, 11,
        12, 14, 15, 17, 19, 21, 23, 26, 29, 32, 35,
        39, 43, 48, 54, 59, 66, 73, 81, 90, 100,
        111, 123, 136, 151, 168
    );

    constant ST_WAIT_FULL  : natural := 0;
    constant ST_COPY_ADDR  : natural := 1;
    constant ST_COPY_WAIT  : natural := 2;
    constant ST_COPY_READ  : natural := 3;
    constant ST_COPY_WRITE : natural := 4;
    constant ST_BF_ADDR_A  : natural := 5;
    constant ST_BF_WAIT_A  : natural := 6;
    constant ST_BF_ADDR_B  : natural := 7;
    constant ST_BF_WAIT_B  : natural := 8;
    constant ST_BF_WRITE_A : natural := 9;
    constant ST_BF_COMMIT_A : natural := 10;
    constant ST_BF_COMMIT_B : natural := 11;
    constant ST_OUT_ADDR   : natural := 12;
    constant ST_OUT_WAIT   : natural := 13;
    constant ST_OUT_WRITE  : natural := 14;
    constant ST_BF_LATCH_B  : natural := 15;
    constant ST_BF_PRODUCTS : natural := 16;
    constant ST_BF_MIX      : natural := 17;
    constant ST_BF_SUM      : natural := 18;
    constant ST_OUT_READ    : natural := 19;
    constant ST_OUT_MAG     : natural := 20;

    signal bank0, bank1 : spectrum_bank_t := (others => (others => '0'));
    signal write_bank, read_bank : std_logic := '0';
    signal completed_bank : std_logic := '0';

    signal capture_count : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal capture_full : std_logic := '0';
    signal capture_locked : std_logic := '0';
    signal capture_read_address : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal capture_read_data : signed(15 downto 0) := (others => '0');
    signal capture_write_enable : std_logic := '0';

    signal work_read_address : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal work_read_real : signed(31 downto 0) := (others => '0');
    signal work_read_imag : signed(31 downto 0) := (others => '0');
    signal work_write_enable : std_logic := '0';
    signal work_write_address : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal work_write_real : signed(31 downto 0) := (others => '0');
    signal work_write_imag : signed(31 downto 0) := (others => '0');

    signal state : natural range 0 to 20 := ST_WAIT_FULL;
    signal copy_index : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal stage : natural range 0 to 10 := 0;
    signal butterfly_index : natural range 0 to 1023 := 0;
    signal bf_a, bf_b : natural range 0 to SPECTRUM_FFT_SIZE-1 := 0;
    signal bf_twiddle : natural range 0 to 1023 := 0;
    signal bf_a_real, bf_a_imag : signed(31 downto 0) := (others => '0');
    signal bf_b_real, bf_b_imag : signed(31 downto 0) := (others => '0');
    signal bf_product_rr, bf_product_ri : signed(47 downto 0) :=
        (others => '0');
    signal bf_product_ir, bf_product_ii : signed(47 downto 0) :=
        (others => '0');
    signal bf_t_real, bf_t_imag : signed(35 downto 0) := (others => '0');
    signal copy_product : signed(31 downto 0) := (others => '0');
    signal bf_diff_real, bf_diff_imag : signed(31 downto 0) :=
        (others => '0');
    signal output_index : natural range 0 to 51 := 0;
    signal out_real_reg, out_imag_reg : signed(31 downto 0) :=
        (others => '0');
    signal magnitude_reg : unsigned(7 downto 0) := (others => '0');
    signal frame_ready_reg : std_logic := '0';

    function saturate32(value : signed(35 downto 0))
        return signed is
    begin
        if value > to_signed(2147483647, 36) then
            return to_signed(2147483647, 32);
        elsif value < to_signed(-2147483648, 36) then
            return to_signed(-2147483648, 32);
        else
            return value(31 downto 0);
        end if;
    end function;

    function mul_q15(value : signed(31 downto 0);
                      coefficient : signed(15 downto 0))
        return signed is
        variable product : signed(47 downto 0);
    begin
        product := value * coefficient;
        return resize(shift_right(product, 15), 36);
    end function;

    function log_level(real_value, imag_value : signed(31 downto 0))
        return unsigned is
        variable magnitude : unsigned(32 downto 0);
        variable level : natural := 0;
        variable position : natural := 0;
        variable fraction : natural := 0;
    begin
        magnitude := resize(unsigned(abs(real_value)), 33) +
                     resize(unsigned(abs(imag_value)), 33);
        if magnitude = 0 then
            return to_unsigned(0, 8);
        end if;
        for bit_index in 0 to 32 loop
            if magnitude(bit_index) = '1' then
                position := bit_index;
            end if;
        end loop;
        if position >= 2 then
            fraction := to_integer(magnitude(position-1 downto position-2));
        end if;
        level := position * 8 + fraction * 2;
        if level > 255 then
            level := 255;
        end if;
        return to_unsigned(level, 8);
    end function;
begin
    frame_ready <= frame_ready_reg;
    capture_write_enable <= '1' when
        sample_tick = '1' and capture_locked = '0' and
        capture_full = '0' else '0';

    capture_memory: entity work.spectrum_capture_ram
        port map (
            clk => clk,
            write_enable => capture_write_enable,
            write_address => capture_count,
            write_data => sample_in,
            read_address => capture_read_address,
            read_data => capture_read_data
        );

    work_memory: entity work.spectrum_work_ram
        port map (
            clk => clk,
            write_enable => work_write_enable,
            write_address => work_write_address,
            write_real => work_write_real,
            write_imag => work_write_imag,
            read_address => work_read_address,
            read_real => work_read_real,
            read_imag => work_read_imag
        );

    magnitude_output: process(clk)
    begin
        if rising_edge(clk) then
            if read_bank = '0' then
                magnitude_o <= bank0(read_bin);
            else
                magnitude_o <= bank1(read_bin);
            end if;
        end if;
    end process;

    analyzer: process(clk)
        variable stage_u : unsigned(10 downto 0);
        variable group_u : unsigned(10 downto 0);
        variable j_u : unsigned(10 downto 0);
        variable a_u, b_u : unsigned(11 downto 0);
        variable twiddle_u : unsigned(10 downto 0);
        variable window_product : signed(31 downto 0);
        variable t_real, t_imag : signed(35 downto 0);
        variable sum_real, diff_real : signed(35 downto 0);
        variable sum_imag, diff_imag : signed(35 downto 0);
        variable magnitude_value : unsigned(7 downto 0);
    begin
        if rising_edge(clk) then
            frame_ready_reg <= '0';
            if rst_n = '0' then
                work_write_enable <= '0';
                capture_count <= 0;
                capture_full <= '0';
                capture_locked <= '0';
                capture_read_address <= 0;
                work_read_address <= 0;
                work_write_address <= 0;
                work_write_real <= (others => '0');
                work_write_imag <= (others => '0');
                state <= ST_WAIT_FULL;
                copy_index <= 0;
                stage <= 0;
                butterfly_index <= 0;
                bf_a <= 0;
                bf_b <= 0;
                bf_twiddle <= 0;
                bf_a_real <= (others => '0');
                bf_a_imag <= (others => '0');
                bf_b_real <= (others => '0');
                bf_b_imag <= (others => '0');
                bf_product_rr <= (others => '0');
                bf_product_ri <= (others => '0');
                bf_product_ir <= (others => '0');
                bf_product_ii <= (others => '0');
                bf_t_real <= (others => '0');
                bf_t_imag <= (others => '0');
                copy_product <= (others => '0');
                bf_diff_real <= (others => '0');
                bf_diff_imag <= (others => '0');
                output_index <= 0;
                out_real_reg <= (others => '0');
                out_imag_reg <= (others => '0');
                magnitude_reg <= (others => '0');
                write_bank <= '0';
                read_bank <= '0';
                completed_bank <= '0';
                bank0 <= (others => (others => '0'));
                bank1 <= (others => (others => '0'));
            else
                work_write_enable <= '0';
                if display_latch = '1' then
                    read_bank <= completed_bank;
                end if;

                if sample_tick = '1' and capture_locked = '0' and
                   capture_full = '0' then
                    if capture_count = SPECTRUM_FFT_SIZE-1 then
                        capture_full <= '1';
                    else
                        capture_count <= capture_count + 1;
                    end if;
                end if;

                case state is
                    when ST_WAIT_FULL =>
                        if capture_full = '1' then
                            capture_locked <= '1';
                            capture_read_address <= 0;
                            copy_index <= 0;
                            state <= ST_COPY_ADDR;
                        end if;
                    when ST_COPY_ADDR =>
                        capture_read_address <= copy_index;
                        state <= ST_COPY_WAIT;
                    when ST_COPY_WAIT =>
                        state <= ST_COPY_READ;
                    when ST_COPY_READ =>
                        window_product := capture_read_data *
                                          HANN_TABLE(copy_index);
                        copy_product <=
                            resize(shift_right(window_product, 15), 32);
                        work_write_enable <= '1';
                        work_write_address <=
                            bit_reverse_11(copy_index);
                        work_write_real <=
                            resize(shift_right(window_product, 15), 32);
                        work_write_imag <= (others => '0');
                        state <= ST_COPY_WRITE;
                    when ST_COPY_WRITE =>
                        if copy_index = SPECTRUM_FFT_SIZE-1 then
                            capture_locked <= '0';
                            capture_full <= '0';
                            capture_count <= 0;
                            stage <= 0;
                            butterfly_index <= 0;
                            state <= ST_BF_ADDR_A;
                        else
                            copy_index <= copy_index + 1;
                            capture_read_address <= copy_index + 1;
                            state <= ST_COPY_WAIT;
                        end if;
                    when ST_BF_ADDR_A =>
                        group_u := shift_right(
                            to_unsigned(butterfly_index, 11), stage);
                        j_u := to_unsigned(butterfly_index, 11) -
                               shift_left(group_u, stage);
                        a_u := resize(shift_left(group_u, stage+1) + j_u, 12);
                        b_u := a_u + resize(shift_left(
                            to_unsigned(1, 11), stage), 12);
                        twiddle_u := resize(shift_left(
                            j_u, 10-stage), 11);
                        bf_a <= to_integer(a_u);
                        bf_b <= to_integer(b_u);
                        bf_twiddle <= to_integer(twiddle_u);
                        work_read_address <= to_integer(a_u);
                        state <= ST_BF_WAIT_A;
                    when ST_BF_WAIT_A =>
                        state <= ST_BF_ADDR_B;
                    when ST_BF_ADDR_B =>
                        bf_a_real <= work_read_real;
                        bf_a_imag <= work_read_imag;
                        work_read_address <= bf_b;
                        state <= ST_BF_WAIT_B;
                    when ST_BF_WAIT_B =>
                        state <= ST_BF_LATCH_B;
                    when ST_BF_LATCH_B =>
                        bf_b_real <= work_read_real;
                        bf_b_imag <= work_read_imag;
                        state <= ST_BF_PRODUCTS;
                    when ST_BF_PRODUCTS =>
                        bf_product_rr <= bf_b_real *
                                         TWIDDLE_COS(bf_twiddle);
                        bf_product_ri <= bf_b_imag *
                                         TWIDDLE_SIN(bf_twiddle);
                        bf_product_ir <= bf_b_real *
                                         TWIDDLE_SIN(bf_twiddle);
                        bf_product_ii <= bf_b_imag *
                                         TWIDDLE_COS(bf_twiddle);
                        state <= ST_BF_MIX;
                    when ST_BF_MIX =>
                        t_real := resize(shift_right(
                            bf_product_rr - bf_product_ri, 15), 36);
                        t_imag := resize(shift_right(
                            bf_product_ir + bf_product_ii, 15), 36);
                        bf_t_real <= t_real;
                        bf_t_imag <= t_imag;
                        state <= ST_BF_SUM;
                    when ST_BF_SUM =>
                        t_real := bf_t_real;
                        t_imag := bf_t_imag;
                        sum_real := resize(bf_a_real, 36) + t_real;
                        diff_real := resize(bf_a_real, 36) - t_real;
                        sum_imag := resize(bf_a_imag, 36) + t_imag;
                        diff_imag := resize(bf_a_imag, 36) - t_imag;
                        work_write_enable <= '1';
                        work_write_address <= bf_a;
                        work_write_real <= saturate32(sum_real);
                        work_write_imag <= saturate32(sum_imag);
                        bf_diff_real <= saturate32(diff_real);
                        bf_diff_imag <= saturate32(diff_imag);
                        state <= ST_BF_COMMIT_A;
                    when ST_BF_COMMIT_A =>
                        work_write_address <= bf_b;
                        work_write_real <= bf_diff_real;
                        work_write_imag <= bf_diff_imag;
                        work_write_enable <= '1';
                        state <= ST_BF_COMMIT_B;
                    when ST_BF_COMMIT_B =>
                        if butterfly_index = 1023 then
                            if stage = 10 then
                                output_index <= 0;
                                state <= ST_OUT_ADDR;
                            else
                                stage <= stage + 1;
                                butterfly_index <= 0;
                                state <= ST_BF_ADDR_A;
                            end if;
                        else
                            butterfly_index <= butterfly_index + 1;
                            state <= ST_BF_ADDR_A;
                        end if;
                    when ST_OUT_ADDR =>
                        if test_mode = '1' then
                            if output_index < 32 then
                                work_read_address <= 9 + output_index*2;
                            else
                                work_read_address <= 0;
                            end if;
                        else
                            work_read_address <= OUTPUT_BINS(output_index);
                        end if;
                        state <= ST_OUT_WAIT;
                    when ST_OUT_WAIT =>
                        state <= ST_OUT_READ;
                    when ST_OUT_READ =>
                        out_real_reg <= work_read_real;
                        out_imag_reg <= work_read_imag;
                        state <= ST_OUT_MAG;
                    when ST_OUT_MAG =>
                        magnitude_reg <= log_level(out_real_reg, out_imag_reg);
                        state <= ST_OUT_WRITE;
                    when ST_OUT_WRITE =>
                        if write_bank = '0' then
                            if test_mode = '1' and output_index >= 32 then
                                bank0(output_index) <= (others => '0');
                            else
                                bank0(output_index) <= magnitude_reg;
                            end if;
                        else
                            if test_mode = '1' and output_index >= 32 then
                                bank1(output_index) <= (others => '0');
                            else
                                bank1(output_index) <= magnitude_reg;
                            end if;
                        end if;
                        if output_index = 51 then
                            completed_bank <= write_bank;
                            write_bank <= not write_bank;
                            frame_ready_reg <= '1';
                            state <= ST_WAIT_FULL;
                        else
                            output_index <= output_index + 1;
                            state <= ST_OUT_ADDR;
                        end if;
                    when others =>
                        state <= ST_WAIT_FULL;
                end case;
            end if;
        end if;
    end process;
end architecture;
