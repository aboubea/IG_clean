import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {
    private(set) var state = Store.load()
    /// Affiche l'écran de connexion Instagram.
    var needsLogin = false
    /// Texte d'avancement du scan en cours, nil sinon.
    private(set) var scanProgress: String?
    private(set) var lastError: String?
    private(set) var runnerActive = false
    private(set) var runnerStatus: String?

    let client = InstagramClient()
    private var runnerTask: Task<Void, Never>?

    var isScanning: Bool { scanProgress != nil }

    // MARK: Démarrage et connexion

    /// Appelé à chaque retour au premier plan : connexion si besoin, sinon scan du jour.
    func refresh() async {
        guard !needsLogin, !isScanning else { return }
        if await client.hasSession() {
            if SnapshotEngine.scanDue(state) { await scan() }
        } else {
            needsLogin = true
        }
    }

    /// Tourne tant que l'écran de connexion est affiché ; le referme dès que la session existe.
    func waitForLogin() async {
        while needsLogin, !Task.isCancelled {
            if await client.hasSession() {
                client.invalidate()
                needsLogin = false
                // Tâche indépendante : celle de l'écran de connexion est annulée à sa fermeture.
                Task { await scan() }
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    func logout() async {
        stopRunner()
        await client.logout()
        state = AppState()
        Store.save(state)
        needsLogin = true
    }

    // MARK: Scan

    func scan() async {
        guard !isScanning, !runnerActive else { return }
        scanProgress = "Connexion à Instagram…"
        defer { scanProgress = nil }
        state.lastAttemptAt = Date()
        do {
            let me = try await client.me()
            let followers = try await client.list(userId: me.id, kind: "followers") { count in
                self.scanProgress = "Abonnés : \(count) / \(me.followerCount)"
            }
            let following = try await client.list(userId: me.id, kind: "following") { count in
                self.scanProgress = "Abonnements : \(count) / \(me.followingCount)"
            }
            state.account = Account(id: me.id, username: me.username)
            let status = SnapshotEngine.apply(
                to: &state,
                followers: followers,
                following: following,
                expectedFollowers: me.followerCount,
                expectedFollowing: me.followingCount
            )
            lastError = status == .ok
                ? nil
                : "Scan incomplet (\(followers.count)/\(me.followerCount) abonnés, \(following.count)/\(me.followingCount) abonnements) : il a été ignoré pour ne pas fausser les listes."
        } catch IGError.loggedOut {
            needsLogin = true
        } catch {
            lastError = error.localizedDescription
            state.snapshots.insert(Snapshot(at: Date(), status: .error, error: error.localizedDescription), at: 0)
        }
        Store.save(state)
    }

    // MARK: Listes

    func setProtected(_ ids: Set<String>, _ protected: Bool) {
        if protected {
            state.whitelist.formUnion(ids)
            state.queue.removeAll { ids.contains($0) }
        } else {
            state.whitelist.subtract(ids)
        }
        Store.save(state)
    }

    func enqueue(_ ids: Set<String>) {
        let eligible = ids.filter {
            state.following[$0] != nil && state.followers[$0] == nil
                && !state.whitelist.contains($0) && !state.queue.contains($0)
        }
        state.queue.append(contentsOf: eligible.sorted())
        Store.save(state)
    }

    func clearQueue() {
        stopRunner()
        state.queue = []
        Store.save(state)
    }

    func updateSettings(_ change: (inout UnfollowSettings) -> Void) {
        change(&state.settings)
        Store.save(state)
    }

    // MARK: File d'unfollow

    var cooldownActive: Bool {
        if let until = state.cooldownUntil { return until > Date() }
        return false
    }

    func startRunner() {
        guard runnerTask == nil, !isScanning, !cooldownActive, !state.queue.isEmpty else { return }
        runnerActive = true
        lastError = nil
        UIApplication.shared.isIdleTimerDisabled = true // l'écran reste allumé pendant le traitement
        runnerTask = Task {
            await runQueue()
            runnerActive = false
            runnerTask = nil
            UIApplication.shared.isIdleTimerDisabled = false
            Store.save(state)
        }
    }

    func stopRunner() {
        runnerTask?.cancel()
        if runnerActive { runnerStatus = "En pause." }
    }

    private func record(_ userId: String, _ status: UnfollowStatus, _ detail: String? = nil) {
        state.log.insert(UnfollowLog(at: Date(), userId: userId, status: status, detail: detail), at: 0)
        state.log = Array(state.log.prefix(300))
    }

    private func runQueue() async {
        var failures = 0
        while !Task.isCancelled {
            guard let userId = state.queue.first else {
                runnerStatus = "File terminée."
                return
            }
            if state.unfollowsDone(since: 3600) >= state.settings.hourlyCap {
                runnerStatus = "Plafond horaire atteint : reprends dans une heure."
                return
            }
            if state.unfollowsDone(since: 86400) >= state.settings.dailyCap {
                runnerStatus = "Plafond journalier atteint : reprends demain."
                return
            }
            runnerStatus = "Unfollow de @\(state.users[userId]?.username ?? userId)…"
            do {
                // Revérification en direct : on n'unfollow jamais quelqu'un qui s'est (ré)abonné entre-temps.
                let relation = try await client.relationship(with: userId)
                if relation.followedBy {
                    record(userId, .skipped, "te suit désormais")
                    state.followers[userId] = Date()
                } else if !relation.following {
                    record(userId, .skipped, "déjà plus suivi")
                    state.following[userId] = nil
                } else {
                    try await client.unfollow(userId)
                    record(userId, .done)
                    state.following[userId] = nil
                    state.events.insert(ChangeEvent(at: Date(), type: .followingRemoved, userId: userId), at: 0)
                }
                failures = 0
            } catch IGError.loggedOut {
                needsLogin = true
                runnerStatus = "Session expirée."
                return
            } catch let error as IGError {
                switch error {
                case .rateLimited, .checkpoint:
                    // Premier signe de blocage : on arrête tout pendant 24 h.
                    state.cooldownUntil = Date().addingTimeInterval(86400)
                    lastError = error.localizedDescription
                    runnerStatus = "Arrêt de sécurité."
                    return
                default:
                    record(userId, .error, error.localizedDescription)
                    failures += 1
                }
            } catch {
                record(userId, .error, error.localizedDescription)
                failures += 1
            }
            state.queue.removeAll { $0 == userId }
            Store.save(state)
            if failures >= 3 {
                lastError = "3 échecs consécutifs : arrêt par sécurité."
                runnerStatus = "Arrêt de sécurité."
                return
            }
            if state.queue.isEmpty { continue }

            let low = state.settings.delayMin
            let high = max(low, state.settings.delayMax)
            var remaining = Int(Double.random(in: low...high))
            while remaining > 0 {
                if Task.isCancelled { return }
                runnerStatus = "Pause de \(remaining) s avant le prochain unfollow…"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
            }
        }
    }
}
