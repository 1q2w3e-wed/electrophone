# Bluetooth Score Playback and Performance Recording Design

Date: 2026-10-24

## Goal

Implement the Bluetooth-linked portion of competition extension 4 on GW5A-25:

- Send short scores from a phone through JDY-31 SPP.
- Store and play scores without the phone.
- Reassign the eight physical pressure keys.
- Record a performance as compact note events.
- Replay the recorded performance on the FPGA.

LED song guidance remains out of scope. A generic Bluetooth serial APK is used
for the first version; automatic online score download and a custom mobile app
are deferred.

## Hardware

The supplied module is a JDY-31 Bluetooth 3.0 SPP transparent UART module.

- Supply: 3.3 V
- Default UART: 9600 bps, 8N1
- Required project UART: 115200 bps, 8N1
- Supported Android, Windows, and Linux hosts
- Apple iOS SPP support is not assumed
- Maximum module throughput: approximately 16 KB/s

Configure the module once with:

```text
AT+BAUD8\r\n
```

Expected response: `+OK`.

The four-pin module does not expose the `STAT` connection pin in the current
wiring, so the FPGA cannot distinguish "Bluetooth idle" from "connected but
silent." The display may show recent Bluetooth activity after a valid command,
but must not claim a hardware connection-status guarantee.

Project wiring:

- JDY-31 TXD -> FPGA J5 (FPGA UART RX)
- JDY-31 RXD -> FPGA H7 (FPGA UART TX)
- Common ground and 3.3 V supply

## Serial Protocol

The protocol is human-readable ASCII so it can be pasted into the supplied
generic Bluetooth serial APK.

- One command per line.
- Accept LF or CRLF line endings.
- Commands are case-insensitive.
- A line longer than the parser buffer is rejected.
- Every completed command returns `OK`, `PONG`, `ERR`, or `FULL`.

### Commands

```text
PING
MAP 0,1,2,3,4,5,6,7
SCORE CLEAR
NOTE 0,500,0,20,0,0
PLAY SCORE
STOP
REC START
REC STOP
REC PLAY
```

`MAP` defines the note assigned to pressure channels CH0 through CH7. Each
value must be 0 through 7.

`NOTE` fields are:

```text
NOTE delta_ms,duration_ms,note,velocity,tone,effect
```

- `delta_ms`: 0 through 4095 ms
- `duration_ms`: 10 through 2550 ms
- `note`: 0 through 7
- `velocity`: 0 through 31
- `tone`: 0 through 3
- `effect`: 0 through 3

When a chord starts, the first note uses its normal delta and the remaining
notes use delta 0. A note duration is encoded in 10 ms units.

### Command Responses

- `PING` -> `PONG`
- Valid state-changing command -> `OK`
- Storage full -> `FULL`
- Invalid or out-of-range command -> `ERR`
- `STOP` stops score/record playback and releases all virtual notes.

## Score Event Storage

Score and performance recording share one event RAM. They never run together.

- Capacity: 1024 events
- Packed size: 4 bytes per event
- Total storage: 4 KB

Each packed event contains:

- 12-bit time delta in milliseconds
- 8-bit duration in 10 ms units
- 3-bit note index
- 5-bit velocity
- 2-bit timbre
- 2-bit effect mode

The event RAM should be implemented as a dedicated BSRAM-backed module with a
small read/write interface. The score parser writes events linearly. Playback
reads events linearly.

When storage is full:

- Further `NOTE` commands return `FULL`.
- Existing events remain unchanged.

## Key Mapping

- Default mapping is `0,1,2,3,4,5,6,7`.
- `MAP` updates eight note assignments.
- The mapping applies to physical pressure input immediately.
- Score playback uses musical note indexes directly and does not reinterpret
  them through the physical-key mapping.
- Mapping is not persisted across power cycles in this version.

The top level applies the mapping before feeding the synthesizer:

```text
physical channel -> configured note index -> voice allocator
```

The pressure visualization continues to show physical CH0 through CH7.

## Score Playback

- `SCORE CLEAR` empties the score event count.
- `NOTE` appends a note event.
- `PLAY SCORE` starts playback from the first event.
- Score playback generates virtual pressure gates and velocity levels for the
  synthesizer.
- Physical pressure input is ignored while a score is playing.
- `STOP` releases all score-generated notes and restores physical input.

Scores support up to eight simultaneous physical note indexes, matching the
eight-key input. Same-note overlap is not added as a special polyphonic score
feature in this version.

## Performance Recording

`REC START` clears the shared event RAM and begins performance recording.

