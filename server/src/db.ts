import { config } from "./config.js";
import { SCHEMA } from "./schema.js";

/** Accès minimal à Postgres, identique en production (pg) et en local (PGlite). */
export interface Db {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
  exec(sql: string): Promise<void>;
  close(): Promise<void>;
}

export async function openDb(location?: string): Promise<Db> {
  if (config.databaseUrl && !location) {
    const pg = (await import("pg")).default;
    const pool = new pg.Pool({ connectionString: config.databaseUrl });
    return {
      query: async <T>(sql: string, params: unknown[] = []) => (await pool.query(sql, params)).rows as T[],
      exec: async (sql) => {
        await pool.query(sql);
      },
      close: () => pool.end(),
    };
  }
  const { PGlite } = await import("@electric-sql/pglite");
  const lite = new PGlite(location ?? config.pgliteDir);
  return {
    query: async <T>(sql: string, params: unknown[] = []) => (await lite.query<T>(sql, params)).rows,
    exec: async (sql) => {
      await lite.exec(sql);
    },
    close: () => lite.close(),
  };
}

export async function migrate(db: Db): Promise<void> {
  await db.exec(SCHEMA);
}
