# Map glossary

Existing product terms are defined in [CONTEXT.md](CONTEXT.md).

| Term | Meaning |
| --- | --- |
| Surface road | Road visible above ground; excludes tunnels, ferry routes and railways. Bridges remain visible. |
| Carriageway | Physical roadway. Separate carriageways retain separate map geometry. A cycleway beside a street is not another road carriageway. |
| Vector tile archive | Downloaded PMTiles file containing features at multiple zooms. Rendering styles choose how those features look. |
| Style layer | Drawing rule over a shared tile source; does not itself imply another tile download. |
| Local rendering | Rendering from assets hosted on this computer, independent of external map services. |
| Offline tile cache | Assets stored on the viewing device for use without a network or local server. Separate from local rendering. |
| Bundled map | Fixed map region, styles, fonts and sprites packaged inside the phone app. Works offline from first launch; separate from a selectable route cache. |
| Recording overlay | GPS trail and waypoint annotations drawn above the base map. Recording controls are a separate interface overlay. |
