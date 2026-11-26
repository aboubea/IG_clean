import SwiftUI

/** Ce qui marche : formats, créneaux, meilleurs posts. */
struct AnalysisView: View {
    @Environment(AppModel.self) private var model
    @State private var days = 30
    @State private var showInflux = false
    private let weekdays = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Période", selection: $days) {
                        Text("7 jours").tag(7)
                        Text("30 jours").tag(30)
                        Text("90 jours").tag(90)
                    }
                    .pickerStyle(.segmented)
                    if let works = model.works[days] {
                        if works.postCount == 0 {
                            Card { Text("Aucune publication sur cette période.").foregroundStyle(Theme.muted) }
                        } else {
                            formats(works)
                            heat(works)
                            topPosts(works)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ce qui marche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showInflux = true } label: { Label("Hot Influx", systemImage: "flame") }
                }
            }
            .sheet(isPresented: $showInflux) { HotInfluxView() }
            .task(id: days) { await model.loadWorks(days: days) }
        }
    }

    private func formats(_ works: WhatWorks) -> some View {
        let top = works.formats.first?.engagementRate ?? 1
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Engagement par format")
                ForEach(works.formats) { format in
                    HStack(spacing: 10) {
                        Text(format.label).font(.subheadline).frame(width: 104, alignment: .leading)
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(Theme.lime).frame(width: proxy.size.width * CGFloat(top > 0 ? format.engagementRate / top : 0))
                            }
                        }
                        .frame(height: 8)
                        Text(Fmt.percent(format.engagementRate)).font(.subheadline).fontWeight(.bold).frame(width: 60, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func heat(_ works: WhatWorks) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Quand publier")
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    GridRow {
                        Text("")
                        ForEach(0..<7, id: \.self) { day in
                            Text(weekdays[day]).font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(works.slotStarts.enumerated()), id: \.offset) { slot, start in
                        GridRow {
                            Text("\(start) h").font(.caption2).foregroundStyle(Theme.muted)
                            ForEach(0..<7, id: \.self) { day in
                                let value = works.heat.indices.contains(day) && works.heat[day].indices.contains(slot) ? works.heat[day][slot] : nil
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(value == nil ? Theme.track : Theme.lime.opacity(0.12 + 0.88 * (value ?? 0)))
                                    .frame(height: 16)
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
                if let best = works.bestSlot {
                    (Text("Ton meilleur créneau : ").foregroundStyle(Theme.muted) + Text(best.label).foregroundStyle(Theme.lime).bold())
                        .font(.subheadline)
                }
            }
        }
    }

    private func topPosts(_ works: WhatWorks) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Kicker("Top publications")
                ForEach(works.topPosts) { post in
                    let row = HStack(spacing: 12) {
                        NetworkBadge(network: post.network, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.caption).font(.subheadline).lineLimit(2).foregroundStyle(Color.primary)
                            Text("\(post.formatLabel) · \(Fmt.percent(post.engagementRate))\(post.views.map { " · \(Fmt.compact($0)) vues" } ?? "")")
                                .font(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }
                    if let link = post.permalink.flatMap(URL.init(string:)) {
                        Link(destination: link) { row }
                    } else {
                        row
                    }
                }
            }
        }
    }
}
