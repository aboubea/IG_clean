// Faux Instagram pour la démo et les tests : aucune requête réseau, les listes bougent un peu à chaque scan.
const NAMES = ['lea', 'hugo', 'ines', 'noah', 'jade', 'liam', 'emma', 'adam', 'lina', 'paul', 'zoe', 'tom', 'mila', 'leo', 'nina', 'sam'];
const TAGS = ['photo', 'travel', 'art', 'fit', 'food', 'music', 'dev', 'surf', 'ski', 'run'];
const all = Array.from({ length: 420 }, (_, i) => ({
  id: String(1000 + i),
  username: `${NAMES[i % NAMES.length]}.${TAGS[(i * 7) % TAGS.length]}${i}`,
  fullName: `${NAMES[i % NAMES.length][0].toUpperCase()}${NAMES[i % NAMES.length].slice(1)} ${String.fromCharCode(65 + (i % 26))}.`,
  isPrivate: i % 5 === 0,
  isVerified: i % 37 === 0,
}));
const pick = (p) => new Set(all.filter(() => Math.random() < p).map((u) => u.id));
const state = { followers: pick(0.6), following: pick(0.5) };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function drift(set) {
  const ids = [...set];
  for (let i = 0; i < Math.floor(Math.random() * 4); i++) set.delete(ids[Math.floor(Math.random() * ids.length)]);
  for (let i = 0; i < Math.floor(Math.random() * 4); i++) set.add(all[Math.floor(Math.random() * all.length)].id);
}

export async function login(onProgress = () => {}) {
  onProgress('Connexion (démo)…');
  await sleep(800);
  return { id: '1', username: 'compte.demo', followerCount: state.followers.size, followingCount: state.following.size };
}

export async function openSession() {
  return {
    async me() {
      drift(state.followers);
      drift(state.following);
      return { id: '1', username: 'compte.demo', followerCount: state.followers.size, followingCount: state.following.size };
    },
    async list(kind, onProgress = () => {}) {
      await sleep(400);
      const out = all.filter((u) => state[kind].has(u.id));
      onProgress(out.length);
      return out;
    },
    async relationship(userId) {
      return { following: state.following.has(userId), followedBy: state.followers.has(userId) };
    },
    async unfollow(userId) {
      await sleep(200);
      state.following.delete(userId);
    },
    async close() {},
  };
}
