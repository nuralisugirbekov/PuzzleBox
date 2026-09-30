import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case kazakh = "kk"
    case english = "en"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .russian: "Русский"
        case .kazakh: "Қазақша"
        case .english: "English"
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
