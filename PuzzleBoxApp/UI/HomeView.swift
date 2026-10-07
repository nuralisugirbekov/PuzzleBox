import SwiftUI

/// Personal start page, like Apple Music's Home: a featured carousel,
/// recently played, favorites and a random pick.
struct HomeView: View {
    @Environment(StatsStore.self) private var stats
    @Environment(\.playGame) private var playGame

    private var featured: [GameID] {
        let today = GameID.gameOfTheDay
        return [today] + [.match3, .blockBlast, .solitaire, .sudoku].filter { $0 != today }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Shelf(items: featured, spacing: 12) { id in
                        FeaturedGameCard(gameID: id,
                                         eyebrow: L10n.text(id == .gameOfTheDay ? "Game of the Day" : "Featured"),
                                         source: "home_featured")
                            .containerRelativeFrame(.horizontal) { width, _ in width - 32 }
                    }

                    if !stats.recentGames.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: L10n.text("Recently Played"))
                            Shelf(items: stats.recentGames) { id in
                                ShelfGameTile(gameID: id, source: "home_recent")
                            }
                        }
                    }

                    if !stats.favoriteGames.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(title: L10n.text("Favorites"))
                            Shelf(items: stats.favoriteGames) { id in
                                ShelfGameTile(gameID: id, source: "home_favorites")
                            }
                        }
                    }

                    randomGameCard
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("Home"))
            .toolbar { SettingsToolbarButton() }
        }
    }

    private var randomGameCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stats.totalPlayed)")
                    .font(.largeTitle.bold())
                    .contentTransition(.numericText())
                Text(L10n.text("puzzles played"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let game = GameID.allCases.randomElement() {
                    playGame(game, source: "random")
                }
            } label: {
                Label(L10n.text("Random Game"), systemImage: "dice.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 24))
    }
}
