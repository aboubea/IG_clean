import SwiftUI

/** Bilan de la semaine rédigé par l'IA, avec 3 actions, à partager. */
struct RecapScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var error: APIError?
    @State private var loading = false
    @State private var sharing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recap = model.recap {
                        content(recap)
                    } else if let error {
                        if error.upgrade { UpsellCard(message: error.message) } else { BannerCard(message: error.message) { self.error = nil } }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Pulse rédige ton bilan…").foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ton bilan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Régénérer le bilan", systemImage: "arrow.clockwise") { Task { await load(refresh: true) } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(loading)
                }
            }
            .sheet(isPresented: $sharing) {
                if let recap = model.recap, let overview = model.overview {
                    CardShareSheet(title: "Partager mon bilan") {
                        ShareCardView(data: ShareCardData(user: model.user, overview: overview, headline: recap.headline, detail: nil))
                    }
                }
            }
            .task { if model.recap == nil { await load(refresh: false) } }
        }
    }

    private func content(_ recap: Recap) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Kicker("Semaine du \(recap.week)")
            Text(recap.headline).font(.system(size: 28, weight: .heavy))
            Text(recap.summary).font(.body)
            Kicker("3 actions pour la semaine prochaine").padding(.top, 6)
            ForEach(Array(recap.actions.enumerated()), id: \.offset) { index, action in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption).fontWeight(.heavy)
                        .frame(width: 26, height: 26)
                        .background(Theme.lime, in: Circle())
                        .foregroundStyle(Theme.background)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(action.title).font(.headline)
                        Text(action.detail).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    if let network = action.network { NetworkBadge(network: network, size: 24) }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text(recap.source == "claude" ? "✨ Rédigé par IA à partir de tes chiffres" : "Bilan de démonstration, calculé à partir de tes chiffres")
                .font(.caption).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity)
            Button { sharing = true } label: { Label("Partager mon bilan", systemImage: "square.and.arrow.up") }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private func load(refresh: Bool) async {
        loading = true
        defer { loading = false }
        do {
            try await model.loadRecap(refresh: refresh)
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = APIError(status: 0, message: error.localizedDescription, upgrade: false)
        }
    }
}
