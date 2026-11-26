import SwiftUI

/// Classement de tes fans les plus fidèles : mutuels, du plus ancien au plus récent.
/// L'ancienneté part de la première fois où l'app les a vus (Instagram ne donne pas la vraie date).
struct LoyalFansView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fans = model.state.loyalFans
        NavigationStack {
            Group {
                if fans.isEmpty {
                    ContentUnavailableView(
                        "Pas encore de fans fidèles",
                        systemImage: "star",
                        description: Text("Tes abonnés mutuels apparaîtront ici, du plus ancien au plus récent, après quelques scans.")
                    )
                } else {
                    List {
                        ForEach(Array(fans.prefix(100).enumerated()), id: \.element.id) { index, user in
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(index < 3 ? Theme.lime : Theme.muted)
                                    .frame(width: 30, alignment: .leading)
                                UserLabel(user: user)
                                Spacer()
                                if let since = model.state.followers[user.id] {
                                    Text("vu le \(since.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Fans fidèles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
