import type { TrailOverlay } from "./types";

export interface NearestTrailLocation { vertexIndex: number; segmentIndex: number; position: number }

export function nearestTrailLocation(trail: TrailOverlay, longitude: number, latitude: number): NearestTrailLocation {
  let best: NearestTrailLocation & { distance: number } = { vertexIndex: 0, segmentIndex: 0, position: 0, distance: Infinity };
  let vertexOffset = 0;
  let segmentOffset = 0;
  for (const line of trail.geometry.coordinates) {
    for (let index = 0; index < line.length - 1; index += 1) {
      const start = line[index];
      const end = line[index + 1];
      if (!start || !end) continue;
      const latitudeScale = Math.cos(latitude * Math.PI / 180);
      const ax = (start[0] ?? 0) * latitudeScale;
      const ay = start[1] ?? 0;
      const bx = (end[0] ?? 0) * latitudeScale;
      const by = end[1] ?? 0;
      const px = longitude * latitudeScale;
      const dx = bx - ax;
      const dy = by - ay;
      const denominator = dx * dx + dy * dy;
      const position = denominator === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (latitude - ay) * dy) / denominator));
      const distance = (px - (ax + position * dx)) ** 2 + (latitude - (ay + position * dy)) ** 2;
      if (distance < best.distance) {
        best = {
          segmentIndex: segmentOffset + index,
          vertexIndex: vertexOffset + index + (position >= 0.5 ? 1 : 0),
          position,
          distance
        };
      }
    }
    vertexOffset += line.length;
    segmentOffset += Math.max(0, line.length - 1);
  }
  return best;
}
