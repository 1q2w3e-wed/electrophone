# 32-Voice Latched Polyphony Design

Date: 2026-10-23

## Goal

Extend the existing eight-voice FPGA synthesizer to at least 32 simultaneous
independent voices while preserving playability on the eight pressure inputs.

The new performance mode behaves like a piano sustain pedal:

- Enter the mode by pressing the right encoder while the timbre parameter is
  selected.
- Every pressure-key attack allocates a new voice.
- Releasing a pressure key does not release its voice while the mode is active.
- Pressing the same pressure key again allocates another voice at the same
  pitch.
- Each voice captures the timbre selected when that voice was triggered.
- Turning the right encoder changes only the timbre of future voices.
- Pressing the right encoder again exits the mode and releases all voices that
  are currently being held only by the pedal.

The feature must produce at least 32 active independent oscillators, each with
its own phase accumulator, frequency control, envelope, pressure amplitude,
timbre, and allocation age.

## Current Context

The current engine has eight direct sensor-to-voice paths. Its one shared
per-sample processing pipeline loops over voices 0 through 7 and completes in
less than one 48.8 kHz sample period.

The current GW5A-25 implementation uses:

- 38% logic
- 14% registers
- 40% DSP
- 11% BSRAM

The audio pipeline is time-multiplexed, so increasing the voice count to 32
primarily increases state storage and multiplexing logic. It does not require
replicating the waveform lookup and mixing arithmetic 32 times.

## Voice Lifecycle

The engine owns a fixed pool of 32 voices. A voice is in one of four states:

1. `FREE`: the slot can be allocated.
2. `HELD`: its pressure input is physically active.
3. `LATCHED`: its pressure input was released, but pedal mode keeps it
   sounding.
4. `RELEASE`: it is in the ADSR release phase and will become `FREE` after its
   envelope reaches zero.

On a pressure-key rising edge:

- Allocate the oldest occupied slot if all 32 slots are occupied.
- Set the new voice's note from the sensor index.
- Capture the current pressure value as its initial pressure amplitude.
- Capture the currently selected timbre.
- Capture a new allocation age.
- Initialize its phase, pitch increment, and ADSR state.
- Enter `HELD`.

On a pressure-key falling edge:

- In normal mode, enter `RELEASE`.
- In pedal mode, enter `LATCHED` and retain the last pressure amplitude.

When pedal mode is disabled:

- Every `LATCHED` voice enters `RELEASE`.
- Every `HELD` voice remains held until its physical key is released.

The last pressure amplitude is held for the entire `LATCHED` state. The
pressure input returning to zero must not mute a latched voice.

## Voice Stealing

Each note attack increments a wrapping allocation-age counter. When all 32
voices are occupied, the allocator selects the voice with the largest age
distance from the current counter and replaces it with the new voice.

Replacement is immediate. The new voice starts its normal attack from zero
gain. No additional voice is created during the replacement, so the active
voice count never exceeds 32.

If a voice is already in `RELEASE`, its release tail is still part of the
32-slot pool until the envelope reaches zero.

## Timbre Ownership

Timbre is captured per voice at note-on. Changing the selected timbre does not
modify voices already in `HELD`, `LATCHED`, or `RELEASE`.

The waveform calculation accepts the selected voice's captured timbre rather
than the current global settings value. This preserves the distinction between
an old instrument sound and a newly added instrument sound.

## UI Behavior

Normal mode keeps the current controls unchanged except when the focused
parameter is timbre:

- Focus timbre and press the right encoder: enter pedal mode.
- Other right-encoder presses retain their existing reset-to-default behavior.

While pedal mode is active:

- Right encoder rotation changes the selected timbre.
- Right encoder press exits pedal mode.
- Left encoder rotation and press retain their existing parameter-selection and
  preview-selection behavior.

The dashboard shows the mode and active voice count:

```text
Pedal ON   12/32
```

When the mode is off, it shows:

```text
Pedal OFF
```

The voice count includes `HELD`, `LATCHED`, and `RELEASE` voices.

## Module Design

### `voice_allocator`

Add a dedicated `voice_allocator` module. It owns:

- Pressure-key edge detection
- Voice-slot allocation
- Held/latched/release ownership
- Per-voice pressure capture
- Per-voice timbre capture
- Allocation-age tracking and oldest-voice stealing
- Active voice count

Its interface exposes held/trigger masks, a read port for one voice's captured
metadata, and the active count needed by the audio engine and UI. It also
accepts a 32-bit `voice_done` pulse from the synthesizer when an envelope
reaches idle; that pulse frees the corresponding slot. Allocation behavior is
tested through this interface without inspecting internal slot registers.

