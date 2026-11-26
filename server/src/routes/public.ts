import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { userBySlug } from "../accounts.js";
import { config } from "../config.js";
import type { Db } from "../db.js";
import { loadUserData, overview, whatWorks } from "../insights.js";
import { renderMediaKit, renderNotFound } from "../web/mediaKit.js";
import { rateLimit } from "./rateLimit.js";

/** Pages publiques : media kits partagés aux marques, et formulaire de contact. */
export async function publicRoutes(app: FastifyInstance, { db }: { db: Db }) {
  app.get("/healthz", async () => ({ ok: true }));

  async function kit(slug: string) {
    const user = await userBySlug(db, slug);
    if (!user || !user.media_kit_public) return null;
    const data = await loadUserData(db, user.id);
    if (!data.connections.length) return null;
    return { user, overview: overview(data), works: whatWorks(data, 30) };
  }

  app.get<{ Params: { slug: string } }>("/@:slug", async (request, reply) => {
    const found = await kit(request.params.slug);
    reply.type("text/html; charset=utf-8").header("cache-control", "public, max-age=300");
    if (!found) return reply.status(404).send(renderNotFound());
    return renderMediaKit(found.user, found.overview, found.works, `${config.publicBaseUrl}/@${found.user.public_slug}`);
  });

  const Contact = z.object({
    brand: z.string().trim().min(1).max(120),
    email: z.email().max(200),
    budget: z.string().trim().max(80).optional(),
    message: z.string().trim().min(1).max(2000),
    website: z.string().max(0).optional(), // champ piège : rempli seulement par les robots
  });

  app.post<{ Params: { slug: string } }>("/@:slug/contact", async (request, reply) => {
    rateLimit(`contact:${request.ip}`, 5, 3_600_000);
    const found = await kit(request.params.slug);
    reply.type("text/html; charset=utf-8");
    if (!found) return reply.status(404).send(renderNotFound());
    const form = Contact.safeParse(request.body ?? {});
    if (!form.success) return reply.status(400).send(renderMediaKit(found.user, found.overview, found.works, ""));
    await db.query(
      "insert into brand_inquiries (user_id, brand, email, message, budget) values ($1, $2, $3, $4, $5)",
      [found.user.id, form.data.brand, form.data.email, form.data.message, form.data.budget || null],
    );
    return renderMediaKit(found.user, found.overview, found.works, "", true);
  });
}
