# Android Remote Performance and Recording Readback Design

Date: 2026-10-25

## Goal

Extend the Android score application and FPGA firmware so the phone can:

- Configure the eight physical pressure-key assignments.
- Display eight configurable remote piano keys.
- Play the FPGA instrument in real time from the phone with multi-touch.
- Store a separate note, label, velocity, tone, and effect for each remote key.
- Record physical and remote performance into the FPGA event memory.
- Read the recorded events back to the phone for editing, saving, copying, and
  replay through the FPGA.

The app remains a master-score client. The FPGA remains the sole real-time audio
engine and event recorder.

## User-Approved Decisions

- Both physical-key remapping and remote-key customization are required.
- Recording includes both physical pressure-key and remote-key performance.
- Each remote key stores its own note, label, velocity, tone, and effect.
- The FPGA has one global effect processor. A remote key press selects its
  stored effect for the current mix. When effects differ, the last pressed key
  wins; already-started voices retain their original tone.
- New commands require a new FPGA bitstream and a new APK.
- A recording is returned as editable NOTE events, not as WAV audio.

## Scope

### Included

- App pages for scores, live performance, and recording.
- Eight physical-key mappings and eight remote keys.
- Multi-touch remote performance with ordered Bluetooth commands.
- FPGA virtual key input merged with mapped physical pressure input.
- Recording of the merged performance.
- Bulk upload of recorded packed events from FPGA to phone.
- NOTE editing, validation, local save, copy, and replay.
- Backward-compatible parsing of old FPGA responses without line endings.

### Not Included

- More than eight distinct FPGA note indexes, which are 0 through 7.
- More than eight simultaneously held note indexes.
- Independent simultaneous effect processors per key.
- Raw PCM/WAV recording or audio streaming over Bluetooth.
- Persisting mapping or recordings on the FPGA across power cycles.
- Apple iOS support.

## App Design

The existing single-activity app gains three top-level pages.

### Scores

The current online catalog, search, NOTE preview, save, copy, and score-send
flow remains available without changing existing behavior.

### Performance

The page contains:

- Bluetooth device selection and connection status.
- Eight physical-channel mapping rows from CH0 through CH7.
- Eight remote piano keys.
- A remote recording control: start, stop, and status.

Each physical mapping row assigns a note from 0 through 7. Each remote key has:

- A short user-defined label.
- A note from 0 through 7.
- Velocity from 0 through 31.
- Tone from 0 through 3.
- Effect from 0 through 3.

The app prevents duplicate note assignments within the physical mapping and
within the remote key set. This keeps press and release ownership unambiguous.
The same note may be assigned once to a physical channel and once to a remote
key; the two sources are merged on the FPGA.

Remote keys support multi-touch. A touch-down sends `KEY DOWN`; touch-up or
touch-cancel sends `KEY UP`. Commands are serialized through one Bluetooth
worker so they reach the FPGA in finger-action order.

On disconnect, page exit, app backgrounding, or send failure, the app sends
`KEY ALL UP` when possible and immediately marks all remote keys released in
the UI.

### Recording

The recording page contains:

- Start and stop controls.
- Retrieval progress while the FPGA streams events.
- A NOTE editor.
- Save, copy, clear, and replay controls.

Starting a new FPGA recording replaces the previous FPGA recording. The app asks
for confirmation before sending `REC START`.

After `REC STOP` succeeds, the app waits for the FPGA to finish duration
updates and automatically requests `REC DUMP`. A successful upload is converted
to editable NOTE lines. The app validates them with the existing score
validator before allowing replay.

Saved recordings use this name pattern:

```text
录音_yyyyMMdd_HHmmss.txt
```

They use the same Android Download storage as downloaded scores.

### Persistence

Physical mappings and remote key configurations are stored as versioned JSON in
Android SharedPreferences. The current catalog URL preference and catalog
behavior remain unchanged.

Configuration changes apply only after all held remote keys are released. The
app does not silently reinterpret a held key.

## Bluetooth Protocol

The FPGA continues to accept LF or CRLF command endings and remains
case-insensitive. Existing commands remain valid.

### Existing Commands

```text
PING
MAP 0,1,2,3,4,5,6,7
SCORE CLEAR
NOTE delta,duration,note,velocity,tone,effect
PLAY SCORE
STOP
REC START
REC STOP
REC PLAY
```

### New Commands

```text
VERSION
KEY DOWN note,velocity,tone,effect
KEY UP note
KEY ALL UP
REC DUMP
```

`VERSION` returns:

```text
VERSION 2
```

Older firmware returns `ERR` for `VERSION`. The app then keeps score download
and score playback available but disables remote performance and recording
readback with a clear upgrade message.

`KEY DOWN` fields:

- `note`: 0 through 7
- `velocity`: 0 through 31
- `tone`: 0 through 3
- `effect`: 0 through 3

`KEY UP` releases only the named note. `KEY ALL UP` releases all remote notes.
`STOP` also releases remote notes.

### Response Formatting

New firmware terminates every complete response line with CRLF. The new app
parses line-delimited responses and the known tokens `PONG`, `OK`, `ERR`, and
`FULL`. The existing app tolerance for unseparated legacy responses remains.

### Recording Dump

`REC DUMP` is accepted only after recording has stopped and while score playback
is inactive. Otherwise the FPGA returns the ASCII line `ERR`.

A successful dump returns a compact binary packet:

```text
A5 5A COUNT_HI COUNT_LO
<COUNT big-endian 32-bit packed events>
```

`COUNT` is the event count from 0 through 1024. The app verifies the two-byte
magic header and count before creating NOTE text. A timeout, disconnect, missing
event, or invalid magic header rejects the transfer.

