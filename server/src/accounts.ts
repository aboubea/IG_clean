import { randomInt } from "node:crypto";
import { QUOTAS, type AiFeature } from "./config.js";
import { randomToken, sha256 } from "./crypto.js";
import type { Db } from "./db.js";

export interface UserRow {
  id: string;
  created_at: Date;
  display_name: string | null;
  profile_type: "creator" | "business" | "curious";
  goal: "awareness" | "engagement" | "traffic" | "sales";
  timezone: string;
  plan: "free" | "premium";
  premium_until: Date | null;
  referral_code: string;
  referred_by: string | null;
  public_slug: string | null;
  media_kit_public: boolean;
}

const USER_COLUMNS = `id, created_at, display_name, profile_type, goal, timezone, plan, premium_until,
  referral_code, referred_by, public_slug, media_kit_public`;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const referralCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join("");

/** Compte anonyme lié à l'appareil (la connexion avec Apple viendra en phase 2). */
export async function createUser(db: Db): Promise<{ user: UserRow; token: string }> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const rows = await db.query<UserRow>(
      `insert into users (referral_code) values ($1) on conflict (referral_code) do nothing returning ${USER_COLUMNS}`,
      [referralCode()],
    );
    const user = rows[0];
    if (!user) continue;
    const token = randomToken();
    await db.query("insert into sessions (token_hash, user_id) values ($1, $2)", [sha256(token), user.id]);
    return { user, token };
  }
  throw new Error("Impossible de créer le compte.");
}

export async function userForToken(db: Db, token: string): Promise<UserRow | null> {
  const rows = await db.query<UserRow>(
    `select ${USER_COLUMNS.split(",").map((c) => `u.${c.trim()}`).join(", ")}
     from sessions s join users u on u.id = s.user_id where s.token_hash = $1`,
    [sha256(token)],
  );
  return rows[0] ?? null;
}

export async function userById(db: Db, id: string): Promise<UserRow | null> {
  return (await db.query<UserRow>(`select ${USER_COLUMNS} from users where id = $1`, [id]))[0] ?? null;
}

export async function userBySlug(db: Db, slug: string): Promise<UserRow | null> {
  return (await db.query<UserRow>(`select ${USER_COLUMNS} from users where public_slug = $1`, [slug.toLowerCase()]))[0] ?? null;
}

export const isPremium = (user: UserRow, now = new Date()) =>
  user.plan === "premium" || (user.premium_until !== null && new Date(user.premium_until) > now);

/** Lundi de la semaine en cours (UTC), au format AAAA-MM-JJ. */
export function weekStart(now = new Date()): string {
  const day = (now.getUTCDay() + 6) % 7;
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - day)).toISOString().slice(0, 10);
}

export interface QuotaState {
  feature: AiFeature;
  used: number;
  limit: number;
  remaining: number;
}

export async function quota(db: Db, user: UserRow, feature: AiFeature): Promise<QuotaState> {
  const limit = QUOTAS[isPremium(user) ? "premium" : "free"][feature];
  const rows = await db.query<{ count: number }>(
    "select count from ai_usage where user_id = $1 and feature = $2 and week_start = $3",
    [user.id, feature, weekStart()],
  );
  const used = rows[0]?.count ?? 0;
  return { feature, used, limit, remaining: Math.max(0, limit - used) };
}

/** Compte une utilisation, seulement après un appel IA réussi. */
export async function recordUsage(db: Db, user: UserRow, feature: AiFeature): Promise<void> {
  await db.query(
    `insert into ai_usage (user_id, feature, week_start, count) values ($1, $2, $3, 1)
     on conflict (user_id, feature, week_start) do update set count = ai_usage.count + 1`,
    [user.id, feature, weekStart()],
  );
}

export type ReferralResult = "ok" | "unknown" | "self" | "already";

/** Parrainage : le filleul et le parrain gagnent chacun un mois de Premium. */
export async function redeemReferral(db: Db, user: UserRow, code: string): Promise<ReferralResult> {
  if (user.referred_by) return "already";
  const [sponsor] = await db.query<{ id: string }>("select id from users where referral_code = $1", [code.trim().toUpperCase()]);
  if (!sponsor) return "unknown";
  if (sponsor.id === user.id) return "self";
  const extend = `premium_until = greatest(coalesce(premium_until, now()), now()) + interval '30 days'`;
  await db.query(`update users set referred_by = $2, ${extend} where id = $1 and referred_by is null`, [user.id, sponsor.id]);
  await db.query(`update users set ${extend} where id = $1`, [sponsor.id]);
  return "ok";
}

export function publicUser(user: UserRow, baseUrl: string) {
  return {
    id: user.id,
    displayName: user.display_name,
    profileType: user.profile_type,
    goal: user.goal,
    timezone: user.timezone,
    premium: isPremium(user),
    premiumUntil: user.premium_until ? new Date(user.premium_until).toISOString() : null,
    referralCode: user.referral_code,
    referred: user.referred_by !== null,
    publicSlug: user.public_slug,
    mediaKitPublic: user.media_kit_public,
    mediaKitUrl: user.public_slug ? `${baseUrl}/@${user.public_slug}` : null,
  };
}
