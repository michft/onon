import pg from "pg";
import { config } from "./config.js";

const { Pool } = pg;

export const db = new Pool({ connectionString: config.DATABASE_URL, max: 10 });

export async function inTransaction<T>(run: (client: pg.PoolClient) => Promise<T>): Promise<T> {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const result = await run(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