The binary transport avoids per-event ASCII formatting, which exceeded the
remaining FPGA timing margin. The phone still presents editable NOTE text.

## Packed Event Format

The existing event layout is unchanged:

| Bits | Field |
|---|---|
| 31..20 | delta in milliseconds |
| 19..12 | duration in 10 ms units |
| 11..9 | note index |
| 8..4 | velocity |
| 3..2 | tone |
| 1..0 | effect |

The app decodes a packed event to:

```text
NOTE delta,duration_ms,note,velocity,tone,effect
```

The duration field is multiplied by 10 when displayed.

## FPGA Design

### Command Parser

`command_parser` adds:

- `VERSION`
- Remote key down, up, and all-up commands
- `REC DUMP` start

It continues to parse existing score and recording commands. Parameterized
responses use a line-oriented response generator rather than adding another
large command state machine.

### Remote Input State

A small `remote_input` module holds:

- Eight remote-key on bits.
- Eight remote-key pressure levels.
- Per-note tone and effect captured from the last key-down for that note.

The command parser updates this state one command at a time. This ensures remote
chords still use a new tone for each new voice and avoids interpreting the phone
as a pressure sensor.

### Input Merge

The top level creates the performance input:

```text
performance_on(note) =
    mapped_physical_on(note) OR remote_on(note)

performance_level(note) =
    max(mapped_physical_level(note), remote_level(note))
```

Score playback remains mutually exclusive with live performance. Remote input
is ignored or released while `PLAY SCORE` or `REC PLAY` is active.

### Recorder

`score_recorder` consumes the merged performance input rather than raw physical
input. On a note-on:

- Physical-only notes capture the current instrument tone/effect.
- Remote notes capture the remote key's tone/effect.
- If both sources start the same note together, the remote configuration takes
  precedence for the recorded metadata.
- Peak velocity and completed duration continue to use the existing rules.

The event RAM capacity remains 1024 events.

### Event Dump and RAM Arbitration

A dedicated `event_uploader` streams the binary header and packed event bytes
through the existing UART transmitter.

The event RAM has one synchronous read port. The top level multiplexes it as
follows:

1. The uploader owns the read port only while a dump is active.
2. Playback must be idle and recording must be stopped before a dump starts.
3. The sequencer otherwise owns the read port as it does today.

The uploader uses the existing event RAM and adds no BSRAM.

The parser and uploader share the UART transmitter through an explicit
arbiter. The uploader owns TX for the entire dump sequence so command responses
cannot interleave with event data.

### Tone and Effect Limitation

The synth already captures a voice's tone when it allocates that voice. Remote
key-down commands therefore give new voices their configured tone. The audio
effects block remains one global processor, so the most recently pressed remote
key selects the current global effect. This limitation is shown in the app help
text.

## Error and State Handling

- Invalid key fields return `ERR` without changing remote state.
- Duplicate app mappings are rejected before sending.
- A lost Bluetooth link stops UI note indication and requires all remote keys
  to be pressed again after reconnection.
- A dump rejected by the FPGA is reported without erasing the last successfully
  retrieved recording in the app.
- Incomplete dump data is rejected unless `COUNT` and `END` agree with the
  received event count.
- Event count must be 0 through 1024 and every event payload must be exactly
  eight hexadecimal digits.
- `REC START`, `REC STOP`, `REC PLAY`, score playback, and dump operations are
  serialized; the app does not send conflicting controls concurrently.

## Testing

### App Unit Tests

- Decode packed events to NOTE lines.
- Reject truncated `EVT`, invalid hex, mismatched `COUNT`, and more than 1024
  events.
- Preserve the current app's tolerance for responses without CRLF.
- Load and save versioned key configurations.
- Reject duplicate physical or remote note mappings.
- Encode remote key commands with each key's own velocity, tone, and effect.
- Generate all-up commands on cancellation paths.
- Save recording filenames and reload saved NOTE text.

### FPGA Simulation

- `VERSION` returns the supported protocol line.
- `KEY DOWN`, `KEY UP`, and `KEY ALL UP` change only their note gate.
- Remote and physical inputs merge with OR and maximum pressure.
- `STOP` and playback start release remote notes.
- Recording captures physical-only, remote-only, and merged notes with the
  correct metadata.
- `REC STOP` completes open durations before a dump succeeds.
- `REC DUMP` returns the expected count, exact packed values, and `END`.
- Dump is rejected while recording or playback is active.
- Existing UART, parser, score, recorder, sequencer, audio, display, and
  effects tests continue to pass.

### Hardware and Integration

1. Flash the new bitstream and install the new APK.
2. Connect through JDY-31 and verify `VERSION 2`.
3. Remap the eight physical channels and verify actual key behavior.
4. Hold multiple phone keys, including chords, and verify immediate sound and
   independent release.
5. Verify per-key tone while notes are held and the documented global-effect
   behavior.
6. Record a performance containing physical and phone notes.
7. Retrieve, edit, save, and replay the recording.

## Resource and Timing Acceptance

Current utilization before this feature:

- Logic: 91%
- Registers: 31%
- CLS: 98%
- BSRAM: 100%
- DSP: 95%

The implementation adds no new BSRAM. The event uploader and remote controller
must fit in the remaining CLS. Gowin synthesis and place-and-route must succeed
at 50 MHz with zero setup and hold violations.

If the first implementation does not fit, existing parser and response logic
must be consolidated or moved to a table/state-machine representation. The
1024-event capacity, eight remote keys, recording readback, and existing audio
features must not be silently removed.

## Deliverables

- Updated Android source and installable APK.
- Updated FPGA source and regenerated `electrophone.fs`.
- Updated command and user documentation.
- App unit-test results.
- FPGA simulation results.
- Synthesis, resource, Fmax, and setup/hold reports proving the final build.
