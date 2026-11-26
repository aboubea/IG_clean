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
/// Elle renvoie toutes les fenêtres d'un coup ; le tri se fait dans l'app.
protocol HotInfluxProvider {
    func fetch() async throws -> [InfluencerRow]
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
    func fetch() async throws -> [InfluencerRow] {
        try await Task.sleep(nanoseconds: 300_000_000)
        return Self.rows
    }

    /// Pseudos au format Instagram : minuscules sans accents, chiffres, points et tirets bas.
    private static let handles = [
        ("lea.moves", "Léa Moreau", "Fitness"), ("chef.nordin", "Nordin K.", "Cuisine"),
        ("studio.palette", "Studio Palette", "Art"), ("km.runner", "Kamel B.", "Running"),
        ("vibe.records", "Vibe Records", "Musique"), ("maison.lora", "Maison Lora", "Mode"),
        ("yanis.tech", "Yanis T.", "Tech"), ("green.margot", "Margot V.", "Jardin"),
        ("atlas.surf", "Atlas Surf", "Voyage"), ("theo.pixel", "Théo R.", "Gaming"),
        ("suna.yoga", "Suna I.", "Yoga"), ("riviera.auto", "Riviera Auto", "Auto"),
        ("ines.books", "Inès D.", "Lecture"), ("sky.drone", "Sky Drone", "Photo"),
        ("lou.and.co", "Lou & Co", "Famille"), ("mehdi.invest", "Mehdi A.", "Finance"),
        ("okan.danse", "Okan Y.", "Danse"), ("belle.table", "Belle Table", "Food"),
        ("come.mtb", "Côme L.", "Vélo"), ("zoe.makeup", "Zoé M.", "Beauté"),
    ]

    private static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Croissance cumulée, donc croissante avec la fenêtre ; une « accélération récente » propre à chaque
    /// compte fait varier le classement selon la fenêtre choisie.
    private static let rows: [InfluencerRow] = handles.enumerated().map { index, item in
        let daily = 0.9 - 0.035 * Double(index)
        let boost = 1 + 0.8 * Double((index * 7) % 5) / 4
        let g5 = daily * 5 * boost
        let g10 = g5 + daily * 5
        let g20 = g10 + daily * 10 * 0.8
        let g30 = g20 + daily * 10 * 0.6
        return InfluencerRow(
            id: "demo-\(index)",
            username: item.0,
            fullName: item.1,
            category: item.2,
            isVerified: index % 4 == 0,
            followers: Int(1_500_000 / (Double((index * 7) % 20) + 1.3)) + 3_100,
            growth5: round1(g5),
            growth10: round1(g10),
            growth20: round1(g20),
            growth30: round1(g30),
            engagementRate: round1((Double((index * 13) % 9) + 2.5) / 2)
        )
    }
}
