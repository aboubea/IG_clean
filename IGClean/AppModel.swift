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
    /// Secondes restantes pendant une attente (délai entre deux unfollows ou plafond horaire).
    private(set) var countdown: Int?

    let client = InstagramClient()
    private var runnerTask: Task<Void, Never>?

    var isScanning: Bool { scanProgress != nil }

    var cooldownActive: Bool { (state.cooldownUntil ?? .distantPast) > Date() }

    /// Reprise automatique prévue après le plafond du jour, si elle est encore à venir.
    var scheduledResume: Date? {
        guard let date = state.resumeAfter, date > Date() else { return nil }
        return date
    }

    // MARK: Démarrage et connexion

    /// Appelé au lancement et à chaque retour au premier plan : connexion si besoin, scan du jour,
    /// puis reprise d'un nettoyage interrompu par le plafond du jour.
    func refresh() async {
        guard !needsLogin, !isScanning else { return }
        guard await client.hasSession() else {
            needsLogin = true
            return
        }
        if SnapshotEngine.scanDue(state) { await scan() }
        resumeIfDue()
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
        stopRunner(byUser: false)
        await client.logout()
        state = AppState()
        Store.save(state)
        lastError = nil
        runnerStatus = nil
        needsLogin = true
    }

    /// Instagram a refusé la session alors que le cookie existe : il est périmé. On l'efface,
    /// sinon l'écran de connexion se refermerait aussitôt et relancerait une requête, en boucle.
    private func handleLoggedOut() async {
        await client.logout()
        needsLogin = true
    }

    // MARK: Scan

    func scan() async {
        guard !isScanning, !runnerActive, !needsLogin else { return }
        scanProgress = "Connexion à Instagram…"
        updateIdleTimer()
        defer {
            scanProgress = nil
            updateIdleTimer()
        }
        state.lastAttemptAt = Date()
        do {
            let me = try await client.me()
            let followers = try await client.list(userId: me.id, kind: "followers") { count in
                self.scanProgress = "Abonnés : \(count)" + (me.followerCount.map { " / \($0)" } ?? "")
            }
            let following = try await client.list(userId: me.id, kind: "following") { count in
                self.scanProgress = "Abonnements : \(count)" + (me.followingCount.map { " / \($0)" } ?? "")
            }
            state.account = Account(id: me.id, username: me.username ?? state.account?.username ?? "")
            let status = SnapshotEngine.apply(
                to: &state,
                followers: followers,
                following: following,
                expectedFollowers: me.followerCount,
                expectedFollowing: me.followingCount
            )
            lastError = status == .ok
                ? nil
                : "Scan incomplet (\(followers.count)/\(me.followerCount ?? 0) abonnés, \(following.count)/\(me.followingCount ?? 0) abonnements) : il a été ignoré pour ne pas fausser les listes."
        } catch IGError.loggedOut {
            await handleLoggedOut()
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
        stopRunner(byUser: false)
        state.queue = []
        state.batchTotal = nil
        state.resumeAfter = nil
        state.userPaused = false
        runnerStatus = nil
        Store.save(state)
    }

    /// Met les comptes choisis en file et démarre aussitôt.
    func startCleaning(_ ids: Set<String>, pace: Pace) {
        state.settings = pace.settings
        enqueue(ids)
        state.batchTotal = state.queue.count
        Store.save(state)
        startRunner()
    }

    /// Referme l'écran « terminé ».
    func finishBatch() {
        state.batchTotal = nil
        runnerStatus = nil
        Store.save(state)
    }

    // MARK: File d'unfollow

    func startRunner() {
        guard runnerTask == nil, !isScanning, !needsLogin, !cooldownActive, !state.queue.isEmpty else { return }
        runnerActive = true
        lastError = nil
        state.userPaused = false
        state.resumeAfter = nil
        updateIdleTimer()
        runnerTask = Task {
            await runQueue()
            runnerActive = false
            countdown = nil
            runnerTask = nil
            updateIdleTimer()
            Store.save(state)
        }
    }

    /// `byUser` : pause demandée par toi, donc pas de reprise automatique à la prochaine ouverture.
    func stopRunner(byUser: Bool = true) {
        guard let runnerTask else { return }
        runnerTask.cancel()
        if byUser {
            state.userPaused = true
            runnerStatus = "En pause."
            Store.save(state)
        }
    }

    /// Reprend un nettoyage arrêté par le plafond du jour, sauf pause volontaire ou arrêt de sécurité.
    private func resumeIfDue() {
        guard !runnerActive, !needsLogin, !state.queue.isEmpty, !state.userPaused, !cooldownActive else { return }
        if scheduledResume != nil { return }
        startRunner()
    }

    private func updateIdleTimer() {
        // L'écran reste allumé pendant un scan ou un nettoyage : iOS suspend les apps verrouillées.
        UIApplication.shared.isIdleTimerDisabled = isScanning || runnerActive
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return
            }
            let now = Date()
            if let freesAt = state.capFreesAt(cap: state.settings.dailyCap, window: 86400, now: now) {
                state.resumeAfter = freesAt
                runnerStatus = "Plafond du jour atteint."
                return
            }
            if let freesAt = state.capFreesAt(cap: state.settings.hourlyCap, window: 3600, now: now) {
                // L'app est ouverte : on patiente sur place jusqu'à ce qu'un créneau se libère.
                let resumeAt = freesAt.addingTimeInterval(Double.random(in: 5...30))
                guard await wait(until: resumeAt, label: "Plafond horaire atteint · reprise dans") else { return }
                continue
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
                    state.lifetimeUnfollows += 1
                    state.following[userId] = nil
                    state.events.insert(ChangeEvent(at: Date(), type: .followingRemoved, userId: userId), at: 0)
                }
                failures = 0
            } catch IGError.loggedOut {
                runnerStatus = "Session expirée : reconnecte-toi."
                await handleLoggedOut()
                return
            } catch let error as IGError {
                switch error {
                case .rateLimited, .checkpoint:
                    // Premier signe de blocage : arrêt 24 h, et reprise seulement à ta demande.
                    state.cooldownUntil = Date().addingTimeInterval(86400)
                    state.userPaused = true
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
                state.userPaused = true
                lastError = "3 échecs consécutifs : arrêt par sécurité."
                runnerStatus = "Arrêt de sécurité."
                return
            }
            if state.queue.isEmpty { continue }

            let low = state.settings.delayMin
            let high = max(low, state.settings.delayMax)
            let next = Date().addingTimeInterval(Double.random(in: low...high))
            guard await wait(until: next, label: "Prochain dans") else { return }
        }
    }

    /// Attend jusqu'à `date` en affichant le temps restant ; renvoie false si la tâche a été annulée.
    private func wait(until date: Date, label: String) async -> Bool {
        while date.timeIntervalSinceNow > 0 {
            if Task.isCancelled { break }
            let remaining = Int(date.timeIntervalSinceNow.rounded(.up))
            countdown = remaining
            runnerStatus = label + " " + Self.format(seconds: remaining)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        countdown = nil
        return !Task.isCancelled
    }

    private static func format(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }
}
