import Foundation
import WebKit

enum IGError: LocalizedError {
    case loggedOut
    case rateLimited(String)
    case checkpoint
    case http(Int, String)
    case page(String)

    var errorDescription: String? {
        switch self {
        case .loggedOut:
            return "Session Instagram absente ou expirée : reconnecte-toi."
        case .rateLimited(let detail):
            return "Instagram limite temporairement les requêtes. Attends quelques heures avant de réessayer. [\(detail)]"
        case .checkpoint:
            return "Instagram demande une vérification de sécurité : ouvre Instagram et valide-la."
        case .http(let status, let detail):
            return "Instagram a répondu \(status). [\(detail)]"
        case .page(let detail):
            return "Impossible de joindre Instagram : \(detail)"
        }
    }
}

struct Profile {
    let id: String
    /// nil quand Instagram refuse de donner le profil : le scan continue sans ces informations.
    var username: String?
    var followerCount: Int?
    var followingCount: Int?
}

struct Relationship {
    let following: Bool
    let followedBy: Bool
}

/// Parle à Instagram depuis une vue web invisible qui partage la session de l'écran de connexion :
/// les requêtes partent de la page instagram.com elle-même, avec ses cookies, comme le fait le site.
@MainActor
final class InstagramClient: NSObject, WKNavigationDelegate {
    static let origin = URL(string: "https://www.instagram.com/")!
    static let loginURL = URL(string: "https://www.instagram.com/accounts/login/")!
    /// Identifiant public de l'app web Instagram.
    private static let appId = "936619743392459"

