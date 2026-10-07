import SwiftUI
import UIKit

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case home, discover, rating, games, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: L10n.text("Home")
        case .discover: L10n.text("Discover")
        case .rating: L10n.text("Rating")
        case .games: L10n.text("Games")
        case .search: L10n.text("Search")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .discover: "globe"
        case .rating: "flag.and.flag.filled.crossed"
        case .games: "gamecontroller.fill"
        case .search: "magnifyingglass"
        }
    }

    static let mainTabs: [AppTab] = [.home, .discover, .rating, .games]
}

/// Apple Music–style shell: four content tabs plus a detached search tab.
/// Owns game presentation so every screen launches games the same way.
struct RootTabView: View {
    @Environment(StatsStore.self) private var stats
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @State private var selection: AppTab = .home
    @State private var activeGame: GameID?

    var body: some View {
        tabs
            // Set on the window rather than via preferredColorScheme, which
            // doesn't reliably revert open sheets when switching back to system.
            .onChange(of: theme, initial: true) { _, theme in
                theme.apply()
            }
            .environment(\.playGame, PlayGameAction { id, source in
                Haptics.tap()
                AppAnalytics.selectGame(id, source: source)
                stats.markOpened(id)
                activeGame = id
            })
            .fullScreenCover(item: $activeGame) { id in
                gameView(for: id)
            }
            .onChange(of: selection, initial: true) { _, tab in
                AppAnalytics.screen(tab.rawValue)
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                ForEach(AppTab.mainTabs) { tab in
                    Tab(tab.title, systemImage: tab.symbol, value: tab) {
                        screen(for: tab)
                    }
                }
                Tab(value: AppTab.search, role: .search) {
                    screen(for: .search)
                }
            }
            .minimizeTabBarOnScroll()
        } else {
            TabView(selection: $selection) {
                ForEach(AppTab.allCases) { tab in
                    screen(for: tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .discover: DiscoverView()
        case .rating: RatingView()
        case .games: MyGamesView { selection = .discover }
        case .search: SearchView()
        }
    }
}

private extension View {
    @ViewBuilder
    func minimizeTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

// MARK: - Launching games

/// Opens a game full screen. `source` is reported to analytics.
struct PlayGameAction {
    var action: @MainActor (GameID, String) -> Void

    @MainActor
    func callAsFunction(_ id: GameID, source: String) {
        action(id, source)
    }
}

extension EnvironmentValues {
    @Entry var playGame = PlayGameAction { _, _ in }
}

// MARK: - Appearance

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appTheme"

    var id: String { rawValue }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies the theme to every window, including presented sheets.
    @MainActor
    func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }

    var title: String {
        switch self {
        case .system: L10n.text("Automatic")
        case .light: L10n.text("Light")
        case .dark: L10n.text("Dark")
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
}

// MARK: - Settings

/// Gear button shown in every tab's navigation bar.
struct SettingsToolbarButton: ToolbarContent {
    @State private var showingSettings = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
            }
            .accessibilityLabel(L10n.text("Settings"))
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats
    @AppStorage(L10n.languageKey) private var languageCode = ""
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.text("Appearance")) {
                    Picker(L10n.text("Appearance"), selection: $theme) {
                        ForEach(AppTheme.allCases) { option in
                            Label(option.title, systemImage: option.symbol)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .onChange(of: theme) { _, newTheme in
                        Haptics.tap()
                        AppAnalytics.log("theme_selected", parameters: ["theme": newTheme.rawValue])
                    }
                }
                Section(L10n.text("Language")) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            Haptics.tap()
                            AppAnalytics.selectLanguage(language)
                            languageCode = language.rawValue
                        } label: {
                            HStack {
                                Text(language.name)
                                    .foregroundStyle(Color(.label))
                                Spacer()
                                if languageCode == language.rawValue {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
                Section(L10n.text("Statistics")) {
                    LabeledContent(L10n.text("Games played"), value: "\(stats.totalPlayed)")
                    LabeledContent(L10n.text("Favorites"), value: "\(stats.favoriteGames.count)")
                }
            }
            .navigationTitle(L10n.text("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(L10n.text("Done"))
                }
            }
        }
        .onAppear { AppAnalytics.screen("settings") }
    }
}
