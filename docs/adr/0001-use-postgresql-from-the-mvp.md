---
status: accepted
---

# Use PostgreSQL from the MVP

Use PostgreSQL instead of SQLite even though SQLite would simplify the single-user local MVP. The product is intended to move online after the local workflow proves itself; accepting one extra Apple container, explicit backups, and service startup now avoids a database-engine migration when concurrency and hosted deployment arrive. PostGIS remains deferred until spatial database queries justify it.
