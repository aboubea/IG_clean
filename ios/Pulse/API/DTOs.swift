import Foundation

// Miroir des réponses JSON du serveur Pulse (server/src/routes/api.ts).

enum Network: String, Codable, CaseIterable, Identifiable {
    case instagram, facebook, tiktok, linkedin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instagram: return "Instagram"
        case .facebook: return "Facebook"
        case .tiktok: return "TikTok"
        case .linkedin: return "LinkedIn"
        }
    }

    /** Initiales affichées dans la pastille du réseau (pas de logo officiel). */
    var initials: String {
        switch self {
        case .instagram: return "IG"
        case .facebook: return "FB"
        case .tiktok: return "TT"
        case .linkedin: return "IN"
        }
    }
}

enum PostFormat: String, Codable, CaseIterable, Identifiable {
    case shortVideo = "short_video"
    case video, carousel, photo, text, article, story

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shortVideo: return "Vidéo courte"
        case .video: return "Vidéo"
        case .carousel: return "Carrousel"
        case .photo: return "Photo"
        case .text: return "Texte"
        case .article: return "Article"
        case .story: return "Story"
        }
    }
}

enum ProfileType: String, Codable, CaseIterable, Identifiable {
    case creator, business, curious

    var id: String { rawValue }

    var label: String {
        switch self {
        case .creator: return "Créateur de contenu"
        case .business: return "Pro ou entreprise"
        case .curious: return "Juste curieux"
        }
    }

    var hint: String {
        switch self {
        case .creator: return "Je publie régulièrement et je veux grandir."
        case .business: return "Je veux des clients grâce à mes réseaux."
        case .curious: return "Je veux comprendre mes statistiques."
        }
    }

    var symbol: String {
        switch self {
        case .creator: return "sparkles"
        case .business: return "briefcase"
        case .curious: return "eye"
        }
    }
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case awareness, engagement, traffic, sales

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awareness: return "Me faire connaître"
        case .engagement: return "Créer une communauté engagée"
        case .traffic: return "Attirer du trafic"
        case .sales: return "Vendre"
        }
    }
}

struct User: Codable, Equatable {
    let id: String
    var displayName: String?
    var profileType: ProfileType
    var goal: Goal
    var timezone: String
    var premium: Bool
    var premiumUntil: Date?
    var referralCode: String
    var referred: Bool
    var publicSlug: String?
    var mediaKitPublic: Bool
    var mediaKitUrl: String?
    var aiSource: String?
}

struct AuthResponse: Codable {
    let token: String
    let user: User
}

struct NetworkStatus: Codable, Identifiable {
    struct Connection: Codable {
        let id: String
        let handle: String
        let mode: String
        let lastSyncedAt: Date?
        let lastError: String?
    }

    let network: Network
    let label: String
    let available: Bool
    let mode: String?
    let connection: Connection?

    var id: String { network.rawValue }
}

struct ConnectResponse: Codable {
    let status: String
    let connectionId: String?
    let mode: String?
    let syncError: String?
    let url: String?
    let callbackScheme: String?
}

struct NetworkSummary: Codable, Identifiable {
    let connectionId: String
    let network: Network
    let label: String
    let handle: String
    let mode: String
    let followers: Int
    let change7d: Int
    let change30d: Int
    let change30dPct: Double
    let engagementRate: Double
    let postsLast30d: Int
    let lastSyncedAt: Date?
    let lastError: String?

    var id: String { connectionId }
}

struct Milestone: Codable, Identifiable, Hashable {
    let kind: String
    let network: Network?
    let value: Int
    let label: String
    let at: Date
    let postId: String?

    var id: String { "\(kind)-\(network?.rawValue ?? "all")-\(value)-\(at.timeIntervalSince1970)" }
}

struct Overview: Codable {
    struct Point: Codable {
        let day: String
        let total: Int
    }

    struct Driver: Codable {
        let network: Network
        let label: String
        let share: Int
    }

    let totalAudience: Int
    let change7d: Int
    let change30d: Int
    let series: [Point]
    let networks: [NetworkSummary]
    let growthDriver: Driver?
    let milestones: [Milestone]
}

struct TopPost: Codable, Identifiable {
    let id: String
    let network: Network
    let format: PostFormat
    let formatLabel: String
    let caption: String
    let permalink: String?
    let publishedAt: Date
    let views: Int?
    let reach: Int?
    let interactions: Int
    let engagementRate: Double
}

struct WhatWorks: Codable {
    struct FormatStat: Codable, Identifiable {
        let format: PostFormat
        let label: String
        let engagementRate: Double
        let posts: Int
        var id: String { format.rawValue }
    }

    struct NetworkStat: Codable, Identifiable {
        let network: Network
        let label: String
        let engagementRate: Double
        let posts: Int
        var id: String { network.rawValue }
    }

    struct BestSlot: Codable {
        let label: String
        let weekdays: [Int]
        let slot: Int
    }

    let days: Int
    let postCount: Int
    let formats: [FormatStat]
    let networks: [NetworkStat]
    let heat: [[Double?]]
    let slotStarts: [Int]
    let bestSlot: BestSlot?
    let topPosts: [TopPost]
    let weakPosts: [TopPost]
}

struct Quota: Codable {
    let feature: String
    let used: Int
    let limit: Int
    let remaining: Int
}

struct RecapAction: Codable, Identifiable {
    let title: String
    let detail: String
    let network: Network?
    var id: String { title }
}

struct Recap: Codable {
    let week: String
    let source: String
    let createdAt: Date
    let headline: String
    let summary: String
    let actions: [RecapAction]
}

struct Idea: Codable, Identifiable {
    let title: String
    let network: Network
    let format: PostFormat
    let hook: String
    let outline: [String]
    let why: String
    var id: String { title + network.rawValue }
}

struct IdeasResponse: Codable {
    let source: String
    let quota: Quota
    let ideas: [Idea]
}

struct PretestResponse: Codable {
    let source: String
    let quota: Quota
    let score: Double
    let verdict: String
    let bestNetwork: Network
    let bestTime: String
    let strengths: [String]
    let improvements: [String]
    let improvedCaption: String
    let hooks: [String]
}

struct CoachMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String
    var content: String
    let createdAt: Date
}

struct CoachHistory: Codable {
    let messages: [CoachMessage]
    let quota: Quota
}

/** Évènement du flux du coach : `delta`, `reset`, `done` ou `error`. */
struct CoachStreamEvent: Codable {
    let type: String
    let text: String?
    let error: String?
    let source: String?
}

struct MediaKitInfo: Codable {
    let slug: String?
    let `public`: Bool
    let url: String?
    let newInquiries: Int
}

struct Inquiry: Codable, Identifiable {
    let id: String
    let brand: String
    let email: String
    let message: String
    let budget: String?
    let status: String
    let createdAt: Date
}

struct ReferralResponse: Codable {
    let message: String
    let user: User
}

struct ErrorResponse: Codable {
    let error: String
    let upgrade: Bool?
}

enum JSONCoding {
    /** Dates ISO 8601, avec ou sans millisecondes. */
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date illisible : \(text)")
        }
        return decoder
    }()
}
