import SwiftUI
import Observation

// MARK: - Engine

/// A square of the maze, by column and row.
struct MazeCell: Hashable, Codable {
    var c: Int, r: Int
    func step(_ d: MazeDirection) -> MazeCell { MazeCell(c: c + d.dc, r: r + d.dr) }
}

enum MazeDirection: CaseIterable {
    case up, down, left, right
    var dc: Int { self == .left ? -1 : self == .right ? 1 : 0 }
    var dr: Int { self == .up ? -1 : self == .down ? 1 : 0 }
}

/// Swipe the ball through one-square corridors to paint the whole maze. The
/// ball rolls straight in the swiped direction until it hits a wall; it
/// never turns by itself. Painted squares can be crossed again.
@MainActor
@Observable
final class MazePaintEngine: GameEngine {
    static let levelCount = 60
    private static let levelKey = "mazePaintLevel"

    private(set) var level = 1
    private(set) var columns = 0
    private(set) var rows = 0
    private(set) var open: Set<MazeCell> = []
    private(set) var painted: Set<MazeCell> = []
    private(set) var ball = MazeCell(c: 0, r: 0)
    private(set) var moves = 0
    var state: GameState = .playing

    /// The last roll, for the view to animate: squares from start to stop,
    /// and the ones it painted for the first time.
    struct Roll: Equatable {
        let id: Int
        let path: [MazeCell]
        let fresh: Set<MazeCell>
        var length: Double { Double(max(1, path.count - 1)) }
        /// Longer rolls take longer, but not proportionally: the ball keeps speeding up.
        var duration: Double { 0.1 + 0.1 * length.squareRoot() }
        /// Squares travelled `elapsed` seconds in: an ease-in, so the ball
        /// starts slowly and accelerates until it hits the wall.
        func distance(at elapsed: Double) -> Double {
            let t = min(1, max(0, elapsed / duration))
            return length * t * t
        }
    }
    private(set) var lastRoll: Roll?

    var hasNextLevel: Bool { level < Self.levelCount }
    var score: Int { state == .gameOver(won: true) ? 100 + level * 30 : 0 }