### `synth_engine`

The synthesizer changes from eight voice slots to 32 voice slots. It owns:

- 32 phase accumulators
- 32 current and target pitch increments
- 32 ADSR states and envelope levels
- 32 pressure-amplitude states
- 32 captured timbre values
- 32 per-sample voice contributions

Per-voice phase, pitch, envelope, expression, state, and captured timbre are
stored in `voice_state_ram`. The synthesizer reads and writes one voice record
per sample using a synchronous simple dual-port RAM.

### `voice_state_ram`

The wide 32-entry voice-state RAM maps to BSRAM in the GW5A device. It provides
one synchronous read port and one write port and is separate from the waveform
lookup table.

The phase accumulator advances for every non-idle voice, including `RELEASE`.
This also fixes the existing release-tail defect where phase motion stopped as
soon as the pressure input was released.

Global pitch bend, vibrato, portamento, master volume, and ADSR settings remain
shared. Only timbre and pressure amplitude are captured per voice.

### `ui_controller`

The controller owns the pedal-mode state and toggles it according to the
encoder rules above. It exports the mode to the renderer and synthesizer.

### `color_ui_renderer`

The renderer displays pedal mode and active voice count. The rest of the
dashboard layout remains unchanged.

## Data Flow

```text
8 pressure inputs
        |
        v
voice_allocator ---- latch mode / selected timbre
        |
        | 32 x (note, pressure, timbre, gate, trigger)
        v
synth_engine -> mixed 48.8 kHz sample -> I2S / audio scope
        |
        +---- 32-bit voice_done feedback -> voice_allocator
        |
        +---- active voice count -------------------+
                                                     |
ui_controller <---- encoder input                   |
        |                                            |
        +---- latch mode / settings -> renderer <----+
                                      |
                                      v
                                    LCD
```

## Timing and Mixing

The sample period is approximately 1024 system clocks at 50 MHz. The pipelined
per-voice path uses 11 stages including the synchronous RAM read wait, so 32
voices require about 352 clocks plus final mixing. This leaves substantial
timing margin inside each sample period.

The mix accumulator is widened to accommodate 32 full-scale voices. The
normalizer scales the master output by the current active voice count so that
32 simultaneous voices remain inside the signed 16-bit output range.

The 48.8 kHz sample rate and the measured pressure-to-audio latency of less
than 10 ms must remain unchanged.

## Verification

Allocation behavior is verified through the `voice_allocator` interface:

1. A held key remains held while its pressure input is active.
2. A released key enters release in normal mode.
3. A released key remains audible in pedal mode.
4. A held key keeps its last pressure while latched.
5. Repeated attacks on the same pressure key allocate distinct voices.
6. A voice captures the timbre that was selected at its attack.
7. Changing timbre affects only subsequent attacks.
8. Disabling pedal mode releases latched voices but not physically held keys.
9. Thirty-two attacks occupy 32 slots.
10. A 33rd attack steals the oldest occupied slot and leaves the count at 32.

Synthesizer integration tests verify:

1. Thirty-two voices produce a non-zero, non-clipping mix.
2. The active voice count reaches 32.
3. A latched voice remains audible after its pressure input returns to zero.
4. Two same-pitch latched voices remain active simultaneously.
5. An old latched voice keeps its original waveform after the selected timbre
   changes.
6. Release phases continue advancing phase and eventually become idle.
7. Pressure-to-audio latency remains at most 10 ms.
8. Existing ADC, noise, pitch-expression, UI, scope, I2S, dashboard, and LCD
   tests continue to pass.

Build verification requires:

1. Successful Gowin synthesis, place-and-route, and bitstream generation for
   GW5A-25.
2. No setup or hold timing violations at 50 MHz.
3. The documented resource usage and resulting Fmax are updated from the
   generated report.

If the 32-voice design does not fit or does not close timing, implementation
must stop and report the exact resource or timing failure. The voice count must
not be silently reduced.

The implemented build uses 46% logic, 17% registers, 40% DSP, and 22% BSRAM.
The final place-and-route report has zero setup and hold violations and an
actual Fmax of 51.242 MHz at the 50 MHz constraint.

## Out of Scope

- More than eight distinct physical note positions
- Per-voice pitch bend or per-voice vibrato depth
- Per-voice ADSR settings
- Audio effects such as reverb, delay, or chorus
- Persistent pedal mode or settings across power cycles
- A fixed multi-frequency competition test mode
- Hardware latency measurement
