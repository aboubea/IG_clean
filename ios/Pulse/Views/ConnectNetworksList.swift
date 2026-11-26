import AuthenticationServices
import SwiftUI

/** Liste des réseaux avec leur état, et le bouton pour connecter ou retirer chacun. */
struct ConnectNetworksList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var busy: Network?

    var body: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(model.networks) { status in
                    row(status)
                    if status.id != model.networks.last?.id { Divider().overlay(Theme.track) }
                }
            }
        }
    }

    private func row(_ status: NetworkStatus) -> some View {
        HStack(spacing: 12) {
            NetworkBadge(network: status.network)
            VStack(alignment: .leading, spacing: 2) {
                Text(status.label).font(.headline)
                Text(subtitle(status)).font(.caption).foregroundStyle(status.connection?.lastError == nil ? Theme.muted : Theme.coral).lineLimit(2)
            }
            Spacer()
            if busy == status.network {
                ProgressView()
            } else if status.connection != nil {
                Menu {
                    Button("Retirer \(status.label)", role: .destructive) {
                        Task { await model.disconnect(status) }
                    }
                } label: {
                    Label("Connecté", systemImage: "checkmark").font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.lime.opacity(0.15), in: Capsule())
                        .foregroundStyle(Theme.lime)
                }
            } else if status.available {
                Button("Connecter") { connect(status.network) }
                    .font(.caption).fontWeight(.bold)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.lime, in: Capsule())
                    .foregroundStyle(Theme.background)
            } else {
                Text("Bientôt").font(.caption).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 10)
    }

    private func subtitle(_ status: NetworkStatus) -> String {
        if let error = status.connection?.lastError { return error }
        if let connection = status.connection {
            return connection.mode == "demo" ? "Données de démonstration" : "@\(connection.handle)"
        }
        return status.mode == "demo" ? "Mode démo, sans compte réel" : "Connexion officielle"
    }

    private func connect(_ network: Network) {
        busy = network
        Task {
            await model.connect(network) { url, scheme in
                try await webAuthenticationSession.authenticate(using: url, callbackURLScheme: scheme)
            }
            busy = nil
        }
    }
}
