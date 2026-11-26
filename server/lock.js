// Un seul navigateur peut utiliser le profil à la fois : toutes les tâches Instagram passent par ce verrou.
let current = null;
let lastError = null;

export const busyState = () => (current ? { ...current } : null);
export const lastTaskError = () => lastError;

export async function runExclusive(name, fn) {
  if (current) {
    throw Object.assign(new Error(`Une tâche est déjà en cours (${current.name}).`), { code: 'BUSY' });
  }
  current = { name, progress: '', since: Date.now() };
  try {
    const out = await fn((p) => {
      if (current) current.progress = p;
    });
    if (lastError?.name === name) lastError = null;
    return out;
  } catch (e) {
    lastError = { name, message: e.message, code: e.code ?? null, at: Date.now() };
    throw e;
  } finally {
    current = null;
  }
}
