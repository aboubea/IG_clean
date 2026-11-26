export const NETWORKS = ["instagram", "facebook", "tiktok", "linkedin"] as const;
export type Network = (typeof NETWORKS)[number];

export const FORMATS = ["short_video", "video", "carousel", "photo", "text", "article", "story"] as const;
export type PostFormat = (typeof FORMATS)[number];

export const NETWORK_LABELS: Record<Network, string> = {
  instagram: "Instagram",
  facebook: "Facebook",
  tiktok: "TikTok",
  linkedin: "LinkedIn",
};

export const FORMAT_LABELS: Record<PostFormat, string> = {
  short_video: "Vidéo courte",
  video: "Vidéo",
  carousel: "Carrousel",
  photo: "Photo",
  text: "Texte",
  article: "Article",
  story: "Story",
};

/** Pluriels, pour des phrases comme « publie 2 vidéos courtes de plus ». */
export const FORMAT_PLURALS: Record<PostFormat, string> = {
  short_video: "vidéos courtes",
  video: "vidéos",
  carousel: "carrousels",
  photo: "photos",
  text: "posts texte",
  article: "articles",
  story: "stories",
};

export const isNetwork = (value: unknown): value is Network =>
  typeof value === "string" && (NETWORKS as readonly string[]).includes(value);
