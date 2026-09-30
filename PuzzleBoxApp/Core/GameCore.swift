import SwiftUI
import UIKit
import Observation

// MARK: - Shared primitives

/// A cell position on any game grid. Row 0 is the top row.
struct GridPos: Hashable {
    var r: Int
    var c: Int
}

enum GameState: Equatable {
    case playing
    case paused
    case gameOver(won: Bool)
}

/// Every mini-game exposes its engine through this protocol so the shared
/// `GameContainerView` can drive the header, pause/game-over overlays,
/// and high-score recording. Adding a new game = new engine + view + registry entry.
@MainActor
protocol GameEngine: AnyObject, Observable {
    var score: Int { get }
    var state: GameState { get set }
    func restart()
}

// MARK: - Game registry

enum GameCategory: String, CaseIterable, Identifiable {
    case logic = "Logic"
    case casual = "Casual"
    case arcade = "Arcade"
    case cards = "Cards"
    var id: String { rawValue }
}

enum Difficulty: String {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var tint: Color {
        switch self {
        case .easy: .green
        case .medium: .orange
        case .hard: .red
        }
    }
}

struct GameInfo {
    let title: String
    let tagline: String
    let symbol: String
    let tint: Color
    let category: GameCategory
    let difficulty: Difficulty
}

enum GameID: String, CaseIterable, Identifiable {
    case match3
    case sudoku
    case snake
    case blockBlast
    case waterSort
    case solitaire
    case spiderSolitaire
    case freecell
    case spades
    case minesweeper
    case checkmate
    case dominoes

    var id: String { rawValue }

    var info: GameInfo {
        switch self {
        case .match3:
            GameInfo(title: L10n.text("Three in a Row"),
                     tagline: L10n.text("Swap gems, chase cascades"),
                     symbol: "diamond.fill",
                     tint: .pink,
                     category: .casual,
                     difficulty: .easy)
        case .sudoku:
            GameInfo(title: L10n.text("Mini Sudoku"),
                     tagline: L10n.text("6×6 logic, quick rounds"),
                     symbol: "square.grid.3x3.fill",
                     tint: .indigo,
                     category: .logic,
                     difficulty: .medium)
        case .snake:
            GameInfo(title: L10n.text("Snake"),
                     tagline: L10n.text("Eat, grow, don't crash"),
                     symbol: "scribble.variable",
                     tint: .green,
                     category: .arcade,
                     difficulty: .medium)
        case .blockBlast:
            GameInfo(title: L10n.text("Block Blast"),
                     tagline: L10n.text("Fill lines, clear the board"),
                     symbol: "square.stack.3d.up.fill",
                     tint: .orange,
                     category: .logic,
                     difficulty: .easy)
        case .waterSort:
            GameInfo(title: L10n.text("Water Sort"),
                     tagline: L10n.text("Pour and sort the colors"),
                     symbol: "testtube.2",
                     tint: .cyan,
                     category: .logic,
                     difficulty: .medium)
        case .solitaire:
            GameInfo(title: L10n.text("Solitaire"),
                     tagline: L10n.text("Classic Klondike patience"),
                     symbol: "suit.diamond.fill",
                     tint: .teal,
                     category: .cards,
                     difficulty: .medium)
        case .spiderSolitaire:
            GameInfo(title: L10n.text("Spider"),
                     tagline: L10n.text("Build runs, clear the table"),
                     symbol: "suit.club.fill",
                     tint: .purple,
                     category: .cards,
                     difficulty: .hard)
        case .freecell:
            GameInfo(title: L10n.text("FreeCell"),
                     tagline: L10n.text("Every deal is winnable"),
                     symbol: "suit.heart.fill",
                     tint: .pink,
                     category: .cards,
                     difficulty: .hard)
        case .spades:
            GameInfo(title: L10n.text("Spades"),
                     tagline: L10n.text("Bid, trump, take tricks"),
                     symbol: "suit.spade.fill",
                     tint: .blue,
                     category: .cards,
                     difficulty: .medium)
        case .minesweeper:
            GameInfo(title: L10n.text("Minesweeper"),
                     tagline: L10n.text("Flag the mines, clear the field"),
                     symbol: "flag.fill",
                     tint: .red,
                     category: .logic,
                     difficulty: .medium)
        case .checkmate:
            GameInfo(title: L10n.text("Checkmate"),
                     tagline: L10n.text("Find the mate in 1 or 2"),
                     symbol: "crown.fill",
                     tint: .yellow,
                     category: .logic,
                     difficulty: .hard)
        case .dominoes:
            GameInfo(title: L10n.text("Dominoes"),
                     tagline: L10n.text("Match pips, beat the bot"),
                     symbol: "die.face.5.fill",
                     tint: .indigo,
                     category: .cards,
                     difficulty: .easy)
        }
    }
}

/// Maps a game id to its playable view. The one place to register a new game's UI.
@MainActor
@ViewBuilder
func gameView(for id: GameID) -> some View {
    switch id {
    case .match3: Match3View()
    case .sudoku: SudokuView()
    case .snake: SnakeView()
    case .blockBlast: BlockBlastView()
    case .waterSort: WaterSortView()
    case .solitaire: SolitaireView()
    case .spiderSolitaire: SpiderView()
    case .freecell: FreeCellView()
    case .spades: SpadesView()
    case .minesweeper: MinesweeperView()
    case .checkmate: CheckmateView()
    case .dominoes: DominoesView()
    }
}

// MARK: - Haptics

@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func move() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
