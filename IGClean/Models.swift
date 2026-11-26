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

    func unfollowsDone(since interval: TimeInterval, now: Date = Date()) -> Int {
        let limit = now.addingTimeInterval(-interval)
        return log.filter { $0.status == .done && $0.at > limit }.count
    }
}
