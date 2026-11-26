import SwiftUI

struct NetworkCount: Identifiable {
    let network: Network
    let followers: Int
    var id: String { network.rawValue }
}

/** Données d'une carte à partager : bilan de la semaine ou palier franchi. */
struct ShareCardData {
    var name: String
    var totalAudience: Int
    var weekChange: Int
    var networks: [NetworkCount]
    /** Grand titre : le palier franchi ou le titre du bilan. */
    var headline: String
    var detail: String?
    var celebration = false
}

extension ShareCardData {
    init(user: User?, overview: Overview, headline: String, detail: String?, celebration: Bool = false) {
        self.init(
            name: user?.displayName ?? "Mon bilan",
            totalAudience: overview.totalAudience,
            weekChange: overview.change7d,
            networks: overview.networks.map { NetworkCount(network: $0.network, followers: $0.followers) },
            headline: headline,
            detail: detail,
            celebration: celebration
        )
    }
}

/** Carte au format story (9:16), dessinée en points puis exportée à l'échelle 3 (1080 × 1920). */
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 640)
    let data: ShareCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(data.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text("PULSE").font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(Theme.lime)
            }
            Spacer()
            if data.celebration {
                Text("🎉").font(.system(size: 54))
            }
            Text(data.headline)
                .font(.system(size: data.celebration ? 40 : 30, weight: .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
            if let detail = data.detail {
                Text(detail).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted).padding(.top, 8)
            }
            Spacer()
            Text("Audience totale".uppercased()).font(.system(size: 12, weight: .semibold)).tracking(1).foregroundStyle(Theme.muted)
            Text(Fmt.number(data.totalAudience)).font(.system(size: 64, weight: .heavy)).foregroundStyle(.white).minimumScaleFactor(0.5).lineLimit(1)
            if data.weekChange != 0 {
                Text("\(Fmt.signed(data.weekChange)) cette semaine").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(data.weekChange > 0 ? Theme.lime : Theme.coral)
            }
            HStack(spacing: 8) {
                ForEach(Array(data.networks.prefix(4))) { item in
                    HStack(spacing: 6) {
                        NetworkBadge(network: item.network, size: 22)
                        Text(Fmt.compact(item.followers)).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.card, in: Capsule())
                }
            }
            .padding(.top, 18)
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .leading)
        .background(Theme.background)
    }
}
