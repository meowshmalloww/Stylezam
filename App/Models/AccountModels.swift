import Foundation

enum AccountPlan: String, Codable, CaseIterable, Identifiable, Sendable {
    case free
    case plus
    case pro
    case developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "Free"
        case .plus: "Plus"
        case .pro: "Pro"
        case .developer: "Developer"
        }
    }

    var productSearchAllowance: String {
        switch self {
        case .free: "10 searches / month"
        case .plus: "100 searches / month"
        case .pro: "300 searches / month"
        case .developer: "Unlimited searches"
        }
    }

    var assistantAllowance: String {
        switch self {
        case .free: "20 AI questions / month"
        case .plus: "250 AI questions / month"
        case .pro: "1,000 AI questions / month"
        case .developer: "Unlimited AI questions"
        }
    }

    var summary: String {
        switch self {
        case .free: "Try the complete search flow at a careful monthly limit."
        case .plus: "For regular personal shopping and saved looks."
        case .pro: "For creators and frequent product research."
        case .developer: "Internal testing with Developer Debug access."
        }
    }

    var isAvailable: Bool { true }

    var productSearchLimit: Int? {
        switch self {
        case .free: 10
        case .plus: 100
        case .pro: 300
        case .developer: nil
        }
    }

    var assistantQuestionLimit: Int? {
        switch self {
        case .free: 20
        case .plus: 250
        case .pro: 1_000
        case .developer: nil
        }
    }
}

struct LocalUserProfile: Codable, Hashable, Sendable {
    var displayName: String
    var username: String
    var styleNote: String

    static func initial(displayName: String) -> LocalUserProfile {
        LocalUserProfile(displayName: displayName, username: "", styleNote: "")
    }
}

struct StylezamAccount: Hashable, Sendable {
    let uid: String
    let email: String
    let googleDisplayName: String
    let photoURL: URL?
    var profile: LocalUserProfile
    let isDeveloper: Bool

    var plan: AccountPlan { isDeveloper ? .developer : .free }
    var roleLabel: String { isDeveloper ? "DEVELOPER" : "MEMBER" }
    var visibleName: String {
        let trimmed = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? googleDisplayName : trimmed
    }

    var initials: String {
        let parts = visibleName.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "S" : value.uppercased()
    }
}

enum FirebaseConfigurationState: Equatable, Sendable {
    case checking
    case ready
    case missingPlist
    case invalidPlist

    var message: String {
        switch self {
        case .checking: "Checking Firebase configuration…"
        case .ready: "Firebase is ready."
        case .missingPlist: "Add GoogleService-Info.plist to App/Resources and rebuild."
        case .invalidPlist: "The Firebase configuration file is invalid or belongs to another app."
        }
    }
}
