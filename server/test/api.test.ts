import assert from "node:assert/strict";
import { after, before, test } from "node:test";

process.env.PULSE_AI = "demo";
process.env.PULSE_DEMO_CONNECTORS = "1";
const { buildApp } = await import("../src/app.js");
const { migrate, openDb } = await import("../src/db.js");

const db = await openDb("memory://");
await migrate(db);
const app = await buildApp(db, { logger: false });

before(() => app.ready());
after(async () => {
  await app.close();
  await db.close();
});

async function call(method: string, url: string, token?: string, payload?: unknown) {
  const response = await app.inject({
    method: method as "GET",
    url,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    payload: payload as object | undefined,
  });
  let body: any = response.body;
  try {
    body = JSON.parse(response.body);
  } catch {}
  return { status: response.statusCode, body, raw: response.body };
}

async function newUser() {
  const res = await call("POST", "/v1/auth/device");
  assert.equal(res.status, 201);
  return res.body as { token: string; user: { id: string; referralCode: string } };
}

test("parcours complet en mode démo", async (t) => {
  const { token, user } = await newUser();

  await t.test("sans session : 401", async () => {
    assert.equal((await call("GET", "/v1/overview")).status, 401);
  });

  await t.test("IA indisponible tant qu'aucun réseau n'est connecté", async () => {
    const res = await call("GET", "/v1/recap", token);
    assert.equal(res.status, 409);
  });

  await t.test("connexion de trois réseaux", async () => {
    for (const network of ["instagram", "tiktok", "facebook"]) {
      const res = await call("POST", `/v1/connections/${network}`, token);
      assert.equal(res.status, 200, res.raw);
      assert.equal(res.body.status, "connected");
    }
    const networks = (await call("GET", "/v1/networks", token)).body;
    assert.equal(networks.filter((n: any) => n.connection).length, 3);
    assert.equal(networks.find((n: any) => n.network === "linkedin").connection, null);
  });

  await t.test("vue d'ensemble et ce qui marche", async () => {
    const ov = (await call("GET", "/v1/overview", token)).body;
    assert.ok(ov.totalAudience > 40_000, `audience ${ov.totalAudience}`);
    assert.equal(ov.growthDriver.network, "tiktok");
    const works = (await call("GET", "/v1/what-works?days=90", token)).body;
    assert.equal(works.days, 90);
    assert.ok(works.formats.length >= 3);
    assert.ok(works.bestSlot);
  });

  await t.test("bilan : généré une fois par semaine, puis servi depuis la base", async () => {
    const first = await call("GET", "/v1/recap", token);
    assert.equal(first.status, 200, first.raw);
    assert.equal(first.body.actions.length, 3);
    assert.equal(first.body.source, "demo");
    const again = await call("GET", "/v1/recap", token);
    assert.equal(again.body.createdAt, first.body.createdAt);
    const refresh = await call("GET", "/v1/recap?refresh=1", token);
    assert.equal(refresh.status, 402, "limite gratuite : 1 bilan par semaine");
    assert.equal(refresh.body.upgrade, true);
  });

  await t.test("idées de contenus", async () => {
    const res = await call("POST", "/v1/ideas", token, { request: "des idées pour les fêtes" });
    assert.equal(res.status, 200, res.raw);
    assert.equal(res.body.ideas.length, 5);
    assert.equal(res.body.quota.remaining, 1);
  });

  await t.test("pré-test : 3 gratuits par semaine", async () => {
    for (let i = 0; i < 3; i++) {
      const res = await call("POST", "/v1/pretest", token, { caption: "Ma routine du matin en 30 secondes, et toi ?", format: "short_video" });
      assert.equal(res.status, 200, res.raw);
      assert.ok(res.body.score >= 0 && res.body.score <= 100);
      assert.ok(res.body.improvedCaption.length > 0);
    }
    assert.equal((await call("POST", "/v1/pretest", token, { caption: "encore" })).status, 402);
    assert.equal((await call("POST", "/v1/pretest", token, { caption: "x", image: { mediaType: "image/png", data: "pas du base64 !" } })).status, 400);
  });

  await t.test("coach en flux, puis historique", async () => {
    const res = await call("POST", "/v1/coach", token, { message: "Quand est-ce que je devrais publier ?" });
    assert.equal(res.status, 200);
    const events = res.raw.split("\n\n").filter(Boolean).map((line) => JSON.parse(line.replace(/^data: /, "")));
    assert.ok(events.some((e) => e.type === "delta"));
    assert.equal(events.at(-1).type, "done");
    const history = (await call("GET", "/v1/coach", token)).body;
    assert.deepEqual(history.messages.map((m: any) => m.role), ["user", "assistant"]);
    assert.match(history.messages[1].content, /créneau/);
  });

  await t.test("media kit public, échappement HTML et formulaire des marques", async () => {
    assert.equal((await call("PATCH", "/v1/me", token, { mediaKitPublic: true })).status, 400, "adresse requise d'abord");
    const patch = await call("PATCH", "/v1/me", token, { displayName: "Léa <script>alert(1)</script>", publicSlug: "Lea.Test", mediaKitPublic: true, profileType: "creator" });
    assert.equal(patch.status, 200, patch.raw);
    assert.equal(patch.body.publicSlug, "lea.test");
    const page = await call("GET", "/@lea.test");
    assert.equal(page.status, 200);
    assert.match(page.raw, /Media kit/);
    assert.ok(!page.raw.includes("<script>alert"), "le nom doit être échappé");
    assert.match(page.raw, /og:description/);
    const form = await app.inject({
      method: "POST",
      url: "/@lea.test/contact",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      payload: "brand=Maison+Test&email=contact%40maison.test&message=Collaboration+pour+Noel&budget=500+euros",
    });
    assert.match(form.body, /Message envoyé/);
    const inquiries = (await call("GET", "/v1/inquiries", token)).body;
    assert.equal(inquiries.length, 1);
    assert.equal(inquiries[0].brand, "Maison Test");
    assert.equal((await call("GET", "/@personne")).status, 404);
  });

  await t.test("parrainage : un mois offert aux deux, une seule fois", async () => {
    const friend = await newUser();
    const res = await call("POST", "/v1/referral", friend.token, { code: user.referralCode });
    assert.equal(res.status, 200, res.raw);
    assert.equal(res.body.user.premium, true);
    assert.equal((await call("GET", "/v1/me", token)).body.premium, true);
    assert.equal((await call("POST", "/v1/referral", friend.token, { code: user.referralCode })).status, 409);
    assert.equal((await call("POST", "/v1/referral", token, { code: user.referralCode })).status, 409);
    assert.equal((await call("POST", "/v1/referral", token, { code: "ZZZZZZ" })).status, 404);
  });

  await t.test("isolation : on ne supprime pas la connexion d'un autre", async () => {
    const other = await newUser();
    const mine = (await call("GET", "/v1/networks", token)).body.find((n: any) => n.network === "tiktok").connection;
    assert.equal((await call("DELETE", `/v1/connections/${mine.id}`, other.token)).status, 204);
    assert.ok((await call("GET", "/v1/networks", token)).body.find((n: any) => n.network === "tiktok").connection, "toujours là");
  });

  await t.test("suppression du compte (RGPD)", async () => {
    assert.equal((await call("DELETE", "/v1/me", token)).status, 204);
    assert.equal((await call("GET", "/v1/me", token)).status, 401);
    assert.equal((await call("GET", "/@lea.test")).status, 404);
  });
});
