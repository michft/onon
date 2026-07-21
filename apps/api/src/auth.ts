import { createHash, createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "./config.js";
import { db } from "./db.js";

export interface DeviceIdentity { id: string; name: string }

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function pairingCodeHash(code: string): string {
  return sha256(`${config.ADMIN_TOKEN}:${code}`);
}

export function createDeviceToken(): string {
  return randomBytes(32).toString("base64url");
}

export function requireAdmin(request: FastifyRequest, reply: FastifyReply): boolean {
  const supplied = request.cookies.onon_admin;
  const expected = adminCookieValue();
  if (typeof supplied !== "string" || !safeEqual(supplied, expected)) {
    void reply.code(401).send({ error: "admin_token_required" });
    return false;
  }
  return true;
}

export function adminCookieValue(): string {
  return createHmac("sha256", config.ADMIN_TOKEN).update("onon-local-admin-v1").digest("base64url");
}

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  return leftBuffer.length === rightBuffer.length && timingSafeEqual(leftBuffer, rightBuffer);
}

export async function requireDevice(request: FastifyRequest, reply: FastifyReply): Promise<DeviceIdentity | null> {
  const authorization = request.headers.authorization;
  if (!authorization?.startsWith("Bearer ")) {
    await reply.code(401).send({ error: "device_token_required" });
    return null;
  }
  const tokenHash = sha256(authorization.slice("Bearer ".length));
  const result = await db.query<DeviceIdentity>(
    `UPDATE devices SET last_seen_at = now()
     WHERE token_hash = $1 AND revoked_at IS NULL
     RETURNING id, name`,
    [tokenHash]
  );
  const device = result.rows[0];
  if (!device) {
    await reply.code(401).send({ error: "invalid_device_token" });
    return null;
  }
  return device;
}
