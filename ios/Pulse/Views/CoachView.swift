import SwiftUI

/** Coach IA : on pose ses questions à ses propres chiffres. */
struct CoachView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    private let suggestions = [
        "Quand est-ce que je devrais publier ?",
        "Pourquoi mon meilleur post a marché ?",
        "Sur quel réseau miser en ce moment ?",
        "Comment gagner mes 1 000 prochains abonnés ?",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.coachMessages.isEmpty {
                            intro
                        }
                        ForEach(model.coachMessages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.coachMessages.last?.content) {
                    if let last = model.coachMessages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { inputBar }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .task { if model.coachMessages.isEmpty { await model.loadCoach() } }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pose tes questions à tes chiffres").font(.title2).fontWeight(.heavy)
            Text("Le coach connaît tes statistiques sur tous tes réseaux. Essaie :").foregroundStyle(Theme.muted)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    Task { await model.askCoach(suggestion) }
                } label: {
                    Text(suggestion).font(.subheadline)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func bubble(_ message: CoachMessage) -> some View {
        let mine = message.role == "user"
        return HStack {
            if mine { Spacer(minLength: 48) }
            Group {
                if message.content.isEmpty && model.coachStreaming {
                    ProgressView()
                } else {
                    Text(message.content).textSelection(.enabled)
                }
            }
            .font(.body)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(mine ? Theme.background : Color.white)
            .background(mine ? Theme.lime : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !mine { Spacer(minLength: 48) }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                TextField("Ta question…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    let text = draft
                    draft = ""
                    Task { await model.askCoach(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.lime)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.coachStreaming)
                .accessibilityLabel("Envoyer")
            }
            if let quota = model.coachQuota {
                Text("\(quota.remaining) question\(quota.remaining > 1 ? "s" : "") restante\(quota.remaining > 1 ? "s" : "") cette semaine")
                    .font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
    }
}
