import SwiftUI

/// Hot Influx : les comptes qui montent, classés par croissance, engagement ou taille.
struct HotInfluxView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var window: GrowthWindow = .d10
    @State private var metric: RankMetric = .growth
    @State private var rows: [InfluencerRow] = []
    @State private var loading = true
    @State private var error: String?

    private let provider: HotInfluxProvider = DemoInfluxProvider()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Critère", selection: $metric) {
                    ForEach(RankMetric.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if metric == .growth {
                    Picker("Fenêtre", selection: $window) {
                        ForEach(GrowthWindow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                }

                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Hot Influx 🔥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
            .task { await reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            Spacer()
            ProgressView("Chargement…")
            Spacer()
        } else if let error {
            Spacer()
            ContentUnavailableView("Indisponible", systemImage: "wifi.slash", description: Text(error))
            Spacer()
        } else {
            List(Array(rows.ranked(by: metric, window: window).enumerated()), id: \.element.id) { index, row in
                InfluencerRowView(rank: index + 1, row: row, window: window, metric: metric)
                    .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
            .safeAreaInset(edge: .bottom) {
                Text("Données de démonstration. Branche un fournisseur pour couvrir tout Instagram.")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .padding(8)
            }
        }
    }

    private func reload() async {
        loading = true
        error = nil
        do {
            rows = try await provider.fetch()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

private struct InfluencerRowView: View {
    let rank: Int
    let row: InfluencerRow
    let window: GrowthWindow
    let metric: RankMetric

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline)
                .foregroundStyle(rank <= 3 ? Theme.lime : Theme.muted)
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(row.username)").fontWeight(.semibold)
                    if row.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue)
                    }
                }
                Text("\(row.category) · \(compact(row.followers)) abonnés")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(highlight)
                    .font(.headline)
                    .foregroundStyle(Theme.lime)
                Text(highlightLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private var highlight: String {
        switch metric {
        case .growth: return "+" + String(format: "%.1f", row.growth(window)) + " %"
        case .engagement: return String(format: "%.1f", row.engagementRate) + " %"
        case .followers: return compact(row.followers)
        }
    }

    private var highlightLabel: String {
        switch metric {
        case .growth: return "sur \(window.rawValue) j"
        case .engagement: return "engagement"
        case .followers: return "abonnés"
        }
    }

    private func compact(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1f M", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0f k", Double(value) / 1_000) }
        return "\(value)"
    }
}
