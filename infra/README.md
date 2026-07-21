# Local infrastructure

Apple's `container` CLI launches each OCI container directly. There is no
Compose file. PostgreSQL and runtime services share the isolated
`onon-private` network; PostgreSQL has no published host port. TileServer and
Web/API publish LAN ports so a paired iPhone can reach them.

## Requirements

- Apple `container` CLI 1.1 or newer on Apple silicon.
- `curl`, `openssl`, `sqlite3`, `tar`, and `shasum` from macOS.
- Internet access only for bootstrap and manual map refresh.
- About 8 GB RAM for Planetiler by default, plus working disk space of roughly
  5–10 times the downloaded PBF size.
- TileServer uses 2 GB RAM by default so A4 300 dpi static renders have headroom.

## First setup

```sh
scripts/bootstrap-local.sh
scripts/refresh-map.sh
scripts/start-local.sh
scripts/status-local.sh
```

Bootstrap creates `infra/config/local.env`, an isolated application network, a
persistent Apple-container PostgreSQL volume, persistent host directories,
random database/admin secrets, pinned images, local Web/API image, and local
font/sprite assets. It does not start application containers. Override the data
location by adding an absolute `ONON_DATA_ROOT` to `local.env` before the first
map build.
The default is the git-ignored `.local/onon` directory in this repository.

The map refresh downloads Geofabrik's Australia extract, then Planetiler clips
generated tiles to `151.00,-34.04,151.33,-33.70`. This rectangle is a
conservative generation envelope around the agreed service area, not a legal or
administrative boundary. Change `ONON_SERVICE_BOUNDS` if field validation shows
the one-nautical-mile offshore edge needs adjustment.

## Operations

- `start-local.sh`: starts PostgreSQL, waits for readiness, then TileServer and
  the Web/API if `ONON_WEB_IMAGE` is configured.
- `stop-local.sh`: stops only Onon containers, in reverse dependency order.
  Containers and host data remain.
- `status-local.sh`: reports container state, service health, active map, and
  disk use.
- `refresh-map.sh`: downloads versioned source, makes a versioned candidate,
  runs SQLite and live TileServer smoke checks, atomically changes the active
  symlink, writes source/archive checksums, and recreates TileServer. Failed
  candidates never replace the active map. Previous source and tile archives
  remain until manually reviewed. Set `ONON_SOURCE_PBF` to an existing file
  under `maps/source/` when retrying a build without downloading it again.
- `backup-local.sh`: creates a custom-format PostgreSQL dump, infrastructure
  snapshot, manifest, and checksums under `backups/<UTC timestamp>`.
- `restore-local.sh /absolute/path/database.dump`: restores to a new staging
  database and validates it before switching names. The prior database is kept
  as `onon_before_<timestamp>`; it is never dropped automatically.

All scripts are safe to repeat. They never delete the PostgreSQL volume,
persistent map archives, backups, or old restored databases. Stopped PostgreSQL
and TileServer containers are reused. The stateless Web/API container is
recreated after a stop so it receives current Apple-container service IPs.
`refresh-map.sh` recreates only the ephemeral TileServer container when
activating a map.

## Endpoints

With default ports:

- Tile data: `http://<mac-lan-address>:8080/data/sydney.json`
- Screen style: `http://<mac-lan-address>:8080/styles/screen/style.json`
- Blue-light style: `http://<mac-lan-address>:8080/styles/blue-light-print/style.json`
- Greyscale style: `http://<mac-lan-address>:8080/styles/greyscale-print/style.json`
- Web/API: `http://<mac-lan-address>:3000`.

Unlock Web workspace with `ADMIN_TOKEN` from `infra/config/local.env`. File is
mode `0600`, git-ignored, and must not be shared.

Add the Mac's LAN hostname and address to `ONON_TILESERVER_ALLOWED_HOSTS` before
iPhone use. The server rewrites local `mbtiles://` and glyph paths in published
styles. Runtime tile, style, font, and sprite requests require no internet.

## Data layout

```text
Apple container volume:
  onon-postgres-data        PostgreSQL 17 data (20 GB default)

ONON_DATA_ROOT/
  maps/
    active.mbtiles         Relative symlink to current version
    candidates/            Failed/in-progress builds retained for inspection
    source/                Versioned OSM PBF inputs
    versions/              Validated MBTiles archives
  style-assets/fonts/      Pinned OpenMapTiles glyph PBFs
  style-assets/sprites/    Pinned OSM Bright sprites
  exports/                 Web/API print exports
  backups/                 Database/config backup sets
```

## Image and schema upgrades

Images are deliberately pinned in `infra/config/images.env`. Update one image at
a time, verify its ARM64 manifest, back up first, then stop and explicitly
delete that stopped runtime container so `start-local.sh` can recreate it with
the new image. Deleting a container does not delete its named volume.
PostgreSQL major upgrades require `pg_upgrade` or dump/restore; never point a
new major image directly at an old major-version data volume.

## Integration notes

- `bootstrap-local.sh` builds `ONON_WEB_IMAGE`; rerun
  `scripts/build-app-image.sh` after application changes.
- Application migrations run on each Web/API container start. Infrastructure
  waits for PostgreSQL readiness first.
- Three styles are compact fixed profiles. Automated luminance checks cover
  critical classes; physical printer and blue-LED calibration remains an
  acceptance test because software cannot simulate target paper, ink, and light.

## Attribution

Any screen or print composition using these tiles must visibly show:

`© OpenMapTiles © OpenStreetMap contributors`

OpenMapTiles schema/design attribution and OpenStreetMap database attribution
remain required even though all files are served locally.
