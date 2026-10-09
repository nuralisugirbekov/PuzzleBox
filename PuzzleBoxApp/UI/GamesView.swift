import SwiftUI

/// The Games tab: the player's liked games in the Figma "All games" grid.
struct MyGamesView: View {
    /// Switches to the Discover tab from the empty state.
    var onDiscover: () -> Void = {}

    @Environment(StatsStore.self) private var stats

    var body: some View {
        NavigationStack {
            ScrollView {
                if stats.favoriteGames.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.text("No Favorites Yet"), systemImage: "heart")
                    } description: {
                        Text(L10n.text("Tap the heart on any game to keep it here."))
                    } actions: {
                        Button(L10n.text("Discover Games"), action: onDiscover)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                    }
                    .padding(.top, 80)
                } else {
                    GameGrid(games: stats.favoriteGames, source: "my_games")
                        .padding(.horizontal)
                        .padding(.bottom)
                        .animation(.snappy, value: stats.favoriteGames)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("My Games"))
            .toolbar { SettingsToolbarButton() }
        }
    }
}

/// Two-column grid of `GameCard`s, 8pt apart.
struct GameGrid: View {
    let games: [GameID]
    var source: String = "grid"

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)],
                  spacing: 8) {
            ForEach(games) { id in
                GameCard(gameID: id, source: source)
            }
        }
    }
}

/// Games from a single category, pushed from Discover and Search.
struct CategoryGamesView: View {
    let category: GameCategory

    var body: some View {
        ScrollView {
            GameGrid(games: GameID.visibleGames.filter { $0.info.category == category },
                     source: "category")
                .padding(.horizontal)
                .padding(.bottom)
        }
        .background(Color(.systemBackground))
        .navigationTitle(L10n.text(category.rawValue))
    }
}
