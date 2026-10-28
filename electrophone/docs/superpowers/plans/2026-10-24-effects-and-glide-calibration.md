# Effects and Glide Calibration Implementation Plan

Date: 2026-10-24

Design:
`docs/superpowers/specs/2026-10-24-effects-and-glide-calibration-design.md`

## Success Criteria

- Portamento reaches its target in the configured 80 ms and 1000 ms ranges.
- One selectable effect is active at a time: 原声, 延迟, 合唱, 混响.
- All displayed effect labels are Chinese.
- I2S and every visual analyzer consume post-effect audio.
- Existing synthesis, 32-voice, pedal, spectrum, and Lissajous behavior remains
  intact.
- GW5A-25 fits the design with zero setup and hold violations at 50 MHz.

## Stage 1: Glide Timing

1. Add duration-focused pitch tests for 0, 80, and 1000 ms.
2. Confirm the current shift-only implementation fails the 80/1000 ms checks.
3. Extend each voice state with glide interpolation state.
4. Implement 32-step linear interpolation with the configured sample interval.
5. Make duration and monotonicity tests pass.

Verification:

- Existing pitch-expression tests and new duration tests pass.

## Stage 2: Effect Engine

1. Add `tb_audio_effects.vhd` at the public effect seam.
2. Test 原声 passthrough, 延迟 echoes, 合唱 modulation, 混响 tail, saturation,
   and mode smoothing.
3. Add a shared 8192-sample delay RAM.
4. Add fixed Delay, Chorus, and Reverb algorithms.
5. Add wet-gain ramp and safe mode changes.
6. Make effect tests pass.

Verification:

- Each effect produces its intended post-processing behavior.

## Stage 3: Chinese Effect UI

1. Add the effect enum and setting to shared types.
2. Add `FOCUS_EFFECT` after glide.
3. Update the controller cycle and reset behavior.
4. Expand the bottom row to four columns.
5. Add Chinese glyphs and labels:
   原声, 延迟, 合唱, 混响, 效果.
6. Add controller and dashboard tests.

Verification:

- All effect labels are Chinese and the four-column layout does not overlap.

## Stage 4: Audio Integration

1. Insert `audio_effects` between the synthesizer mix and downstream consumers.
2. Route post-effect audio to I2S, audio scope, spectrum, and Lissajous.
3. Update integration tests and screenshots.

Verification:

- All analyzers observe the final audio signal.

## Stage 5: Full Regression and Build

1. Run all GHDL tests.
2. Run Gowin synthesis, place-and-route, and timing analysis.
3. Inspect logic, DSP, BSRAM, CLS, and Fmax.
4. Update README and design metrics.

Verification:

- Full regression passes.
- GW5A-25 resources fit.
- Setup and hold violations are zero.
- Final bitstream is generated.
