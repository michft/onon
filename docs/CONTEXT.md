# Local Map and Path Recording

This context covers maps whose appearance can be adapted for screen use and reliable paper reproduction.

## Language

**Base Map**:
The geographic reference map upon which recorded paths and symbols are shown.
_Avoid_: Edited map, annotations

**Display Profile**:
A named set of visual distinctions suited to a particular screen or printing condition.
_Avoid_: Theme, colour mode

**Screen Profile**:
A **Display Profile** designed for ordinary colour screens.

**Blue-Light Print Profile**:
A **Display Profile** designed to remain legible on paper viewed under blue-tinted LED light.

**Greyscale Print Profile**:
A **Display Profile** that maps visually distant colours to visually distant grey values.
_Avoid_: Desaturated map, black-and-white filter

**Recommended Visual Scale**:
A curated set of colours, grey values, line weights, patterns, and outlines chosen to preserve meaningful visual separation.
_Avoid_: Automatic conversion, arbitrary palette, colour-only distinction

**Raw Recording**:
The immutable ordered GPS observations, their available accuracy and motion data, and waypoint observations captured by one **Recording Session**.
_Avoid_: Editable trail, cleaned path

**Trail Overlay**:
An editable geographic line derived from a **Raw Recording** and displayed above the **Base Map**.
_Avoid_: Base-map trail, route

**Direction Arrow**:
A user-placed symbol attached beside a **Trail Overlay** that shows the trail's recorded direction.
_Avoid_: Free-standing arrow, compass heading

**Waypoint**:
A point symbol whose centre dot marks its exact coordinate and whose outer circle keeps it visible.
_Avoid_: Approximate area, trail vertex

**Recording Session**:
A user-started period of location capture that produces one **Raw Recording** and continues through phone sleep or locking.
_Avoid_: Foreground-only tracking, map viewing session

**Offline Map Area**:
A bounded portion of the **Base Map** retained on a device for use without the local map server.
_Avoid_: Whole-map cache, screenshot

**Pending Recording**:
A **Raw Recording** retained on its recording device until it can be transferred to the local server.
_Avoid_: Failed upload, temporary path

**Local-First Recording**:
A recording workflow whose essential capture and recovery remain available without an account or server connection.
_Avoid_: Cloud-first sync, account-owned recording

**Device Pairing**:
A local trust step that authorizes one device to transfer and change map data without creating an account.
_Avoid_: User login, public LAN access

**Print Export**:
A PDF map file prepared by the workspace for transfer to and printing from a laptop or desktop.
_Avoid_: In-app printing, browser screenshot

**Print Scale**:
The fixed relationship between distance on a **Print Export** and distance on the ground.
_Avoid_: Fit-to-page zoom, Recommended Visual Scale

**Sydney Service Area**:
The initial map area east of Parramatta, south of Hornsby, north of Sutherland, and extending one nautical mile offshore.
_Avoid_: Greater Sydney, New South Wales

### Map and rendering terms

| Term | Meaning |
| --- | --- |
| Surface road | Road visible above ground; excludes tunnels, ferry routes and railways. Bridges remain visible. |
| Carriageway | Physical roadway. Separate carriageways retain separate map geometry. A cycleway beside a street is not another road carriageway. |
| Vector tile archive | Downloaded PMTiles file containing features at multiple zooms. Rendering styles choose how those features look. |
| Style layer | Drawing rule over a shared tile source; does not itself imply another tile download. |
| Local rendering | Rendering from assets hosted on this computer, independent of external map services. |
| Offline tile cache | Assets stored on the viewing device for use without a network or local server. Separate from local rendering. |
| Bundled map | Fixed map region, styles, fonts and sprites packaged inside the phone app. Works offline from first launch; separate from a selectable route cache. |
| Recording overlay | GPS trail and waypoint annotations drawn above the base map. Recording controls are a separate interface overlay. |

## Relationships

