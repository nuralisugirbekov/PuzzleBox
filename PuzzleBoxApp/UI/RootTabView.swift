import SwiftUI
import UIKit

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case home, discover, friends, games, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: L10n.text("Home")
        case .discover: L10n.text("Discover")
        case .friends: L10n.text("Friends")
        case .games: L10n.text("Games")
        case .search: L10n.text("Search")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .discover: "globe"
        case .friends: "person.2"
        case .games: "gamecontroller.fill"
        case .search: "magnifyingglass"
        }
    }

    static let mainTabs: [AppTab] = [.home, .discover, .friends, .games]
}

/// What the full-screen game cover is showing.
enum PresentedGame: Identifiable, Hashable {
    case solo(GameID)
    case online(MatchRef)
    case nearby(NearbyMatchRef)

    var id: String {
        switch self {
        case .solo(let game): "solo-" + game.rawValue
        case .online(let match): "online-" + match.id
        case .nearby(let match): "nearby-" + match.id
        }
    }
}

/// Apple Music–style shell: four content tabs plus a detached search tab.
/// Owns game presentation so every screen launches games the same way.
struct RootTabView: View {
    @Environment(StatsStore.self) private var stats
    @Environment(FriendsStore.self) private var friends
    @Environment(NearbyStore.self) private var nearby
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @State private var selection: AppTab = .home
    @State private var presented: PresentedGame?
    /// A two-player game waiting for "vs Bot" or "vs Friend".
    @State private var choosingOpponent: GameID?
    /// A game to open once the opponent picker has finished closing.
    @State private var queued: PresentedGame?

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
                if id.supportsFriends {
                    choosingOpponent = id
                } else {
                    stats.markOpened(id)
                    presented = .solo(id)
                }
            })
            .sheet(item: $choosingOpponent, onDismiss: {
                if let queued {
                    self.queued = nil
                    presented = queued
                }
            }) { game in
                OpponentPickerView(game: game) {
                    stats.markOpened(game)
                    present(.solo(game))
                }
            }
            .fullScreenCover(item: $presented, onDismiss: {
                // Swapping one game for another dismisses too; only a closed cover ends the match.
                guard presented == nil else { return }
                friends.roomMatchFinished()
                // The nearby game screen was closed: leave its room. Done here rather than
                // when the screen disappears, which can happen without the player leaving.
                if nearby.matchState != nil { nearby.leave() }
            }) { item in
                Group {
                    switch item {
                    case .solo(let id): GameSessionView(initialGame: id)
                    case .online(let match): onlineGameView(for: match)
                    case .nearby(let match): matchView(for: match.game, transport: NearbyMatchSession(store: nearby, game: match.game))
                    }
                }
                .roomLobby()
                .incomingInviteBanner()
            }
            .roomLobby()
            .incomingInviteBanner()
            .onChange(of: friends.pendingMatch) { _, match in
                guard let match else { return }
                friends.pendingMatch = nil
                stats.markOpened(match.game)
                present(.online(match))
            }
            .onChange(of: nearby.pendingMatch) { _, match in
                guard let match else { return }
                nearby.pendingMatch = nil
                stats.markOpened(match.game)
                present(.nearby(match))
            }
            .onChange(of: selection, initial: true) { _, tab in
                AppAnalytics.screen(tab.rawValue)
            }
            .task { await friends.start() }
            .onChange(of: scenePhase) { _, phase in
                friends.setActive(phase == .active)
            }
            // Keeps the stats on the player's profile current (unless they hide them).
            .onChange(of: StatsSnapshot(stats: stats, ready: friends.status == .ready), initial: true) { _, snapshot in
                if snapshot.ready { friends.publish(PublicStats(stats: stats)) }
            }
    }

    /// Opens `game` full screen. With the opponent picker up (and the nearby
    /// room sheet on top of it), the picker closes first: covering it while
    /// it's still closing can make UIKit drop the cover again, which for a
    /// nearby game used to end it for everyone.
    private func present(_ game: PresentedGame) {
        if choosingOpponent != nil {
            queued = game
            choosingOpponent = nil
        } else {
            presented = game
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
                ForEach(AppTab.mainTabs + [.search]) { tab in
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
        case .friends: FriendsView()
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
/// Gear in a glass circle that opens Settings; sits in each tab's `TabHeader`.
struct SettingsButton: View {
    @State private var showingSettings = false

    var body: some View {
        HeaderCircleButton(symbol: "gear", label: L10n.text("Settings")) {
            showingSettings = true
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats
    @AppStorage(L10n.languageKey) private var languageCode = ""
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @AppStorage(SoundFX.enabledKey) private var soundEnabled = true
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true

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
                    Picker(L10n.text("Language"), selection: Binding(
                        get: { languageCode },
                        set: { code in
                            guard let language = AppLanguage(rawValue: code), code != languageCode else { return }
                            Haptics.tap()
                            AppAnalytics.selectLanguage(language)
                            languageCode = code
                        }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.name).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section {
                    Toggle(isOn: $soundEnabled) {
                        Label(L10n.text("Sound"), systemImage: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    Toggle(isOn: $hapticsEnabled) {
                        Label(L10n.text("Haptics"), systemImage: hapticsEnabled ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    }
                    .onChange(of: hapticsEnabled) { _, enabled in
                        // Confirm the switch on, the one moment a buzz is expected.
                        if enabled { Haptics.tap() }
                        AppAnalytics.log("haptics_toggled", parameters: ["enabled": enabled])
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
                            // The toolbar pads this to its 44pt glass circle; the frame makes
                            // that whole circle, not only the glyph, take the tap.
                            .frame(width: 32, height: 32)
                            .contentShape(.circle)
                    }
                    .accessibilityLabel(L10n.text("Done"))
                }
            }
        }
        .onAppear { AppAnalytics.screen("settings") }
    }
}

/// Keeps random-game navigation inside the existing full-screen presentation.
private struct GameSessionView: View {
    @Environment(StatsStore.self) private var stats
    @State private var currentGame: GameID
    /// Lets each game opened here offer its saved round exactly once.
    @State private var resumeOffer = ResumeOffer()

    init(initialGame: GameID) {
        _currentGame = State(initialValue: initialGame)
        let offer = ResumeOffer()
        offer.open(initialGame)
        _resumeOffer = State(initialValue: offer)
    }

    var body: some View {
        gameView(for: currentGame)
            .id(currentGame)
            .environment(\.resumeOffer, resumeOffer)
            .environment(\.playGame, PlayGameAction { id, source in
                // Games switched to from here (e.g. a random pick) are played against the bot.
                AppAnalytics.selectGame(id, source: source)
                stats.markOpened(id)
                resumeOffer.open(id)
                currentGame = id
            })
    }
}

/// What changes the shared stats, so they are published only when needed.
private struct StatsSnapshot: Equatable {
    let played: Int
    let favorites: Int
    let ready: Bool

    @MainActor
    init(stats: StatsStore, ready: Bool) {
        played = stats.totalPlayed
        favorites = stats.favoriteGames.count
        self.ready = ready
    }
}
