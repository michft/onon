import { randomInt, randomUUID } from "node:crypto";
import { fileURLToPath, pathToFileURL } from "node:url";
import cookie from "@fastify/cookie";
import cors from "@fastify/cors";
import staticFiles from "@fastify/static";
import Fastify, { type FastifyInstance, type FastifyReply } from "fastify";
import { z, ZodError } from "zod";
import { adminCookieValue, createDeviceToken, pairingCodeHash, requireAdmin, requireDevice, sha256 } from "./auth.js";
import { config } from "./config.js";
import { db, inTransaction } from "./db.js";
import { PdfExportError, renderPdf } from "./pdf-export.js";
import {
  arrowSchema,
  exchangePairingSchema,
  printRequestSchema,
  recordingUploadSchema,
  trailOperationSchema,
  waypointSchema
} from "./schemas.js";
import { createTrail, editTrail, loadTrail, redoTrail, TrailStoreError, undoTrail } from "./trails.js";

const uuidParameterSchema = z.object({
  recordingId: z.string().uuid().optional(),
  trailOverlayId: z.string().uuid().optional(),
  waypointId: z.string().uuid().optional(),
  arrowId: z.string().uuid().optional()
});

export async function buildServer(): Promise<FastifyInstance> {
  const app = Fastify({ logger: true, bodyLimit: 25 * 1024 * 1024 });
  await app.register(cookie);
  await app.register(cors, { origin: config.CORS_ORIGIN, credentials: true });

  app.get("/health", async (_request, reply) => {
    await db.query("SELECT 1");
    return reply.send({ status: "ok", database: "ok", mapVersion: config.MAP_VERSION });
  });

  app.post("/api/v1/admin/session", async (request, reply) => {
    const body = z.object({ bootstrapToken: z.string() }).parse(request.body);
    if (body.bootstrapToken !== config.ADMIN_TOKEN) return reply.code(401).send({ error: "invalid_bootstrap_token" });
    reply.setCookie("onon_admin", adminCookieValue(), {
      httpOnly: true,
      sameSite: "strict",
      secure: false,
      path: "/",
      maxAge: 12 * 60 * 60
    });
    return reply.code(204).send();
  });

  app.post("/api/v1/pairing-codes", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { code, expiresAt } = await createPairingCode();
    const qr = new URL("onon://pair");
    qr.searchParams.set("server", config.PUBLIC_BASE_URL);
    qr.searchParams.set("code", code);
    return reply.code(201).send({ code, expiresAt: expiresAt.toISOString(), qrPayload: qr.toString() });
  });

  app.post("/api/v1/pairings/exchange", async (request, reply) => {
    const body = exchangePairingSchema.parse(request.body);
    const deviceToken = createDeviceToken();
    const exchanged = await inTransaction(async (client) => {
      const pairing = await client.query<{ id: string }>(
        `SELECT id FROM pairing_codes
         WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > now()
         ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
        [pairingCodeHash(body.code)]
      );
      const row = pairing.rows[0];
      if (!row) return false;
      await client.query("UPDATE pairing_codes SET consumed_at = now() WHERE id = $1", [row.id]);
      await client.query(
        `INSERT INTO devices (id, name, token_hash) VALUES ($1, $2, $3)
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, token_hash = EXCLUDED.token_hash,
         paired_at = now(), revoked_at = NULL`,
        [body.deviceId, body.deviceName, sha256(deviceToken)]
      );
      return true;
    });
    if (!exchanged) return reply.code(410).send({ error: "pairing_code_invalid_or_expired" });
    return reply.send({ deviceToken, deviceId: body.deviceId });
  });

  app.post("/api/v1/recordings", async (request, reply) => {
    const device = await requireDevice(request, reply);
    if (!device) return;
    const body = recordingUploadSchema.parse(request.body);
    const idempotencyKey = request.headers["idempotency-key"];
    if (typeof idempotencyKey !== "string" || idempotencyKey !== body.id) {
      return reply.code(400).send({ error: "idempotency_key_must_equal_recording_id" });
    }
    const requestHash = sha256(JSON.stringify(body));
    const status = await inTransaction(async (client): Promise<"created" | "existing"> => {
      const receipt = await client.query<{ request_sha256: string; recording_id: string }>(
        "SELECT request_sha256, recording_id FROM sync_receipts WHERE device_id = $1 AND idempotency_key = $2 FOR UPDATE",
        [device.id, idempotencyKey]
      );
      const existingReceipt = receipt.rows[0];
      if (existingReceipt) {
        if (existingReceipt.request_sha256 !== requestHash || existingReceipt.recording_id !== body.id) {
          throw new ApiError(409, "idempotency_key_payload_mismatch");
        }
        return "existing";
      }
      const recording = await client.query<{ device_id: string; payload_sha256: string }>(
        "SELECT device_id, payload_sha256 FROM raw_recordings WHERE id = $1",
        [body.id]
      );
      const existingRecording = recording.rows[0];
      if (existingRecording) {
        if (existingRecording.device_id !== device.id || existingRecording.payload_sha256 !== requestHash) {
          throw new ApiError(409, "recording_id_payload_mismatch");
        }
        await client.query(
          "INSERT INTO sync_receipts (device_id, idempotency_key, request_sha256, recording_id) VALUES ($1, $2, $3, $4)",
          [device.id, idempotencyKey, requestHash, body.id]
        );
        return "existing";
      }
      await client.query(
        `INSERT INTO raw_recordings
         (id, device_id, client_recording_id, started_at, finished_at, payload_sha256)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [body.id, device.id, body.id, body.startedAt, body.finishedAt, requestHash]
      );
      for (const sample of body.samples) {
        await client.query(
          `INSERT INTO raw_samples
           (recording_id, sample_index, observed_at, latitude, longitude, horizontal_accuracy_m,
            altitude_m, vertical_accuracy_m, speed_mps, course_degrees)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
          [body.id, sample.sequence, sample.recordedAt, sample.latitude, sample.longitude,
            sample.horizontalAccuracy, sample.altitude ?? null, sample.verticalAccuracy ?? null,
            sample.speed ?? null, sample.course ?? null]
        );
      }
      for (const [index, waypoint] of body.waypoints.entries()) {
        await client.query(
          `INSERT INTO raw_waypoint_observations
           (id, recording_id, observation_index, observed_at, latitude, longitude, horizontal_accuracy_m)
           VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [waypoint.id, body.id, index, waypoint.recordedAt, waypoint.latitude, waypoint.longitude, waypoint.horizontalAccuracy]
        );
      }
      await client.query(
        "INSERT INTO sync_receipts (device_id, idempotency_key, request_sha256, recording_id) VALUES ($1, $2, $3, $4)",
        [device.id, idempotencyKey, requestHash, body.id]
      );
      return "created";
    });
    return reply.code(status === "created" ? 201 : 200).send({ recordingId: body.id, status });
  });

  app.get("/api/v1/recordings", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const result = await db.query<{
      id: string; device_id: string; device_name: string; started_at: Date; finished_at: Date;
      received_at: Date; sample_count: string; trail_overlay_id: string | null;
    }>(
      `SELECT r.id, r.device_id, d.name AS device_name, r.started_at, r.finished_at, r.received_at,
       count(s.sample_index)::text AS sample_count, t.id AS trail_overlay_id
       FROM raw_recordings r JOIN devices d ON d.id = r.device_id
       JOIN raw_samples s ON s.recording_id = r.id
       LEFT JOIN trail_overlays t ON t.recording_id = r.id
       GROUP BY r.id, d.name, t.id ORDER BY r.started_at DESC`
    );
    return reply.send(result.rows.map((row) => ({
      id: row.id,
      deviceId: row.device_id,
      deviceName: row.device_name,
      startedAt: row.started_at.toISOString(),
      finishedAt: row.finished_at.toISOString(),
      receivedAt: row.received_at.toISOString(),
      sampleCount: Number(row.sample_count),
      trailOverlayId: row.trail_overlay_id
    })));
  });

  app.get("/api/v1/recordings/:recordingId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { recordingId } = uuidParameterSchema.parse(request.params);
    if (!recordingId) return reply.code(400).send({ error: "recording_id_required" });
    const recording = await db.query<{
      id: string; device_id: string; started_at: Date; finished_at: Date; received_at: Date;
    }>("SELECT id, device_id, started_at, finished_at, received_at FROM raw_recordings WHERE id = $1", [recordingId]);
    const row = recording.rows[0];
    if (!row) return reply.code(404).send({ error: "recording_not_found" });
    const samples = await db.query<{
      sample_index: number; observed_at: Date; latitude: number; longitude: number;
      horizontal_accuracy_m: number; altitude_m: number | null; vertical_accuracy_m: number | null;
      speed_mps: number | null; course_degrees: number | null;
    }>("SELECT * FROM raw_samples WHERE recording_id = $1 ORDER BY sample_index", [recordingId]);
    const waypoints = await db.query<{
      id: string; observed_at: Date; latitude: number; longitude: number; horizontal_accuracy_m: number;
    }>("SELECT id, observed_at, latitude, longitude, horizontal_accuracy_m FROM raw_waypoint_observations WHERE recording_id = $1 ORDER BY observation_index", [recordingId]);
    return reply.send({
      id: row.id, deviceId: row.device_id, startedAt: row.started_at.toISOString(),
      finishedAt: row.finished_at.toISOString(), receivedAt: row.received_at.toISOString(),
      samples: samples.rows.map((sample) => ({
        sequence: sample.sample_index, recordedAt: sample.observed_at.toISOString(), latitude: sample.latitude,
        longitude: sample.longitude, horizontalAccuracy: sample.horizontal_accuracy_m,
        altitude: sample.altitude_m, verticalAccuracy: sample.vertical_accuracy_m,
        speed: sample.speed_mps, course: sample.course_degrees
      })),
      waypoints: waypoints.rows.map((waypoint) => ({
        id: waypoint.id, recordedAt: waypoint.observed_at.toISOString(), latitude: waypoint.latitude,
        longitude: waypoint.longitude, horizontalAccuracy: waypoint.horizontal_accuracy_m
      }))
    });
  });

  app.post("/api/v1/recordings/:recordingId/trail-overlays", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { recordingId } = uuidParameterSchema.parse(request.params);
    if (!recordingId) return reply.code(400).send({ error: "recording_id_required" });
    const result = await createTrail(recordingId);
    return reply.code(result.status === "created" ? 201 : 200).send({ ...result.trail, status: result.status });
  });

  app.get("/api/v1/trail-overlays/:trailOverlayId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId) return reply.code(400).send({ error: "trail_overlay_id_required" });
    return reply.send(await loadTrail(trailOverlayId));
  });

  app.post("/api/v1/trail-overlays/:trailOverlayId/operations", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId) return reply.code(400).send({ error: "trail_overlay_id_required" });
    const body = trailOperationSchema.parse(request.body);
    return reply.send(await editTrail(trailOverlayId, body.expectedVersion, body.operation));
  });

  for (const action of ["undo", "redo"] as const) {
    app.post(`/api/v1/trail-overlays/:trailOverlayId/${action}`, async (request, reply) => {
      if (!requireAdmin(request, reply)) return;
      const { trailOverlayId } = uuidParameterSchema.parse(request.params);
      if (!trailOverlayId) return reply.code(400).send({ error: "trail_overlay_id_required" });
      return reply.send(action === "undo" ? await undoTrail(trailOverlayId) : await redoTrail(trailOverlayId));
    });
  }

  app.post("/api/v1/trail-overlays/:trailOverlayId/waypoints", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId) return reply.code(400).send({ error: "trail_overlay_id_required" });
    const body = waypointSchema.parse(request.body);
    const id = randomUUID();
    await db.query(
      "INSERT INTO editable_waypoints (id, trail_id, latitude, longitude, label) VALUES ($1, $2, $3, $4, $5)",
      [id, trailOverlayId, body.latitude, body.longitude, body.label]
    );
    return reply.code(201).send(await loadTrail(trailOverlayId));
  });

  app.patch("/api/v1/trail-overlays/:trailOverlayId/waypoints/:waypointId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId, waypointId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId || !waypointId) return reply.code(400).send({ error: "trail_and_waypoint_ids_required" });
    const body = waypointSchema.partial().refine((value) => Object.keys(value).length > 0).parse(request.body);
    const result = await db.query(
      `UPDATE editable_waypoints SET latitude = COALESCE($3, latitude), longitude = COALESCE($4, longitude),
       label = CASE WHEN $5::boolean THEN $6 ELSE label END, updated_at = now()
       WHERE id = $1 AND trail_id = $2`,
      [waypointId, trailOverlayId, body.latitude ?? null, body.longitude ?? null,
        Object.hasOwn(body, "label"), body.label ?? null]
    );
    if (result.rowCount === 0) return reply.code(404).send({ error: "waypoint_not_found" });
    return reply.send(await loadTrail(trailOverlayId));
  });

  app.delete("/api/v1/trail-overlays/:trailOverlayId/waypoints/:waypointId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId, waypointId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId || !waypointId) return reply.code(400).send({ error: "trail_and_waypoint_ids_required" });
    await db.query("DELETE FROM editable_waypoints WHERE id = $1 AND trail_id = $2", [waypointId, trailOverlayId]);
    return reply.send(await loadTrail(trailOverlayId));
  });

  app.post("/api/v1/trail-overlays/:trailOverlayId/direction-arrows", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId) return reply.code(400).send({ error: "trail_overlay_id_required" });
    const body = arrowSchema.parse(request.body);
    const trail = await loadTrail(trailOverlayId);
    const sourcePairs = trail.sourceSampleIndexes.flatMap((line) => line.slice(0, -1).map((start, index) => [start, line[index + 1]] as const));
    const sourcePair = sourcePairs[body.segmentIndex];
    if (!sourcePair || sourcePair[0] === undefined || sourcePair[1] === undefined) return reply.code(422).send({ error: "arrow_segment_outside_trail" });
    await db.query(
      `INSERT INTO direction_arrows
       (id, trail_id, source_start_sample_index, source_end_sample_index, segment_fraction, side)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [randomUUID(), trailOverlayId, sourcePair[0], sourcePair[1], body.position, body.side]
    );
    return reply.code(201).send(await loadTrail(trailOverlayId));
  });

  app.patch("/api/v1/trail-overlays/:trailOverlayId/direction-arrows/:arrowId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId, arrowId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId || !arrowId) return reply.code(400).send({ error: "trail_and_arrow_ids_required" });
    const body = arrowSchema.partial().refine((value) => Object.keys(value).length > 0).parse(request.body);
    const trail = await loadTrail(trailOverlayId);
    const sourcePairs = trail.sourceSampleIndexes.flatMap((line) => line.slice(0, -1).map((start, index) => [start, line[index + 1]] as const));
    const sourcePair = body.segmentIndex === undefined ? null : sourcePairs[body.segmentIndex];
    if (body.segmentIndex !== undefined && (!sourcePair || sourcePair[0] === undefined || sourcePair[1] === undefined)) {
      return reply.code(422).send({ error: "arrow_segment_outside_trail" });
    }
    const result = await db.query(
      `UPDATE direction_arrows SET source_start_sample_index = COALESCE($3, source_start_sample_index),
       source_end_sample_index = COALESCE($4, source_end_sample_index),
       segment_fraction = COALESCE($5, segment_fraction), side = COALESCE($6, side), updated_at = now()
       WHERE id = $1 AND trail_id = $2`,
      [arrowId, trailOverlayId, sourcePair?.[0] ?? null, sourcePair?.[1] ?? null, body.position ?? null, body.side ?? null]
    );
    if (result.rowCount === 0) return reply.code(404).send({ error: "direction_arrow_not_found" });
    return reply.send(await loadTrail(trailOverlayId));
  });

  app.delete("/api/v1/trail-overlays/:trailOverlayId/direction-arrows/:arrowId", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const { trailOverlayId, arrowId } = uuidParameterSchema.parse(request.params);
    if (!trailOverlayId || !arrowId) return reply.code(400).send({ error: "trail_and_arrow_ids_required" });
    await db.query("DELETE FROM direction_arrows WHERE id = $1 AND trail_id = $2", [arrowId, trailOverlayId]);
    return reply.send(await loadTrail(trailOverlayId));
  });

  app.get("/api/v1/maps/manifest", async (_request, reply) => reply.send({
    version: config.MAP_VERSION,
    bounds: [151.00, -34.04, 151.33, -33.70],
    overviewMaxZoom: 11,
    detailMaxZoom: 14,
    styles: {
      screen: new URL("/styles/screen/style.json", config.PUBLIC_TILESERVER_URL).toString(),
      blueLightPrint: new URL("/styles/blue-light-print/style.json", config.PUBLIC_TILESERVER_URL).toString(),
      greyscalePrint: new URL("/styles/greyscale-print/style.json", config.PUBLIC_TILESERVER_URL).toString()
    }
  }));

  app.post("/api/v1/exports/pdf", async (request, reply) => {
    if (!requireAdmin(request, reply)) return;
    const body = printRequestSchema.parse(request.body);
    const pdf = await renderPdf(body);
    return reply.header("Content-Type", "application/pdf")
      .header("Content-Disposition", `attachment; filename=onon-${body.profile}.pdf`)
      .send(pdf);
  });

  await app.register(staticFiles, {
    root: fileURLToPath(new URL("../public", import.meta.url)),
    wildcard: false
  });
  app.get("/*", async (request, reply) => {
    const pathname = new URL(request.url, "http://onon.local").pathname;
    if (["/api", "/health", "/styles"].some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`))) {
      return reply.code(404).send({ error: "not_found" });
    }
    if (pathname.includes(".")) return reply.sendFile(pathname.slice(1));
    return reply.sendFile("index.html");
  });

  app.setErrorHandler((error, _request, reply) => handleError(error, reply));
  return app;
}

