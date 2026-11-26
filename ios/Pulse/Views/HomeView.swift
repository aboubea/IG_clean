import SwiftUI

/** Accueil : toute l'audience en un coup d'œil, et ce qui mérite d'être fêté. */
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showProfile = false
    @State private var showRecap = false
    @State private var sharing: Milestone?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner = model.banner {
                        BannerCard(message: banner) { model.banner = nil }
                    }
                    if let overview = model.overview {
                        hero(overview)
                        networksCard(overview)
                        if let driver = overview.growthDriver { driverCard(driver) }
                        ForEach(overview.milestones) { milestone in milestoneCard(milestone) }
                    } else if model.hasConnections {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    } else {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Aucun réseau connecté").font(.headline)
                                Text("Connecte au moins un réseau pour voir tes statistiques.").foregroundStyle(Theme.muted)
                                Button("Connecter mes réseaux") { showProfile = true }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .refreshable { await model.refresh() }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if model.overview != nil {
                    Button("Voir mon bilan de la semaine") { showRecap = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Pulse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showProfile = true } label: { Label("Profil", systemImage: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(isPresented: $showRecap) { RecapScreen() }
            .sheet(item: $sharing) { milestone in
                if let overview = model.overview {
                    CardShareSheet(title: "Partager ce palier") {
                        ShareCardView(data: ShareCardData(user: model.user, overview: overview, headline: milestone.label, detail: nil, celebration: true))
                    }
                }
            }
        }
    }

    private func hero(_ overview: Overview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Kicker("Ton audience totale")
            Text(Fmt.number(overview.totalAudience))
                .font(.system(size: 60, weight: .heavy))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text("\(overview.change30d >= 0 ? "▲" : "▼") \(Fmt.number(abs(overview.change30d))) sur 30 jours")
                .font(.caption).fontWeight(.semibold)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .foregroundStyle(overview.change30d >= 0 ? Theme.lime : Theme.coral)
                .background(Theme.card, in: Capsule())
            let values = overview.series.map { Double($0.total) }
            if values.count > 1 {
                ZStack {
                    Sparkline(values: values, closed: true)
                        .fill(LinearGradient(colors: [Theme.lime.opacity(0.3), Theme.lime.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Sparkline(values: values)
                        .stroke(Theme.lime, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                .frame(height: 64)
                .accessibilityHidden(true)
            }
        }
    }

    private func networksCard(_ overview: Overview) -> some View {
        Card {
            VStack(spacing: 0) {
                ForEach(overview.networks) { network in
                    HStack(spacing: 12) {
                        NetworkBadge(network: network.network)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Fmt.number(network.followers)).font(.headline)
                            Text("\(network.label) · engagement \(Fmt.percent(network.engagementRate))")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Fmt.percent(network.change30dPct, signed: true))
                                .font(.headline)
                                .foregroundStyle(network.change30d >= 0 ? Theme.lime : Theme.coral)
                            Text("30 j").font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if network.id != overview.networks.last?.id { Divider().overlay(Theme.track) }
                }
            }
        }
    }

    private func driverCard(_ driver: Overview.Driver) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(driver.label) porte ta croissance").font(.headline).foregroundStyle(Theme.lime)
            Text("\(driver.share) % de tes nouveaux abonnés ce mois viennent de là.").font(.subheadline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func milestoneCard(_ milestone: Milestone) -> some View {
        Card {
            HStack(spacing: 12) {
                Text(milestone.kind == "record" ? "🚀" : "🎉").font(.title)
                Text(milestone.label).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                Button { sharing = milestone } label: { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Partager ce palier")
            }
        }
    }
}
