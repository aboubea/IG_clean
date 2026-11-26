import type { Network, PostFormat } from "../networks.js";

export interface RemoteProfile {
  externalId: string;
  handle: string;
  displayName: string;
  avatarUrl?: string;
}

export interface DailyPoint {
  /** Jour au format AAAA-MM-JJ. */
  day: string;
  followers: number;
  reach?: number;
  impressions?: number;
  profileViews?: number;
}

export interface RemotePost {
  externalId: string;
  format: PostFormat;
  caption: string;
  permalink?: string;
  thumbnailUrl?: string;
  publishedAt: string;
  views?: number;
  reach?: number;
  likes: number;
  comments: number;
  shares: number;
  saves: number;
}

export interface SyncPayload {
  profile: RemoteProfile;
  daily: DailyPoint[];
  posts: RemotePost[];
}

export interface Credentials {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: string;
}

/**
 * Un réseau. Les connecteurs officiels passent par OAuth et l'API du réseau ;
 * les connecteurs de démo génèrent des données réalistes sans rien appeler.
 */
export interface Connector {
  network: Network;
  mode: "official" | "demo";
  /** URL d'autorisation à ouvrir dans l'app (connecteurs officiels). */
  authorizeUrl(state: string): string;
  exchangeCode(code: string): Promise<{ credentials: Credentials; profile: RemoteProfile }>;
  /** Compte fictif créé à la connexion (connecteurs de démo). */
  demoProfile(seed: string): RemoteProfile;
  fetch(credentials: Credentials | null, profile: RemoteProfile, since: Date): Promise<SyncPayload>;
}
