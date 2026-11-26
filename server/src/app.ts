import formbody from "@fastify/formbody";
import Fastify from "fastify";
import type { Db } from "./db.js";
import { apiRoutes } from "./routes/api.js";
import { publicRoutes } from "./routes/public.js";

export async function buildApp(db: Db, options: { logger?: boolean } = {}) {
  // Derrière un proxy (hébergeur, CDN), TRUST_PROXY=1 fait lire la vraie IP cliente pour les limites de débit.
  const app = Fastify({ logger: options.logger ?? true, trustProxy: process.env.TRUST_PROXY === "1", bodyLimit: 1024 * 1024 });
  await app.register(formbody);
  await app.register(publicRoutes, { db });
  await app.register(apiRoutes, { db });
  return app;
}
