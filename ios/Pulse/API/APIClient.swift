import Foundation
import Security

enum AppConfig {
    /** Serveur par défaut : le Mac qui fait tourner `npm run dev` (simulateur). */
    static let defaultServer = "http://localhost:8787"
    static let callbackScheme = "pulse"
    private static let serverKey = "pulse.server"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverKey) ?? defaultServer }
        set { UserDefaults.standard.set(newValue, forKey: serverKey) }
    }
}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    /** Limite gratuite atteinte : proposer Premium ou le parrainage. */
    let upgrade: Bool

    var errorDescription: String? { message }
}

/** Jeton de session dans le trousseau iOS, jamais dans les préférences. */
enum Keychain {
    private static let service = "app.pulse.session"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard let token else { return }
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor
final class APIClient {
    private(set) var token: String? = Keychain.read()

    func setToken(_ token: String?) {
        self.token = token
        Keychain.write(token)
    }

    private func makeRequest(_ method: String, _ path: String, json: [String: Any]? = nil) throws -> URLRequest {
        guard let url = URL(string: AppConfig.serverURL + path) else {
            throw APIError(status: 0, message: "Adresse du serveur invalide.", upgrade: false)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 120
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    private func failure(status: Int, data: Data) -> APIError {
        if let body = try? JSONCoding.decoder.decode(ErrorResponse.self, from: data) {
            return APIError(status: status, message: body.error, upgrade: body.upgrade ?? false)
        }
        return APIError(status: status, message: "Le serveur a répondu \(status).", upgrade: false)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError(status: 0, message: "Serveur injoignable (\(AppConfig.serverURL)).", upgrade: false)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw failure(status: status, data: data) }
        return data
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONCoding.decoder.decode(T.self, from: await perform(makeRequest("GET", path)))
    }

    func send<T: Decodable>(_ method: String, _ path: String, json: [String: Any] = [:]) async throws -> T {
        try JSONCoding.decoder.decode(T.self, from: await perform(makeRequest(method, path, json: json)))
    }

    func sendWithoutResult(_ method: String, _ path: String) async throws {
        _ = try await perform(makeRequest(method, path))
    }

    /** Réponse du coach en flux (Server-Sent Events). */
    func coachStream(_ message: String) -> AsyncThrowingStream<CoachStreamEvent, Error> {
        let request = Result { try makeRequest("POST", "/v1/coach", json: ["message": message]) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request.get())
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if status != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw failure(status: status, data: data)
                    }
                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        let event = try JSONCoding.decoder.decode(CoachStreamEvent.self, from: Data(line.dropFirst(6).utf8))
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
