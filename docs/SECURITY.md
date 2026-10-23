# Local MVP Security

## Trust model

- Web administration starts by exchanging the bootstrap token for an HTTP-only, same-site cookie.
- iPhone pairing uses a one-time code that expires after ten minutes.
- Incoming QR links stage a local laptop destination for explicit approval before
  exchanging credentials or enabling uploads. Existing pairings without approved
  origin metadata must be approved again with a new QR.
- iOS accepts only `.local`, localhost and private LAN IP server origins, without
  URL credentials, non-root paths, query strings or fragments. Pairing and upload
  requests reject redirects before forwarding data.
- The iPhone receives a random device token and stores it in Keychain.
- Device upload retries are authenticated and idempotent.
- PostgreSQL is not published to the LAN.
- Web/API and tile endpoints are intended for a trusted local network only.

## Secrets

- Runtime secrets live outside version control in `.env` or Keychain.
- Scripts must not print database passwords, bootstrap tokens, or device tokens.
- Backups include sensitive location history even when secrets are excluded.

## Not an internet deployment

Local HTTP and a non-secure admin cookie are deliberate MVP constraints. Before any public or remote deployment, require HTTPS, secure cookies, origin restrictions, rate limits, rotated secrets, database least privilege, and a new approval of the authentication model.
