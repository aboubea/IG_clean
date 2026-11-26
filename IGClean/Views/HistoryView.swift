import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var filter: EventType?

    var body: some View {
        let events = model.state.events.filter { filter == nil || $0.type == filter }
        NavigationStack {
            List {
                Section {
                    Picker("Afficher", selection: $filter) {
                        Text("Tous les changements").tag(EventType?.none)
                        ForEach(EventType.allCases) { type in
                            Text(type.label).tag(EventType?.some(type))
                        }
                    }
                }
                Section {
                    if events.isEmpty {
                        Text("Aucun changement enregistré.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(events.prefix(500)) { event in
                        EventRow(event: event)
                    }
                }
                if !model.state.log.isEmpty {
                    Section("Journal des unfollows") {
                        ForEach(model.state.log.prefix(50)) { entry in
                            LabeledContent {
                                Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                            } label: {
                                Text("@\(model.state.users[entry.userId]?.username ?? entry.userId)")
                                Text(label(for: entry))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Historique")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func label(for entry: UnfollowLog) -> String {
        switch entry.status {
        case .done: return "Unfollow fait"
        case .skipped: return "Ignoré : \(entry.detail ?? "")"
        case .error: return "Erreur : \(entry.detail ?? "")"
        }
    }
}
