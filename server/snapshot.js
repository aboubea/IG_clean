import { db, tx, setSetting, upsertUsers } from './db.js';
import { runExclusive } from './lock.js';
import { openSession } from './ig/index.js';

// Instagram affiche des compteurs légèrement supérieurs aux listes réelles (comptes désactivés) :
// en dessous de ce ratio, on considère le scan tronqué et on ne touche pas à l'état.
const COMPLETE_RATIO = 0.97;
const KINDS = [
  { list: 'followers', kind: 'follower', gained: 'follower_gained', lost: 'follower_lost' },
  { list: 'following', kind: 'following', gained: 'following_added', lost: 'following_removed' },
];

export function applySnapshot({ me, followers, following, source, at = Date.now() }) {
  const complete =
    followers.length >= Math.floor(me.followerCount * COMPLETE_RATIO) &&
    following.length >= Math.floor(me.followingCount * COMPLETE_RATIO);
  return tx(() => {
    const { lastInsertRowid: snapshotId } = db
      .prepare(
        `INSERT INTO snapshots(at, source, status, followers, following, expected_followers, expected_following)
         VALUES(?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(at, source, complete ? 'ok' : 'incomplete', followers.length, following.length, me.followerCount, me.followingCount);
    if (!complete) return { snapshotId, status: 'incomplete', events: 0 };

    // Le tout premier scan complet sert de référence : il ne génère pas d'événements.
    const hasBaseline = db.prepare("SELECT 1 FROM snapshots WHERE status = 'ok' AND id <> ?").get(snapshotId);
    upsertUsers([...followers, ...following], at);
    const addEvent = db.prepare('INSERT INTO events(at, type, user_id, snapshot_id) VALUES(?, ?, ?, ?)');
    const addRel = db.prepare('INSERT INTO relations(user_id, kind, since) VALUES(?, ?, ?)');
    const delRel = db.prepare('DELETE FROM relations WHERE user_id = ? AND kind = ?');
    let events = 0;
    for (const k of KINDS) {
      const now = new Set((k.list === 'followers' ? followers : following).map((u) => u.id));
      const before = new Set(db.prepare('SELECT user_id FROM relations WHERE kind = ?').all(k.kind).map((r) => r.user_id));
      for (const id of now) {
        if (before.has(id)) continue;
        addRel.run(id, k.kind, at);
        if (hasBaseline) (addEvent.run(at, k.gained, id, snapshotId), events++);
      }
      for (const id of before) {
        if (now.has(id)) continue;
        delRel.run(id, k.kind);
        if (hasBaseline) (addEvent.run(at, k.lost, id, snapshotId), events++);
      }
    }
    // La file d'unfollow ne garde que des comptes que je suis encore et qui ne me suivent pas.
    db.exec(`DELETE FROM unfollow_queue WHERE
      user_id NOT IN (SELECT user_id FROM relations WHERE kind = 'following')
      OR user_id IN (SELECT user_id FROM relations WHERE kind = 'follower')`);
    return { snapshotId, status: 'ok', events };
  });
}

export function takeSnapshot(source = 'manual') {
  return runExclusive('snapshot', async (progress) => {
    let session;
    try {
      progress('Ouverture de la session…');
      session = await openSession();
      const me = await session.me();
      setSetting('account', { id: me.id, username: me.username });
      const followers = await session.list('followers', (n) => progress(`Abonnés : ${n} / ${me.followerCount}`));
      const following = await session.list('following', (n) => progress(`Abonnements : ${n} / ${me.followingCount}`));
      return applySnapshot({ me, followers, following, source });
    } catch (e) {
      if (e.code === 'LOGGED_OUT') setSetting('loggedOut', true);
      db.prepare("INSERT INTO snapshots(at, source, status, error) VALUES(?, ?, 'error', ?)").run(Date.now(), source, e.message);
      throw e;
    } finally {
      await session?.close();
    }
  });
}

export function snapshotDueToday(snapshotHour) {
  const now = new Date();
  if (now.getHours() < snapshotHour) return false;
  const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  // Un seul essai automatique par jour, pour ne pas insister si Instagram bloque.
  return !db.prepare("SELECT 1 FROM snapshots WHERE at >= ? AND (status = 'ok' OR source = 'auto')").get(midnight);
}
