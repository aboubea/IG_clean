import SwiftUI

/// L'unique écran de l'app : où tu en es, ce qui a changé, et une seule action.
struct PulseView: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: PulseSheet?

    var body: some View {
        let state = model.state
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    if state.lastGoodSnapshot != nil {
                        hero
                        tiles
                        recentCard
                    } else if !model.isScanning {
                        Card {
                            Text("Aucun scan pour l’instant. Touche la flèche en haut à droite pour lancer le premier : il sert de référence, les changements apparaissent dès le suivant.")
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { callToAction }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Listes", systemImage: "person.2") { sheet = .lists }
                        Button("Historique", systemImage: "clock") { sheet = .history }
                        Button("Se déconnecter et tout effacer", systemImage: "trash", role: .destructive) {
                            Task { await model.logout() }
                        }
                    } label: {
                        Label("Menu", systemImage: "person.circle")
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
            .sheet(item: $sheet) { kind in
                switch kind {
                case .clean: CleanFlowView()
                case .lists: ListsView()
                case .history: HistoryView()
                }
            }
        }
    }

    private var title: String {
        guard let username = model.state.account?.username, !username.isEmpty else { return "IG Clean" }
        return "@\(username)"
    }

    // MARK: Blocs

    @ViewBuilder
    private var statusCard: some View {
        if let progress = model.scanProgress {
            Card {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progress)
                }
            }
        } else if let error = model.lastError {
            Card {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    private var hero: some View {
        let history = followerHistory
        return VStack(alignment: .leading, spacing: 8) {
            Kicker("Tes abonnés")
            Text(model.state.followers.count.formatted())
                .font(.system(size: 68, weight: .heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let delta = monthDelta {
                Text("\(delta >= 0 ? "▲" : "▼") \(abs(delta)) sur 30 jours")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(delta >= 0 ? Theme.lime : Theme.coral)
                    .background(Theme.card, in: Capsule())
            }
            if history.count > 1 {
                ZStack {
                    Sparkline(values: history, closed: true)
                        .fill(LinearGradient(colors: [Theme.lime.opacity(0.3), Theme.lime.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Sparkline(values: history)
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 70)
                .padding(.top, 4)
                .accessibilityHidden(true)
            } else {
                Text("La courbe apparaîtra après quelques scans.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            tile("+\(latestCount(.followerGained))", "nouveaux au dernier scan", Theme.lime)
            tile("−\(latestCount(.followerLost))", "partis au dernier scan", Theme.coral)
            tile("\(model.state.count(in: .nonFollowers))", "ne te suivent pas", Color.white)
        }
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title2)
                .fontWeight(.heavy)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var recentCard: some View {
        let events = Array(model.state.events.prefix(5))
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Kicker("Derniers changements")
                    Spacer()
                    if !events.isEmpty {
                        Button("Tout voir") { sheet = .history }
                            .font(.caption)
                    }
                }
                if events.isEmpty {
                    Text("Rien pour l’instant : les changements apparaîtront au prochain scan.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                ForEach(events) { event in
                    HStack {
                        Text("@\(model.state.users[event.userId]?.username ?? event.userId)")
                            .lineLimit(1)
                        Spacer()
                        Text(event.type.shortLabel)
                            .font(.footnote)
                            .foregroundStyle(event.type.color)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var callToAction: some View {
        let state = model.state
        let pending = state.count(in: .nonFollowers)
        if model.runnerActive || !state.queue.isEmpty || state.batchTotal != nil {
            let total = state.batchTotal ?? state.queue.count
            Button("Nettoyage · \(max(0, total - state.queue.count)) sur \(total)") { sheet = .clean }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        } else if pending > 0 {
            Button(pending > 1 ? "Nettoyer \(pending) comptes" : "Nettoyer 1 compte") { sheet = .clean }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
    }

    // MARK: Chiffres

    /// Nombre d'abonnés à chaque scan réussi, du plus ancien au plus récent (30 derniers).
    private var followerHistory: [Double] {
        let good = model.state.snapshots.filter { $0.status == .ok }.prefix(30)
        return good.reversed().map { Double($0.followers) }
    }

    private var monthDelta: Int? {
        let limit = Date().addingTimeInterval(-30 * 86400)
        let good = model.state.snapshots.filter { $0.status == .ok && $0.at > limit }
        guard good.count > 1, let newest = good.first, let oldest = good.last else { return nil }
        return newest.followers - oldest.followers
    }

    /// Changements détectés par le dernier scan réussi.
    private func latestCount(_ type: EventType) -> Int {
        guard let last = model.state.lastGoodSnapshot else { return 0 }
        return model.state.events.filter { $0.type == type && abs($0.at.timeIntervalSince(last.at)) < 1 }.count
    }
}

enum PulseSheet: String, Identifiable {
    case clean, lists, history

    var id: String { rawValue }
}
