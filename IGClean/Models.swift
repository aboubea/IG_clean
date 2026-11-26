import Foundation

struct IGUser: Codable, Identifiable, Hashable {
    let id: String
    var username: String
    var fullName: String
    var isPrivate: Bool
    var isVerified: Bool
}

struct Account: Codable {
    let id: String
    var username: String
}

enum EventType: String, Codable, CaseIterable, Identifiable {
    case followerGained, followerLost, followingAdded, followingRemoved

    var id: String { rawValue }

    var label: String {
        switch self {
        case .followerGained: return "Nouvel abonné"
        case .followerLost: return "Ne te suit plus"
        case .followingAdded: return "Tu le suis"
        case .followingRemoved: return "Tu ne le suis plus"
        }
    }

    var symbol: String {
        switch self {
        case .followerGained: return "person.badge.plus"
        case .followerLost: return "person.badge.minus"
        case .followingAdded: return "plus.circle"
        case .followingRemoved: return "minus.circle"
        }
    }
}

struct ChangeEvent: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let type: EventType
    let userId: String
}

enum SnapshotStatus: String, Codable {
    case ok, incomplete, error
}

struct Snapshot: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let status: SnapshotStatus
    var followers = 0
    var following = 0
    var expectedFollowers = 0
    var expectedFollowing = 0
    var error: String?
}

enum UnfollowStatus: String, Codable {
    case done, skipped, error
}

struct UnfollowLog: Codable, Identifiable {
    var id = UUID()
    let at: Date
    let userId: String
    let status: UnfollowStatus
    var detail: String?
}

struct UnfollowSettings: Codable {
    var hourlyCap = 20
    var dailyCap = 100
    /// Délai aléatoire entre deux unfollows, en secondes.
    var delayMin = 20.0
    var delayMax = 45.0
}

/// Tout ce que l'app conserve, enregistré dans un seul fichier JSON.
struct AppState: Codable {
    var account: Account?
    var users: [String: IGUser] = [:]
    /// id -> date de première observation
    var followers: [String: Date] = [:]
    var following: [String: Date] = [:]
    /// Du plus récent au plus ancien.
    var events: [ChangeEvent] = []
    var snapshots: [Snapshot] = []
    var queue: [String] = []
    var whitelist: Set<String> = []
    var log: [UnfollowLog] = []
    var settings = UnfollowSettings()
    var cooldownUntil: Date?
    var lastAttemptAt: Date?
    /// Taille du nettoyage en cours, pour afficher l'avancement ; nil quand aucun n'est lancé.
    var batchTotal: Int?
    /// Nombre total d'unfollows faits depuis l'installation (le journal, lui, est plafonné).
    var lifetimeUnfollows = 0
    /// Premier scan complet : point de départ de l'ancienneté des abonnements.
    var firstScanAt: Date?
    /// Plafond du jour atteint : le nettoyage reprend tout seul à l'ouverture de l'app après cette date.
    var resumeAfter: Date?
    /// Pause demandée par toi (ou arrêt de sécurité) : pas de reprise automatique.
    var userPaused = false
}

extension AppState {
    /// Décodage tolérant : une clé absente (champ ajouté dans une version plus récente) ou illisible
    /// reprend sa valeur par défaut, au lieu de faire échouer toute la lecture et d'effacer l'historique.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = (try? c.decodeIfPresent(Account.self, forKey: .account)) ?? nil
        users = (try? c.decodeIfPresent([String: IGUser].self, forKey: .users)) ?? [:]
        followers = (try? c.decodeIfPresent([String: Date].self, forKey: .followers)) ?? [:]
        following = (try? c.decodeIfPresent([String: Date].self, forKey: .following)) ?? [:]
        events = (try? c.decodeIfPresent([ChangeEvent].self, forKey: .events)) ?? []
        snapshots = (try? c.decodeIfPresent([Snapshot].self, forKey: .snapshots)) ?? []
        queue = (try? c.decodeIfPresent([String].self, forKey: .queue)) ?? []
        whitelist = (try? c.decodeIfPresent(Set<String>.self, forKey: .whitelist)) ?? []
        log = (try? c.decodeIfPresent([UnfollowLog].self, forKey: .log)) ?? []
        settings = (try? c.decodeIfPresent(UnfollowSettings.self, forKey: .settings)) ?? UnfollowSettings()
        cooldownUntil = (try? c.decodeIfPresent(Date.self, forKey: .cooldownUntil)) ?? nil
        lastAttemptAt = (try? c.decodeIfPresent(Date.self, forKey: .lastAttemptAt)) ?? nil
        batchTotal = (try? c.decodeIfPresent(Int.self, forKey: .batchTotal)) ?? nil
        lifetimeUnfollows = (try? c.decodeIfPresent(Int.self, forKey: .lifetimeUnfollows)) ?? 0
        firstScanAt = (try? c.decodeIfPresent(Date.self, forKey: .firstScanAt)) ?? nil
        resumeAfter = (try? c.decodeIfPresent(Date.self, forKey: .resumeAfter)) ?? nil
        userPaused = (try? c.decodeIfPresent(Bool.self, forKey: .userPaused)) ?? false
    }
}

