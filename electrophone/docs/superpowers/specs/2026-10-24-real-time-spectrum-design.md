# Real-Time 2048-Point Spectrum Design

Date: 2026-10-24

## Goal

Add a real-time FPGA spectrum preview for the 32-voice electrophone.

The view must show the actual mixed audio spectrum, support competition
verification of multiple independent tones, and preserve the existing audio,
pedal, pressure, ADSR, and waveform functions.

LED performance feedback remains out of scope for this change. The Lissajous
view will be designed and implemented later as a separate feature.

## Confirmed Display Behavior

- Use a 2048-point FFT.
- Display a zoomed frequency range of approximately 200 to 1400 Hz.
- Render the spectrum as energy bars.
- Overlay orange markers at the fundamental frequencies of currently sounding
  voices.
- Adjacent notes may merge into one FFT energy lobe at 2048-point resolution.
  The fundamental markers, not the number of FFT lobes, identify all currently
  sounding note positions.
- Add the spectrum to the left-encoder preview cycle:
  `Audio -> Spectrum -> Pressure -> Envelope -> Audio`.
- The later Lissajous feature will be inserted between Spectrum and Pressure.
- Keep the existing pedal status and active voice count in the header.
- Label the frequency axis at approximately 200, 400, 600, 800, 1000, 1200,
  and 1400 Hz.

## Architecture

### `spectrum_analyzer`

Add a dedicated `spectrum_analyzer` module.

Interface:

- `clk`, `rst_n`
- `sample_tick`
- `sample_in : signed(15 downto 0)`
- `read_bin : natural range 0 to 63`
- `magnitude_o : unsigned(7 downto 0)`
- `frame_ready : std_logic`

The module captures real mixed-audio samples, computes a 2048-point FFT, and
updates a spectrum result buffer. It does not write to I2S and does not affect
the audio sample stream.

### Capture Path

- Capture 2048 consecutive samples at approximately 48.8 kHz.
- A new non-overlapping capture begins after the previous capture is complete.
- Capture duration is approximately 41.9 ms, giving a maximum update rate near
  23.8 frames per second.
- Store the real samples in an inferred RAM.
- Apply a Hann window before FFT processing.
- Write samples in bit-reversed order during the copy/window pass so the FFT
  does not require a separate bit-reversal traversal.

### FFT Core

- Use a radix-2 decimation-in-time FFT with 11 stages.
- Use one time-multiplexed butterfly engine rather than 1024 parallel
  butterflies.
- Store complex work data in on-chip RAM.
- Store Hann coefficients and FFT twiddle factors in generated ROM tables.
- Capture samples use signed 16-bit values, Hann and twiddle coefficients use
  Q1.15 signed values, complex work values use signed 32-bit fixed point, and
  display magnitudes use 8-bit unsigned levels.
- Use fixed-point arithmetic with explicit scaling and overflow protection at
  each stage.
- The FFT engine operates independently of the audio pipeline and can use idle
  system clocks between audio samples.

### Magnitude Path

- Compute a low-cost magnitude estimate from the real and imaginary FFT
  outputs.
- Compress magnitude using a logarithmic approximation based on the highest
  active magnitude bit plus lower fractional bits.
- Store 8-bit display levels for FFT bins 8 through 59.
- These 52 bins cover approximately 190.7 through 1406.8 Hz.

### Double Buffering

- FFT output writes the inactive display bank.
- On frame completion, switch the display read bank.
- The renderer never reads a bank while it is being updated.
- A spectrum frame remains visible until the next frame is complete.

## Fundamental Markers

`voice_allocator` adds an 8-bit `note_active_o` output.

Each bit indicates that at least one held, latched, or releasing voice is
currently using that physical note. The bit clears only after the last voice
for that note reaches idle or is stolen.

The renderer maps the eight base frequencies to horizontal positions in the
200 to 1400 Hz axis and draws thin orange markers. The real FFT bars remain the
primary spectrum data; markers only indicate the fundamental locations of
currently sounding voices.

## Audio Analyzer Input

The analyzer receives the same `mixed_sample` already sent to the I2S
transmitter and audio scope. It must not inject prerecorded data or replace the
real synthesized signal.

No microphone or external ADC is added.

## UI and Rendering

`ui_types` gains `PREVIEW_SPECTRUM`.

`ui_controller` cycles the left-encoder preview in the confirmed order.

`wave_preview` gains a spectrum mode:

- Draw a dark panel with a frequency grid.
- Draw a cyan energy bar for the current frequency pixel.
- Draw orange fundamental markers.
- Clamp bar height to the preview panel.
- Show a stable empty plot when no voices are active.

`color_ui_renderer` receives the selected spectrum magnitude and note-active
mask and passes them to the preview module.

The top level computes the spectrum bin from the current display X coordinate.
The first displayed bin is FFT bin 8 at approximately 190.7 Hz and the last is
bin 59 at approximately 1406.8 Hz. The axis labels use the nominal 200 to
1400 Hz range while preserving the actual FFT bin positions.

## Timing and Resource Budget

Current implementation before this feature:

- Logic: 46%
- Registers: 17%
- DSP: 40%
- BSRAM: 22%
- Fmax: 51.242 MHz

Expected spectrum additions:

- 8 to 10 BSRAM blocks for complex work data
- 2 to 4 BSRAM blocks for capture, window, twiddle, and output tables
- A small number of DSP multipliers for fixed-point butterfly arithmetic
- Additional address and display logic

Final spectrum implementation after place-and-route:

- Logic: 74%
- Registers: 23%
- DSP: 74%
- BSRAM: 40%
- Fmax: 50.050 MHz
- Setup violations: 0
- Hold violations: 0

The feature must fit GW5A-25 and continue to close timing at 50 MHz with zero
setup and hold violations.

If the full spectrum cannot fit or close timing, implementation must report the
specific resource or timing gap. It must not silently switch to Goertzel,
reduce the FFT size, or lower the frequency resolution without user approval.

## Verification

Spectrum module tests:

1. Capture exactly 2048 samples and assert frame completion.
2. Feed a 262 Hz sine and verify the dominant peak is near the 262 Hz bin.
3. Feed two tones near C4 and E4 and verify two separated peaks.
4. Feed all eight base frequencies and verify multiple separated FFT lobes.
   At 2048-point resolution, adjacent notes may merge; all eight notes must
   still expose eight fundamental markers through the UI.
5. Feed silence and verify all display levels return to zero.
6. Verify fixed-point output never produces invalid or out-of-range levels.
7. Verify display-bank switching does not expose a partially updated frame.

Marker and UI tests:

1. Verify held, latched, and releasing notes assert their marker bits.
2. Verify duplicate same-pitch voices keep one marker until the last voice
   becomes idle.
3. Verify pedal release and oldest-voice stealing clear markers correctly.
4. Verify the preview cycle includes Audio, Spectrum, Pressure, and Envelope.
5. Render a spectrum screenshot with eight fundamental markers and inspect:
   - frequency labels
   - bar alignment
   - marker alignment
   - no overlap with the header or bottom panels

Regression and build:

1. All existing 15 tests continue to pass.
2. New spectrum, marker, and dashboard tests pass.
3. Gowin synthesis, place-and-route, and bitstream generation succeed.
4. The final design fits GW5A-25.
5. Setup and hold violations remain zero at 50 MHz.
6. README and resource documentation are updated from measured results.

## Out of Scope

- LED performance guidance
- Lissajous display, deferred to the following feature
- Full 0 to 24.4 kHz spectrum range
- User-selectable FFT size
- Goertzel or eight-band-only spectrum mode
- External microphone input
- Recorded PCM playback
