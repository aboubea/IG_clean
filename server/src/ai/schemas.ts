import { z } from "zod";
import { FORMATS, NETWORKS } from "../networks.js";

export const RecapSchema = z.object({
  headline: z.string().describe("Titre court et accrocheur de la semaine, 8 mots maximum"),
  summary: z.string().describe("Ce qui s'est passé cette semaine, en 2 phrases, chiffres à l'appui"),
  actions: z
    .array(
      z.object({
        title: z.string().describe("L'action, à l'impératif, 10 mots maximum"),
        detail: z.string().describe("Pourquoi et comment, en 1 ou 2 phrases fondées sur les données"),
        network: z.enum(NETWORKS).nullable().describe("Réseau concerné, ou null si l'action est générale"),
      }),
    )
    .describe("Exactement 3 actions pour la semaine prochaine, de la plus utile à la moins utile"),
});
export type Recap = z.infer<typeof RecapSchema>;

export const IdeasSchema = z.object({
  ideas: z
    .array(
      z.object({
        title: z.string().describe("Le sujet du contenu, 8 mots maximum"),
        network: z.enum(NETWORKS),
        format: z.enum(FORMATS),
        hook: z.string().describe("La première phrase, ou les 3 premières secondes d'une vidéo"),
        outline: z.array(z.string()).describe("3 à 5 étapes pour réaliser le contenu"),
        why: z.string().describe("Pourquoi cette idée devrait marcher chez cet utilisateur, d'après ses données"),
      }),
    )
    .describe("Exactement 5 idées, sur des réseaux et des formats qui marchent chez l'utilisateur"),
});
export type Ideas = z.infer<typeof IdeasSchema>;

export const PretestSchema = z.object({
  score: z.number().describe("Potentiel estimé de 0 à 100, relatif aux résultats habituels de l'utilisateur"),
  verdict: z.string().describe("Le verdict en une phrase"),
  bestNetwork: z.enum(NETWORKS).describe("Le réseau où publier ce contenu"),
  bestTime: z.string().describe("Le meilleur moment pour le publier, par exemple « jeudi, 18 h-21 h »"),
  strengths: z.array(z.string()).describe("2 ou 3 points forts"),
  improvements: z.array(z.string()).describe("2 ou 3 améliorations concrètes, de la plus importante à la moins importante"),
  improvedCaption: z.string().describe("La légende réécrite, prête à copier"),
  hooks: z.array(z.string()).describe("3 accroches alternatives"),
});
export type Pretest = z.infer<typeof PretestSchema>;

export interface PretestInput {
  caption: string;
  network: (typeof NETWORKS)[number] | null;
  format: (typeof FORMATS)[number] | null;
  image?: { mediaType: "image/jpeg" | "image/png" | "image/webp" | "image/gif"; data: string };
}

export interface UserProfile {
  profileType: "creator" | "business" | "curious";
  goal: "awareness" | "engagement" | "traffic" | "sales";
  displayName: string | null;
}
