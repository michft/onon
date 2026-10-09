# Local surface-map trial

This separate, zoomable Sydney map trials Protomaps Light with surface roads and walking paths. It does not replace the workspace map, iOS offline packs or PDF renderer.

## Run

On Apple Silicon macOS, with the repository's pnpm dependencies installed:

```sh
bash scripts/download-protomaps-trial.sh
bash scripts/start-protomaps-trial.sh
```

Open <http://127.0.0.1:8083/protomaps.html>. Stop with Ctrl-C. Both servers bind only to loopback; tiles use port 8082 and the viewer uses 8083. The starter builds the viewer with existing Vite/MapLibre dependencies and serves static assets with Python 3. Set an absolute `ONON_DATA_ROOT` to store the trial elsewhere.

Downloads live in ignored `.local/onon/protomaps-trial/`. After downloading and installing dependencies, startup/rendering needs no external network: tiles, English glyphs, icons, style and viewer assets are local. This is **host-local rendering**, not a browser/device offline tile cache. A phone still needs an integrated source and its own cached assets; see [TODO](../TODO.md).

## Data and appearance

- Sydney archive: 8,707,011 bytes, 208 vector tiles, zooms 0–15; higher viewer zooms overzoom those tiles. Bounds: west 151.15, south -33.92, east 151.25, north -33.80. Tiles intersecting the bounds can contain features beyond the requested rectangle.
- Source: Protomaps daily build `20261009.pmtiles`, schema 4.15.2, OSM replication timestamp `2026-10-09T04:00:00Z`. This is another prepared OSM dataset, not an independent road survey.
- Style library: `@protomaps/basemaps` 5.7.2; asset commit `028c18f713baecad011301ff7a69acc39bcc2ae7`; PMTiles CLI 1.31.2. Downloads use pinned hashes and atomic writes; cached runs verify and reuse files. Dated upstream builds have limited retention: preserve the downloaded archive. A future refresh needs a new dated source and verified regional hash.
- Ordinary road geometry renders as one ribbon. Actual separate carriageways retain separate source geometry, including Western Distributor. Cycleways/sidewalks do not become extra road ribbons. Road strokes and labels exclude tunnels, ferries and railways; walking paths have thin dashed strokes. Bridges remain visible.
- No road geometry is merged or written back into OSM. If a future area has duplicated actual road centerlines, that needs a geometry/data review rather than suppressing all split roads.
- English labels use local Noto Sans Regular/Italic/Medium glyphs, including extended Latin, combining accents, Arabic and punctuation ranges observed in Sydney labels. Other writing systems need additional glyphs before claiming offline coverage; upstream Italic Arabic is empty.

All style layers share the same vector tile source: adding a drawing layer does not download another copy of each tile. Cache cost depends on covered area and zooms, not simply the number of style layers. The downloaded rectangle is broader than a typical 5–10 km route; route-corridor caching should reduce it further.

## Validation

Run `pnpm --filter @onon/web typecheck`, `pnpm --filter @onon/web test -- src/protomaps-style.test.ts` and `bash -n scripts/{download,start}-protomaps-trial.sh`. The starter performs the trial production build. The regression test evaluates MapLibre filters for streets, both carriageways, paths, tunnels, ferries and labels.

The viewer's Content Security Policy restricts map connections and images to local resources. Verify a fresh browser load, then pan, zoom and switch CBD/harbour/park scenes with no failed requests. This proves independence from external services while the local servers run. It does not prove airplane-mode operation on iPhone or browser caching after the servers stop.

## Licenses

OSM data is ODbL with attribution in the map. Protomaps basemap styles are BSD-3-Clause; the downloader includes `basemaps-LICENSE.md`. Noto fonts use the SIL Open Font License; [font license](https://github.com/notofonts/noto-fonts/blob/main/LICENSE). See [Protomaps downloads](https://docs.protomaps.com/basemaps/downloads) and [MapLibre setup](https://docs.protomaps.com/basemaps/maplibre).
