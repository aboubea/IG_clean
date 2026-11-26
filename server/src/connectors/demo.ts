import type { Network, PostFormat } from "../networks.js";
import type { Connector, DailyPoint, RemotePost, RemoteProfile, SyncPayload } from "./types.js";

/** Générateur pseudo-aléatoire déterministe : mêmes données à chaque synchronisation d'un compte. */
function prng(seedText: string) {
  let seed = 2166136261;
  for (const char of seedText) seed = Math.imul(seed ^ char.charCodeAt(0), 16777619);
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Personality {
  base: number;
  dailyGrowth: number;
  postEvery: number;
  engagement: number;
  reachRatio: number;
  saves: boolean;
  formats: Array<[PostFormat, number, number]>; // format, fréquence, multiplicateur d'engagement
}

/** Chaque réseau a son caractère, pour que les analyses aient quelque chose à découvrir. */
const PERSONALITIES: Record<Network, Personality> = {
  tiktok: { base: 28_400, dailyGrowth: 0.0029, postEvery: 2, engagement: 0.068, reachRatio: 2.4, saves: true, formats: [["short_video", 1, 1]] },
  instagram: {
    base: 11_700, dailyGrowth: 0.001, postEvery: 3, engagement: 0.042, reachRatio: 0.85, saves: true,
    formats: [["short_video", 0.45, 1], ["carousel", 0.3, 0.8], ["photo", 0.25, 0.4]],
  },
  facebook: {
    base: 5_320, dailyGrowth: -0.00016, postEvery: 4, engagement: 0.02, reachRatio: 0.35, saves: false,
    formats: [["photo", 0.4, 0.6], ["video", 0.3, 1], ["text", 0.3, 0.45]],
  },
  linkedin: {
    base: 2_150, dailyGrowth: 0.0016, postEvery: 4, engagement: 0.042, reachRatio: 1.3, saves: false,
    formats: [["text", 0.45, 0.85], ["carousel", 0.25, 1.25], ["video", 0.15, 0.7], ["article", 0.15, 0.5]],
  },
};

const CAPTIONS: Record<PostFormat, string[]> = {
  short_video: ["Ma routine du matin en 30 secondes", "3 astuces que personne ne te dit", "Avant / après : le résultat", "POV : ton lundi matin", "Je teste la tendance du moment", "Les coulisses d'une journée"],
  video: ["Tuto complet pas à pas", "On répond à vos questions", "Visite des coulisses", "Le making-of"],
  carousel: ["5 erreurs à éviter", "Le guide en 7 étapes", "Ce que j'aurais aimé savoir avant", "Mes outils préférés", "Checklist à garder"],
  photo: ["Nouveau projet 📸", "Petit moment de la semaine", "Le résultat final", "Merci pour vos messages ❤️"],
  text: ["Ce que j'ai appris en lançant mon activité", "Une leçon qui m'a coûté cher", "Pourquoi j'ai changé d'avis sur un sujet", "Mon conseil n°1 pour démarrer"],
  article: ["Analyse : les tendances du secteur", "Retour d'expérience complet", "Le guide pour bien démarrer"],
  story: ["Sondage du jour", "Question du jour"],
};

const HANDLES: Record<Network, string> = { instagram: "pulse.demo", facebook: "Pulse Démo", tiktok: "pulse.demo", linkedin: "Pulse Démo" };

const dayString = (date: Date) => date.toISOString().slice(0, 10);

function pick<T>(rand: () => number, items: Array<[T, number, number]>): [T, number, number] {
  const total = items.reduce((sum, item) => sum + item[1], 0);
  let roll = rand() * total;
  for (const item of items) {
    roll -= item[1];
    if (roll <= 0) return item;
  }
  return items[items.length - 1]!;
}

/** Effet du moment de publication (heure de Paris) : mardi, jeudi et 18 h - 21 h ressortent. */
function timingEffect(weekday: number, hour: number): number {
  const day = weekday === 2 || weekday === 4 ? 1.3 : weekday === 0 ? 0.8 : 1;
  const time = hour >= 18 && hour < 21 ? 1.35 : hour < 9 ? 0.7 : hour >= 12 && hour < 14 ? 1.1 : 1;
  return day * time;
}

export function generateDemo(network: Network, profile: RemoteProfile, now = new Date(), days = 120): SyncPayload {
  const p = PERSONALITIES[network];
  const rand = prng(`${network}:${profile.externalId}`);
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const daily: DailyPoint[] = [];
  const posts: RemotePost[] = [];
  let followers = p.base;
  let nextPost = Math.floor(rand() * p.postEvery);

  for (let i = days; i >= 1; i--) {
    const date = new Date(today.getTime() - i * 86_400_000);
    followers = followers * (1 + p.dailyGrowth) + (rand() - 0.5) * p.base * 0.002;
    const rounded = Math.max(0, Math.round(followers));
    daily.push({ day: dayString(date), followers: rounded, reach: Math.round(rounded * (0.15 + rand() * 0.2)) });

    if (--nextPost > 0) continue;
    nextPost = p.postEvery + Math.round((rand() - 0.5) * 2);
    const [format, , engagementFactor] = pick(rand, p.formats);
    const hourRoll = rand();
    const hour = hourRoll < 0.45 ? 18 + Math.floor(rand() * 3) : hourRoll < 0.65 ? 12 + Math.floor(rand() * 2) : 7 + Math.floor(rand() * 10);
    const weekday = date.getUTCDay();
    const effect = timingEffect(weekday, hour) * (rand() < 0.05 ? 4 : 1); // de temps en temps, un post explose
    const reach = Math.round(rounded * p.reachRatio * (0.45 + rand() * 1.1) * effect);
    const interactions = reach * p.engagement * engagementFactor * effect * (0.65 + rand() * 0.7);
    const isVideo = format === "short_video" || format === "video";
    const captions = CAPTIONS[format];
    posts.push({
      externalId: `${network}-${dayString(date)}-${posts.length}`,
      format,
      caption: captions[Math.floor(rand() * captions.length)]!,
      // Heure de Paris approximée en UTC (heure d'hiver), suffisant pour la démo.
      publishedAt: new Date(date.getTime() + (hour - 1) * 3_600_000 + Math.floor(rand() * 59) * 60_000).toISOString(),
      views: isVideo ? Math.round(reach * 1.35) : undefined,
      reach,
      likes: Math.round(interactions * 0.8),
      comments: Math.round(interactions * 0.07),
      shares: Math.round(interactions * 0.08),
      saves: p.saves ? Math.round(interactions * 0.05) : 0,
    });
  }
  return { profile, daily, posts };
}

export function demoConnector(network: Network): Connector {
  return {
    network,
    mode: "demo",
    authorizeUrl: () => {
      throw new Error("Les connecteurs de démo n'utilisent pas OAuth.");
    },
    exchangeCode: async () => {
      throw new Error("Les connecteurs de démo n'utilisent pas OAuth.");
    },
    demoProfile: (seed) => ({
      externalId: `demo-${network}-${seed}`,
      handle: HANDLES[network],
      displayName: "Compte de démonstration",
    }),
    fetch: async (_credentials, profile) => generateDemo(network, profile),
  };
}
