import type { Orientation, PrintScale } from "./types";

const EARTH_RADIUS_M = 6_378_137;

export function printBounds(
  center: [longitude: number, latitude: number],
  scale: PrintScale,
  orientation: Orientation
): [number, number, number, number] {
  const [pageWidth, pageHeight] = orientation === "portrait" ? [210, 297] : [297, 210];
  const groundWidthM = (pageWidth - 24) * scale / 1_000;
  const groundHeightM = (pageHeight - 42) * scale / 1_000;
  const latitudeDelta = groundHeightM / EARTH_RADIUS_M * 180 / Math.PI;
  const longitudeDelta = groundWidthM / (EARTH_RADIUS_M * Math.cos(center[1] * Math.PI / 180)) * 180 / Math.PI;
  return [center[0] - longitudeDelta / 2, center[1] - latitudeDelta / 2, center[0] + longitudeDelta / 2, center[1] + latitudeDelta / 2];
}