- A **Base Map** can be presented through one of many **Display Profiles**.
- The **Screen Profile**, **Blue-Light Print Profile**, and **Greyscale Print Profile** are distinct **Display Profiles**.
- A **Display Profile** uses a **Recommended Visual Scale**.
- A **Base Map** can show zero or more **Trail Overlays**.
- A **Trail Overlay** is derived from exactly one **Raw Recording**.
- Editing a **Trail Overlay** never changes its **Raw Recording**.
- MVP editing of a **Trail Overlay** is limited to trimming its ends and removing a selected bad section, with undo and redo.
- A **Direction Arrow** belongs to exactly one **Trail Overlay**.
- A **Direction Arrow** derives its orientation from its **Trail Overlay** and may be moved to either side.
- A **Waypoint** may sit on or off a **Trail Overlay**.
- A **Recording Session** may add zero or more **Waypoints** at the device's current location.
- A **Waypoint** may be added or moved during later map editing.
- A **Recording Session** produces exactly one **Raw Recording**.
- A **Recording Session** is active or paused until the user finishes it.
- Finishing a **Recording Session** requires confirmation.
- An unfinished **Recording Session** survives an app interruption and can resume.
- An **Offline Map Area** contains the map resources needed to view its bounds without the local map server.
- A device may retain overview detail for the whole **Sydney Service Area** and field detail for selected **Offline Map Areas**.
- A completed **Recording Session** may produce a **Pending Recording**.
- A **Pending Recording** remains on its recording device until the local server confirms receipt.
- Repeated transfer of one **Pending Recording** creates only one server copy.
- Every **Recording Session** uses **Local-First Recording**.
- A device completes **Device Pairing** before transferring recordings to the local server.
- A **Print Export** presents the **Base Map**, selected overlays, and one **Display Profile**.
- A **Print Export** uses a **Print Scale** of 1:10,000, 1:15,000, or 1:25,000.
- A **Print Export** uses A4 portrait or landscape and shows its exact crop before export.
- The initial **Base Map** covers the **Sydney Service Area**.

## Example dialogue

> **Dev:** “Should greyscale output simply remove colour from the **Base Map**?”
> **Domain expert:** “No. Use the **Greyscale Print Profile** so features remain distinguishable after printing.”

## Flagged ambiguities

- “Changes to maps” means changing map appearance through a **Display Profile**, not changing geographic source data.
- Automatic colour-to-grey conversion is deferred; initial profiles use **Recommended Visual Scales**.
- Phone sleep or locking does not end an active **Recording Session**.
- Phone sleep or locking does not pause an active **Recording Session**.
- “Honsby” is understood as Hornsby.
- MVP has no accounts; identity and multi-user ownership remain deferred.
- MVP provides PDF **Print Exports**; SVG and image exports remain deferred.
- The default **Print Scale** is 1:10,000.
- Freehand redrawing, splitting, and joining **Trail Overlays** remain deferred.
- Automatic snapping of a **Raw Recording** to mapped roads or paths remains deferred.

## Architecture

### Runtime boundary

- iPhone runs a native SwiftUI application. It never runs containers.
- Mac laptop runs individually scripted Apple containers. It has no Compose file.
- PostgreSQL and service ports stay private where possible; Web/API and map endpoints are exposed to the trusted LAN.

### Dependency direction

```text
SwiftUI recorder ---> versioned HTTP contract <--- TypeScript API ---> PostgreSQL
       |                                            |
       +------------ TileServer GL <----------------+
                           ^
                           |
                   Planetiler map job
```

Clients depend on the versioned API and map manifests. They do not depend on PostgreSQL schemas or container names.

## API contract

**Version:** `v1`
**Status:** implementation contract

The native iPhone app and local web workspace use this contract. Times are ISO 8601 UTC strings. IDs are UUID strings. The recording device generates Raw Recording, device and raw waypoint-observation IDs; the server generates Trail Overlay, editable Waypoint and Direction Arrow IDs. Coordinates are WGS84 decimal degrees.

### Authentication

- Native device requests use `Authorization: Bearer <device-token>`.
- Web mutations use an HTTP-only, same-site local admin cookie.
- Map reads and health checks require no authentication on the trusted local network.
- A one-time pairing code expires after first use or ten minutes.
- The native device token is returned once and stored in iOS Keychain.

### Health

#### `GET /health`

Returns `200` when the API and database are ready.

```json
{
  "status": "ok",
  "database": "ok",
  "mapVersion": "2026-07-21T00:00:00Z"
}
```

### Local Admin Session

#### `POST /api/v1/admin/session`

Exchanges the bootstrap secret for the local web cookie.

```json
{ "bootstrapToken": "local-secret" }
```

### Device Pairing

The iPhone validates the QR destination as a local laptop origin and displays it
for approval before calling the exchange endpoint. Completed Raw Recordings may
upload only after that approval. Pairing and upload requests do not follow HTTP
redirects. The wire schemas below are unchanged.

#### `POST /api/v1/pairing-codes`

Admin cookie required. Returns a short-lived code and QR payload.

```json
{
  "code": "123456",
  "expiresAt": "2026-07-21T10:10:00Z",
  "qrPayload": "onon://pair?server=http%3A%2F%2Fonon.local%3A3000&code=123456"
}
```

