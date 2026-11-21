import SwiftUI

/// Live snapshots of real game boards for the Home previews. Each one is
/// rendered from the game's own view with a fixed demo position, once per
/// colour scheme. Games without a snapshot keep their flat GameArtwork.
@MainActor
enum GameSnapshot {
    private static var cache: [String: UIImage] = [:]

    /// Games whose board can be drawn on its own.
    static func supports(_ gameID: GameID) -> Bool {
        switch gameID {
        case .game2048, .blockBlast, .stack, .numberConnect,
             .arrowEscape, .miniGolf, .sudoku, .minesweeper,
             .solitaire, .snake, .waterSort, .checkmate,
             .spiderSolitaire, .freecell, .durak, .hangman,
             .battleship, .mazePaint, .gems, .gemsArcade, .gemsBlitz, .unblock, .simon,
             .knifeSpin, .helixDrop, .flappyFlight, .roadHop: true
        default:
            ToyMode.allCases.contains { $0.id == gameID } || VisualMode.allCases.contains { $0.id == gameID }
                || MotionMode.allCases.contains { $0.gameID == gameID } || ActionMode.allCases.contains { $0.id == gameID }
                || PuzzleMode.allCases.contains { $0.id == gameID }
        }
    }

    static func image(for gameID: GameID, dark: Bool) -> UIImage? {
        guard supports(gameID) else { return nil }
        let key = "\(gameID.rawValue)-\(dark ? "dark" : "light")"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content: content(for: gameID)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }

    private static func content(for gameID: GameID) -> AnyView {
        switch gameID {
        case .game2048:
            let engine = Game2048Engine()
            engine.showcase()
            return AnyView(Game2048Showcase(engine: engine))
        case .blockBlast:
            let engine = BlockBlastEngine()
            engine.showcase()
            return AnyView(BlockBlastShowcase(engine: engine))
        case .stack:
            let engine = ArcadeEngine(mode: .stack)
            engine.showcase()
            return AnyView(TowerShowcase(engine: engine))
        case .numberConnect:
            let engine = NumberLinkEngine()
            engine.showcase()
            return AnyView(NumberLinkShowcase(engine: engine))
        case .arrowEscape:
            let engine = ArrowEscapePuzzleEngine()
            engine.showcase()
            return AnyView(ArrowEscapeShowcase(engine: engine))
        case .miniGolf:
            let engine = MiniGolfEngine()
            engine.showcase()
            return AnyView(MiniGolfShowcase(engine: engine))
        case .sudoku:
            let engine = SudokuEngine()
            engine.showcase()
            return AnyView(SudokuView(showcase: engine))
        case .minesweeper:
            let engine = MinesweeperEngine()
            engine.showcase()
            return AnyView(MinesweeperView(showcase: engine))
        case .solitaire:
            let engine = SolitaireEngine()
            engine.showcase()
            return AnyView(SolitaireView(showcase: engine))
        case .snake:
            let engine = SnakeEngine()
            engine.showcase()
            return AnyView(SnakeView(showcase: engine))
        case .waterSort:
            let engine = WaterSortEngine()
            engine.showcase()
            return AnyView(WaterSortView(showcase: engine))
        case .checkmate:
            let engine = CheckmateEngine()
            engine.showcase()
            return AnyView(CheckmateView(showcase: engine))
        case .spiderSolitaire:
            let engine = SpiderEngine()
            engine.showcase()
            return AnyView(SpiderView(showcase: engine))
        case .freecell:
            let engine = FreeCellEngine()
            engine.showcase()
            return AnyView(FreeCellView(showcase: engine))
        case .durak:
            return AnyView(DurakShowcase())
        case .hangman:
            return AnyView(HangmanShowcase())
        case .battleship:
            return AnyView(BattleshipShowcase())
        case .mazePaint:
            let engine = MazePaintEngine()
            engine.showcase()
            return AnyView(MazePaintView(showcase: engine))
        case .gems:
            return AnyView(Match3Showcase(engine: Match3Engine(mode: .casual, seed: 11)))
        case .gemsArcade:
            return AnyView(Match3Showcase(engine: Match3Engine(mode: .arcade, seed: 11)))
        case .gemsBlitz:
            return AnyView(Match3Showcase(engine: Match3Engine(mode: .blitz, seed: 11)))
        case .unblock:
            let engine = CarParkEngine()
            engine.showcase()
            return AnyView(CarParkShowcase(engine: engine))
        case .simon:
            let engine = BrainArcadeEngine(mode: .simon)
            engine.showcase()
            return AnyView(BrainArcadeView(showcase: engine))
        case .knifeSpin, .helixDrop, .flappyFlight, .roadHop:
            guard let mode = ArcadeMode.allCases.first(where: { $0.gameID == gameID }) else { return AnyView(EmptyView()) }
            return AnyView(ArcadeView(showcase: arcadeShowcase(mode)))
        default:
            if let mode = ToyMode.allCases.first(where: { $0.id == gameID }) {
                let engine = ToyEngine(mode: mode)
                warm(engine.advance) { engine.active = $0; if $0 { engine.start() } }
                return AnyView(ToyView(showcase: engine))
            }
            if let mode = MotionMode.allCases.first(where: { $0.gameID == gameID }) {
                let engine = MotionEngine(mode: mode)
                warm(engine.advance) { engine.active = $0; if $0 { engine.start() } }
                return AnyView(MotionView(showcase: engine))
            }
            if let mode = ActionMode.allCases.first(where: { $0.id == gameID }) {
                let engine = ActionCollectionEngine(mode: mode)
                warm(engine.advance, seconds: 1.8) { engine.active = $0; if $0 { engine.tap(CGPoint(x: 160, y: 230)) } }
                engine.showcase()
                return AnyView(ActionCollectionView(showcase: engine))
            }
            if let mode = VisualMode.allCases.first(where: { $0.id == gameID }) {
                return AnyView(VisualView(showcase: VisualEngine(mode: mode)))
            }
            if let mode = PuzzleMode.allCases.first(where: { $0.id == gameID }) {
                return AnyView(PuzzleCollectionView(showcase: PuzzleCollectionEngine(mode: mode)))
            }
            return AnyView(EmptyView())
        }
    }