    init() {
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: Self.levelKey)))
        restart()
    }

    func restart() {
        let maze = Self.generate(level: level)
        columns = maze.columns; rows = maze.rows; open = maze.open
        ball = maze.start
        painted = [ball]
        moves = 0
        lastRoll = nil
        state = .playing
    }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: Self.levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    func roll(_ direction: MazeDirection) {
        guard state == .playing else { return }
        let path = Self.path(from: ball, direction, open: open)
        guard path.count > 1 else { Haptics.tap(); return }
        let fresh = Set(path).subtracting(painted)
        painted.formUnion(path)
        ball = path[path.count - 1]
        moves += 1
        let roll = Roll(id: (lastRoll?.id ?? 0) + 1, path: path, fresh: fresh)
        lastRoll = roll
        SoundFX.play(.whoosh)
        // The win is announced once the ball has finished rolling.
        guard painted.count == open.count else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(roll.duration + 0.15))
            guard let self, self.lastRoll == roll, self.state == .playing else { return }
            UserDefaults.standard.set(min(Self.levelCount, self.level + 1), forKey: Self.levelKey)
            Haptics.success(); SoundFX.play(.clear)
            self.state = .gameOver(won: true)
        }
    }

    // MARK: Rolling

    /// Squares the ball passes from `start` when swiped in `direction`, start included.
    /// The ball only ever rolls straight: it never turns on its own.
    static func path(from start: MazeCell, _ direction: MazeDirection, open: Set<MazeCell>) -> [MazeCell] {
        var path = [start], here = start
        while open.contains(here.step(direction)) {
            here = here.step(direction)
            path.append(here)
        }
        return path
    }

    // MARK: Levels

    private struct Maze {
        let columns: Int, rows: Int
        let open: Set<MazeCell>
        let start: MazeCell
    }

    /// For each level, the first `attempt` that `maze(level:attempt:)` turns
    /// into a solvable maze, worked out ahead so opening a level is instant.
    private static let attempts = [2, 2, 0, 0, 1, 7, 3, 5, 2, 9, 1, 4,
                                   23, 10, 1, 4, 6, 49, 10, 43, 45, 66, 6, 86,
                                   45, 48, 47, 488, 73, 64, 1776, 279, 39, 1752, 1351, 330,
                                   3574, 2201, 17124, 3589, 7178, 1305, 110, 893, 600, 1593, 3841, 5287,
                                   2059, 3668, 8242, 122, 1952, 1890, 2647, 319, 382, 3747, 14150, 8896]

    private static func generate(level: Int) -> Maze {
        let known = attempts.indices.contains(level - 1) ? attempts[level - 1] : 0
        if let maze = maze(level: level, attempt: known) { return maze }
        // Only if the table is out of date: keep trying.
        var attempt = 0
        while true {
            if let maze = maze(level: level, attempt: attempt) { return maze }
            attempt += 1
        }
    }

    /// The first attempt at a solvable maze for `level`, for building `attempts`.
    static func firstSolvableAttempt(level: Int) -> Int {
        var attempt = 0
        while maze(level: level, attempt: attempt) == nil { attempt += 1 }
        return attempt
    }

    /// A random maze that grows with the level, or nil when not every square
    /// can be painted (see `isSolvable`). Deterministic per level and attempt.
    private static func maze(level: Int, attempt: Int) -> Maze? {
        let roomsWide = min(7, 3 + (level - 1) / 8), roomsHigh = min(10, 4 + (level - 1) / 6)
        var random = PuzzleRandom(seed: UInt64(level) &* 7_919 &+ UInt64(attempt) &* 104_729 &+ 31)
        do {
            var open = Set<MazeCell>()
            // Rooms on even squares, joined by a depth-first maze.
            var visited: Set<MazeCell> = [MazeCell(c: 0, r: 0)]
            var stack = [MazeCell(c: 0, r: 0)]
            open.insert(MazeCell(c: 0, r: 0))
            while let room = stack.last {
                let next = MazeDirection.allCases.map { MazeCell(c: room.c + $0.dc, r: room.r + $0.dr) }
                    .filter { (0..<roomsWide).contains($0.c) && (0..<roomsHigh).contains($0.r) && !visited.contains($0) }
                guard let pick = next.randomElement(using: &random) else { stack.removeLast(); continue }
                visited.insert(pick)
                open.insert(MazeCell(c: pick.c * 2, r: pick.r * 2))
                open.insert(MazeCell(c: room.c + pick.c, r: room.r + pick.r))
                stack.append(pick)
            }
            // A few extra openings make loops, so there is more than one way round.
            var walls: [MazeCell] = []
            for c in 0..<(roomsWide * 2 - 1) {
                for r in 0..<(roomsHigh * 2 - 1) where (c + r) % 2 == 1 {
                    let wall = MazeCell(c: c, r: r)
                    if !open.contains(wall) { walls.append(wall) }
                }
            }
            var spare = walls.shuffled(using: &random)[...]
            for wall in spare.prefix(min(level / 3, walls.count / 4)) { open.insert(wall) }
            spare = spare.dropFirst(min(level / 3, walls.count / 4))
            // Start in the dead end nearest the bottom-left corner.
            var start = MazeCell(c: 0, r: roomsHigh * 2 - 2)
            var bestScore = Int.min
            for cell in open {
                let exits = MazeDirection.allCases.filter { open.contains(cell.step($0)) }.count
                let score = cell.r * 100 - cell.c
                if exits == 1 && score > bestScore { bestScore = score; start = cell }
            }
            // A branch the ball always rolls past can't be painted; opening
            // another wall gives it a fork to stop at. Try a few before starting over.
            for _ in 0..<12 {
                if isSolvable(open: open, start: start) {
                    return Maze(columns: roomsWide * 2 - 1, rows: roomsHigh * 2 - 1, open: open, start: start)
                }
                guard let wall = spare.popFirst() else { break }
                open.insert(wall)
            }
            return nil
        }
    }

    /// Every square is on some roll the ball can make, and from anywhere the
    /// ball can stop it can get back, so no move ever strands the player.
    static func isSolvable(open: Set<MazeCell>, start: MazeCell) -> Bool {
        var edges: [MazeCell: Set<MazeCell>] = [:]
        var covered: Set<MazeCell> = [start]
        var queue = [start], seen: Set<MazeCell> = [start]
        while let here = queue.popLast() {
            for direction in MazeDirection.allCases {
                let path = path(from: here, direction, open: open)
                guard path.count > 1, let stop = path.last else { continue }
                covered.formUnion(path)
                edges[here, default: []].insert(stop)
                if seen.insert(stop).inserted { queue.append(stop) }
            }
        }
        guard covered.count == open.count else { return false }
        var back: [MazeCell: [MazeCell]] = [:]
        for (from, tos) in edges { for to in tos { back[to, default: []].append(from) } }
        var reach: Set<MazeCell> = [start], todo = [start]
        while let here = todo.popLast() {
            for from in back[here] ?? [] where reach.insert(from).inserted { todo.append(from) }
        }
        return reach.count == seen.count
    }
}