#### `POST /api/v1/pairings/exchange`

Consumes a one-time code.

```json
{
  "code": "123456",
  "deviceId": "00931bab-c60d-4143-8444-5fd42f9a63e0",
  "deviceName": "Field iPhone"
}
```

```json
{
  "deviceToken": "returned-once",
  "deviceId": "00931bab-c60d-4143-8444-5fd42f9a63e0"
}
```

### Immutable Recordings

#### `POST /api/v1/recordings`

Device token required. `Idempotency-Key` must equal the recording UUID. A repeated identical upload returns `existing`; a different body with an existing key returns `409`.

```json
{
  "id": "8a607ee6-660a-4d2d-9cc9-730e1ed48c31",
  "startedAt": "2026-07-21T09:00:00Z",
  "finishedAt": "2026-07-21T09:30:00Z",
  "samples": [
    {
      "sequence": 0,
      "recordedAt": "2026-07-21T09:00:01Z",
      "latitude": -33.8688,
      "longitude": 151.2093,
      "horizontalAccuracy": 4.2,
      "altitude": 18.1,
      "verticalAccuracy": 6.0,
      "speed": 1.3,
      "course": 87.0
    }
  ],
  "waypoints": [
    {
      "id": "97b80af8-6095-4638-97e9-0cf62ad3fd88",
      "recordedAt": "2026-07-21T09:10:00Z",
      "latitude": -33.87,
      "longitude": 151.21,
      "horizontalAccuracy": 3.8
    }
  ]
}
```

```json
{
  "recordingId": "8a607ee6-660a-4d2d-9cc9-730e1ed48c31",
  "status": "created"
}
```

#### `GET /api/v1/recordings`

Admin cookie required. Lists recording metadata, not sample payloads.

#### `GET /api/v1/recordings/:recordingId`

Admin cookie required. Returns immutable recording and samples.

### Trail Overlays

All endpoints below require the admin cookie. Creation endpoints return the
complete current `TrailDocument`; clients use its returned IDs in subsequent
requests. Editable resource IDs are generated by the server, never supplied in
these creation payloads.

```typescript
type TrailDocument = {
  id: string;                  // Trail Overlay UUID
  recordingId: string;         // source Raw Recording UUID
  name: string;
  version: number;             // current geometry revision
  geometry: { type: "MultiLineString"; coordinates: number[][][] };
  sourceSampleIndexes: number[][];
  waypoints: { id: string; latitude: number; longitude: number; label: string | null }[];
  directionArrows: {
    id: string; segmentIndex: number; position: number; side: "left" | "right";
    latitude: number; longitude: number; bearing: number;
  }[];
  canUndo: boolean;
  canRedo: boolean;
};
```

GeoJSON coordinates are `[longitude, latitude]`. `sourceSampleIndexes` mirrors
the geometry's lines using indexes in the immutable Raw Recording.
`segmentIndex` counts adjacent coordinate pairs across all current lines, in
order. Arrow coordinates and bearing are derived by the server.

New overlays begin at `version: 0`. Geometry operations, undo and redo produce
new versions; Waypoint and Direction Arrow mutations return the current geometry
version without incrementing it. Symbol mutations do not accept `expectedVersion`.

#### `POST /api/v1/recordings/:recordingId/trail-overlays`

Request: no body. The path contains the existing Raw Recording UUID.
Returns `201` with `TrailDocument` plus `"status": "created"`, or `200` with
`TrailDocument` plus `"status": "existing"` when that recording already has an
overlay. The server generates the overlay UUID and IDs for any copied editable
Waypoints. An existing overlay retains its current version. The Raw Recording
must exist and contain at least two samples.

#### `GET /api/v1/trail-overlays/:trailOverlayId`

Admin cookie required. Returns versioned GeoJSON MultiLineString, editable waypoints, and direction arrows.

#### `POST /api/v1/trail-overlays/:trailOverlayId/operations`

Admin cookie required. `expectedVersion` prevents stale writes.

```json
{
  "expectedVersion": 3,
  "operation": {
    "type": "remove_range",
    "fromIndex": 12,
    "toIndex": 20
  }
}
```

Supported geometry operations:

- `trim_start` with `throughIndex`.
- `trim_end` with `fromIndex`.
- `remove_range` with inclusive `fromIndex` and `toIndex`.

#### `POST /api/v1/trail-overlays/:trailOverlayId/undo`

#### `POST /api/v1/trail-overlays/:trailOverlayId/redo`

