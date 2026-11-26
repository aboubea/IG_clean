import SwiftUI

struct CleanView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var query = ""

    var body: some View {
        let state = model.state
        let users = filteredUsers
        let selectable = users.filter { isSelectable($0) }
        NavigationStack {
            List {
                StatusSection()

                Section {
                    LabeledContent("En attente", value: "\(state.queue.count)")
                    LabeledContent("Faits sur 1 h", value: "\(state.unfollowsDone(since: 3600)) / \(state.settings.hourlyCap)")
                    LabeledContent("Faits sur 24 h", value: "\(state.unfollowsDone(since: 86400)) / \(state.settings.dailyCap)")
                    if let status = model.runnerStatus {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if model.cooldownActive, let until = state.cooldownUntil {
                        Text("Pause de sécurité jusqu’au \(until.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Button(model.runnerActive ? "Mettre en pause" : "Démarrer") {
                        if model.runnerActive {
                            model.stopRunner()
                        } else {
                            model.startRunner()
                        }
                    }
                    .disabled(!model.runnerActive && (state.queue.isEmpty || model.isScanning || model.cooldownActive))
                    Button("Vider la file", role: .destructive) {
                        model.clearQueue()
                    }
                    .disabled(state.queue.isEmpty)
                } header: {
                    Text("File d’unfollow")
                } footer: {
                    Text("Garde l’app ouverte pendant le traitement : iOS suspend les apps en arrière-plan. Chaque compte est revérifié juste avant l’unfollow.")
                }

                Section {
                    Stepper("Maximum par heure : \(state.settings.hourlyCap)", value: hourlyCap, in: 1...60)
                    Stepper("Maximum par 24 h : \(state.settings.dailyCap)", value: dailyCap, in: 10...300, step: 10)
                } header: {
                    Text("Rythme")
                } footer: {
                    Text("Augmenter ces valeurs accélère le nettoyage mais augmente le risque de blocage par Instagram.")
                }

                Section {
                    Button(selected.isEmpty ? "Tout sélectionner" : "Tout désélectionner") {
                        selected = selected.isEmpty ? Set(selectable.map(\.id)) : []
                    }
                    .disabled(selectable.isEmpty)
                    Button("Ajouter \(selected.count) à la file") {
                        model.enqueue(selected)
                        selected = []
                    }
                    .disabled(selected.isEmpty)
                    Button("Protéger \(selected.count) (ne jamais unfollow)") {
                        model.setProtected(selected, true)
                        selected = []
                    }
                    .disabled(selected.isEmpty)
                }

                Section("Ne me suivent pas en retour (\(users.count))") {
                    ForEach(users) { user in
                        row(user)
                    }
                }
            }
            .searchable(text: $query, prompt: "Rechercher")
            .navigationTitle("Nettoyage")
        }
    }

    private var filteredUsers: [IGUser] {
        let all = model.state.users(in: .nonFollowers)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return all }
        return all.filter { $0.username.lowercased().contains(needle) || $0.fullName.lowercased().contains(needle) }
    }

    private func isSelectable(_ user: IGUser) -> Bool {
        !model.state.whitelist.contains(user.id) && !model.state.queue.contains(user.id)
    }

    private func row(_ user: IGUser) -> some View {
        let isProtected = model.state.whitelist.contains(user.id)
        let isQueued = model.state.queue.contains(user.id)
        let isSelected = selected.contains(user.id)
        return Button {
            if isSelected {
                selected.remove(user.id)
            } else {
                selected.insert(user.id)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                UserLabel(user: user)
                    .foregroundStyle(Color.primary)
                Spacer()
                if isProtected {
                    Text("Protégé")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if isQueued {
                    Text("Dans la file")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isProtected || isQueued)
        .swipeActions {
            Button(isProtected ? "Ne plus protéger" : "Protéger") {
                model.setProtected([user.id], !isProtected)
                selected.remove(user.id)
            }
            .tint(isProtected ? Color.gray : Color.green)
        }
    }

    private var hourlyCap: Binding<Int> {
        Binding(
            get: { model.state.settings.hourlyCap },
            set: { value in model.updateSettings { $0.hourlyCap = value } }
        )
    }

    private var dailyCap: Binding<Int> {
        Binding(
            get: { model.state.settings.dailyCap },
            set: { value in model.updateSettings { $0.dailyCap = value } }
        )
    }
}
