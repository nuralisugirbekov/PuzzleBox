import SwiftUI

/// The Games tab: the player's liked games in the Figma "All games" grid.
struct MyGamesView: View {
    /// Switches to the Discover tab from the empty state.
    var onDiscover: () -> Void = {}

    @Environment(StatsStore.self) private var stats

    var body: some View {
        NavigationStack {
            ScrollView {
                TabHeader(title: L10n.text("My Games"))
                    .padding(.bottom, 16)

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
            .tabRoot(title: L10n.text("My Games"))
        }
    }
}

/// Two-column grid of `GameCard`s.
struct GameGrid: View {
    let games: [GameID]
    var source: String = "grid"

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: GameCard.spacing),
                            GridItem(.flexible(), spacing: GameCard.spacing)],
                  spacing: GameCard.rowSpacing) {
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
            GameGrid(games: GameID.catalog.filter { $0.info.category == category },
                     source: "category")
                .padding(.horizontal)
                .padding(.bottom)
        }
        .background(Color(.systemBackground))
        .navigationTitle(L10n.text(category.rawValue))
    }
}

/// A titled grid of games, pushed from a Home shelf header.
struct GameCollectionView: View {
    let title: String
    let games: [GameID]
    var source: String = "collection"

    var body: some View {
        ScrollView {
            GameGrid(games: games, source: source)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .background(Color(.systemBackground))
        .navigationTitle(title)
    }
}
