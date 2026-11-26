import { fileURLToPath } from "node:url";
import { migrate, openDb, type Db } from "./db.js";
import { syncAll } from "./sync.js";

interface Log {
  info(message: string): void;
  error(error: unknown): void;
}

/** Heure de la prochaine synchronisation : 4 h du matin, heure du serveur. */
function nextRun(now = new Date()): Date {
  const next = new Date(now);
  next.setHours(4, 0, 0, 0);
  if (next <= now) next.setDate(next.getDate() + 1);
  return next;
}

export function scheduleNightlySync(db: Db, log: Log): void {
  const plan = () => {
    const at = nextRun();
    setTimeout(async () => {
      try {
        const result = await syncAll(db);
        log.info(`Synchronisation nocturne : ${result.total} compte(s), ${result.failed} échec(s).`);
      } catch (error) {
        log.error(error);
      }
      plan();
    }, at.getTime() - Date.now()).unref();
  };
  plan();
}

// `npm run sync` : une synchronisation immédiate, puis arrêt. `npm run worker` : synchronisation chaque nuit.
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const db = await openDb();
  await migrate(db);
  const log: Log = { info: (m) => console.log(m), error: (e) => console.error(e) };
  if (process.argv.includes("--once")) {
    const result = await syncAll(db);
    log.info(`${result.total} compte(s) synchronisé(s), ${result.failed} échec(s).`);
    await db.close();
  } else {
    log.info("Worker Pulse démarré : synchronisation chaque nuit à 4 h.");
    scheduleNightlySync(db, log);
    setInterval(() => {}, 1 << 30);
  }
}
