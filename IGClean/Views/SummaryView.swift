import SwiftUI

struct SummaryView: View {
    @Environment(AppModel.self) private var model

    private let counters: [(String, UserList)] = [
        ("Abonnés", .followers),
        ("Abonnements", .following),
        ("Ne me suivent pas en retour", .nonFollowers),
        ("Je ne les suis pas", .fans),
        ("Mutuels", .mutuals),
    ]

    var body: some View {
        let state = model.state
        NavigationStack {
            List {
                StatusSection()
                if let last = state.lastGoodSnapshot {
                    Section {
                        ForEach(counters, id: \.0) { item in
                            LabeledContent(item.0, value: "\(state.count(in: item.1))")
                        }
                    } footer: {
                        Text("Dernier scan : \(last.at.formatted(date: .abbreviated, time: .shortened))")
                    }
                    Section("7 derniers jours") {
                        ForEach(EventType.allCases) { type in
                            LabeledContent(type.label, value: "\(recentCount(type))")
                        }
                    }
                    Section("Derniers changements") {
                        if state.events.isEmpty {
                            Text("Aucun changement détecté pour l’instant : ils apparaîtront à partir du prochain scan.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(state.events.prefix(10)) { event in
                            EventRow(event: event)
                        }
                    }
                } else if !model.isScanning {
                    Section {
                        Text("Aucun scan pour l’instant. Le premier sert de référence ; les changements apparaissent dès le suivant.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Se déconnecter et tout effacer", role: .destructive) {
                            Task { await model.logout() }
                        }
                    } label: {
                        Label("Compte", systemImage: "person.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label("Scanner maintenant", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning || model.runnerActive)
                }
            }
        }
    }

    private var title: String {
        guard let username = model.state.account?.username, !username.isEmpty else { return "IG Clean" }
        return "@\(username)"
    }

    private func recentCount(_ type: EventType) -> Int {
        let limit = Date().addingTimeInterval(-7 * 86400)
        return model.state.events.filter { $0.type == type && $0.at > limit }.count
    }
}
