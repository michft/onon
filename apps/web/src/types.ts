export type ProfileName = "screen" | "blueLightPrint" | "greyscalePrint";
export type Orientation = "portrait" | "landscape";
export type PrintScale = 10_000 | 15_000 | 25_000;

export interface MapManifest {
  version: string;
  bounds: [number, number, number, number];
  overviewMaxZoom: number;
  detailMaxZoom: number;
  styles: Record<ProfileName, string>;
}

export interface RecordingSummary {
  id: string;
  deviceId: string;
  deviceName: string;
  startedAt: string;
  finishedAt: string;
  receivedAt: string;
  sampleCount: number;
  trailOverlayId: string | null;
}

export interface TrailOverlay {
  id: string;
  recordingId: string;
  name: string;
  version: number;
  geometry: { type: "MultiLineString"; coordinates: number[][][] };
  sourceSampleIndexes: number[][];
  waypoints: Array<{ id: string; latitude: number; longitude: number; label: string | null }>;
  directionArrows: Array<{
    id: string;
    segmentIndex: number;
    position: number;
    side: "left" | "right";
    latitude: number;
    longitude: number;
    bearing: number;
  }>;
  canUndo: boolean;
  canRedo: boolean;
}

export type TrailOperation =
  | { type: "trim_start"; throughIndex: number }
  | { type: "trim_end"; fromIndex: number }
  | { type: "remove_range"; fromIndex: number; toIndex: number };

export type EditMode = "inspect" | "waypoint" | "move-waypoint" | "arrow" | "move-arrow" | "trim-start" | "trim-end" | "remove-range";
