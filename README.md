# Onon

Local-first OSM map, native iPhone trail recorder, and web editing/print workspace.

## Quick start

```sh
scripts/bootstrap-local.sh
scripts/refresh-map.sh
scripts/start-local.sh
scripts/status-local.sh
```

Open `http://<ONON_PUBLIC_HOST>:<ONON_WEB_PORT>` using values from git-ignored
`infra/config/local.env`, then unlock with its `ADMIN_TOKEN`.

Before building for iPhone, run `pnpm install --frozen-lockfile` and
`scripts/prepare-ios-map.sh`. Follow the [iOS requirements](apps/ios/README.md#requirements),
then open `apps/ios/Onon.xcodeproj`, select a personal development team and install.

Project context, plans, validation, and operating guidance live in [docs/](docs/).

## Melbourne rendered map

After installing the workspace dependencies:

```sh
ONON_PROTOMAPS_REGION=melbourne bash scripts/download-protomaps-trial.sh
ONON_PROTOMAPS_REGION=melbourne bash scripts/start-protomaps-trial.sh
```

Open <http://127.0.0.1:8083/protomaps.html>. Melbourne CBD/inner-suburb coverage
uses the same surface-road styles and local labels as Sydney. See
[map coverage and LAN setup](docs/CONTEXT.md#protomaps-surface-map-trial).
The native iPhone bundle remains Sydney; this adds locally rendered Melbourne tiles.

## Parts

- `infra/` and `scripts/`: Apple-container local map/database platform.
- `apps/ios/`: native SwiftUI recorder.
- `apps/api/`: TypeScript API and PDF export.
- `apps/web/`: MapLibre web workspace.

No Docker Compose file is used.
