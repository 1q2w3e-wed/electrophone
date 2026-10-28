library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- 根据地址实时生成 OLED 的一个字节，不需要 1024 字节帧缓冲。
entity ui_renderer is
    generic (
        G_CLK_HZ : positive := 50_000_000;
        G_I2C_ADDRESS : natural range 0 to 127 := 16#3C#
    );
    port (
        clk, reset_n, frame_start_i : in std_logic;
        page_i : in page_t;
        cursor_i : in natural range 0 to 3;
        settings_i : in settings_t;
        address_i : in natural range 0 to 1023;
        pixel_o : out byte_t
    );
end entity;

architecture rtl of ui_renderer is
    signal page : page_t := HOME_PAGE;
    signal cursor : natural range 0 to 3 := 0;
    signal cfg : settings_t := (0, 50, 20, 100, 70, 200);
    subtype text_t is string(1 to 21);
    function padded(s : string) return text_t is
        variable result : text_t := (others => ' ');
    begin
        for i in s'range loop
            if i-s'low+1 <= 21 then result(i-s'low+1) := s(i); end if;
        end loop;
        return result;
    end function;
    function decimal(n : natural; digits : positive) return string is
        variable result : string(1 to digits);
        variable value : natural := n;
    begin
        for i in digits downto 1 loop
            result(i) := character'val(character'pos('0') + value mod 10);
            value := value / 10;
        end loop;
        return result;
    end function;
    function hex_digit(n : natural) return character is
    begin
        if n < 10 then return character'val(character'pos('0')+n);
        else return character'val(character'pos('A')+n-10); end if;
    end function;
    function line_text(p : page_t; row : natural; c : settings_t) return text_t is
    begin
        if row = 7 and p /= HOME_PAGE and p /= SYSTEM_PAGE then
            return padded("L:SAVE R:CANCEL");
        end if;
        case p is
            when HOME_PAGE =>
                case row is
                    when 0 => return padded("ELECTROPHONE");
                    when 2 => return padded("  TONE");
                    when 3 => return padded("  VOLUME");
                    when 4 => return padded("  ADSR ENVELOPE");
                    when 5 => return padded("  SYSTEM INFO");
                    when 7 => return padded("LEFT:SELECT / ENTER");
                    when others => return padded("");
                end case;
            when TONE_PAGE =>
                case row is
                    when 0 => return padded("TONE");
                    when 2 =>
                        case c.tone is
                            when 0 => return padded("  0 SINE");
                            when 1 => return padded("  1 SQUARE");
                            when 2 => return padded("  2 SAWTOOTH");
                            when others => return padded("  3 TRIANGLE");
                        end case;
                    when 5 => return padded("TURN RIGHT TO CHANGE");
                    when others => return padded("");
                end case;
            when VOLUME_PAGE =>
                case row is
                    when 0 => return padded("VOLUME");
                    when 2 => return padded("  LEVEL: " & decimal(c.volume,3) & " %");
                    when 5 => return padded("TURN RIGHT TO CHANGE");
                    when others => return padded("");
                end case;
            when ADSR_PAGE =>
                case row is
                    when 0 => return padded("ADSR ENVELOPE");
                    when 2 => return padded("A ATTACK  " & decimal(c.attack_ms,4) & " MS");
                    when 3 => return padded("D DECAY   " & decimal(c.decay_ms,4) & " MS");
                    when 4 => return padded("S SUSTAIN " & decimal(c.sustain,3) & " %");
                    when 5 => return padded("R RELEASE " & decimal(c.release_ms,4) & " MS");
                    when 6 => return padded("L:SELECT R:ADJUST");
                    when others => return padded("");
                end case;
            when SYSTEM_PAGE =>
                case row is
                    when 0 => return padded("SYSTEM INFO");
                    when 2 => return padded("TANG PRIMER 25K");
                    when 3 => return padded("SSD1306 128X64");
                    when 4 => return padded("I2C ADDR: 0X" & hex_digit(G_I2C_ADDRESS/16) & hex_digit(G_I2C_ADDRESS mod 16));
                    when 5 => return padded("CLOCK: " & decimal(G_CLK_HZ/1_000_000,2) & " MHZ");
                    when 6 => return padded("2X EC11 UI V1.0");
                    when 7 => return padded("PRESS EITHER TO BACK");
                    when others => return padded("");
                end case;
        end case;
    end function;
    function glyph(ch : character; column : natural) return byte_t is
        variable columns : std_logic_vector(39 downto 0);
        variable result : byte_t;
    begin
        case ch is
            when 'A' => columns := x"7E1111117E"; when 'B' => columns := x"7F49494936";
            when 'C' => columns := x"3E41414122"; when 'D' => columns := x"7F4141221C";
            when 'E' => columns := x"7F49494941"; when 'F' => columns := x"7F09090901";
            when 'G' => columns := x"3E41495132"; when 'H' => columns := x"7F0808087F";
            when 'I' => columns := x"00417F4100"; when 'J' => columns := x"2040413F01";
            when 'K' => columns := x"7F08142241"; when 'L' => columns := x"7F40404040";
            when 'M' => columns := x"7F020C027F"; when 'N' => columns := x"7F0408107F";
            when 'O' => columns := x"3E4141413E"; when 'P' => columns := x"7F09090906";
            when 'Q' => columns := x"3E4151215E"; when 'R' => columns := x"7F09192946";
            when 'S' => columns := x"4649494931"; when 'T' => columns := x"01017F0101";
            when 'U' => columns := x"3F4040403F"; when 'V' => columns := x"1F2040201F";
            when 'W' => columns := x"3F4038403F"; when 'X' => columns := x"6314081463";
            when 'Y' => columns := x"0304780403"; when 'Z' => columns := x"6151494543";
            when '0' => columns := x"3E5149453E"; when '1' => columns := x"00427F4000";
            when '2' => columns := x"4261514946"; when '3' => columns := x"2141454B31";
            when '4' => columns := x"1814127F10"; when '5' => columns := x"2745454539";
            when '6' => columns := x"3C4A494930"; when '7' => columns := x"0171090503";
            when '8' => columns := x"3649494936"; when '9' => columns := x"064949291E";
            when ':' => columns := x"0036360000"; when '.' => columns := x"0060600000";
            when '/' => columns := x"2010080402"; when '%' => columns := x"2313086462";
            when '-' => columns := x"0808080808"; when others => columns := (others => '0');
        end case;
        if column >= 5 then return x"00"; end if;
        result := columns(39-column*8 downto 32-column*8);
        return result;
    end function;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                page <= HOME_PAGE; cursor <= 0; cfg <= (0,50,20,100,70,200);
            elsif frame_start_i = '1' then
                page <= page_i; cursor <= cursor_i; cfg <= settings_i;
            end if;
        end if;
    end process;
    process(page, cursor, cfg, address_i)
        variable row, x, letter : natural;
        variable line : text_t;
        variable pixels : byte_t;
    begin
        row := address_i / 128; x := address_i mod 128; letter := x / 6 + 1;
        line := line_text(page, row, cfg); pixels := x"00";
        if letter <= 21 then pixels := glyph(line(letter), x mod 6); end if;
        if row = 1 then pixels := x"80"; end if;
        if (page = HOME_PAGE or page = ADSR_PAGE) and row = cursor+2 then pixels := not pixels; end if;
        if page = VOLUME_PAGE and row = 4 and x >= 10 and x <= 111 then
            if x = 10 or x = 111 then pixels := x"7E";
            elsif x <= 10 + cfg.volume then pixels := x"7E";
            else pixels := x"42"; end if;
        end if;
        pixel_o <= pixels;
    end process;
end architecture;
