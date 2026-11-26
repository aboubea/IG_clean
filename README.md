# IG Clean

Application locale (React + Node + Playwright) qui suit ton compte Instagram jour après jour :

- **scan quotidien** de tes abonnés et abonnements ;
- **historique** : qui s'est abonné, qui ne te suit plus, qui tu as suivi, qui tu ne suis plus ;
- **listes** : ne me suivent pas en retour, me suivent sans que je les suive, mutuels ;
- **nettoyage** : file d'unfollow progressive avec plafonds horaires et journaliers, délais aléatoires et liste de comptes protégés.

> ⚠️ Instagram n'offre aucune API officielle pour cela. L'app automatise ta propre session web, ce qui est contraire
> aux conditions d'utilisation d'Instagram et peut entraîner un blocage temporaire, voire la suspension du compte.
> Garde des plafonds bas et utilise-la à tes risques.

## Installation

Node 22.13 ou plus récent est nécessaire.

```bash
npm install
npx playwright install chromium
```

## Utilisation

```bash
npm start
```

Ouvre ensuite http://localhost:3001.

1. **Se connecter à Instagram** : une fenêtre de navigateur s'ouvre, tu t'y identifies toi-même (2FA comprise).
   L'app ne voit jamais ton mot de passe ; la session reste dans `data/browser-profile`.
2. **Scanner maintenant** : le premier scan sert de référence, les changements apparaissent dès le suivant.
3. Onglet **Nettoyage** : protège les comptes à garder, ajoute les autres à la file, puis **Démarrer**.

Tant que l'app tourne, elle relance un scan chaque jour à l'heure choisie dans **Réglages** (ou au démarrage si
l'heure est déjà passée) et reprend la file d'unfollow dès que les plafonds le permettent.

Pour essayer sans toucher à Instagram, avec de fausses données :

```bash
npm run demo
```

### Scan planifié sans laisser l'app ouverte

`npm run snapshot` fait un scan puis s'arrête : à brancher sur cron ou le Planificateur de tâches.
L'app ne doit pas tourner en même temps (un seul navigateur peut utiliser le profil).

## Sécurités intégrées

- Un scan dont les listes sont tronquées par rapport aux compteurs du profil est ignoré.
- Chaque compte est revérifié en direct juste avant l'unfollow : quelqu'un qui s'est réabonné est épargné.
- Au premier signe de limitation ou de vérification demandée par Instagram, la file se met en pause 24 h.
- Le serveur n'écoute que sur `127.0.0.1`.

## Variables d'environnement

| Variable | Rôle |
| --- | --- |
| `PORT` | Port du serveur (3001 par défaut) |
| `DATA_DIR` | Dossier de la base SQLite et du profil navigateur (`./data`) |
| `BROWSER_CHANNEL=chrome` | Utiliser le Chrome installé plutôt que le Chromium de Playwright |
| `HEADLESS=1` | Ne pas afficher la fenêtre pendant les scans (plus facilement détecté par Instagram) |
| `IG_MOCK=1` | Mode démo |

## Structure

- `server/ig/browser.js` : client Instagram (endpoints web appelés depuis la page) ; `server/ig/mock.js` : faux client.
- `server/snapshot.js` : scan et calcul des changements ; `server/unfollow.js` : file d'unfollow.
- `server/index.js` : API HTTP et planificateur ; `src/` : interface React.

Pour ajouter une action, s'inspirer de `server/unfollow.js` : une tâche passée à `runExclusive` qui ouvre une session.
