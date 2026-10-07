import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case kazakh = "kk"
    case english = "en"
    case french = "fr"
    case hindi = "hi"
    case german = "de"
    case chinese = "zh-Hans"
    case korean = "ko"

    static func matching(_ identifier: String) -> AppLanguage? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if let exact = AppLanguage(rawValue: normalized) { return exact }
        let base = normalized.components(separatedBy: "-").first ?? normalized
        // Simplified Chinese is currently the supported Chinese localization.
        return base == "zh" ? .chinese : AppLanguage(rawValue: base)
    }

    var id: String { rawValue }
    var name: String {
        switch self {
        case .russian: "Русский"
        case .kazakh: "Қазақша"
        case .english: "English"
        case .french: "Français"
        case .hindi: "हिन्दी"
        case .german: "Deutsch"
        case .chinese: "简体中文"
        case .korean: "한국어"
        }
    }
}

enum L10n {
    static let languageKey = "appLanguage"

    static var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .english
    }

    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? self.language
        guard let path = Bundle.main.path(forResource: selected.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
