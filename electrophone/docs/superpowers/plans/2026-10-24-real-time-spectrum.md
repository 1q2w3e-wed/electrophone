# Real-Time Spectrum Implementation Plan

Date: 2026-10-24

Design:
`docs/superpowers/specs/2026-10-24-real-time-spectrum-design.md`

## Success Criteria

- A 2048-point fixed-point FFT analyzes the real mixed-audio sample stream.
- The display shows bins corresponding to approximately 200 to 1400 Hz.
- Known single- and dual-tone inputs produce the expected separated spectral
  peaks.
- Eight-tone input produces the expected visible FFT lobes plus all eight
  fundamental markers. Adjacent notes may merge in the raw 2048-point FFT.
- The spectrum view overlays active-fundamental markers without hiding the
  real FFT bars.
- Existing waveform, pressure, ADSR, pedal, 32-voice, ADC, I2S, and display
  behavior remains intact.
- GW5A-25 fits the implementation with zero setup and hold violations at
  50 MHz.
- LED feedback remains unimplemented. Lissajous is deferred to a later cycle.

## Stage 1: Spectrum Tables and FFT Interface

1. Add a table generator for Hann coefficients and FFT twiddle factors.
2. Generate VHDL ROM tables.
3. Add `tb_spectrum_analyzer.vhd` at the public analyzer seam.
4. Test a 262 Hz sine and confirm the dominant peak is near FFT bin 11.
5. Run the test and confirm it fails because the analyzer does not exist.

Verification:

- Generated tables analyze without hand-edited binary data.
- The new test fails only because the analyzer implementation is absent.

## Stage 2: Capture and 2048-Point FFT

1. Add `spectrum_analyzer.vhd`.
2. Capture 2048 samples at the existing audio sample rate.
3. Apply Hann windowing and bit-reversed storage.
4. Implement the 11-stage radix-2 FFT with a time-multiplexed butterfly.
5. Produce 8-bit logarithmic display levels for bins 8 through 59.
6. Publish completed frames through double-buffered output banks.
7. Make the single-tone test pass.

Verification:

- Single-tone peak bin and timing pass.
- FFT output does not disturb the audio pipeline.

## Stage 3: Multi-Tone Spectrum Tests

1. Add a two-tone C4/E4 test and verify two local maxima.
2. Add all eight base-frequency tones and verify multiple separated FFT lobes
   while accepting physically adjacent lobes.
3. Add silence and confirm zero display energy.
4. Add a bank-switch test confirming that a partially-written frame is not
   visible.

Verification:

- Spectrum tests describe public analyzer behavior and pass.

## Stage 4: Fundamental Markers

1. Extend the allocator with an 8-bit active-note bitmap.
2. Increment and decrement per-note active counts as voices allocate, finish,
   or are stolen.
3. Add allocator marker tests.

Verification:

- Duplicate same-pitch voices produce one marker.
- The marker clears after the last same-pitch voice becomes idle.

## Stage 5: Spectrum UI

1. Add `PREVIEW_SPECTRUM` to shared UI types.
2. Extend the controller preview cycle.
3. Add spectrum bars, frequency labels, grid, and marker rendering.
4. Wire analyzer output and note mask through the renderer and top level.
5. Add controller and dashboard tests.

Verification:

- Preview cycling is correct.
- A rendered spectrum screenshot with eight markers has no overlap or text
  clipping.

## Stage 6: Integration and Build

1. Add all new source files to the Gowin project.
2. Run the complete GHDL regression.
3. Run Gowin synthesis, place-and-route, timing analysis, and bitstream
   generation.
4. Inspect resource and timing reports.
5. Update README with measured resource, Fmax, and spectrum behavior.

Verification:

- Full regression passes.
- Register, DSP, and BSRAM usage remain within GW5A-25.
- Setup and hold violations are zero at 50 MHz.
- Final `electrophone.fs` is generated.
