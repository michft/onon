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
    bounds: [151.15, -33.92, 151.25, -33.80],
    sourceBuild: "20261009",
    sha256: "4035d24abf7aa0fcf2edc0a299d46a7fa17caf5dd099d2b5c585199a12509060",
    scenes: {
      streets: { label: "CBD streets", center: [151.2024, -33.8685], zoom: 17, bearing: 45 },
      water: { label: "Harbour", center: [151.210, -33.856], zoom: 14.5, bearing: 0 },
      park: { label: "Park paths", center: [151.216, -33.863], zoom: 16, bearing: 0 },
    },
  },
  melbourne: {
    id: "melbourne", name: "Melbourne",
    bounds: [144.85, -37.95, 145.10, -37.70],
    sourceBuild: "20261030",
    sha256: "934f26ff5228857e606d47ac863a0f420fd37e238de9a36f338075f90b98ae04",
    scenes: {
      streets: { label: "CBD streets", center: [144.9631, -37.8136], zoom: 16.5, bearing: 0 },
      water: { label: "Yarra River", center: [144.9674, -37.8198], zoom: 16.5, bearing: 0 },
      park: { label: "Botanic Gardens", center: [144.9798, -37.8317], zoom: 16, bearing: 0 },
    },
  },
} satisfies Record<string, MapRegion>;

export function mapRegion(id: string): MapRegion {
  const region = Object.values(mapRegions).find((value) => value.id === id);
  if (!region) throw new Error("ONON_PROTOMAPS_REGION must be sydney or melbourne");
  return region;
}
