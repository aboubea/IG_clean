import { db, getSetting, setSetting, getSettings } from './db.js';
import { runExclusive } from './lock.js';
import { openSession } from './ig/index.js';

const HOUR = 3_600_000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const runner = () => ({ enabled: false, cooldownUntil: 0, lastError: null, ...getSetting('runner', {}) });
const patchRunner = (patch) => setSetting('runner', { ...runner(), ...patch });

const doneSince = (ms) =>
  db.prepare("SELECT COUNT(*) AS n FROM unfollow_log WHERE status = 'done' AND at > ?").get(Date.now() - ms).n;
const queueLength = () => db.prepare('SELECT COUNT(*) AS n FROM unfollow_queue').get().n;

export function runnerState() {
  const s = getSettings();
  const doneHour = doneSince(HOUR);
  const doneDay = doneSince(24 * HOUR);
  return {
    ...runner(),
    queue: queueLength(),
    doneHour,
    doneDay,
    available: Math.max(0, Math.min(s.hourlyCap - doneHour, s.dailyCap - doneDay)),
  };
}

export function setRunnerEnabled(enabled) {
  patchRunner(enabled ? { enabled: true, lastError: null, cooldownUntil: 0 } : { enabled: false });
}

export function enqueue(userIds) {
  const stmt = db.prepare(`
    INSERT OR IGNORE INTO unfollow_queue(user_id, added_at)
    SELECT u.user_id, ? FROM users u
    WHERE u.user_id = ? AND u.whitelisted = 0
      AND EXISTS(SELECT 1 FROM relations r WHERE r.user_id = u.user_id AND r.kind = 'following')
      AND NOT EXISTS(SELECT 1 FROM relations r WHERE r.user_id = u.user_id AND r.kind = 'follower')`);
  let added = 0;
  for (const id of userIds) added += stmt.run(Date.now(), String(id)).changes;
  return added;
}

export function shouldStartBatch() {
  const st = runnerState();
  if (!st.enabled || !st.queue || Date.now() < st.cooldownUntil) return false;
  // Évite de rouvrir le navigateur pour un seul unfollow dès qu'un créneau se libère.
  return st.available >= Math.min(st.queue, Math.ceil(getSettings().hourlyCap / 2));
}

export function runBatch() {
  return runExclusive('unfollow', async (progress) => {
    const log = db.prepare('INSERT INTO unfollow_log(at, user_id, status, detail) VALUES(?, ?, ?, ?)');
    const dequeue = db.prepare('DELETE FROM unfollow_queue WHERE user_id = ?');
    const dropFollowing = db.prepare("DELETE FROM relations WHERE user_id = ? AND kind = 'following'");
    let session;
    let failures = 0;
    try {
      session = await openSession();
      while (runner().enabled && runnerState().available > 0) {
        const next = db
          .prepare('SELECT q.user_id, u.username FROM unfollow_queue q JOIN users u USING(user_id) ORDER BY q.added_at LIMIT 1')
          .get();
        if (!next) break;
        progress(`Unfollow de @${next.username}…`);
        try {
          // Revérification en direct : on n'unfollow jamais quelqu'un qui s'est (ré)abonné entre-temps.
          const rel = await session.relationship(next.user_id);
          if (rel.followedBy) {
            log.run(Date.now(), next.user_id, 'skipped', 'te suit désormais');
            db.prepare("INSERT OR IGNORE INTO relations(user_id, kind, since) VALUES(?, 'follower', ?)").run(next.user_id, Date.now());
          } else if (!rel.following) {
            log.run(Date.now(), next.user_id, 'skipped', 'déjà plus suivi');
            dropFollowing.run(next.user_id);
          } else {
            await session.unfollow(next.user_id);
            const at = Date.now();
            log.run(at, next.user_id, 'done', null);
            dropFollowing.run(next.user_id);
            db.prepare("INSERT INTO events(at, type, user_id) VALUES(?, 'following_removed', ?)").run(at, next.user_id);
          }
          failures = 0;
          dequeue.run(next.user_id);
        } catch (e) {
          if (e.code === 'RATE_LIMITED' || e.code === 'CHECKPOINT') {
            patchRunner({ enabled: false, cooldownUntil: Date.now() + 24 * HOUR, lastError: e.message });
            throw e;
          }
          if (e.code === 'LOGGED_OUT') {
            setSetting('loggedOut', true);
            patchRunner({ enabled: false, lastError: e.message });
            throw e;
          }
          log.run(Date.now(), next.user_id, 'error', e.message);
          dequeue.run(next.user_id);
          if (++failures >= 3) {
            patchRunner({ enabled: false, lastError: `3 échecs consécutifs, arrêt par sécurité : ${e.message}` });
            throw e;
          }
        }
        const s = getSettings();
        const waitUntil = Date.now() + (s.delayMinSec + Math.random() * Math.max(0, s.delayMaxSec - s.delayMinSec)) * 1000;
        while (Date.now() < waitUntil && runner().enabled && queueLength()) {
          progress(`Pause de ${Math.ceil((waitUntil - Date.now()) / 1000)} s avant le prochain unfollow…`);
          await sleep(1000);
        }
      }
    } finally {
      await session?.close();
    }
  });
}
