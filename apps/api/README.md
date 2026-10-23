# Onon API

TypeScript/Fastify API for pairing, immutable recording sync, editable Trail Overlays, symbols, map discovery, and A4 PDF export.

## Required environment

```text
DATABASE_URL=postgres://onon:...@onon-postgres:5432/onon
ADMIN_TOKEN=a-long-random-bootstrap-secret
PUBLIC_BASE_URL=http://onon.local:3000
TILESERVER_URL=http://onon-tiles:8080
PUBLIC_TILESERVER_URL=http://onon.local:8081
MAP_VERSION=2026-07-21T00:00:00Z
CORS_ORIGIN=http://onon.local:5173
```

Run `pnpm migrate` before `pnpm start`. The migration adds database triggers which reject updates or deletes to all Raw Recording tables.

For a production image, run the web build, copy `apps/web/dist/` to `apps/api/public/`, then run the API build. Keep `apps/api/migrations/` beside `apps/api/dist/`. Run `pnpm migrate:prod` before `pnpm start:prod`; the API serves the copied workspace with SPA fallback while reserving `/api`, `/health`, and `/styles`.

The published native/web contract is [project context](../../docs/CONTEXT.md#api-contract). Additional web-only symbol operations are:

- `PATCH|DELETE /api/v1/trail-overlays/:trailOverlayId/waypoints/:waypointId`
- `PATCH|DELETE /api/v1/trail-overlays/:trailOverlayId/direction-arrows/:arrowId`

The PATCH arrow body accepts `segmentIndex`, `position`, and/or `side`. The server stores the underlying raw sample pair, so an arrow does not silently move when an earlier Trail Overlay section is removed.

PDF generation expects TileServer GL static rendering to permit the requested 300 DPI raster size (up to roughly 3,100 px on its long edge).
