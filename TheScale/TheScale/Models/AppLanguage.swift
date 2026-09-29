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

    /// Allow-list check. Unknown codes are not a language the app can apply.
    var isSupported: Bool { AppLanguage.validated(rawValue) == self }

    /// Splash and settings brand line in this language.
    var splashTagline: String {
        switch self == .system ? resolved : self {
        case .system, .english:
            return "Nag until the fat folds."
        case .spanish:
            return "Nag hasta que la grasa ceda."
        case .french:
            return "Nag jusqu'à ce que le gras plie."
        case .german:
            return "Nag, bis das Fett nachgibt."
        case .italian:
            return "Nag finché il grasso cede."
        case .portugueseBrazil, .portuguesePortugal:
            return "Nag até a gordura ceder."
        case .japanese:
            return "脂肪が折れるまで、Nag。"
        case .korean:
            return "살이 접힐 때까지 Nag."
        case .chineseSimplified:
            return "Nag，直到脂肪让步。"
        case .chineseTraditional:
            return "Nag，直到脂肪讓步。"
        case .dutch:
            return "Nag tot het vet wijkt."
        case .swedish:
            return "Nag tills fettet viker."
        case .danish:
            return "Nag indtil fedtet giver sig."
        case .finnish:
            return "Nag, kunnes rasva antaa periksi."
        case .norwegian:
            return "Nag til fettet gir seg."
        case .polish:
            return "Nag, aż tłuszcz ustąpi."
        case .turkish:
            return "Yağ pes edene kadar Nag."
        case .russian:
            return "Nag, пока жир не сдастся."
        case .arabic:
            return "Nag حتى ينثني الدهن."
        case .hindi:
            return "Nag, जब तक चर्बी न झुके."
        case .thai:
            return "Nag จนกว่าไขมันจะยอม."
        case .vietnamese:
            return "Nag cho đến khi mỡ chịu thua."
        case .indonesian:
            return "Nag sampai lemaknya menyerah."
        case .malay:
            return "Nag sehingga lemak mengalah."
        case .hebrew:
            return "Nag עד שהשומן נכנע."
        case .ukrainian:
            return "Nag, доки жир не здасться."
        case .czech:
            return "Nag, dokud tuk nepovolí."
        case .greek:
            return "Nag μέχρι να υποχωρήσει το λίπος."
        case .hungarian:
            return "Nag, amíg a zsír meg nem adja magát."
        case .romanian:
            return "Nag până cedează grăsimea."
        case .slovak:
            return "Nag, kým tuk nepovolí."
        case .croatian:
            return "Nag dok masnoća ne popusti."
        case .catalan:
            return "Nag fins que el greix cedeixi."
        }
    }

    /// Concrete language when the choice is System.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier
        let script = Locale.current.language.script?.identifier
        if code == "zh" {
            if script == "Hant" || region == "TW" || region == "HK" || region == "MO" {
                return .chineseTraditional
            }
            return .chineseSimplified
        }
        if code == "pt" {
            return region == "PT" ? .portuguesePortugal : .portugueseBrazil
        }
        if code == "no" { return .norwegian }
        if let match = AppLanguage(rawValue: code) { return match }
        return .english
    }

    /// Hard instruction for Keel, on-device models, and meal copy.
    var modelDirective: String {
        let lang = resolved
        return "Language lock: write every sentence the user will read in \(lang.profileLanguageName) (\(lang.nativeLabel)). Meals, jokes, greetings, and notifications included. Keep numbers and the name fatnag as written."
    }

    static func validated(_ raw: String) -> AppLanguage? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let lang = AppLanguage(rawValue: trimmed) else { return nil }
        return lang
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
                  let lang = AppLanguage.validated(raw) else { return .system }
            return lang
        }
        set {
            guard let lang = AppLanguage.validated(newValue.rawValue) else { return }
            UserDefaults.standard.set(lang.rawValue, forKey: key)
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
        }
    }

    /// Applies a language only when it is on the allow-list. Returns nil when rejected.
    @discardableResult
    static func apply(_ language: AppLanguage) -> AppLanguage? {
        guard let lang = AppLanguage.validated(language.rawValue), lang.isSupported else { return nil }
        current = lang
        return lang
    }

    /// Pins model prompts to the validated language.
    static func locked(_ prompt: String) -> String {
        let line = current.resolved.modelDirective
        if prompt.contains(line) { return prompt }
        return prompt + "\n" + line
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
