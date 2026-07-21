# Onon iPhone Recorder

Native SwiftUI field recorder for the Onon local-first mapping MVP.

## Requirements

- Current Xcode and the owner's current iPhone/iOS.
- Location Services enabled, including **Always** permission and Precise Location.
- The laptop server reachable over local Wi-Fi for pairing, map download, and sync.

Open `Onon.xcodeproj`; Xcode resolves MapLibre Native through Swift Package Manager. Select a personal development team, install directly on the iPhone, and enable the app's Background Modes > Location updates capability if Xcode does not preserve the project setting.

No build or App Store configuration is required by the repository scripts.

## Configuration

The app is configured by pairing. Scan the QR shown by the local server. Payload:

```text
onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=short-lived-code
```

The exchanged device token is stored in the iOS Keychain. The server URL is stored in app preferences. Local HTTP is allowed only for local-network addresses by the app's Info.plist policy; production internet deployment should use HTTPS.

The selected MapLibre style URL comes from `GET /api/v1/maps/manifest`. Offline downloads include the style and the vector resources it references.

## API contract

### Pair

`POST /api/v1/pairings/exchange`

Request: `{"code","deviceId","deviceName"}`

Response: `{"deviceToken","deviceId"}`

### Upload immutable recording

`POST /api/v1/recordings`

Headers: `Authorization: Bearer <device token>` and `Idempotency-Key: <recording UUID>`.

The body contains the recording UUID, start/finish timestamps, ordered raw samples, and immutable waypoint observations. `201` and `200` are both treated as confirmed receipt. Response: `{"recordingId","status":"created"}` or `{"recordingId","status":"existing"}`.

Retries use the same UUID and idempotency key. Local raw data is never deleted after confirmation.

## MVP capabilities

- Start, Pause, Resume, and confirmed Finish.
- Background Core Location capture through sleep/lock.
- Every accepted sample committed immediately to SQLite in WAL/full-sync mode.
- Recovery of unfinished active or paused sessions.
- Exact-coordinate waypoint capture at the current accepted GPS fix.
- Immutable raw samples and waypoint observations enforced with SQLite triggers.
- MapLibre map with trail and waypoint overlays.
- Whole-area overview pack plus user-defined detailed offline packs.
- Estimated download size, download progress, pause, and removal.
- QR pairing, Keychain device token, automatic/manual idempotent sync.

## Field acceptance

Before relying on a recording, do one outdoor test: record for at least ten minutes with the phone locked, pause/resume once, add a waypoint, finish, and sync twice. Also terminate/relaunch a separate unfinished session and confirm its committed state recovers. iOS does not promise continuous location delivery after an explicit user force-quit. Server must contain one recording and the phone must retain the same raw samples.
