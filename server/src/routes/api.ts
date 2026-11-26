import Anthropic from "@anthropic-ai/sdk";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import {
  createUser,
  publicUser,
  quota,
  recordUsage,
  redeemReferral,
  userById,
  userForToken,
  weekStart,
  type UserRow,
} from "../accounts.js";
import * as ai from "../ai/index.js";
import type { AiFeature } from "../config.js";
import { config } from "../config.js";
import { connectorFor } from "../connectors/index.js";
import { randomToken } from "../crypto.js";
import type { Db } from "../db.js";
import { loadUserData, overview, whatWorks } from "../insights.js";
import { FORMATS, NETWORKS, NETWORK_LABELS, isNetwork } from "../networks.js";
import { saveConnection, syncConnection, syncUser } from "../sync.js";
import { rateLimit } from "./rateLimit.js";

declare module "fastify" {
  interface FastifyRequest {
    user: UserRow | null;
  }
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message);
  }
}

const me = (request: FastifyRequest): UserRow => {
  if (!request.user) throw new HttpError(401, "Session absente ou expirée.");
  return request.user;
};

export async function apiRoutes(app: FastifyInstance, { db }: { db: Db }) {
  app.decorateRequest("user", null);

  app.addHook("preHandler", async (request) => {
    const header = request.headers.authorization;
    if (header?.startsWith("Bearer ")) request.user = await userForToken(db, header.slice(7));
  });

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof HttpError) return reply.status(error.status).send({ error: error.message, ...error.extra });
    if (error instanceof z.ZodError) return reply.status(400).send({ error: "Requête invalide.", details: error.issues });
    if (error instanceof ai.AiRefusal) return reply.status(422).send({ error: error.message });
    if (error instanceof Anthropic.APIError) {
      app.log.error({ status: error.status, message: error.message }, "Erreur de l'API Claude");
      return reply.status(503).send({ error: "Le service IA est momentanément indisponible. Réessaie dans un instant." });
    }
    const status = (error as { statusCode?: number }).statusCode;
    if (status && status < 500) return reply.status(status).send({ error: (error as Error).message });
    app.log.error(error);
    return reply.status(500).send({ error: "Erreur inattendue." });
  });

  /** Statistiques prêtes pour les écrans et pour l'IA. */
  async function analytics(user: UserRow, days = 30) {
    const data = await loadUserData(db, user.id);
    if (!data.connections.length) throw new HttpError(409, "Connecte au moins un réseau pour commencer.");
    return { data, overview: overview(data), works: whatWorks(data, days) };
  }

  const aiInput = async (user: UserRow) => {
    const { overview: ov, works } = await analytics(user);
    return { profile: { profileType: user.profile_type, goal: user.goal, displayName: user.display_name }, overview: ov, works };
  };

  async function requireQuota(user: UserRow, feature: AiFeature) {
    const state = await quota(db, user, feature);
    if (state.remaining <= 0) {
      throw new HttpError(402, "Tu as atteint la limite gratuite de la semaine pour cette fonction.", { quota: state, upgrade: true });
    }
    return state;
  }

  // MARK: Compte

  app.post("/v1/auth/device", async (request, reply) => {
    rateLimit(`device:${request.ip}`, 20, 3_600_000);
    const { user, token } = await createUser(db);
    return reply.status(201).send({ token, user: publicUser(user, config.publicBaseUrl) });
  });

  app.get("/v1/me", async (request) => {
    const user = me(request);
    return { ...publicUser(user, config.publicBaseUrl), aiSource: ai.aiSource() };
  });

  const ProfilePatch = z.object({
    displayName: z.string().trim().max(60).nullable().optional(),
    profileType: z.enum(["creator", "business", "curious"]).optional(),
    goal: z.enum(["awareness", "engagement", "traffic", "sales"]).optional(),
    timezone: z.string().max(60).optional(),
    publicSlug: z.string().trim().toLowerCase().regex(/^[a-z0-9._-]{3,30}$/, "3 à 30 caractères : lettres, chiffres, point, tiret").nullable().optional(),
    mediaKitPublic: z.boolean().optional(),
  });

  app.patch("/v1/me", async (request) => {
    const user = me(request);
    const patch = ProfilePatch.parse(request.body ?? {});
    if (patch.timezone) {
      try {
        new Intl.DateTimeFormat("fr-FR", { timeZone: patch.timezone });
      } catch {
        throw new HttpError(400, "Fuseau horaire inconnu.");
      }
    }
    if (patch.mediaKitPublic && !(patch.publicSlug ?? user.public_slug)) {
      throw new HttpError(400, "Choisis d'abord l'adresse de ton media kit.");
    }
    const columns: Record<string, unknown> = {
      display_name: patch.displayName,
      profile_type: patch.profileType,
      goal: patch.goal,
      timezone: patch.timezone,
      public_slug: patch.publicSlug,
      media_kit_public: patch.mediaKitPublic,
    };
    const entries = Object.entries(columns).filter(([, value]) => value !== undefined);
    if (entries.length) {
      try {
        await db.query(
          `update users set ${entries.map(([column], i) => `${column} = $${i + 2}`).join(", ")} where id = $1`,
          [user.id, ...entries.map(([, value]) => value)],
        );
      } catch (error) {
        if (String(error).includes("users_public_slug_key")) throw new HttpError(409, "Cette adresse de media kit est déjà prise.");
        throw error;
      }
    }
    const updated = await userById(db, user.id);
    return publicUser(updated!, config.publicBaseUrl);
  });

  /** Suppression du compte et de toutes ses données (RGPD). */
  app.delete("/v1/me", async (request, reply) => {
    await db.query("delete from users where id = $1", [me(request).id]);
    return reply.status(204).send();
  });

  // MARK: Réseaux

  app.get("/v1/networks", async (request) => {
    const user = me(request);
    const rows = await db.query<{ id: string; network: string; mode: string; handle: string; last_synced_at: Date | null; last_error: string | null }>(
      "select id, network, mode, handle, last_synced_at, last_error from connections where user_id = $1",
      [user.id],
    );
    return NETWORKS.map((network) => {
      const connector = connectorFor(network);
      const row = rows.find((r) => r.network === network);
      return {
        network,
        label: NETWORK_LABELS[network],
        available: connector !== null,
        mode: connector?.mode ?? null,
        connection: row
          ? { id: row.id, handle: row.handle, mode: row.mode, lastSyncedAt: row.last_synced_at ? new Date(row.last_synced_at).toISOString() : null, lastError: row.last_error }
          : null,
      };
    });
  });

  app.post<{ Params: { network: string } }>("/v1/connections/:network", async (request) => {
    const user = me(request);
    const { network } = request.params;
    if (!isNetwork(network)) throw new HttpError(404, "Réseau inconnu.");
    const connector = connectorFor(network);
    if (!connector) throw new HttpError(409, `${NETWORK_LABELS[network]} n'est pas encore disponible.`);
    if (connector.mode === "demo") {
      const connection = await saveConnection(db, user.id, network, "demo", connector.demoProfile(user.id.slice(0, 8)), null);
      const result = await syncConnection(db, connection);
      return { status: "connected", connectionId: connection.id, mode: "demo", syncError: result.error ?? null };
    }
    const state = randomToken(24);
    await db.query("insert into oauth_states (state, user_id, network) values ($1, $2, $3)", [state, user.id, network]);
    return { status: "authorize", url: connector.authorizeUrl(state), callbackScheme: config.appScheme };
  });

  app.delete<{ Params: { id: string } }>("/v1/connections/:id", async (request, reply) => {
    const user = me(request);
    if (!z.uuid().safeParse(request.params.id).success) throw new HttpError(404, "Connexion inconnue.");
    await db.query("delete from connections where id = $1 and user_id = $2", [request.params.id, user.id]);
    return reply.status(204).send();
  });

  /** Retour d'OAuth : le réseau renvoie ici, puis on rend la main à l'app par son schéma d'URL. */
  app.get<{ Params: { network: string }; Querystring: { code?: string; state?: string; error?: string } }>(
    "/oauth/:network/callback",
    async (request, reply) => {
      const back = (status: string, message = "") =>
        reply.redirect(`${config.appScheme}://connected?network=${encodeURIComponent(request.params.network)}&status=${status}&message=${encodeURIComponent(message)}`);
      const { network } = request.params;
      const { code, state, error } = request.query;
      if (!isNetwork(network) || !state) return back("error", "Requête de connexion invalide.");
      const [row] = await db.query<{ user_id: string }>(
        "delete from oauth_states where state = $1 and network = $2 and created_at > now() - interval '15 minutes' returning user_id",
        [state, network],
      );
      if (!row) return back("error", "La connexion a expiré, recommence.");
      if (error || !code) return back("cancelled", "Connexion annulée.");
      const connector = connectorFor(network);
      if (!connector || connector.mode !== "official") return back("error", "Réseau indisponible.");
      try {
        const { credentials, profile } = await connector.exchangeCode(code);
        const connection = await saveConnection(db, row.user_id, network, "official", profile, credentials);
        await syncConnection(db, connection);
        return back("ok");
      } catch (err) {
        app.log.error(err, "Échec de la connexion OAuth");
        return back("error", "Le réseau a refusé la connexion.");
      }
    },
  );

  app.post("/v1/sync", async (request) => {
    const user = me(request);
    await syncUser(db, user.id);
    return overview(await loadUserData(db, user.id));
  });

  // MARK: Analyses

  app.get("/v1/overview", async (request) => {
    const user = me(request);
    return overview(await loadUserData(db, user.id));
  });

  app.get<{ Querystring: { days?: string } }>("/v1/what-works", async (request) => {
    const user = me(request);
    const days = [7, 30, 90].includes(Number(request.query.days)) ? Number(request.query.days) : 30;
    return whatWorks(await loadUserData(db, user.id), days);
  });

  // MARK: IA

  app.get<{ Querystring: { refresh?: string } }>("/v1/recap", async (request) => {
    const user = me(request);
    const week = weekStart();
    if (request.query.refresh !== "1") {
      const [stored] = await db.query<{ payload: unknown; source: string; created_at: Date }>(
        "select payload, source, created_at from recaps where user_id = $1 and week_start = $2",
        [user.id, week],
      );
      if (stored) return { week, source: stored.source, createdAt: new Date(stored.created_at).toISOString(), ...(stored.payload as object) };
    }
    await requireQuota(user, "recap");
    const recap = await ai.recap(await aiInput(user));
    await recordUsage(db, user, "recap");
    const [saved] = await db.query<{ created_at: Date }>(
      `insert into recaps (user_id, week_start, payload, source) values ($1, $2, $3, $4)
       on conflict (user_id, week_start) do update set payload = excluded.payload, source = excluded.source, created_at = now()
       returning created_at`,
      [user.id, week, JSON.stringify(recap), ai.aiSource()],
    );
    return { week, source: ai.aiSource(), createdAt: new Date(saved!.created_at).toISOString(), ...recap };
  });

  app.post("/v1/ideas", async (request) => {
    const user = me(request);
    const { request: wish } = z.object({ request: z.string().max(500).nullish() }).parse(request.body ?? {});
    const state = await requireQuota(user, "ideas");
    const result = await ai.ideas(await aiInput(user), wish ?? null);
    await recordUsage(db, user, "ideas");
    return { source: ai.aiSource(), quota: { ...state, used: state.used + 1, remaining: state.remaining - 1 }, ...result };
  });

  const PretestBody = z.object({
    caption: z.string().max(2200),
    network: z.enum(NETWORKS).nullish(),
    format: z.enum(FORMATS).nullish(),
    image: z.object({ mediaType: z.enum(["image/jpeg", "image/png", "image/webp", "image/gif"]), data: z.base64().max(7_000_000) }).nullish(),
  });

  app.post("/v1/pretest", { bodyLimit: 8 * 1024 * 1024 }, async (request) => {
    const user = me(request);
    const body = PretestBody.parse(request.body ?? {});
    if (!body.caption.trim() && !body.image) throw new HttpError(400, "Ajoute une légende ou un visuel à tester.");
    const state = await requireQuota(user, "pretest");
    const result = await ai.pretest(await aiInput(user), {
      caption: body.caption,
      network: body.network ?? null,
      format: body.format ?? null,
      image: body.image ?? undefined,
    });
    await recordUsage(db, user, "pretest");
    return { source: ai.aiSource(), quota: { ...state, used: state.used + 1, remaining: state.remaining - 1 }, ...result };
  });

  app.get("/v1/coach", async (request) => {
    const user = me(request);
    const rows = await db.query<{ id: string; role: string; content: string; created_at: Date }>(
      "select id, role, content, created_at from (select * from coach_messages where user_id = $1 order by id desc limit 50) m order by id",
      [user.id],
    );
    return { messages: rows.map((r) => ({ id: String(r.id), role: r.role, content: r.content, createdAt: new Date(r.created_at).toISOString() })), quota: await quota(db, user, "coach") };
  });

  /** Coach en flux (Server-Sent Events) : `delta`, `reset` (un autre modèle reprend), puis `done` ou `error`. */
  app.post("/v1/coach", async (request, reply: FastifyReply) => {
    const user = me(request);
    const { message } = z.object({ message: z.string().trim().min(1).max(2000) }).parse(request.body ?? {});
    await requireQuota(user, "coach");
    const input = await aiInput(user);
    const history = (
      await db.query<{ role: "user" | "assistant"; content: string }>(
        "select role, content from (select * from coach_messages where user_id = $1 order by id desc limit 20) m order by id",
        [user.id],
      )
    ).filter((m, i, all) => !(i === 0 && m.role === "assistant") && !(i === all.length - 1 && m.role === "user"));

    reply.hijack();
    reply.raw.writeHead(200, { "content-type": "text/event-stream; charset=utf-8", "cache-control": "no-cache", connection: "keep-alive" });
    const send = (payload: object) => reply.raw.write(`data: ${JSON.stringify(payload)}\n\n`);
    try {
      const stream = ai.coach(input, history, message);
      let step = await stream.next();
      while (!step.done) {
        send(step.value.kind === "delta" ? { type: "delta", text: step.value.text } : { type: "reset" });
        step = await stream.next();
      }
      await db.query("insert into coach_messages (user_id, role, content) values ($1, 'user', $2), ($1, 'assistant', $3)", [user.id, message, step.value]);
      await recordUsage(db, user, "coach");
      send({ type: "done", source: ai.aiSource() });
    } catch (error) {
      app.log.error(error, "Échec du coach");
      send({ type: "error", error: error instanceof ai.AiRefusal ? error.message : "Le coach n'a pas pu répondre. Réessaie dans un instant." });
    }
    reply.raw.end();
  });

  // MARK: Viralité et marques

  app.get("/v1/media-kit", async (request) => {
    const user = me(request);
    const inquiries = await db.query<{ count: number }>("select count(*)::int as count from brand_inquiries where user_id = $1 and status = 'new'", [user.id]);
    return {
      slug: user.public_slug,
      public: user.media_kit_public,
      url: user.public_slug ? `${config.publicBaseUrl}/@${user.public_slug}` : null,
      newInquiries: inquiries[0]?.count ?? 0,
    };
  });

  app.get("/v1/inquiries", async (request) => {
    const user = me(request);
    const rows = await db.query<{ id: string; brand: string; email: string; message: string; budget: string | null; status: string; created_at: Date }>(
      "select id, brand, email, message, budget, status, created_at from brand_inquiries where user_id = $1 order by created_at desc limit 100",
      [user.id],
    );
    await db.query("update brand_inquiries set status = 'read' where user_id = $1 and status = 'new'", [user.id]);
    return rows.map((r) => ({ ...r, createdAt: new Date(r.created_at).toISOString(), created_at: undefined }));
  });

  app.post("/v1/referral", async (request) => {
    const user = me(request);
    const { code } = z.object({ code: z.string().trim().min(4).max(12) }).parse(request.body ?? {});
    const result = await redeemReferral(db, user, code);
    const messages = {
      ok: "Parrainage validé : un mois de Premium offert, pour toi et ton parrain.",
      unknown: "Ce code n'existe pas.",
      self: "Tu ne peux pas utiliser ton propre code.",
      already: "Tu as déjà utilisé un code de parrainage.",
    };
    if (result !== "ok") throw new HttpError(result === "unknown" ? 404 : 409, messages[result]);
    return { message: messages.ok, user: publicUser((await userById(db, user.id))!, config.publicBaseUrl) };
  });
}
