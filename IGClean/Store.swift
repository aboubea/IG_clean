import Foundation

/// Persistance : un fichier JSON dans Application Support, sur l'appareil uniquement.
enum Store {
    private static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL { directory.appendingPathComponent("state.json") }

    static func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL) else { return AppState() }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            // Fichier illisible : on le met de côté plutôt que de l'écraser au prochain enregistrement.
            let backup = directory.appendingPathComponent("state-\(Int(Date().timeIntervalSince1970)).unreadable.json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return AppState()
        }
    }

    static func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
