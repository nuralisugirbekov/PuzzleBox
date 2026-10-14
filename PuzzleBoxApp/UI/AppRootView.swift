import SwiftUI

/// There is no language prompt: the app starts in the system language when it is
/// translated (otherwise English). The choice can still be changed in Settings.
struct AppRootView: View {
    @AppStorage(L10n.languageKey) private var languageCode = ""

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .systemDefault }

    var body: some View {
        RootTabView()
            .environment(\.locale, Locale(identifier: language.rawValue))
            .id(language)
            .onAppear {
                // Remember the automatic choice so every screen and the analytics agree on it.
                if AppLanguage(rawValue: languageCode) == nil {
                    languageCode = language.rawValue
                    AppAnalytics.updateLanguageProperty()
                }
            }
    }
}
