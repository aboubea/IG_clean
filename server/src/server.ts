import { buildApp } from "./app.js";
import { config } from "./config.js";
import { migrate, openDb } from "./db.js";
import { scheduleNightlySync } from "./worker.js";

const db = await openDb();
await migrate(db);
const app = await buildApp(db);
// En instance unique, le serveur relève aussi les chiffres chaque nuit ; en production, préférer `npm run worker` à part.
if (process.env.PULSE_INLINE_WORKER !== "0") scheduleNightlySync(db, app.log);
await app.listen({ port: config.port, host: config.host });
app.log.info(`Pulse : ${config.publicBaseUrl} · IA ${config.ai.enabled ? config.ai.model : "démo"} · connecteurs ${config.demoConnectors ? "démo" : "officiels"}`);