- Physical playing continues normally.
- A note event is allocated on key-on.
- Its duration field is completed on key-off.
- Recorded fields use the mapped note, peak pressure velocity reached while
  the key was held, captured timbre, and current effect mode.
- Maximum duration and inter-note gap follow the packed event limits.

`REC STOP` ends recording and restores normal operation.

`REC PLAY` replays the recorded events using the same sequencer as score
playback.

Recording stores performance events, not PCM audio. The phone can cause the
FPGA to replay the performance, but the generic APK cannot receive a WAV file.

## Module Design

### `uart_rx`

Implements 115200 bps 8N1 receive with a 50 MHz clock.

Outputs one byte and a byte-valid pulse.

### `uart_tx`

Implements 115200 bps 8N1 transmit.

### `command_parser`

Turns ASCII lines into typed commands and drives:

- key mapping
- score clearing and event append
- playback control
- recording control

The parser never drives audio directly.

### `score_event_ram`

Stores 1024 packed 32-bit events in BSRAM.

Interfaces:

- append event
- read event by index
- update recorded duration by index
- clear
- event count

### `score_sequencer`

Owns the millisecond playback timeline, active note gates, and durations.

Outputs:

- virtual sensor-on mask
- virtual per-note pressure levels
- note trigger and release events

### `score_recorder`

Captures mapped physical note-on/off events into the shared event RAM and
completes their duration fields.

### Top-Level Audio Multiplexer

Selects between mapped physical pressure input and virtual score input.

The selected pressure signals feed the existing synthesizer, effects, I2S, and
all visual analyzers without changing their interfaces.

## Data Flow

```text
JDY-31 -> UART RX -> command parser -> event RAM / key map
                                           |
physical CH0..CH7 -- key mapping ----------+
                                           |
score/record sequencer -> virtual pressure |
                                           v
                                     32-voice synth
                                           |
                                  effects -> I2S/UI
```

## Resource Budget

Current implementation before this feature:

- Logic: 80%
- Registers: 25%
- DSP: 90%
- BSRAM: 95%
- CLS: 93%
- Fmax: 50.107 MHz
- Setup and hold violations: 0

Expected additions:

- UART receiver and transmitter: small
- ASCII parser and command state machine: low to moderate logic
- Event RAM: 4 KB, approximately 2 BSRAM blocks
- Sequencer and recorder: low to moderate logic

Only one BSRAM block is expected to remain after event storage. If the design
does not fit or close timing, implementation must report the concrete resource
or timing gap. It must not silently reduce the 1024-event capacity or remove a
required feature.

Implementation result:

- The shared 1024 by 32-bit event RAM maps to four SDPB blocks.
- The existing audio scope's two 512 by 16-bit arrays were consolidated into
  one 1024 by 16-bit dual-bank RAM, freeing the block needed for the score RAM.
- Final utilization is 56/56 BSRAM and 99% CLS, so no BSRAM and almost no logic
  remain for later features.

## Verification

UART tests:

1. Send and receive 0x00, 0x55, 0xAA, and 0xFF at 115200 bps.
2. Verify one byte-valid pulse per received byte.
3. Verify baud timing tolerance at a 50 MHz clock.

Parser tests:

1. Verify PING/PONG.
2. Verify LF and CRLF commands.
3. Verify case-insensitive commands.
4. Verify MAP bounds and immediate mapping.
5. Verify malformed and overlong commands return ERR without hanging.

Score tests:

1. Append 1024 events and report FULL for event 1025.
2. Verify packed event fields.
3. Verify timeline, note durations, and chords.
4. Verify STOP releases virtual notes.
5. Verify physical input is ignored during score playback.

Recording tests:

1. Verify note-on creates a record and note-off completes its duration.
2. Verify mapped note, peak velocity, timbre, and effect are captured.
3. Verify REC STOP ends capture.
4. Verify REC PLAY recreates the recorded timeline.

Hardware tests:

1. Pair a phone with JDY-31-SPP at 115200 bps.
2. Send PING from the supplied generic APK and receive PONG.
3. Paste a multi-note score and play it.
4. Change key mapping and verify the next physical performance.
5. Record, stop, and replay a short performance.

Regression and build:

1. All existing 20 tests continue to pass.
2. New Bluetooth, parser, score, and recording tests pass.
3. Gowin synthesis and place-and-route succeed.
4. The design fits GW5A-25.
5. Setup and hold violations remain zero at 50 MHz.
6. The final bitstream is regenerated.

## Out of Scope

- LED song guidance
- Automatic online score download in the generic APK
- A custom Android application in this version
- Apple iOS support
- Raw PCM or WAV recording
- Audio playback over Bluetooth A2DP
- Persistent mapping or scores across power cycles
- More than 1024 score or recording events
