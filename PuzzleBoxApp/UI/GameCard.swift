import SwiftUI

// MARK: - Game card (Figma "All games" › Album Teaser)

/// Apple Music–style teaser: a square, unrounded preview with a glass heart
/// in its corner, and the game's title and one-line description underneath.
/// The long-press menu offers the same favorite toggle.
struct GameCard: View {
    /// `.grid` is the "All games" teaser; `.shelf` is the Home page variant
    /// with an 8pt-rounded cover and a 17pt title.
    enum Style { case grid, shelf }

    let gameID: GameID
    var source: String = "grid"
    var style: Style = .grid

    @Environment(StatsStore.self) private var stats
    @Environment(\.playGame) private var playGame

    /// Figma teaser width (two columns on a 390pt screen) and the gaps.
    static let width: CGFloat = 171
    static let spacing: CGFloat = 16
    static let rowSpacing: CGFloat = 8

    var body: some View {
        let info = gameID.info
        VStack(alignment: .leading, spacing: 6) {
            Button(action: play) {
                GamePreviewArt(gameID: gameID, fade: false)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: style == .shelf ? 8 : 0))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(info.title)
            .accessibilityHint(info.tagline)
            // Figma: 50pt glass heart, 4pt in from the cover's bottom-trailing corner.
            .overlay(alignment: .bottomTrailing) {
                FavoriteButton(gameID: gameID)
                    .padding(4)
            }

            Button(action: play) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(info.title)
                        .font(style == .shelf ? .body : .subheadline)
                        .foregroundStyle(.primary)
                    Text(info.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // The cover button already announces the game.
            .accessibilityHidden(true)
        }
        .contextMenu {
            FavoriteMenuButton(gameID: gameID)
        }
    }

    private func play() {
        playGame(gameID, source: source)
    }
}

/// "Add to / Remove from Favorites" for a game's context menu.
struct FavoriteMenuButton: View {
    let gameID: GameID
    @Environment(StatsStore.self) private var stats

    var body: some View {
        let isFavorite = stats.isFavorite(gameID)
        Button {
            Haptics.tap()
            withAnimation(.snappy) { stats.toggleFavorite(gameID) }
            AppAnalytics.log(isFavorite ? "favorite_removed" : "favorite_added",
                             parameters: ["game_id": gameID.rawValue])
        } label: {
            Label(L10n.text(isFavorite ? "Remove from Favorites" : "Add to Favorites"),
                  systemImage: isFavorite ? "heart.slash" : "heart")
        }
    }
}

/// Circular Liquid Glass heart toggle.
struct FavoriteButton: View {
    static let size: CGFloat = 50

    let gameID: GameID
    @Environment(StatsStore.self) private var stats

    var body: some View {
        let isFavorite = stats.isFavorite(gameID)
        Button {
            Haptics.tap()
            withAnimation(.snappy) { stats.toggleFavorite(gameID) }
            AppAnalytics.log(isFavorite ? "favorite_removed" : "favorite_added",
                             parameters: ["game_id": gameID.rawValue])
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.title2)
                .foregroundStyle(isFavorite ? Color.pink : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.size, height: Self.size)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(isFavorite ? "Remove from Favorites" : "Add to Favorites"))
    }
}

extension View {
    /// Liquid Glass on iOS 26, a thin material circle on earlier systems.
    /// The whole circle is the hit target, not just the glyph inside it.
    func glassCircle() -> some View {
        contentShape(.circle).glassCircleSurface()
    }

    @ViewBuilder
    private func glassCircleSurface() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: .circle)
        }
    }
}

// MARK: - Preview artwork

/// A game's flat illustration (GameArtwork), optionally fading to black at
/// the bottom.
struct GamePreviewArt: View {
    let gameID: GameID
    /// Darkens the bottom so overlaid text and buttons stay legible.
    var fade = true

    var body: some View {
        GameArtwork(gameID: gameID)
            .overlay {
                if fade {
                    // Fade starts 105pt down a 178pt preview; proportional so it scales.
                    LinearGradient(stops: [.init(color: .clear, location: 105 / 178),
                                           .init(color: .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
