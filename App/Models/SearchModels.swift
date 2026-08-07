import Foundation

enum ProductSearchPipeline: String, Codable, CaseIterable, Identifiable, Sendable {
    case privateAIText = "private-ai-text"
    case directImage = "direct-image"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateAIText: "AI-guided similar search"
        case .directImage: "Visual product search"
        }
    }

    var detail: String {
        switch self {
        case .privateAIText:
            "Uses Fireworks to prepare shopping terms, then sends one request to the next ready keyword provider."
        case .directImage:
            "Sends the selected crop to one eligible visual-search provider, advancing the route after every request."
        }
    }
}

enum AIShoppingSearchIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case similar
    case cheaper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .similar: "Find similar"
        case .cheaper: "Find cheaper"
        }
    }

    var systemImage: String {
        switch self {
        case .similar: "square.stack.3d.up"
        case .cheaper: "tag"
        }
    }

    func refinementPrompt(conversationContext: String?) -> String {
        let context = conversationContext?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let contextInstruction = context.flatMap { $0.isEmpty ? nil : $0 }
            .map { " Respect this request from the conversation: \($0)." }
            ?? ""

        switch self {
        case .similar:
            return "Find visually similar products in the same garment category. Preserve the most distinctive visible silhouette, color, pattern, and construction details. Do not assume a brand.\(contextInstruction)"
        case .cheaper:
            return "Find lower-priced alternatives in the same garment category. Preserve the key visible style details, but favor useful shopping terms such as affordable, sale, outlet, or budget only where natural. Do not invent a price or assume a brand.\(contextInstruction)"
        }
    }
}

enum StylezamChatRole: String, Codable, Sendable {
    case user
    case assistant
}

struct StylezamChatMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let role: StylezamChatRole
    let text: String
    let createdAt: Date
    let suggestedQuestions: [String]?

    init(
        id: UUID = UUID(),
        role: StylezamChatRole,
        text: String,
        createdAt: Date = .now,
        suggestedQuestions: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.suggestedQuestions = suggestedQuestions
    }
}

struct StylezamChatThread: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let scanID: UUID
    let garmentID: String
    var messages: [StylezamChatMessage]
    var updatedAt: Date
}

struct StylezamAssistantTurn: Hashable, Sendable {
    let answer: String
    let suggestedQuestions: [String]
}

enum ProductSearchProgress: Equatable, Sendable {
    case preparing
    case searchingImage(String)
    case analyzingRequest
    case searchingStores
    case saving(Int)

    var title: String {
        switch self {
        case .preparing: "Preparing the selected piece"
        case let .searchingImage(provider): "Searching with \(provider)"
        case .analyzingRequest: "Stylezam AI is reading your request"
        case .searchingStores: "Searching live shopping results"
        case let .saving(count): "Organizing \(count) matches"
        }
    }
}

enum ImageSearchProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case lykdat
    case googleVision = "googlevision"
    case searchAPI = "searchapi"
    case serpAPI = "serpapi"
    case brightData = "brightdata"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lykdat: "Lykdat Global Search"
        case .googleVision: "Google Cloud Vision Web Detection"
        case .searchAPI: "SearchAPI.io Google Lens"
        case .serpAPI: "SerpApi Google Lens"
        case .brightData: "Bright Data Google Lens"
        }
    }

    var acceptsPrivateImageData: Bool {
        self == .lykdat || self == .googleVision
    }

    var credential: SearchCredentialKind {
        switch self {
        case .lykdat: .lykdat
        case .googleVision: .googleVision
        case .searchAPI: .searchAPI
        case .serpAPI: .serpAPI
        case .brightData: .brightData
        }
    }
}

enum KeywordSearchProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case serper
    case searchAPI = "searchapi"
    case serpAPI = "serpapi"
    case brightData = "brightdata"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serper: "Serper.dev Shopping"
        case .searchAPI: "SearchAPI.io Shopping"
        case .serpAPI: "SerpApi Shopping"
        case .brightData: "Bright Data Shopping"
        }
    }

    var credential: SearchCredentialKind {
        switch self {
        case .serper: .serper
        case .searchAPI: .searchAPI
        case .serpAPI: .serpAPI
        case .brightData: .brightData
        }
    }

    var requiresZone: Bool { self == .brightData }
}

