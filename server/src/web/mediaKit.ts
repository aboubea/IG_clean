import type { UserRow } from "../accounts.js";
import type { Overview, WhatWorks } from "../insights.js";
import { NETWORK_LABELS } from "../networks.js";

const escape = (value: string) =>
  value.replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!);

const fmt = (n: number) => n.toLocaleString("fr-FR");

function compact(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toLocaleString("fr-FR", { maximumFractionDigits: 1 })}\u00a0M`;
  if (n >= 10_000) return `${Math.round(n / 1000)}\u00a0k`;
  return fmt(n);
}

const STYLE = `
:root{--bg:#0d0d10;--card:#18181d;--line:#26262e;--text:#f4f4f6;--muted:#9a9aa6;--lime:#c6f432;--coral:#ff7a6b}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--bg);color:var(--text);font:16px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif;padding:28px 16px 48px}
main{max-width:640px;margin:0 auto}
.k{font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);font-weight:600}
h1{font-size:28px;font-weight:800;letter-spacing:-.02em;margin-top:4px}
.big{font-size:56px;font-weight:800;letter-spacing:-.04em;line-height:1;margin-top:18px}
.chip{display:inline-block;margin-top:10px;padding:5px 11px;border-radius:99px;background:#1f2a08;color:var(--lime);font-size:13px;font-weight:600}
.card{background:var(--card);border-radius:20px;padding:16px 18px;margin-top:14px}
.row{display:flex;align-items:center;gap:12px;padding:10px 0;border-bottom:1px solid var(--line)}
.row:last-child{border:0}
.row b{font-size:16px}.row small{display:block;color:var(--muted);font-size:13px}
.right{margin-left:auto;text-align:right;white-space:nowrap}
.good{color:var(--lime)}.bad{color:var(--coral)}
.post{padding:10px 0;border-bottom:1px solid var(--line)}.post:last-child{border:0}
label{display:block;font-size:13px;color:var(--muted);margin-top:12px}
input,textarea{width:100%;margin-top:4px;padding:11px 12px;border-radius:12px;border:1px solid var(--line);background:var(--bg);color:var(--text);font:inherit}
button{margin-top:16px;width:100%;padding:15px;border:0;border-radius:16px;background:var(--lime);color:var(--bg);font:inherit;font-weight:800;cursor:pointer}
a{color:var(--lime)}
.hp{position:absolute;left:-9999px}
footer{margin-top:28px;text-align:center;color:var(--muted);font-size:13px}`;

function page(title: string, description: string, body: string, url: string): string {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape(title)}</title><meta name="description" content="${escape(description)}">
<meta property="og:title" content="${escape(title)}"><meta property="og:description" content="${escape(description)}">
<meta property="og:url" content="${escape(url)}"><meta property="og:type" content="profile"><meta name="twitter:card" content="summary">
<style>${STYLE}</style></head><body><main>${body}
<footer>Statistiques relevées par <a href="/">Pulse</a> auprès des réseaux, mises à jour chaque nuit.</footer></main></body></html>`;
}

/** Media kit public : la carte de visite chiffrée qu'un créateur envoie aux marques. */
export function renderMediaKit(user: UserRow, overview: Overview, works: WhatWorks, url: string, sent = false): string {
  const name = user.display_name || `@${user.public_slug}`;
  const engagement = works.networks.length
    ? Math.round((works.networks.reduce((sum, n) => sum + n.engagementRate * n.posts, 0) / Math.max(1, works.postCount)) * 10) / 10
    : 0;
  const description = `${fmt(overview.totalAudience)} abonnés sur ${overview.networks.length} réseau${overview.networks.length > 1 ? "x" : ""} · ${engagement.toLocaleString("fr-FR")}\u00a0% d'engagement`;
  const networks = overview.networks
    .map(
      (n) => `<div class="row"><div><b>${compact(n.followers)}</b><small>${escape(n.label)} · @${escape(n.handle)}</small></div>
      <div class="right"><b class="${n.change30d >= 0 ? "good" : "bad"}">${n.change30dPct >= 0 ? "+" : ""}${n.change30dPct.toLocaleString("fr-FR")}\u00a0%</b><small>${n.engagementRate.toLocaleString("fr-FR")}\u00a0% d'engagement</small></div></div>`,
    )
    .join("");
  const posts = works.topPosts
    .slice(0, 3)
    .map(
      (p) => `<div class="post"><b>${escape(p.caption)}</b><small style="display:block;color:var(--muted)">${escape(NETWORK_LABELS[p.network])} · ${escape(p.formatLabel)} · ${p.engagementRate.toLocaleString("fr-FR")}\u00a0% d'engagement${p.views ? ` · ${compact(p.views)}\u00a0vues` : ""}</small></div>`,
    )
    .join("");
  const contact = sent
    ? `<div class="card"><b class="good">Message envoyé ✓</b><p style="color:var(--muted);margin-top:6px">${escape(name)} le recevra dans l'app Pulse.</p></div>`
    : `<form class="card" method="post" action="/@${escape(user.public_slug ?? "")}/contact">
      <div class="k">Proposer une collaboration</div>
      <label>Marque<input name="brand" required maxlength="120"></label>
      <label>E-mail professionnel<input name="email" type="email" required maxlength="200"></label>
      <label>Budget indicatif (facultatif)<input name="budget" maxlength="80"></label>
      <label>Votre proposition<textarea name="message" rows="4" required maxlength="2000"></textarea></label>
      <input class="hp" name="website" tabindex="-1" autocomplete="off" aria-hidden="true">
      <button type="submit">Envoyer</button></form>`;

  const body = `<div class="k">Media kit</div><h1>${escape(name)}</h1>
  <div class="big">${fmt(overview.totalAudience)}</div><div class="k" style="margin-top:6px">abonnés au total</div>
  ${overview.change30d > 0 ? `<span class="chip">▲ ${fmt(overview.change30d)} sur 30 jours</span>` : ""}
  <div class="card">${networks}</div>
  ${posts ? `<div class="card"><div class="k">Contenus qui performent</div>${posts}</div>` : ""}
  ${works.bestSlot ? `<div class="card"><div class="k">Audience la plus active</div><b>${escape(works.bestSlot.label)}</b></div>` : ""}
  ${contact}`;
  return page(`${name} · Media kit Pulse`, description, body, url);
}

export function renderNotFound(): string {
  return page("Media kit introuvable · Pulse", "Ce media kit n'existe pas ou n'est pas public.", `<h1>Media kit introuvable</h1><p style="color:var(--muted);margin-top:8px">Ce media kit n'existe pas, ou son propriétaire ne l'a pas rendu public.</p>`, "");
}
