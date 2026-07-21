# Architecture

## Runtime boundary

- iPhone runs a native SwiftUI application. It never runs containers.
- Mac laptop runs individually scripted Apple containers. It has no Compose file.
- PostgreSQL and service ports stay private where possible; Web/API and map endpoints are exposed to the trusted LAN.

## Data boundary

- A raw recording is immutable after completion.
- An editable trail overlay is derived from one raw recording.
- Device sync is idempotent and keeps a local copy until confirmation.
- Display profiles affect presentation, never geographic source data.

## Dependency direction

```text
SwiftUI recorder ---> versioned HTTP contract <--- TypeScript API ---> PostgreSQL
       |                                            |
       +------------ TileServer GL <----------------+
                           ^
                           |
                   Planetiler map job
```

Clients depend on the versioned API and map manifests. They do not depend on PostgreSQL schemas or container names.
