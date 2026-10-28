library ieee;
use ieee.std_logic_1164.all;

-- 一个 EC11 使用本模块一次；顶层实例化两次。
-- 外部开关接地，因此 A/B/KEY 均需上拉，按下为低电平。
entity ec11_decoder is
    generic (
        G_CLK_HZ          : positive := 50_000_000;
        G_ROT_FILTER_US   : positive := 100;
        G_KEY_DEBOUNCE_MS : positive := 20;
        G_EDGES_PER_STEP  : positive range 1 to 4 := 2;
        G_REVERSE         : boolean := false
    );
    port (
        clk, reset_n : in std_logic;
        enc_a, enc_b, key_n : in std_logic;
        step_left, step_right, key_press : out std_logic
    );
end entity;

architecture rtl of ec11_decoder is
    function at_least_one(n : natural) return positive is
    begin
        if n = 0 then return 1; else return n; end if;
    end function;
    constant ROT_CYCLES : positive := at_least_one((G_CLK_HZ / 1_000_000) * G_ROT_FILTER_US);
    constant KEY_CYCLES : positive := at_least_one((G_CLK_HZ / 1000) * G_KEY_DEBOUNCE_MS);
    signal meta, sync : std_logic_vector(2 downto 0) := "111";
    signal ab, ab_previous : std_logic_vector(1 downto 0) := "11";
    signal key, key_previous : std_logic := '1';
    signal rot_count : natural range 0 to ROT_CYCLES-1 := 0;
    signal key_count : natural range 0 to KEY_CYCLES-1 := 0;
    signal partial_step : integer range -4 to 4 := 0;
    attribute syn_keep : boolean;
    attribute syn_keep of meta, sync : signal is true;
begin
    process(clk)
        variable transition : std_logic_vector(3 downto 0);
        variable movement, sum : integer range -5 to 5;
    begin
        if rising_edge(clk) then
            step_left <= '0'; step_right <= '0'; key_press <= '0';
            if reset_n = '0' then
                meta <= "111"; sync <= "111"; ab <= "11"; ab_previous <= "11";
                key <= '1'; key_previous <= '1'; rot_count <= 0; key_count <= 0; partial_step <= 0;
            else
                meta <= enc_a & enc_b & key_n;
                sync <= meta;
                if sync(2 downto 1) = ab then rot_count <= 0;
                elsif rot_count = ROT_CYCLES-1 then ab <= sync(2 downto 1); rot_count <= 0;
                else rot_count <= rot_count + 1; end if;
                if sync(0) = key then key_count <= 0;
                elsif key_count = KEY_CYCLES-1 then key <= sync(0); key_count <= 0;
                else key_count <= key_count + 1; end if;

                -- 合法正交序列：11 -> 01 -> 00 -> 10 -> 11。
                if ab /= ab_previous then
                    transition := ab_previous & ab;
                    movement := 0;
                    case transition is
                        when "1101" | "0100" | "0010" | "1011" => movement := 1;
                        when "1110" | "1000" | "0001" | "0111" => movement := -1;
                        when others => partial_step <= 0;
                    end case;
                    if movement /= 0 then
                        sum := partial_step + movement;
                        if sum >= G_EDGES_PER_STEP then
                            if G_REVERSE then step_left <= '1'; else step_right <= '1'; end if;
                            partial_step <= 0;
                        elsif sum <= -G_EDGES_PER_STEP then
                            if G_REVERSE then step_right <= '1'; else step_left <= '1'; end if;
                            partial_step <= 0;
                        else partial_step <= sum; end if;
                    end if;
                    ab_previous <= ab;
                end if;
                if key_previous = '1' and key = '0' then key_press <= '1'; end if;
                key_previous <= key;
            end if;
        end if;
    end process;
end architecture;
