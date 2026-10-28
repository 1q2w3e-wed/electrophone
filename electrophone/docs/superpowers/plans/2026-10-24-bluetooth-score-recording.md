# Bluetooth Score Playback and Performance Recording Implementation Plan

Date: 2026-10-24

Design:
`docs/superpowers/specs/2026-10-24-bluetooth-score-recording-design.md`

## Success Criteria

- JDY-31 communicates over 115200 bps, 8N1 using FPGA pins J5 and H7.
- PING, MAP, SCORE CLEAR, NOTE, PLAY SCORE, STOP, REC START, REC STOP,
  and REC PLAY follow the approved ASCII protocol.
- Up to 1024 packed four-byte events are stored in the shared event RAM.
- Physical pressure channels use the configured note mapping.
- Score playback, performance recording, and performance replay use the same
  event format and sequencer.
- Existing audio, effects, spectrum, Lissajous, UI, and 32-voice behavior
  remain intact.
- All simulations pass, the GW5A-25 build fits, and setup/hold violations
  remain zero at 50 MHz.

## Stage 1: UART

1. Add `tb_uart.vhd` at the public UART seams.
2. Verify 0x00, 0x55, 0xAA, and 0xFF reception at 115200 bps.
3. Verify exactly one byte-valid pulse per received byte and transmit timing.
4. Add `uart_rx.vhd` and `uart_tx.vhd`.
5. Make the UART tests pass.
6. Add a parser-to-UART integration test proving PING returns complete PONG
   with real transmitter back-pressure.

Verification:

- Four-byte loopback receives the same bytes.
- Bit timing is within the 115200 bps tolerance at a 50 MHz clock.

## Stage 2: Event RAM

1. Add `tb_score_event_ram.vhd`.
2. Verify clear, append, read, duration update, count, and FULL at 1024.
3. Add `score_event_ram.vhd` with a small synchronous read interface.
4. Make the RAM test pass.

Verification:

- 1024 events fit without truncation.
- Event 1025 is rejected and existing events remain unchanged.

## Stage 3: Command Parser

1. Add `tb_command_parser.vhd`.
2. Verify LF/CRLF, case insensitivity, PING/PONG, MAP bounds, valid NOTE,
   malformed NOTE, overlong input, STOP, and recording commands.
3. Add `command_parser.vhd` with a bounded line buffer and numeric fields parsed
   without division.
4. Make parser tests pass against a small RAM stub.

Verification:

- Every complete command produces exactly one response: PONG, OK, ERR, or FULL.
- Parser output drives mapping, RAM append, and playback control pulses.

## Stage 4: Sequencer and Recorder

1. Add `tb_score_sequencer.vhd`.
2. Verify deltas, chords, durations, STOP, end-of-score, and physical-input
   suppression through the virtual pressure output.
3. Add `score_sequencer.vhd`.
4. Add `tb_score_recorder.vhd`.
5. Verify mapped note, velocity, tone, effect, timing, duration completion, and
   replay-compatible event output.
6. Add `score_recorder.vhd`.

Verification:

- A short sequence containing a chord and a later note replays with the same
  gate timeline.
- A recorded press/release produces one packed event with completed duration.

## Stage 5: Top-Level Integration

1. Add Bluetooth UART ports and J5/H7 constraints.
2. Add a one-millisecond tick from the existing I2S sample tick.
3. Apply key mapping before `synth_engine`.
4. Multiplex score pressure input and physical pressure input.
5. Route event timbre/effect through playback without changing analyzer inputs.
6. Add the new source files to `electrophone.gprj`.
7. Add integration assertions for physical suppression and mapped note indexes.

Verification:

- Existing analyzer and UI interfaces are unchanged.
- Top-level simulation reaches score playback after a parsed command stream.

## Stage 6: Regression, Build, and Hardware

1. Run every existing and new GHDL test.
2. Run Gowin synthesis and place-and-route.
3. Inspect logic, register, DSP, BSRAM, CLS, Fmax, and setup/hold results.
4. Keep the complete requested feature set or report the exact closure gap.
5. Update README with Bluetooth commands, wiring, usage, and final metrics.
6. Generate the final bitstream.
7. Validate PING, pasted score playback, mapping, recording, and replay with the
   supplied APK and JDY-31 configured to 115200 bps.

Verification:

- Full regression passes.
- Build succeeds with zero setup/hold violations.
- Hardware test results and any remaining limitations are explicit.
