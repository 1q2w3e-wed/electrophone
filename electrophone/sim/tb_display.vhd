library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
use work.ui_types.all;

entity tb_display is end;
architecture test of tb_display is
    signal clk : std_logic := '0';
    signal reset_n, frame_start : std_logic := '0';
    signal scl, sda : std_logic := 'H';
    signal ack : std_logic := 'Z';
    signal address : natural range 0 to 1023;
    signal pixel : byte_t;
    signal page : page_t := HOME_PAGE;
    signal cursor : natural range 0 to 3 := 0;
    signal cfg : settings_t := (0,50,20,100,70,200,0,20,80);
    type ram_t is array(0 to 1023) of byte_t;
    signal ram : ram_t := (others => x"00");
    signal frames, starts, init_count, enabled_count : natural := 0;
begin
    clk <= not clk after 500 ns;
    scl <= 'H'; sda <= 'H'; sda <= ack;
    display: entity work.oled_ssd1306_i2c
        generic map(G_CLK_HZ=>1_000_000, G_I2C_HZ=>25_000, G_POWER_WAIT_MS=>1, G_FRAME_PAUSE_MS=>1)
        port map(clk,reset_n,frame_start,address,pixel,scl,sda);
    renderer: entity work.ui_renderer
        generic map(G_CLK_HZ=>1_000_000)
        port map(clk,reset_n,frame_start,page,cursor,cfg,address,pixel);

    -- Bus-level SSD1306 receiver. The first address is deliberately NACKed.
    -- All assertions observe the actual resolved SCL/SDA, not driver internals.
    process(scl,sda)
        variable active, nack_first : boolean := false;
        variable bits : natural range 0 to 9 := 0;
        variable received : byte_t := x"00";
        variable index, physical_page, column, control, value, pending : natural := 0;
    begin
        if sda'event and to_x01(scl)='1' then
            if to_x01(sda)='0' then
                active:=true; bits:=0; index:=0; nack_first := starts=0; starts<=starts+1;
            elsif to_x01(sda)='1' and active then
                active:=false; ack<='Z';
                if nack_first then
                    assert index=1 report "NACK did not abort after address" severity failure;
                elsif control=16#40# then
                    assert index=130 report "Page transfer is not exactly 128 pixels" severity failure;
                    if physical_page=7 then frames<=frames+1; end if;
                elsif index=26 then init_count<=init_count+1;
                else assert index=5 or index=3 report "Command transaction length" severity failure;
                end if;
            end if;
        elsif rising_edge(scl) and active then
            if bits<8 then
                received := received(6 downto 0) & to_x01(sda); bits:=bits+1;
                if bits=8 then
                    value := to_integer(unsigned(received));
                    if index=0 then
                        assert received=x"78" report "Wrong 7-bit address/RW bit" severity failure;
                    elsif index=1 then
                        control:=value;
                        assert control=0 or control=16#40# report "Wrong OLED control byte" severity failure;
                    elsif control=16#40# then
                        ram(physical_page*128+column)<=received;
                        column := (column+1) mod 128;
                    elsif pending/=0 then
                        if pending=16#20# then assert value=2 report "Not page addressing mode" severity failure; end if;
                        pending:=0;
                    elsif value>=16#B0# and value<=16#B7# then physical_page:=value-16#B0#;
                    elsif value<=15 then column:=(column/16)*16+value;
                    elsif value>=16#10# and value<=16#1F# then column:=(value-16#10#)*16+column mod 16;
                    elsif value=16#AF# then enabled_count<=enabled_count+1;
                    elsif value=16#D5# or value=16#A8# or value=16#D3# or value=16#8D# or
                          value=16#20# or value=16#DA# or value=16#81# or value=16#D9# or value=16#DB# then pending:=value;
                    end if;
                    index:=index+1;
                end if;
            else bits:=9;
            end if;
        elsif falling_edge(scl) and active then
            if bits=8 then
                if nack_first then ack<='Z'; else ack<='0'; end if;
            elsif bits=9 then ack<='Z'; bits:=0;
            end if;
        end if;
    end process;
    process
        procedure screenshot(name : string) is
            file output : text;
            variable ln : line;
            variable pix : integer;
        begin
            file_open(output,"sim/output/" & name & ".pgm",write_mode);
            write(ln,string'("P2")); writeline(output,ln);
            write(ln,string'("128 64")); writeline(output,ln);
            write(ln,string'("255")); writeline(output,ln);
            for y in 0 to 63 loop
                for x in 0 to 127 loop
                    if ram((y/8)*128+x)(y mod 8)='1' then pix:=255; else pix:=0; end if;
                    write(ln,pix); write(ln,string'(" "));
                end loop;
                writeline(output,ln);
            end loop;
            file_close(output);
        end;
    begin
        wait for 10 us; reset_n<='1';
        wait until enabled_count=1;
        assert starts>=19 and init_count=1 and frames=1 report "Initialization/retry/first frame sequence" severity failure;
        assert ram(0)=x"7F" and ram(1)=x"49" and ram(4)=x"41" report "Title font not on bus" severity failure;
        assert ram(2*128)=x"FF" and ram(3*128)=x"00" report "Home focus rendering" severity failure;
        screenshot("home");

        page<=VOLUME_PAGE; cfg.volume<=73;
        wait until frame_start='1';
        wait for 1 ms;
        -- Mid-transfer changes must be postponed to the following frame.
        cfg.volume<=0;
        wait until frames=2;
        assert ram(4*128+80)=x"7E" and ram(4*128+84)=x"42" report "Frame snapshot/progress bar" severity failure;
        screenshot("volume");
        wait until frames=3;
        assert ram(4*128+11)=x"42" report "Next frame did not update" severity failure;

        page<=ADSR_PAGE; cursor<=2; cfg<=(1,73,20,100,70,200);
        wait until frames=4;
        screenshot("adsr");
        page<=TONE_PAGE; cfg.tone<=1;
        wait until frames=5;
        screenshot("tone");
        page<=SYSTEM_PAGE;
        wait until frames=6;
        screenshot("system");
        report "PASS: OLED bus bytes, NACK retry, all 8 pages, snapshot, font and 5 screens" severity note;
        stop; wait;
    end process;
    process
    begin wait for 4 sec; assert false report "Display test timeout" severity failure; end process;
end;
