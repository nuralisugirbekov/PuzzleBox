import SwiftUI
import Observation

struct Game2048Tile: Identifiable, Equatable, Codable {
    let id: Int
    var value: Int
    var row: Int
    var col: Int
    /// Bumped whenever this tile absorbs another, to replay the merge pop.
    var mergeCount = 0
    /// Absorbed tiles slide into their partner, then disappear.
    var isVanishing = false
}

/// The board grows as the game gets easier: more room means fewer dead ends.
enum Game2048Difficulty: Int, CaseIterable, Codable {
    case easy, medium, hard
    var title: String { ["Easy", "Medium", "Hard"][rawValue] }
    var size: Int { [6, 5, 4][rawValue] }
}

@MainActor
@Observable
final class Game2048Engine: GameEngine {
    private static let difficultyKey = "game2048Difficulty"

    private(set) var difficulty: Game2048Difficulty
    var size: Int { difficulty.size }

    private(set) var tiles: [Game2048Tile] = []
    private(set) var score = 0
    private(set) var bestTile = 2
    private(set) var undoAvailable = false
    /// Undo is a limited resource so it cannot be used to reroll every spawn.
    private(set) var undosLeft = 3
    var state: GameState = .playing
    let popups = ClassicFXPopupFeed()
    /// Points of the last merges, flying from their tile up into the score.
    private(set) var flights: [ScoreFlight] = []
    /// Moves made this round; the swipe hint goes away after the first.
    private(set) var moveCount = 0
    private var flightID = 0

    struct ScoreFlight: Identifiable, Equatable {
        let id: Int
        let row: Int
        let col: Int
        let value: Int
    }

    enum Direction { case up, down, left, right }

    private var nextID = 0
    private var undoSnapshot: (tiles: [Game2048Tile], score: Int)?

    /// Board values in row-major order (vanishing tiles excluded).
    var values: [Int] {
        var grid = Array(repeating: 0, count: size * size)
        for tile in tiles where !tile.isVanishing { grid[tile.row * size + tile.col] = tile.value }
        return grid
    }

    /// The difficulty picked last, which the next game opens on.
    static var savedDifficulty: Game2048Difficulty {
        Game2048Difficulty(rawValue: UserDefaults.standard.integer(forKey: difficultyKey)) ?? .easy
    }

    /// Picked before the game opens. A saved round on another board size is
    /// dropped, so the game opens on the board that was asked for.
    static func choose(_ difficulty: Game2048Difficulty) {
        UserDefaults.standard.set(difficulty.rawValue, forKey: difficultyKey)
        if let saved = GameSessionStore.load(.game2048),
           (try? JSONDecoder().decode(SavedDifficulty.self, from: saved.payload))?.difficulty ?? .hard != difficulty {
            GameSessionStore.delete(.game2048)
        }
    }

    /// Just the difficulty of a saved round; rounds saved before there was a
    /// choice were played on the 4×4 board.
    private struct SavedDifficulty: Decodable {
        let difficulty: Game2048Difficulty?
    }

    init() {
        difficulty = Self.savedDifficulty
        restart()
    }

    func restart() {
        tiles = []
        score = 0
        bestTile = 2
        undoSnapshot = nil
        undoAvailable = false
        undosLeft = 3
        popups.clear()
        flights = []
        moveCount = 0
        state = .playing
        spawn()
        spawn()
    }

    private func spawn() {
        let grid = values
        guard let index = grid.indices.filter({ grid[$0] == 0 }).randomElement() else { return }
        nextID += 1
        tiles.append(Game2048Tile(id: nextID, value: Int.random(in: 0..<10) == 0 ? 4 : 2,
                                  row: index / size, col: index % size))
    }

    /// Drops tiles that finished their merge slide.
    func purgeVanished() {
        tiles.removeAll(where: \.isVanishing)
    }

