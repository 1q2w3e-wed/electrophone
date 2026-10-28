# Dual-EC11 Chinese Waveform UI Design

Date: 2026-10-20

## Goal

Replace the existing multi-page, English, touch-oriented interface with a
single-screen Chinese instrument dashboard controlled only by two EC11 rotary
encoders. The screen must have a larger waveform preview, richer colors, fewer
interactions, and no touch dependency.

The waveform is a live preview derived from the current tone, volume, and ADSR
settings. It is not a capture of real audio because this project does not
currently include an oscillator, sensor input, or audio output path.

## User Interaction

The left encoder selects one of six parameters in a loop:

1. Timbre
2. Volume
3. Attack
4. Decay
5. Sustain
6. Release

The right encoder adjusts only the selected parameter:

- Timbre: sine, square, sawtooth, triangle
- Volume: 1 percent per detent
- Attack, decay, release: 10 ms per detent
- Sustain: 1 percent per detent

The left encoder press toggles the upper preview between the waveform and the
ADSR envelope. The right encoder press restores the selected parameter to its
default and shows a short confirmation message.

There are no enter, back, cancel, draft, or save interactions. Every edit is
applied immediately.

## Screen Layout

The display remains 480 x 320 pixels, landscape.

```text
+--------------------------------------------------+
| Chinese title                         focus item | 40 px
+--------------------------------------------------+
| Waveform or ADSR preview                         |
| cyan waveform, dark grid, purple envelope        | 145 px
+--------------------------+-----------------------+
| Timbre card              | Volume card           | 48 px
| orange selection border  | orange level bar      |
+--------------------------+-----------------------+
| Envelope                                         |
| A 20 ms    D 100 ms    S 70%    R 200 ms        | 75 px
| selected value highlighted with purple           |
+--------------------------------------------------+
```

Colors:

- Background: deep navy
- Waveform: cyan
- Volume: orange
- Envelope: purple
- Selection and focus: warm orange border
- Text: white and muted blue-gray

## Components

### `ui_controller`

Owns the single-screen interaction state:

- Current focus parameter
- Current preview mode
- Live settings
- Default-reset behavior
- Short status message timer

It consumes debounced EC11 step and press pulses and outputs the render state.

### `wave_preview`

Generates waveform geometry from the current settings:

- Sine wave via a compact lookup table
- Square wave
- Sawtooth wave
- Triangle wave
- ADSR envelope curve

The module is a pixel predicate or pixel-color component used by the renderer.
It must clamp all vertical coordinates to the preview panel.

### `cjk_font_rom`

Stores only the Chinese glyphs used by the interface. The glyph set includes
the title, parameter labels, timbre names, units, and reset confirmation text.
Technical abbreviations such as ADSR may remain Latin text.

### `color_ui_renderer`

Composes the fixed dashboard layout and returns RGB565 color for the current
pixel. It no longer depends on page navigation or touch coordinates.

### Top-Level

The touch driver is removed from the user interface path and is not
instantiated in the top-level design. Its source remains in the repository for
possible future use. The EC11 decoder, UI controller, renderer, and LCD driver
remain connected.

## Data Flow

```text
EC11-1 --> ec11_decoder --> ui_controller <-- ec11_decoder <-- EC11-2
                                |
                                v
                         settings + focus
                                |
                                v
color_ui_renderer <------ wave_preview
        |
        v
st7796s_display --> LCD
```

The display refreshes the top preview region for three consecutive frames,
then performs one full-frame refresh so parameter cards remain current. At the
12.5 MHz SPI setting this gives an average preview rate near 10 frame/s and a
full-dashboard rate near 2.5 frame/s. Adjacent waveform columns are connected
with short vertical segments to avoid a broken dotted trace. Each capture is
armed on the first rising zero crossing and swapped at a frame boundary, so
successive refreshes start from the same waveform phase.

## Bounds and Defaults

- Volume: 0 to 100
- Attack: 0 to 2000 ms
- Decay: 0 to 2000 ms
- Sustain: 0 to 100 percent
- Release: 0 to 5000 ms
- Timbre: one of four defined values
- Parameter selection always wraps

All values are clamped before entering the renderer.

## Verification

1. Simulate parameter focus wrapping in both directions.
2. Simulate right-encoder adjustment at lower and upper bounds.
3. Simulate preview toggle and selected-parameter reset.
4. Simulate all four waveform formulas and verify that different timbres and
   amplitudes produce different rendered pixels.
5. Simulate the ADSR curve and verify all four parameters affect its geometry.
6. Render a dashboard image and inspect Chinese labels, color contrast,
   selection feedback, and panel overlap.
7. Run Gowin synthesis, place-and-route, timing analysis, and bitstream
   generation.

## Out of Scope

- Touchscreen interaction
- Real sensor note input
- Multi-voice synthesis
- Audio output or audio sample capture
- Persistent settings across power cycles
- Partial LCD refresh

