import PhotosUI
import SwiftUI
import UIKit

/** Créer : tester un contenu avant de le publier, ou trouver quoi publier. */
struct CreateView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case pretest = "Pré-test"
        case ideas = "Idées"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .pretest

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch mode {
                    case .pretest: PretestPanel()
                    case .ideas: IdeasPanel()
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Créer")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct PretestPanel: View {
    @Environment(AppModel.self) private var model
    @State private var caption = ""
    @State private var network: Network?
    @State private var format: PostFormat?
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var result: PretestResponse?
    @State private var error: APIError?
    @State private var loading = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Teste ton post avant de le publier").font(.title2).fontWeight(.heavy)
            Text("Pulse le compare à ce qui marche chez toi et te dit comment l’améliorer.").font(.subheadline).foregroundStyle(Theme.muted)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Group {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus").font(.title)
                            Text("Ajouter le visuel (facultatif)").font(.subheadline)
                        }
                        .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { image = UIImage(data: data) }
                }
            }

            TextField("Ta légende", text: $caption, axis: .vertical)
                .lineLimit(3...8)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Picker("Réseau", selection: $network) {
                    Text("Réseau : auto").tag(Network?.none)
                    ForEach(Network.allCases) { Text($0.label).tag(Network?.some($0)) }
                }
                Picker("Format", selection: $format) {
                    Text("Format : auto").tag(PostFormat?.none)
                    ForEach(PostFormat.allCases) { Text($0.label).tag(PostFormat?.some($0)) }
                }
            }
            .pickerStyle(.menu)

            Button(loading ? "Analyse en cours…" : "Tester mon post") { Task { await run() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading || (caption.trimmingCharacters(in: .whitespaces).isEmpty && image == nil))

            if let error {
                if error.upgrade { UpsellCard(message: error.message) } else { BannerCard(message: error.message) { self.error = nil } }
            }
            if let result { resultView(result) }
        }
    }

    private func run() async {
        loading = true
        defer { loading = false }
        do {
            result = try await model.pretest(caption: caption, network: network, format: format, image: image)
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = APIError(status: 0, message: error.localizedDescription, upgrade: false)
        }
    }

    private func resultView(_ result: PretestResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(Theme.track, lineWidth: 8)
                        Circle().trim(from: 0, to: result.score / 100)
                            .stroke(scoreColor(result.score), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(result.score))").font(.title2).fontWeight(.heavy)
                    }
                    .frame(width: 72, height: 72)
                    .accessibilityLabel("Score \(Int(result.score)) sur 100")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.verdict).font(.headline)
                        Label("\(result.bestNetwork.label) · \(result.bestTime)", systemImage: "calendar.badge.clock")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
            list("Points forts", result.strengths, symbol: "checkmark.circle.fill", color: Theme.lime)
            list("À améliorer", result.improvements, symbol: "arrow.up.right.circle.fill", color: .yellow)
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Kicker("Légende améliorée")
                        Spacer()
                        Button(copied ? "Copiée ✓" : "Copier") {
                            UIPasteboard.general.string = result.improvedCaption
                            copied = true
                        }
                        .font(.caption)
                    }
                    Text(result.improvedCaption).font(.subheadline).textSelection(.enabled)
                }
            }
            list("Accroches à essayer", result.hooks, symbol: "quote.opening", color: Theme.muted)
            Text("\(result.quota.remaining) pré-test\(result.quota.remaining > 1 ? "s" : "") restant\(result.quota.remaining > 1 ? "s" : "") cette semaine")
                .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
        }
    }

    private func list(_ title: String, _ items: [String], symbol: String, color: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Kicker(title)
                ForEach(items, id: \.self) { item in
                    Label {
                        Text(item).font(.subheadline)
                    } icon: {
                        Image(systemName: symbol).foregroundStyle(color)
                    }
                }
            }
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        score >= 70 ? Theme.lime : score >= 45 ? .yellow : Theme.coral
    }
}

private struct IdeasPanel: View {
    @Environment(AppModel.self) private var model
    @State private var request = ""
    @State private var response: IdeasResponse?
    @State private var error: APIError?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quoi publier cette semaine ?").font(.title2).fontWeight(.heavy)
            Text("5 idées prêtes à tourner, tirées de ce qui marche chez toi.").font(.subheadline).foregroundStyle(Theme.muted)
            TextField("Un thème, un événement ? (facultatif)", text: $request)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button(loading ? "Recherche d’idées…" : "Trouve-moi 5 idées") { Task { await run() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading)
            if let error {
                if error.upgrade { UpsellCard(message: error.message) } else { BannerCard(message: error.message) { self.error = nil } }
            }
            if let response {
                ForEach(response.ideas) { idea in ideaCard(idea) }
            }
        }
    }

    private func run() async {
        loading = true
        defer { loading = false }
        do {
            response = try await model.ideas(request)
            error = nil
        } catch let apiError as APIError {
            error = apiError
        } catch {
            self.error = APIError(status: 0, message: error.localizedDescription, upgrade: false)
        }
    }

    private func ideaCard(_ idea: Idea) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NetworkBadge(network: idea.network, size: 24)
                    Text(idea.format.label).font(.caption).foregroundStyle(Theme.muted)
                }
                Text(idea.title).font(.headline)
                Text("« \(idea.hook) »").font(.subheadline).italic()
                ForEach(Array(idea.outline.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(step)").font(.footnote).foregroundStyle(Theme.muted)
                }
                Text(idea.why).font(.footnote).foregroundStyle(Theme.lime)
            }
        }
    }
}
