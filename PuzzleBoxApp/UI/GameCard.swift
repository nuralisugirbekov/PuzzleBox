import SwiftUI

// MARK: - Game card (Figma "All games" › Card)

/// Two-column grid card: an isometric game preview with a glass favorite
/// button, and the game title underneath.
struct GameCard: View {
    let gameID: GameID
    var source: String = "grid"

    @Environment(StatsStore.self) private var stats
    @Environment(\.playGame) private var playGame

    private static let previewHeight: CGFloat = 178

    var body: some View {
        Button {
            playGame(gameID, source: source)
        } label: {
            VStack(spacing: 8) {
                GamePreviewArt(gameID: gameID)
                    .frame(height: Self.previewHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(.rect(cornerRadius: 24))

                Text(gameID.info.title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .frame(height: 239, alignment: .top)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 32))
            .contentShape(.rect(cornerRadius: 32))
        }
        .buttonStyle(.plain)
        // The heart sits over the preview's bottom-trailing corner, 8pt in.
        .overlay(alignment: .topTrailing) {
            FavoriteButton(gameID: gameID)
                .padding(.top, 8 + Self.previewHeight - 8 - FavoriteButton.size)
                .padding(.trailing, 16)
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
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: .circle)
        }
    }
}

// MARK: - Preview artwork

/// The "vis" block of a card: an isometric snapshot of the game on a
/// tertiary background, fading to black at the bottom.
struct GamePreviewArt: View {
    let gameID: GameID
    /// Enlarges the artwork for frames wider than the grid card.
    var artScale: CGFloat = 1

