library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- Selectable Dry/Delay/Chorus/Reverb effect using one shared delay RAM.
entity audio_effects is
    port (
        clk, rst_n : in std_logic;
        sample_tick : in std_logic;
        sample_in : in signed(15 downto 0);
        effect_mode : in effect_mode_t;
        audio_out : out signed(15 downto 0)
    );
end entity;

architecture rtl of audio_effects is
    constant ST_WAIT       : natural := 0;
    constant ST_READ_ADDR  : natural := 1;
    constant ST_READ_WAIT  : natural := 2;
    constant ST_WRITE      : natural := 3;

    constant DELAY_TAP : natural := 5859;
    constant CHORUS_BASE : natural := 488;
    constant CHORUS_DEPTH : natural := 122;

    signal ram_write_enable : std_logic := '0';
    signal ram_write_address : unsigned(12 downto 0) := (others => '0');
    signal ram_write_data : std_logic_vector(19 downto 0) := (others => '0');
    signal ram_read_address : unsigned(12 downto 0) := (others => '0');
    signal ram_read_data : std_logic_vector(19 downto 0);

    signal write_index : unsigned(12 downto 0) := (others => '0');
    signal state : natural range 0 to 3 := ST_WAIT;
    signal mode_reg : effect_mode_t := FX_DRY;
    signal epoch : unsigned(3 downto 0) := (others => '0');
    signal lfo_phase : unsigned(31 downto 0) := (others => '0');
    signal input_reg : signed(15 downto 0) := (others => '0');
    signal tap_index : natural range 0 to 3 := 0;
    signal tap_count : natural range 0 to 4 := 0;
    signal tap_sum : signed(20 downto 0) := (others => '0');
    signal damp_state : signed(20 downto 0) := (others => '0');
    signal dry_gain : natural range 0 to 255 := 255;
    signal wet_gain : natural range 0 to 255 := 0;
    signal output_reg : signed(15 downto 0) := (others => '0');

    function target_dry(mode : effect_mode_t) return natural is
    begin
        case mode is
            when FX_DELAY => return 191;
            when FX_CHORUS | FX_REVERB => return 166;
            when others => return 255;
        end case;
    end function;

    function target_wet(mode : effect_mode_t) return natural is
    begin
        case mode is
            when FX_DELAY => return 89;
            when FX_CHORUS | FX_REVERB => return 115;
            when others => return 0;
        end case;
    end function;

    function tap_count_for(mode : effect_mode_t) return natural is
    begin
        case mode is
            when FX_DELAY => return 1;
            when FX_CHORUS => return 2;
            when FX_REVERB => return 4;
            when others => return 0;
        end case;
    end function;

    function chorus_offset(phase : unsigned(31 downto 0)) return integer is
        variable p : integer;
        variable triangle : integer;
    begin
        p := to_integer(phase(31 downto 16));
        if phase(31) = '0' then
            triangle := p - 32768;
        else
            triangle := 65535 - p;
        end if;
        return (triangle * CHORUS_DEPTH) / 32768;
    end function;

    function saturate_sample(value : signed(32 downto 0))
        return signed is
    begin
        if value > to_signed(32767, 33) then
            return to_signed(32767, 16);
        elsif value < to_signed(-32768, 33) then
            return to_signed(-32768, 16);
        else
            return value(15 downto 0);
        end if;
    end function;

    function read_sample(word : std_logic_vector(19 downto 0);
                         expected_epoch : unsigned(3 downto 0))
        return signed is
    begin
        if unsigned(word(19 downto 16)) = expected_epoch then
            return signed(word(15 downto 0));
        else
            return to_signed(0, 16);
        end if;
    end function;

    function mixed_output(dry_value, wet_value : signed(15 downto 0);
                          dry_amount, wet_amount : natural) return signed is
        variable sum_value : integer;
    begin
        sum_value :=
            to_integer(dry_value) * dry_amount +
            to_integer(wet_value) * wet_amount;
        sum_value := sum_value / 256;
        if sum_value > 32767 then
            return to_signed(32767, 16);
        elsif sum_value < -32768 then
            return to_signed(-32768, 16);
        else
            return to_signed(sum_value, 16);
        end if;
    end function;
