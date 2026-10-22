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
        spawn()

        if gained > 0 {
            popups.show("+\(gained)", color: .orange, at: UnitPoint(x: 0.5, y: 0.45),
                        large: gained >= 128)
            Haptics.move()
            SoundFX.play(.merge)
        } else {
            Haptics.tap()
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
                          resultSummary: L10n.format("%@ · %d×%d", L10n.text(engine.difficulty.title), engine.size, engine.size)) {
            VStack(spacing: 16) {
                Text(L10n.text("Merge matching tiles to reach 2048."))
                    .font(.subheadline).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Label(L10n.format("Best tile: %d", engine.bestTile), systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Self.color(for: engine.bestTile))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: engine.bestTile)
                    Spacer()
                    Button { withAnimation(.snappy(duration: 0.2)) { engine.undo() } } label: {
                        Label(L10n.text("Undo") + " (\(engine.undosLeft))", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.bold().monospacedDigit())
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(GameTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(engine.undoAvailable ? GameTheme.accent : GameTheme.textSecondary)
                    .disabled(!engine.undoAvailable)
                }
                board
                Text(L10n.text("Swipe to slide the tiles."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = geo.size.width
            let n = CGFloat(engine.size)
            let cell = (side - spacing * (n + 1)) / n
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.62, green: 0.56, blue: 0.50).opacity(0.85))
                ForEach(0..<(engine.size * engine.size), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.22))
                        .frame(width: cell, height: cell)
                        .offset(x: spacing + CGFloat(index % engine.size) * (cell + spacing),
                                y: spacing + CGFloat(index / engine.size) * (cell + spacing))
                }
                ForEach(engine.tiles) { tile in
                    Game2048TileView(tile: tile, size: cell, reduceMotion: reduceMotion)
                        .offset(x: spacing + CGFloat(tile.col) * (cell + spacing),
                                y: spacing + CGFloat(tile.row) * (cell + spacing))
                        .zIndex(tile.isVanishing ? 0 : 1)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.2).combined(with: .opacity))
                }
                ClassicFXPopupLayer(feed: engine.popups)
            }
            .frame(width: side, height: side)
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

    static func color(for value: Int) -> Color {
        switch value {
        case ...2: Color(red: 0.93, green: 0.89, blue: 0.85)
        case 4: Color(red: 0.93, green: 0.88, blue: 0.78)
        case 8: Color(red: 0.95, green: 0.69, blue: 0.47)
        case 16: Color(red: 0.96, green: 0.58, blue: 0.39)
        case 32: Color(red: 0.96, green: 0.49, blue: 0.37)
        case 64: Color(red: 0.96, green: 0.37, blue: 0.23)
        case 128: Color(red: 0.93, green: 0.81, blue: 0.45)
        case 256: Color(red: 0.93, green: 0.80, blue: 0.38)
        case 512: Color(red: 0.93, green: 0.78, blue: 0.31)
        case 1024: Color(red: 0.93, green: 0.77, blue: 0.25)
        default: Color(red: 0.93, green: 0.76, blue: 0.18)
        }
    }
}

private struct Game2048TileView: View {
    let tile: Game2048Tile
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let dark = tile.value <= 4
        RoundedRectangle(cornerRadius: min(12, size * 0.18), style: .continuous)
            .fill(Game2048View.color(for: tile.value).gradient)
            .overlay {
                Text(verbatim: "\(tile.value)")
                    .font(.system(size: size * (tile.value >= 1024 ? 0.3 : tile.value >= 128 ? 0.36 : 0.44),
                                  weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1).padding(4)
                    .foregroundStyle(dark ? Color(red: 0.47, green: 0.43, blue: 0.40) : .white)
            }
            .shadow(color: tile.value >= 128 ? Game2048View.color(for: tile.value).opacity(0.7) : .black.opacity(0.12),
                    radius: tile.value >= 128 ? 8 : 2, y: tile.value >= 128 ? 0 : 1)
            .frame(width: size, height: size)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: tile.mergeCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.08)
                    SpringKeyframe(reduceMotion ? 1 : 1.18, duration: 0.1)
                    SpringKeyframe(1, duration: 0.14)
                }
            }
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
        undoSnapshot = nil
        undoAvailable = false
        popups.clear()
        state = .playing
        return true
    }
}
