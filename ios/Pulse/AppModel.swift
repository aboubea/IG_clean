import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case loading
        case failed(String)
        case onboarding
        case ready
    }

    let api = APIClient()

    private(set) var phase: Phase = .loading
    private(set) var user: User?
    private(set) var networks: [NetworkStatus] = []
    private(set) var overview: Overview?
    private(set) var works: [Int: WhatWorks] = [:]
    private(set) var recap: Recap?
    private(set) var mediaKit: MediaKitInfo?
    private(set) var isRefreshing = false
    /** Dernière erreur à afficher en bandeau. */
    var banner: String?

    // Coach
    private(set) var coachMessages: [CoachMessage] = []
    private(set) var coachQuota: Quota?
    private(set) var coachStreaming = false

    private static let onboardedKey = "pulse.onboarded"

    var hasConnections: Bool { networks.contains { $0.connection != nil } }

    // MARK: Démarrage

    func bootstrap() async {
        phase = .loading
        do {
            if api.token == nil {
                let auth: AuthResponse = try await api.send("POST", "/v1/auth/device")
                api.setToken(auth.token)
            }
            do {
                user = try await api.get("/v1/me")
            } catch let error as APIError where error.status == 401 {
                // Session perdue côté serveur : on repart sur un nouveau compte d'appareil.
                api.setToken(nil)
                let auth: AuthResponse = try await api.send("POST", "/v1/auth/device")
                api.setToken(auth.token)
                user = try await api.get("/v1/me")
            }
            networks = try await api.get("/v1/networks")
            if UserDefaults.standard.bool(forKey: Self.onboardedKey) && hasConnections {
                phase = .ready
                await loadDashboard()
            } else {
                phase = .onboarding
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func completeOnboarding() async {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        phase = .ready
        await loadDashboard()
    }

    // MARK: Données

    func loadDashboard() async {
        guard hasConnections else { return }
        do {
            async let overviewTask: Overview = api.get("/v1/overview")
            async let worksTask: WhatWorks = api.get("/v1/what-works?days=30")
            async let kitTask: MediaKitInfo = api.get("/v1/media-kit")
            overview = try await overviewTask
            works[30] = try await worksTask
            mediaKit = try await kitTask
        } catch {
            banner = error.localizedDescription
        }
    }

    /** Tire pour rafraîchir : relève les chiffres auprès des réseaux, puis recharge. */
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            overview = try await api.send("POST", "/v1/sync")
            networks = try await api.get("/v1/networks")
            works = [:]
            works[30] = try await api.get("/v1/what-works?days=30")
            banner = nil
        } catch {
            banner = error.localizedDescription
        }
    }

    func loadWorks(days: Int) async {
        guard works[days] == nil else { return }
        do {
            works[days] = try await api.get("/v1/what-works?days=\(days)")
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: Réseaux

    /**
     * Connexion d'un réseau. En démo, le serveur connecte tout de suite ; avec un connecteur officiel,
     * il renvoie l'URL d'autorisation du réseau, ouverte par `authorize`.
     */
    func connect(_ network: Network, authorize: (URL, String) async throws -> URL) async {
        do {
            let response: ConnectResponse = try await api.send("POST", "/v1/connections/\(network.rawValue)")
            if response.status == "authorize", let link = response.url.flatMap(URL.init(string:)) {
                let callback = try await authorize(link, response.callbackScheme ?? AppConfig.callbackScheme)
                let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
                if items.first(where: { $0.name == "status" })?.value != "ok" {
                    banner = items.first(where: { $0.name == "message" })?.value ?? "Connexion annulée."
                }
            } else if let syncError = response.syncError {
                banner = syncError
            }
            networks = try await api.get("/v1/networks")
            if phase == .ready { await loadDashboard() }
        } catch {
            banner = error.localizedDescription
        }
    }

    func disconnect(_ status: NetworkStatus) async {
        guard let id = status.connection?.id else { return }
        do {
            try await api.sendWithoutResult("DELETE", "/v1/connections/\(id)")
            networks = try await api.get("/v1/networks")
            overview = nil
            works = [:]
            await loadDashboard()
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: Profil

    func updateProfile(_ fields: [String: Any]) async -> Bool {
        do {
            let updated: User = try await api.send("PATCH", "/v1/me", json: fields)
            user = updated
            mediaKit = try? await api.get("/v1/media-kit")
            return true
        } catch {
            banner = error.localizedDescription
            return false
        }
    }

    func redeemReferral(_ code: String) async -> String {
        do {
            let response: ReferralResponse = try await api.send("POST", "/v1/referral", json: ["code": code])
            user = response.user
            return response.message
        } catch {
            return error.localizedDescription
        }
    }

    func inquiries() async -> [Inquiry] {
        do {
            let list: [Inquiry] = try await api.get("/v1/inquiries")
            mediaKit = try? await api.get("/v1/media-kit")
            return list
        } catch {
            banner = error.localizedDescription
            return []
        }
    }

    func deleteAccount() async {
        do {
            try await api.sendWithoutResult("DELETE", "/v1/me")
        } catch {
            banner = error.localizedDescription
            return
        }
        api.setToken(nil)
        UserDefaults.standard.removeObject(forKey: Self.onboardedKey)
        user = nil
        networks = []
        overview = nil
        works = [:]
        recap = nil
        coachMessages = []
        await bootstrap()
    }

    // MARK: IA

    func loadRecap(refresh: Bool = false) async throws {
        recap = try await api.get(refresh ? "/v1/recap?refresh=1" : "/v1/recap")
    }

    func ideas(_ request: String) async throws -> IdeasResponse {
        let wish = request.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await api.send("POST", "/v1/ideas", json: wish.isEmpty ? [:] : ["request": wish])
    }

    func pretest(caption: String, network: Network?, format: PostFormat?, image: UIImage?) async throws -> PretestResponse {
        var body: [String: Any] = ["caption": caption]
        if let network { body["network"] = network.rawValue }
        if let format { body["format"] = format.rawValue }
        if let data = image.flatMap(Self.jpegForUpload) {
            body["image"] = ["mediaType": "image/jpeg", "data": data.base64EncodedString()]
        }
        return try await api.send("POST", "/v1/pretest", json: body)
    }

    /** Visuel réduit à 1 280 px de côté : assez pour l'analyse, léger à envoyer. */
    private static func jpegForUpload(_ image: UIImage) -> Data? {
        let side: CGFloat = 1280
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    func loadCoach() async {
        do {
            let history: CoachHistory = try await api.get("/v1/coach")
            coachMessages = history.messages
            coachQuota = history.quota
        } catch {
            banner = error.localizedDescription
        }
    }

    /** Envoie une question au coach et affiche sa réponse au fil de l'écriture. */
    func askCoach(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !coachStreaming else { return }
        coachStreaming = true
        defer { coachStreaming = false }
        coachMessages.append(CoachMessage(id: UUID().uuidString, role: "user", content: question, createdAt: Date()))
        let answerId = UUID().uuidString
        coachMessages.append(CoachMessage(id: answerId, role: "assistant", content: "", createdAt: Date()))
        func update(_ change: (inout CoachMessage) -> Void) {
            if let index = coachMessages.firstIndex(where: { $0.id == answerId }) { change(&coachMessages[index]) }
        }
        do {
            for try await event in api.coachStream(question) {
                switch event.type {
                case "delta": update { $0.content += event.text ?? "" }
                case "reset": update { $0.content = "" }
                case "error": update { $0.content = event.error ?? "Le coach n'a pas pu répondre." }
                default: break
                }
            }
            coachQuota = (try? await api.get("/v1/coach") as CoachHistory)?.quota
        } catch {
            update { $0.content = error.localizedDescription }
        }
    }
}

extension AppModel.Phase: Equatable {}