begin
    audio_out <= output_reg;

    delay_memory: entity work.effects_delay_ram
        port map (
            clk => clk,
            write_enable => ram_write_enable,
            write_address => ram_write_address,
            write_data => ram_write_data,
            read_address => ram_read_address,
            read_data => ram_read_data
        );

    effect_process: process(clk)
        variable mode_v : effect_mode_t;
        variable tap_value : signed(15 downto 0);
        variable wet_v : signed(15 downto 0);
        variable feedback_v : signed(20 downto 0);
        variable damp_next : signed(20 downto 0);
        variable address_v : unsigned(12 downto 0);
        variable offset_v : integer;
    begin
        if rising_edge(clk) then
            ram_write_enable <= '0';
            if rst_n = '0' then
                ram_write_address <= (others => '0');
                ram_write_data <= (others => '0');
                ram_read_address <= (others => '0');
                write_index <= (others => '0');
                state <= ST_WAIT;
                mode_reg <= FX_DRY;
                epoch <= (others => '0');
                lfo_phase <= (others => '0');
                input_reg <= (others => '0');
                tap_index <= 0;
                tap_count <= 0;
                tap_sum <= (others => '0');
                damp_state <= (others => '0');
                dry_gain <= 255;
                wet_gain <= 0;
                output_reg <= (others => '0');
            else
                case state is
                    when ST_WAIT =>
                        if sample_tick = '1' then
                            if effect_mode /= mode_reg then
                                mode_reg <= effect_mode;
                                epoch <= epoch + 1;
                                dry_gain <= 255;
                                wet_gain <= 0;
                                damp_state <= (others => '0');
                            end if;
                            mode_v := effect_mode;
                            input_reg <= sample_in;
                            tap_sum <= (others => '0');
                            tap_index <= 0;
                            tap_count <= tap_count_for(mode_v);
                            lfo_phase <= lfo_phase + 70369;

                            if dry_gain < target_dry(mode_v) then
                                dry_gain <= dry_gain + 1;
                            elsif dry_gain > target_dry(mode_v) then
                                dry_gain <= dry_gain - 1;
                            end if;
                            if wet_gain < target_wet(mode_v) then
                                wet_gain <= wet_gain + 1;
                            elsif wet_gain > target_wet(mode_v) then
                                wet_gain <= wet_gain - 1;
                            end if;

                            if mode_v = FX_DRY then
                                state <= ST_WRITE;
                            else
                                state <= ST_READ_ADDR;
                            end if;
                        end if;
                    when ST_READ_ADDR =>
                        case mode_reg is
                            when FX_DELAY =>
                                address_v := write_index -
                                             to_unsigned(DELAY_TAP, 13);
                            when FX_CHORUS =>
                                offset_v := chorus_offset(lfo_phase);
                                if tap_index = 0 then
                                    address_v := write_index -
                                        to_unsigned(
                                            CHORUS_BASE + offset_v, 13);
                                else
                                    address_v := write_index -
                                        to_unsigned(
                                            CHORUS_BASE - offset_v, 13);
                                end if;
                            when FX_REVERB =>
                                case tap_index is
                                    when 0 =>
                                        address_v := write_index -
                                                     to_unsigned(1513, 13);
                                    when 1 =>
                                        address_v := write_index -
                                                     to_unsigned(2099, 13);
                                    when 2 =>
                                        address_v := write_index -
                                                     to_unsigned(2880, 13);
                                    when others =>
                                        address_v := write_index -
                                                     to_unsigned(3563, 13);
                                end case;
                            when others =>
                                address_v := write_index;
                        end case;
                        ram_read_address <= address_v;
                        state <= ST_READ_WAIT;
                    when ST_READ_WAIT =>
                        tap_value := read_sample(ram_read_data, epoch);
                        tap_sum <= tap_sum + resize(tap_value, 21);
                        if tap_index + 1 = tap_count then
                            state <= ST_WRITE;
                        else
                            tap_index <= tap_index + 1;
                            state <= ST_READ_ADDR;
                        end if;
                    when ST_WRITE =>
                        case mode_reg is
                            when FX_DELAY =>
                                wet_v := tap_sum(15 downto 0);
                                feedback_v :=
                                    resize(input_reg, 21) +
                                    resize(shift_right(wet_v, 2), 21) +
                                    resize(shift_right(wet_v, 3), 21);
                            when FX_CHORUS =>
                                wet_v := resize(shift_right(tap_sum, 1), 16);
                                feedback_v := resize(input_reg, 21);
                            when FX_REVERB =>
                                wet_v := resize(shift_right(tap_sum, 2), 16);
                                damp_next := damp_state +
                                    shift_right(
                                        resize(wet_v, 21) - damp_state, 2);
                                damp_state <= damp_next;
                                feedback_v := resize(input_reg, 21) +
                                    shift_right(damp_next, 1) -
                                    shift_right(damp_next, 4);
                            when others =>
                                wet_v := (others => '0');
                                feedback_v := resize(input_reg, 21);
                        end case;

                        ram_write_enable <= '1';
                        ram_write_address <= write_index;
                        ram_write_data <= std_logic_vector(epoch) &
                            std_logic_vector(saturate_sample(
                                resize(feedback_v, 33)));
                        if mode_reg = FX_DRY then
                            output_reg <= input_reg;
                        else
                            output_reg <= mixed_output(input_reg, wet_v,
                                                       dry_gain, wet_gain);
                        end if;
                        write_index <= write_index + 1;
                        state <= ST_WAIT;
                    when others =>
                        state <= ST_WAIT;
                end case;
            end if;
        end if;
    end process;
end architecture;
