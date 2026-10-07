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
    case bounce
    case oddOneOut
    case findColor
    case biggestNumber
    case missingNumber
    case whichSide
    case memoryFlash
    case findPair
    case ascending
    case dontTap
    case fastSort
    case basketShot
    case bottleFlip
    case paperToss
    case darts
    case miniGolf
    case pinballMini
    case plinko
    case ricochet
    case ropeCut
    case drawBridge
    case spotDifference
    case hiddenObject
    case shadowMatch
    case rotatePuzzle
    case symmetry
    case patternMatch
    case tangram
    case pixelPuzzle
    case foldIt
    case matchstick
    case slope
    case keepItUp
    case wallJump
    case circlePong
    case spaceDodge
    case laneSwitch
    case gravityFlip
    case cannonShot
    case endlessClimb
    case drift
    case hashi
    case kakuro
    case nurikabe
    case slitherlink
    case futoshiki
    case hitori
    case takuzu
    case tents
    case masyu
    case circleJump
    case dash
    case darkTiles
    case redGreen
    case perfectTiming
    case bubblePop
    case whackMole
    case avoid
    case zigZag
    case chainReaction
    case orbit
    case lightsOut
    case nonogram
    case numberConnect
    case oneLine
    case unblock
    case parkingJam
    case fifteenPuzzle
    case pipeConnect
    case dots
    case sameGame
    case floodFill
    case laser
    case balanceScale
    case colorLines
    case stack
    case colorJump
    case knifeSpin
    case helixDrop
    case skyJump
    case flappyFlight
    case brickBreaker
    case pong
    case roadHop
    case reactionTap
    case simon
    case higherLower
    case mergeFruit
    case game2048
    case quickMath
    case match3
    case sudoku
    case snake
    case blockBlast
    case waterSort
    case solitaire
    case spiderSolitaire
    case freecell
    //case spades
    case minesweeper
    case checkmate
   // case dominoes

    var id: String { rawValue }

    var info: GameInfo {
        switch self {
        case .bounce:
            GameInfo(title: L10n.text("Bounce"), tagline: L10n.text("Roll, jump and collect every ring"),
                     symbol: "circle.fill", tint: .red, category: .arcade, difficulty: .medium)
        case .oddOneOut:
            GameInfo(title: L10n.text(AttentionMode.oddOneOut.title), tagline: L10n.text(AttentionMode.oddOneOut.hint),
                     symbol: "eye.fill", tint: .cyan, category: .logic, difficulty: .medium)
        case .findColor:
            GameInfo(title: L10n.text(AttentionMode.findColor.title), tagline: L10n.text(AttentionMode.findColor.hint),
                     symbol: "paintpalette.fill", tint: .pink, category: .logic, difficulty: .medium)
        case .biggestNumber:
            GameInfo(title: L10n.text(AttentionMode.biggestNumber.title), tagline: L10n.text(AttentionMode.biggestNumber.hint),
                     symbol: "number", tint: .orange, category: .logic, difficulty: .medium)
        case .missingNumber:
            GameInfo(title: L10n.text(AttentionMode.missingNumber.title), tagline: L10n.text(AttentionMode.missingNumber.hint),
                     symbol: "questionmark.square", tint: .mint, category: .logic, difficulty: .medium)
        case .whichSide:
            GameInfo(title: L10n.text(AttentionMode.whichSide.title), tagline: L10n.text(AttentionMode.whichSide.hint),
                     symbol: "arrow.left.arrow.right", tint: .purple, category: .logic, difficulty: .medium)
        case .memoryFlash:
            GameInfo(title: L10n.text(AttentionMode.memoryFlash.title), tagline: L10n.text(AttentionMode.memoryFlash.hint),
                     symbol: "brain.head.profile", tint: .cyan, category: .logic, difficulty: .medium)
        case .findPair:
            GameInfo(title: L10n.text(AttentionMode.findPair.title), tagline: L10n.text(AttentionMode.findPair.hint),
                     symbol: "square.on.square", tint: .pink, category: .logic, difficulty: .medium)
        case .ascending:
            GameInfo(title: L10n.text(AttentionMode.ascending.title), tagline: L10n.text(AttentionMode.ascending.hint),
                     symbol: "arrow.up", tint: .orange, category: .logic, difficulty: .medium)
        case .dontTap:
            GameInfo(title: L10n.text(AttentionMode.dontTap.title), tagline: L10n.text(AttentionMode.dontTap.hint),
                     symbol: "hand.raised.fill", tint: .mint, category: .logic, difficulty: .medium)
        case .fastSort:
            GameInfo(title: L10n.text(AttentionMode.fastSort.title), tagline: L10n.text(AttentionMode.fastSort.hint),
                     symbol: "arrow.triangle.swap", tint: .purple, category: .logic, difficulty: .medium)
        case .basketShot:
            GameInfo(title: L10n.text(ToyMode.basketShot.title), tagline: L10n.text(ToyMode.basketShot.hint),
                     symbol: "basketball.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .bottleFlip:
            GameInfo(title: L10n.text(ToyMode.bottleFlip.title), tagline: L10n.text(ToyMode.bottleFlip.hint),
                     symbol: "waterbottle.fill", tint: .pink, category: .arcade, difficulty: .medium)
        case .paperToss:
            GameInfo(title: L10n.text(ToyMode.paperToss.title), tagline: L10n.text(ToyMode.paperToss.hint),
                     symbol: "trash.fill", tint: .orange, category: .arcade, difficulty: .medium)
        case .darts:
            GameInfo(title: L10n.text(ToyMode.darts.title), tagline: L10n.text(ToyMode.darts.hint),
                     symbol: "target", tint: .mint, category: .arcade, difficulty: .medium)
        case .miniGolf:
            GameInfo(title: L10n.text(ToyMode.miniGolf.title), tagline: L10n.text(ToyMode.miniGolf.hint),
                     symbol: "flag.fill", tint: .purple, category: .arcade, difficulty: .medium)
        case .pinballMini:
            GameInfo(title: L10n.text(ToyMode.pinballMini.title), tagline: L10n.text(ToyMode.pinballMini.hint),
                     symbol: "circle.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .plinko:
            GameInfo(title: L10n.text(ToyMode.plinko.title), tagline: L10n.text(ToyMode.plinko.hint),
                     symbol: "circle.grid.3x3.fill", tint: .pink, category: .arcade, difficulty: .medium)
        case .ricochet:
            GameInfo(title: L10n.text(ToyMode.ricochet.title), tagline: L10n.text(ToyMode.ricochet.hint),
                     symbol: "arrow.triangle.branch", tint: .orange, category: .arcade, difficulty: .medium)
        case .ropeCut:
            GameInfo(title: L10n.text(ToyMode.ropeCut.title), tagline: L10n.text(ToyMode.ropeCut.hint),
                     symbol: "scissors", tint: .mint, category: .arcade, difficulty: .medium)
        case .drawBridge:
            GameInfo(title: L10n.text(ToyMode.drawBridge.title), tagline: L10n.text(ToyMode.drawBridge.hint),
                     symbol: "pencil.tip", tint: .purple, category: .arcade, difficulty: .medium)
        case .spotDifference:
            GameInfo(title: L10n.text(VisualMode.spotDifference.title), tagline: L10n.text(VisualMode.spotDifference.hint),
                     symbol: "square.on.square", tint: .cyan, category: .logic, difficulty: .medium)
        case .hiddenObject:
            GameInfo(title: L10n.text(VisualMode.hiddenObject.title), tagline: L10n.text(VisualMode.hiddenObject.hint),
                     symbol: "magnifyingglass", tint: .pink, category: .logic, difficulty: .medium)
        case .shadowMatch:
            GameInfo(title: L10n.text(VisualMode.shadowMatch.title), tagline: L10n.text(VisualMode.shadowMatch.hint),
                     symbol: "moon.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .rotatePuzzle:
            GameInfo(title: L10n.text(VisualMode.rotatePuzzle.title), tagline: L10n.text(VisualMode.rotatePuzzle.hint),
                     symbol: "rotate.right", tint: .mint, category: .logic, difficulty: .medium)
        case .symmetry:
            GameInfo(title: L10n.text(VisualMode.symmetry.title), tagline: L10n.text(VisualMode.symmetry.hint),
                     symbol: "arrow.left.and.right", tint: .purple, category: .logic, difficulty: .medium)
        case .patternMatch:
            GameInfo(title: L10n.text(VisualMode.patternMatch.title), tagline: L10n.text(VisualMode.patternMatch.hint),
                     symbol: "square.grid.3x3.fill", tint: .cyan, category: .logic, difficulty: .medium)
        case .tangram:
            GameInfo(title: L10n.text(VisualMode.tangram.title), tagline: L10n.text(VisualMode.tangram.hint),
                     symbol: "triangle.fill", tint: .pink, category: .logic, difficulty: .medium)
        case .pixelPuzzle:
            GameInfo(title: L10n.text(VisualMode.pixelPuzzle.title), tagline: L10n.text(VisualMode.pixelPuzzle.hint),
                     symbol: "square.grid.3x3.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .foldIt:
            GameInfo(title: L10n.text(VisualMode.foldIt.title), tagline: L10n.text(VisualMode.foldIt.hint),
                     symbol: "doc.fill", tint: .mint, category: .logic, difficulty: .medium)
        case .matchstick:
            GameInfo(title: L10n.text(VisualMode.matchstick.title), tagline: L10n.text(VisualMode.matchstick.hint),
                     symbol: "flame.fill", tint: .purple, category: .logic, difficulty: .medium)
        case .slope:
            GameInfo(title: L10n.text(MotionMode.slope.title), tagline: L10n.text(MotionMode.slope.hint),
                     symbol: "circle.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .keepItUp:
            GameInfo(title: L10n.text(MotionMode.keepItUp.title), tagline: L10n.text(MotionMode.keepItUp.hint),
                     symbol: "basketball.fill", tint: .orange, category: .arcade, difficulty: .medium)
        case .wallJump:
            GameInfo(title: L10n.text(MotionMode.wallJump.title), tagline: L10n.text(MotionMode.wallJump.hint),
                     symbol: "arrow.left.arrow.right", tint: .mint, category: .arcade, difficulty: .medium)
        case .circlePong:
            GameInfo(title: L10n.text(MotionMode.circlePong.title), tagline: L10n.text(MotionMode.circlePong.hint),
                     symbol: "circle.circle", tint: .pink, category: .arcade, difficulty: .medium)
        case .spaceDodge:
            GameInfo(title: L10n.text(MotionMode.spaceDodge.title), tagline: L10n.text(MotionMode.spaceDodge.hint),
                     symbol: "paperplane.fill", tint: .purple, category: .arcade, difficulty: .medium)
        case .laneSwitch:
            GameInfo(title: L10n.text(MotionMode.laneSwitch.title), tagline: L10n.text(MotionMode.laneSwitch.hint),
                     symbol: "arrow.triangle.swap", tint: .cyan, category: .arcade, difficulty: .medium)
        case .gravityFlip:
            GameInfo(title: L10n.text(MotionMode.gravityFlip.title), tagline: L10n.text(MotionMode.gravityFlip.hint),
                     symbol: "arrow.up.arrow.down", tint: .orange, category: .arcade, difficulty: .medium)
        case .cannonShot:
            GameInfo(title: L10n.text(MotionMode.cannonShot.title), tagline: L10n.text(MotionMode.cannonShot.hint),
                     symbol: "scope", tint: .mint, category: .arcade, difficulty: .medium)
        case .endlessClimb:
            GameInfo(title: L10n.text(MotionMode.endlessClimb.title), tagline: L10n.text(MotionMode.endlessClimb.hint),
                     symbol: "arrow.up.circle.fill", tint: .pink, category: .arcade, difficulty: .medium)
        case .drift:
            GameInfo(title: L10n.text(MotionMode.drift.title), tagline: L10n.text(MotionMode.drift.hint),
                     symbol: "car.fill", tint: .purple, category: .arcade, difficulty: .medium)
        case .hashi:
            GameInfo(title: L10n.text(LogicMode.hashi.title), tagline: L10n.text(LogicMode.hashi.hint),
                     symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .cyan, category: .logic, difficulty: .medium)
        case .kakuro:
            GameInfo(title: L10n.text(LogicMode.kakuro.title), tagline: L10n.text(LogicMode.kakuro.hint),
                     symbol: "sum", tint: .orange, category: .logic, difficulty: .medium)
        case .nurikabe:
            GameInfo(title: L10n.text(LogicMode.nurikabe.title), tagline: L10n.text(LogicMode.nurikabe.hint),
                     symbol: "square.on.square", tint: .mint, category: .logic, difficulty: .medium)
        case .slitherlink:
            GameInfo(title: L10n.text(LogicMode.slitherlink.title), tagline: L10n.text(LogicMode.slitherlink.hint),
                     symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .pink, category: .logic, difficulty: .medium)
        case .futoshiki:
            GameInfo(title: L10n.text(LogicMode.futoshiki.title), tagline: L10n.text(LogicMode.futoshiki.hint),
                     symbol: "lessthan", tint: .purple, category: .logic, difficulty: .medium)
        case .hitori:
            GameInfo(title: L10n.text(LogicMode.hitori.title), tagline: L10n.text(LogicMode.hitori.hint),
                     symbol: "square.fill", tint: .cyan, category: .logic, difficulty: .medium)
        case .takuzu:
            GameInfo(title: L10n.text(LogicMode.takuzu.title), tagline: L10n.text(LogicMode.takuzu.hint),
                     symbol: "01.square.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .tents:
            GameInfo(title: L10n.text(LogicMode.tents.title), tagline: L10n.text(LogicMode.tents.hint),
                     symbol: "tree.fill", tint: .mint, category: .logic, difficulty: .medium)
        case .masyu:
            GameInfo(title: L10n.text(LogicMode.masyu.title), tagline: L10n.text(LogicMode.masyu.hint),
                     symbol: "circle.lefthalf.filled", tint: .pink, category: .logic, difficulty: .medium)
        case .circleJump:
            GameInfo(title: L10n.text("Circle Jump"), tagline: L10n.text(ActionMode.circleJump.hint),
                     symbol: "circle.dotted", tint: .cyan, category: .arcade, difficulty: .medium)
        case .dash:
            GameInfo(title: L10n.text("Dash"), tagline: L10n.text(ActionMode.dash.hint),
                     symbol: "bolt.fill", tint: .orange, category: .arcade, difficulty: .medium)
        case .darkTiles:
            GameInfo(title: L10n.text("Don’t Touch White"), tagline: L10n.text(ActionMode.darkTiles.hint),
                     symbol: "square.grid.3x3.fill", tint: .indigo, category: .arcade, difficulty: .medium)
        case .redGreen:
            GameInfo(title: L10n.text("Red Light, Green Light"), tagline: L10n.text(ActionMode.redGreen.hint),
                     symbol: "light.beacon.max.fill", tint: .red, category: .arcade, difficulty: .medium)
        case .perfectTiming:
            GameInfo(title: L10n.text("Perfect Timing"), tagline: L10n.text(ActionMode.perfectTiming.hint),
                     symbol: "scope", tint: .mint, category: .arcade, difficulty: .medium)
        case .bubblePop:
            GameInfo(title: L10n.text("Bubble Pop"), tagline: L10n.text(ActionMode.bubblePop.hint),
                     symbol: "bubble.left.and.bubble.right.fill", tint: .pink, category: .arcade, difficulty: .medium)
        case .whackMole:
            GameInfo(title: L10n.text("Whack-a-Mole"), tagline: L10n.text(ActionMode.whackMole.hint),
                     symbol: "target", tint: .orange, category: .arcade, difficulty: .medium)
        case .avoid:
            GameInfo(title: L10n.text("Avoid"), tagline: L10n.text(ActionMode.avoid.hint),
                     symbol: "move.3d", tint: .purple, category: .arcade, difficulty: .medium)
        case .zigZag:
            GameInfo(title: L10n.text("Zig Zag"), tagline: L10n.text(ActionMode.zigZag.hint),
                     symbol: "arrow.triangle.turn.up.right.diamond.fill", tint: .cyan, category: .arcade, difficulty: .medium)
        case .chainReaction:
            GameInfo(title: L10n.text("Chain Reaction"), tagline: L10n.text(ActionMode.chainReaction.hint),
                     symbol: "sparkles", tint: .green, category: .arcade, difficulty: .medium)
        case .orbit:
            GameInfo(title: L10n.text("Orbit"), tagline: L10n.text(ActionMode.orbit.hint),
                     symbol: "circle.circle", tint: .blue, category: .arcade, difficulty: .medium)
        case .lightsOut:
            GameInfo(title: L10n.text("Lights Out"), tagline: L10n.text(PuzzleMode.lightsOut.hint),
                     symbol: "lightbulb.fill", tint: .yellow, category: .logic, difficulty: .medium)
        case .nonogram:
            GameInfo(title: L10n.text("Nonogram"), tagline: L10n.text(PuzzleMode.nonogram.hint),
                     symbol: "square.grid.3x3.fill", tint: .cyan, category: .logic, difficulty: .medium)
        case .numberConnect:
            GameInfo(title: L10n.text("Numberlink"), tagline: L10n.text(PuzzleMode.numberConnect.hint),
                     symbol: "point.topleft.down.to.point.bottomright.curvepath", tint: .pink, category: .logic, difficulty: .medium)
        case .oneLine:
            GameInfo(title: L10n.text("One Line"), tagline: L10n.text(PuzzleMode.oneLine.hint),
                     symbol: "pencil.tip", tint: .mint, category: .logic, difficulty: .medium)
        case .unblock:
            GameInfo(title: L10n.text("Unblock"), tagline: L10n.text(PuzzleMode.unblock.hint),
                     symbol: "rectangle.split.3x1.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .parkingJam:
            GameInfo(title: L10n.text("Parking Jam"), tagline: L10n.text(PuzzleMode.parkingJam.hint),
                     symbol: "car.fill", tint: .red, category: .logic, difficulty: .medium)
        case .fifteenPuzzle:
            GameInfo(title: L10n.text("15 Puzzle"), tagline: L10n.text(PuzzleMode.fifteenPuzzle.hint),
                     symbol: "square.grid.3x3.fill", tint: .indigo, category: .logic, difficulty: .medium)
        case .pipeConnect:
            GameInfo(title: L10n.text("Pipe Connect"), tagline: L10n.text(PuzzleMode.pipeConnect.hint),
                     symbol: "arrow.triangle.branch", tint: .teal, category: .logic, difficulty: .medium)
        case .dots:
            GameInfo(title: L10n.text("Dots"), tagline: L10n.text(PuzzleMode.dots.hint),
                     symbol: "circle.grid.3x3.fill", tint: .pink, category: .logic, difficulty: .medium)
        case .sameGame:
            GameInfo(title: L10n.text("Same Game"), tagline: L10n.text(PuzzleMode.sameGame.hint),
                     symbol: "square.stack.3d.up.fill", tint: .purple, category: .logic, difficulty: .medium)
        case .floodFill:
            GameInfo(title: L10n.text("Flood Fill"), tagline: L10n.text(PuzzleMode.floodFill.hint),
                     symbol: "drop.fill", tint: .blue, category: .logic, difficulty: .medium)
        case .laser:
            GameInfo(title: L10n.text("Laser"), tagline: L10n.text(PuzzleMode.laser.hint),
                     symbol: "sun.max.fill", tint: .red, category: .logic, difficulty: .medium)
        case .balanceScale:
            GameInfo(title: L10n.text("Balance Scale"), tagline: L10n.text(PuzzleMode.balanceScale.hint),
                     symbol: "scalemass.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .colorLines:
            GameInfo(title: L10n.text("Color Lines"), tagline: L10n.text(PuzzleMode.colorLines.hint),
                     symbol: "circle.grid.3x3.fill", tint: .green, category: .logic, difficulty: .medium)
        case .stack:
            GameInfo(title: L10n.text("Stack"), tagline: L10n.text("Build the tallest tower"),
                     symbol: "square.stack.3d.up.fill", tint: .mint, category: .arcade, difficulty: .easy)
        case .colorJump:
            GameInfo(title: L10n.text("Color Jump"), tagline: L10n.text("Jump through your color"),
                     symbol: "circle.hexagongrid.fill", tint: .pink, category: .arcade, difficulty: .hard)
        case .knifeSpin:
            GameInfo(title: L10n.text("Knife Spin"), tagline: L10n.text("Hit the target, avoid the pins"),
                     symbol: "scope", tint: .orange, category: .arcade, difficulty: .medium)
        case .helixDrop:
            GameInfo(title: L10n.text("Helix Drop"), tagline: L10n.text("Rotate, drop, avoid red"),
                     symbol: "tornado", tint: .cyan, category: .arcade, difficulty: .medium)
        case .skyJump:
            GameInfo(title: L10n.text("Sky Jump"), tagline: L10n.text("Bounce higher and higher"),
                     symbol: "arrow.up.circle.fill", tint: .green, category: .arcade, difficulty: .medium)
        case .flappyFlight:
            GameInfo(title: L10n.text("Flappy Flight"), tagline: L10n.text("Tap to fly between obstacles"),
                     symbol: "bird.fill", tint: .yellow, category: .arcade, difficulty: .hard)
        case .brickBreaker:
            GameInfo(title: L10n.text("Brick Breaker"), tagline: L10n.text("Bounce the ball, break the wall"),
                     symbol: "rectangle.split.3x3.fill", tint: .purple, category: .arcade, difficulty: .medium)
        case .pong:
            GameInfo(title: L10n.text("Pong"), tagline: L10n.text("Beat the bot to seven"),
                     symbol: "sportscourt.fill", tint: .blue, category: .arcade, difficulty: .medium)
        case .roadHop:
            GameInfo(title: L10n.text("Road Hop"), tagline: L10n.text("Hop across busy lanes"),
                     symbol: "car.fill", tint: .teal, category: .arcade, difficulty: .medium)
        case .reactionTap:
            GameInfo(title: L10n.text("Reaction Tap"), tagline: L10n.text("Wait for green, react fast"),
                     symbol: "bolt.fill", tint: .red, category: .arcade, difficulty: .easy)
        case .simon:
            GameInfo(title: L10n.text("Simon"), tagline: L10n.text("Watch, remember, repeat"),
                     symbol: "circle.grid.2x2.fill", tint: .indigo, category: .logic, difficulty: .medium)
        case .higherLower:
            GameInfo(title: L10n.text("Higher or Lower"), tagline: L10n.text("Guess the next number"),
                     symbol: "arrow.up.arrow.down", tint: .orange, category: .casual, difficulty: .easy)
        case .mergeFruit:
            GameInfo(title: L10n.text("Merge Fruit"), tagline: L10n.text("Drop fruit and merge pairs"),
                     symbol: "leaf.fill", tint: .green, category: .casual, difficulty: .medium)
        case .game2048:
            GameInfo(title: "2048", tagline: L10n.text("Merge tiles, reach 2048"),
                     symbol: "square.grid.2x2.fill", tint: .orange, category: .logic, difficulty: .medium)
        case .quickMath:
            GameInfo(title: L10n.text("Quick Math"), tagline: L10n.text("Beat the clock with mental math"),
                     symbol: "plus.forwardslash.minus", tint: .mint, category: .logic, difficulty: .medium)
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
//        case .spades:
//            GameInfo(title: L10n.text("Spades"),
//                     tagline: L10n.text("Bid, trump, take tricks"),
//                     symbol: "suit.spade.fill",
//                     tint: .blue,
//                     category: .cards,
//                     difficulty: .medium)
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
//        case .dominoes:
//            GameInfo(title: L10n.text("Dominoes"),
//                     tagline: L10n.text("Match pips, beat the bot"),
//                     symbol: "die.face.5.fill",
//                     tint: .indigo,
//                     category: .cards,
//                     difficulty: .easy)
        }
    }
}

/// Maps a game id to its playable view. The one place to register a new game's UI.
@MainActor
@ViewBuilder
func gameView(for id: GameID) -> some View {
    switch id {
    case .bounce: BounceView()
    case .oddOneOut: AttentionView(mode: .oddOneOut)
    case .findColor: AttentionView(mode: .findColor)
    case .biggestNumber: AttentionView(mode: .biggestNumber)
    case .missingNumber: AttentionView(mode: .missingNumber)
    case .whichSide: AttentionView(mode: .whichSide)
    case .memoryFlash: AttentionView(mode: .memoryFlash)
    case .findPair: AttentionView(mode: .findPair)
    case .ascending: AttentionView(mode: .ascending)
    case .dontTap: AttentionView(mode: .dontTap)
    case .fastSort: AttentionView(mode: .fastSort)
    case .basketShot: ToyView(mode: .basketShot)
    case .bottleFlip: ToyView(mode: .bottleFlip)
    case .paperToss: ToyView(mode: .paperToss)
    case .darts: ToyView(mode: .darts)
    case .miniGolf: ToyView(mode: .miniGolf)
    case .pinballMini: ToyView(mode: .pinballMini)
    case .plinko: ToyView(mode: .plinko)
    case .ricochet: ToyView(mode: .ricochet)
    case .ropeCut: ToyView(mode: .ropeCut)
    case .drawBridge: ToyView(mode: .drawBridge)
    case .spotDifference: VisualView(mode: .spotDifference)
    case .hiddenObject: VisualView(mode: .hiddenObject)
    case .shadowMatch: VisualView(mode: .shadowMatch)
    case .rotatePuzzle: VisualView(mode: .rotatePuzzle)
    case .symmetry: VisualView(mode: .symmetry)
    case .patternMatch: VisualView(mode: .patternMatch)
    case .tangram: VisualView(mode: .tangram)
    case .pixelPuzzle: VisualView(mode: .pixelPuzzle)
    case .foldIt: VisualView(mode: .foldIt)
    case .matchstick: VisualView(mode: .matchstick)
    case .slope: MotionView(mode: .slope)
    case .keepItUp: MotionView(mode: .keepItUp)
    case .wallJump: MotionView(mode: .wallJump)
    case .circlePong: MotionView(mode: .circlePong)
    case .spaceDodge: MotionView(mode: .spaceDodge)
    case .laneSwitch: MotionView(mode: .laneSwitch)
    case .gravityFlip: MotionView(mode: .gravityFlip)
    case .cannonShot: MotionView(mode: .cannonShot)
    case .endlessClimb: MotionView(mode: .endlessClimb)
    case .drift: MotionView(mode: .drift)
    case .hashi: LogicView(mode: .hashi)
    case .kakuro: LogicView(mode: .kakuro)
    case .nurikabe: LogicView(mode: .nurikabe)
    case .slitherlink: LogicView(mode: .slitherlink)
    case .futoshiki: LogicView(mode: .futoshiki)
    case .hitori: LogicView(mode: .hitori)
    case .takuzu: LogicView(mode: .takuzu)
    case .tents: LogicView(mode: .tents)
    case .masyu: LogicView(mode: .masyu)
    case .circleJump: ActionCollectionView(mode: .circleJump)
    case .dash: ActionCollectionView(mode: .dash)
    case .darkTiles: ActionCollectionView(mode: .darkTiles)
    case .redGreen: ActionCollectionView(mode: .redGreen)
    case .perfectTiming: ActionCollectionView(mode: .perfectTiming)
    case .bubblePop: ActionCollectionView(mode: .bubblePop)
    case .whackMole: ActionCollectionView(mode: .whackMole)
    case .avoid: ActionCollectionView(mode: .avoid)
    case .zigZag: ActionCollectionView(mode: .zigZag)
    case .chainReaction: ActionCollectionView(mode: .chainReaction)
    case .orbit: ActionCollectionView(mode: .orbit)
    case .lightsOut: PuzzleCollectionView(mode: .lightsOut)
    case .nonogram: PuzzleCollectionView(mode: .nonogram)
    case .numberConnect: PuzzleCollectionView(mode: .numberConnect)
    case .oneLine: PuzzleCollectionView(mode: .oneLine)
    case .unblock: PuzzleCollectionView(mode: .unblock)
    case .parkingJam: PuzzleCollectionView(mode: .parkingJam)
    case .fifteenPuzzle: PuzzleCollectionView(mode: .fifteenPuzzle)
    case .pipeConnect: PuzzleCollectionView(mode: .pipeConnect)
    case .dots: PuzzleCollectionView(mode: .dots)
    case .sameGame: PuzzleCollectionView(mode: .sameGame)
    case .floodFill: PuzzleCollectionView(mode: .floodFill)
    case .laser: PuzzleCollectionView(mode: .laser)
    case .balanceScale: PuzzleCollectionView(mode: .balanceScale)
    case .colorLines: PuzzleCollectionView(mode: .colorLines)
    case .stack: ArcadeView(mode: .stack)
    case .colorJump: ArcadeView(mode: .colorJump)
    case .knifeSpin: ArcadeView(mode: .knifeSpin)
    case .helixDrop: ArcadeView(mode: .helixDrop)
    case .skyJump: ArcadeView(mode: .skyJump)
    case .flappyFlight: ArcadeView(mode: .flappyFlight)
    case .brickBreaker: ArcadeView(mode: .brickBreaker)
    case .pong: ArcadeView(mode: .pong)
    case .roadHop: ArcadeView(mode: .roadHop)
    case .reactionTap: BrainArcadeView(mode: .reaction)
    case .simon: BrainArcadeView(mode: .simon)
    case .higherLower: BrainArcadeView(mode: .higherLower)
    case .mergeFruit: MergeFruitView()
    case .game2048: Game2048View()
    case .quickMath: QuickMathView()
    case .match3: Match3View()
    case .sudoku: SudokuView()
    case .snake: SnakeView()
    case .blockBlast: BlockBlastView()
    case .waterSort: WaterSortView()
    case .solitaire: SolitaireView()
    case .spiderSolitaire: SpiderView()
    case .freecell: FreeCellView()
   // case .spades: SpadesView()
    case .minesweeper: MinesweeperView()
    case .checkmate: CheckmateView()
    //case .dominoes: DominoesView()
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
