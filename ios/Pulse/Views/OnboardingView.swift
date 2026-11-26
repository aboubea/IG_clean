import SwiftUI

/** Inscription en 4 temps : bienvenue, profil, objectif, réseaux. */
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var profile: ProfileType = .creator
    @State private var goal: Goal = .awareness
    @State private var saving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if step > 0 {
                ProgressView(value: Double(step), total: 3)
                    .tint(Theme.lime)
                    .padding(.bottom, 20)
            }
            switch step {
            case 0: welcome
            case 1: profileStep
            case 2: goalStep
            default: networksStep
            }
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut, value: step)
        .onAppear {
            if let user = model.user {
                profile = user.profileType
                goal = user.goal
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Text("PULSE").font(.system(size: 14, weight: .heavy)).tracking(3).foregroundStyle(Theme.lime)
            Text("Tous tes réseaux,\nun seul tableau de bord").font(.system(size: 36, weight: .heavy))
            Text("Instagram, Facebook, TikTok et LinkedIn réunis. Pulse te dit où tu grandis, ce qui marche, et quoi faire la semaine prochaine.")
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Commencer") { step = 1 }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu utilises tes réseaux plutôt…").font(.title).fontWeight(.heavy)
            Text("Pulse adapte ses analyses et ses conseils à ton profil.").foregroundStyle(Theme.muted)
            ForEach(ProfileType.allCases) { option in
                choice(selected: profile == option, symbol: option.symbol, title: option.label, hint: option.hint) { profile = option }
            }
            Spacer()
            Button("Continuer") { step = 2 }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ton objectif principal ?").font(.title).fontWeight(.heavy)
            Text("Le bilan de chaque semaine te proposera des actions dans ce sens.").foregroundStyle(Theme.muted)
            ForEach(Goal.allCases) { option in
                choice(selected: goal == option, symbol: "target", title: option.label, hint: nil) { goal = option }
            }
            Spacer()
            Button(saving ? "…" : "Continuer") {
                saving = true
                Task {
                    _ = await model.updateProfile(["profileType": profile.rawValue, "goal": goal.rawValue])
                    saving = false
                    step = 3
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
        }
    }

    private var networksStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connecte tes réseaux").font(.title).fontWeight(.heavy)
            Text("Connexion officielle de chaque réseau : Pulse ne voit jamais ton mot de passe.").foregroundStyle(Theme.muted)
            ScrollView {
                ConnectNetworksList()
                Card {
                    HStack(alignment: .top, spacing: 10) {
                        Text("💡")
                        Text("Instagram et TikTok demandent un compte Pro (créateur ou entreprise) pour partager leurs statistiques. C’est gratuit et ça prend 30 secondes dans les réglages de l’app.")
                            .font(.footnote)
                    }
                }
            }
            Button("Voir mon tableau de bord") { Task { await model.completeOnboarding() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.hasConnections)
                .opacity(model.hasConnections ? 1 : 0.4)
        }
    }

    private func choice(selected: Bool, symbol: String, title: String, hint: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let hint { Text(hint).font(.footnote).foregroundStyle(Theme.muted) }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.lime : Theme.muted)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Theme.lime : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
