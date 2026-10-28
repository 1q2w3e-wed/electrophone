library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ui_types.all;

-- 双缓冲、过零点触发的音频示波器。每个显示帧先抓到完整的新缓冲区，
-- 再在下一帧起点整体切换，避免逐行刷新时拼出不同相位的波形。
entity audio_scope is
    port (
        clk, rst_n  : in  std_logic;
        sample_tick : in  std_logic;
        sample_in   : in  audio_sample_t;
        frame_start : in  std_logic;
        read_index  : in  natural range 0 to 479;
        audio_sample: out audio_sample_t
    );
end entity;

architecture rtl of audio_scope is
    type sample_banks_t is array (0 to 1023) of audio_sample_t;
    signal banks : sample_banks_t := (others => (others => '0'));
    signal write_bank : std_logic := '1';
    signal read_bank  : std_logic := '0';
    signal write_index : natural range 0 to 511 := 0;
    signal capture_armed : std_logic := '0';
    signal trigger_seen : std_logic := '0';
    signal pending_ready : std_logic := '0';
    signal wait_count : natural range 0 to 1023 := 0;
    signal previous_sample : audio_sample_t := (others => '0');
begin
    process(clk)
        variable write_address_v : natural range 0 to 1023;
        variable read_address_v : natural range 0 to 1023;
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                banks <= (others => (others => '0'));
                write_bank <= '1';
                read_bank <= '0';
                write_index <= 0;
                capture_armed <= '0';
                trigger_seen <= '0';
                pending_ready <= '0';
                wait_count <= 0;
                previous_sample <= (others => '0');
                audio_sample <= (others => '0');
            else
                if frame_start = '1' then
                    -- 新缓冲区已经抓完整帧后才允许整体切换，画面扫描期间
                    -- read_bank 不会变化。
                    if pending_ready = '1' then
                        read_bank <= write_bank;
                        write_bank <= not write_bank;
                        pending_ready <= '0';
                    end if;
                    capture_armed <= '1';
                    trigger_seen <= '0';
                    write_index <= 0;
                    wait_count <= 0;
                elsif sample_tick = '1' then
                    if capture_armed = '1' then
                        if trigger_seen = '0' then
                            -- 正过零点触发；长时间静音时超时后从头采集。
                            if (previous_sample < to_signed(0, 16) and
                                sample_in >= to_signed(0, 16)) or
                               wait_count = 1023 then
                                trigger_seen <= '1';
                            else
                                wait_count <= wait_count + 1;
                            end if;
                        else
                            if write_bank = '0' then
                                write_address_v := write_index;
                            else
                                write_address_v := 512 + write_index;
                            end if;
                            banks(write_address_v) <= sample_in;
                            if write_index = 511 then
                                capture_armed <= '0';
                                pending_ready <= '1';
                            else
                                write_index <= write_index + 1;
                            end if;
                        end if;
                    end if;
                    previous_sample <= sample_in;
                end if;

                if read_bank = '0' then
                    read_address_v := read_index;
                else
                    read_address_v := 512 + read_index;
                end if;
                audio_sample <= banks(read_address_v);
            end if;
        end if;
    end process;
end architecture;
