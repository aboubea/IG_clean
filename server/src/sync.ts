import { connectorFor } from "./connectors/index.js";
import type { Credentials, RemoteProfile, SyncPayload } from "./connectors/types.js";
import { open, seal } from "./crypto.js";
import type { Db } from "./db.js";
import type { Network } from "./networks.js";

export interface ConnectionRecord {
  id: string;
  user_id: string;
  network: Network;
  mode: "official" | "demo";
  external_id: string;
  handle: string;
  display_name: string | null;
  credentials: string | null;
}

/** Enregistre (ou remplace) le compte d'un réseau pour un utilisateur. */
export async function saveConnection(
  db: Db,
  userId: string,
  network: Network,
  mode: "official" | "demo",
  profile: RemoteProfile,
  credentials: Credentials | null,
): Promise<ConnectionRecord> {
  const [row] = await db.query<ConnectionRecord>(
    `insert into connections (user_id, network, mode, external_id, handle, display_name, avatar_url, credentials, status, last_error)
     values ($1, $2, $3, $4, $5, $6, $7, $8, 'active', null)
     on conflict (user_id, network) do update set
       mode = excluded.mode, external_id = excluded.external_id, handle = excluded.handle,
       display_name = excluded.display_name, avatar_url = excluded.avatar_url,
       credentials = excluded.credentials, status = 'active', last_error = null
     returning id, user_id, network, mode, external_id, handle, display_name, credentials`,
    [userId, network, mode, profile.externalId, profile.handle, profile.displayName, profile.avatarUrl ?? null, credentials ? seal(JSON.stringify(credentials)) : null],
  );
  if (!row) throw new Error("Connexion non enregistrée.");
  return row;
}

async function store(db: Db, connectionId: string, payload: SyncPayload): Promise<void> {
  for (const point of payload.daily) {
    await db.query(
      `insert into account_daily (connection_id, day, followers, reach, impressions, profile_views)
       values ($1, $2, $3, $4, $5, $6)
       on conflict (connection_id, day) do update set
         followers = excluded.followers, reach = excluded.reach,
         impressions = excluded.impressions, profile_views = excluded.profile_views`,
      [connectionId, point.day, point.followers, point.reach ?? null, point.impressions ?? null, point.profileViews ?? null],
    );
  }
  for (const post of payload.posts) {
    await db.query(
      `insert into posts (connection_id, external_id, format, caption, permalink, thumbnail_url, published_at,
                          views, reach, likes, comments, shares, saves, metrics_updated_at)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now())
       on conflict (connection_id, external_id) do update set
         format = excluded.format, caption = excluded.caption, permalink = excluded.permalink,
         thumbnail_url = excluded.thumbnail_url, views = excluded.views, reach = excluded.reach,
         likes = excluded.likes, comments = excluded.comments, shares = excluded.shares,
         saves = excluded.saves, metrics_updated_at = now()`,
      [
        connectionId, post.externalId, post.format, post.caption, post.permalink ?? null, post.thumbnailUrl ?? null,
        post.publishedAt, post.views ?? null, post.reach ?? null, post.likes, post.comments, post.shares, post.saves,
      ],
    );
  }
}

/** Relève les chiffres d'un compte. Les erreurs sont enregistrées sur la connexion plutôt que propagées. */
export async function syncConnection(db: Db, connection: ConnectionRecord): Promise<{ ok: boolean; error?: string }> {
  const connector = connectorFor(connection.network);
  try {
    if (!connector) throw new Error("Ce réseau n'est pas encore disponible.");
    const credentials = connection.credentials ? (JSON.parse(open(connection.credentials)) as Credentials) : null;
    const profile: RemoteProfile = {
      externalId: connection.external_id,
      handle: connection.handle,
      displayName: connection.display_name ?? connection.handle,
    };
    const since = new Date(Date.now() - 120 * 86_400_000);
    const payload = await connector.fetch(credentials, profile, since);
    await store(db, connection.id, payload);
    await db.query(
      `update connections set handle = $2, display_name = $3, last_synced_at = now(), last_error = null, status = 'active' where id = $1`,
      [connection.id, payload.profile.handle, payload.profile.displayName],
    );
    return { ok: true };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await db.query(`update connections set last_error = $2 where id = $1`, [connection.id, message]);
    return { ok: false, error: message };
  }
}

export async function syncUser(db: Db, userId: string): Promise<void> {
  const connections = await db.query<ConnectionRecord>(
    `select id, user_id, network, mode, external_id, handle, display_name, credentials from connections where user_id = $1`,
    [userId],
  );
  for (const connection of connections) await syncConnection(db, connection);
}

/** Synchronisation nocturne de tous les comptes. */
export async function syncAll(db: Db): Promise<{ total: number; failed: number }> {
  const connections = await db.query<ConnectionRecord>(
    `select id, user_id, network, mode, external_id, handle, display_name, credentials from connections where status = 'active'`,
  );
  let failed = 0;
  for (const connection of connections) {
    const result = await syncConnection(db, connection);
    if (!result.ok) failed++;
  }
  return { total: connections.length, failed };
}
