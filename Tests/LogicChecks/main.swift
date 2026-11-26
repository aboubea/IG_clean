// Vérifications de la logique pure (modèle, moteur de scan, Hot Influx), sans simulateur.
// Lancement : scripts/test-logic.sh
import Foundation

func check(_ ok: Bool, _ name: String) { print(ok ? "OK   \(name)" : "FAIL \(name)"); if !ok { failures += 1 } }
var failures = 0
func u(_ id: String) -> IGUser { IGUser(id: id, username: "u\(id)", fullName: "", isPrivate: false, isVerified: false) }

// 1. Ancien fichier sans les champs ajoutés depuis : doit se relire sans perdre l'historique.
let old = """
{"users":{"1":{"id":"1","username":"lea","fullName":"","isPrivate":false,"isVerified":false}},
 "followers":{"1":0},"following":{"1":0},"events":[],"snapshots":[],"queue":[],"whitelist":["9"],
 "log":[],"settings":{"hourlyCap":20,"dailyCap":100,"delayMin":20,"delayMax":45}}
"""
let decoded = try? JSONDecoder().decode(AppState.self, from: Data(old.utf8))
check(decoded?.users["1"]?.username == "lea" && decoded?.whitelist == ["9"] && decoded?.lifetimeUnfollows == 0,
      "ancien fichier relu sans perte (champs manquants = valeurs par défaut)")
let roundTrip = try! JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(decoded!))
check(roundTrip.followers.count == 1, "aller-retour JSON")

// 2. Scan : référence puis détection des 4 changements, et nettoyage de la file.
var s = AppState()
SnapshotEngine.apply(to: &s, followers: [u("1"), u("2")], following: [u("2"), u("3")], expectedFollowers: 2, expectedFollowing: 2)
check(s.events.isEmpty && s.firstScanAt != nil, "premier scan = référence, sans événements")
s.queue = ["3", "2"]
SnapshotEngine.apply(to: &s, followers: [u("2"), u("4"), u("3")], following: [u("2"), u("5"), u("3")], expectedFollowers: 3, expectedFollowing: 3)
let types = Set(s.events.map { "\($0.type.rawValue):\($0.userId)" })
check(types == ["followerGained:4", "followerGained:3", "followerLost:1", "followingAdded:5"], "changements détectés \(types.sorted())")
check(s.queue.isEmpty, "la file retire ceux qui me suivent désormais")

// 3. Scan tronqué ignoré.
let before = s.followers
SnapshotEngine.apply(to: &s, followers: [u("2")], following: [u("2"), u("5"), u("3")], expectedFollowers: 300, expectedFollowing: 3)
check(s.snapshots.first?.status == .incomplete && s.followers == before, "scan tronqué ignoré")

// 4. Plafonds : date de libération.
var c = AppState()
let now = Date()
c.log = (0..<20).map { UnfollowLog(at: now.addingTimeInterval(Double(-$0 * 60)), userId: "\($0)", status: .done) }
let frees = c.capFreesAt(cap: 20, window: 3600, now: now)
check(frees != nil && abs(frees!.timeIntervalSince(now.addingTimeInterval(-19 * 60 + 3600))) < 1, "plafond horaire : libération quand le plus ancien sort")
check(c.capFreesAt(cap: 21, window: 3600, now: now) == nil, "sous le plafond : pas d'attente")

// 5. Groupes : sans 3 mois d'historique, pas de distinction ancien/récent.
check(s.cleanGroups == [.recent, .verified] && s.title(for: .recent) == "Comptes non vérifiés", "groupes adaptés à un historique court")
var long = s; long.firstScanAt = Date().addingTimeInterval(-100 * 86400)
check(long.cleanGroups == CleanGroup.allCases, "groupes complets après 3 mois")

// 6. Série de scans.
var st = AppState()
st.snapshots = (0..<4).map { Snapshot(at: Date().addingTimeInterval(Double(-$0) * 86400), status: .ok) }
check(st.scanStreak == 4, "série de 4 jours")

// 7. Démo Hot Influx : croissance croissante avec la fenêtre, classements qui diffèrent.
let rows = try await DemoInfluxProvider().fetch()
check(rows.allSatisfy { $0.growth5 <= $0.growth10 && $0.growth10 <= $0.growth20 && $0.growth20 <= $0.growth30 }, "croissance cumulée cohérente")
check(rows.ranked(by: .growth, window: .d5).map(\.id) != rows.ranked(by: .growth, window: .d30).map(\.id), "le classement change selon la fenêtre")
let validHandle = rows.allSatisfy { $0.username.range(of: "^[a-z0-9._]+$", options: .regularExpression) != nil }
check(validHandle, "pseudos au format Instagram")
check(plural(1, "compte") == "1 compte" && plural(0, "compte") == "0 compte" && plural(3, "compte") == "3 comptes", "pluriels")

print(failures == 0 ? "\nTOUT PASSE" : "\n\(failures) ÉCHEC(S)")
exit(failures == 0 ? 0 : 1)
