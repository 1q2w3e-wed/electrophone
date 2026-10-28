# 32-Voice Latched Polyphony Implementation Plan

Date: 2026-10-23

Design:
`docs/superpowers/specs/2026-10-23-32-voice-latched-polyphony-design.md`

## Success Criteria

- More than 32 independent voices are **not** implemented; the fixed pool is
  exactly 32.
- Thirty-two active voices can be created through repeated pressure attacks.
- Pedal mode holds released voices and preserves their last pressure and
  trigger-time timbre.
- Disabling pedal mode releases pedal-held voices while leaving physically
  held keys active.
- The UI shows pedal mode and active voice count.
- The mix does not clip at 32 voices.
- Pressure-to-audio simulation latency remains at most 10 ms.
- All existing tests pass.
- Gowin synthesis, place-and-route, bitstream generation, and 50 MHz timing
  analysis pass without reducing the voice count.

## Stage 1: Voice Pool and Allocator

1. Add shared 32-voice constants, indices, and array types.
2. Add `tb_voice_allocator.vhd` covering:
   - normal press/release ownership
   - pedal release retention
   - last-pressure retention
   - trigger-time timbre retention
   - same-note stacking
   - 32 active voices
   - 33rd-note oldest-voice stealing
   - pedal-off release behavior
   - `voice_done` slot recycling
3. Run the test and confirm it fails because the allocator does not exist.
4. Add `voice_allocator.vhd` with the smallest interface that satisfies the
   test.
5. Run the allocator test to green.

Verification:

- `tb_voice_allocator` passes.
- No source outside the new types, allocator, and its test changes in this
  stage.

## Stage 2: Thirty-Two-Voice Synthesizer

1. Extend synth stage arrays from eight to 32 voices.
2. Consume allocator voice controls instead of direct sensor-to-slot mapping.
3. Capture per-voice timbre.
4. Advance phase during held, latched, and release states.
5. Return `voice_done` pulses when envelopes reach idle.
6. Widen mix accumulation and normalization for 32 voices.
7. Add synthesizer tests for:
   - 32 simultaneous non-clipping voices
   - latched voice continuing after input release
   - two same-pitch latched voices
   - old voice retaining its timbre after a global timbre change
   - release phase continuing and eventually freeing its slot
8. Update existing synth, headroom, smoothing, pitch, and latency tests for the
   new interface.

Verification:

- New and existing synth tests pass.
- `tb_input_latency` still passes at or below 10 ms.

## Stage 3: Pedal UI and Dashboard

1. Add pedal state to `ui_controller`.
2. Toggle pedal mode on right-encoder press while timbre is focused.
3. Keep right-encoder timbre adjustment and pedal exit behavior active while in
   pedal mode.
4. Add controller tests for entering, changing timbre, and exiting.
5. Add pedal state and active voice count ports to the renderer.
6. Show `PEDAL ON xx/32` or `PEDAL OFF`.
7. Update dashboard tests and rendered snapshots.

Verification:

- UI and dashboard tests pass.
- The rendered display has no overlapping or clipped text.

## Stage 4: Top-Level Integration and Regression

1. Add new source and test files to the Gowin project as required.
2. Wire pressure inputs, allocator, synthesizer, controller, and renderer.
3. Analyze and run all current and new GHDL tests.
4. Run Gowin synthesis, place-and-route, and timing analysis.
5. Update README and design timing/resource documentation from measured output.
6. Inspect the final dashboard image.

Verification:

- Full GHDL regression passes.
- Gowin build succeeds and generates `electrophone.fs`.
- Setup and hold violations are zero at 50 MHz.
- The 32-voice implementation fits GW5A-25.