/// « 1 compte », « 3 comptes » (en français, 0 et 1 sont au singulier).
func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
    "\(count) " + (count > 1 ? (pluralForm ?? singular + "s") : singular)
}

/// Santé du compte, d'après la part d'abonnements qui te suivent en retour.
enum AccountHealth {
    case excellent, good, watch

    static func from(ratio: Double) -> AccountHealth {
        if ratio >= 0.8 { return .excellent }
        if ratio >= 0.5 { return .good }
        return .watch
    }

    var label: String {
        switch self {
        case .excellent: return "Compte sain"
        case .good: return "Compte correct"
        case .watch: return "À surveiller"
        }
    }
}

/// Instantané de chiffres prêts à afficher ou à partager.
struct Stats {
    var followers = 0
    var following = 0
    var mutuals = 0
    var nonFollowers = 0
    var weekGained = 0
    var weekLost = 0
    var cleaned = 0
    /// Part des abonnements qui te suivent en retour, entre 0 et 1.
    var mutualRatio = 0.0
    var scanStreak = 0

    var mutualPercent: Int { Int((mutualRatio * 100).rounded()) }
    var health: AccountHealth { AccountHealth.from(ratio: mutualRatio) }
}

/// Rythme du nettoyage : plus il est rapide, plus Instagram risque de limiter le compte.
enum Pace: String, CaseIterable, Identifiable {
    case careful, normal, fast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .careful: return "Prudent"
        case .normal: return "Normal"
        case .fast: return "Rapide"
        }
    }

    var settings: UnfollowSettings {
        switch self {
        case .careful: return UnfollowSettings(hourlyCap: 15, dailyCap: 60, delayMin: 30, delayMax: 60)
        case .normal: return UnfollowSettings(hourlyCap: 20, dailyCap: 100, delayMin: 20, delayMax: 45)
        case .fast: return UnfollowSettings(hourlyCap: 40, dailyCap: 150, delayMin: 10, delayMax: 25)
        }
    }

    static func matching(_ settings: UnfollowSettings) -> Pace {
        allCases.first { $0.settings.hourlyCap == settings.hourlyCap } ?? .normal
    }
}

/// Groupes proposés à l'écran de nettoyage.
enum CleanGroup: String, CaseIterable, Identifiable {
    case old, recent, verified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .old: return "Suivis depuis plus de 3 mois"
        case .recent: return "Suivis récemment"
        case .verified: return "Comptes vérifiés"
        }
    }

    var hint: String {
        switch self {
        case .old: return "jamais suivi en retour"
        case .recent: return "vus depuis moins de 3 mois"
        case .verified: return "marques, célébrités"
        }
    }
}

enum UserList: String, CaseIterable, Identifiable {
    case nonFollowers, fans, mutuals, followers, following

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nonFollowers: return "Ne me suivent pas en retour"
        case .fans: return "Me suivent, je ne les suis pas"
        case .mutuals: return "Abonnements mutuels"
        case .followers: return "Tous mes abonnés"
        case .following: return "Tous mes abonnements"
        }
    }
}

extension AppState {
    func users(in list: UserList) -> [IGUser] {
        let ids: [String]
        switch list {
        case .nonFollowers: ids = following.keys.filter { followers[$0] == nil }
        case .fans: ids = followers.keys.filter { following[$0] == nil }
        case .mutuals: ids = following.keys.filter { followers[$0] != nil }
        case .followers: ids = Array(followers.keys)
        case .following: ids = Array(following.keys)
        }
        return ids.compactMap { users[$0] }.sorted { $0.username < $1.username }
    }

