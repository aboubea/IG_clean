# IG Clean

App iOS (Swift / SwiftUI) qui suit ton compte Instagram :

- **Un seul écran** : ton nombre d'abonnés, ce qui a changé au dernier scan, et un bouton pour nettoyer.
- **Historique** (menu en haut à gauche) : qui s'est abonné, qui ne te suit plus, qui tu as suivi, qui tu ne suis plus.
- **Nettoyage** : tu choisis des groupes de comptes et un rythme, puis l'app unfollow progressivement.
- **Bilan partageable** : une carte au format story (abonnés, mutuels, série) à poster en un tap, et un défi à envoyer à un ami.
- **Fans fidèles** : le classement de tes abonnés mutuels, du plus ancien au plus récent.
- **Hot Influx** : classement d'influenceurs par croissance (5/10/20/30 j), engagement ou taille. Source de démo intégrée ; à brancher sur un fournisseur de données pour couvrir tout Instagram (voir ci-dessous).

Tu ouvres l'app, tu te connectes à Instagram une fois, et le scan se lance tout seul. Ensuite, un scan par jour
à l'ouverture de l'app.

> ⚠️ Usage personnel uniquement. Instagram n'offre aucune API officielle pour cela : l'app automatise ta propre
> session web, ce qui est contraire à ses conditions d'utilisation et peut entraîner un blocage du compte.
> Pour la même raison, l'app n'est pas publiable sur l'App Store (règle 5.2.2 d'Apple).

## Installation sur ton iPhone

Il faut un Mac avec **Xcode 16 ou plus récent** et un iPhone sous **iOS 17 ou plus récent**.

1. Ouvre `IGClean.xcodeproj` dans Xcode.
2. Cible **IGClean** → onglet **Signing & Capabilities** → choisis ton **Team** (ton identifiant Apple suffit)
   et remplace l'identifiant `com.igclean.app` par un identifiant à toi, par exemple `com.tonnom.igclean`.
3. Branche ton iPhone, sélectionne-le en haut de la fenêtre, puis lance avec ▶.
4. Au premier lancement, sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil → fais confiance à ton
   certificat de développeur.

Avec un identifiant Apple gratuit, l'app doit être réinstallée depuis Xcode tous les 7 jours ; avec un compte
développeur payant, une fois par an.

## Hot Influx : source de données

L'écran Hot Influx tourne sur une **source de démo** intégrée (`DemoInfluxProvider`). Couvrir tout Instagram
n'est pas possible depuis la session de l'appareil : il faut une source externe, à placer derrière le protocole
`HotInfluxProvider` sans toucher à l'interface.

- **N'utilise pas ta session Instagram perso** pour alimenter Hot Influx : relever chaque jour les chiffres de
  centaines de comptes ferait bannir ton compte.
- Deux voies : une **API d'analytics d'influenceurs** payante, ou un **backend qui scrape** (ex. Apify) amorcé
  par hashtags/catégories, relevant les chiffres chaque jour.
- La fenêtre 30 j reste vide tant que la source n'a pas 30 jours d'historique ; l'engagement (likes/commentaires)
  suppose de lire les posts récents de chaque compte.

## Limites liées à iOS

- iOS suspend les apps en arrière-plan : le scan se fait à l'ouverture de l'app (ou en tirant l'écran vers le bas),
  et le nettoyage n'avance que tant que l'app reste au premier plan. L'écran reste allumé pendant ces deux tâches.
- Plafond horaire atteint : l'app attend sur place et reprend toute seule. Plafond du jour atteint : le nettoyage
  reprend tout seul à la prochaine ouverture de l'app, sauf si tu l'as mis en pause.
- Les données restent sur l'appareil ; « Se déconnecter et tout effacer » (avec confirmation) supprime la session
  et l'historique.

## Sécurités intégrées

- Un scan dont les listes sont tronquées par rapport aux compteurs du profil est ignoré.
- Chaque compte est revérifié juste avant l'unfollow : quelqu'un qui s'est réabonné est épargné.
- Au premier signe de limitation ou de vérification demandée par Instagram, la file s'arrête 24 h.
- Le mot de passe est saisi dans la page d'Instagram elle-même ; l'app ne le voit pas.
- Session refusée par Instagram : l'app efface le cookie périmé et redemande la connexion, au lieu de réessayer en boucle.
- Fichier de données illisible : il est mis de côté (`state-….unreadable.json`) plutôt qu'écrasé.

## Tests de logique

La logique sans interface (modèle, moteur de scan, stockage, Hot Influx) se vérifie sans simulateur :

```bash
scripts/test-logic.sh
```

## Structure

| Fichier | Rôle |
| --- | --- |
| `IGClean/InstagramClient.swift` | Requêtes Instagram, exécutées dans une vue web invisible qui partage la session |
| `IGClean/SnapshotEngine.swift` | Comparaison d'un scan avec l'état connu, calcul des changements |
| `IGClean/AppModel.swift` | État de l'app, connexion, scan, file d'unfollow |
| `IGClean/Models.swift`, `IGClean/Store.swift` | Données et enregistrement (fichier JSON local) |
| `IGClean/Views/` | Écrans SwiftUI |

Pour ajouter une action, ajoute la requête dans `InstagramClient` et son déroulé dans `AppModel`, sur le modèle
de `runQueue()`.
