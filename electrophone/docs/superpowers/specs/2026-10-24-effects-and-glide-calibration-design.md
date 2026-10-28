# Effects and Glide Calibration Design

Date: 2026-10-24

## Goal

Correct the portamento timing scale and add one selectable FPGA audio effect at
a time:

- 原声 (Dry)
- 延迟 (Delay)
- 合唱 (Chorus)
- 混响 (Reverb)

All labels visible to the user are Chinese. The effect algorithms operate on
the real synthesized audio and must not replay prerecorded material.

LED feedback remains out of scope.

## Audio Placement

The effect engine is placed after the 32-voice mix:

```text
32-voice synth -> audio_effects -> I2S
                              -> audio scope
                              -> spectrum analyzer
                              -> Lissajous scope
```

I2S and all visual analyzers receive the post-effect output.

## Effect Controls

Add `FOCUS_EFFECT` after `FOCUS_GLIDE` in the parameter cycle.

When effect is focused:

- Right encoder rotates through `原声 -> 延迟 -> 合唱 -> 混响 -> 原声`.
- Right encoder press restores `原声`.

The bottom parameter row expands from three to four columns:

```text
弯音    揉音    滑音    效果
+000    020     0080    原声
 CENT    CENT     MS
```

The effect value displays one of:

- `原声`
- `延迟`
- `合唱`
- `混响`

The renderer adds the required Chinese glyphs. No English effect abbreviations
are shown.

Pedal mode retains priority: right-encoder rotation in pedal mode always
changes timbre.

## Effect Modes

Only one effect algorithm is active at a time. Fixed musical parameters are
used; no additional effect parameter page is added.

### 原声

- Wet level is zero.
- Output is the unmodified mixed sample.
- No additional effect latency.

### 延迟

- Single feedback delay.
- Delay time: approximately 120 ms, or 5859 samples at 48.8 kHz.
- Feedback: approximately 0.35.
- Output uses approximately 75% dry and 35% delayed signal.
- Repeated echoes decay over time.

### 合唱

- Two modulated short-delay taps.
- Base delay: approximately 10 ms.
- Modulation rate: approximately 0.8 Hz.
- Modulation depth: approximately plus or minus 2.5 ms.
- Output uses approximately 65% dry and 45% combined chorus signal.
- The two taps use different modulation phases.

### 混响

- The shared delay RAM is divided into four taps at approximately:
  - 31 ms
  - 43 ms
  - 59 ms
  - 73 ms
- Tap outputs are gain weighted and fed back with damping.
- Feedback is limited so the tail decays to silence.
- Output uses approximately 65% dry and 45% wet reverb signal.

The simplified multi-tap feedback structure is intentionally used instead of a
large Freeverb bank so the design fits the GW5A-25.

## Shared Delay Memory

- One 8192-sample, 16-bit circular delay RAM is shared by all three effects.
- Maximum delay span is approximately 168 ms.
- Delay and Reverb perform deterministic tap reads.
- Chorus uses the same RAM with fractional/two-tap reads.
- Effect computation is time-multiplexed within the audio sample period.
- No extra audio sample rate conversion is introduced.

## Mode Transition

Changing effect mode must not produce an abrupt full-amplitude wet jump.

- On mode change, wet gain resets to zero and ramps to the new target over
  approximately 5 ms.
- Dry audio remains available during the ramp.
- Output is saturated to signed 16-bit range.
- Delay and Reverb feedback states are cleared only while their algorithm is
  inactive, so switching modes does not create an uncontrolled tail.

## Portamento Timing Correction

The current shift-only glide reaches the target much earlier than the displayed
time. Replace it with fixed-count linear interpolation.

At 48.8 kHz, use approximately 49 sample periods per millisecond.

For a non-zero glide:

- Move from the previous note's phase increment to the target increment in 32
  equal steps.
- The step interval is `(glide_ms * 49) / 32` sample clock periods.
- Interpolate linearly between the starting and target phase increments.
- Clamp the final value to the target increment.

For a zero glide:

- Jump to the target increment on the next audio sample.

Each voice stores its remaining glide steps, update interval, counter, and
direction in `voice_state_ram`.

Expected timing:

- 80 ms setting: 64 to 96 ms measured duration.
- 1000 ms setting: 800 to 1000 ms measured duration.

## Module Design

### `audio_effects`

Interface:

- `clk`, `rst_n`
- `sample_tick`
- `sample_in : signed(15 downto 0)`
- `effect_mode : effect_mode_t`
- `audio_out : signed(15 downto 0)`

The module hides delay RAM addressing, mode-specific taps, feedback, damping,
and wet-gain smoothing.

### Shared Types

`ui_types` gains:

- `effect_mode_t = (FX_DRY, FX_DELAY, FX_CHORUS, FX_REVERB)`
- `settings_t.effect_mode`
- `FOCUS_EFFECT`

The internal enum names remain English for code clarity. Only displayed labels
are Chinese.

## Resource Budget

Current implementation:

- Logic: 75%
- Registers: 24%
- DSP: 77%
- BSRAM: 70%
- Fmax: 50.175 MHz
- Setup and hold violations: 0

Expected effect additions:

- Approximately 8 to 9 BSRAM for the 8192-sample delay RAM.
- A few multipliers for fixed-point wet mixing and damping.
- Additional address and effect-state logic.

Final effects implementation after place-and-route:

- Logic: 80%
- Registers: 25%
- DSP: 90%
- BSRAM: 95%
- CLS: 93%
- Fmax: 50.107 MHz
- Setup violations: 0
- Hold violations: 0

The design must fit GW5A-25 and preserve zero setup and hold violations at
50 MHz. If it does not fit, implementation must report the exact resource or
timing gap rather than silently removing an effect.

## Verification

Glide tests:

1. Verify 0 ms jumps on the next sample.
2. Verify 80 ms reaches the target between 64 and 96 ms.
3. Verify 1000 ms reaches the target between 800 and 1000 ms.
4. Verify pitch moves monotonically between the endpoints.

Effect tests:

1. 原声 is sample-for-sample identical to the input.
2. 延迟 produces the first echo near 120 ms and decaying later echoes.
3. 合唱 output is modulated relative to the dry signal.
4. 混响 produces a multi-tap tail that eventually reaches zero.
5. All modes saturate instead of overflowing.
6. Mode changes ramp wet gain without a full-scale discontinuity.
7. Delay RAM is shared without state corruption between modes.

Integration tests:

1. I2S, audio scope, spectrum, and Lissajous receive post-effect audio.
2. UI cycle includes effect mode and uses Chinese labels.
3. The four-column bottom row has no overlap or clipping.
4. Existing 18 tests continue to pass.

Build tests:

1. Gowin synthesis and place-and-route succeed.
2. Design fits GW5A-25.
3. Setup and hold violations remain zero at 50 MHz.
4. Final bitstream is regenerated.

## Out of Scope

- LED performance feedback
- Simultaneous Delay, Chorus, and Reverb stacking
- Adjustable delay time, feedback, chorus rate, or reverb decay
- External audio input
- Recorded PCM playback
- Stereo-specific effect processing