    var body: some View {
        // Artwork lives in an overlay so its oversized, transformed frame
        // never changes the card's layout size.
        Color(gameID == .blockBlast ? .systemBackground : .tertiarySystemBackground)
            .overlay {
                switch gameID {
                case .match3:
                    Match3PreviewArt()
                case .blockBlast:
                    BlockBlastPreviewArt()
                default:
                    TilePreviewArt(info: gameID.info, seed: gameID.rawValue)
                }
            }
            .scaleEffect(artScale)
            .overlay {
                // Fade starts 105pt down a 178pt preview; proportional so it scales.
                LinearGradient(stops: [.init(color: .clear, location: 105 / 178),
                                       .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Figma "image 2": the Match-3 screenshot, cropped into a square and laid flat.
private struct Match3PreviewArt: View {
    private let side: CGFloat = 268.577

    var body: some View {
        Image("Match3Preview")
            .resizable()
            .frame(width: side * 2.2137, height: side * 1.3275)
            .offset(x: -side * 0.3804, y: -side * 0.2313)
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
            .isometric()
            .offset(x: 0.09, y: 6.29)
    }
}

/// Figma "Block blast": a miniature of the game board and piece tray.
private struct BlockBlastPreviewArt: View {
    // Board snapshot from the design, row by row.
    private static let board = [
        "IIIGGG..",
        "IIIG....",
        "IIIPP...",
        "....PP..",
        ".....KK.",
        "..YY.KK.",
        "...Y....",
        "...Y....",
    ]

    private static func color(_ code: Character) -> Color {
        switch code {
        case "I": .indigo
        case "G": .green
        case "P": .purple
        case "K": .pink
        case "Y": .yellow
        default: Color(.tertiarySystemBackground)
        }
    }

    private let unit: CGFloat = 1.5524

    var body: some View {
        VStack(spacing: 12.419) {
            boardGrid
            tray
            VStack(spacing: 0) {
                // Plain fill: glass doesn't render well under the projection.
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 9))
                    .frame(width: 22, height: 22)
                    .background(Color(.tertiarySystemFill), in: .circle)
                Text(L10n.text("Revert"))
                    .font(.system(size: 10.867))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6.21)
        .padding(.top, 45)
        .frame(width: 156.018, height: 339.203, alignment: .top)
        .background(Color(.systemBackground))
        .isometric()
        // Figma places the snapshot slightly left of and above the card centre.
        .offset(x: -16.06, y: -1.2)
    }

    private var boardGrid: some View {
        Grid(horizontalSpacing: unit, verticalSpacing: unit) {
            ForEach(Self.board.indices, id: \.self) { row in
                GridRow {
                    ForEach(Array(Self.board[row].enumerated()), id: \.offset) { _, code in
                        RoundedRectangle(cornerRadius: unit)
                            .fill(Self.color(code))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
        }
        .padding(unit)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: unit * 2))
    }

    private var tray: some View {
        HStack(spacing: unit * 2) {
            trayPiece([(0, 0), (0, 1), (1, 1), (2, 1)], color: .yellow)
            trayPiece((0..<3).flatMap { r in (0..<3).map { (r, $0) } }, color: .indigo)
            trayPiece([(0, 0), (0, 1), (1, 1), (1, 2)], color: .purple)
        }
        .padding(.horizontal, unit * 2)
    }

    private func trayPiece(_ cells: [(Int, Int)], color: Color) -> some View {
        let cell: CGFloat = 9.314, step: CGFloat = 10.09
        let rows = (cells.map(\.0).max() ?? 0) + 1
        let cols = (cells.map(\.1).max() ?? 0) + 1
        return Color(.secondarySystemBackground)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack(alignment: .topLeading) {
                    ForEach(cells.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: unit)
                            .fill(color)
                            .frame(width: cell, height: cell)
                            .offset(x: CGFloat(cells[i].1) * step, y: CGFloat(cells[i].0) * step)
                    }
                }
                .frame(width: CGFloat(cols - 1) * step + cell,
                       height: CGFloat(rows - 1) * step + cell,
                       alignment: .topLeading)
            }
            .clipShape(.rect(cornerRadius: unit * 2))
    }
}

/// Generic preview for games without bespoke artwork: an isometric board of
/// tinted tiles with the game's symbol on the highlighted ones.
private struct TilePreviewArt: View {
    let info: GameInfo
    let seed: String

    private let size = 7

    var body: some View {
        let lit = litTiles
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<size, id: \.self) { row in
                GridRow {
                    ForEach(0..<size, id: \.self) { col in
                        let isLit = lit.contains(row * size + col)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isLit ? AnyShapeStyle(info.tint.gradient)
                                        : AnyShapeStyle(Color(.secondarySystemBackground)))
                            .frame(width: 34, height: 34)
                            .overlay {
                                if isLit {
                                    Image(systemName: info.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .rotationEffect(.degrees(-30))
                                }
                            }
                    }
                }
            }
        }
        .isometric()
        .offset(y: 6)
    }

    /// A stable, per-game scatter of highlighted tiles.
    private var litTiles: Set<Int> {
        var state = seed.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        var result = Set<Int>()
        while result.count < 14 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            result.insert(Int((state >> 33) % UInt64(size * size)))
        }
        return result
    }
}

// MARK: - Isometric projection

extension View {
    /// The design's `rotate(30°) skewX(-30°) scaleY(0.87)` isometric
    /// transform, applied around the view's centre.
    func isometric() -> some View {
        modifier(IsometricEffect())
    }
}

private struct IsometricEffect: GeometryEffect {
    var animatableData: EmptyAnimatableData {
        get { EmptyAnimatableData() }
        set {}
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = CGFloat.pi / 6
        let rotate = CGAffineTransform(rotationAngle: angle)
        let skew = CGAffineTransform(a: 1, b: 0, c: tan(-angle), d: 1, tx: 0, ty: 0)
        let scale = CGAffineTransform(scaleX: 1, y: 0.87)
        // CSS applies the rightmost function first: scale, then skew, then rotate.
        let projection = scale.concatenating(skew).concatenating(rotate)
        let transform = CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(projection)
            .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
        return ProjectionTransform(transform)
    }
}
