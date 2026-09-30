import Foundation
import Testing
@testable import PuzzleBoxApp

struct LocalizationTests {
    @MainActor
    @Test func translatedResourcesAreComplete() throws {
        let englishURL = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let english = try #require(NSDictionary(contentsOf: englishURL) as? [String: String])
        for language in [AppLanguage.russian, .kazakh] {
            let url = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language.rawValue))
            let translations = try #require(NSDictionary(contentsOf: url) as? [String: String])
            #expect(Set(translations.keys) == Set(english.keys))
            #expect(translations.values.allSatisfy { !$0.isEmpty })
            #expect(L10n.text("Resume", language: language) != "Resume")
        }
    }
}
