# Score Follow Practice Mode Design

Date: 2026-10-25

## Goal

Add a mode selector to the Android performance page:

- Free Play: the existing behavior.
- Score Follow: guide the player through the currently selected NOTE score and
  advance after the correct physical and/or phone key is pressed.

The player controls the tempo. The score is visual guidance and does not play
audio automatically.

## App Experience

The Performance page gets a two-option mode bar:

```text
自由演奏    曲谱跟弹
```

Score Follow requires an already downloaded and selected score. If no score is
available, the app prompts the user to choose one on the Score page.

Follow-mode display:

- Song title.
- Current step and total steps.
- Expected note or chord.
- Correct/incorrect feedback.
- Completion state.

For repeated notes, the player must release the current note before the next
step. A chord advances only after all required notes are held together and then
released.

Wrong notes produce a red warning but do not stop the exercise.

## Score Grouping

The app reads the existing NOTE commands:

```text
NOTE delta,duration,note,velocity,tone,effect
```

The first event starts a step. Every following event with `delta=0` belongs to
the same chord step. Later events start new steps. Duration is displayed as
guidance but does not impose a metronome.

## Input Sources

The app combines:

- Phone virtual-key state known from touch events.
- Physical pressure-key state queried from the FPGA.

Physical keys use the currently applied CH1-CH8 mapping, so the state reported
to the app is already the mapped note bitmask.

## Bluetooth Polling

Follow mode polls once approximately every 30 ms:

```text
KEYSTATE
```

New firmware returns:

```text
KS XX
```

`XX` is the current mapped physical key mask. Polling stops immediately when
leaving follow mode, leaving the Performance page, disconnecting, or completing
the score.

Polling uses the existing serialized Bluetooth worker and does not introduce
unsolicited data into command responses.

## Protocol Version

New firmware reports:

```text
VERSION 3
```

The new app accepts VERSION 2 for base remote play and requires VERSION 3 for
Score Follow. Older wording and commands remain compatible.

## FPGA Change

`command_parser` recognizes the read-only command `KEYSTATE` and returns the
current mapped physical key mask.

The state source is the top-level `mapped_on` signal, after `MAP` remapping and
before merging the phone keys. The app adds its own virtual-key state.

`KEYSTATE` never changes recording, score playback, remote key state, mapping,
or audio.

## Error Handling

- No selected score: do not enter follow mode.
- Empty score: do not enter follow mode.
- Poll timeout: show one warning and stop polling; free play remains available.
- Disconnect: exit follow mode and release remote keys.
- Score reaches its final step: show completed and stop polling.
- Wrong note: show feedback but retain the current step.

## Testing

App unit tests:

- Sequential NOTES create separate steps.
- Zero-delta chords group into one step.
- Correct-note completion and repeated-note release behavior.
- Wrong note does not advance.
- Final step reports complete.
- VERSION 3 enables follow mode; VERSION 2 does not.
- `KS XX` parsing and malformed responses.

FPGA tests:

- `KEYSTATE` returns the exact mapped current mask.
- Mapping changes are visible in the next response.
- Recording and playback commands are unchanged.
- Existing 31 testbenches continue to pass.

Build acceptance:

- Android lint and unit tests pass.
- Gowin synthesis and PNR succeed.
- Setup and hold violations remain zero at 50 MHz.
- The design fits the existing GW5A-25 device.

## Out of Scope

- Automatic score playback in follow mode.
- Tempo enforcement or scoring points.
- Microphone-based acoustic note detection.
- Persisting practice progress across App restarts.
