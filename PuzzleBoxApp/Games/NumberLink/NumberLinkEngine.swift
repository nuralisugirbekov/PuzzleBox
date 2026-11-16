import SwiftUI
import Observation

/// Number Link without numbers: pairs of shaped clay pieces joined by tubes.
///
/// Every level comes from `NumberLinkLevels`, made offline by
/// `tools/NumberLinkGenerator`. A solver proved that each level has exactly
/// one way to join its pairs and that this way covers every cell. So there is
/// no separate "fill the board" rule here: joining all pairs is the win, and
/// the board is full because the puzzle allows nothing else.
///
/// Controls follow the familiar flow-style rules: drag from either piece of a
/// pair, or from the loose end of a tube, to draw. Drawing back over your own
/// tube shortens it; drawing through another tube cuts it, and the cut part
/// comes back if you pull away again in the same drag.
@MainActor
@Observable
final class NumberLinkEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var level = 1
    private(set) var n = 5
    /// Pair index of the piece standing on each cell, or -1.
    private(set) var pieces: [Int] = []
    private(set) var pairs: [(Int, Int)] = []
    /// Tubes as they are shown now (the drag in progress included).
    private(set) var paths: [[Int]] = []
    /// The pair being drawn by the finger, if any.
    private(set) var drawing: Int?
    /// Strokes that changed something, counted the flow way: drawing the
    /// same tube again right away doesn't count again.
    private(set) var moves = 0
    /// Bumps once when the last pair joins; the view plays its wave on it.
    private(set) var solvedWave = 0
    /// Bumps when a pair joins, for a little pop on that tube.
    private(set) var joinedPair: (pair: Int, count: Int) = (-1, 0)

    static var levelCount: Int { NumberLinkLevels.all.count }
    private let levelKey = "numberLink.level"
    private var solution: [Int] = []
    private var committed: [[Int]] = []
    private var history: [[[Int]]] = []
    private var lastMovedPair: Int?
    private var strokeStart: [[Int]] = []
    private var stroke: [Int] = []

    init() {
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: levelKey)))
        restart()
    }

    // MARK: Level

    var hasNextLevel: Bool { level < Self.levelCount }
    var pairCount: Int { pairs.count }
    var joinedCount: Int { (0..<pairs.count).filter(isJoined).count }
    /// 3 stars when every tube was drawn in one go, 2 with a few redraws.
    var stars: Int { moves <= pairs.count ? 3 : moves <= pairs.count + 2 ? 2 : 1 }
    var canUndo: Bool { state == .playing && !history.isEmpty }
    var isSolved: Bool { !pairs.isEmpty && joinedCount == pairs.count }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    func restart() {
        load(NumberLinkLevels.all[level - 1])
        state = .playing; score = 0; moves = 0
        committed = Array(repeating: [], count: pairs.count)
        paths = committed; history = []; lastMovedPair = nil; drawing = nil; stroke = []
    }

    private func load(_ entry: (size: Int, puzzle: String, solution: String)) {
        n = entry.size
        let letters = Array("abcdefghijkl")
        let puzzle = Array(entry.puzzle)
        pieces = puzzle.map { letters.firstIndex(of: $0) ?? -1 }
        solution = Array(entry.solution).map { letters.firstIndex(of: $0) ?? -1 }
        let count = (pieces.max() ?? -1) + 1
        pairs = (0..<count).map { pair in
            let cells = pieces.indices.filter { pieces[$0] == pair }
            return (cells[0], cells[1])
        }
    }

    /// Starts over on the current level, keeping the level.
    func reset() {
        guard state == .playing, paths.contains(where: { !$0.isEmpty }) else { return }
        history.append(committed)
        committed = Array(repeating: [], count: pairs.count)
        paths = committed; lastMovedPair = nil
        Haptics.tap()
    }

    func undo() {
        guard state == .playing, let previous = history.popLast() else { return }
        committed = previous; paths = previous; drawing = nil; lastMovedPair = nil
        Haptics.tap()
    }

    // MARK: Drawing

    private func adjacent(_ a: Int, _ b: Int) -> Bool { abs(a / n - b / n) + abs(a % n - b % n) == 1 }
    private func partner(of cell: Int, pair: Int) -> Int { pairs[pair].0 == cell ? pairs[pair].1 : pairs[pair].0 }
    func isJoined(_ pair: Int) -> Bool {
        guard let first = paths[pair].first, let last = paths[pair].last, paths[pair].count > 1 else { return false }
        return pieces[first] == pair && pieces[last] == pair && first != last
    }
    /// The pair whose tube covers `cell`, if any.
    func owner(of cell: Int) -> Int? { paths.firstIndex { $0.contains(cell) } }

    func begin(at cell: Int) {
        guard state == .playing, pieces.indices.contains(cell) else { return }
        strokeStart = committed
        if pieces[cell] >= 0 {
            // A piece starts its pair's tube afresh from that end.
            drawing = pieces[cell]; stroke = [cell]
        } else if let pair = committed.firstIndex(where: { $0.contains(cell) }) {
            // Picking up a tube shortens it to that cell and carries on from there.
            let path = committed[pair]
            drawing = pair; stroke = Array(path[...path.firstIndex(of: cell)!])
        } else {
            drawing = nil; return
        }
        refresh()
        Haptics.tap()
    }

    func move(to cell: Int) {
        guard state == .playing, let pair = drawing, pieces.indices.contains(cell), let head = stroke.last, head != cell else { return }
        // A fast finger can skip cells: walk there one step at a time.
        var at = head
        while at != cell {
            let dr = cell / n - at / n, dc = cell % n - at % n
            let next = abs(dr) >= abs(dc) ? at + (dr > 0 ? n : -n) : at + (dc > 0 ? 1 : -1)
            guard step(to: next, pair: pair) else { break }
            at = next
        }
        refresh()
    }

    /// One step of the drawing finger; false when blocked.
    private func step(to cell: Int, pair: Int) -> Bool {
        guard let head = stroke.last, adjacent(head, cell) else { return false }
        if let back = stroke.firstIndex(of: cell) {
            stroke.removeSubrange((back + 1)...)
            return true
        }
        // A finished tube doesn't grow past its other piece.
        if stroke.count > 1, pieces[head] == pair { return false }
        if pieces[cell] >= 0 && pieces[cell] != pair { return false }
        stroke.append(cell)
        if pieces[cell] == pair {
            joinedPair = (pair, joinedPair.count + 1)
            SoundFX.play(.place)
            Haptics.move()
        } else {
            Haptics.tap()
        }
        return true
    }

    func end() {
        guard let pair = drawing else { return }
        refresh()
        drawing = nil; stroke = []
        let changed = paths != committed
        if changed {
            history.append(committed)
            if lastMovedPair != pair { moves += 1 }
            lastMovedPair = pair
        }
        // A lone piece isn't a tube.
        committed = paths.map { $0.count > 1 ? $0 : [] }
        paths = committed
        if isSolved { finish() }
    }

    /// Shows the tubes as committed, with the drawn one on top and the ones it
    /// crosses cut short (their cut parts come back if the finger pulls away).
    private func refresh() {
        guard let pair = drawing else { paths = committed; return }
        let taken = Set(stroke)
        var shown = strokeStart
        for other in shown.indices where other != pair {
            if let cut = shown[other].firstIndex(where: taken.contains) { shown[other] = Array(shown[other][..<cut]) }
        }
        shown[pair] = stroke
        paths = shown
    }

    private func finish() {
        // Joined pairs can only be the level's one solution, which fills the board.
        assert(Set(paths.joined()).count == n * n, "Number Link level \(level) is not unique")
        score = 100 + level * 50 + stars * 100
        UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: levelKey)
        solvedWave += 1
        Haptics.success()
        // Let the wave run over the board before the result window comes up.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, self.isSolved, self.state == .playing else { return }
            self.state = .gameOver(won: true)
        }
    }

    /// A fixed, almost finished position for the Home preview.
    func showcase() {
        selectLevelQuietly(14)
        for pair in pairs.indices where pair != 1 {
            committed[pair] = solvedPath(pair)
        }
        let open = solvedPath(1)
        committed[1] = Array(open.prefix(max(2, open.count / 2)))
        paths = committed
    }

    private func selectLevelQuietly(_ value: Int) {
        level = max(1, min(Self.levelCount, value))
        restart()
    }

    /// The level's own tube for `pair`, in order from its first piece.
    private func solvedPath(_ pair: Int) -> [Int] {
        var path = [pairs[pair].0]
        while path.last != pairs[pair].1 {
            let head = path.last!
            guard let next = [head - n, head + n, head - 1, head + 1].first(where: {
                solution.indices.contains($0) && adjacent(head, $0) && solution[$0] == pair && !path.contains($0)
            }) else { break }
            path.append(next)
        }
        return path
    }
}
