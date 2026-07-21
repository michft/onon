# Onon MVP Plan

**Status:** Draft — awaiting approval  
**Implementation:** Do not begin until this plan is approved.

## Outcome

Build a local-first mapping system for inner Sydney with three parts:

1. A local OSM vector-map pipeline and application server on a Mac laptop.
2. A native SwiftUI iPhone trail recorder that survives sleep and locking.
3. A web workspace for editing trails, adding symbols, styling maps, and exporting A4 PDFs.

The initial map covers east of Parramatta, south of Hornsby, north of Sutherland, and one nautical mile offshore.

## System Shape

```text
OSM extract
    |
    v
Planetiler one-shot container -> versioned OpenMapTiles MBTiles
                                      |
                                      v
                                TileServer GL
                                  /       \
                     vector tiles         print raster
                        /                       \
              SwiftUI iPhone              Web/API container
                    |                            |
                    +--- immutable recording --> PostgreSQL
                                                 |
                                      editable trail + PDF
```

All laptop services run as individually launched OCI containers through Apple's `container` CLI. There is no Docker Compose file. Shell scripts create the network, launch containers in dependency order, check health, and stop them in reverse order.

## Part 1: Local Map and Application Platform

### Map pipeline

- Use Planetiler in a one-shot ARM64 OCI container.
- Download an OSM source extract and clip output to the Sydney Service Area.
- Generate OpenMapTiles-compatible, versioned MBTiles archives.
- Start from OSM Bright GL style and self-host fonts, sprites, and style files.
- Provide three fixed styles:
  - Screen colour.
  - Blue-light paper.
  - Greyscale paper.
- Use redundant visual distinctions: luminance, line weight, dash patterns, borders, and symbols.
- Include `© OpenMapTiles © OpenStreetMap contributors` on screen and in exports.
- Refresh OSM data manually. Generate and validate a new archive before switching the active version. Retain the prior archive for rollback.

### Runtime services

- **PostgreSQL:** persistent application data, reachable only on the private container network.
- **TileServer GL:** vector tiles, styles, fonts, sprites, and server-rendered print imagery.
- **Web/API:** TypeScript service hosting the web workspace, pairing, sync, editing APIs, and PDF export.
- Pin all OCI images by major version and verify ARM64 manifests.
- Store PostgreSQL data, map archives, styles, exports, and backups in explicit host-mounted directories.
- Use database migrations from the first schema version.
- Do not add PostGIS initially. Preserve latitude/longitude and editable geometry in ordinary PostgreSQL types; add PostGIS only when spatial database queries justify it.

### Local deployment scripts

- `scripts/bootstrap-local.sh`: verify Apple `container`, start its system service, create directories/network, pull pinned images, and initialize secrets.
- `scripts/start-local.sh`: start PostgreSQL, wait for health, then start TileServer GL and Web/API.
- `scripts/stop-local.sh`: stop services in reverse order without deleting data.
- `scripts/status-local.sh`: show service, health, map-version, and disk-use status.
- `scripts/refresh-map.sh`: fetch source data, build a candidate MBTiles archive, smoke-test it, activate it, and retain the previous archive.
- `scripts/backup-local.sh`: create a timestamped PostgreSQL dump plus styles/configuration manifest.
- `scripts/restore-local.sh`: restore into a new database, validate it, then switch the application.

Scripts must be idempotent, quote paths, fail clearly, and never remove persistent data implicitly. Startup remains manual for MVP.

### PostgreSQL model

- Paired devices and revocable device tokens.
- Immutable raw recordings.
- Ordered GPS samples with timestamp, coordinates, accuracy, altitude, speed, and course when available.
- Immutable waypoint observations captured during recording.
- Editable trail overlays derived from raw recordings.
- Editable waypoints and direction-arrow placement.
- Sync receipt/idempotency keys.
- Active and historical map versions.
- Schema migration history.

PostgreSQL is chosen over SQLite because the intended next deployment is online. This adds one local service but avoids changing database engines during that move.

## Part 2: Native SwiftUI iPhone Recorder

### Technology

- Native SwiftUI, targeting the owner's current iPhone/iOS first.
- Core Location with the iOS background location capability.
- MapLibre Native for local vector styles and offline maps.
- Native durable storage that commits samples incrementally; an app interruption must not lose the active session.
- Keychain storage for the paired-device token.

### Recording workflow

- Controls: Start, Pause, Resume, Finish.
- Locking or sleeping the phone does not pause or finish recording.
- Finish requires confirmation.
- Restore an unfinished session after app interruption.
- Record raw GPS observations without snapping to OSM roads or paths.
- Preserve the raw recording permanently; editing creates a separate trail overlay.
- One tap during recording adds a waypoint at the current GPS coordinate.
- Waypoint dot represents the exact coordinate; outer circle preserves visibility.

### Offline maps

- Cache overview detail for the whole Sydney Service Area.
- Let the user select smaller detailed offline areas before field use.
- Show estimated download size and progress.
- Recording, waypoint capture, session recovery, and map viewing work with the laptop unreachable.

### Pairing and sync

- Laptop displays a QR code containing its local address and a short-lived one-time pairing code.
- iPhone exchanges the code for a revocable long-lived device token.
- Auto-upload completed recordings when the server becomes reachable.
- Provide manual Sync Now and visible pending/error status.
- Keep the phone's raw copy until the server confirms receipt.
- Make retries idempotent so they never create duplicate recordings.
- Install directly from Xcode for MVP. No TestFlight or App Store work.

## Part 3: Web Workspace and Print Export

### Trail workspace