// MARK: - View

struct MazePaintView: View {
    @State private var engine = MazePaintEngine()
    @State private var rolling: (roll: MazePaintEngine.Roll, start: Date)?
    /// A swipe made while the ball is still rolling, played when it stops.
    @State private var queued: MazeDirection?
    /// Where the finger was when the current swipe's direction was last read.
    @State private var dragAnchor: CGPoint?
    @State private var dragDirection: MazeDirection?

    static let corridor = Color(red: 0.45, green: 0.53, blue: 0.72)
    static let paint = Color(red: 0.78, green: 0.2, blue: 0.3)

    var body: some View {
        GameContainerView(gameID: .mazePaint, engine: engine,
                          resultSummary: L10n.format("Level %d", engine.level),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 16) {
                statusBar
                board
                Text(L10n.text("Swipe to roll the ball until it hits a wall. Keep your finger down and swipe again to turn. Paint every square."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(engine.level)
        .onChange(of: engine.lastRoll) { _, roll in
            guard let roll else { rolling = nil; return }
            rolling = (roll, .now)
            Task {
                try? await Task.sleep(for: .seconds(roll.duration + 0.02))
                guard rolling?.roll == roll else { return }
                rolling = nil
                if let next = queued { queued = nil; engine.roll(next) }
            }
        }
    }

    private func steer(_ direction: MazeDirection) {
        if rolling == nil { engine.roll(direction) } else { queued = direction }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(1...MazePaintEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                Label(L10n.format("Level %d", engine.level), systemImage: "paintbrush.pointed.fill")
                    .font(.subheadline.weight(.semibold))
            }
            Label(L10n.format("%d moves", engine.moves), systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var board: some View {
        let columns = CGFloat(engine.columns), rows = CGFloat(engine.rows)
        return TimelineView(.animation(paused: rolling == nil)) { timeline in
            let progress = rolling.map { $0.roll.distance(at: timeline.date.timeIntervalSince($0.start)) }
            Canvas { context, size in
                let cell = min(size.width / columns, size.height / rows)
                let origin = CGPoint(x: (size.width - cell * columns) / 2, y: (size.height - cell * rows) / 2)
                draw(&context, cell: cell, origin: origin, progress: progress)
            }
        }
        .aspectRatio(columns / rows, contentMode: .fit)
        .padding(10)
        .background(Color(red: 0.12, green: 0.13, blue: 0.18), in: RoundedRectangle(cornerRadius: 20))
        .contentShape(Rectangle())
        // Every change of direction while the finger stays down is a new roll,
        // so the ball can be steered round a maze in one continuous swipe.
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let anchor = dragAnchor ?? value.startLocation
                let x = value.location.x - anchor.x, y = value.location.y - anchor.y
                guard max(abs(x), abs(y)) > 22 else { return }
                let direction: MazeDirection = abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
                dragAnchor = value.location
                guard direction != dragDirection else { return }
                dragDirection = direction
                steer(direction)
            }
            .onEnded { _ in dragAnchor = nil; dragDirection = nil })
        .accessibilityElement()
        .accessibilityLabel(L10n.text("Maze Paint"))
        .accessibilityValue("\(engine.painted.count) / \(engine.open.count)")
    }

    private func draw(_ context: inout GraphicsContext, cell: CGFloat, origin: CGPoint, progress: Double?) {
        func rect(_ m: MazeCell) -> CGRect {
            CGRect(x: origin.x + CGFloat(m.c) * cell, y: origin.y + CGFloat(m.r) * cell, width: cell, height: cell)
        }
        func center(_ m: MazeCell) -> CGPoint { CGPoint(x: rect(m).midX, y: rect(m).midY) }

        var corridors = Path()
        for m in engine.open { corridors.addRect(rect(m).insetBy(dx: -0.3, dy: -0.3)) }
        context.fill(corridors, with: .color(Self.corridor))
        // Faint seams between squares, as on graph paper.
        var seams = Path()
        for m in engine.open { seams.addRect(rect(m).insetBy(dx: 0.5, dy: 0.5)) }
        context.stroke(seams, with: .color(.black.opacity(0.08)), lineWidth: 0.6)

        // Squares this roll paints appear as the ball reaches them.
        let roll = rolling?.roll
        let reached = progress.map { Int($0) } ?? Int.max
        let shown: (MazeCell) -> Bool = { m in
            guard let roll, roll.fresh.contains(m), let index = roll.path.firstIndex(of: m) else { return true }
            return index <= reached
        }
        var paint = Path()
        for m in engine.painted where shown(m) { paint.addRect(rect(m).insetBy(dx: -0.3, dy: -0.3)) }
        context.fill(paint, with: .color(Self.paint))

        // The ball, between squares while it rolls.
        var position = center(engine.ball)
        if let roll, let progress, progress < Double(roll.path.count - 1) {
            let i = Int(progress), t = CGFloat(progress - Double(i))
            let a = center(roll.path[i]), b = center(roll.path[min(i + 1, roll.path.count - 1)])
            position = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            // A short comet tail behind it.
            let tailStart = center(roll.path[max(0, i - 2)])
            var tail = Path(); tail.move(to: tailStart); tail.addLine(to: position)
            context.stroke(tail, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: cell * 0.35, lineCap: .round))
        }
        let r = cell * 0.32
        context.fill(Path(ellipseIn: CGRect(x: position.x - r * 1.6, y: position.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                     with: .color(.white.opacity(0.15)))
        context.fill(Path(ellipseIn: CGRect(x: position.x - r, y: position.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [.white, Color(white: 0.8)]),
                                           center: CGPoint(x: position.x - r * 0.3, y: position.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
    }
}

// MARK: - Saved round

extension MazePaintEngine: ResumableGame {
    private struct Session: Codable {
        let level: Int
        let painted: [MazeCell]
        let ball: MazeCell
        let moves: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, moves > 0 else { return nil }
        return encodeSession(Session(level: level, painted: Array(painted), ball: ball, moves: moves))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data),
              (1...Self.levelCount).contains(session.level) else { return false }
        level = session.level
        restart()
        guard session.painted.allSatisfy(open.contains), open.contains(session.ball) else { return false }
        painted = Set(session.painted)
        ball = session.ball
        moves = session.moves
        return true
    }
}
