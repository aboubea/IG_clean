import assert from "node:assert/strict";
import test from "node:test";
import { generateDemo } from "../src/connectors/demo.js";
import { localWeekdayHour, overview, slotIndex, whatWorks, type PostRow, type UserData } from "../src/insights.js";
import type { Network } from "../src/networks.js";

const NOW = new Date("2026-11-26T10:00:00Z");

function demoData(networks: Network[]): UserData {
  const data: UserData = { connections: [], daily: [], posts: [], timezone: "Europe/Paris", now: NOW };
  for (const network of networks) {
    const id = `c-${network}`;
    const payload = generateDemo(network, { externalId: `ext-${network}`, handle: network, displayName: network }, NOW);
    data.connections.push({ id, network, mode: "demo", handle: network, display_name: null, status: "active", last_synced_at: NOW, last_error: null });
    data.daily.push(...payload.daily.map((d) => ({ connection_id: id, day: d.day, followers: d.followers })));
    data.posts.push(
      ...payload.posts.map((p, i): PostRow => ({
        id: `${id}-${i}`, connection_id: id, format: p.format, caption: p.caption, permalink: null,
        published_at: new Date(p.publishedAt), views: p.views ?? null, reach: p.reach ?? null,
        likes: p.likes, comments: p.comments, shares: p.shares, saves: p.saves,
      })),
    );
  }
  return data;
}

test("la démo est déterministe", () => {
  const a = generateDemo("tiktok", { externalId: "x", handle: "x", displayName: "x" }, NOW);
  const b = generateDemo("tiktok", { externalId: "x", handle: "x", displayName: "x" }, NOW);
  assert.deepEqual(a, b);
  assert.equal(a.daily.length, 120);
  assert.ok(a.posts.length > 40);
});

test("vue d'ensemble : audience totale, réseaux triés, TikTok moteur de croissance", () => {
  const ov = overview(demoData(["instagram", "tiktok", "facebook"]));
  assert.equal(ov.networks.length, 3);
  assert.equal(ov.totalAudience, ov.networks.reduce((s, n) => s + n.followers, 0));
  assert.deepEqual(ov.networks.map((n) => n.network), ["tiktok", "instagram", "facebook"]);
  assert.equal(ov.growthDriver?.network, "tiktok");
  assert.ok(ov.change30d > 0);
  assert.ok(ov.networks.find((n) => n.network === "facebook")!.change30d < 0, "Facebook décline");
  assert.equal(ov.series.length, 30);
  assert.ok(ov.series.at(-1)!.total > ov.series[0]!.total);
});

test("ce qui marche : vidéo courte en tête, créneau du soir détecté", () => {
  const works = whatWorks(demoData(["instagram", "tiktok", "facebook"]), 90);
  assert.equal(works.formats[0]?.format, "short_video");
  assert.equal(works.heat.length, 7);
  assert.ok(works.heat.every((row) => row.length === 6));
  assert.ok(works.bestSlot, "un meilleur créneau doit être trouvé");
  assert.match(works.bestSlot!.label, /18 h-21 h/);
  assert.equal(works.topPosts.length, 5);
  assert.ok(works.topPosts[0]!.engagementRate >= works.topPosts[4]!.engagementRate);
});

test("heure locale de Paris et créneaux", () => {
  assert.deepEqual(localWeekdayHour(new Date("2026-11-26T18:30:00Z"), "Europe/Paris"), { weekday: 3, hour: 19 }); // jeudi 19 h
  assert.deepEqual(localWeekdayHour(new Date("2026-07-06T22:30:00Z"), "Europe/Paris"), { weekday: 1, hour: 0 }); // heure d'été
  assert.equal(slotIndex(19), 4);
  assert.equal(slotIndex(2), 5);
});

test("paliers : franchissement d'un seuil d'abonnés dans la semaine", () => {
  const data: UserData = {
    connections: [{ id: "c", network: "instagram", mode: "demo", handle: "x", display_name: null, status: "active", last_synced_at: NOW, last_error: null }],
    daily: [
      { connection_id: "c", day: "2026-11-15", followers: 9_900 },
      { connection_id: "c", day: "2026-11-22", followers: 9_990 },
      { connection_id: "c", day: "2026-11-24", followers: 10_020 },
    ],
    posts: [],
    timezone: "Europe/Paris",
    now: NOW,
  };
  const found = overview(data).milestones;
  assert.equal(found[0]?.value, 10_000);
  assert.match(found[0]!.label, /10\s000 abonnés sur Instagram/);
});
