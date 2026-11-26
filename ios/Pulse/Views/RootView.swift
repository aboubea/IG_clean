import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background.ignoresSafeArea())
            case .failed(let message):
                ServerErrorView(message: message)
            case .onboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            }
        }
        .task { await model.bootstrap() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "chart.line.uptrend.xyaxis") }
            AnalysisView()
                .tabItem { Label("Analyse", systemImage: "chart.bar.xaxis") }
            CreateView()
                .tabItem { Label("Créer", systemImage: "wand.and.stars") }
            CoachView()
                .tabItem { Label("Coach", systemImage: "bubble.left.and.bubble.right") }
        }
    }
}

/** Serveur injoignable : on explique, et on laisse corriger l'adresse (utile pour tester sur un iPhone). */
struct ServerErrorView: View {
    @Environment(AppModel.self) private var model
    let message: String
    @State private var server = AppConfig.serverURL

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi.exclamationmark").font(.system(size: 48)).foregroundStyle(Theme.coral)
            Text("Impossible de joindre Pulse").font(.title2).fontWeight(.heavy)
            Text(message).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            TextField("Adresse du serveur", text: $server)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            Spacer()
            Button("Réessayer") {
                AppConfig.serverURL = server.trimmingCharacters(in: .whitespaces)
                Task { await model.bootstrap() }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
    }
}
