import type { MapManifest, Orientation, PrintScale, ProfileName, RecordingSummary, TrailOperation, TrailOverlay } from "./types";

const API_BASE = import.meta.env.VITE_API_URL ?? window.location.origin;

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(new URL(path, API_BASE), {
    ...init,
    credentials: "include",
    headers: { "Content-Type": "application/json", ...init?.headers }
  });
  if (!response.ok) {
    const payload: unknown = await response.json().catch(() => null);
    const message = payload && typeof payload === "object" && "error" in payload && typeof payload.error === "string"
      ? payload.error : `Request failed (${response.status})`;
    throw new ApiError(response.status, message);
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

export class ApiError extends Error {
  constructor(public readonly status: number, message: string) { super(message); }
}

export const api = {
  manifest: () => request<MapManifest>("/api/v1/maps/manifest"),
  adminSession: (bootstrapToken: string) => request<void>("/api/v1/admin/session", {
    method: "POST", body: JSON.stringify({ bootstrapToken })
  }),
  createPairingCode: () => request<{ code: string; expiresAt: string; qrPayload: string }>("/api/v1/pairing-codes", { method: "POST" }),
  recordings: () => request<RecordingSummary[]>("/api/v1/recordings"),
  createTrail: (recordingId: string) => request<TrailOverlay>(`/api/v1/recordings/${recordingId}/trail-overlays`, { method: "POST" }),
  trail: (trailId: string) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}`),
  operation: (trail: TrailOverlay, operation: TrailOperation) => request<TrailOverlay>(`/api/v1/trail-overlays/${trail.id}/operations`, {
    method: "POST", body: JSON.stringify({ expectedVersion: trail.version, operation })
  }),
  history: (trailId: string, action: "undo" | "redo") => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/${action}`, { method: "POST" }),
  addWaypoint: (trailId: string, latitude: number, longitude: number) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/waypoints`, {
    method: "POST", body: JSON.stringify({ latitude, longitude, label: null })
  }),
  moveWaypoint: (trailId: string, waypointId: string, latitude: number, longitude: number) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/waypoints/${waypointId}`, {
    method: "PATCH", body: JSON.stringify({ latitude, longitude })
  }),
  deleteWaypoint: (trailId: string, waypointId: string) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/waypoints/${waypointId}`, { method: "DELETE" }),
  addArrow: (trailId: string, segmentIndex: number, position: number) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/direction-arrows`, {
    method: "POST", body: JSON.stringify({ segmentIndex, position, side: "right" })
  }),
  flipArrow: (trailId: string, arrowId: string, side: "left" | "right") => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/direction-arrows/${arrowId}`, {
    method: "PATCH", body: JSON.stringify({ side })
  }),
  moveArrow: (trailId: string, arrowId: string, segmentIndex: number, position: number) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/direction-arrows/${arrowId}`, {
    method: "PATCH", body: JSON.stringify({ segmentIndex, position })
  }),
  deleteArrow: (trailId: string, arrowId: string) => request<TrailOverlay>(`/api/v1/trail-overlays/${trailId}/direction-arrows/${arrowId}`, { method: "DELETE" }),
  exportPdf: async (input: {
    trailOverlayId: string; profile: ProfileName; orientation: Orientation;
    scale: PrintScale; center: [number, number];
  }): Promise<Blob> => {
    const response = await fetch(new URL("/api/v1/exports/pdf", API_BASE), {
      method: "POST", credentials: "include", headers: { "Content-Type": "application/json" }, body: JSON.stringify(input)
    });
    if (!response.ok) throw new ApiError(response.status, `PDF export failed (${response.status})`);
    return response.blob();
  }
};