Both require admin cookie and create a new overlay version. Raw recording tables are never updated.

#### `POST /api/v1/trail-overlays/:trailOverlayId/waypoints`

Request JSON:

```json
{ "latitude": -33.8688, "longitude": 151.2093, "label": "Gate" }
```

`latitude` and `longitude` are required, in `[-90, 90]` and `[-180, 180]`.
`label` is optional (default `null`), nullable, and at most 200 characters.
Returns `201` with `TrailDocument`, whose `waypoints` array includes the new
server-generated UUID, exact coordinates and label. This does not add a raw
waypoint observation or change the geometry version.

#### `PATCH /api/v1/trail-overlays/:trailOverlayId/waypoints/:waypointId`

Moves or renames an editable waypoint.

#### `POST /api/v1/trail-overlays/:trailOverlayId/direction-arrows`

Request JSON:

```json
{ "segmentIndex": 0, "position": 0.5, "side": "right" }
```

`segmentIndex` is a required nonnegative integer naming an existing pair in the
current geometry. `position` is an optional fraction in `[0, 1]` (default `0.5`);
`side` is optional, `left` or `right` (default `right`). Returns `201` with
`TrailDocument`, whose `directionArrows` array includes the server-generated UUID,
segment index, fraction, side, derived coordinates and bearing. Geometry version
is unchanged. An index outside the current trail returns `422` with
`{"error":"arrow_segment_outside_trail"}`.

### Map Manifest

The manifest keeps the configured LAN hostname for native clients. The web
workspace substitutes the hostname used to open the page while preserving the
TileServer port, so both loopback and LAN-host access load the same local tiles.

#### `GET /api/v1/maps/manifest`

```json
{
  "version": "2026-07-21T00:00:00Z",
  "bounds": [151.00, -34.04, 151.33, -33.70],
  "overviewMaxZoom": 11,
  "detailMaxZoom": 14,
  "styles": {
    "screen": "http://onon-host.local:8081/styles/screen/style.json",
    "blueLightPrint": "http://onon-host.local:8081/styles/blue-light-print/style.json",
    "greyscalePrint": "http://onon-host.local:8081/styles/greyscale-print/style.json"
  }
}
```

### PDF Export

#### `POST /api/v1/exports/pdf`

Admin cookie required.

```json
{
  "trailOverlayId": "0df6dcf0-cbe6-48cb-95ea-7b5e5c34054e",
  "profile": "greyscalePrint",
  "orientation": "landscape",
  "scale": 10000,
  "center": [151.2093, -33.8688]
}
```

Returns `application/pdf`. Supported scales are `10000`, `15000`, and `25000`. Supported orientations are `portrait` and `landscape`.

## Database decision

**Status:** accepted.

Use PostgreSQL instead of SQLite even though SQLite would simplify the single-user local MVP. The product is intended to move online after the local workflow proves itself; accepting one extra Apple container, explicit backups, and service startup now avoids a database-engine migration when concurrency and hosted deployment arrive. PostGIS remains deferred until spatial database queries justify it.

## Protomaps surface-map trial

This separate, zoomable Sydney map trials Protomaps Light with surface roads and walking paths. It does not replace the workspace map, iOS offline packs or PDF renderer.

### Run

On Apple Silicon macOS, with the repository's pnpm dependencies installed:

```sh
bash scripts/download-protomaps-trial.sh
bash scripts/start-protomaps-trial.sh
```

Open <http://127.0.0.1:8083/protomaps.html>. Stop with Ctrl-C. Both servers bind only to loopback; tiles use port 8082 and the viewer uses 8083. The starter builds the viewer with existing Vite/MapLibre dependencies and serves static assets with Python 3. Set an absolute `ONON_DATA_ROOT` to store the trial elsewhere.

Downloads live in ignored `.local/onon/protomaps-trial/`. After downloading and installing dependencies, startup/rendering needs no external network: tiles, English glyphs, icons, style and viewer assets are local. This is **host-local rendering**, not a browser/device offline tile cache. A phone still needs an integrated source and its own cached assets; selectable route caching remains future work.

### Data and appearance

