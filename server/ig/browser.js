// Client Instagram réel : pilote un navigateur avec un profil persistant et appelle,
// depuis la page, les mêmes endpoints web que le site utilise lui-même.
import { chromium } from 'playwright';
import { config } from '../config.js';
import { IgError, loggedOut, rateLimited, checkpoint } from './errors.js';

const ORIGIN = 'https://www.instagram.com';
const APP_ID = '936619743392459'; // identifiant public de l'app web Instagram
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rand = (min, max) => min + Math.random() * (max - min);

async function launch(headless) {
  const ctx = await chromium.launchPersistentContext(config.profileDir, {
    headless,
    channel: config.browserChannel,
    viewport: { width: 1280, height: 850 },
  });
  const page = ctx.pages()[0] ?? (await ctx.newPage());
  return { ctx, page };
}

async function cookie(ctx, name) {
  const all = await ctx.cookies(ORIGIN);
  return all.find((c) => c.name === name)?.value ?? null;
}

async function call(ctx, page, path, method = 'GET', body = null) {
  const csrf = (await cookie(ctx, 'csrftoken')) ?? '';
  const res = await page.evaluate(
    async ({ path, method, body, csrf, appId }) => {
      const headers = { 'X-IG-App-ID': appId, 'X-CSRFToken': csrf, 'X-Requested-With': 'XMLHttpRequest' };
      if (method === 'POST') headers['Content-Type'] = 'application/x-www-form-urlencoded';
      const r = await fetch(path, { method, headers, body, credentials: 'include' });
      const text = await r.text();
      let json = null;
      try {
        json = JSON.parse(text);
      } catch {}
      return { status: r.status, json, snippet: json ? null : text.slice(0, 200) };
    },
    { path, method, body, csrf, appId: APP_ID },
  );
  const msg = res.json?.message ?? '';
  if (res.status === 429 || res.json?.spam || /feedback_required|wait a few minutes/i.test(msg)) {
    throw rateLimited(msg);
  }
  if (/checkpoint/i.test(msg) || res.json?.checkpoint_url) throw checkpoint();
  if (res.status === 401 || /login_required/i.test(msg) || res.json?.require_login || (res.status === 200 && !res.json)) {
    throw loggedOut();
  }
  if (res.status !== 200 || !res.json) {
    throw new IgError('HTTP', `Instagram a répondu ${res.status} sur ${path} ${msg || res.snippet || ''}`.trim());
  }
  return res.json;
}

const toUser = (u) => ({
  id: String(u.pk ?? u.pk_id ?? u.id),
  username: u.username,
  fullName: u.full_name ?? '',
  isPrivate: !!u.is_private,
  isVerified: !!u.is_verified,
});

/** Ouvre une fenêtre pour que l'utilisateur se connecte lui-même (mot de passe et 2FA ne passent jamais par l'app). */
export async function login(onProgress = () => {}) {
  const { ctx, page } = await launch(false);
  try {
    await page.goto(`${ORIGIN}/accounts/login/`, { waitUntil: 'domcontentloaded' });
    onProgress('Connecte-toi dans la fenêtre Instagram qui vient de s’ouvrir…');
    const deadline = Date.now() + 10 * 60_000;
    while (!(await cookie(ctx, 'sessionid'))) {
      if (Date.now() > deadline) throw new IgError('TIMEOUT', 'Connexion non finalisée dans le délai de 10 minutes.');
      if (page.isClosed()) throw new IgError('CLOSED', 'La fenêtre a été fermée avant la fin de la connexion.');
      await sleep(1500);
    }
    await sleep(4000); // laisse Instagram finir d'écrire ses cookies
    await page.goto(`${ORIGIN}/`, { waitUntil: 'domcontentloaded' });
    return await me(ctx, page);
  } finally {
    await ctx.close().catch(() => {});
  }
}

async function me(ctx, page) {
  const id = await cookie(ctx, 'ds_user_id');
  if (!id) throw loggedOut();
  const { user } = await call(ctx, page, `/api/v1/users/${id}/info/`);
  return {
    id,
    username: user.username,
    followerCount: user.follower_count,
    followingCount: user.following_count,
  };
}

export async function openSession() {
  const { ctx, page } = await launch(config.headless);
  try {
    await page.goto(`${ORIGIN}/`, { waitUntil: 'domcontentloaded' });
    if (!(await cookie(ctx, 'sessionid'))) throw loggedOut();
  } catch (e) {
    await ctx.close().catch(() => {});
    throw e;
  }
  let myId = null;
  return {
    async me() {
      const m = await me(ctx, page);
      myId = m.id;
      return m;
    },
    /** kind : 'followers' | 'following' */
    async list(kind, onProgress = () => {}) {
      myId ??= await cookie(ctx, 'ds_user_id');
      const seen = new Map();
      let maxId = null;
      for (let pageNo = 0; pageNo < 2000; pageNo++) {
        const qs = new URLSearchParams({ count: '50' });
        if (maxId) qs.set('max_id', maxId);
        const data = await call(ctx, page, `/api/v1/friendships/${myId}/${kind}/?${qs}`);
        for (const u of data.users ?? []) seen.set(String(u.pk ?? u.pk_id ?? u.id), toUser(u));
        onProgress(seen.size);
        if (!data.next_max_id || !(data.users ?? []).length) break;
        maxId = String(data.next_max_id);
        await sleep(rand(1500, 4000));
      }
      return [...seen.values()];
    },
    async relationship(userId) {
      const r = await call(ctx, page, `/api/v1/friendships/show/${userId}/`);
      return { following: !!r.following, followedBy: !!r.followed_by };
    },
    async unfollow(userId) {
      const r = await call(ctx, page, `/api/v1/friendships/destroy/${userId}/`, 'POST', `user_id=${userId}`);
      if (r.friendship_status?.following) throw new IgError('NOT_APPLIED', 'Instagram n’a pas appliqué l’unfollow.');
    },
    async close() {
      await ctx.close().catch(() => {});
    },
  };
}
