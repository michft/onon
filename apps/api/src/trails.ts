import { randomUUID } from "node:crypto";
import { z } from "zod";
import type pg from "pg";
import { db, inTransaction } from "./db.js";
import { applyTrailEdit, type TrailEdit, type TrailSegments } from "./domain/trail-edits.js";
import { bearingDegrees, interpolateCoordinate, offsetCoordinate, type Coordinate } from "./domain/geo.js";

const segmentsSchema = z.array(z.array(z.number().int().nonnegative()).min(2)).min(1);
const stackSchema = z.array(segmentsSchema);

interface OverlayRow {
  id: string;
  recording_id: string;
  name: string;
  current_revision: number;
  undo_stack: unknown;
  redo_stack: unknown;
}

interface SampleRow {
  sample_index: number;
  latitude: number;
  longitude: number;
  observed_at: Date;
}

export interface TrailDocument {
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

export async function createTrail(recordingId: string): Promise<{ trail: TrailDocument; status: "created" | "existing" }> {
  const result = await inTransaction(async (client) => {
    const existing = await client.query<{ id: string }>("SELECT id FROM trail_overlays WHERE recording_id = $1", [recordingId]);
    if (existing.rows[0]) return { id: existing.rows[0].id, status: "existing" as const };
    const recording = await client.query<{ started_at: Date }>("SELECT started_at FROM raw_recordings WHERE id = $1", [recordingId]);
    const source = await client.query<{ sample_index: number }>(
      "SELECT sample_index FROM raw_samples WHERE recording_id = $1 ORDER BY sample_index",
      [recordingId]
    );
    if (!recording.rows[0]) throw new TrailStoreError(404, "recording_not_found");
    if (source.rows.length < 2) throw new TrailStoreError(422, "recording_has_too_few_samples");
    const id = randomUUID();
    const segments = [source.rows.map((row) => row.sample_index)];
    const name = `Trail ${recording.rows[0].started_at.toISOString().slice(0, 10)}`;
    await client.query(
      "INSERT INTO trail_overlays (id, recording_id, name) VALUES ($1, $2, $3)",
      [id, recordingId, name]
    );
    await client.query(
      "INSERT INTO trail_revisions (trail_id, revision, source_segments, operation) VALUES ($1, 0, $2::jsonb, $3::jsonb)",
      [id, JSON.stringify(segments), JSON.stringify({ type: "derive" })]
    );
    await client.query(
      `INSERT INTO editable_waypoints (id, trail_id, source_observation_id, latitude, longitude, label)
       SELECT gen_random_uuid(), $1, id, latitude, longitude, label
       FROM raw_waypoint_observations WHERE recording_id = $2`,
      [id, recordingId]
    );
    return { id, status: "created" as const };
  });
  return { trail: await loadTrail(result.id), status: result.status };
}

export async function loadTrail(id: string, queryable: Pick<pg.Pool, "query"> | pg.PoolClient = db): Promise<TrailDocument> {
  const overlayResult = await queryable.query<OverlayRow>(
    `SELECT id, recording_id, name, current_revision, undo_stack, redo_stack
     FROM trail_overlays WHERE id = $1`,
    [id]
  );
  const overlay = overlayResult.rows[0];
  if (!overlay) throw new TrailStoreError(404, "trail_overlay_not_found");
  const revision = await queryable.query<{ source_segments: unknown }>(
    "SELECT source_segments FROM trail_revisions WHERE trail_id = $1 AND revision = $2",
    [id, overlay.current_revision]
  );
  const segments = segmentsSchema.parse(revision.rows[0]?.source_segments);
  const allIndexes = [...new Set(segments.flat())];
  const sampleResult = await queryable.query<SampleRow>(
    `SELECT sample_index, latitude, longitude, observed_at
     FROM raw_samples WHERE recording_id = $1 AND sample_index = ANY($2::integer[])
     ORDER BY sample_index`,
    [overlay.recording_id, allIndexes]
  );
  const samples = new Map(sampleResult.rows.map((sample) => [sample.sample_index, sample]));
  const lines = segments.map((segment) => segment.map((index) => {
    const sample = samples.get(index);
    if (!sample) throw new TrailStoreError(500, "trail_source_sample_missing");
    return [sample.longitude, sample.latitude];
  }));
  const waypoints = await queryable.query<{
    id: string; latitude: number; longitude: number; label: string | null;
  }>("SELECT id, latitude, longitude, label FROM editable_waypoints WHERE trail_id = $1 ORDER BY created_at", [id]);
  const arrows = await queryable.query<{
    id: string; source_start_sample_index: number; source_end_sample_index: number;
    segment_fraction: number; side: "left" | "right";
  }>(
    `SELECT id, source_start_sample_index, source_end_sample_index, segment_fraction, side
     FROM direction_arrows WHERE trail_id = $1 ORDER BY created_at`,
    [id]
  );
  const lineSegments = lines.flatMap((line, lineIndex) => line.slice(0, -1).map((start, index) => ({
    coordinates: [start, line[index + 1]] as const,
    sourceIndexes: [segments[lineIndex]?.[index], segments[lineIndex]?.[index + 1]] as const
  })));
  const directionArrows = arrows.rows.flatMap((arrow) => {
    const segmentIndex = lineSegments.findIndex((pair) =>
      pair.sourceIndexes[0] === arrow.source_start_sample_index && pair.sourceIndexes[1] === arrow.source_end_sample_index
    );
    const pair = lineSegments[segmentIndex];
    const startCoordinate = pair?.coordinates[0];
    const endCoordinate = pair?.coordinates[1];
    if (!startCoordinate || !endCoordinate) return [];
    const start: Coordinate = { longitude: startCoordinate[0] ?? 0, latitude: startCoordinate[1] ?? 0 };
    const end: Coordinate = { longitude: endCoordinate[0] ?? 0, latitude: endCoordinate[1] ?? 0 };
    const bearing = bearingDegrees(start, end);
    const onLine = interpolateCoordinate(start, end, arrow.segment_fraction);
    const sideBearing = bearing + (arrow.side === "right" ? 90 : -90);
    const location = offsetCoordinate(onLine, sideBearing, 8);
    return [{
      id: arrow.id,
      segmentIndex,
      position: arrow.segment_fraction,
      side: arrow.side,
      ...location,
      bearing
    }];
  });
  return {
    id: overlay.id,
    recordingId: overlay.recording_id,
    name: overlay.name,
    version: overlay.current_revision,
    geometry: { type: "MultiLineString", coordinates: lines },
    sourceSampleIndexes: segments,
    waypoints: waypoints.rows,
    directionArrows,
    canUndo: stackSchema.parse(overlay.undo_stack).length > 0,
    canRedo: stackSchema.parse(overlay.redo_stack).length > 0
  };
}

export async function editTrail(id: string, expectedVersion: number, operation: TrailEdit): Promise<TrailDocument> {
  await inTransaction(async (client) => {
    const overlay = await lockOverlay(client, id);
    if (overlay.current_revision !== expectedVersion) throw new TrailStoreError(409, "stale_trail_version");
    const current = await currentSegments(client, overlay);
    let next: TrailSegments;
    try { next = applyTrailEdit(current, operation); }
    catch (error) { throw new TrailStoreError(422, error instanceof Error ? error.message : "invalid_trail_edit"); }
    const undo = stackSchema.parse(overlay.undo_stack);
    await appendRevision(client, overlay, next, operation, [...undo, current], []);
  });
  return loadTrail(id);
}

export async function undoTrail(id: string): Promise<TrailDocument> {
  await moveHistory(id, "undo");
  return loadTrail(id);
}

export async function redoTrail(id: string): Promise<TrailDocument> {
  await moveHistory(id, "redo");
  return loadTrail(id);
}

async function moveHistory(id: string, direction: "undo" | "redo"): Promise<void> {
  await inTransaction(async (client) => {
    const overlay = await lockOverlay(client, id);
    const current = await currentSegments(client, overlay);
    const undo = stackSchema.parse(overlay.undo_stack);
    const redo = stackSchema.parse(overlay.redo_stack);
    const source = direction === "undo" ? undo : redo;
    if (source.length === 0) throw new TrailStoreError(409, `nothing_to_${direction}`);
    const next = source[source.length - 1];
    if (!next) throw new TrailStoreError(409, `nothing_to_${direction}`);
    const nextUndo = direction === "undo" ? undo.slice(0, -1) : [...undo, current];
    const nextRedo = direction === "redo" ? redo.slice(0, -1) : [...redo, current];
    await appendRevision(client, overlay, next, { type: direction }, nextUndo, nextRedo);
  });
}

async function lockOverlay(client: pg.PoolClient, id: string): Promise<OverlayRow> {
  const result = await client.query<OverlayRow>(
    `SELECT id, recording_id, name, current_revision, undo_stack, redo_stack
     FROM trail_overlays WHERE id = $1 FOR UPDATE`,
    [id]
  );
  const overlay = result.rows[0];
  if (!overlay) throw new TrailStoreError(404, "trail_overlay_not_found");
  return overlay;
}

async function currentSegments(client: pg.PoolClient, overlay: OverlayRow): Promise<TrailSegments> {
  const result = await client.query<{ source_segments: unknown }>(
    "SELECT source_segments FROM trail_revisions WHERE trail_id = $1 AND revision = $2",
    [overlay.id, overlay.current_revision]
  );
  return segmentsSchema.parse(result.rows[0]?.source_segments);
}

async function appendRevision(
  client: pg.PoolClient,
  overlay: OverlayRow,
  segments: TrailSegments,
  operation: object,
  undo: TrailSegments[],
  redo: TrailSegments[]
): Promise<void> {
  const revision = overlay.current_revision + 1;
  await client.query(
    "INSERT INTO trail_revisions (trail_id, revision, source_segments, operation) VALUES ($1, $2, $3::jsonb, $4::jsonb)",
    [overlay.id, revision, JSON.stringify(segments), JSON.stringify(operation)]
  );
  await client.query(
    `UPDATE trail_overlays SET current_revision = $2, undo_stack = $3::jsonb,
     redo_stack = $4::jsonb, updated_at = now() WHERE id = $1`,
    [overlay.id, revision, JSON.stringify(undo), JSON.stringify(redo)]
  );
}

export class TrailStoreError extends Error {
  constructor(public readonly statusCode: number, message: string) { super(message); }
}
