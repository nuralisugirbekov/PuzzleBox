import SwiftUI

struct LanguageSelectionView: View {
    let onSelect: (AppLanguage) -> Void
    @State private var selectedLanguage: AppLanguage

    init(onSelect: @escaping (AppLanguage) -> Void) {
        self.onSelect = onSelect
        let saved = UserDefaults.standard.string(forKey: L10n.languageKey) ?? ""
        let preferred = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
        _selectedLanguage = State(initialValue: AppLanguage(rawValue: saved)
                                  ?? AppLanguage(rawValue: preferred) ?? .english)
    }

    private func text(_ key: String) -> String {
        L10n.text(key, language: selectedLanguage)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Theme.neon)
                            .frame(width: 64, height: 64)
                            .themeCard(cornerRadius: 18)
                            .padding(.bottom, 8)
                            .accessibilityHidden(true)

                        (Text("Puzzle ").foregroundStyle(.white)
                         + Text("Box").foregroundStyle(Theme.neon))
                            .font(.system(size: 40, weight: .bold, design: .rounded))

                        Text(text("Make yourself at home."))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text("Choose your language"))
                                .font(.title2.bold())
                            Text(text("You can change it later in the main menu."))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Menu {
                            Picker(text("Language"), selection: $selectedLanguage) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(verbatim: language.name)
                                        .tag(language)
                                }
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "globe")
                                    .font(.title3)
                                    .foregroundStyle(Theme.neon)
                                Text(verbatim: selectedLanguage.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(18)
                            .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Theme.stroke, lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel(text("Language"))
                        .accessibilityValue(selectedLanguage.name)
                        .accessibilityIdentifier("language-selector")

                        Button {
                            Haptics.tap()
                            AppAnalytics.selectLanguage(selectedLanguage)
                            onSelect(selectedLanguage)
                        } label: {
                            HStack(spacing: 10) {
                                Text(text("Continue"))
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(Theme.neon, in: RoundedRectangle(cornerRadius: 14))
                            .neonGlow(0.2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("language-continue")
                    }
                    .padding(24)
                    .themeCard(cornerRadius: 24)
                }
                .frame(maxWidth: 440)
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { AppAnalytics.screen("language_selection") }
    }
}

struct AppRootView: View {
    @AppStorage(L10n.languageKey) private var languageCode = ""

    var body: some View {
        Group {
            if let language = AppLanguage(rawValue: languageCode) {
                RootTabView()
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .id(language)
            } else {
                LanguageSelectionView { language in
                    languageCode = language.rawValue
                }
            }
        }
    }
}
