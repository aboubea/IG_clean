import type { Db } from "./db.js";
import { FORMAT_LABELS, NETWORK_LABELS, type Network, type PostFormat } from "./networks.js";

export interface ConnectionRow {
  id: string;
  network: Network;
  mode: "official" | "demo";
  handle: string;
  display_name: string | null;
  status: string;
  last_synced_at: Date | null;
  last_error: string | null;
}

export interface DailyRow {
  connection_id: string;
  day: string;
  followers: number;
}

export interface PostRow {
  id: string;
  connection_id: string;
  format: PostFormat;
  caption: string;
  permalink: string | null;
  published_at: Date;
  views: number | null;
  reach: number | null;
  likes: number;
  comments: number;
  shares: number;
  saves: number;
}

export interface UserData {
  connections: ConnectionRow[];
  daily: DailyRow[];
  posts: PostRow[];
  timezone: string;
  now: Date;
}

const DAY = 86_400_000;
const MILESTONES = [100, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 500_000, 1_000_000];
const WEEKDAYS_FR = ["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."];
/** Créneaux horaires (heure locale) : 6 h-9 h, 9 h-12 h, …, 21 h-24 h. La nuit compte avec le dernier. */
export const SLOTS = [6, 9, 12, 15, 18, 21];

const round1 = (value: number) => Math.round(value * 10) / 10;
const interactions = (p: PostRow) => p.likes + p.comments + p.shares + p.saves;

/** Base de l'engagement : portée, sinon vues, sinon abonnés au moment du post. */
function engagementBase(post: PostRow, followers: number): number {
  return post.reach || post.views || followers || 0;
}

/** Taux d'engagement d'un post, en %, comparable d'un réseau à l'autre. */
export function postEngagementRate(post: PostRow, followers: number): number {
  const base = engagementBase(post, followers);
  return base > 0 ? (interactions(post) / base) * 100 : 0;
}

function followersAt(series: DailyRow[], date: Date): number {
  const day = date.toISOString().slice(0, 10);
  let value = series[0]?.followers ?? 0;
  for (const point of series) {
    if (point.day > day) break;
    value = point.followers;
  }
  return value;
}

function seriesByConnection(daily: DailyRow[]): Map<string, DailyRow[]> {
  const map = new Map<string, DailyRow[]>();
  for (const row of daily) {
    const list = map.get(row.connection_id) ?? [];
    list.push(row);
    map.set(row.connection_id, list);
  }
  for (const list of map.values()) list.sort((a, b) => a.day.localeCompare(b.day));
  return map;
}

// MARK: Vue d'ensemble

export interface NetworkSummary {
  connectionId: string;
  network: Network;
  label: string;
  handle: string;
  mode: "official" | "demo";
  followers: number;
  change7d: number;
  change30d: number;
  change30dPct: number;
  engagementRate: number;
  postsLast30d: number;
  lastSyncedAt: string | null;
  lastError: string | null;
}

export interface Milestone {
  kind: "followers" | "total" | "record";
  network: Network | null;
  value: number;
  label: string;
  at: string;
  postId?: string;
}

export interface Overview {
  totalAudience: number;
  change7d: number;
  change30d: number;
  series: Array<{ day: string; total: number }>;
  networks: NetworkSummary[];
  growthDriver: { network: Network; label: string; share: number } | null;
  milestones: Milestone[];
}

