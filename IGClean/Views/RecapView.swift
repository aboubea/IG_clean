import SwiftUI
import UIKit

/// Aperçu du bilan + partage : l'image pour une story, ou un texte pour défier un ami.
struct RecapView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var imageURL: URL?

    var body: some View {
        let stats = model.state.stats
        let username = model.state.account?.username ?? ""
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ShareCardView(username: username, stats: stats)
                        .frame(width: ShareCardView.size.width, height: ShareCardView.size.height)
                        .scaleEffect(0.62)
                        .frame(width: ShareCardView.size.width * 0.62, height: ShareCardView.size.height * 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(radius: 20, y: 10)
                        .padding(.top, 12)

                    VStack(spacing: 10) {
                        if let imageURL {
                            ShareLink(item: imageURL, preview: SharePreview("Mon bilan IG Clean", image: Image(systemName: "chart.bar"))) {
                                Label("Partager l’image", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 17)
                        }
                        ShareLink(item: challenge(stats: stats)) {
                            Label("Défier un ami", systemImage: "bolt.fill")
                        }
                        .buttonStyle(GhostButtonStyle())
                    }
                    .padding(.horizontal, 20)

                    Text("Poste l’image en story : tes abonnés découvrent l’app sans que tu aies rien d’autre à faire.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Mon bilan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { imageURL = render(username: username, stats: stats) }
        }
    }

    private func challenge(stats: Stats) -> String {
        "J’ai \(stats.followers) abonnés et \(stats.mutualPercent) % de vrais mutuels sur Instagram. Et toi, t’es à combien ? (vu avec IG Clean)"
    }

    /// Rend la carte en PNG dans un fichier temporaire, à partager tel quel.
    @MainActor
    private func render(username: String, stats: Stats) -> URL? {
        let renderer = ImageRenderer(content: ShareCardView(username: username, stats: stats))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ig-clean-bilan.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
