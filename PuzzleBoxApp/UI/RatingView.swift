import SwiftUI

/// Personal leaderboard: every game ranked by the player's best score.
/// Pushed from the Friends tab.
struct RatingContent: View {
    @Environment(StatsStore.self) private var stats
    @Environment(\.playGame) private var playGame

    private var ranked: [GameID] {
        GameID.allCases.sorted {
            let lhs = stats.highScore(for: $0), rhs = stats.highScore(for: $1)
            return lhs != rhs ? lhs > rhs : stats.gamesPlayed(for: $0) > stats.gamesPlayed(for: $1)
        }
    }

    var body: some View {
            List {
                Section {
                    summary
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section(L10n.text("Your Records")) {
                    ForEach(Array(ranked.enumerated()), id: \.element) { index, id in
                        Button {
                            playGame(id, source: "rating")
                        } label: {
                            RatingRow(rank: index + 1, gameID: id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.text("Your Records"))
    }

    private var summary: some View {
        let played = GameID.allCases.filter { stats.gamesPlayed(for: $0) > 0 }.count
        return HStack(spacing: 12) {
            statTile(value: stats.totalPlayed, title: L10n.text("Games played"), symbol: "play.fill", tint: .blue)
            statTile(value: played, title: L10n.text("Games tried"), symbol: "checkmark.seal.fill", tint: .green)
            statTile(value: stats.favoriteGames.count, title: L10n.text("Favorites"), symbol: "heart.fill", tint: .pink)
        }
    }

    private func statTile(value: Int, title: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.title.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
    }
}

private struct RatingRow: View {
    let rank: Int
    let gameID: GameID
    @Environment(StatsStore.self) private var stats

    var body: some View {
        let info = gameID.info
        let best = stats.highScore(for: gameID)
        HStack(spacing: 12) {
            rankBadge
            GamePreviewArt(gameID: gameID, fade: false)
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(L10n.format("Played: %d", stats.gamesPlayed(for: gameID)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Spacer()
            Label("\(best)", systemImage: "trophy.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(best > 0 ? .yellow : .secondary)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private var rankBadge: some View {
        let medal: Color? = switch rank {
        case 1 where stats.highScore(for: gameID) > 0: .yellow
        case 2 where stats.highScore(for: gameID) > 0: Color(.systemGray)
        case 3 where stats.highScore(for: gameID) > 0: .orange
        default: nil
        }
        Text("\(rank)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(medal ?? .secondary)
            .frame(width: 28)
    }
}
