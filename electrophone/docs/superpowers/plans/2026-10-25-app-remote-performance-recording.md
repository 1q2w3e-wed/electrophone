# Android Remote Performance and Recording Readback Implementation Plan

Date: 2026-10-25

Design:
`docs/superpowers/specs/2026-10-25-app-remote-performance-recording-design.md`

## Success Criteria

- The Android app keeps the existing online score workflow.
- Both physical-key mapping and eight configurable remote keys are available.
- Remote notes support multi-touch and independent press/release.
- Each remote key stores its own label, note, velocity, tone, and effect.
- Physical and remote performance record into the same FPGA event memory.
- The app retrieves and validates all recorded events, supports editing, saving,
  copying, and replay, and preserves the previous recording on a partial dump.
- Old firmware remains usable for score sending.
- New firmware reports protocol version 2 and supports all new commands.
- Existing 1024-event capacity and audio features remain intact.
- App tests, FPGA simulations, synthesis, place-and-route, resource checks, and
  timing checks pass.
- A new installable APK and `electrophone.fs` are produced.

## Stage 1: App Data and Protocol Models

1. Add remote key configuration data with validation, JSON persistence, and
   duplicate-note checks.
2. Add packed-event decoding to NOTE text.
3. Add binary recording packet decoding with magic header and count.
4. Add command builders for key down, key up, all-up, and recording controls.
5. Write unit tests first for all boundaries and malformed input.
6. Make the new tests pass.

Verification:

- Eight unique notes are accepted.
- Duplicate, missing, or out-of-range values are rejected.
- Packed values decode to the exact six NOTE fields.
- Truncated, invalid-header, mismatched, and oversized dumps are rejected.

## Stage 2: App Bluetooth Transport

1. Extend `SppClient` with explicit connect, disconnect, version negotiation,
   remote key commands, recording controls, and dump download.
2. Preserve compatibility with old firmware responses that have no CRLF.
3. Serialize all commands through one worker and release all remote notes on
   failure.
4. Add feed-based unit tests around response token/line handling.
5. Verify old-firmware score sending remains available.

Verification:

- `ERRERRPONG` and line-delimited `PONG` both succeed.
- New and legacy `OK/ERR/FULL` response formats are understood.
- A complete binary packet is parsed correctly.
- Partial dump preserves the last successful app recording.

## Stage 3: App Performance and Recording UI

1. Restructure the activity into Scores, Performance, and Recording pages.
2. Keep device selection visible and add persistent connect/disconnect.
3. Add eight physical mapping selectors and validation.
4. Add eight configurable remote pads with multi-touch handlers.
5. Add per-key configuration dialogs and local persistence.
6. Add recording start/stop, retrieval progress, editor, save, copy, and replay.
7. Add all-up safety on cancel, disconnect, background, and page exit.

Verification:

- Multi-touch generates one down and one up per pad.
- Changing a mapping releases held remote notes first.
- Recording retrieval populates editable NOTE text only after a complete dump.
- Existing score download and send actions still work.

## Stage 4: FPGA Command Parser and Remote Input

1. Add `VERSION`, `KEY DOWN`, `KEY UP`, and `KEY ALL UP` to the parser.
2. Add CRLF to parser response output.
3. Add a small remote input state module with eight gates, levels, and per-note
   tone/effect capture.
4. Add parser and remote-input simulations, including malformed commands and
   release behavior.
5. Keep existing command parsing and responses backward-compatible.

Verification:

- `VERSION` returns `VERSION 2`.
- Invalid key fields return `ERR` without changing state.
- Key down/up/all-up and STOP produce independent gate behavior.
- Existing score and recording commands still pass.

## Stage 5: FPGA Performance Merge and Recording

1. Merge mapped physical and remote inputs using OR plus maximum level.
2. Release remote input when score playback starts.
3. Update the recorder to capture the merged performance and source metadata.
4. Verify physical-only, remote-only, and merged note recording in simulation.
5. Preserve score playback and existing UI behavior.

Verification:

- Pressing physical and remote copies of one note keeps sound until both release.
- Remote tone is used for a newly allocated remote voice.
- Recorded velocity, duration, tone, and effect match the triggering source.

## Stage 6: FPGA Recording Upload

1. Add `REC DUMP` recognition and busy-state rejection.
2. Add an event uploader that emits a binary header and packed event bytes.
3. Arbitrate the existing event RAM read port between sequencer and uploader.
4. Arbitrate UART transmission between command responses and event streaming.
5. Add simulation coverage for zero, partial, and 1024-event dumps.

Verification:

- Dump is rejected while recording or playback is active.
- All packed events are returned in order without another event changing.
- A 1024-event dump contains four header bytes and 4096 event bytes with no
  interleaved command response.

## Stage 7: App Regression and Packaging

1. Run all app unit tests.
2. Run Android Lint.
3. Build the APK.
4. Verify package version, signature, embedded catalog, and all bundled scores.
5. Update user documentation and place the APK on the desktop.

Verification:

- All tests pass and lint reports no errors.
- APK contains seven valid bundled scores.
- Signature and version checks pass.

## Stage 8: FPGA Regression, Build, and Delivery

1. Run every existing and new GHDL test.
2. Add new source files to `electrophone.gprj`.
3. Run Gowin synthesis and place-and-route at 50 MHz.
4. Inspect CLS, BSRAM, DSP, Fmax, setup, and hold results.
5. If resources do not fit, consolidate parser/response logic without reducing
   approved features.
6. Produce and verify `impl/pnr/electrophone.fs`.
7. Update README with commands, app workflow, programming steps, and limitations.

Verification:

- Full regression passes.
- The design fits GW5A-25.
- Setup and hold violations are zero.
- Final firmware and APK are delivered with exact test/build results.

## Hardware Verification

1. Program the new bitstream.
2. Pair and connect through JDY-31.
3. Verify protocol version 2.
4. Remap physical channels and play them.
5. Hold multiple remote notes and verify independent release.
6. Verify per-key tone behavior and documented global-effect behavior.
7. Record a mix of physical and remote notes.
8. Retrieve, edit, save, and replay the recording.

Hardware limitations must be reported explicitly if no phone or board is
available during an automated run.
