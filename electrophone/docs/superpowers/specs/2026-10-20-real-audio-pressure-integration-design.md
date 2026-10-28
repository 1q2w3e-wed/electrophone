# Real Audio and Eight-Pressure Integration Design

Date: 2026-10-20

The eight-voice limitation in this document is superseded by
`2026-10-23-32-voice-latched-polyphony-design.md`. The eight pressure inputs
remain unchanged.

## Goal

Merge the existing ST7796S/dual-EC11 interface project with the MCP3008/I2S
synthesizer project, extend sensor support from four to eight channels, and use
the final mixed audio sample as the default waveform source.

The existing EC11 settings must affect the actual synthesizer. The waveform
panel must no longer be limited to a formula-generated preview.

## Confirmed Modes

The left encoder press cycles three preview modes:

1. Real mixed-audio waveform
2. Eight pressure channels
3. ADSR envelope

Real mixed-audio waveform is the default.

## Top-Level Hardware

The merged project keeps the existing LCD and EC11 pins and adds:

- MCP3008: `spi_clk=J7`, `spi_din=K7`, `spi_dout=L8`, `spi_cs_n=L7`
- MAX98357A I2S: `i2s_lrclk=L10`, `i2s_bclk=K10`, `i2s_din=K9`
- Board reset input: `rst_n=H11`

These pins do not overlap the LCD pins or the two EC11 interfaces.

## Components

### `mcp3008_reader`

Extracts the tested MCP3008 SPI reader from the existing synthesizer project.
It scans channels 0 through 7 in sequence.

The existing two-stage ON/OFF threshold behavior is retained for each channel.
Raw 10-bit ADC values are also published for the pressure display.

### `synth_engine`

Owns eight independent voices:

- Phase accumulator and waveform lookup per voice
- Sensor-pressure amplitude per voice
- ADSR state and level per voice
- Shared selected timbre
- Shared master volume
- Per-sample mixing with saturation

The shared controls come from `ui_controller`. The pressure value controls the
per-voice expression amount. The ADSR controls the note envelope.

The engine produces one signed 16-bit `mixed_sample` and a 48.8 kHz
`sample_tick`.

### `audio_scope`

Stores recent mixed samples in two 512-sample banks.

- Capture writes one bank while the display reads the other.
- LCD frame start switches banks.
- The display window represents approximately 10.5 ms at 48.8 kHz.
- The display maps 480 waveform pixels across the captured window without
  modifying capture.

This prevents ring-buffer overwrite while a full LCD frame is being generated.

### `wave_preview`

The existing fixed-formula waveform mode is replaced with three display modes:

- Audio: signed sample amplitude to vertical pixel
- Pressure: eight labeled level bars
- Envelope: existing ADSR visualization

All modes use the existing three-stage display pipeline.

### `ui_controller`

The controller continues to own parameter focus and values. The left press
cycles three preview modes instead of toggling two.

The settings output feeds the synthesizer engine as well as the renderer.

## Data Flow

```text
MCP3008 CH0..CH7 --> ADC scanner --> pressure levels/raw values
                                      |             |
                                      v             v
EC11 settings -----------------> synth engine   pressure view
                                      |
                              mixed 48.8 kHz sample
                                      |
                                      v
                                audio_scope
                                      |
                                      v
                              UI renderer --> LCD

synth engine --> I2S transmitter --> MAX98357A
```

## Timing and Update Rates

- System clock: 50 MHz
- Audio sample rate: approximately 48.8 kHz
- ADC poll interval: approximately 8.6 kHz per channel
- Full eight-channel ADC sweep: approximately 0.93 ms
- LCD full-frame update: approximately 2.5 frames/s

The audio scope captures a stable 10.5 ms window per LCD frame. A future partial
LCD refresh may increase visual update smoothness but is not required for this
integration.

## Resource Constraints

Eight voices add phase accumulators, waveform lookup, ADSR state, gain
multipliers, and mixing logic. The design must fit the GW5A-25 device without
using latches, and must close timing at 50 MHz.

If eight full ADSR voices do not fit, the implementation must stop and report
the concrete resource or timing failure rather than silently reducing the voice
count.

## Verification

1. Extend MCP3008 tests to verify sequential scans of CH0 through CH7.
2. Verify raw channel values are stored in the correct eight-element array.
3. Verify one active sensor, two active sensors, and all eight active sensors
   produce the expected mixed audio behavior.
4. Verify pressure changes modify the corresponding voice amplitude.
5. Verify EC11 timbre, volume, and ADSR settings reach the synthesizer.
6. Verify the audio scope bank switch and stable 480-sample read window.
7. Verify worst-case pressure-to-audio latency is at most 10 ms.
8. Render synthetic audio and pressure screenshots and inspect labels and bars.
9. Run controller, ADC, synthesizer, scope, renderer, LCD, and integration
   simulations.
10. Run Gowin synthesis, place-and-route, and timing analysis at 50 MHz.

## Out of Scope

- 32 independent note generators
- MIDI input
- Recorded external audio input
- Persistent settings across power cycles
- Partial LCD refresh
- Touchscreen interaction

