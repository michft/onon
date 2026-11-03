interface MapScene {
  label: string;
  center: [number, number];
  zoom: number;
  bearing: number;
}

export interface MapRegion {
  id: string;
  name: string;
  bounds: [number, number, number, number];
  sourceBuild: string;
  sha256: string;
  scenes: Record<"streets" | "water" | "park", MapScene>;
}

export const mapRegions = {
  sydney: {
    id: "sydney", name: "Sydney",
    // Penrith to the sea, Hornsby to Sutherland.
    bounds: [150.65, -34.06, 151.34, -33.67],
    sourceBuild: "20261030",
    sha256: "d4e5fa05c3464ce3fbf78a0a9030032917f6b528029ff5289fdd22a7b1d6ef3b",
    scenes: {
      streets: { label: "CBD streets", center: [151.2024, -33.8685], zoom: 17, bearing: 45 },
      water: { label: "Harbour", center: [151.210, -33.856], zoom: 14.5, bearing: 0 },
      park: { label: "Park paths", center: [151.216, -33.863], zoom: 16, bearing: 0 },
    },
  },
  melbourne: {
    id: "melbourne", name: "Melbourne",
    // West to the Airport, east past La Trobe to Monash Clayton, north of South Morang, south below Clayton.
    bounds: [144.80, -37.96, 145.16, -37.58],
    sourceBuild: "20261030",
    sha256: "154dc4cab2108c04de404013e730f95bcb55440145f8fee94217cc56bfb110bf",
    scenes: {
      streets: { label: "CBD streets", center: [144.9631, -37.8136], zoom: 16.5, bearing: 0 },
      water: { label: "Yarra River", center: [144.9674, -37.8198], zoom: 16.5, bearing: 0 },
      park: { label: "Botanic Gardens", center: [144.9798, -37.8317], zoom: 16, bearing: 0 },
    },
  },
} satisfies Record<string, MapRegion>;

/** Every region in one archive, bundled into the iPhone app for offline use. */
export const nativeBundle = {
  file: "onon-regions.pmtiles",
  sourceBuild: "20261030",
  sha256: "7430e1ac2d42f01108f4dea0539e2bba35b1a7cfe59f8c27c0471c6ebdc7d01f",
  regions: [mapRegions.sydney, mapRegions.melbourne],
};

/** GeoJSON MultiPolygon of the bundled regions, the `pmtiles extract --region` input. */
export function nativeBundleArea() {
  return {
    type: "MultiPolygon",
    coordinates: nativeBundle.regions.map(({ bounds: [west, south, east, north] }) => [
      [[west, south], [east, south], [east, north], [west, north], [west, south]],
    ]),
  };
}

export function mapRegion(id: string): MapRegion {
  const region = Object.values(mapRegions).find((value) => value.id === id);
  if (!region) throw new Error("ONON_PROTOMAPS_REGION must be sydney or melbourne");
  return region;
}