    /// Plays the opening of an arcade round with a few scripted moves:
    /// two knives thrown, the ball bouncing down the tower, the bird kept
    /// aloft, three hops up the road. Rounds that end early are replayed.
    private static func arcadeShowcase(_ mode: ArcadeMode) -> ArcadeEngine {
        SoundFX.quiet = true; Haptics.quiet = true
        defer { SoundFX.quiet = false; Haptics.quiet = false }
        var engine = ArcadeEngine(mode: mode)
        for _ in 0..<8 {
            engine = ArcadeEngine(mode: mode)
            engine.active = true
            engine.tap()
            var lastFlap = 0
            for frame in 0..<90 {
                switch mode {
                case .knifeSpin:
                    if frame == 12 || frame == 50 { engine.tap() }
                case .flappyFlight:
                    if engine.player.y > 250, frame - lastFlap > 14 { engine.tap(); lastFlap = frame }
                case .roadHop:
                    if frame % 22 == 8, frame < 70 { engine.hop(dx: 0, dy: -1) }
                default: break
                }
                engine.advance(1.0 / 60)
            }
            engine.active = false
            if engine.state == .playing { break }
        }
        return engine
    }

    /// Starts a real-time game and runs it for a moment with no sound or
    /// haptics, so its preview shows the scene in motion.
    private static func warm(_ advance: (Double) -> Void, seconds: Double = 0.8, activate: (Bool) -> Void) {
        SoundFX.quiet = true; Haptics.quiet = true
        defer { SoundFX.quiet = false; Haptics.quiet = false }
        activate(true)
        for _ in 0..<Int(seconds * 60) { advance(1.0 / 60) }
        activate(false)
    }
}

/// A Home preview frame for a board drawn in a tall scene: the board is set
/// 300 points wide in the game's tray, and a square window of it is shown,
/// centred on `focus` (0 top … 1 bottom of the scene).
struct ToyShowcaseFrame<Board: View>: View {
    let palette: ToyPalette
    /// Width over height of the board's scene.
    var aspect: CGFloat = 320.0 / 460
    var focus: CGFloat = 0.5
    var cornerRadius: CGFloat = 20
    @ViewBuilder let board: Board

    var body: some View {
        let side: CGFloat = 300
        let height = side / aspect
        let shift = height > side ? -min(height - side, max(0, focus * height - side / 2)) : (side - height) / 2
        ZStack {
            palette.backdrop
            board
                .frame(width: side, height: height)
                .offset(y: shift)
                .frame(width: side, height: side, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .toyTray(palette.tray, cornerRadius: cornerRadius + 4, padding: 6)
        }
        .environment(\.toyStyle, palette.style)
        .frame(width: 360, height: 360)
    }
}
