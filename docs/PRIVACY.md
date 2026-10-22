# Privacy

Onon records precise location history. Treat the iPhone database, PostgreSQL volume, exports, and backups as sensitive.

## MVP data flow

- Raw GPS samples are written to the iPhone first.
- A completed recording transfers only to the paired local laptop server.
- Scanning a pairing QR does not transfer data. The phone first displays the
  destination and asks permission to pair and enable automatic uploads; Cancel
  preserves the existing destination. Unapproved stored destinations cannot upload.
- The iPhone retains its raw copy after server confirmation.
- Map source data comes from OpenStreetMap; Onon does not upload recordings to OpenStreetMap.
- No Onon account, cloud sync, analytics, advertising, or telemetry exists in the MVP.

## Operator responsibilities

- Use a trusted local network.
- Keep the Mac login and disk encryption enabled.
- Store backup files on encrypted storage.
- Revoke a paired device if the phone is lost.
- Delete exports manually when no longer needed; export cleanup never deletes raw recordings.

Moving the server online requires a new security/privacy review before exposing any endpoint.