async function createPairingCode(): Promise<{ code: string; expiresAt: Date }> {
  return inTransaction(async (client) => {
    await client.query("SELECT pg_advisory_xact_lock(723611)");
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
      const hash = pairingCodeHash(code);
      const collision = await client.query(
        "SELECT 1 FROM pairing_codes WHERE code_hash = $1 AND consumed_at IS NULL AND expires_at > now() LIMIT 1",
        [hash]
      );
      if (collision.rowCount !== 0) continue;
      const expiresAt = new Date(Date.now() + 10 * 60 * 1_000);
      await client.query(
        "INSERT INTO pairing_codes (id, code_hash, expires_at) VALUES ($1, $2, $3)",
        [randomUUID(), hash, expiresAt]
      );
      return { code, expiresAt };
    }
    throw new ApiError(503, "pairing_code_generation_failed");
  });
}

function handleError(error: unknown, reply: FastifyReply): void {
  if (error instanceof ZodError) {
    void reply.code(400).send({ error: "invalid_request", details: error.flatten() });
    return;
  }
  if (error instanceof ApiError || error instanceof TrailStoreError || error instanceof PdfExportError) {
    void reply.code(error.statusCode).send({ error: error.message });
    return;
  }
  const postgresCode = error && typeof error === "object" && "code" in error && typeof error.code === "string" ? error.code : null;
  if (postgresCode === "23503") {
    void reply.code(404).send({ error: "related_record_not_found" });
    return;
  }
  if (postgresCode === "23505") {
    void reply.code(409).send({ error: "record_already_exists" });
    return;
  }
  void reply.code(500).send({ error: "internal_server_error" });
}

class ApiError extends Error {
  constructor(public readonly statusCode: number, message: string) { super(message); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const app = await buildServer();
  await app.listen({ host: config.HOST, port: config.PORT });
}
