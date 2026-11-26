# Pulse

Tous tes réseaux, un seul tableau de bord. Pulse réunit Instagram, Facebook, TikTok et LinkedIn, dit où tu
grandis et ce qui marche, et un coach IA propose quoi faire la semaine prochaine.

| Dossier | Contenu |
| --- | --- |
| `ios/` | App iPhone en SwiftUI (iOS 17+) |
| `server/` | Serveur TypeScript : comptes, connexion des réseaux, relevé nocturne des chiffres, analyses, IA, media kits publics |
| `design/` | Maquettes |

```
iPhone (SwiftUI) ──https──▶ serveur Pulse ──▶ API officielles des réseaux
                                 │        └──▶ API Claude (coach, bilans, idées, pré-test)
                                 └──▶ Postgres
```

## Démarrage rapide

### Serveur

Node 22 ou plus récent.

```bash
cd server
npm install
npm run dev
```

Le serveur écoute sur http://localhost:8787. Sans configuration, tout fonctionne en **mode démo** : base
Postgres embarquée (PGlite, dans `server/.data/`), réseaux de démonstration aux données réalistes, IA de
démonstration sans appel réseau. Pour le vrai coach IA, ajoute une clé Anthropic avant `npm run dev` :

```bash
export ANTHROPIC_API_KEY=...
```

Les autres réglages sont dans `server/.env.example`.

### App iPhone

Ouvre `ios/Pulse.xcodeproj` dans Xcode 16+, choisis ton équipe dans **Signing & Capabilities**, puis lance sur
le simulateur : il joint directement `http://localhost:8787`. Sur un vrai iPhone, indique l'adresse du Mac
(ex. `http://192.168.1.20:8787`) dans **Profil → Avancé**.

### Tests

```bash
cd server
npm test
```

## Fonctions

- **Accueil** : audience totale de tous les réseaux, évolution, réseau qui porte la croissance, paliers à fêter.
- **Analyse** : engagement par format, carte des meilleurs créneaux (heure de Paris), meilleurs posts, Hot Influx.
- **Créer** : pré-test d'un post avant publication (visuel + légende → score, réseau, horaire, légende améliorée)
  et 5 idées de contenus par semaine.
- **Coach** : questions libres sur ses propres chiffres, réponse en direct.
- **Bilan hebdo** : résumé et 3 actions, à partager en story.
- **Viralité** : cartes à partager (bilan, paliers), media kit public `pulse/@nom` avec formulaire pour les
  marques, parrainage qui offre un mois de Premium aux deux.
- **Modèle** : version gratuite avec quotas IA hebdomadaires, Premium (abonnement en phase 2), commission sur
  les collaborations avec les marques (phase 3), publicité dans la version gratuite (phase 2).

## Feuille de route

**Phase 1 — fait** : serveur complet en mode démo, app iPhone branchée dessus, IA Claude, media kit, parrainage.

**Phase 2 — à lancer dès maintenant** (les validations des réseaux prennent plusieurs semaines) :

| Qui | Quoi |
| --- | --- |
| Meta | Créer une app sur developers.facebook.com, faire la **vérification d'entreprise**, demander l'accès aux statistiques Instagram (comptes professionnels) et aux Pages Facebook, puis passer l'**examen de l'app** (vidéo de démonstration, politique de confidentialité, URL de suppression des données). |
| TikTok | Créer une app sur developers.tiktok.com, demander la connexion (Login Kit) et l'accès aux statistiques des vidéos, puis passer l'examen. |
| LinkedIn | Demander l'accès à l'API des pages entreprise (programme partenaire) : c'est le plus long, et il peut être refusé. |
| Apple | Créer l'abonnement Premium dans App Store Connect ; prévoir la connexion avec Apple. |
| Publicité | Ouvrir un compte AdMob (ou équivalent) pour la version gratuite. |
| Hébergement | Un Postgres managé, le serveur en https, et une clé `TOKEN_ENCRYPTION_KEY` générée une fois pour toutes. |
| Légal | Politique de confidentialité, conditions d'utilisation, registre RGPD. |

Les conditions d'accès des réseaux changent souvent : vérifier chaque point au moment de la demande. Une fois
les identifiants obtenus, chaque connecteur officiel s'ajoute dans `server/src/connectors/` derrière la même
interface que le connecteur de démo, sans toucher aux écrans.

**Phase 3** : portail des marques et commission, récap annuel façon Wrapped, défis entre amis (avec accord des
deux), notifications push, version web.

## Choix techniques

- **API officielles uniquement** : condition pour l'App Store et pour ne jamais mettre en danger les comptes des
  utilisateurs. L'ancien outil perso Instagram (lecture des abonnés, unfollow automatique) n'est plus dans l'app ;
  il reste dans l'historique git, au commit `646d7cd`.
- **IA** : modèle `claude-opus-5-5` par défaut (`PULSE_AI_MODEL` pour en changer), réponses structurées pour le
  bilan, les idées et le pré-test, flux pour le coach, et repli automatique sur un autre modèle si une requête
  est déclinée. Les quotas hebdomadaires (`server/src/config.ts`) maîtrisent le coût.
- **Sécurité** : jetons des réseaux chiffrés en AES-256-GCM, session de l'app dans le trousseau iOS, media kit
  privé par défaut, suppression complète du compte depuis l'app.
