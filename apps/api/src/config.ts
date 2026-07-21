import { z } from "zod";

const environmentSchema = z.object({
  DATABASE_URL: z.string().min(1),
  ADMIN_TOKEN: z.string().min(20),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().positive().default(3000),
  PUBLIC_BASE_URL: z.string().url().default("http://localhost:3000"),
  TILESERVER_URL: z.string().url().default("http://onon-tiles:8080"),
  PUBLIC_TILESERVER_URL: z.string().url().default("http://localhost:8081"),
  MAP_VERSION: z.string().default("not-built"),
  CORS_ORIGIN: z.string().default("http://localhost:5173")
});

export const config = environmentSchema.parse(process.env);
