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
`infra/config/local.env`, then unlock with its `ADMIN_TOKEN`. Open
`apps/ios/Onon.xcodeproj` in Xcode, select personal development team, then
install on iPhone.

Product language: [CONTEXT.md](./CONTEXT.md). Approved scope and acceptance
tests: [PLAN.md](./PLAN.md). Integration boundary:
[docs/API_CONTRACT.md](./docs/API_CONTRACT.md). Validation guide:
[docs/TESTING.md](./docs/TESTING.md).

## Parts

- `infra/` and `scripts/`: Apple-container local map/database platform.
- `apps/ios/`: native SwiftUI recorder.
- `apps/api/`: TypeScript API and PDF export.
- `apps/web/`: MapLibre web workspace.

No Docker Compose file is used.
