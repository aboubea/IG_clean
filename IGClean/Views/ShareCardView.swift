import SwiftUI

/// Carte de bilan au format story (9:16), dessinée en points puis rendue en image à l'échelle 3.
struct ShareCardView: View {
    let username: String
    let stats: Stats
    var date = Date()

    /// Taille logique ; l'image exportée fait 3×, soit 1080 × 1920.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(username.isEmpty ? "mon compte" : "@\(username)")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("IG CLEAN")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.lime)
            }

            Spacer()

            Text("Abonnés".uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.muted)
            Text(stats.followers.formatted())
                .font(.system(size: 92, weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if stats.weekGained + stats.weekLost > 0 {
                Text("+\(stats.weekGained) · −\(stats.weekLost) cette semaine")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.lime)
            }

            Spacer()

            HStack(spacing: 10) {
                metric("\(stats.mutualPercent) %", "de mutuels")
                metric("\(stats.nonFollowers)", "ne te suivent pas")
                metric("\(stats.cleaned)", "nettoyés")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(stats.health.color)
                    .frame(width: 9, height: 9)
                Text(stats.health.label)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                if stats.scanStreak > 1 {
                    Text("· série de \(stats.scanStreak) jours 🔥")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(Theme.background)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
