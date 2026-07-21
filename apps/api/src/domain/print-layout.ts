export const PRINT_SCALES = [10_000, 15_000, 25_000] as const;
export type PrintScale = (typeof PRINT_SCALES)[number];
export type Orientation = "portrait" | "landscape";

const A4_MM = { width: 210, height: 297 } as const;
const MARGIN_MM = 12;
const HEADER_MM = 18;
const EARTH_RADIUS_M = 6_378_137;

export interface PrintLayout {
  pageWidthMm: number;
  pageHeightMm: number;
  mapWidthMm: number;
  mapHeightMm: number;
  groundWidthM: number;
  groundHeightM: number;
  bounds: [west: number, south: number, east: number, north: number];
  rasterWidthPx: number;
  rasterHeightPx: number;
}

export function calculatePrintLayout(
  center: { latitude: number; longitude: number },
  scale: PrintScale,
  orientation: Orientation,
  dpi = 300
): PrintLayout {
  const [pageWidthMm, pageHeightMm] = orientation === "portrait"
    ? [A4_MM.width, A4_MM.height]
    : [A4_MM.height, A4_MM.width];
  const mapWidthMm = pageWidthMm - 2 * MARGIN_MM;
  const mapHeightMm = pageHeightMm - 2 * MARGIN_MM - HEADER_MM;
  const groundWidthM = mapWidthMm * scale / 1_000;
  const groundHeightM = mapHeightMm * scale / 1_000;
  const latitudeRadians = center.latitude * Math.PI / 180;
  const latitudeDelta = groundHeightM / EARTH_RADIUS_M * 180 / Math.PI;
  const longitudeDelta = groundWidthM / (EARTH_RADIUS_M * Math.cos(latitudeRadians)) * 180 / Math.PI;
  return {
    pageWidthMm,
    pageHeightMm,
    mapWidthMm,
    mapHeightMm,
    groundWidthM,
    groundHeightM,
    bounds: [
      center.longitude - longitudeDelta / 2,
      center.latitude - latitudeDelta / 2,
      center.longitude + longitudeDelta / 2,
      center.latitude + latitudeDelta / 2
    ],
    rasterWidthPx: Math.round(mapWidthMm / 25.4 * dpi),
    rasterHeightPx: Math.round(mapHeightMm / 25.4 * dpi)
  };
}