export function overview(data: UserData): Overview {
  const series = seriesByConnection(data.daily);
  const since30 = new Date(data.now.getTime() - 30 * DAY);
  const since7 = new Date(data.now.getTime() - 7 * DAY);
  const networks: NetworkSummary[] = [];

  for (const connection of data.connections) {
    const points = series.get(connection.id) ?? [];
    const latest = points[points.length - 1];
    const followers = latest?.followers ?? 0;
    const latestDate = latest ? new Date(`${latest.day}T00:00:00Z`) : data.now;
    const before30 = followersAt(points, new Date(latestDate.getTime() - 30 * DAY));
    const before7 = followersAt(points, new Date(latestDate.getTime() - 7 * DAY));
    const recent = data.posts.filter((p) => p.connection_id === connection.id && p.published_at >= since30);
    const totalInteractions = recent.reduce((sum, p) => sum + interactions(p), 0);
    const totalBase = recent.reduce((sum, p) => sum + engagementBase(p, followersAt(points, p.published_at)), 0);
    networks.push({
      connectionId: connection.id,
      network: connection.network,
      label: NETWORK_LABELS[connection.network],
      handle: connection.handle,
      mode: connection.mode,
      followers,
      change7d: followers - before7,
      change30d: followers - before30,
      change30dPct: before30 > 0 ? round1(((followers - before30) / before30) * 100) : 0,
      engagementRate: totalBase > 0 ? round1((totalInteractions / totalBase) * 100) : 0,
      postsLast30d: recent.length,
      lastSyncedAt: connection.last_synced_at ? new Date(connection.last_synced_at).toISOString() : null,
      lastError: connection.last_error,
    });
  }
  networks.sort((a, b) => b.followers - a.followers);

  // Audience totale jour par jour, en reportant la dernière valeur connue de chaque réseau.
  const days: string[] = [];
  for (let i = 30; i >= 1; i--) days.push(new Date(data.now.getTime() - i * DAY).toISOString().slice(0, 10));
  const totalSeries = days.map((day) => ({
    day,
    total: data.connections.reduce((sum, c) => sum + followersAt(series.get(c.id) ?? [], new Date(`${day}T00:00:00Z`)), 0),
  }));

  const positive = networks.filter((n) => n.change30d > 0);
  const positiveSum = positive.reduce((sum, n) => sum + n.change30d, 0);
  const driver = positive.sort((a, b) => b.change30d - a.change30d)[0];

  return {
    totalAudience: networks.reduce((sum, n) => sum + n.followers, 0),
    change7d: networks.reduce((sum, n) => sum + n.change7d, 0),
    change30d: networks.reduce((sum, n) => sum + n.change30d, 0),
    series: totalSeries,
    networks,
    growthDriver:
      driver && networks.length > 1 && positiveSum > 0
        ? { network: driver.network, label: driver.label, share: Math.round((driver.change30d / positiveSum) * 100) }
        : null,
    milestones: milestones(data, series, since7),
  };
}

function crossed(before: number, after: number): number | null {
  const hit = MILESTONES.filter((m) => before < m && after >= m);
  return hit.length ? hit[hit.length - 1]! : null;
}

/** Moments à célébrer (et à partager) sur les 7 derniers jours. */
export function milestones(data: UserData, series: Map<string, DailyRow[]>, since: Date): Milestone[] {
  const found: Milestone[] = [];
  const sinceDay = since.toISOString().slice(0, 10);
  let totalBefore = 0;
  let totalAfter = 0;

  for (const connection of data.connections) {
    const points = series.get(connection.id) ?? [];
    const before = [...points].reverse().find((p) => p.day < sinceDay)?.followers ?? points[0]?.followers ?? 0;
    const after = points[points.length - 1]?.followers ?? 0;
    totalBefore += before;
    totalAfter += after;
    const value = crossed(before, after);
    if (value) {
      const day = points.find((p) => p.followers >= value && p.day >= sinceDay)?.day ?? sinceDay;
      found.push({
        kind: "followers",
        network: connection.network,
        value,
        label: `${value.toLocaleString("fr-FR")} abonnés sur ${NETWORK_LABELS[connection.network]}`,
        at: `${day}T12:00:00.000Z`,
      });
    }

    // Record : un post récent qui fait au moins 3 fois mieux que la médiane du compte.
    const own = data.posts.filter((p) => p.connection_id === connection.id);
    const older = own.filter((p) => p.published_at < since).map(interactions).sort((a, b) => a - b);
    const median = older.length ? older[Math.floor(older.length / 2)]! : 0;
    const best = own.filter((p) => p.published_at >= since).sort((a, b) => interactions(b) - interactions(a))[0];
    if (best && median > 0 && interactions(best) >= median * 3) {
      found.push({
        kind: "record",
        network: connection.network,
        value: Math.round(interactions(best) / median),
        label: `Un post ${Math.round(interactions(best) / median)}× au-dessus de ta moyenne sur ${NETWORK_LABELS[connection.network]}`,
        at: best.published_at.toISOString(),
        postId: best.id,
      });
    }
  }

  const total = data.connections.length > 1 ? crossed(totalBefore, totalAfter) : null;
  if (total) {
    found.push({ kind: "total", network: null, value: total, label: `${total.toLocaleString("fr-FR")} abonnés au total`, at: data.now.toISOString() });
  }
  return found.sort((a, b) => b.at.localeCompare(a.at));
}

