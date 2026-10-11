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
    case attention = "Attention"
    case visual = "Visual puzzles"
    case numbers = "Numbers"
    case japanese = "Japanese puzzles"
    case physics = "Physics"
    case reaction = "Reaction"
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
    case arrowMaze = "arrowEscape" // Preserve existing maze scores and favorites.
    case arrowEscape = "arrowEscapePuzzle"
    case bounce
    case findColor

    case findPair

    case basketShot
    case bottleFlip

    case miniGolf
    case plinko
    case ropeCut
    case drawBridge

    case rotatePuzzle

    case matchstick
    case slope

    case circlePong
    case spaceDodge

    case endlessClimb

    case redGreen
    case perfectTiming
    case bubblePop
    case whackMole

    case chainReaction
    case lightsOut
    case nonogram
    case numberConnect
    case oneLine
    case unblock
    case fifteenPuzzle
    case pipeConnect
    case dots
    case floodFill
    case laser
    case colorLines
    case stack
    case knifeSpin
    case helixDrop
    case flappyFlight

    case roadHop
    case reactionTap
    case simon
    case mergeFruit
    case game2048
    case quickMath
    case sudoku
    case snake
    case blockBlast
    case waterSort
    case solitaire
    case spiderSolitaire
    case freecell
    case minesweeper
    case checkmate
    var id: String { rawValue }

    var info: GameInfo {
        switch self {
        case .arrowEscape:
            GameInfo(title: L10n.text("Arrow Escape"), tagline: L10n.text("Untangle the arrows and clear the board"),
                     symbol: "arrow.up.right", tint: .indigo, category: .logic, difficulty: .medium)
        case .arrowMaze:
            GameInfo(title: L10n.text("Rocket Maze"), tagline: L10n.text("Grab stars, speed up, reach the portal"),
                     symbol: "location.north.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .bounce:
            GameInfo(title: L10n.text("Bounce"), tagline: L10n.text("Roll, jump and collect every ring"),
                     symbol: "circle.fill", tint: .red, category: .arcade, difficulty: .medium)
        case .findColor:
            GameInfo(title: L10n.text(AttentionMode.findColor.title), tagline: L10n.text(AttentionMode.findColor.hint),
                     symbol: "paintpalette.fill", tint: .pink, category: .attention, difficulty: .medium)
        case .findPair:
            GameInfo(title: L10n.text(AttentionMode.findPair.title), tagline: L10n.text(AttentionMode.findPair.hint),
                     symbol: "square.on.square", tint: .pink, category: .attention, difficulty: .medium)
        case .basketShot:
            GameInfo(title: L10n.text(ToyMode.basketShot.title), tagline: L10n.text(ToyMode.basketShot.hint),
                     symbol: "basketball.fill", tint: .cyan, category: .physics, difficulty: .medium)
        case .bottleFlip:
            GameInfo(title: L10n.text(ToyMode.bottleFlip.title), tagline: L10n.text(ToyMode.bottleFlip.hint),
                     symbol: "waterbottle.fill", tint: .pink, category: .physics, difficulty: .medium)
        case .miniGolf:
            GameInfo(title: L10n.text(ToyMode.miniGolf.title), tagline: L10n.text(ToyMode.miniGolf.hint),
                     symbol: "flag.fill", tint: .purple, category: .physics, difficulty: .medium)
        case .plinko:
            GameInfo(title: L10n.text(ToyMode.plinko.title), tagline: L10n.text(ToyMode.plinko.hint),
                     symbol: "circle.grid.3x3.fill", tint: .pink, category: .physics, difficulty: .medium)
        case .ropeCut:
            GameInfo(title: L10n.text(ToyMode.ropeCut.title), tagline: L10n.text(ToyMode.ropeCut.hint),
                     symbol: "scissors", tint: .mint, category: .physics, difficulty: .medium)
        case .drawBridge:
            GameInfo(title: L10n.text(ToyMode.drawBridge.title), tagline: L10n.text(ToyMode.drawBridge.hint),
                     symbol: "pencil.tip", tint: .purple, category: .physics, difficulty: .medium)
        case .rotatePuzzle:
            GameInfo(title: L10n.text(VisualMode.rotatePuzzle.title), tagline: L10n.text(VisualMode.rotatePuzzle.hint),
                     symbol: "rotate.right", tint: .mint, category: .visual, difficulty: .medium)
        case .matchstick:
            GameInfo(title: L10n.text(VisualMode.matchstick.title), tagline: L10n.text(VisualMode.matchstick.hint),
                     symbol: "flame.fill", tint: .purple, category: .numbers, difficulty: .medium)
        case .slope:
            GameInfo(title: L10n.text(MotionMode.slope.title), tagline: L10n.text(MotionMode.slope.hint),
                     symbol: "circle.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .circlePong:
            GameInfo(title: L10n.text(MotionMode.circlePong.title), tagline: L10n.text(MotionMode.circlePong.hint),
                     symbol: "circle.circle", tint: .pink, category: .arcade, difficulty: .medium)
        case .spaceDodge:
            GameInfo(title: L10n.text(MotionMode.spaceDodge.title), tagline: L10n.text(MotionMode.spaceDodge.hint),
                     symbol: "paperplane.fill", tint: .purple, category: .arcade, difficulty: .medium)
        case .endlessClimb:
            GameInfo(title: L10n.text(MotionMode.endlessClimb.title), tagline: L10n.text(MotionMode.endlessClimb.hint),
                     symbol: "arrow.up.circle.fill", tint: .pink, category: .arcade, difficulty: .medium)
        case .redGreen:
            GameInfo(title: L10n.text("Red Light, Green Light"), tagline: L10n.text(ActionMode.redGreen.hint),
                     symbol: "light.beacon.max.fill", tint: .red, category: .reaction, difficulty: .medium)
        case .perfectTiming:
            GameInfo(title: L10n.text("Perfect Timing"), tagline: L10n.text(ActionMode.perfectTiming.hint),
                     symbol: "scope", tint: .mint, category: .reaction, difficulty: .medium)
        case .bubblePop:
            GameInfo(title: L10n.text("Bubble Pop"), tagline: L10n.text(ActionMode.bubblePop.hint),
                     symbol: "bubble.left.and.bubble.right.fill", tint: .pink, category: .reaction, difficulty: .medium)
        case .whackMole:
            GameInfo(title: L10n.text("Whack-a-Mole"), tagline: L10n.text(ActionMode.whackMole.hint),
                     symbol: "target", tint: .orange, category: .reaction, difficulty: .medium)
        case .chainReaction:
            GameInfo(title: L10n.text("Chain Reaction"), tagline: L10n.text(ActionMode.chainReaction.hint),
                     symbol: "sparkles", tint: .green, category: .arcade, difficulty: .medium)
        case .lightsOut:
            GameInfo(title: L10n.text("Lights Out"), tagline: L10n.text(PuzzleMode.lightsOut.hint),
                     symbol: "lightbulb.fill", tint: .yellow, category: .logic, difficulty: .medium)
        case .nonogram:
            GameInfo(title: L10n.text("Nonogram"), tagline: L10n.text(PuzzleMode.nonogram.hint),
                     symbol: "square.grid.3x3.fill", tint: .cyan, category: .japanese, difficulty: .medium)
        case .numberConnect:
            GameInfo(title: L10n.text("Numberlink"), tagline: L10n.text(PuzzleMode.numberConnect.hint),
                     symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .pink, category: .japanese, difficulty: .medium)
        case .oneLine:
            GameInfo(title: L10n.text("One Line"), tagline: L10n.text(PuzzleMode.oneLine.hint),
                     symbol: "pencil.tip", tint: .mint, category: .logic, difficulty: .medium)
        case .unblock:
            GameInfo(title: L10n.text("Unblock"), tagline: L10n.text(PuzzleMode.unblock.hint),
                     symbol: "rectangle.split.3x1.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .fifteenPuzzle:
            GameInfo(title: L10n.text("15 Puzzle"), tagline: L10n.text(PuzzleMode.fifteenPuzzle.hint),
                     symbol: "square.grid.3x3.fill", tint: .indigo, category: .logic, difficulty: .medium)
        case .pipeConnect:
            GameInfo(title: L10n.text("Pipe Connect"), tagline: L10n.text(PuzzleMode.pipeConnect.hint),
                     symbol: "arrow.triangle.branch", tint: .teal, category: .logic, difficulty: .medium)
        case .dots:
            GameInfo(title: L10n.text("Dots"), tagline: L10n.text(PuzzleMode.dots.hint),
                     symbol: "circle.grid.3x3.fill", tint: .pink, category: .logic, difficulty: .medium)
        case .floodFill:
            GameInfo(title: L10n.text("Flood Fill"), tagline: L10n.text(PuzzleMode.floodFill.hint),
                     symbol: "drop.fill", tint: .blue, category: .logic, difficulty: .medium)
        case .laser:
            GameInfo(title: L10n.text("Laser"), tagline: L10n.text(PuzzleMode.laser.hint),
                     symbol: "sun.max.fill", tint: .red, category: .logic, difficulty: .medium)
        case .colorLines:
            GameInfo(title: L10n.text("Color Lines"), tagline: L10n.text(PuzzleMode.colorLines.hint),
                     symbol: "circle.grid.3x3.fill", tint: .green, category: .logic, difficulty: .medium)
        case .stack:
            GameInfo(title: L10n.text("Stack"), tagline: L10n.text("Build the tallest tower"),
                     symbol: "square.stack.3d.up.fill", tint: .mint, category: .arcade, difficulty: .easy)
        case .knifeSpin:
            GameInfo(title: L10n.text("Knife Spin"), tagline: L10n.text("Hit the target, avoid the pins"),
                     symbol: "scope", tint: .orange, category: .arcade, difficulty: .medium)
        case .helixDrop:
            GameInfo(title: L10n.text("Helix Drop"), tagline: L10n.text("Rotate, drop, avoid red"),
                     symbol: "tornado", tint: .cyan, category: .arcade, difficulty: .medium)
        case .flappyFlight:
            GameInfo(title: L10n.text("Flappy Flight"), tagline: L10n.text("Tap to fly between obstacles"),
                     symbol: "bird.fill", tint: .yellow, category: .arcade, difficulty: .hard)
        case .roadHop:
            GameInfo(title: L10n.text("Road Hop"), tagline: L10n.text("Hop across busy lanes"),
                     symbol: "car.fill", tint: .teal, category: .arcade, difficulty: .medium)
        case .reactionTap:
            GameInfo(title: L10n.text("Reaction Tap"), tagline: L10n.text("Wait for green, react fast"),
                     symbol: "bolt.fill", tint: .red, category: .reaction, difficulty: .easy)
        case .simon:
            GameInfo(title: L10n.text("Simon"), tagline: L10n.text("Watch, remember, repeat"),
                     symbol: "circle.grid.2x2.fill", tint: .indigo, category: .reaction, difficulty: .medium)
        case .mergeFruit:
            GameInfo(title: L10n.text("Merge Fruit"), tagline: L10n.text("Drop fruit and merge pairs"),
                     symbol: "leaf.fill", tint: .green, category: .physics, difficulty: .medium)
        case .game2048:
            GameInfo(title: "2048", tagline: L10n.text("Merge tiles, reach 2048"),
                     symbol: "square.grid.2x2.fill", tint: .orange, category: .numbers, difficulty: .medium)
        case .quickMath:
            GameInfo(title: L10n.text("Quick Math"), tagline: L10n.text("Beat the clock with mental math"),
                     symbol: "plus.forwardslash.minus", tint: .mint, category: .numbers, difficulty: .medium)
        case .sudoku:
            GameInfo(title: L10n.text("Sudoku"),
                     tagline: L10n.text("6×6 and 9×9 puzzles with notes and hints"),
                     symbol: "square.grid.3x3.fill",
                     tint: .indigo,
                     category: .japanese,
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
        case .minesweeper:
            GameInfo(title: L10n.text("Minesweeper"),
                     tagline: L10n.text("Flag the mines, clear the field"),
                     symbol: "flag.fill",
                     tint: .red,
                     category: .logic,
                     difficulty: .medium)
        case .checkmate:
            GameInfo(title: L10n.text("Checkmate"),
                     tagline: L10n.text("Solve as many mates as you can"),
                     symbol: "crown.fill",
                     tint: .yellow,
                     category: .logic,
                     difficulty: .hard)
        }
    }
}

/// Maps a game id to its playable view. The one place to register a new game's UI.
@MainActor
@ViewBuilder
func gameView(for id: GameID) -> some View {
    switch id {
    case .arrowMaze: ArrowMazeView()
    case .arrowEscape: ArrowEscapePuzzleView()
    case .bounce: BounceView()
    case .findColor: AttentionView(mode: .findColor)
    case .findPair: AttentionView(mode: .findPair)
    case .basketShot: ToyView(mode: .basketShot)
    case .bottleFlip: ToyView(mode: .bottleFlip)
    case .miniGolf: ToyView(mode: .miniGolf)
    case .plinko: ToyView(mode: .plinko)
    case .ropeCut: ToyView(mode: .ropeCut)
    case .drawBridge: ToyView(mode: .drawBridge)
    case .rotatePuzzle: VisualView(mode: .rotatePuzzle)
    case .matchstick: VisualView(mode: .matchstick)
    case .slope: MotionView(mode: .slope)
    case .circlePong: MotionView(mode: .circlePong)
    case .spaceDodge: MotionView(mode: .spaceDodge)
    case .endlessClimb: MotionView(mode: .endlessClimb)
    case .redGreen: ActionCollectionView(mode: .redGreen)
    case .perfectTiming: ActionCollectionView(mode: .perfectTiming)
    case .bubblePop: ActionCollectionView(mode: .bubblePop)
    case .whackMole: ActionCollectionView(mode: .whackMole)
    case .chainReaction: ActionCollectionView(mode: .chainReaction)
    case .lightsOut: PuzzleCollectionView(mode: .lightsOut)
    case .nonogram: PuzzleCollectionView(mode: .nonogram)
    case .numberConnect: PuzzleCollectionView(mode: .numberConnect)
    case .oneLine: PuzzleCollectionView(mode: .oneLine)
    case .unblock: PuzzleCollectionView(mode: .unblock)
    case .fifteenPuzzle: PuzzleCollectionView(mode: .fifteenPuzzle)
    case .pipeConnect: PuzzleCollectionView(mode: .pipeConnect)
    case .dots: PuzzleCollectionView(mode: .dots)
    case .floodFill: PuzzleCollectionView(mode: .floodFill)
    case .laser: PuzzleCollectionView(mode: .laser)
    case .colorLines: PuzzleCollectionView(mode: .colorLines)
    case .stack: ArcadeView(mode: .stack)
    case .knifeSpin: ArcadeView(mode: .knifeSpin)
    case .helixDrop: ArcadeView(mode: .helixDrop)
    case .flappyFlight: ArcadeView(mode: .flappyFlight)
    case .roadHop: ArcadeView(mode: .roadHop)
    case .reactionTap: BrainArcadeView(mode: .reaction)
    case .simon: BrainArcadeView(mode: .simon)
    case .mergeFruit: MergeFruitView()
    case .game2048: Game2048View()
    case .quickMath: QuickMathView()
    case .sudoku: SudokuView()
    case .snake: SnakeView()
    case .blockBlast: BlockBlastView()
    case .waterSort: WaterSortView()
    case .solitaire: SolitaireView()
    case .spiderSolitaire: SpiderView()
    case .freecell: FreeCellView()
    case .minesweeper: MinesweeperView()
    case .checkmate: CheckmateView()
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
