import SwiftUI

struct MainMenuView: View {
    @Environment(StatsStore.self) private var stats
    @AppStorage(L10n.languageKey) private var languageCode = ""
    @State private var showingLanguages = false
    @State private var searchText = ""
    @State private var filter: GameCategory? = nil
    @State private var activeGame: GameID?

    private var filteredGames: [GameID] {
        GameID.allCases.filter { id in
            let info = id.info
            let matchesFilter = filter == nil || info.category == filter
            let matchesSearch = searchText.isEmpty
                || info.title.localizedCaseInsensitiveContains(searchText)
                || (id == .numberConnect && ("Number Connect".localizedCaseInsensitiveContains(searchText) || L10n.text("Number Connect").localizedCaseInsensitiveContains(searchText)))
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                quickPlayCard
                searchBar
                filterChips
                gameGrid
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .onAppear { AppAnalytics.screen("main_menu") }
        .onChange(of: filter) { _, category in
            AppAnalytics.log("category_selected", parameters: [
                "game_category": category?.rawValue.lowercased() ?? "all"
            ])
        }
        .sheet(isPresented: $showingLanguages, onDismiss: {
            AppAnalytics.screen("main_menu")
        }) {
            LanguageSelectionView { language in
                showingLanguages = false
                languageCode = language.rawValue
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $activeGame) { id in
            gameView(for: id)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("Puzzle ").foregroundStyle(.white)
                    + Text("Box").foregroundStyle(Theme.neon))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(L10n.text("Pick a game and start winning"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { showingLanguages = true } label: {
                Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(Theme.neon)
                .frame(width: 48, height: 48)
                .themeCard(cornerRadius: 14)
            }
            .accessibilityLabel(L10n.text("Language"))
        }
        .padding(.top, 12)
    }

    // MARK: Quick play header

    private var quickPlayCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stats.totalPlayed)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.neon)
                    .contentTransition(.numericText())
                Text(L10n.text("puzzles played"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Haptics.tap()
                if let game = GameID.allCases.randomElement() {
                    AppAnalytics.selectGame(game, source: "random")
                    activeGame = game
                }
            } label: {
                Label(L10n.text("Random Game"), systemImage: "dice.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(Theme.neon, in: Capsule())
                    .neonGlow()
            }
        }
        .padding(20)
        .themeCard(cornerRadius: 20)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Theme.neon.opacity(0.25), lineWidth: 1)
        }
    }

    // MARK: Search & filter

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField(L10n.text("Search games"), text: $searchText)
                .autocorrectionDisabled()
                .tint(Theme.neon)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(13)
        .themeCard(cornerRadius: 12)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: L10n.text("All"), isSelected: filter == nil) { filter = nil }
                ForEach(GameCategory.allCases) { category in
                    chip(title: L10n.text(category.rawValue), isSelected: filter == category) {
                        filter = category
                    }
                }
            }
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? Theme.neon : Theme.surface, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.clear : Theme.stroke, lineWidth: 1)
                }
                .foregroundStyle(isSelected ? .black : .white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Game grid

    private var gameGrid: some View {
        Group {
            if filteredGames.isEmpty {
                ContentUnavailableView {
                    Label(L10n.text("No games found"), systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.text("Try another search."))
                }
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(filteredGames) { id in
                        Button {
                            Haptics.tap()
                            AppAnalytics.selectGame(id, source: searchText.isEmpty ? "grid" : "search")
                            activeGame = id
                        } label: {
                            GameCardView(gameID: id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Game card

struct GameCardView: View {
    let gameID: GameID
    @Environment(StatsStore.self) private var stats

    var body: some View {
        let info = gameID.info
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(info.tint.gradient)
                Image(systemName: info.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(height: 88)

            Text(info.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(info.tagline)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2, reservesSpace: true)

            HStack {
                Text(L10n.text(info.difficulty.rawValue))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(info.difficulty.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(info.difficulty.tint)
                Spacer()
                Label("\(stats.highScore(for: gameID))", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(12)
        .themeCard(cornerRadius: 18)
    }
}
