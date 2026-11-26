import SwiftUI
import UIKit

enum Fmt {
    private static let french = Locale(identifier: "fr_FR")

    static func number(_ value: Int) -> String { value.formatted(.number.locale(french)) }

    static func signed(_ value: Int) -> String { value >= 0 ? "+\(number(value))" : "−\(number(abs(value)))" }

    static func percent(_ value: Double, signed: Bool = false) -> String {
        let text = abs(value).formatted(.number.precision(.fractionLength(1)).locale(french))
        let sign = signed ? (value >= 0 ? "+" : "−") : (value < 0 ? "−" : "")
        return "\(sign)\(text)\u{00a0}%"
    }

    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return (Double(value) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(french)) + "\u{00a0}M" }
        if value >= 10_000 { return "\(value / 1000)\u{00a0}k" }
        return number(value)
    }
}

/** Pastille de réseau : couleurs et initiales, sans reproduire de logo officiel. */
struct NetworkBadge: View {
    let network: Network
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(fill)
            .overlay {
                if network == .tiktok {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).stroke(Color.cyan, lineWidth: 1.5)
                }
            }
            .overlay(Text(network.initials).font(.system(size: size * 0.36, weight: .heavy)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityLabel(network.label)
    }

    private var fill: AnyShapeStyle {
        switch network {
        case .instagram:
            return AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .tiktok: return AnyShapeStyle(Color.black)
        case .facebook: return AnyShapeStyle(Color(red: 0.09, green: 0.47, blue: 0.95))
        case .linkedin: return AnyShapeStyle(Color(red: 0.04, green: 0.4, blue: 0.76))
        }
    }
}

/** Bandeau d'erreur refermable. */
struct BannerCard: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.coral)
                Text(message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) { Image(systemName: "xmark").font(.caption) }
                    .accessibilityLabel("Fermer")
            }
        }
    }
}

/** Limite gratuite atteinte : Premium, ou un mois offert en parrainant un ami. */
struct UpsellCard: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Limite gratuite atteinte", systemImage: "sparkles").font(.headline).foregroundStyle(Theme.lime)
                Text(message).font(.subheadline).foregroundStyle(Theme.muted)
                Text("Premium débloque le coach, le pré-test et les idées sans limite. En attendant, invite un ami : vous gagnez chacun un mois de Premium.")
                    .font(.subheadline)
                if let code = model.user?.referralCode {
                    ShareLink(item: Invite.text(code: code)) {
                        Label("Inviter un ami", systemImage: "gift")
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}

enum Invite {
    static func text(code: String) -> String {
        "Je suis mes réseaux avec Pulse : tous mes chiffres au même endroit et un coach IA. Avec mon code \(code), on gagne chacun un mois de Premium."
    }
}

/** Partage d'une carte en image : rendue en PNG au format story, prête pour Instagram, TikTok ou Messages. */
struct CardShareSheet<CardContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let card: CardContent
    @State private var file: URL?
    @State private var preview: UIImage?

    init(title: String, @ViewBuilder card: () -> CardContent) {
        self.title = title
        self.card = card()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    card
                        .frame(width: ShareCardView.size.width, height: ShareCardView.size.height)
                        .scaleEffect(0.62)
                        .frame(width: ShareCardView.size.width * 0.62, height: ShareCardView.size.height * 0.62)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(radius: 20, y: 10)
                        .padding(.top, 12)
                    if let file, let preview {
                        ShareLink(item: file, preview: SharePreview(title, image: Image(uiImage: preview))) {
                            Label("Partager l’image", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                    } else {
                        ProgressView()
                    }
                    Text("Poste-la en story : ton audience découvre Pulse sans que tu aies rien d’autre à faire.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Fermer") { dismiss() } }
            }
            .task { render() }
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: card.frame(width: ShareCardView.size.width, height: ShareCardView.size.height))
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-\(UUID().uuidString.prefix(8)).png")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        preview = image
        file = url
    }
}
