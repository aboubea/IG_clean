import Foundation

/// Fenêtre de mesure de la croissance.
enum GrowthWindow: Int, CaseIterable, Identifiable {
    case d5 = 5, d10 = 10, d20 = 20, d30 = 30

    var id: Int { rawValue }
    var label: String { "\(rawValue) j" }
}

/// Critère de classement.
enum RankMetric: String, CaseIterable, Identifiable {
    case growth, engagement, followers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .growth: return "Croissance"
        case .engagement: return "Engagement"
        case .followers: return "Abonnés"
        }
    }
}

/// Un influenceur classé. Les champs de croissance sont des pourcentages par fenêtre.
/// Clés explicites (et non un dictionnaire) pour un contrat JSON simple côté backend.
struct InfluencerRow: Codable, Identifiable {
    let id: String
    var username: String
    var fullName: String
    var category: String
    var isVerified: Bool
    var followers: Int
    var growth5: Double
    var growth10: Double
    var growth20: Double
    var growth30: Double
    /// Taux d'engagement en pourcentage : (likes + commentaires moyens) / abonnés.
    var engagementRate: Double

    func growth(_ window: GrowthWindow) -> Double {
        switch window {
        case .d5: return growth5
        case .d10: return growth10
        case .d20: return growth20
        case .d30: return growth30
        }
    }
}

/// Source des classements : la démo intégrée, ou plus tard un backend / fournisseur.
protocol HotInfluxProvider {
    func top(window: GrowthWindow, metric: RankMetric) async throws -> [InfluencerRow]
}

extension Array where Element == InfluencerRow {
    /// Tri local selon le critère et la fenêtre choisis.
    func ranked(by metric: RankMetric, window: GrowthWindow) -> [InfluencerRow] {
        switch metric {
        case .growth: return sorted { $0.growth(window) > $1.growth(window) }
        case .engagement: return sorted { $0.engagementRate > $1.engagementRate }
        case .followers: return sorted { $0.followers > $1.followers }
        }
    }
}

/// Jeu de données factice : aucune requête réseau, pour voir l'écran fonctionner.
struct DemoInfluxProvider: HotInfluxProvider {
    func top(window: GrowthWindow, metric: RankMetric) async throws -> [InfluencerRow] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Self.rows
    }

    private static let handles = [
        ("lea.moves", "Léa Moreau", "Fitness"), ("chef.nordin", "Nordin K.", "Cuisine"),
        ("studio.palette", "Studio Palette", "Art"), ("km.runner", "Kamel B.", "Running"),
        ("vibe.records", "Vibe Records", "Musique"), ("maison.lora", "Maison Lora", "Mode"),
        ("tech.posé", "Yanis T.", "Tech"), ("green.margot", "Margot V.", "Jardin"),
        ("surf.atlas", "Atlas Surf", "Voyage"), ("pixel.théo", "Théo R.", "Gaming"),
        ("yoga.suna", "Suna I.", "Yoga"), ("auto.riviera", "Riviera Auto", "Auto"),
        ("inès.books", "Inès D.", "Lecture"), ("drone.sky", "Sky Drone", "Photo"),
        ("baby.lou", "Lou & Co", "Famille"), ("crypto.mbehdi", "Mehdi A.", "Finance"),
        ("danse.okan", "Okan Y.", "Danse"), ("resto.belle", "Belle Table", "Food"),
        ("mtb.côme", "Côme L.", "Vélo"), ("make.by.zoé", "Zoé M.", "Beauté"),
    ]

    private static let rows: [InfluencerRow] = handles.enumerated().map { index, item in
        // Nombres plausibles et stables, décroissants avec le rang.
        let seed = Double(index)
        let followers = Int(1_200_000 / (seed + 1.4)) + 4_200
        let base = 34 - seed * 1.5
        return InfluencerRow(
            id: "demo-\(index)",
            username: item.0,
            fullName: item.1,
            category: item.2,
            isVerified: index % 4 == 0,
            followers: followers,
            growth5: (base + 6).rounded() / 10 * 10 / 10,
            growth10: max(0.4, base * 0.7).rounded() / 10,
            growth20: max(0.3, base * 0.5).rounded() / 10,
            growth30: max(0.2, base * 0.35).rounded() / 10,
            engagementRate: max(0.8, 11 - seed * 0.45).rounded() / 10
        )
    }
}
