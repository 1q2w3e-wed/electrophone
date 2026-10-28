library ieee;
use ieee.std_logic_1164.all;
use work.ui_types.all;

entity tb_ui_controller is
end entity;

architecture sim of tb_ui_controller is
    constant CLK_PERIOD : time := 20 ns;
    signal clk : std_logic := '0';
    signal reset_n : std_logic := '0';
    signal left_next, left_prev, left_press : std_logic := '0';
    signal right_next, right_prev, right_press : std_logic := '0';
    signal voices_idle : std_logic := '1';
    signal focus : focus_t;
    signal preview : preview_t;
    signal cfg : settings_t;
    signal status : status_t;
    signal pedal_mode : std_logic;
    signal octave_shift : std_logic;
begin
    clk <= not clk after CLK_PERIOD/2;

    dut: entity work.ui_controller
        generic map (
            G_CLK_HZ => 1_000_000,
            G_DEFAULT_TONE => 0,
            G_DEFAULT_VOLUME => 50,
            G_DEFAULT_ATTACK => 20,
            G_DEFAULT_DECAY => 100,
            G_DEFAULT_SUSTAIN => 70,
            G_DEFAULT_RELEASE => 200,
            G_TIME_STEP_MS => 10,
            G_STATUS_MS => 100
        )
        port map (
            clk => clk, reset_n => reset_n,
            left_next => left_next, left_prev => left_prev,
            left_press => left_press,
            right_next => right_next, right_prev => right_prev,
            right_press => right_press,
            voices_idle => voices_idle,
            focus_o => focus, preview_o => preview,
            settings_o => cfg, status_o => status,
            pedal_mode_o => pedal_mode,
            octave_shift_o => octave_shift
        );

    stimulus: process
        procedure pulse_left_next is
        begin
            wait until falling_edge(clk); left_next <= '1';
            wait until falling_edge(clk); left_next <= '0';
        end procedure;

        procedure pulse_left_prev is
        begin
            wait until falling_edge(clk); left_prev <= '1';
            wait until falling_edge(clk); left_prev <= '0';
        end procedure;

        procedure pulse_left_press is
        begin
            wait until falling_edge(clk); left_press <= '1';
            wait until falling_edge(clk); left_press <= '0';
        end procedure;

        procedure pulse_right_next is
        begin
            wait until falling_edge(clk); right_next <= '1';
            wait until falling_edge(clk); right_next <= '0';
        end procedure;

        procedure pulse_right_prev is
        begin
            wait until falling_edge(clk); right_prev <= '1';
            wait until falling_edge(clk); right_prev <= '0';
        end procedure;

        procedure pulse_right_press is
        begin
            wait until falling_edge(clk); right_press <= '1';
            wait until falling_edge(clk); right_press <= '0';
        end procedure;
    begin
        wait for 5*CLK_PERIOD;
        reset_n <= '1';
        wait for 3*CLK_PERIOD;

        assert focus = FOCUS_TIMBRE and preview = PREVIEW_AUDIO
            report "Initial focus/preview is wrong" severity failure;
        assert octave_shift = '0'
            report "Octave switch did not start in the low position"
            severity failure;
        assert cfg = (0,50,20,100,70,200,0,20,80,FX_DRY)
            report "Initial settings are wrong" severity failure;

        pulse_right_next;
        assert cfg.tone = 1 severity failure;

        pulse_right_press;
        assert pedal_mode = '1' and cfg.tone = 1
            report "Timbre focus press did not enter pedal mode"
            severity failure;
        pulse_right_next;
        assert cfg.tone = 2
            report "Pedal mode right rotation did not change timbre"
            severity failure;
        pulse_left_next;
        assert focus = FOCUS_VOLUME severity failure;
        pulse_right_next;
        assert cfg.tone = 3 and cfg.volume = 50
            report "Pedal mode right rotation changed a non-timbre parameter"
            severity failure;
        pulse_right_press;
        assert pedal_mode = '0'
            report "Second right press did not exit pedal mode"
            severity failure;
        pulse_left_prev;
        assert focus = FOCUS_TIMBRE severity failure;

        pulse_left_next;
        assert focus = FOCUS_VOLUME severity failure;
        pulse_right_next;
        assert cfg.volume = 51 severity failure;
        pulse_right_prev;
        assert cfg.volume = 50 severity failure;

        pulse_left_next;
        assert focus = FOCUS_ATTACK severity failure;
        pulse_right_next;
        assert cfg.attack_ms = 30 severity failure;
        pulse_right_press;
        assert cfg.attack_ms = 20 and status = STATUS_RESET
            report "Reset selected parameter failed" severity failure;

        pulse_left_press;
        assert preview = PREVIEW_SPECTRUM severity failure;
        pulse_left_press;
        assert preview = PREVIEW_LISSAJOUS severity failure;
        pulse_left_press;
        assert preview = PREVIEW_PRESSURE severity failure;
        pulse_left_press;
        assert preview = PREVIEW_ENVELOPE severity failure;
        pulse_left_press;
        assert preview = PREVIEW_AUDIO severity failure;

        pulse_left_next;
        assert focus = FOCUS_DECAY severity failure;
        pulse_left_next;
        assert focus = FOCUS_SUSTAIN severity failure;
        pulse_left_next;
        assert focus = FOCUS_RELEASE severity failure;
        pulse_left_next;
        assert focus = FOCUS_BEND severity failure;

        pulse_right_next;
        assert cfg.bend_cents = 10 severity failure;
        for i in 1 to 25 loop
            pulse_right_next;
        end loop;
        assert cfg.bend_cents = 200
            report "Positive pitch-bend limit is wrong" severity failure;
        for i in 1 to 45 loop
            pulse_right_prev;
        end loop;
        assert cfg.bend_cents = -200
            report "Negative pitch-bend limit is wrong" severity failure;

        pulse_left_next;
        assert focus = FOCUS_VIBRATO severity failure;
        for i in 1 to 30 loop
            pulse_right_next;
        end loop;
        assert cfg.vibrato_cents = 50
            report "Vibrato limit is wrong" severity failure;

        pulse_left_next;
        assert focus = FOCUS_GLIDE severity failure;
        for i in 1 to 110 loop
            pulse_right_next;
        end loop;
        assert cfg.glide_ms = 1000
            report "Portamento limit is wrong" severity failure;

        pulse_left_next;
        assert focus = FOCUS_PLUCK severity failure;
        assert cfg.sustain = 70
            report "Pluck mode did not start from the saved sustain level"
            severity failure;
        pulse_right_next;
        assert cfg.sustain = 0
            report "Clockwise pluck control did not enable pluck mode"
            severity failure;
        pulse_right_prev;
        assert cfg.sustain = 70
            report "Counter-clockwise pluck control did not restore sustain"
            severity failure;
        pulse_right_press;
        assert cfg.sustain = 0 and status = STATUS_RESET
            report "Pluck mode toggle did not enable pluck mode"
            severity failure;
        pulse_right_press;
        assert cfg.sustain = 70
            report "Second pluck mode toggle did not restore sustain"
            severity failure;

        pulse_left_next;
        assert focus = FOCUS_EFFECT severity failure;
        pulse_right_next;
        assert cfg.effect_mode = FX_DELAY severity failure;
        pulse_right_next;
        assert cfg.effect_mode = FX_CHORUS severity failure;
        pulse_right_next;
        assert cfg.effect_mode = FX_REVERB severity failure;
        pulse_right_press;
        assert cfg.effect_mode = FX_DRY and status = STATUS_RESET
            report "Effect reset did not restore dry mode"
            severity failure;

        pulse_left_next;
        assert focus = FOCUS_OCTAVE severity failure;
        pulse_right_next;
        assert octave_shift = '1' severity failure;
        pulse_right_prev;
        assert octave_shift = '0' severity failure;
        pulse_right_next;
        pulse_right_press;
        assert octave_shift = '0'
            report "Octave reset did not return to the low position"
            severity failure;
        pulse_left_next;
        assert focus = FOCUS_TIMBRE severity failure;
        pulse_left_prev;
        assert focus = FOCUS_OCTAVE severity failure;
        pulse_left_prev;
        assert focus = FOCUS_EFFECT severity failure;
        pulse_left_prev;
        assert focus = FOCUS_PLUCK severity failure;
        pulse_left_prev;
        assert focus = FOCUS_GLIDE severity failure;
        pulse_left_prev;
        assert focus = FOCUS_VIBRATO severity failure;
        pulse_left_prev;
        assert focus = FOCUS_BEND severity failure;

        voices_idle <= '0';
        wait for 2*CLK_PERIOD;
        voices_idle <= '1';
        wait for 2*CLK_PERIOD;
        assert cfg.bend_cents = 0
            report "Pitch bend did not return to zero after all notes stopped"
            severity failure;

        assert focus = FOCUS_BEND severity failure;

        report "tb_ui_controller passed" severity note;
        wait;
    end process;
end architecture;
