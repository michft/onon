import { z } from "zod";

const uuid = z.string().uuid();
const latitude = z.number().min(-90).max(90);
const longitude = z.number().min(-180).max(180);

export const exchangePairingSchema = z.object({
  code: z.string().regex(/^\d{6}$/),
  deviceId: uuid,
  deviceName: z.string().trim().min(1).max(120)
});

const sampleSchema = z.object({
  sequence: z.number().int().min(0),
  recordedAt: z.string().datetime({ offset: true }),
  latitude,
  longitude,
  horizontalAccuracy: z.number().nonnegative(),
  altitude: z.number().optional(),
  verticalAccuracy: z.number().nonnegative().optional(),
  speed: z.number().optional(),
  course: z.number().min(0).max(360).optional()
});

const rawWaypointSchema = z.object({
  id: uuid,
  recordedAt: z.string().datetime({ offset: true }),
  latitude,
  longitude,
  horizontalAccuracy: z.number().nonnegative()
});

export const recordingUploadSchema = z.object({
  id: uuid,
  startedAt: z.string().datetime({ offset: true }),
  finishedAt: z.string().datetime({ offset: true }),
  samples: z.array(sampleSchema).min(1),
  waypoints: z.array(rawWaypointSchema)
}).superRefine((recording, context) => {
  if (Date.parse(recording.finishedAt) < Date.parse(recording.startedAt)) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ["finishedAt"], message: "must not precede startedAt" });
  }
  recording.samples.forEach((sample, index) => {
    if (sample.sequence !== index) {
      context.addIssue({ code: z.ZodIssueCode.custom, path: ["samples", index, "sequence"], message: `must equal ${index}` });
    }
  });
});

export const trailEditSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("trim_start"), throughIndex: z.number().int().nonnegative() }),
  z.object({ type: z.literal("trim_end"), fromIndex: z.number().int().nonnegative() }),
  z.object({
    type: z.literal("remove_range"),
    fromIndex: z.number().int().nonnegative(),
    toIndex: z.number().int().nonnegative()
  })
]);
export const trailOperationSchema = z.object({ expectedVersion: z.number().int().nonnegative(), operation: trailEditSchema });

export const waypointSchema = z.object({ latitude, longitude, label: z.string().max(200).nullable().default(null) });
export const arrowSchema = z.object({
  segmentIndex: z.number().int().nonnegative(),
  position: z.number().min(0).max(1).default(0.5),
  side: z.enum(["left", "right"]).default("right")
});

export const printRequestSchema = z.object({
  trailOverlayId: uuid,
  center: z.tuple([longitude, latitude]),
  scale: z.union([z.literal(10_000), z.literal(15_000), z.literal(25_000)]),
  orientation: z.enum(["portrait", "landscape"]),
  profile: z.enum(["screen", "blueLightPrint", "greyscalePrint"])
});
