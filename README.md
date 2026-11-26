# IG Clean

App iOS (Swift / SwiftUI) qui suit ton compte Instagram :

- **Résumé** : abonnés, abonnements, qui ne te suit pas en retour, changements des 7 derniers jours.
- **Historique** : qui s'est abonné, qui ne te suit plus, qui tu as suivi, qui tu ne suis plus.
- **Nettoyage** : unfollow progressif de ceux qui ne te suivent pas, avec plafonds et comptes protégés.

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

## Limites liées à iOS

- iOS suspend les apps en arrière-plan : le scan se fait à l'ouverture de l'app, et la file d'unfollow n'avance
  que tant que l'app reste au premier plan (l'écran est maintenu allumé pendant le traitement).
- Les données restent sur l'appareil ; « Se déconnecter et tout effacer » supprime la session et l'historique.

## Sécurités intégrées

- Un scan dont les listes sont tronquées par rapport aux compteurs du profil est ignoré.
- Chaque compte est revérifié juste avant l'unfollow : quelqu'un qui s'est réabonné est épargné.
- Au premier signe de limitation ou de vérification demandée par Instagram, la file s'arrête 24 h.
- Le mot de passe est saisi dans la page d'Instagram elle-même ; l'app ne le voit pas.

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
