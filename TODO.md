# TODO

- [x] Bundle the Sydney Protomaps extract, styles, fonts and sprites in iOS; show surface roads and readable labels under the recorder's trail/waypoint overlay without a tile server.
- [ ] Add an offline tile cache for 5–10 km runs using the chosen map source. Prefetch a route corridor or selected area with a safety margin and required zoom levels, plus styles, fonts and sprites. Share cached vector tiles across drawing layers/display profiles. Show size, download progress, update and delete controls; handle quota/eviction. Verify cold-start, pan, zoom and profile changes in airplane mode without the local tile server, including iPhone. Existing native offline packs must be assessed for Protomaps; the bundled Sydney map is fixed coverage, not a selectable route cache.
- [ ] Integrate the chosen surface-road style/source with the workspace viewer and PDF output; verify trail overlays and attribution in each.
