import { DatabaseSync } from 'node:sqlite';
import { config, DEFAULT_SETTINGS } from './config.js';

export const db = new DatabaseSync(config.dbPath);
db.exec(`
PRAGMA journal_mode = WAL;
CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS users(
  user_id TEXT PRIMARY KEY, username TEXT NOT NULL, full_name TEXT,
  is_private INTEGER, is_verified INTEGER,
  whitelisted INTEGER NOT NULL DEFAULT 0, updated_at INTEGER);
-- État courant : qui me suit ('follower') et qui je suis ('following').
CREATE TABLE IF NOT EXISTS relations(
  user_id TEXT NOT NULL, kind TEXT NOT NULL, since INTEGER NOT NULL,
  PRIMARY KEY(user_id, kind)) WITHOUT ROWID;
CREATE TABLE IF NOT EXISTS snapshots(
  id INTEGER PRIMARY KEY, at INTEGER NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL,
  followers INTEGER, following INTEGER,
  expected_followers INTEGER, expected_following INTEGER, error TEXT);
-- Historique : follower_gained, follower_lost, following_added, following_removed.
CREATE TABLE IF NOT EXISTS events(
  id INTEGER PRIMARY KEY, at INTEGER NOT NULL, type TEXT NOT NULL,
  user_id TEXT NOT NULL, snapshot_id INTEGER);
CREATE INDEX IF NOT EXISTS events_at ON events(at);
CREATE TABLE IF NOT EXISTS unfollow_queue(user_id TEXT PRIMARY KEY, added_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS unfollow_log(
  id INTEGER PRIMARY KEY, at INTEGER NOT NULL, user_id TEXT NOT NULL,
  status TEXT NOT NULL, detail TEXT);
CREATE INDEX IF NOT EXISTS unfollow_log_at ON unfollow_log(at);
`);

export function tx(fn) {
  db.exec('BEGIN');
  try {
    const out = fn();
    db.exec('COMMIT');
    return out;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

export function getSetting(key, fallback = null) {
  const row = db.prepare('SELECT value FROM settings WHERE key = ?').get(key);
  return row ? JSON.parse(row.value) : fallback;
}

export function setSetting(key, value) {
  db.prepare(
    'INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
  ).run(key, JSON.stringify(value));
}

export function getSettings() {
  return { ...DEFAULT_SETTINGS, ...getSetting('prefs', {}) };
}

export function upsertUsers(users, at) {
  const stmt = db.prepare(`
    INSERT INTO users(user_id, username, full_name, is_private, is_verified, updated_at)
    VALUES(?, ?, ?, ?, ?, ?)
    ON CONFLICT(user_id) DO UPDATE SET username = excluded.username, full_name = excluded.full_name,
      is_private = excluded.is_private, is_verified = excluded.is_verified, updated_at = excluded.updated_at`);
  for (const u of users) {
    stmt.run(u.id, u.username, u.fullName ?? '', u.isPrivate ? 1 : 0, u.isVerified ? 1 : 0, at);
  }
}
