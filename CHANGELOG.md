# Changelog

## Unreleased

- Restore the optional Server tab and QR scanner; show destination approval after dismissing the scanner. Skip empty cached OSM inputs during map refresh.

- Require explicit local-laptop destination approval before iOS pairing or automatic uploads, reject public server origins and redirects, and retain previous credentials if replacement fails.
- Propagate SQLite read errors and show stopped capture with a working Resume action even when a storage failure prevents persisting pause or a state reload fails after a successful transition. Failed Finish stays stopped with an explicit Retry finish action; a later Pause or Finish invalidates suspended Resume work. Reject snapshots read before later storage changes and preserve Finish retry alerts when older recovery completes.
- Let iOS waypoints use a location fix up to 2 minutes old by default, adjustable from 15 seconds to 5 minutes by long-pressing Waypoint, so standing still no longer blocks waypoints.
- Add iOS unified logging for recording, location delivery, storage, sync and map loading, and a hidden capture diagnostics row (long-press the Record status card); location errors now show on screen.
- Fix iOS recorder showing a false "Recording stopped" alert on pause; a genuine sample-save failure now pauses the recording so Resume works.
- Fix iOS recorder so re-enabling location access mid-recording resumes capture, the Saved tab shows live counts for the current recording, and a quick pause/resume no longer raises a false save-failure alert; explain how to grant Always access once the prompt has been used.
- Keep the iOS recorder's GPS-fix indicator and Always-location hint current.
- Draw the iOS recorder's track incrementally and stop re-reading the full recording on every GPS fix, so long recordings stay smooth.
- Add a phone-deployable offline Sydney OSM map beneath the iOS recorder's GPS trail, waypoints and controls, with system light/dark styling and larger street labels.
- Add checksum-pinned native map preparation and preserve the route-sized offline cache TODO.
- Add a separate locally hosted Sydney Protomaps Light trial with surface roads, distinct walking paths and local map assets.
- Track route-sized offline tile caching and production map integration in [TODO](docs/TODO.md).