    func move(_ direction: Direction) {
        guard state == .playing else { return }
        purgeVanished()
        let before = tiles
        let previousScore = score
        let n = size
        var gained = 0
        var biggestMerge = 0
        var moved = false
        var landed: [ScoreFlight] = []

        for line in 0..<n {
            // Cells of this line ordered from the edge the tiles slide toward.
            let cells: [(Int, Int)] = (0..<n).map { i in
                switch direction {
                case .left: (line, i)
                case .right: (line, n - 1 - i)
                case .up: (i, line)
                case .down: (n - 1 - i, line)
                }
            }
            let lineTiles = cells.compactMap { cell in
                tiles.firstIndex { $0.row == cell.0 && $0.col == cell.1 }
            }
            var slot = 0
            var lastIndex: Int?   // tile in the previous slot that may still merge
            for index in lineTiles {
                if let last = lastIndex, tiles[last].value == tiles[index].value {
                    // Slide onto the partner, then vanish; the partner doubles.
                    let target = cells[slot - 1]
                    tiles[index].row = target.0
                    tiles[index].col = target.1
                    tiles[index].isVanishing = true
                    tiles[last].value *= 2
                    tiles[last].mergeCount += 1
                    gained += tiles[last].value
                    flightID += 1
                    landed.append(ScoreFlight(id: flightID, row: target.0, col: target.1, value: tiles[last].value))
                    biggestMerge = max(biggestMerge, tiles[last].value)
                    lastIndex = nil // A merged tile cannot merge again during this move.
                    moved = true
                } else {
                    let target = cells[slot]
                    if tiles[index].row != target.0 || tiles[index].col != target.1 { moved = true }
                    tiles[index].row = target.0
                    tiles[index].col = target.1
                    lastIndex = index
                    slot += 1
                }
            }
        }

        guard moved else {
            tiles = before
            return
        }
        undoSnapshot = (before, previousScore)
        undoAvailable = undosLeft > 0
        score += gained
        moveCount += 1
        spawn()

        if gained > 0 {
            flights.append(contentsOf: landed)
            let ids = Set(landed.map(\.id))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                self?.flights.removeAll { ids.contains($0.id) }
            }
            Haptics.rigid()
            SoundFX.play(.merge)
        } else {
            Haptics.soft()
            SoundFX.play(.place)
        }
        if biggestMerge > bestTile {
            bestTile = biggestMerge
            if biggestMerge >= 128 {
                Haptics.heavy()
                SoundFX.play(.coin)
            }
        }

        if values.contains(2048) {
            state = .gameOver(won: true)
        } else if !hasMoves {
            state = .gameOver(won: false)
        }
    }

    /// One step back, so a single slip does not end a long run.
    func undo() {
        guard state == .playing, undosLeft > 0, let snapshot = undoSnapshot else { return }
        undosLeft -= 1
        tiles = snapshot.tiles
        score = snapshot.score
        bestTile = max(2, tiles.map(\.value).max() ?? 2)
        undoSnapshot = nil
        undoAvailable = false
        Haptics.tap()
        SoundFX.play(.whoosh)
    }

    private var hasMoves: Bool {
        let grid = values
        if grid.contains(0) { return true }
        let n = size
        for i in grid.indices {
            if i % n < n - 1, grid[i] == grid[i + 1] { return true }
            if i / n < n - 1, grid[i] == grid[i + n] { return true }
        }
        return false
    }
}

struct Game2048View: View {
    @State private var engine = Game2048Engine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tighter gaps on the bigger boards keep the tiles readable.
    private var spacing: CGFloat { engine.size > 4 ? 6 : 8 }

