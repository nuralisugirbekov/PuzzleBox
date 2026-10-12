import SwiftUI

/// Browse page, like Apple Music's New/Browse: the game of the day,
/// a shelf per category, quick picks, category tiles and every game.
struct DiscoverView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    FeaturedGameCard(gameID: .gameOfTheDay,
                                     eyebrow: L10n.text("Game of the Day"),
                                     source: "discover_daily")
                        .padding(.horizontal)

                    ForEach(GameCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 12) {
                            ShelfHeader(title: L10n.text(category.rawValue)) {
                                CategoryGamesView(category: category)
                            }
                            Shelf(items: category.games, spacing: GameCard.spacing) { id in
                                GameCard(gameID: id, source: "discover_\(category.rawValue.lowercased())")
                                    .frame(width: GameCard.width)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: L10n.text("Quick and Easy"))
                        Shelf(items: GameID.allCases.filter { $0.info.difficulty == .easy }, spacing: GameCard.spacing) { id in
                            GameCard(gameID: id, source: "discover_easy")
                                .frame(width: GameCard.width)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: L10n.text("Browse Categories"))
                        CategoryGrid()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: L10n.text("All games"))
                        GameGrid(games: GameID.allCases, source: "discover_all")
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("Discover"))
            .toolbar { SettingsToolbarButton() }
        }
    }
}
