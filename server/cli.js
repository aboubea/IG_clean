// Scan ponctuel en ligne de commande (pour cron / Planificateur de tâches) : npm run snapshot
import { takeSnapshot } from './snapshot.js';

try {
  const r = await takeSnapshot('auto');
  console.log(`Scan ${r.status} — ${r.events} changement(s) détecté(s).`);
} catch (e) {
  console.error(`Échec du scan : ${e.message}`);
  process.exitCode = 1;
}