    var body: some View {
        GameContainerView(gameID: .game2048, engine: engine,
                          resultSummary: L10n.format("%@ · %d×%d", L10n.text(engine.difficulty.title), engine.size, engine.size),
                          chrome: .inGame,
                          backdrop: AnyView(Toy2048.backdrop),
                          toyStyle: Toy2048.style) {
            Game2048Stage(engine: engine) { board }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let n = CGFloat(engine.size)
            let cell = (side - spacing * (n + 1)) / n
            ZStack(alignment: .topLeading) {
                ForEach(0..<(engine.size * engine.size), id: \.self) { index in
                    ToySocket(color: Toy2048.socket,
                              shape: RoundedRectangle(cornerRadius: min(14, cell * 0.22), style: .continuous))
                        .frame(width: cell, height: cell)
                        .offset(x: spacing + CGFloat(index % engine.size) * (cell + spacing),
                                y: spacing + CGFloat(index / engine.size) * (cell + spacing))
                }
                ForEach(engine.tiles) { tile in
                    Game2048TileView(tile: tile, size: cell, reduceMotion: reduceMotion)
                        .offset(x: spacing + CGFloat(tile.col) * (cell + spacing),
                                y: spacing + CGFloat(tile.row) * (cell + spacing))
                        .zIndex(tile.isVanishing ? 0 : 1)
                        // New tiles drop into their socket and settle with a little bounce.
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(y: -cell * 0.45)
                                .combined(with: .scale(scale: 1.08))
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.34, dampingFraction: 0.55).delay(0.06)),
                            removal: .opacity))
                }
                // Merge points rise from their tile into the score.
                let origin = geo.frame(in: .named(Toy2048.space)).origin
                ForEach(engine.flights) { flight in
                    ScoreFlightView(value: flight.value,
                                    start: CGPoint(x: spacing + CGFloat(flight.col) * (cell + spacing) + cell / 2,
                                                   y: spacing + CGFloat(flight.row) * (cell + spacing) + cell / 2),
                                    boardOrigin: origin,
                                    reduceMotion: reduceMotion)
                        .zIndex(2)
                }
            }
            .frame(width: side, height: side, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .id(engine.size)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            let x = value.translation.width, y = value.translation.height
            let direction: Game2048Engine.Direction = abs(x) > abs(y)
                ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
            withAnimation(reduceMotion ? .linear(duration: 0.05) : .easeOut(duration: 0.12)) {
                engine.move(direction)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                engine.purgeVanished()
            }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let grid = engine.values
        return (0..<engine.size).map { r in
            (0..<engine.size).map { c in
                let v = grid[r * engine.size + c]
                return v == 0 ? "·" : "\(v)"
            }.joined(separator: " ")
        }.joined(separator: ", ")
    }

    /// A calm toy ladder: cream and sand, the warm fruits, then cool greens and blues.
    static func color(for value: Int) -> Color {
        switch value {
        case ...2: Color(red: 0.97, green: 0.95, blue: 0.91)
        case 4: Color(red: 0.95, green: 0.89, blue: 0.78)
        case 8: Color(red: 0.98, green: 0.76, blue: 0.58)
        case 16: Color(red: 0.97, green: 0.64, blue: 0.48)
        case 32: Color(red: 0.94, green: 0.52, blue: 0.47)
        case 64: Color(red: 0.85, green: 0.42, blue: 0.45)
        case 128: Color(red: 0.60, green: 0.77, blue: 0.53)
        case 256: Color(red: 0.43, green: 0.73, blue: 0.60)
        case 512: Color(red: 0.35, green: 0.66, blue: 0.71)
        case 1024: Color(red: 0.44, green: 0.59, blue: 0.85)
        default: Color(red: 0.61, green: 0.51, blue: 0.85)
        }
    }
}

