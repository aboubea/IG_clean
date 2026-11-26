/** Configuration lue dans l'environnement. Rien de secret n'est écrit en dur. */
const env = process.env;

export const config = {
  port: Number(env.PORT ?? 8787),
  host: env.HOST ?? "0.0.0.0",
  production: env.NODE_ENV === "production",
  /** URL Postgres. Absente : base PGlite locale (développement et tests). */
  databaseUrl: env.DATABASE_URL,
  /** Dossier de la base PGlite ; "memory://" pour une base jetable. */
  pgliteDir: env.PULSE_PGLITE_DIR ?? ".data/pglite",
  /** Adresse publique du serveur : liens de media kit et retours OAuth. */
  publicBaseUrl: (env.PUBLIC_BASE_URL ?? "http://localhost:8787").replace(/\/$/, ""),
  /** Schéma d'URL de l'app iOS, pour revenir dans l'app après une connexion de réseau. */
  appScheme: env.APP_SCHEME ?? "pulse",
  /** Clé AES-256 (32 octets en base64) qui chiffre les jetons des réseaux. */
  tokenEncryptionKey: env.TOKEN_ENCRYPTION_KEY,
  ai: {
    model: env.PULSE_AI_MODEL ?? "claude-opus-5-5",
    /** Sans identifiants Anthropic (ou avec PULSE_AI=demo), l'IA répond en mode démo, sans appel réseau. */
    enabled: env.PULSE_AI !== "demo" && Boolean(env.ANTHROPIC_API_KEY || env.ANTHROPIC_AUTH_TOKEN),
  },
  /** Connecteurs de démonstration : données réalistes générées, en attendant les accès officiels. */
  demoConnectors: env.PULSE_DEMO_CONNECTORS !== "0",
};

/** Quotas hebdomadaires des fonctions IA. Premium = abonnement ou mois offert par parrainage. */
export const QUOTAS = {
  free: { coach: 15, pretest: 3, ideas: 2, recap: 1 },
  premium: { coach: 300, pretest: 60, ideas: 20, recap: 10 },
} as const;

export type AiFeature = keyof (typeof QUOTAS)["free"];
