import SwiftUI

/// Nettoyage en trois temps : choisir des groupes, suivre l'anneau, voir le résultat.
struct CleanFlowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.runnerActive || !model.state.queue.isEmpty {
                    CleanProgressView()
                } else if model.state.batchTotal != nil {
                    CleanDoneView()
                } else {
                    CleanSetupView()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

// MARK: 1. Choix des groupes

private struct CleanSetupView: View {
    @Environment(AppModel.self) private var model
    @State private var enabled: Set<CleanGroup> = [.old, .recent]
    @State private var pace: Pace = .normal

    var body: some View {
        let selection = selectedIds
        let pending = model.state.count(in: .nonFollowers)
        let heading: String = pending == 1 ? "1 compte ne te suit pas" : "\(pending) comptes ne te suivent pas"
        let launchLabel: String = selection.isEmpty ? "Lancer le nettoyage" : "Lancer le nettoyage · \(selection.count)"
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(heading)
                        .font(.title)
                        .fontWeight(.heavy)
                    Text("Choisis par groupes. Ouvre un groupe pour garder quelqu’un.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    ForEach(model.state.cleanGroups) { group in
                        groupCard(group)
                    }
                    paceCard(count: selection.count)
                }
                .padding(20)
            }
            Button(launchLabel) {
                model.startCleaning(selection, pace: pace)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selection.isEmpty)
            .opacity(selection.isEmpty ? 0.4 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear { pace = Pace.matching(model.state.settings) }
    }

    /// Comptes des groupes activés, hors comptes gardés.
    private var selectedIds: Set<String> {
        var ids: Set<String> = []
        for group in model.state.cleanGroups where enabled.contains(group) {
            for user in model.state.cleanCandidates(group) where !model.state.whitelist.contains(user.id) {
                ids.insert(user.id)
            }
        }
        return ids
    }

    @ViewBuilder
    private func groupCard(_ group: CleanGroup) -> some View {
        let users = model.state.cleanCandidates(group)
        let kept = users.filter { model.state.whitelist.contains($0.id) }.count
        let title = model.state.title(for: group)
        let detail = plural(users.count, "compte") + " · " + (kept > 0 ? plural(kept, "gardé") : model.state.hint(for: group))
        if !users.isEmpty {
            Card {
                HStack(spacing: 12) {
                    NavigationLink {
                        CleanGroupDetailView(group: group)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(title)
                                    .font(.headline)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(detail)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Toggle(title, isOn: binding(for: group))
                        .labelsHidden()
                        .tint(Theme.lime)
                }
            }
        }
    }

    /// Durée estimée : au-delà du plafond horaire, l'app attend sur place ; au-delà du plafond du jour,
    /// elle reprend le lendemain à l'ouverture.
    static func duration(count: Int, settings: UnfollowSettings) -> String {
        guard count > 0 else { return "rien à faire" }
        if count > settings.dailyCap {
            let days = Int((Double(count) / Double(settings.dailyCap)).rounded(.up))
            return "environ \(days) jours (\(settings.dailyCap) par jour max), app ouverte"
        }
        if count > settings.hourlyCap {
            let hours = Int((Double(count) / Double(settings.hourlyCap)).rounded(.up))
            return "environ \(hours) h, app ouverte"
        }
        let minutes = max(1, Int(Double(count) * (settings.delayMin + settings.delayMax) / 2 / 60))
        return "environ \(minutes) min, app ouverte"
    }

    private func binding(for group: CleanGroup) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(group) },
            set: { isOn in
                if isOn {
                    enabled.insert(group)
                } else {
                    enabled.remove(group)
                }
            }
        )
    }

    private func paceCard(count: Int) -> some View {
        let estimate = plural(count, "compte") + " · " + Self.duration(count: count, settings: pace.settings)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Rythme")
                HStack(spacing: 8) {
                    ForEach(Pace.allCases) { option in
                        Button {
                            pace = option
                        } label: {
                            Text(option.label)
                                .font(.footnote)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(pace == option ? Theme.background : Theme.muted)
                                .background(pace == option ? Theme.lime : Theme.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(estimate)
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                if pace == .fast {
                    Text("Rapide augmente le risque qu’Instagram limite ton compte.")
                        .font(.footnote)
                        .foregroundStyle(Theme.coral)
                }
            }
        }
    }
}

private struct CleanGroupDetailView: View {
    @Environment(AppModel.self) private var model
    let group: CleanGroup

    var body: some View {
        List(model.state.cleanCandidates(group)) { user in
            let kept = model.state.whitelist.contains(user.id)
            Button {
                model.setProtected([user.id], !kept)
            } label: {
                HStack {
                    UserLabel(user: user)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Text(kept ? "Gardé" : "À retirer")
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(kept ? Theme.lime : Theme.muted)
                }
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(model.state.title(for: group))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 2. Avancement

private struct CleanProgressView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.state
        let total = max(state.batchTotal ?? state.queue.count, 1)
        let done = max(0, total - state.queue.count)
        VStack(spacing: 14) {
            Kicker(kicker)
                .padding(.top, 12)
            ZStack {
                Circle()
                    .stroke(Theme.track, lineWidth: 16)
                Circle()
                    .trim(from: 0, to: CGFloat(done) / CGFloat(total))
                    .stroke(Theme.lime, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(done)")
                        .font(.system(size: 54, weight: .heavy))
                    Text("sur \(total)")
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 220, height: 220)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) unfollows faits sur \(total)")

            Text(model.runnerStatus ?? "Prêt à reprendre.")
                .font(.headline)
                .multilineTextAlignment(.center)
            if !model.runnerActive, let resume = model.scheduledResume {
                Text("Plafond du jour atteint. Le nettoyage reprend tout seul quand tu rouvres l’app après \(resume.formatted(date: .omitted, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if model.runnerActive {
                Text("Garde l’app ouverte : iOS met les apps en pause en arrière-plan.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if let error = model.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center)
            }
            if model.cooldownActive, let until = state.cooldownUntil {
                Text("Pause de sécurité jusqu’au \(until.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.footnote)
                    .foregroundStyle(Theme.coral)
            }

            if !state.log.isEmpty {
                Card {
                    VStack(spacing: 10) {
                        ForEach(state.log.prefix(4)) { entry in
                            HStack {
                                Text("@\(state.users[entry.userId]?.username ?? entry.userId)")
                                    .lineLimit(1)
                                Spacer()
                                Text(label(for: entry))
                                    .font(.footnote)
                                    .foregroundStyle(entry.status == .done ? Theme.lime : Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            Spacer()
            if model.runnerActive {
                Button("Mettre en pause") { model.stopRunner() }
                    .buttonStyle(GhostButtonStyle())
            } else {
                let blocked = model.cooldownActive || model.isScanning || model.scheduledResume != nil
                Button("Reprendre") { model.startRunner() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(blocked)
                    .opacity(blocked ? 0.4 : 1)
                Button("Annuler le nettoyage", role: .destructive) { model.clearQueue() }
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var kicker: String {
        if model.runnerActive { return "Nettoyage en cours" }
        if model.scheduledResume != nil { return "Reprise prévue" }
        return "Nettoyage en pause"
    }

    private func label(for entry: UnfollowLog) -> String {
        switch entry.status {
        case .done: return "✓ fait"
        case .skipped: return "épargné : \(entry.detail ?? "")"
        case .error: return "erreur"
        }
    }
}

// MARK: 3. Terminé

private struct CleanDoneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let total = model.state.batchTotal ?? 0
        let summary = total > 1 ? "\(total) comptes traités." : "\(total) compte traité."
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.lime)
            Text("C’est fait")
                .font(.largeTitle)
                .fontWeight(.heavy)
            Text(summary + " Le détail est dans l’historique.")
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Terminer") {
                model.finishBatch()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