    func count(in list: UserList) -> Int {
        switch list {
        case .nonFollowers: return following.keys.filter { followers[$0] == nil }.count
        case .fans: return followers.keys.filter { following[$0] == nil }.count
        case .mutuals: return following.keys.filter { followers[$0] != nil }.count
        case .followers: return followers.count
        case .following: return following.count
        }
    }

    var lastGoodSnapshot: Snapshot? { snapshots.first { $0.status == .ok } }

    /// Comptes d'un groupe qui ne me suivent pas en retour. L'ancienneté part de la première fois
    /// où l'app a vu l'abonnement : Instagram ne donne pas la vraie date.
    func cleanCandidates(_ group: CleanGroup, now: Date = Date()) -> [IGUser] {
        let limit = now.addingTimeInterval(-90 * 86400)
        return users(in: .nonFollowers).filter { user in
            let isOld = (following[user.id] ?? now) < limit
            switch group {
            case .verified: return user.isVerified
            case .old: return !user.isVerified && isOld
            case .recent: return !user.isVerified && !isOld
            }
        }
    }

    /// Début de l'historique connu de l'app.
    var historyStart: Date? {
        firstScanAt ?? snapshots.last { $0.status == .ok }?.at
    }

    /// Au moins 3 mois d'historique : la distinction « ancien / récent » a alors un sens.
    var hasLongHistory: Bool {
        guard let start = historyStart else { return false }
        return Date().timeIntervalSince(start) >= 90 * 86400
    }

    /// Groupes affichés au nettoyage. Sans 3 mois d'historique, tous les abonnements paraissent
    /// « récents » : on n'affiche alors qu'un groupe « non vérifiés ».
    var cleanGroups: [CleanGroup] {
        hasLongHistory ? CleanGroup.allCases : [.recent, .verified]
    }

    func title(for group: CleanGroup) -> String {
        if group == .recent && !hasLongHistory { return "Comptes non vérifiés" }
        return group.title
    }

    func hint(for group: CleanGroup) -> String {
        if group == .recent && !hasLongHistory { return "ne te suivent pas en retour" }
        return group.hint
    }

    /// Date à laquelle un unfollow redevient possible sous ce plafond, ou nil s'il reste de la marge.
    func capFreesAt(cap: Int, window: TimeInterval, now: Date = Date()) -> Date? {
        let limit = now.addingTimeInterval(-window)
        // Journal du plus récent au plus ancien.
        let recent = log.filter { $0.status == .done && $0.at > limit }
        guard cap > 0, recent.count >= cap else { return nil }
        // Il faut que le cap-ième plus récent sorte de la fenêtre pour repasser sous le plafond.
        return recent[cap - 1].at.addingTimeInterval(window)
    }

    /// Nombre de scans réussis sur des jours consécutifs finissant aujourd'hui (ou hier).
    var scanStreak: Int {
        let cal = Calendar.current
        let days = Set(snapshots.filter { $0.status == .ok }.map { cal.startOfDay(for: $0.at) })
        guard !days.isEmpty else { return 0 }
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
            if !days.contains(day) { return 0 }
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    func events(ofType type: EventType, since interval: TimeInterval, now: Date = Date()) -> Int {
        let limit = now.addingTimeInterval(-interval)
        return events.filter { $0.type == type && $0.at > limit }.count
    }

    var stats: Stats {
        let following = count(in: .following)
        let mutuals = count(in: .mutuals)
        return Stats(
            followers: count(in: .followers),
            following: following,
            mutuals: mutuals,
            nonFollowers: count(in: .nonFollowers),
            weekGained: events(ofType: .followerGained, since: 7 * 86400),
            weekLost: events(ofType: .followerLost, since: 7 * 86400),
            cleaned: lifetimeUnfollows,
            mutualRatio: following > 0 ? Double(mutuals) / Double(following) : 0,
            scanStreak: scanStreak
        )
    }

    /// Tes mutuels, du plus ancien au plus récent : tes fans les plus fidèles d'abord.
    var loyalFans: [IGUser] {
        following.keys
            .filter { followers[$0] != nil }
            .compactMap { id in users[id].map { (user: $0, since: followers[id] ?? Date()) } }
            .sorted { $0.since < $1.since }
            .map { $0.user }
    }
}