enum SearchCredentialKind: String, CaseIterable, Identifiable, Sendable {
    case fireworks
    case serper
    case lykdat
    case googleVision = "googlevision"
    case searchAPI = "searchapi"
    case serpAPI = "serpapi"
    case brightData = "brightdata"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fireworks: "Fireworks AI"
        case .serper: "Serper.dev"
        case .lykdat: "Lykdat"
        case .googleVision: "Google Cloud Vision"
        case .searchAPI: "SearchAPI.io"
        case .serpAPI: "SerpApi"
        case .brightData: "Bright Data"
        }
    }

    var environmentKey: String {
        switch self {
        case .fireworks: "STYLEZAM_FIREWORKS_API_KEY"
        case .serper: "STYLEZAM_SERPER_API_KEY"
        case .lykdat: "STYLEZAM_LYKDAT_API_KEY"
        case .googleVision: "STYLEZAM_GOOGLE_VISION_API_KEY"
        case .searchAPI: "STYLEZAM_SEARCHAPI_API_KEY"
        case .serpAPI: "STYLEZAM_SERPAPI_API_KEY"
        case .brightData: "STYLEZAM_BRIGHTDATA_API_KEY"
        }
    }
}

struct GarmentSearchContext: Hashable, Sendable {
    let scanID: UUID
    let garmentID: String
    let garmentLabel: String
    let imageData: Data

    var key: String { "\(scanID.uuidString):\(garmentID)" }
}

struct GarmentUnderstanding: Codable, Hashable, Sendable {
    let summary: String
    let searchQuery: String
    let suggestions: [String]
    let category: String?
    let colors: [String]
    let materials: [String]
    let patterns: [String]
}

struct SearchProviderResponse: Sendable {
    let results: [ProductResultDTO]
    let providerRequestID: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let diagnostic: String
}

struct ProductSearchOutcome: Sendable {
    let searchID: String
    let results: [ProductResultDTO]
    let understanding: GarmentUnderstanding?
    let providerSummary: String
    let requestCount: Int
    let durationMilliseconds: Double
    let diagnostic: String
}

struct SavedProductSearch: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let garmentKey: String
    let scanID: UUID
    let garmentID: String
    let createdAt: Date
    let pipeline: ProductSearchPipeline
    let providerSummary: String
    let aiSearchIntent: AIShoppingSearchIntent?
    let generatedQuery: String?
    let generatedSuggestions: [String]
    let results: [ProductResultDTO]
    let durationMilliseconds: Double
}

enum SearchUsageKind: String, Codable, Sendable {
    case productSearch
    case assistant
    case providerTest
    case tryOnInference
}

enum SearchUsageStatus: String, Codable, Sendable {
    case reserved
    case succeeded
    case failed
}

struct SearchUsageRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let garmentKey: String?
    let kind: SearchUsageKind
    let providers: [String]
    let createdAt: Date
    var status: SearchUsageStatus
    var requestCount: Int
    var resultCount: Int
    var latencyMilliseconds: Double?
    var estimatedCostUSD: Double
    var diagnostic: String?
}

struct SearchUsageSnapshot: Codable, Sendable {
    var records: [SearchUsageRecord] = []
}

enum ProductSearchError: LocalizedError, Equatable {
    case missingCredential(String)
    case missingBrightDataZone
    case publicImageURLRequired(String)
    case garmentSearchLimitReached(Int)
    case monthlyRequestLimitReached(String, Int)
    case fireworksBudgetReached(Double)
    case planLimitReached(String, Int)
    case invalidResponse(String)
    case provider(String)
    case noResults

    var errorDescription: String? {
        switch self {
        case let .missingCredential(provider):
            "\(provider) is not configured for this private build. Add it to the ignored developer .env and relaunch."
        case .missingBrightDataZone:
            "Bright Data needs a compatible SERP zone in the ignored developer .env."
        case let .publicImageURLRequired(provider):
            "\(provider) requires a public HTTPS image URL. A private iPhone crop is never uploaded automatically."
        case let .garmentSearchLimitReached(limit):
            "This piece already used its \(limit == 1 ? "one search" : "\(limit) searches"). Change the per-piece limit in Developer Debug to search again."
        case let .monthlyRequestLimitReached(provider, limit):
            "The local \(provider) monthly safety limit of \(limit) requests has been reached."
        case let .fireworksBudgetReached(limit):
            "The local Fireworks monthly safety budget of \(limit.formatted(.currency(code: "USD"))) has been reached."
        case let .planLimitReached(kind, limit):
            "Your Free plan includes \(limit) \(kind) per month. Plus and Pro are previews and cannot be purchased in this build."
        case let .invalidResponse(provider):
            "\(provider) returned a response Stylezam could not read."
        case let .provider(message): message
        case .noResults: "The provider completed the search but returned no usable product results."
        }
    }
}
