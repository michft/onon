import { describe, expect, it } from "vitest";
import { featureFilter, type Feature, type StyleSpecification } from "@maplibre/maplibre-gl-style-spec";
import { surfaceMapStyle } from "./protomaps-style";

const baseline: StyleSpecification = {
  version: 8,
  sources: { protomaps: { type: "vector", tiles: ["http://localhost/{z}/{x}/{y}.mvt"] } },
  layers: [
    { id: "roads", type: "line", source: "protomaps", "source-layer": "roads",
      filter: ["in", "kind", "minor_road", "major_road", "highway"] },
    { id: "links", type: "line", source: "protomaps", "source-layer": "roads",
      filter: ["==", ["get", "is_link"], true] },
    { id: "labels", type: "symbol", source: "protomaps", "source-layer": "roads" }
  ]
};

function visible(style: StyleSpecification, id: string, properties: Feature["properties"]) {
  const layer = style.layers.find((candidate) => candidate.id === id);
  if (!layer || !("filter" in layer)) throw new Error(`Missing layer: ${id}`);
  return featureFilter(layer.filter).filter({ zoom: 17 }, { type: "LineString", properties });
}

describe("surface road style", () => {
  it("keeps streets and both physical carriageways, separates paths, and hides tunnels/ferries from strokes and labels", () => {
    const style = surfaceMapStyle(baseline);
    for (const road of [
      { kind: "minor_road", kind_detail: "residential", name: "Kent Street" },
      { kind: "highway", name: "Western Distributor", oneway: 1, is_bridge: true },
      { kind: "highway", name: "Western Distributor", oneway: -1, is_bridge: true }
    ]) {
      expect(visible(style, "roads", road)).toBe(true);
      expect(visible(style, "labels", road)).toBe(true);
    }
    for (const excluded of [
      { kind: "path", kind_detail: "cycleway" },
      { kind: "ferry" }, { kind: "rail" },
      { kind: "highway", is_tunnel: true, is_link: true }
    ]) {
      for (const id of ["roads", "links", "labels"]) expect(visible(style, id, excluded)).toBe(false);
    }
    expect(visible(style, "walking-paths", { kind: "path", kind_detail: "footway" })).toBe(true);
    expect(visible(style, "walking-paths", { kind: "path", kind_detail: "cycleway" })).toBe(false);
    expect(visible(style, "links", { kind: "major_road", is_link: true })).toBe(true);
    expect(visible(style, "links", { kind: "major_road" })).toBe(false);
    expect(baseline.layers).toHaveLength(3);
  });
});