// MARK: Ce qui marche

export interface FormatStat {
  format: PostFormat;
  label: string;
  engagementRate: number;
  posts: number;
}

export interface TopPost {
  id: string;
  network: Network;
  format: PostFormat;
  formatLabel: string;
  caption: string;
  permalink: string | null;
  publishedAt: string;
  views: number | null;
  reach: number | null;
  interactions: number;
  engagementRate: number;
}

export interface WhatWorks {
  days: number;
  postCount: number;
  formats: FormatStat[];
  networks: Array<{ network: Network; label: string; engagementRate: number; posts: number }>;
  /** heat[jour][créneau] entre 0 et 1 ; null quand aucun post ne permet de juger. */
  heat: Array<Array<number | null>>;
  slotStarts: number[];
  bestSlot: { label: string; weekdays: number[]; slot: number } | null;
  topPosts: TopPost[];
  weakPosts: TopPost[];
}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

/** Jour (0 = lundi) et heure locale d'une date, dans le fuseau de l'utilisateur. */
export function localWeekdayHour(date: Date, timezone: string): { weekday: number; hour: number } {
  let formatter = formatterCache.get(timezone);
  if (!formatter) {
    formatter = new Intl.DateTimeFormat("en-US", { timeZone: timezone, weekday: "short", hour: "numeric", hourCycle: "h23" });
    formatterCache.set(timezone, formatter);
  }
  const parts = formatter.formatToParts(date);
  const weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].indexOf(parts.find((p) => p.type === "weekday")?.value ?? "Mon");
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? 0);
  return { weekday: Math.max(0, weekday), hour };
}

export function slotIndex(hour: number): number {
  if (hour < SLOTS[0]!) return SLOTS.length - 1;
  let index = 0;
  SLOTS.forEach((start, i) => {
    if (hour >= start) index = i;
  });
  return index;
}

