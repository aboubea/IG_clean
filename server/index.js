import express from 'express';
import path from 'node:path';
import fs from 'node:fs';
import { config, DEFAULT_SETTINGS } from './config.js';
import { db, getSetting, setSetting, getSettings } from './db.js';
import { busyState, lastTaskError, runExclusive } from './lock.js';
import { login } from './ig/index.js';
import { takeSnapshot, snapshotDueToday } from './snapshot.js';
import { runnerState, setRunnerEnabled, enqueue, shouldStartBatch, runBatch } from './unfollow.js';

const app = express();
app.use(express.json({ limit: '2mb' }));

const NOT_FOLLOWER = "NOT EXISTS(SELECT 1 FROM relations x WHERE x.user_id = r.user_id AND x.kind = 'follower')";
const NOT_FOLLOWING = "NOT EXISTS(SELECT 1 FROM relations x WHERE x.user_id = r.user_id AND x.kind = 'following')";
const LISTS = {
  followers: "r.kind = 'follower'",
  following: "r.kind = 'following'",
  non_followers: `r.kind = 'following' AND ${NOT_FOLLOWER}`, // je les suis, ils ne me suivent pas
  fans: `r.kind = 'follower' AND ${NOT_FOLLOWING}`, // ils me suivent, je ne les suis pas
  mutuals: "r.kind = 'following' AND EXISTS(SELECT 1 FROM relations x WHERE x.user_id = r.user_id AND x.kind = 'follower')",
};
const count = (where) => db.prepare(`SELECT COUNT(*) AS n FROM relations r WHERE ${where}`).get().n;
const background = (promise) => promise.catch((e) => console.error(`[tâche] ${e.message}`));

app.get('/api/status', (_req, res) => {
  res.json({
    mock: config.mock,
    account: getSetting('loggedOut', false) ? null : getSetting('account'),
    busy: busyState(),
    lastError: lastTaskError(),
    lastSnapshot: db.prepare('SELECT * FROM snapshots ORDER BY id DESC LIMIT 1').get() ?? null,
    lastGoodSnapshot: db.prepare("SELECT * FROM snapshots WHERE status = 'ok' ORDER BY id DESC LIMIT 1").get() ?? null,
    counts: Object.fromEntries(Object.entries(LISTS).map(([k, w]) => [k, count(w)])),
    runner: runnerState(),
    settings: getSettings(),
  });
});

app.post('/api/login', (_req, res) => {
  if (busyState()) return res.status(409).json({ error: 'Une tâche est déjà en cours.' });
  background(
    runExclusive('login', async (progress) => {
      const me = await login(progress);
      setSetting('account', { id: me.id, username: me.username });
      setSetting('loggedOut', false);
    }),
  );
  res.status(202).json({ ok: true });
});

app.post('/api/snapshot', (_req, res) => {
  if (busyState()) return res.status(409).json({ error: 'Une tâche est déjà en cours.' });
  background(takeSnapshot('manual'));
  res.status(202).json({ ok: true });
});

app.get('/api/users', (req, res) => {
  const where = LISTS[req.query.list];
  if (!where) return res.status(400).json({ error: 'Liste inconnue.' });
  res.json(
    db
      .prepare(
        `SELECT u.user_id AS id, u.username, u.full_name AS fullName, u.is_private AS isPrivate,
                u.is_verified AS isVerified, u.whitelisted, r.since,
                EXISTS(SELECT 1 FROM unfollow_queue q WHERE q.user_id = u.user_id) AS queued
         FROM relations r JOIN users u USING(user_id) WHERE ${where} ORDER BY u.username`,
      )
      .all(),
  );
});

app.get('/api/events', (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 300, 2000);
  res.json(
    db
      .prepare(
        `SELECT e.id, e.at, e.type, u.user_id AS userId, u.username, u.full_name AS fullName
         FROM events e JOIN users u USING(user_id) ORDER BY e.at DESC, e.id DESC LIMIT ?`,
      )
      .all(limit),
  );
});

app.get('/api/snapshots', (_req, res) => {
  res.json(db.prepare('SELECT * FROM snapshots ORDER BY id DESC LIMIT 60').all());
});

app.get('/api/unfollow-log', (_req, res) => {
  res.json(
    db
      .prepare(
        `SELECT l.id, l.at, l.status, l.detail, u.username FROM unfollow_log l JOIN users u USING(user_id)
         ORDER BY l.id DESC LIMIT 100`,
      )
      .all(),
  );
});

app.post('/api/whitelist', (req, res) => {
  const { userIds = [], value } = req.body ?? {};
  const stmt = db.prepare('UPDATE users SET whitelisted = ? WHERE user_id = ?');
  for (const id of userIds) stmt.run(value ? 1 : 0, String(id));
  if (value) for (const id of userIds) db.prepare('DELETE FROM unfollow_queue WHERE user_id = ?').run(String(id));
  res.json({ ok: true });
});

app.post('/api/queue', (req, res) => res.json({ added: enqueue(req.body?.userIds ?? []) }));
app.delete('/api/queue', (_req, res) => {
  db.exec('DELETE FROM unfollow_queue');
  res.json({ ok: true });
});

app.post('/api/runner', (req, res) => {
  setRunnerEnabled(!!req.body?.enabled);
  tick();
  res.json(runnerState());
});

app.put('/api/settings', (req, res) => {
  const next = { ...getSettings() };
  for (const key of Object.keys(DEFAULT_SETTINGS)) {
    const v = req.body?.[key];
    if (typeof DEFAULT_SETTINGS[key] === 'boolean' && typeof v === 'boolean') next[key] = v;
    if (typeof DEFAULT_SETTINGS[key] === 'number' && Number.isFinite(v) && v >= 0) next[key] = Math.floor(v);
  }
  next.snapshotHour = Math.min(23, next.snapshotHour);
  next.delayMinSec = Math.max(5, next.delayMinSec);
  next.delayMaxSec = Math.max(next.delayMinSec, next.delayMaxSec);
  setSetting('prefs', next);
  res.json(next);
});

const dist = path.resolve('dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist));
  app.use((_req, res) => res.sendFile(path.join(dist, 'index.html')));
}

// Planificateur : scan quotidien, puis reprise de la file d'unfollow quand les plafonds le permettent.
function tick() {
  if (busyState() || !getSetting('account') || getSetting('loggedOut', false)) return;
  const s = getSettings();
  if (s.autoSnapshot && snapshotDueToday(s.snapshotHour)) return void background(takeSnapshot('auto'));
  if (shouldStartBatch()) background(runBatch());
}
setInterval(tick, 60_000);

// Écoute uniquement en local : l'app contrôle ta session Instagram, elle ne doit pas être joignable du réseau.
app.listen(config.port, '127.0.0.1', () => {
  console.log(`IG Clean : http://localhost:${config.port}${config.mock ? ' (mode démo)' : ''}`);
  tick();
});
