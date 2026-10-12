import SwiftUI

/// Personal start page, like Apple Music's Home (Figma "Home"): top picks,
/// recently played, more like the last game, popular games and a random pick.
struct HomeView: View {
    @Environment(StatsStore.self) private var stats
    @Environment(\.playGame) private var playGame

    @State private var pickSelection: [GameID] = []

    /// Fallback order for "Popular games" before the player has history.
    private static let curated: [GameID] = [.blockBlast, .solitaire, .sudoku, .game2048, .snake,
                                            .waterSort, .minesweeper, .mergeFruit, .flappyFlight, .checkmate]

    private var topPicks: [GameID] {
        let today = GameID.gameOfTheDay
        return [today] + pickSelection.filter { $0 != today }
    }

    /// The game "More like" is based on: the last one played, else today's pick.
    private var anchor: GameID { stats.recentGames.first ?? .gameOfTheDay }

    private var similar: [GameID] {
        anchor.info.category.games.filter { $0 != anchor }
    }

    private var popular: [GameID] {
        func rank(_ id: GameID) -> Int { Self.curated.firstIndex(of: id) ?? Self.curated.count }
        return GameID.allCases.sorted {
            let lhs = stats.gamesPlayed(for: $0), rhs = stats.gamesPlayed(for: $1)
            return lhs != rhs ? lhs > rhs : rank($0) < rank($1)
        }
        .prefix(10)
        .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    section {
                        SectionTitle(title: L10n.text("Top picks for you"))
                    } content: {
                        Shelf(items: topPicks) { id in
                            TopPickCard(gameID: id, eyebrow: eyebrow(for: id))
                        }
                    }

                    if !stats.recentGames.isEmpty {
                        section {
                            ShelfHeader(title: L10n.text("Recently Played")) {
                                GameCollectionView(title: L10n.text("Recently Played"),
                                                   games: stats.recentGames, source: "home_recent_all")
                            }
                        } content: {
                            shelf(stats.recentGames, source: "home_recent")
                        }
                    }

                    if !similar.isEmpty {
                        section {
                            MoreLikeHeader(gameID: anchor)
                        } content: {
                            shelf(similar, source: "home_more_like")
                        }
                    }

                    section {
                        ShelfHeader(title: L10n.text("Popular games")) {
                            GameCollectionView(title: L10n.text("Popular games"),
                                               games: popular, source: "home_popular_all")
                        }
                    } content: {
                        shelf(popular, source: "home_popular")
                    }

                    randomGameCard
                        .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("Home"))
            .toolbar { SettingsToolbarButton() }
            .onAppear {
                if pickSelection.isEmpty {
                    let today = GameID.gameOfTheDay
                    pickSelection = Array(GameID.allCases.filter { $0 != today }.shuffled().prefix(4))
                }
            }
        }
    }

    /// Header 12pt above its content, as in the design.
    private func section<Header: View, Content: View>(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header()
            content()
        }
    }

    private func shelf(_ games: [GameID], source: String) -> some View {
        Shelf(items: games) { id in
            GameCard(gameID: id, source: source, style: .shelf)
                .frame(width: 172)
        }
    }

    private func eyebrow(for id: GameID) -> String {
        guard let index = topPicks.firstIndex(of: id), index > 0 else { return L10n.text("Game of the Day") }
        return L10n.text(index.isMultiple(of: 2) ? "Popular now" : "Made for you")
    }

    /// Figma "Random game": a full-width row with a glass chevron.
    private var randomGameCard: some View {
        Button {
            if let game = GameID.allCases.randomElement() {
                playGame(game, source: "random")
            }
        } label: {
            HStack {
                Text(L10n.text("Random Game"))
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 50, height: 50)
                    .glassCircle()
            }
            .padding(.horizontal, 16)
            .frame(height: 82)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Figma "Top picks for you" teaser: a tall rounded cover with the reason
/// and the game's title over its bottom-leading corner.
private struct TopPickCard: View {
    let gameID: GameID
    let eyebrow: String

    @Environment(\.playGame) private var playGame

    var body: some View {
        Button {
            playGame(gameID, source: "home_top_picks")
        } label: {
            GamePreviewArt(gameID: gameID)
                .frame(width: 236, height: 277)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(eyebrow)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(gameID.info.title)
                            .font(.body)
                            .foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    .padding(16)
                }
                .clipShape(.rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu { FavoriteMenuButton(gameID: gameID) }
    }
}

/// Figma "More like …": a 48pt thumbnail of the anchor game beside
/// "More like" and its title, linking to the rest of its category.
private struct MoreLikeHeader: View {
    let gameID: GameID

    var body: some View {
        NavigationLink {
            CategoryGamesView(category: gameID.info.category)
        } label: {
            HStack(spacing: 8) {
                GamePreviewArt(gameID: gameID, fade: false)
                    .frame(width: 48, height: 48)
                    .clipShape(.rect(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("More like"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(gameID.info.title)
                        Image(systemName: "chevron.forward").imageScale(.small)
                    }
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