private struct Squash {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

private struct Game2048TileView: View {
    let tile: Game2048Tile
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let dark = tile.value <= 4
        let lip = max(3, size * 0.07)
        ToyBlock(color: Game2048View.color(for: tile.value),
                 shape: RoundedRectangle(cornerRadius: min(14, size * 0.22), style: .continuous),
                 lip: lip)
            .overlay {
                Text(verbatim: "\(tile.value)")
                    .font(.system(size: size * (tile.value >= 1024 ? 0.3 : tile.value >= 128 ? 0.36 : 0.44),
                                  weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1).padding(4)
                    .foregroundStyle(dark ? Color(red: 0.47, green: 0.43, blue: 0.40) : .white)
                    .shadow(color: .black.opacity(dark ? 0 : 0.18), radius: 0, y: 1)
                    .padding(.bottom, lip)
            }
            .frame(width: size, height: size)
            // Merges squash the tile flat, then let it spring back up like soft plastic.
            .keyframeAnimator(initialValue: Squash(), trigger: tile.mergeCount) { content, squash in
                content.scaleEffect(x: squash.x, y: squash.y, anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack(\.x) {
                    CubicKeyframe(1, duration: 0.08)
                    CubicKeyframe(reduceMotion ? 1 : 1.14, duration: 0.07)
                    SpringKeyframe(reduceMotion ? 1 : 0.94, duration: 0.1)
                    SpringKeyframe(1, duration: 0.16)
                }
                KeyframeTrack(\.y) {
                    CubicKeyframe(1, duration: 0.08)
                    CubicKeyframe(reduceMotion ? 1 : 0.86, duration: 0.07)
                    SpringKeyframe(reduceMotion ? 1 : 1.1, duration: 0.1)
                    SpringKeyframe(1, duration: 0.16)
                }
            }
    }
}

// MARK: - Toy stage

/// Colours of the 2048 toy box: warm sand around a clay tray.
enum Toy2048 {
    static let backdropTop = Color.dynamic(light: (0.98, 0.95, 0.90), dark: (0.17, 0.14, 0.12))
    static let backdropBottom = Color.dynamic(light: (0.94, 0.88, 0.80), dark: (0.10, 0.08, 0.07))
    static let tray = Color.dynamic(light: (0.78, 0.69, 0.59), dark: (0.36, 0.30, 0.25))
    static let socket = Color.dynamic(light: (0.70, 0.61, 0.52), dark: (0.27, 0.22, 0.19))
    static let ink = Color.dynamic(light: (0.40, 0.33, 0.27), dark: (0.93, 0.88, 0.82))
    static let deboss = Color.dynamic(light: (0.86, 0.78, 0.68), dark: (0.42, 0.36, 0.31))
    /// The lit lower rim of the pressed-in score.
    static let debossRim = Color.dynamic(light: (1.0, 0.98, 0.95), dark: (0.21, 0.18, 0.15))

    static let space = "toy2048"
    static let style = ToyStyle(card: Color.dynamic(light: (1.0, 0.99, 0.96), dark: (0.24, 0.21, 0.18)),
                                accent: Color(red: 0.94, green: 0.52, blue: 0.47),
                                ink: ink, tray: tray, haze: backdropBottom)

    static var backdrop: some View {
        LinearGradient(colors: [backdropTop, backdropBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension EnvironmentValues {
    /// Where the 2048 score sits, in `Toy2048.space`; merge points fly there.
    @Entry var toy2048ScoreTarget: CGPoint = .zero
}

/// "+16" rising from a merged tile and shrinking into the score.
private struct ScoreFlightView: View {
    let value: Int
    let start: CGPoint
    /// The board's corner in `Toy2048.space`, to turn the score's position
    /// into board coordinates.
    let boardOrigin: CGPoint
    let reduceMotion: Bool
    // Read here, inside the stage that sets it; the game view above it only
    // ever sees the default.
    @Environment(\.toy2048ScoreTarget) private var scoreTarget
    @State private var flying = false
    /// Fades only at the very end, so the points stay readable all the way.
    @State private var landed = false

    private var target: CGPoint {
        CGPoint(x: scoreTarget.x - boardOrigin.x, y: scoreTarget.y - boardOrigin.y)
    }

    var body: some View {
        Text(verbatim: "+\(value)")
            .font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(Game2048View.color(for: value).toyShade(-0.3))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.92)))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            .scaleEffect(flying ? 0.7 : 1.1)
            .opacity(landed ? 0 : 1)
            .position(flying && !reduceMotion ? target : start)
            .onAppear {
                let flight = reduceMotion ? 0.0 : 0.45
                withAnimation(.easeIn(duration: flight).delay(0.12)) { flying = true }
                withAnimation(.easeOut(duration: 0.12).delay(0.12 + flight)) { landed = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The whole 2048 screen: toy buttons beside the score pressed into the sand,
/// then the clay tray low on the screen, near the thumb.
private struct Game2048Stage<Board: View>: View {
    let engine: Game2048Engine
    @ViewBuilder let board: () -> Board
    @Environment(\.gameHUD) private var hud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scoreTarget = CGPoint.zero
    /// Bumps when flying points reach the score.
    @State private var scoreBump = 0

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack(alignment: .top) {
                    ToyIconButton(symbol: "pause.fill", label: L10n.text("Paused"), ink: Toy2048.ink) { hud.pause() }
                    Spacer()
                    undoButton
                }
                pressedScore
                    .padding(.horizontal, 56)
            }
            Spacer(minLength: 16)
            tray
            footer
                .padding(.top, 14)
            // Equal room above and below so the board sits in the middle.
            Spacer(minLength: 4)
        }
        .foregroundStyle(Toy2048.ink)
        .coordinateSpace(name: Toy2048.space)
        .environment(\.toy2048ScoreTarget, scoreTarget)
        .onChange(of: hud.score) { old, new in
            guard new > old else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(480))
                scoreBump += 1
            }
        }
    }

