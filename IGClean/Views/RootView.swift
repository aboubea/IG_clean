import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        PulseView()
            // Vue web de travail : invisible, mais dans la hiérarchie pour que ses requêtes s'exécutent.
            .background(WebViewHost(webView: model.client.webView).frame(width: 1, height: 1).opacity(0))
            .fullScreenCover(isPresented: $model.needsLogin) { LoginView() }
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.lime)
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
                .foregroundStyle(event.type.color)
        }
    }
}

extension EventType {
    var color: Color {
        switch self {
        case .followerGained: return Theme.lime
        case .followerLost: return Theme.coral
        case .followingAdded, .followingRemoved: return Theme.muted
        }
    }

    /// Formulation courte pour l'accueil.
    var shortLabel: String {
        switch self {
        case .followerGained: return "t’a rejoint"
        case .followerLost: return "est parti"
        case .followingAdded: return "tu le suis"
        case .followingRemoved: return "tu ne le suis plus"
        }
    }
}