    /// Même configuration pour la vue de connexion et la vue de travail : elles partagent les cookies.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        return config
    }

    let webView: WKWebView
    private var ready = false
    private var loadContinuation: CheckedContinuation<Void, Error>?

    override init() {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: Self.makeConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: Session

    private func cookie(_ name: String) async -> String? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.first { $0.name == name && $0.domain.contains("instagram.com") && !$0.value.isEmpty }?.value
    }

    func hasSession() async -> Bool {
        await cookie("sessionid") != nil
    }

    /// À appeler après une (re)connexion : la page de travail sera rechargée avec la nouvelle session.
    func invalidate() {
        ready = false
    }

    func logout() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: records)
        ready = false
    }

    private func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation?.resume(throwing: IGError.page("chargement interrompu"))
            loadContinuation = continuation
            webView.load(URLRequest(url: Self.origin))
        }
        ready = true
    }

    private func finishLoad(_ error: Error?) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error {
            continuation.resume(throwing: IGError.page(error.localizedDescription))
        } else {
            continuation.resume()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
    }

    // MARK: Requêtes

    /// Corps d'une fonction asynchrone exécutée dans la page ; ses paramètres viennent de `arguments`.
    private static let script = """
    if (!window.__igcAppId) {
      const found = document.documentElement.innerHTML.match(/"X-IG-App-ID":"([0-9]+)"/);
      window.__igcAppId = found ? found[1] : appId;
    }
    const headers = { 'X-IG-App-ID': window.__igcAppId, 'X-CSRFToken': csrf, 'X-Requested-With': 'XMLHttpRequest' };
    if (method === 'POST') headers['Content-Type'] = 'application/x-www-form-urlencoded';
    try {
      const r = await fetch(path, { method: method, headers: headers, body: body || undefined, credentials: 'include' });
      return { status: r.status, text: await r.text() };
    } catch (e) {
      return { status: -1, text: String(e) };
    }
    """

    private func call(_ path: String, method: String = "GET", body: String = "") async throws -> [String: Any] {
        guard await hasSession() else { throw IGError.loggedOut }
        if !ready { try await prepare() }
        let csrf = await cookie("csrftoken") ?? ""
        let arguments: [String: Any] = [
            "path": path,
            "method": method,
            "body": body,
            "appId": Self.appId,
            "csrf": csrf,
        ]
        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(Self.script, arguments: arguments, in: nil, contentWorld: .page)
        } catch {
            ready = false
            throw IGError.page(error.localizedDescription)
        }
        guard let result = raw as? [String: Any] else { throw IGError.page("réponse illisible") }
        let status = (result["status"] as? NSNumber)?.intValue ?? -1
        let text = result["text"] as? String ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
        let message = json?["message"] as? String ?? ""
        let lowered = message.lowercased()

        // Détail affiché tel quel dans l'app : endpoint, code HTTP et début de la réponse, pour diagnostiquer.
        let endpoint = path.split(separator: "?").first.map(String.init) ?? path
        let snippet = message.isEmpty ? String(text.prefix(120)) : message
        let detail = "\(endpoint) · HTTP \(status) · \(snippet)"

        if status == -1 { throw IGError.page(text) }
        if status == 401 || lowered.contains("login_required") || json?["require_login"] != nil || (status == 200 && json == nil) {
            throw IGError.loggedOut
        }
        let spam = (json?["spam"] as? NSNumber)?.boolValue ?? false
        if status == 429 || spam || lowered.contains("feedback_required") || lowered.contains("wait a few minutes") {
            throw IGError.rateLimited(detail)
        }
        if lowered.contains("checkpoint") || json?["checkpoint_url"] != nil { throw IGError.checkpoint }
        guard status == 200, let json else {
            throw IGError.http(status, detail)
        }
        return json
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    /// Le profil (nom, compteurs) est facultatif : si Instagram le refuse, on renvoie seulement l'identifiant
    /// et le scan des listes a quand même lieu. Seule une session absente interrompt tout.
    func me() async throws -> Profile {
        guard let id = await cookie("ds_user_id") else { throw IGError.loggedOut }
        do {
            let json = try await call("/api/v1/users/\(id)/info/")
            let user = json["user"] as? [String: Any]
            return Profile(
                id: id,
                username: user?["username"] as? String,
                followerCount: (user?["follower_count"] as? NSNumber)?.intValue,
                followingCount: (user?["following_count"] as? NSNumber)?.intValue
            )
        } catch IGError.loggedOut {
            throw IGError.loggedOut
        } catch {
            return Profile(id: id)
        }
    }

    /// kind : "followers" ou "following"
    func list(userId: String, kind: String, onProgress: (Int) -> Void) async throws -> [IGUser] {
        var seen: [String: IGUser] = [:]
        var maxId: String?
        for _ in 0..<2000 {
            var path = "/api/v1/friendships/\(userId)/\(kind)/?count=50"
            if let maxId, let encoded = maxId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                path += "&max_id=\(encoded)"
            }
            let json = try await call(path)
            let users = json["users"] as? [[String: Any]] ?? []
            for raw in users {
                guard let id = Self.string(raw["pk_id"]) ?? Self.string(raw["pk"]) ?? Self.string(raw["id"]),
                      let username = raw["username"] as? String
                else { continue }
                seen[id] = IGUser(
                    id: id,
                    username: username,
                    fullName: raw["full_name"] as? String ?? "",
                    isPrivate: (raw["is_private"] as? NSNumber)?.boolValue ?? false,
                    isVerified: (raw["is_verified"] as? NSNumber)?.boolValue ?? false
                )
            }
            onProgress(seen.count)
            guard let next = Self.string(json["next_max_id"]), !next.isEmpty, !users.isEmpty else { break }
            maxId = next
            try await Task.sleep(nanoseconds: UInt64.random(in: 1_500_000_000...4_000_000_000))
        }
        return Array(seen.values)
    }

    func relationship(with userId: String) async throws -> Relationship {
        let json = try await call("/api/v1/friendships/show/\(userId)/")
        return Relationship(
            following: (json["following"] as? NSNumber)?.boolValue ?? false,
            followedBy: (json["followed_by"] as? NSNumber)?.boolValue ?? false
        )
    }

    func unfollow(_ userId: String) async throws {
        let json = try await call("/api/v1/friendships/destroy/\(userId)/", method: "POST", body: "user_id=\(userId)")
        let status = json["friendship_status"] as? [String: Any]
        if (status?["following"] as? NSNumber)?.boolValue == true {
            throw IGError.page("Instagram n’a pas appliqué l’unfollow.")
        }
    }
}
