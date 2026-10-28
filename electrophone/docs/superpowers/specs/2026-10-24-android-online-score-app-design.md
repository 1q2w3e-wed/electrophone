# Android Online Score Downloader Design

Date: 2026-10-24

## Goal

Provide an Android application that searches an HTTPS score catalog, downloads
already-converted NOTE text, validates and saves it on the phone, and sends it
to the FPGA through the paired JDY-31 classic Bluetooth SPP device.

The app is a client for the existing serial protocol. The FPGA remains
responsible for event storage, playback, recording, and audio generation.

## Scope

In scope:

- Fetch a searchable `catalog.json` from HTTPS or use the bundled catalog.
- Search by title, alias, or tag.
- Download a UTF-8 text score over HTTPS.
- Preview the downloaded score.
- Select a Bluetooth device already paired with Android.
- Connect to JDY-31 over classic Bluetooth SPP.
- Validate and send `SCORE CLEAR`, `NOTE`, and `PLAY SCORE`.
- Display download, validation, connection, transmission, and FPGA response
  status.
- Provide seven built-in NOTE scores for offline operation.

Out of scope:

- Hosting a public score service.
- Account login, search, recommendations, ratings, or purchases.
- Server-side authoring or conversion of ordinary web sheet music.
- Internet access from the FPGA.
- BLE and Apple iOS support.
- Audio streaming over Bluetooth.
- Automatic score authoring or MIDI conversion.
- Play Store publication.

## User Interface

The app uses a single screen:

1. Catalog URL field.
2. `联网更新曲谱目录` button.
3. Song-name search field and result list.
4. `选择蓝牙设备` button showing the selected device.
5. `下载保存`, `复制内容`, and `蓝牙发送` actions.
6. Multi-line read-only score preview and status area.

The saved URL and last score remain in the current app session only. The app
does not require file-storage permission.

## Score Format

The downloaded resource is plain UTF-8 text using the existing line protocol.
Blank lines and lines beginning with `#` are ignored.

Supported score commands:

```text
SCORE CLEAR
NOTE delta_ms,duration_ms,note,velocity,tone,effect
PLAY SCORE
```

Validation rules:

- `NOTE` contains exactly six comma-separated decimal fields.
- `delta_ms` is 0 through 4095.
- `duration_ms` is 10 through 2550 and divisible by 10.
- `note` is 0 through 7.
- `velocity` is 0 through 31.
- `tone` and `effect` are each 0 through 3.
- At most 1024 `NOTE` commands are accepted.
- At least one `NOTE` is required before sending.
- The app inserts `SCORE CLEAR` if absent.
- The `下载并发送` action inserts `PLAY SCORE` if absent.

Invalid scores are rejected before any Bluetooth data is sent.

## Android Architecture

### `MainActivity`

Owns the UI, runtime permission requests, and background task coordination.
It never performs network or Bluetooth I/O on the UI thread.

### `ScoreFetcher`

Uses `HttpsURLConnection` with:

- connection and read timeouts;
- redirect support;
- response-code checking;
- a strict maximum download size of 256 KiB;
- UTF-8 decoding.

HTTP URLs are rejected. The app does not disable TLS validation.

### `ScoreValidator`

Converts the downloaded text into a normalized list of protocol commands.
It reports the exact line number for malformed input.

### `SppClient`

Uses Android's classic Bluetooth RFCOMM socket with the standard SPP UUID:

```text
00001101-0000-1000-8000-00805F9B34FB
```

It lists already-paired devices, connects to the selected JDY-31 device, sends
one command line at a time, and waits for `OK`, `PONG`, `ERR`, or `FULL`.

After download and validation, the transmission sequence is:

```text
[SCORE CLEAR]
NOTE ...
NOTE ...
[PLAY SCORE]
```

The app waits for `OK` after each line. Any `ERR`, `FULL`, timeout, or
disconnect stops transmission and is shown to the user.

## Platform Constraints

- Minimum Android API: 23.
- Target Android API: 35.
- Language: Java, to keep the minimal project independent of Kotlin runtime
  libraries.
- UI: platform widgets and a single activity; no external UI framework.
- The app uses classic Bluetooth SPP, not BLE.
- Android 12 and newer require the runtime `BLUETOOTH_CONNECT` permission.
- Older Android versions use the legacy Bluetooth permissions.
- No UART baud-rate setting exists in the phone app.

## Error Handling

The app distinguishes:

- invalid URL;
- network failure;
- non-success HTTP status;
- download larger than 256 KiB;
- invalid UTF-8 or score syntax;
- more than 1024 notes;
- Bluetooth disabled;
- no paired device;
- SPP connection failure;
- FPGA timeout;
- FPGA `ERR` or `FULL`;
- Bluetooth disconnect during transmission.

The user can retry without restarting the app.

## Build and Delivery

The workspace currently has no JDK, Gradle, Android SDK, or ADB. Implementation
will bootstrap a portable JDK and Android command-line SDK under `tmp/` and
build a debug APK with Gradle.

Deliverables:

- Android project source under `android-score-downloader/`.
- Installable debug APK.
- Chinese usage instructions including score URL format.
- Automated tests for score validation and command sequencing.

The APK is a debug-signed sideload build, not a Play Store release.

## Verification

Validation tests:

1. Accept a valid score with notes and play command.
2. Insert missing `SCORE CLEAR` and `PLAY SCORE`.
3. Reject malformed `NOTE` lines and report their line numbers.
4. Reject event 1025.
5. Preserve command order.

Network tests:

1. Download a valid HTTPS score.
2. Reject HTTP.
3. Reject oversized responses.
4. Surface non-2xx status.

Hardware test:

1. Install the APK on Android.
2. Pair JDY-31-SPP through system Bluetooth settings.
3. Start the app and select the paired device.
4. Enter a reachable HTTPS score URL.
5. Tap `下载并发送` and verify each FPGA response and playback.

The final APK must install successfully and pass the JVM validation tests.
