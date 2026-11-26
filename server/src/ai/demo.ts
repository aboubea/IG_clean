import type { Overview, WhatWorks } from "../insights.js";
import { FORMAT_LABELS, FORMAT_PLURALS, NETWORK_LABELS, type Network, type PostFormat } from "../networks.js";
import type { Ideas, Pretest, PretestInput, Recap, UserProfile } from "./schemas.js";

/**
 * IA de démonstration : réponses construites à partir des vraies statistiques, sans appel réseau.
 * Elle sert tant qu'aucune clé Anthropic n'est configurée, et dans les tests.
 */

const fmt = (n: number) => n.toLocaleString("fr-FR");
const signed = (n: number) => (n >= 0 ? `+${fmt(n)}` : `−${fmt(Math.abs(n))}`);

function bestPair(works: WhatWorks, overview: Overview): { network: Network; format: PostFormat } {
  const top = works.topPosts[0];
  if (top) return { network: top.network, format: top.format };
  return { network: overview.networks[0]?.network ?? "instagram", format: works.formats[0]?.format ?? "short_video" };
}

export function recap(profile: UserProfile, overview: Overview, works: WhatWorks): Recap {
  const driver = overview.growthDriver;
  const weakest = [...overview.networks].sort((a, b) => a.change30dPct - b.change30dPct)[0];
  const best = bestPair(works, overview);
  const format = works.formats[0];
  const headline = overview.change7d > 0 ? `${signed(overview.change7d)} abonnés cette semaine` : "Une semaine pour rebondir";
  const summary =
    `Ton audience totale atteint ${fmt(overview.totalAudience)} abonnés (${signed(overview.change7d)} en 7 jours).` +
    (driver ? ` ${driver.label} porte ta croissance avec ${driver.share} % de tes nouveaux abonnés.` : "");
  return {
    headline,
    summary,
    actions: [
      {
        title: `Publie 2 ${FORMAT_PLURALS[best.format]} de plus sur ${NETWORK_LABELS[best.network]}`,
        detail: format ? `C'est ton format le plus engageant : ${format.engagementRate} % d'engagement en moyenne.` : "C'est là que tes contenus marchent le mieux.",
        network: best.network,
      },
      {
        title: works.bestSlot ? `Programme tes posts ${works.bestSlot.label}` : "Teste plusieurs horaires de publication",
        detail: works.bestSlot ? "C'est le créneau où tes publications font le plus réagir." : "Il manque encore de données pour trouver ton meilleur créneau.",
        network: null,
      },
      weakest && weakest.change30dPct <= 0
        ? {
            title: `Allège ${weakest.label} : 1 post par semaine suffit`,
            detail: `${weakest.label} stagne (${weakest.change30dPct} % sur 30 jours) : garde ton énergie pour ce qui grandit.`,
            network: weakest.network,
          }
        : {
            title: "Recycle ton meilleur post sur un autre réseau",
            detail: "Un contenu qui a marché une fois a de bonnes chances de marcher ailleurs.",
            network: null,
          },
    ],
  };
}

export function ideas(_profile: UserProfile, overview: Overview, works: WhatWorks): Ideas {
  const pairs = works.topPosts.length
    ? works.topPosts.map((p) => ({ network: p.network, format: p.format, caption: p.caption }))
    : [{ ...bestPair(works, overview), caption: "ton meilleur sujet" }];
  const angles = [
    { title: "La suite de ton meilleur post", hook: "Vous avez été nombreux à me demander la suite…" },
    { title: "3 erreurs que tu as faites au début", hook: "Si je recommençais à zéro, j'éviterais ces 3 erreurs." },
    { title: "Les coulisses de ta semaine", hook: "Personne ne montre cette partie-là." },
    { title: "Réponds à la question la plus posée", hook: "C'est LA question qu'on me pose chaque semaine." },
    { title: "Avant / après", hook: "Voilà où j'en étais il y a 6 mois." },
  ];
  return {
    ideas: angles.map((angle, i) => {
      const pair = pairs[i % pairs.length]!;
      return {
        title: angle.title,
        network: pair.network,
        format: pair.format,
        hook: angle.hook,
        outline: ["Accroche dans les 3 premières secondes", "Un seul message clé, illustré", "Termine par une question pour lancer les commentaires"],
        why: `Le format ${FORMAT_LABELS[pair.format].toLowerCase()} sur ${NETWORK_LABELS[pair.network]} est l'un de tes plus performants (ex. « ${pair.caption} »).`,
      };
    }),
  };
}

