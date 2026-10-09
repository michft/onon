import { convertFilter, type StyleSpecification } from "@maplibre/maplibre-gl-style-spec";

/** Keep the source's carriageways, but separate paths from surface roads. */
export function surfaceMapStyle(style: StyleSpecification): StyleSpecification {
  const layers = style.layers.map((layer) => {
    if (layer.id === "pois" && layer.type === "symbol") {
      return { ...layer, layout: { ...layer.layout, "icon-image": [
        "match", ["get", "kind"], "station", "train_station", "townhall", "townspot", ["get", "kind"]
      ] } } satisfies typeof layer;
    }
    if (!("source-layer" in layer) || layer["source-layer"] !== "roads") return layer;
    return {
      ...layer,
      filter: [
        "all",
        layer.filter ? convertFilter(layer.filter) : true,
        ["!=", ["get", "is_tunnel"], true],
        ["in", ["get", "kind"], ["literal", ["highway", "major_road", "minor_road"]]]
      ]
    } satisfies typeof layer;
  });
  const roads = layers.find((layer) => "source-layer" in layer && layer["source-layer"] === "roads");
  if (roads && "source" in roads) {
    const firstLabel = layers.findIndex((layer) => layer.type === "symbol");
    layers.splice(firstLabel < 0 ? layers.length : firstLabel, 0, {
      id: "walking-paths",
      type: "line",
      source: roads.source,
      "source-layer": "roads",
      minzoom: 13,
      filter: ["all",
        ["==", ["get", "kind"], "path"],
        ["!=", ["get", "is_tunnel"], true],
        ["!", ["in", ["get", "kind_detail"], ["literal", ["cycleway", "sidewalk", "crossing", "corridor"]]]]
      ],
      paint: { "line-color": "#8b958e", "line-width": 1.2, "line-dasharray": [2, 2] }
    });
  }
  return { ...style, name: "Onon surface roads · Protomaps Light", layers };
}