export function whatWorks(data: UserData, days = 30): WhatWorks {
  const since = new Date(data.now.getTime() - days * DAY);
  const series = seriesByConnection(data.daily);
  const networkOf = new Map(data.connections.map((c) => [c.id, c.network]));
  const posts = data.posts.filter((p) => p.published_at >= since && networkOf.has(p.connection_id));
  const rated = posts.map((post) => ({
    post,
    network: networkOf.get(post.connection_id)!,
    rate: postEngagementRate(post, followersAt(series.get(post.connection_id) ?? [], post.published_at)),
  }));

  const byFormat = new Map<PostFormat, number[]>();
  const byNetwork = new Map<Network, number[]>();
  const cells: number[][][] = Array.from({ length: 7 }, () => Array.from({ length: SLOTS.length }, () => []));
  for (const item of rated) {
    byFormat.set(item.post.format, [...(byFormat.get(item.post.format) ?? []), item.rate]);
    byNetwork.set(item.network, [...(byNetwork.get(item.network) ?? []), item.rate]);
    const { weekday, hour } = localWeekdayHour(item.post.published_at, data.timezone);
    cells[weekday]![slotIndex(hour)]!.push(item.rate);
  }
  const mean = (values: number[]) => values.reduce((sum, v) => sum + v, 0) / values.length;

  const averages = cells.map((row) => row.map((values) => (values.length ? mean(values) : null)));
  const max = Math.max(0, ...averages.flat().filter((v): v is number => v !== null));
  const heat = averages.map((row) => row.map((v) => (v === null || max === 0 ? null : Math.round((v / max) * 100) / 100)));

  // Meilleur créneau : la tranche horaire la plus forte, puis les jours qui y dépassent 85 % du maximum.
  let bestSlot: WhatWorks["bestSlot"] = null;
  const slotScores = SLOTS.map((_, s) => {
    const values = cells.flatMap((row) => row[s]!);
    return values.length >= 2 ? mean(values) : -1;
  });
  const best = slotScores.indexOf(Math.max(...slotScores));
  if (best >= 0 && slotScores[best]! > 0) {
    const column = averages.map((row) => row[best] ?? null);
    const top = Math.max(...column.filter((v): v is number => v !== null));
    const weekdays = column.flatMap((v, day) => (v !== null && v >= top * 0.85 ? [day] : []));
    const end = best === SLOTS.length - 1 ? 24 : SLOTS[best + 1]!;
    const dayLabel = weekdays.length >= 5 ? "tous les jours" : weekdays.map((d) => WEEKDAYS_FR[d]).join(" et ").replace(/ et (?=.* et )/g, ", ");
    bestSlot = { label: `${dayLabel}, ${SLOTS[best]} h-${end} h`, weekdays, slot: best };
  }

  const toTop = (item: (typeof rated)[number]): TopPost => ({
    id: item.post.id,
    network: item.network,
    format: item.post.format,
    formatLabel: FORMAT_LABELS[item.post.format],
    caption: item.post.caption,
    permalink: item.post.permalink,
    publishedAt: item.post.published_at.toISOString(),
    views: item.post.views,
    reach: item.post.reach,
    interactions: interactions(item.post),
    engagementRate: round1(item.rate),
  });
  const ranked = [...rated].sort((a, b) => b.rate - a.rate);

  return {
    days,
    postCount: posts.length,
    formats: [...byFormat.entries()]
      .map(([format, rates]) => ({ format, label: FORMAT_LABELS[format], engagementRate: round1(mean(rates)), posts: rates.length }))
      .sort((a, b) => b.engagementRate - a.engagementRate),
    networks: [...byNetwork.entries()]
      .map(([network, rates]) => ({ network, label: NETWORK_LABELS[network], engagementRate: round1(mean(rates)), posts: rates.length }))
      .sort((a, b) => b.engagementRate - a.engagementRate),
    heat,
    slotStarts: SLOTS,
    bestSlot,
    topPosts: ranked.slice(0, 5).map(toTop),
    weakPosts: ranked.slice(-3).reverse().map(toTop),
  };
}

// MARK: Chargement depuis la base

export async function loadUserData(db: Db, userId: string, now = new Date()): Promise<UserData> {
  const [user] = await db.query<{ timezone: string }>("select timezone from users where id = $1", [userId]);
  const connections = await db.query<ConnectionRow>(
    `select id, network, mode, handle, display_name, status, last_synced_at, last_error
     from connections where user_id = $1 order by created_at`,
    [userId],
  );
  const ids = connections.map((c) => c.id);
  if (!ids.length) return { connections, daily: [], posts: [], timezone: user?.timezone ?? "Europe/Paris", now };
  const since = new Date(now.getTime() - 400 * DAY);
  const daily = await db.query<DailyRow>(
    `select connection_id, to_char(day, 'YYYY-MM-DD') as day, followers
     from account_daily where connection_id = any($1::uuid[]) and day >= $2::date order by day`,
    [ids, since.toISOString().slice(0, 10)],
  );
  const posts = await db.query<PostRow>(
    `select id, connection_id, format, caption, permalink, published_at, views, reach, likes, comments, shares, saves
     from posts where connection_id = any($1::uuid[]) and published_at >= $2 order by published_at`,
    [ids, since.toISOString()],
  );
  for (const post of posts) post.published_at = new Date(post.published_at);
  return { connections, daily, posts, timezone: user?.timezone ?? "Europe/Paris", now };
}