- Sydney archive: 8,707,011 bytes, 208 vector tiles, zooms 0–15; higher viewer zooms overzoom those tiles. Bounds: west 151.15, south -33.92, east 151.25, north -33.80. Tiles intersecting the bounds can contain features beyond the requested rectangle.
- Source: Protomaps daily build `20261009.pmtiles`, schema 4.15.2, OSM replication timestamp `2026-10-09T04:00:00Z`. This is another prepared OSM dataset, not an independent road survey.
- Style library: `@protomaps/basemaps` 5.7.2; asset commit `028c18f713baecad011301ff7a69acc39bcc2ae7`; PMTiles CLI 1.31.2. Downloads use pinned hashes and atomic writes; cached runs verify and reuse files. Dated upstream builds have limited retention: preserve the downloaded archive. A future refresh needs a new dated source and verified regional hash.
- Ordinary road geometry renders as one ribbon. Actual separate carriageways retain separate source geometry, including Western Distributor. Cycleways/sidewalks do not become extra road ribbons. Road strokes and labels exclude tunnels, ferries and railways; walking paths have thin dashed strokes. Bridges remain visible.
- No road geometry is merged or written back into OSM. If a future area has duplicated actual road centerlines, that needs a geometry/data review rather than suppressing all split roads.
- English labels use local Noto Sans Regular/Italic/Medium glyphs, including extended Latin, combining accents, Arabic and punctuation ranges observed in Sydney labels. Other writing systems need additional glyphs before claiming offline coverage; upstream Italic Arabic is empty.

All style layers share the same vector tile source: adding a drawing layer does not download another copy of each tile. Cache cost depends on covered area and zooms, not simply the number of style layers. The downloaded rectangle is broader than a typical 5–10 km route; route-corridor caching should reduce it further.

### Licenses

OSM data is ODbL with attribution in the map. Protomaps basemap styles are BSD-3-Clause; the downloader includes `basemaps-LICENSE.md`. Noto fonts use the SIL Open Font License; [font license](https://github.com/notofonts/noto-fonts/blob/main/LICENSE). See [Protomaps downloads](https://docs.protomaps.com/basemaps/downloads) and [MapLibre setup](https://docs.protomaps.com/basemaps/maplibre).

## Repository workflow

### Issue tracker

Use GitHub issues in `michft/onon`. Always select the repository explicitly
with `--repo michft/onon` when using `gh issue` or `gh pr`; do not infer it from
another fork or a shared playbook. `ISSUES.md` holds local discoveries and
pitfalls; it does not replace the GitHub issue tracker.

- Search open and closed issues before filing duplicates. Use `--body-file` for
  multiline issues, comments, and PR descriptions.
- Publish issues or comments only when requested as part of the task. A ready
  label does not itself authorize implementation or publication.
- Link an implementation PR to its issue when one exists. Use `Refs` for partial
  work and `Closes` only when the issue's acceptance criteria are complete.
- Keep unrelated or upstream work in its own tracker; changing the destination
  requires an explicit decision.

### Triage labels

Use these canonical states, with exactly one state on each triaged issue:

- `needs-triage`: awaiting maintainer evaluation.
- `needs-info`: waiting for specific evidence from the reporter.
- `ready-for-agent`: accepted, specified work suitable for an assigned agent.
- `ready-for-human`: accepted work needing human judgment or implementation.
- `wontfix`: not accepted; close with the reason.

Each triaged issue also has one category, `bug` or `enhancement`. Remove the
previous state when transitioning. `via-triage` records provenance, not readiness.
If labels are missing or states conflict, report the gap instead of inventing
aliases or silently changing GitHub configuration. A reporter reply to
`needs-info` needs maintainer re-evaluation; it does not launch an agent.
Assign an owner before starting accepted work and track progress through its
assignment and implementation PR, without extra in-progress labels.

## Documentation and project records

This file owns domain language, boundaries, contracts, decisions, and repository
workflow settings. Preserve the distinct concepts defined here; raise conflicts
before changing an agreed design. Do not create parallel domain or glossary docs
to satisfy a skill's default layout.

- [PLAN.md](PLAN.md): future work and approved delivery scope. Record proposals
  here before implementing them; keep acceptance gaps explicit.
- [TESTING.md](TESTING.md): implementation conventions, focused validation,
  evidence, and what done means. Consult before changing code or tests.
- [CHANGELOG.md](../CHANGELOG.md): completed changes. Add user-visible changes
  under Unreleased; never record future promises as completed work.
- [ISSUES.md](ISSUES.md): local agent discoveries and environment pitfalls.
  Read before starting; report surprises to the developer and record material
  discoveries here. This does not replace the GitHub tracker.
- [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md): location-data handling,
  access, trust boundaries, and deployment safeguards.

Check git-ignored `.plans/` for relevant session handoffs, newest first; continue
only work within the current request. Keep handoffs there, with uppercase
filename stems. Update affected area documentation when behavior or setup
changes. Folder READMEs serve both agents and humans.