export function pretest(_profile: UserProfile, overview: Overview, works: WhatWorks, input: PretestInput): Pretest {
  const caption = input.caption.trim();
  const best = bestPair(works, overview);
  const network = input.network ?? best.network;
  const format = input.format ?? best.format;
  const strengths: string[] = [];
  const improvements: string[] = [];
  let score = 50;

  const formatRank = works.formats.findIndex((f) => f.format === format);
  if (formatRank === 0) {
    score += 15;
    strengths.push(`${FORMAT_LABELS[format]} : c'est ton format le plus engageant.`);
  } else if (formatRank > 0) {
    improvements.push(`Le format ${FORMAT_LABELS[works.formats[0]!.format].toLowerCase()} marche mieux chez toi que ${FORMAT_LABELS[format].toLowerCase()}.`);
  }
  if (caption.length >= 40 && caption.length <= 300) {
    score += 10;
    strengths.push("Une légende de bonne longueur, ni trop courte ni trop longue.");
  } else {
    improvements.push(caption.length < 40 ? "Développe ta légende : quelques phrases donnent du contexte." : "Raccourcis ta légende : l'essentiel doit tenir dans les 2 premières lignes.");
  }
  if (caption.includes("?")) {
    score += 8;
    strengths.push("Une question qui invite à commenter.");
  } else {
    improvements.push("Termine par une question pour déclencher des commentaires.");
  }
  const hashtags = (caption.match(/#\w+/g) ?? []).length;
  if (hashtags > 8) {
    score -= 8;
    improvements.push("Trop de hashtags : garde les 3 à 5 plus pertinents.");
  }
  if (input.image) score += 5;

  return {
    score: Math.max(5, Math.min(95, score)),
    verdict: score >= 70 ? "Bon potentiel : publie-le avec les ajustements ci-dessous." : "Potentiel moyen : quelques ajustements peuvent tout changer.",
    bestNetwork: network,
    bestTime: works.bestSlot?.label ?? "en fin de journée, 18 h-21 h",
    strengths: strengths.slice(0, 3),
    improvements: improvements.slice(0, 3),
    improvedCaption: caption.includes("?") ? caption : `${caption}\n\nEt toi, tu en penses quoi ?`,
    hooks: ["Personne ne parle de ça, et pourtant…", "J'ai testé pendant 7 jours, voilà le résultat.", "Si tu ne devais retenir qu'une chose :"],
  };
}

/** Réponse du coach de démo, découpée en morceaux pour imiter un flux. */
export function coachReply(overview: Overview, works: WhatWorks, message: string): string {
  const text = message.toLowerCase();
  const driver = overview.growthDriver;
  const top = works.topPosts[0];
  if (/quand|heure|horaire|moment/.test(text)) {
    return works.bestSlot
      ? `D'après tes 30 derniers jours, ton meilleur créneau est ${works.bestSlot.label}. C'est là que tes posts font le plus réagir : programme tes contenus importants à ce moment-là.`
      : "Il me manque encore assez de posts pour trouver ton meilleur créneau. Publie à des horaires variés cette semaine, et je te dirai lequel marche le mieux.";
  }
  if (/pourquoi|marché|marche|meilleur post|top/.test(text) && top) {
    return `Ton meilleur post récent, « ${top.caption} » (${FORMAT_LABELS[top.format].toLowerCase()} sur ${NETWORK_LABELS[top.network]}), atteint ${top.engagementRate} % d'engagement. Ce qui joue : le format, qui est ton plus fort, et le moment de publication. Refais ce type de contenu avec un nouvel angle.`;
  }
  if (/réseau|reseau|où|ou publier|plateforme/.test(text)) {
    return driver
      ? `C'est ${driver.label} qui porte ta croissance : ${driver.share} % de tes nouveaux abonnés sur 30 jours. Mets-y la majorité de ton énergie, et recycle tes meilleurs contenus sur les autres réseaux.`
      : "Connecte au moins deux réseaux pour que je compare où tu grandis le plus vite.";
  }
  return `Tu as ${fmt(overview.totalAudience)} abonnés au total (${signed(overview.change30d)} sur 30 jours). Pose-moi une question précise : quand publier, pourquoi un post a marché, sur quel réseau miser… (réponse de démonstration : branche une clé Anthropic pour le vrai coach IA).`;
}