- Use MapLibre GL JS with the same locally hosted vector tiles and display profiles as iPhone.
- List raw recordings, pending/received state, and derived trail overlays.
- Create one editable trail overlay from each immutable raw recording.
- MVP geometry tools:
  - Trim start.
  - Trim end.
  - Remove a selected bad section.
  - Undo and redo.
- Add or move a waypoint by clicking the map.
- Add a direction arrow by clicking a trail.
- Snap the arrow beside the trail and derive orientation from recorded order.
- Let the user flip arrow side, move it along the trail, or delete it.
- Do not alter raw GPS samples from the web workspace.

### Display profiles

- Screen colour profile.
- Blue-light print profile that avoids blue-dependent distinctions.
- Greyscale profile designed directly in grey values, not produced by desaturation.
- Profiles also vary patterns, widths, and outlines.
- Add automated checks for minimum luminance separation among important adjacent feature classes.
- Use fixed recommended profiles only. No end-user style editor or automatic arbitrary colour conversion in MVP.

### A4 PDF export

- Export from the web workspace to the laptop/desktop as PDF.
- A4 portrait and landscape.
- Fixed scales: 1:10,000 default, 1:15,000, and 1:25,000.
- Exact crop preview before export.
- High-resolution locally rendered base map.
- Crisp vector trail, waypoint, direction arrows, scale bar, north arrow, legend, and attribution.
- SVG and PNG export remain deferred.

## Delivery Phases

### Phase 0: Risk spike

- Run a small Planetiler build through Apple `container` on ARM64.
- Serve the result with TileServer GL through Apple `container`.
- Confirm vector tiles in MapLibre GL JS and MapLibre Native.
- Confirm TileServer GL can render the image dimensions needed for A4 export.
- Confirm official PostgreSQL ARM64 image, persistent mount, private network, and backup/restore.
- If full TileServer GL raster rendering fails on ARM64, retain its vector serving path and move print rendering into the Web/API container.

**Exit:** One local style renders from one local vector archive in browser and iPhone test shells; container restart retains PostgreSQL data.

### Phase 1: Local platform tracer bullet

- Add bootstrap/start/stop/status scripts.
- Add PostgreSQL migrations and minimal Web/API health endpoint.
- Generate the Sydney map archive and serve one screen style.
- Show map in the web workspace.

**Exit:** Fresh laptop setup reaches a local Sydney map using only documented scripts.

### Phase 2: Recorder tracer bullet

- Implement pairing.
- Implement durable Start/Pause/Resume/Finish recording.
- Add background/lock operation and recovery.
- Add live waypoint capture.
- Upload one immutable recording idempotently to PostgreSQL.

**Exit:** A locked-screen outdoor walk uploads exactly one recoverable raw recording.

### Phase 3: Offline field use

- Add overview and selected-detail offline areas.
- Add download size/progress/error handling.
- Exercise recording, waypoint capture, restart, and later sync with no server connection.

**Exit:** Airplane-mode field session records and later syncs without loss or duplication.

### Phase 4: Trail editing and symbols

- Derive editable trail overlay from raw recording.
- Add bounded geometry edits, undo/redo, waypoints, and direction arrows.
- Preserve raw recording through every edit.

**Exit:** Web user cleans a trail and adds required symbols without changing raw evidence.

### Phase 5: Print profiles and PDF

- Implement all three profiles.
- Add A4 crop/scale preview and PDF composition.
- Run automated contrast checks.
- Physically print blue-light and greyscale samples for human review.

**Exit:** A4 outputs remain readable on colour and greyscale printers and under the target blue-tinted LED light.

### Phase 6: Reliability and handoff

- Complete backup/restore and map-version rollback.
- Add focused tests, operating guide, data directory guide, privacy notes, and troubleshooting.
- Validate a clean bootstrap from repository instructions.

**Exit:** Local system can be rebuilt, backed up, restored, and operated without undocumented steps.

## MVP Acceptance Tests

- Sleep and lock iPhone for at least ten minutes during recording; trail remains continuous.
- Pause creates no location segment; Resume continues the same session.
- App interruption restores unfinished recording without losing committed samples.
- Airplane-mode recording works with a downloaded detailed map.
- Repeating sync creates one server recording.
- Raw samples remain byte-for-byte unchanged after every web edit.
- Waypoint centre and direction arrow remain correctly positioned at all supported print scales.
- All three styles load without internet access.
- A4 crop and measured scale match the chosen print scale.
- Greyscale output remains distinguishable on a greyscale printer.
- Blue-light profile receives physical review under the target LED light.
- Restarting each container retains data.
- Failed map refresh leaves the prior map active.
- Backup restores into a fresh PostgreSQL volume.

## Explicitly Deferred

- Accounts, cloud hosting, and public internet access.
- Multi-user ownership and conflict resolution.
- NAS deployment.
- App Store and TestFlight distribution.
- Web or PWA background recording.
- Automatic OSM refresh schedules.
- Planet-wide or all-Australia coverage.
- Full-detail offline download of the whole Sydney Service Area.
- Automatic road/path snapping.
- Freehand trail drawing, splitting, and joining.
- Automatic repeated direction arrows.
- Arbitrary style editing and automatic colour-to-grey conversion.
- PostGIS.
- SVG and PNG export.
- Laptop login autostart.

## Approval Gate

Approval authorizes implementation in the delivery-phase order above. Before feature work, create one ADR recording the PostgreSQL-over-SQLite decision and complete Phase 0. Any failure that changes the three-part architecture returns for approval rather than silently substituting another stack.
