import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from './api.js';

const TABS = [
  ['dashboard', 'Tableau de bord'],
  ['clean', 'Nettoyage'],
  ['lists', 'Listes'],
  ['history', 'Historique'],
  ['settings', 'Réglages'],
];
const EVENT_LABELS = {
  follower_gained: ['Nouvel abonné', 'good'],
  follower_lost: ['Ne te suit plus', 'bad'],
  following_added: ['Tu le suis', 'neutral'],
  following_removed: ['Tu ne le suis plus', 'neutral'],
};
const LIST_LABELS = {
  non_followers: 'Ne me suivent pas en retour',
  fans: 'Me suivent, je ne les suis pas',
  mutuals: 'Abonnements mutuels',
  followers: 'Tous mes abonnés',
  following: 'Tous mes abonnements',
};
const TASK_LABELS = { login: 'Connexion', snapshot: 'Scan', unfollow: 'Unfollow' };
const MAX_ROWS = 500;

const fmt = (ts) =>
  ts ? new Date(ts).toLocaleString('fr-FR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '—';

function usePolling(path, intervalMs, deps = []) {
  const [data, setData] = useState(null);
  const refresh = useCallback(() => api.get(path).then(setData).catch(() => {}), [path]);
  useEffect(() => {
    refresh();
    const id = setInterval(refresh, intervalMs);
    return () => clearInterval(id);
  }, [refresh, intervalMs, ...deps]);
  return [data, refresh];
}

export default function App() {
  const [tab, setTab] = useState('dashboard');
  const [status, refreshStatus] = usePolling('/status', 2500);
  const [notice, setNotice] = useState(null);

  const act = async (fn) => {
    try {
      setNotice(null);
      await fn();
    } catch (e) {
      setNotice(e.message);
    }
    refreshStatus();
  };

  if (!status) return <p className="loading">Chargement…</p>;
  const { account, busy, lastError } = status;
  // Sert à recharger les listes dès qu'une tâche se termine ou que la file avance.
  const dataKey = `${status.lastSnapshot?.id}-${status.runner.queue}-${status.runner.doneDay}-${busy?.name}`;

  return (
    <div className="app">
      <header>
        <div>
          <h1>IG Clean {status.mock && <span className="tag">démo</span>}</h1>
          <p className="muted">
            {account ? <>Connecté : <strong>@{account.username}</strong></> : 'Aucun compte connecté'}
            {' · '}Dernier scan : {fmt(status.lastGoodSnapshot?.at)}
          </p>
        </div>
        <div className="actions">
          <button className="secondary" disabled={!!busy} onClick={() => act(() => api.post('/login'))}>
            {account ? 'Reconnecter' : 'Se connecter à Instagram'}
          </button>
          <button disabled={!!busy || !account} onClick={() => act(() => api.post('/snapshot'))}>
            Scanner maintenant
          </button>
        </div>
      </header>

      {busy && (
        <div className="banner info">
          <span className="spinner" /> <strong>{TASK_LABELS[busy.name] ?? busy.name} en cours.</strong> {busy.progress}
        </div>
      )}
      {!busy && lastError && (
        <div className="banner error">
          <strong>{TASK_LABELS[lastError.name] ?? lastError.name} a échoué ({fmt(lastError.at)}).</strong> {lastError.message}
        </div>
      )}
      {!busy && status.lastSnapshot?.status === 'incomplete' && (
        <div className="banner warn">
          Le dernier scan est incomplet ({status.lastSnapshot.followers}/{status.lastSnapshot.expected_followers} abonnés,{' '}
          {status.lastSnapshot.following}/{status.lastSnapshot.expected_following} abonnements) : il a été ignoré pour ne pas
          fausser les listes.
        </div>
      )}
      {notice && <div className="banner error">{notice}</div>}

      <nav>
        {TABS.map(([id, label]) => (
          <button key={id} className={tab === id ? 'tab active' : 'tab'} onClick={() => setTab(id)}>
            {label}
            {id === 'clean' && status.counts.non_followers > 0 && <span className="pill">{status.counts.non_followers}</span>}
          </button>
        ))}
      </nav>

      {tab === 'dashboard' && <Dashboard status={status} dataKey={dataKey} />}
      {tab === 'clean' && <Clean status={status} dataKey={dataKey} act={act} />}
      {tab === 'lists' && <Lists dataKey={dataKey} act={act} />}
      {tab === 'history' && <History dataKey={dataKey} />}
      {tab === 'settings' && <Settings status={status} act={act} />}
    </div>
  );
}

function Dashboard({ status, dataKey }) {
  const [events] = usePolling('/events?limit=2000', 30000, [dataKey]);
  const [snapshots] = usePolling('/snapshots', 30000, [dataKey]);
  const c = status.counts;
  const week = Date.now() - 7 * 86400000;
  const recent = (type) => (events ?? []).filter((e) => e.type === type && e.at >= week).length;

  if (!status.lastGoodSnapshot) {
    return (
      <section className="card empty">
        <h2>Premier pas</h2>
        <p>
          {status.account
            ? 'Lance un premier scan : il servira de référence, les changements apparaîtront dès le scan suivant.'
            : 'Connecte-toi à Instagram : une fenêtre de navigateur s’ouvre, tu t’y identifies toi-même, puis elle se referme.'}
        </p>
      </section>
    );
  }
  return (
    <>
      <section className="stats">
        <Stat label="Abonnés" value={c.followers} />
        <Stat label="Abonnements" value={c.following} />
        <Stat label="Ne me suivent pas" value={c.non_followers} tone="bad" />
        <Stat label="Je ne les suis pas" value={c.fans} />
        <Stat label="Mutuels" value={c.mutuals} tone="good" />
      </section>
      <section className="card">
        <h2>7 derniers jours</h2>
        <div className="stats small">
          <Stat label="Nouveaux abonnés" value={`+${recent('follower_gained')}`} tone="good" />
          <Stat label="Abonnés perdus" value={`−${recent('follower_lost')}`} tone="bad" />
          <Stat label="Nouveaux abonnements" value={`+${recent('following_added')}`} />
          <Stat label="Abonnements retirés" value={`−${recent('following_removed')}`} />
        </div>
      </section>
      <section className="card">
        <h2>Derniers changements</h2>
        <EventTable events={(events ?? []).slice(0, 12)} />
      </section>
      <section className="card">
        <h2>Scans</h2>
        <table>
          <thead>
            <tr><th>Date</th><th>Origine</th><th>Résultat</th><th className="num">Abonnés</th><th className="num">Abonnements</th></tr>
          </thead>
          <tbody>
            {(snapshots ?? []).slice(0, 10).map((s) => (
              <tr key={s.id}>
                <td>{fmt(s.at)}</td>
                <td>{s.source === 'auto' ? 'Automatique' : 'Manuel'}</td>
                <td>
                  <span className={`badge ${s.status === 'ok' ? 'good' : 'bad'}`}>
                    {s.status === 'ok' ? 'Complet' : s.status === 'incomplete' ? 'Incomplet' : 'Échec'}
                  </span>{' '}
                  <span className="muted">{s.error}</span>
                </td>
                <td className="num">{s.followers ?? '—'}</td>
                <td className="num">{s.following ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </>
  );
}

function Stat({ label, value, tone = '' }) {
  return (
    <div className="stat">
      <div className={`value ${tone}`}>{value}</div>
      <div className="muted">{label}</div>
    </div>
  );
}

function EventTable({ events }) {
  if (!events.length) return <p className="muted">Aucun changement détecté pour l’instant.</p>;
  return (
    <table>
      <tbody>
        {events.map((e) => (
          <tr key={e.id}>
            <td className="nowrap muted">{fmt(e.at)}</td>
            <td><span className={`badge ${EVENT_LABELS[e.type][1]}`}>{EVENT_LABELS[e.type][0]}</span></td>
            <td><UserLink user={e} /></td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function UserLink({ user }) {
  return (
    <>
      <a href={`https://www.instagram.com/${user.username}/`} target="_blank" rel="noreferrer">@{user.username}</a>
      {user.isVerified ? <span className="verified" title="Compte vérifié"> ✓</span> : null}
      {user.fullName && <span className="muted"> · {user.fullName}</span>}
    </>
  );
}

function useUsers(list, dataKey) {
  const [users, setUsers] = useState([]);
  const reload = useCallback(() => api.get(`/users?list=${list}`).then(setUsers).catch(() => {}), [list]);
  useEffect(() => {
    reload();
  }, [reload, dataKey]);
  return [users, reload];
}

function Clean({ status, dataKey, act }) {
  const [users, reload] = useUsers('non_followers', dataKey);
  const [log] = usePolling('/unfollow-log', 10000, [dataKey]);
  const [selected, setSelected] = useState(() => new Set());
  const [query, setQuery] = useState('');
  const r = status.runner;
  const s = status.settings;

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return users.filter((u) => !q || u.username.includes(q) || (u.fullName ?? '').toLowerCase().includes(q));
  }, [users, query]);
  const selectable = visible.filter((u) => !u.whitelisted && !u.queued);
  const run = (fn) => act(async () => { await fn(); setSelected(new Set()); await reload(); });
  const toggle = (id) => setSelected((prev) => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const allSelected = selectable.length > 0 && selectable.every((u) => selected.has(u.id));
  const remainingDays = Math.ceil(r.queue / Math.max(1, s.dailyCap));

  return (
    <>
      <section className="card">
        <h2>File d’unfollow</h2>
        <div className="stats small">
          <Stat label="En attente" value={r.queue} />
          <Stat label={`Faits sur 1 h (max ${s.hourlyCap})`} value={r.doneHour} />
          <Stat label={`Faits sur 24 h (max ${s.dailyCap})`} value={r.doneDay} />
          <Stat label="État" value={r.enabled ? 'Actif' : 'En pause'} tone={r.enabled ? 'good' : ''} />
        </div>
        {r.lastError && <div className="banner error">{r.lastError}</div>}
        {r.cooldownUntil > Date.now() && (
          <div className="banner warn">Pause de sécurité recommandée jusqu’au {fmt(r.cooldownUntil)}. Relancer avant est risqué.</div>
        )}
        <p className="muted">
          {r.queue > 0 && `À ce rythme : environ ${remainingDays} jour${remainingDays > 1 ? 's' : ''}. `}
          Chaque compte est revérifié juste avant l’unfollow ; l’app doit rester lancée pendant le traitement.
        </p>
        <div className="actions left">
          <button disabled={!r.queue && !r.enabled} onClick={() => act(() => api.post('/runner', { enabled: !r.enabled }))}>
            {r.enabled ? 'Mettre en pause' : 'Démarrer'}
          </button>
          <button className="secondary" disabled={!r.queue} onClick={() => run(() => api.del('/queue'))}>Vider la file</button>
        </div>
      </section>

      <section className="card">
        <div className="row">
          <h2>{LIST_LABELS.non_followers} ({users.length})</h2>
          <input placeholder="Rechercher…" value={query} onChange={(e) => setQuery(e.target.value)} />
        </div>
        <div className="actions left">
          <button disabled={!selected.size} onClick={() => run(() => api.post('/queue', { userIds: [...selected] }))}>
            Ajouter {selected.size || ''} à la file
          </button>
          <button className="secondary" disabled={!selected.size} onClick={() => run(() => api.post('/whitelist', { userIds: [...selected], value: true }))}>
            Protéger (ne jamais unfollow)
          </button>
        </div>
        <table>
          <thead>
            <tr>
              <th className="check">
                <input type="checkbox" aria-label="Tout sélectionner" checked={allSelected}
                  onChange={() => setSelected(allSelected ? new Set() : new Set(selectable.map((u) => u.id)))} />
              </th>
              <th>Compte</th><th>État</th><th></th>
            </tr>
          </thead>
          <tbody>
            {visible.slice(0, MAX_ROWS).map((u) => (
              <tr key={u.id}>
                <td className="check">
                  <input type="checkbox" aria-label={`Sélectionner ${u.username}`} disabled={!!u.whitelisted || !!u.queued}
                    checked={selected.has(u.id)} onChange={() => toggle(u.id)} />
                </td>
                <td><UserLink user={u} /></td>
                <td>
                  {u.whitelisted ? <span className="badge good">Protégé</span> : u.queued ? <span className="badge neutral">Dans la file</span> : null}
                </td>
                <td className="num">
                  {u.whitelisted ? (
                    <button className="link" onClick={() => run(() => api.post('/whitelist', { userIds: [u.id], value: false }))}>Ne plus protéger</button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {!users.length && <p className="muted">Personne : tous tes abonnements te suivent en retour, ou aucun scan n’a encore été fait.</p>}
        {visible.length > MAX_ROWS && <p className="muted">{MAX_ROWS} premiers affichés sur {visible.length} : affine avec la recherche.</p>}
      </section>

      {log?.length > 0 && (
        <section className="card">
          <h2>Journal des unfollows</h2>
          <table>
            <tbody>
              {log.slice(0, 30).map((l) => (
                <tr key={l.id}>
                  <td className="nowrap muted">{fmt(l.at)}</td>
                  <td>@{l.username}</td>
                  <td>
                    <span className={`badge ${l.status === 'done' ? 'good' : l.status === 'error' ? 'bad' : 'neutral'}`}>
                      {l.status === 'done' ? 'Unfollow fait' : l.status === 'error' ? 'Erreur' : 'Ignoré'}
                    </span>{' '}
                    <span className="muted">{l.detail}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </>
  );
}

function Lists({ dataKey }) {
  const [list, setList] = useState('fans');
  const [users] = useUsers(list, dataKey);
  const [query, setQuery] = useState('');
  const q = query.trim().toLowerCase();
  const visible = users.filter((u) => !q || u.username.includes(q) || (u.fullName ?? '').toLowerCase().includes(q));
  return (
    <section className="card">
      <div className="row">
        <select value={list} onChange={(e) => setList(e.target.value)}>
          {Object.entries(LIST_LABELS).map(([id, label]) => <option key={id} value={id}>{label}</option>)}
        </select>
        <input placeholder="Rechercher…" value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <p className="muted">{visible.length} compte{visible.length > 1 ? 's' : ''}</p>
      <table>
        <thead><tr><th>Compte</th><th>Type</th><th>Vu depuis le</th></tr></thead>
        <tbody>
          {visible.slice(0, MAX_ROWS).map((u) => (
            <tr key={u.id}>
              <td><UserLink user={u} /></td>
              <td className="muted">{u.isPrivate ? 'Privé' : 'Public'}</td>
              <td className="muted">{fmt(u.since)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {visible.length > MAX_ROWS && <p className="muted">{MAX_ROWS} premiers affichés sur {visible.length} : affine avec la recherche.</p>}
    </section>
  );
}

function History({ dataKey }) {
  const [events] = usePolling('/events?limit=2000', 30000, [dataKey]);
  const [type, setType] = useState('all');
  const visible = (events ?? []).filter((e) => type === 'all' || e.type === type);
  return (
    <section className="card">
      <div className="row">
        <h2>Historique des changements</h2>
        <select value={type} onChange={(e) => setType(e.target.value)}>
          <option value="all">Tous les changements</option>
          {Object.entries(EVENT_LABELS).map(([id, [label]]) => <option key={id} value={id}>{label}</option>)}
        </select>
      </div>
      <EventTable events={visible.slice(0, MAX_ROWS)} />
    </section>
  );
}

function Settings({ status, act }) {
  const [form, setForm] = useState(status.settings);
  const [saved, setSaved] = useState(false);
  const num = (key, label, hint) => (
    <label>
      <span>{label}</span>
      <input type="number" min="0" value={form[key]} onChange={(e) => { setSaved(false); setForm({ ...form, [key]: Number(e.target.value) }); }} />
      {hint && <small className="muted">{hint}</small>}
    </label>
  );
  return (
    <section className="card">
      <h2>Scan quotidien</h2>
      <label className="inline">
        <input type="checkbox" checked={form.autoSnapshot} onChange={(e) => { setSaved(false); setForm({ ...form, autoSnapshot: e.target.checked }); }} />
        <span>Scanner automatiquement une fois par jour</span>
      </label>
      <div className="form">
        {num('snapshotHour', 'Heure du scan (0–23)', 'Si l’app est lancée plus tard dans la journée, le scan part au démarrage.')}
      </div>
      <h2>Rythme des unfollows</h2>
      <div className="form">
        {num('hourlyCap', 'Maximum par heure')}
        {num('dailyCap', 'Maximum par 24 h')}
        {num('delayMinSec', 'Délai minimum (s)')}
        {num('delayMaxSec', 'Délai maximum (s)')}
      </div>
      <p className="muted">Augmenter ces valeurs accélère le nettoyage mais augmente le risque de blocage par Instagram.</p>
      <div className="actions left">
        <button onClick={() => act(async () => { setForm(await api.put('/settings', form)); setSaved(true); })}>Enregistrer</button>
        {saved && <span className="muted">Enregistré.</span>}
      </div>
    </section>
  );
}
