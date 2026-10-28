# Score Follow Practice Mode Implementation Plan

Date: 2026-10-25

Design:
`docs/superpowers/specs/2026-10-25-score-follow-mode-design.md`

## Success Criteria

- Performance page offers Free Play and Score Follow.
- Follow mode groups NOTE events and chords correctly.
- Correct notes advance; wrong notes warn without stopping.
- Repeated notes require a release between steps.
- Physical mapped keys and phone virtual keys both participate.
- FPGA reports VERSION 3 and responds to KEYSTATE.
- Existing play, recording, mapping, and readback behavior remains intact.
- App tests, FPGA simulations, lint, synthesis, PNR, and timing pass.

## Stage 1: App Score Model

1. Parse NOTE events from the current score.
2. Group notes with delta zero into chord steps.
3. Implement the self-paced follow state machine.
4. Test sequential notes, chords, wrong notes, repeated notes, completion, and
   empty scores.

## Stage 2: Bluetooth Key-State Polling

1. Accept VERSION 3 and retain VERSION 2 compatibility.
2. Add the KEYSTATE command and parse `KS XX`.
3. Add serialized, non-overlapping 30 ms polling.
4. Stop polling on mode change, page exit, disconnect, timeout, or completion.

## Stage 3: Performance UI

1. Add Free Play and Score Follow mode controls.
2. Add song title, expected notes, progress, and feedback panel.
3. Require a loaded score before follow mode.
4. Highlight the expected phone pad where possible.
5. Combine physical state with known phone touch state.
6. Keep existing remote play and recording behavior.

## Stage 4: FPGA Support

1. Change VERSION response to VERSION 3.
2. Add KEYSTATE returning the mapped physical key mask.
3. Add parser and integration simulations.
4. Preserve all existing command behavior.

## Stage 5: Verification and Delivery

1. Run all App tests and lint.
2. Run all FPGA simulations.
3. Run Gowin synthesis and PNR.
4. Require zero setup/hold violations at 50 MHz.
5. Deliver updated APK and firmware with test and resource results.
