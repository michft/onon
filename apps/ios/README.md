# Onon iPhone Recorder

Native SwiftUI field recorder for the Onon local-first mapping MVP.

## Requirements

- Current Xcode and the owner's current iPhone/iOS.
- Location Services enabled, including **Always** permission and Precise Location.
- No network or server is required for recording and reviewing sessions.
- Node.js 24 and the workspace's pnpm dependencies for preparing the bundled map.

From the repository root, run `pnpm install`, then `scripts/prepare-ios-map.sh` before building. The preparation downloads checksum-pinned assets on first use; cached reruns work without Internet. It generates `.local/onon/ios-map/Protomaps`, which Xcode copies into the app as a folder resource. Missing generated assets make the build fail; the repository does not commit downloaded maps.

Open `Onon.xcodeproj`; Xcode resolves MapLibre Native through Swift Package Manager. Select a personal development team, install directly on the iPhone, and enable the app's Background Modes > Location updates capability if Xcode does not preserve the project setting. Keep code signing enabled, including on the simulator: app startup reads the iOS Keychain.

## Recorder map

The recorder renders a bundled Protomaps OSM base map through MapLibre Native. Raw GPS trail and waypoints are separate native annotations above it, with recording status and controls over the map. Pan/pinch changes the camera; **Follow my location** enables GPS following. Light/dark follows the phone's appearance, with larger street labels in both styles.

Surface roads retain actual carriageway geometry. Tunnels, ferry routes, railways and adjacent cycleways are excluded from road drawing; walking paths use thin dashed lines. This presentation does not edit OSM data.

The packaged Sydney extract covers longitude 151.15–151.25 and latitude -33.92–-33.80, with source zooms 0–15 and display overzoom through 19. Archive: 8.7 MB; complete map resources: about 11 MB. Map tiles, style, fonts and sprites load from bundle file URLs: no pairing, tile server, localhost service, API key or map network request is needed. The pinned source build is 2026-10-09; preserve the downloaded archive because dated upstream builds have limited retention. Bundled glyphs support the trial's English labels; broad multilingual coverage is not included.

Selected-area/route-corridor downloads and map updates remain in [TODO](../../docs/TODO.md). Outside this bundled Sydney region, detailed offline coverage is not guaranteed. Test cold launch, zoom, pan and appearance changes in airplane mode before an outdoor run.

## Map verification

The packaged-resource regression test loads both real bundled styles and checks their local PMTiles archive, three Latin font families and sprite variants. Run the Onon scheme's tests after preparing map assets. If CoreSimulator cannot clone a simulator, use `-parallel-testing-enabled NO` with `xcodebuild test`; keep code signing enabled.

Simulator follow-up on 2026-10-10 passed eight iOS tests, cold launch after removing only the SDK map cache and regenerated style cache, pinch/pan, and light/dark changes during an active recording. Appearance changes preserved the camera, trail and waypoint. Termination/relaunch recovered three committed samples and one waypoint. Cache removal was reversible and left recording storage intact. This verifies bundled-resource startup; physical-phone airplane mode and outdoor locked-screen location delivery remain field checks.

## Diagnostics

The app logs through unified logging, subsystem `au.local.onon`, categories `location`, `recording`, `storage`, `sync` and `map`. Recording transitions, permission changes, delivery gaps over 30 s, a capture summary every 100 fixes and on stop, sync results and all errors are logged at notice level or above and persist on the phone. Each rejected fix is debug level, visible only while streaming. Coordinates are not logged.

- Live: Console.app, select the iPhone, filter `subsystem:au.local.onon`.
- After a walk: `sudo log collect --device-udid <UDID> --last 3h --output onon.logarchive`, then `log show onon.logarchive --predicate 'subsystem == "au.local.onon"'`.

Long-press the status card on the Record screen to show or hide capture diagnostics: fixes delivered by iOS, kept, rejected as weak (worse than ±50 m) or stale (older than 2 min), seconds since the last delivery and the longest gap. A growing last-fix age while walking means iOS stopped delivering updates; many weak fixes point at the accuracy filter or poor sky view.

## Configuration

Server pairing is optional. Use **Server → Scan pairing QR**, or scan the local
server's QR with the iPhone Camera and open Onon. Review the displayed laptop
address. Pairing and automatic uploads
start only after **Pair and enable uploads**. Cancel leaves the current pairing
unchanged. Payload:

```text
onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=short-lived-code
```

The exchanged device token is stored in the iOS Keychain. The server URL and
approved origin are stored in app preferences. Only `.local`, localhost and
private LAN IP origins are accepted; URL credentials, extra paths, query strings
and fragments are rejected. Pairing and recording uploads do not follow HTTP
redirects. Pairings created before destination approval was introduced must scan
a new QR and approve the laptop again; their recordings and old credentials stay
on the phone until then. Internet deployment requires a separate security review.

The dormant server/offline-area flow can obtain its style from `GET /api/v1/maps/manifest`. Recorder uses the bundled map independently of that flow.

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

- Offline OSM surface map with street names, separate trail/waypoint overlay and light/dark appearance.
- Start, Pause, Resume, and confirmed Finish.
- Background Core Location capture through sleep/lock.
- Every accepted sample committed immediately to SQLite in WAL/full-sync mode.
- Recovery of unfinished active or paused sessions before automatic sync can refresh state.
- Exact-coordinate waypoint capture at the latest accepted GPS fix. Long-press **Waypoint** to choose how old that fix may be (15 seconds to 5 minutes, default 2 minutes); standing still produces no new fixes, so the latest one is usually still current.
- Immutable raw samples and waypoint observations enforced with SQLite triggers.
- Scrollable local saved-session list.
- Optional QR pairing and idempotent sync to the explicitly approved local laptop.
- Storage failures stop capture and show a retryable error, including when the
  database cannot persist a pause; **Resume** reconciles persisted state before restarting capture and can retry a failed reload without changing raw data. A failed **Finish** keeps capture stopped and offers **Retry finish**, including when Finish committed before its reload failed.

## Field acceptance

Before relying on a recording, do one outdoor test: record for at least ten minutes with the phone locked, pause/resume once, add a waypoint, finish, and sync twice. Also terminate/relaunch a separate unfinished session and confirm its committed state recovers. iOS does not promise continuous location delivery after an explicit user force-quit. Server must contain one recording and the phone must retain the same raw samples.
