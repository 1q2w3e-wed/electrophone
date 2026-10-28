# Real-Time Lissajous Display Design

Date: 2026-10-24

## Goal

Add a real-time Lissajous-style XY preview driven by the existing mixed audio.

The display uses the current audio sample as X and a delayed copy of the same
audio as Y. It must remain responsive, visible at different volume levels, and
integrate with the existing waveform, spectrum, pressure, and ADSR previews.

LED feedback is out of scope.

## Confirmed Behavior

- X is the current `mixed_sample`.
- Y is the same audio delayed by 48 samples.
- At approximately 48.8 kHz, the delay is about 0.98 ms, close to one quarter
  period at C4.
- Capture approximately 1024 XY points per frame, a window of about 21 ms.
- Draw a centered 96 by 96 pixel XY plot.
- Draw a cyan trace, dim grid, and visible center axes.
- Use automatic display gain based on the previous frame's peak amplitude.
- Trajectory points are drawn as small crosses to reduce visual gaps.
- Each frame replaces the previous trace; no long persistence trail is added.
- Add the view to the left-encoder preview cycle:
  `Audio -> Spectrum -> Lissajous -> Pressure -> Envelope -> Audio`.

## Audio Path

The Lissajous scope is a read-only observer of `mixed_sample`. It does not alter
the synthesizer, ADSR, pitch expression, I2S transmitter, or audio scope.

No prerecorded signal or synthetic animation is used.

## Module Interface

Add `lissajous_scope` with this interface:

- `clk`, `rst_n`
- `sample_tick`
- `sample_in : signed(15 downto 0)`
- `display_latch : std_logic`
- `read_x, read_y : natural range 0 to 95`
- `pixel_o : std_logic`
- `frame_ready : std_logic`

The top level maps LCD plot coordinates to `read_x` and `read_y`. The renderer
uses `pixel_o` to decide whether a plot pixel is part of the trace.

## Delay Line

- Keep a 48-entry signed 16-bit circular history buffer.
- Y is read from the oldest history entry when a new sample arrives.
- X and Y are captured into the active frame together.
- Reset clears the history buffer.

The delay line is display data only and never feeds the audio output.

## Point Frame

- Capture 1024 consecutive XY pairs at the existing sample rate.
- Convert each pair to 0 through 95 display coordinates.
- Draw a three-pixel horizontal and vertical cross around each point.
- Points outside the plot are clipped.
- The frame completes after all 1024 samples have been processed.
- Capture can restart immediately in the inactive drawing bank while the
  previously completed frame remains visible.

## Automatic Gain

- Track the maximum absolute X or Y value in each captured frame.
- Save that peak for use by the next frame.
- Select an integer left shift for display:
  - Small signals receive additional gain.
  - Larger signals use less gain.
- Saturate the shifted value to the signed 16-bit display range.
- Apply the same gain to X and Y so the plotted shape is not distorted.
- Gain never changes audio or the spectrum analyzer.

The one-frame adaptation delay is intentional and avoids a full frame pre-scan.

## Double Buffering

Use two 96 by 96 one-bit bitmap banks.

- While bank A is displayed, bank B is cleared and filled.
- On `display_latch`, switch to a completed bank if a new frame is ready.
- Never expose a bitmap that is currently being cleared or drawn.
- The first frame displays the center axes and an empty trace until capture
  completes.

## UI and Rendering

`ui_types` gains `PREVIEW_LISSAJOUS`.

The plot is centered in the existing preview panel:

- Plot X range: 192 through 287
- Plot Y range: 56 through 151

The renderer draws:

- Dim background grid.
- Center vertical and horizontal axes.
- Cyan trace pixels from `lissajous_scope`.
- A small title identifying the XY/Lissajous view.

The header continues to show pedal mode and active voice count.

## Timing and Resource Budget

Current spectrum-enabled implementation:

- Logic: 74%
- Registers: 23%
- DSP: 74%
- BSRAM: 40%
- Fmax: 50.050 MHz
- Setup and hold violations: 0

Expected additions:

- Two 96 by 96 bitmap banks, approximately 2 to 3 BSRAM blocks.
- One 48-entry delay line.
- Address, gain, and rendering logic.
- No additional audio multipliers.

Final Lissajous implementation after place-and-route:

- Logic: 75%
- Registers: 24%
- DSP: 77%
- BSRAM: 70%
- Fmax: 50.175 MHz
- Setup violations: 0
- Hold violations: 0

The full design must remain inside GW5A-25 and retain zero setup and hold
violations at 50 MHz.

If resource or timing closure fails, implementation must report the exact gap.
It must not reduce the bitmap resolution or remove automatic gain without user
approval.

## Verification

Module tests:

1. A 262 Hz sine produces a visible closed XY trajectory.
2. A low-amplitude sine uses automatic gain and remains visibly sized.
3. Silence clears the next completed frame.
4. The delay line produces a phase offset near 90 degrees at C4.
5. Display bank switching never exposes a partially cleared frame.
6. Out-of-range coordinates are clipped.

UI tests:

1. The controller cycle includes Audio, Spectrum, Lissajous, Pressure, and
   Envelope in the confirmed order.
2. A rendered Lissajous screenshot shows centered axes, a visible trace, and no
   overlap with the header or lower cards.
3. Existing spectrum bars and fundamental markers remain unchanged.

Regression and build:

1. All existing 17 tests continue to pass.
2. New Lissajous tests pass.
3. Gowin synthesis and place-and-route succeed.
4. The design fits GW5A-25.
5. Setup and hold violations remain zero at 50 MHz.
6. The final bitstream is regenerated.

## Out of Scope

- LED performance feedback
- Separate left/right audio groups for true two-source XY plotting
- Long-persistence phosphor trails
- User-adjustable gain or plot scale
- Full-screen Lissajous rendering
- Changes to the I2S stereo output
