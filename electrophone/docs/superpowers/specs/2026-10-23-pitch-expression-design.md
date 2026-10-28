# Real-Time Pitch Expression Design

Date: 2026-10-23

## Goal

Add real-time pitch bend, vibrato, and portamento to the existing eight-voice
FPGA synthesizer using the current two EC11 encoders and no additional
hardware.

The feature must change oscillator phase increments while notes are sounding,
not merely display different values on screen.

## Controls

The left encoder cycles nine parameters:

1. Timbre
2. Volume
3. Attack
4. Decay
5. Sustain
6. Release
7. Pitch bend
8. Vibrato depth
9. Portamento time

The right encoder adjusts the selected parameter. The right encoder press
continues to restore the selected parameter's default. The left encoder press
continues to cycle the audio, pressure, and envelope previews.

Parameter limits and steps:

- Pitch bend: -200 to +200 cents, 10 cents per step
- Vibrato depth: 0 to 50 cents, 2 cents per step
- Portamento: 0 to 1000 ms, 10 ms per step

Defaults:

- Pitch bend: 0 cents
- Vibrato depth: 20 cents
- Portamento time: 80 ms

Pitch bend returns to zero automatically after all eight voices become idle.

## Screen

The waveform preview is reduced slightly in height. A compact expression row is
added below the ADSR values:

```text
Pitch bend   Vibrato depth   Portamento
+000 cent    020 cent        080 ms
```

The selected expression field is highlighted using the existing focus colors.
The rest of the Chinese dashboard remains unchanged.

## Audio Architecture

### Pitch modulation

The fixed phase increment for each note remains the base pitch. A global pitch
factor is applied to that increment:

```text
current phase increment =
    glide-adjusted base increment * pitch factor
```

The pitch factor is selected from a lookup table covering the combined
-250 to +250 cent range. This range contains:

- +/-200 cents of pitch bend
- +/-50 cents of vibrato

### Vibrato LFO

A global 5.5 Hz phase accumulator drives a sine lookup. The LFO output is
scaled by the selected vibrato depth in cents and added to the bend amount.

The LFO begins at phase zero after reset and runs continuously. It is only
audible when at least one voice is producing sound and vibrato depth is nonzero.

### Portamento

Each voice stores its current phase increment. On a note-on event, the starting
increment is the most recently played voice's increment and the target is the
new note's fixed increment.

The current increment moves toward the target over the configured portamento
time. Zero milliseconds selects immediate pitch change. Portamento affects pitch
only and does not modify ADSR.

### Bend return

The bend value is independent from phase accumulation. When all voices have
entered the idle state and no sensor is pressed, the stored bend parameter is
reset to zero.

## Data Model

`settings_t` gains:

- `bend_cents : integer range -200 to 200`
- `vibrato_cents : natural range 0 to 50`
- `glide_ms : natural range 0 to 1000`

`focus_t` gains:

- `FOCUS_BEND`
- `FOCUS_VIBRATO`
- `FOCUS_GLIDE`

All settings literals in RTL and test benches must be updated consistently.

## Safety and Bounds

- Combined bend and vibrato cents are clipped to -250 to +250 before lookup.
- Pitch factors are positive and constrained so phase increments cannot wrap
  unexpectedly.
- Glide remains within the range from the previous increment to target.
- Bend resets only after all notes are idle; it cannot remain stuck after a
  performance.
- Existing expression smoothing, polyphony normalization, and saturation remain
  active.

## Verification

1. Verify controller focus cycling across all nine parameters.
2. Verify bend range, step size, vibrato depth range, and portamento range.
3. Verify all-notes-idle bend auto-return.
4. Measure synthesized frequency before and after a bend change.
5. Verify vibrato creates periodic frequency modulation.
6. Verify portamento changes frequency continuously over multiple samples.
7. Verify zero portamento produces an immediate frequency change.
8. Re-run single-note, eight-voice headroom, silence, pressure-smoothing, audio
   scope, I2S, renderer, and LCD tests.
9. Complete Gowin synthesis, place-and-route, and 50 MHz timing analysis.

## Out of Scope

- MIDI pitch-wheel hardware
- Polyphonic per-note bend from independent physical controls
- Pitch modulation from sensor sliding gestures
- Additional oscillators or effects processors
- Persistent settings across power cycles

