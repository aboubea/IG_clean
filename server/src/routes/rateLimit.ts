/** Limiteur simple en mémoire, par clé (adresse IP + action). Suffisant pour une seule instance. */
const hits = new Map<string, number[]>();

export function rateLimit(key: string, max: number, windowMs: number): void {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < windowMs);
  if (recent.length >= max) {
    throw Object.assign(new Error("Trop de tentatives, réessaie plus tard."), { statusCode: 429 });
  }
  recent.push(now);
  hits.set(key, recent);
  if (hits.size > 50_000) hits.clear();
}
