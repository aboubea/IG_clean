import Foundation

/// Persistance : un fichier JSON dans Application Support, sur l'appareil uniquement.
enum Store {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    static func load() -> AppState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data)
        else { return AppState() }
        return state
    }

    static func save(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