    private var undoButton: some View {
        VStack(spacing: 6) {
            ToyIconButton(symbol: "arrow.uturn.backward", label: L10n.text("Undo"), ink: Toy2048.ink) {
                withAnimation(.snappy(duration: 0.2)) { engine.undo() }
            }
            .disabled(!engine.undoAvailable)
            .opacity(engine.undoAvailable ? 1 : 0.55)
            // Undos left, as three little pips.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Toy2048.ink.opacity(i < engine.undosLeft ? 0.75 : 0.18))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.snappy, value: engine.undosLeft)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(verbatim: "\(engine.undosLeft)"))
    }

    /// The score as big letters pressed into the backdrop.
    private var pressedScore: some View {
        VStack(spacing: 0) {
            Text(hud.score, format: .number)
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundStyle(Toy2048.deboss)
                .shadow(color: Toy2048.debossRim, radius: 0, y: 1.5)
                .shadow(color: .black.opacity(0.08), radius: 0, y: -1)
                .contentTransition(.numericText())
                .animation(.snappy, value: hud.score)
                .lineLimit(1).minimumScaleFactor(0.4)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: scoreBump) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(reduceMotion ? 1 : 1.1, duration: 0.08)
                        SpringKeyframe(1, duration: 0.25)
                    }
                }
                .onGeometryChange(for: CGPoint.self) { proxy in
                    let frame = proxy.frame(in: .named(Toy2048.space))
                    return CGPoint(x: frame.midX, y: frame.midY)
                } action: { scoreTarget = $0 }
            Label {
                Text(L10n.text("Your best") + " · ") + Text(hud.best, format: .number)
            } icon: {
                Image(systemName: "crown.fill")
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Toy2048.ink.opacity(0.7))
        }
        .accessibilityElement(children: .combine)
    }

    private var tray: some View {
        board()
            .padding(10)
            .padding(.bottom, 8)
            .background {
                ToyBlock(color: Toy2048.tray, shape: RoundedRectangle(cornerRadius: 28, style: .continuous), lip: 8)
            }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Label {
                Text(L10n.format("Best tile: %d", engine.bestTile))
            } icon: {
                Image(systemName: "star.fill").foregroundStyle(Game2048View.color(for: max(engine.bestTile, 8)))
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .contentTransition(.numericText())
            .animation(.snappy, value: engine.bestTile)
            // Only until the first swipe.
            Text(L10n.text("Swipe to slide the tiles."))
                .font(.system(.footnote, design: .rounded))
                .opacity(engine.moveCount == 0 ? 0.6 : 0)
                .accessibilityHidden(!(engine.moveCount == 0))
        }
        .animation(.easeOut(duration: 0.3), value: engine.moveCount == 0)
    }
}

// MARK: - Saved round

extension Game2048Engine: ResumableGame {
    private struct Session: Codable {
        let tiles: [Game2048Tile]
        let score: Int
        let bestTile: Int
        let undosLeft: Int
        let nextID: Int
        var difficulty: Game2048Difficulty?
    }

    func saveSession() -> Data? {
        // A board with only the two opening tiles has no progress to keep.
        guard state == .playing || state == .paused, score > 0 else { return nil }
        purgeVanished()
        return encodeSession(Session(tiles: tiles, score: score, bestTile: bestTile,
                                     undosLeft: undosLeft, nextID: nextID, difficulty: difficulty))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        difficulty = session.difficulty ?? .hard
        tiles = session.tiles.filter { !$0.isVanishing }
        score = session.score
        bestTile = session.bestTile
        undosLeft = session.undosLeft
        nextID = session.nextID
        flights = []
        moveCount = session.score > 0 ? 1 : 0
        undoSnapshot = nil
        undoAvailable = false
        popups.clear()
        state = .playing
        return true
    }
}
