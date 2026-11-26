import Foundation

/// Logique pure : compare un scan à l'état connu et en déduit les changements.
enum SnapshotEngine {
    /// Instagram affiche des compteurs légèrement supérieurs aux listes réelles (comptes désactivés) :
    /// en dessous de ce ratio, on considère le scan tronqué et on ne touche pas à l'état.
    static let completeRatio = 0.97
    static let maxEvents = 5000
    static let maxSnapshots = 90

    @discardableResult
    static func apply(
        to state: inout AppState,
        followers: [IGUser],
        following: [IGUser],
        expectedFollowers: Int,
        expectedFollowing: Int,
        at: Date = Date()
    ) -> SnapshotStatus {
        let complete =
            Double(followers.count) >= (Double(expectedFollowers) * completeRatio).rounded(.down)
            && Double(following.count) >= (Double(expectedFollowing) * completeRatio).rounded(.down)
        // Le tout premier scan complet sert de référence : il ne génère pas d'événements.
        let hasBaseline = state.snapshots.contains { $0.status == .ok }

        state.snapshots.insert(
            Snapshot(
                at: at,
                status: complete ? .ok : .incomplete,
                followers: followers.count,
                following: following.count,
                expectedFollowers: expectedFollowers,
                expectedFollowing: expectedFollowing
            ),
            at: 0
        )
        state.snapshots = Array(state.snapshots.prefix(maxSnapshots))
        guard complete else { return .incomplete }

        for user in followers + following { state.users[user.id] = user }

        var fresh: [ChangeEvent] = []
        func diff(_ before: [String: Date], _ now: [IGUser], gained: EventType, lost: EventType) -> [String: Date] {
            var result: [String: Date] = [:]
            for user in now {
                result[user.id] = before[user.id] ?? at
                if before[user.id] == nil, hasBaseline {
                    fresh.append(ChangeEvent(at: at, type: gained, userId: user.id))
                }
            }
            if hasBaseline {
                for id in before.keys where result[id] == nil {
                    fresh.append(ChangeEvent(at: at, type: lost, userId: id))
                }
            }
            return result
        }
        state.followers = diff(state.followers, followers, gained: .followerGained, lost: .followerLost)
        state.following = diff(state.following, following, gained: .followingAdded, lost: .followingRemoved)
        state.events = Array((fresh + state.events).prefix(maxEvents))
        // La file ne garde que des comptes que je suis encore et qui ne me suivent pas.
        state.queue.removeAll { state.following[$0] == nil || state.followers[$0] != nil }
        return .ok
    }

    /// Un scan automatique par jour ; après un échec, on attend 6 h avant de réessayer.
    static func scanDue(_ state: AppState, now: Date = Date()) -> Bool {
        if let last = state.lastGoodSnapshot, Calendar.current.isDate(last.at, inSameDayAs: now) { return false }
        if let attempt = state.lastAttemptAt, now.timeIntervalSince(attempt) < 6 * 3600 { return false }
        return true
    }
}
