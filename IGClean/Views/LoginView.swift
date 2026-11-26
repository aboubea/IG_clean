import SwiftUI
import WebKit

/// Page de connexion d'Instagram elle-même : l'app ne voit jamais le mot de passe,
/// elle attend seulement que la session existe pour refermer l'écran.
struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            LoginWebView()
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Connexion à Instagram")
                .navigationBarTitleDisplayMode(.inline)
        }
        .task { await model.waitForLogin() }
    }
}

private struct LoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: InstagramClient.makeConfiguration())
        webView.load(URLRequest(url: InstagramClient.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// Insère une vue web existante dans la hiérarchie SwiftUI.
struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
