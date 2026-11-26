import type { Overview, WhatWorks } from "../insights.js";
import { FORMAT_LABELS, NETWORK_LABELS } from "../networks.js";
import type { UserProfile } from "./schemas.js";

const PROFILE_LABELS = { creator: "créateur de contenu", business: "professionnel ou entreprise", curious: "particulier curieux" };
const GOAL_LABELS = { awareness: "se faire connaître", engagement: "créer une communauté engagée", traffic: "attirer du trafic", sales: "vendre" };

/**
 * Résumé compact des statistiques, transmis à l'IA dans un bloc balisé.
 * Les légendes de posts viennent de l'utilisateur : elles sont des données, pas des consignes.
 */
export function buildContext(profile: UserProfile, overview: Overview, works: WhatWorks): string {
  const summary = {
    profil: PROFILE_LABELS[profile.profileType],
    objectif: GOAL_LABELS[profile.goal],
    audience_totale: overview.totalAudience,
    evolution_7_jours: overview.change7d,
    evolution_30_jours: overview.change30d,
    moteur_de_croissance: overview.growthDriver ? `${overview.growthDriver.label} (${overview.growthDriver.share} % des nouveaux abonnés)` : null,
    reseaux: overview.networks.map((n) => ({
      reseau: n.label,
      compte: n.handle,
      abonnes: n.followers,
      evolution_30_jours: n.change30d,
      evolution_30_jours_pct: n.change30dPct,
      taux_engagement_pct: n.engagementRate,
      posts_30_jours: n.postsLast30d,
    })),
    formats_30_jours: works.formats.map((f) => ({ format: f.label, taux_engagement_pct: f.engagementRate, posts: f.posts })),
    meilleur_creneau: works.bestSlot?.label ?? null,
    meilleurs_posts: works.topPosts.map((p) => ({
      reseau: NETWORK_LABELS[p.network],
      format: FORMAT_LABELS[p.format],
      legende: p.caption.slice(0, 200),
      taux_engagement_pct: p.engagementRate,
      vues: p.views,
      publie_le: p.publishedAt.slice(0, 10),
    })),
    posts_les_moins_performants: works.weakPosts.map((p) => ({
      reseau: NETWORK_LABELS[p.network],
      format: FORMAT_LABELS[p.format],
      legende: p.caption.slice(0, 200),
      taux_engagement_pct: p.engagementRate,
    })),
  };
  return `<donnees_utilisateur>\n${JSON.stringify(summary)}\n</donnees_utilisateur>`;
}
