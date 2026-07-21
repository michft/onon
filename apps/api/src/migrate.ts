import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { db } from "./db.js";

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDirectory = join(here, "../migrations");

async function migrate(): Promise<void> {
  await db.query("CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
  const applied = await db.query<{ version: number }>("SELECT version FROM schema_migrations");
  const appliedVersions = new Set(applied.rows.map((row) => row.version));
  const files = (await readdir(migrationsDirectory)).filter((file) => /^\d+_.*\.sql$/.test(file)).sort();
  for (const file of files) {
    const version = Number.parseInt(file.split("_")[0] ?? "", 10);
    if (!Number.isInteger(version) || appliedVersions.has(version)) continue;
    const sql = await readFile(join(migrationsDirectory, file), "utf8");
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query(sql);
      await client.query("INSERT INTO schema_migrations (version) VALUES ($1)", [version]);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}

await migrate();
await db.end();
