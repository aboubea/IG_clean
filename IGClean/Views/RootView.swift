import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView {
            SummaryView()
                .tabItem { Label("Résumé", systemImage: "chart.bar") }
            CleanView()
                .tabItem { Label("Nettoyage", systemImage: "person.crop.circle.badge.minus") }
                .badge(model.state.count(in: .nonFollowers))
            ListsView()
                .tabItem { Label("Listes", systemImage: "person.2") }
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock") }
        }
        // Vue web de travail : invisible, mais dans la hiérarchie pour que ses requêtes s'exécutent.
        .background(WebViewHost(webView: model.client.webView).frame(width: 1, height: 1).opacity(0))
        .fullScreenCover(isPresented: $model.needsLogin) { LoginView() }
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

/// Avancement du scan et dernière erreur, repris en haut de chaque écran.
struct StatusSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let progress = model.scanProgress {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(progress)
                }
            }
        } else if let error = model.lastError {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        }
    }
}

struct UserLabel: View {
    let user: IGUser

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("@\(user.username)")
                if user.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                        .accessibilityLabel("Compte vérifié")
                }
            }
            if !user.fullName.isEmpty {
                Text(user.fullName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct EventRow: View {
    @Environment(AppModel.self) private var model
    let event: ChangeEvent

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(model.state.users[event.userId]?.username ?? event.userId)")
                Text("\(event.type.label) · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: event.type.symbol)
                .foregroundStyle(color)
        }
    }

    private var color: Color {
        switch event.type {
        case .followerGained: return .green
        case .followerLost: return .red
        case .followingAdded, .followingRemoved: return .secondary
        }
    }
}
