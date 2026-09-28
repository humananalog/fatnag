import Foundation
import SwiftUI

/// In-app language override (App Store distribution locales). Persisted; drives `.environment(\.locale)`.
enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portugueseBrazil = "pt-BR"
    case portuguesePortugal = "pt-PT"
    case japanese = "ja"
    case korean = "ko"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
    case dutch = "nl"
    case swedish = "sv"
    case danish = "da"
    case finnish = "fi"
    case norwegian = "nb"
    case polish = "pl"
    case turkish = "tr"
    case russian = "ru"
    case arabic = "ar"
    case hindi = "hi"
    case thai = "th"
    case vietnamese = "vi"
    case indonesian = "id"
    case malay = "ms"
    case hebrew = "he"
    case ukrainian = "uk"
    case czech = "cs"
    case greek = "el"
    case hungarian = "hu"
    case romanian = "ro"
    case slovak = "sk"
    case croatian = "hr"
    case catalan = "ca"

    var id: String { rawValue }

    /// Native name for the language picker (always in that language).
    var nativeLabel: String {
        switch self {
        case .system: return String(localized: "lang.system", defaultValue: "System")
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portugueseBrazil: return "Português (Brasil)"
        case .portuguesePortugal: return "Português (Portugal)"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .dutch: return "Nederlands"
        case .swedish: return "Svenska"
        case .danish: return "Dansk"
        case .finnish: return "Suomi"
        case .norwegian: return "Norsk"
        case .polish: return "Polski"
        case .turkish: return "Türkçe"
        case .russian: return "Русский"
        case .arabic: return "العربية"
        case .hindi: return "हिन्दी"
        case .thai: return "ไทย"
        case .vietnamese: return "Tiếng Việt"
        case .indonesian: return "Bahasa Indonesia"
        case .malay: return "Bahasa Melayu"
        case .hebrew: return "עברית"
        case .ukrainian: return "Українська"
        case .czech: return "Čeština"
        case .greek: return "Ελληνικά"
        case .hungarian: return "Magyar"
        case .romanian: return "Română"
        case .slovak: return "Slovenčina"
        case .croatian: return "Hrvatski"
        case .catalan: return "Català"
        }
    }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        default:
            return Locale(identifier: rawValue)
        }
    }

    var layoutDirection: LayoutDirection {
        switch self {
        case .arabic, .hebrew:
            return .rightToLeft
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            return (code == "ar" || code == "he") ? .rightToLeft : .leftToRight
        default:
            return .leftToRight
        }
    }

    /// Profile string for Coach vibe (legacy `preferredLanguage` field).
    var profileLanguageName: String {
        switch self {
        case .system:
            return Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en")
                ?? "English"
        default:
            return Locale(identifier: "en").localizedString(forLanguageCode: rawValue.split(separator: "-").first.map(String.init) ?? rawValue)
                ?? nativeLabel
        }
    }
}

extension Notification.Name {
    static let appLanguageDidChange = Notification.Name("thescale.appLanguageDidChange")
}

enum AppLanguageStore {
    private static let key = "thescale.appLanguage"

    static var current: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let lang = AppLanguage(rawValue: raw) else { return .system }
            return lang
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    /// Effective locale for SwiftUI environment.
    static var effectiveLocale: Locale { current.locale }
}

/// Banking-style mass privacy on the home greeting line.
enum MassPrivacyStore {
    private static let key = "thescale.hideHomeMass"

    /// Default true: hide digits until the user taps the eye / mass.
    static var hideHomeMass: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func maskedMass(system: PreferredUnitSystem) -> String {
        switch system {
        case .metric: return "••.• kg"
        case .imperial: return "••• lb"
        }
    }
}
