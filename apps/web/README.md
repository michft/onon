# Onon Web Workspace

Mobile-first React/MapLibre workspace for reviewing Raw Recordings, deriving and cleaning Trail Overlays, placing Waypoints and Direction Arrows, and exporting fixed-scale A4 PDFs.

Production uses the workspace origin for API requests. Set `VITE_API_URL` only when the API is on a different origin. The browser must reach the public TileServer URLs returned by `GET /api/v1/maps/manifest`.

The workspace uses the local bootstrap secret once to obtain the API's HTTP-only, same-site admin cookie. It does not store that secret in browser storage.

Editing gestures are deliberately bounded:

- Choose a trim tool, then click the Trail Overlay.
- Choose remove section, then click its first and last points.
- Choose Add Waypoint, then click its exact coordinate.
- Choose Add Arrow, then click its trail segment.
- Choose Move beside an existing symbol, then click its new position.

The dashed A4 crop follows the map centre and uses the same physical page/scale calculation as PDF export.
