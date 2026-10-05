import Foundation
import SwiftUI
import ObjectiveC

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
        case .system: return AppLanguageStore.text("lang.system", default: "System")
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

    /// Code used in `Localizable.xcstrings` language keys.
    var catalogLanguageCode: String {
        switch self {
        case .system:
            return resolved.catalogLanguageCode
        default:
            return rawValue
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
        if lang.isEnglishFamily {
            return "Language lock: write every sentence the user will read in English. Meals, jokes, greetings, and notifications included. Keep numbers and the name fatnag as written."
        }
        return """
        Language lock (HARD — ZERO exceptions): write 100% of every user-facing sentence in \(lang.profileLanguageName) (\(lang.nativeLabel)) only. Do not mix languages. Do not code-switch. Do not paste English Health labels (walking, active energy, deep sleep, recovery, high protein, veggies, Charts) — translate those facts into \(lang.nativeLabel). Vulgarity and humour stay in \(lang.nativeLabel) only. Proper nouns OK: fatnag, Keel, Hong Kong, Apple Health. Units OK: kg, g, kcal, km, bpm, h, %. If any English slips in, rewrite the whole sentence in \(lang.nativeLabel) before you send.
        """
    }

    /// End-of-prompt reminder (models attend to the last lines).
    var languageLockFooter: String {
        let lang = resolved
        if lang.isEnglishFamily { return "" }
        return "FINAL CHECK: the entire reply is in \(lang.nativeLabel) only. No English mix. Translate Health digest labels into \(lang.nativeLabel)."
    }

    /// English or system resolving to English.
    var isEnglishFamily: Bool {
        let code = resolved.catalogLanguageCode
        return code == "en" || code.hasPrefix("en-")
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
            StringCatalogLookup.invalidateCache()
            syncBundleLanguages(lang)
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

    /// Point Bundle / `String(localized:)` at the in-app language. SwiftUI `.locale` alone is not enough.
    static func syncBundleLanguages(_ language: AppLanguage = current) {
        AppLanguageBundleInstaller.installIfNeeded()
        StringCatalogLookup.invalidateCache()
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.resolved.catalogLanguageCode], forKey: "AppleLanguages")
        }
    }

    /// Splash / cold-open tagline.
    /// - Returning user: last language chosen in Settings / onboarding (resolved).
    /// - First launch (nothing saved): system language.
    static var splashTagline: String {
        current.resolved.splashTagline
    }

    /// Lookup that always uses the validated in-app language (sheets, Settings, splash).
    static func text(_ key: String, default defaultValue: String) -> String {
        let lang = current.resolved.catalogLanguageCode
        if let value = StringCatalogLookup.string(key: key, language: lang) {
            return value
        }
        return defaultValue
    }

    /// Pins model prompts to the validated language (directive + end footer).
    static func locked(_ prompt: String) -> String {
        let line = current.resolved.modelDirective
        let footer = current.resolved.languageLockFooter
        var out = prompt.contains(line) ? prompt : (line + "\n" + prompt)
        if !footer.isEmpty, !out.contains(footer) {
            out += "\n" + footer
        }
        return out
    }

    /// Effective locale for SwiftUI environment.
    static var effectiveLocale: Locale { current.locale }
}

// MARK: - Catalog-backed localization

/// Resolves strings from compiled `*.lproj/Localizable.strings` for the in-app language.
/// SwiftUI `.environment(\.locale)` does not affect `String(localized:)`; this does.
enum StringCatalogLookup {
    private static let lock = NSLock()
    /// language → (key → value). Cleared on language change. Guarded by `lock`.
    private nonisolated(unsafe) static var cache: [String: [String: String]] = [:]
    private nonisolated(unsafe) static var bundleCache: [String: Bundle] = [:]

    static func invalidateCache() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll(keepingCapacity: true)
        bundleCache.removeAll(keepingCapacity: true)
    }

    static func string(key: String, language: String) -> String? {
        lock.lock()
        if let hit = cache[language]?[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        for code in languageCandidates(language) {
            if let value = lookup(key: key, inLproj: code) {
                lock.lock()
                cache[language, default: [:]][key] = value
                lock.unlock()
                return value
            }
        }
        return nil
    }

    private static func languageCandidates(_ language: String) -> [String] {
        var codes = [language]
        let prefix = language.split(separator: "-").first.map(String.init) ?? language
        if prefix != language, !language.hasPrefix("zh") {
            codes.append(prefix)
        }
        if language != "en" {
            codes.append("en")
        }
        return codes
    }

    private static func lookup(key: String, inLproj code: String) -> String? {
        let bundle: Bundle? = {
            lock.lock()
            defer { lock.unlock() }
            if let cached = bundleCache[code] { return cached }
            let lprojURL = Bundle.main.bundleURL.appendingPathComponent("\(code).lproj", isDirectory: true)
            guard let b = Bundle(url: lprojURL) else { return nil }
            bundleCache[code] = b
            return b
        }()
        guard let bundle else { return nil }
        // Sentinel: missing keys come back as the key or the value argument.
        let sentinel = "\u{FFFF}"
        let value = bundle.localizedString(forKey: key, value: sentinel, table: nil)
        if value == sentinel || value == key || value.isEmpty { return nil }
        return value
    }
}

enum AppLanguageBundleInstaller {
    private static let lock = NSLock()
    /// Guarded by `lock`.
    private nonisolated(unsafe) static var _didInstall = false

    static func installIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !_didInstall else { return }
        _didInstall = true
        object_setClass(Bundle.main, LanguageAwareBundle.self)
    }
}

private final class LanguageAwareBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let lang = AppLanguageStore.current.resolved.catalogLanguageCode
        if let translated = StringCatalogLookup.string(key: key, language: lang) {
            return translated
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
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
        system.usesImperialMass ? "••• lb" : "••.• kg"
    }
}
