import SwiftUI
import Observation

enum PuzzleMode: String {
    case lightsOut, nonogram, numberConnect, oneLine, unblock, fifteenPuzzle, pipeConnect, dots, floodFill, laser, colorLines
    var id: GameID {
        switch self {
        case .lightsOut: .lightsOut
        case .nonogram: .nonogram
        case .numberConnect: .numberConnect
        case .oneLine: .oneLine
        case .unblock: .unblock
        case .fifteenPuzzle: .fifteenPuzzle
        case .pipeConnect: .pipeConnect
        case .dots: .dots
        case .floodFill: .floodFill
        case .laser: .laser
        case .colorLines: .colorLines
        }
    }
    var hint: String {
        switch self {
        case .lightsOut: "Tap to toggle a light and its neighbors. Turn all lights off."
        case .nonogram: "Use the row and column clues to fill the picture."
        case .numberConnect: "Connect matching numbers without crossing. Fill every cell."
        case .oneLine: "Trace every edge once. Tap connected nodes."
        case .unblock: "Slide blocks along their length. Free the red block."
        case .fifteenPuzzle: "Slide tiles into order, with the empty cell last."
        case .pipeConnect: "Rotate pipes to connect IN to OUT through every cell."
        case .dots: "Connect adjacent matching dots, then release or tap Collect."
        case .floodFill: "Choose colors to fill the board from the top-left corner."
        case .laser: "Rotate mirrors to guide the beam from the arrow to the star."
        case .colorLines: "Move balls along clear paths. Make lines of five before the board fills."
        }
    }
}

struct SlidingPiece: Identifiable {
    let id: Int
    var row: Int
    var col: Int
    let length: Int
    let horizontal: Bool
    var cells: [Int] { (0..<length).map { (row + (horizontal ? 0 : $0)) * 6 + col + (horizontal ? $0 : 0) } }
}

@MainActor
@Observable
final class PuzzleCollectionEngine: GameEngine {
    let mode: PuzzleMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var n = 5
    private(set) var grid: [Int] = []
    private(set) var target: [Int] = []
    private(set) var marks: Set<Int> = []
    var markMode = false
    private(set) var moves = 0
    private(set) var movesLeft = 25
    private(set) var selected: Int?
    private(set) var paths: [Int: [Int]] = [:]
    private(set) var activePath: [Int] = []
    private(set) var pieces: [SlidingPiece] = []
    private(set) var beam: [Int] = []
    private(set) var nodes: [Int] = []
    private(set) var edges: [[Int]] = []
    private(set) var level = 1
    /// Moves an expert needs; drives the star rating.
    private(set) var par = 0
    private(set) var colorCount = 5
    private(set) var nextBalls: [Int] = []
    private(set) var laserSource = 10
    private(set) var laserTarget = 15
    private(set) var pipeEnd = 12
    private(set) var pipeExit = 4
    private(set) var loopClosed = false
    private(set) var combo = 0

    private var history: [([Int], Int)] = []
    static let levelCount = 60

    init(mode: PuzzleMode) {
        self.mode = mode
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: levelKey)))
        restart()
    }

    private var levelKey: String { "puzzleLevel." + mode.rawValue }
    /// Endless score-attack modes have no level ladder.
    var hasLevels: Bool { mode != .dots && mode != .colorLines }
    var hasNextLevel: Bool { hasLevels && level < Self.levelCount }
    /// 3 stars at or under par, 2 within 50 % over, else 1.
    var stars: Int { par == 0 ? 3 : moves <= par ? 3 : Double(moves) <= Double(par) * 1.5 ? 2 : 1 }

    func selectLevel(_ value: Int) {
        guard hasLevels, (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    var canUndo: Bool { state == .playing && (!history.isEmpty || !activePath.isEmpty || !paths.isEmpty) }
    private func adjacent(_ a: Int, _ b: Int) -> Bool { abs(a / n - b / n) + abs(a % n - b % n) == 1 }
    private func neighbors(_ i: Int) -> [Int] { [i - n, i + n, i - 1, i + 1].filter { grid.indices.contains($0) && adjacent(i, $0) } }
    private func win() {
        score = 100 + level * 50 + stars * 100
        if hasLevels { UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: levelKey) }
        state = .gameOver(won: true)
        Haptics.success()
    }
    private func save() { history.append((grid, score)) }

    func restart() {
        state = .playing; score = 0; moves = 0; selected = nil; marks = []; markMode = false
        paths = [:]; activePath = []; pieces = []; beam = []; history = []; loopClosed = false; combo = 0
        n = 5; movesLeft = 25; grid = Array(repeating: 0, count: 25); target = []; par = 0
        var random = PuzzleRandom(seed: UInt64(level) &* 7919 &+ UInt64(mode.rawValue.hashValueStable))
        let l = level
        switch mode {
        case .lightsOut:
            n = min(7, 3 + (l - 1) / 6)
            let presses = min(n * n - 2, 2 + (l - 1) % 6 + n / 2)
            grid = PuzzleGenerators.lightsOut(n: n, presses: presses, random: &random)
            par = presses
        case .nonogram:
            n = min(9, 5 + (l - 1) / 10)
            target = PuzzleGenerators.nonogram(n: n, random: &random)
            grid = Array(repeating: 0, count: n * n)
        case .numberConnect:
            n = min(8, 5 + (l - 1) / 12)
            let pairs = min(n + 1, n - 1 + (l - 1) % 12 / 6)
            grid = PuzzleGenerators.numberConnect(n: n, pairs: min(pairs, 7), random: &random)
        case .oneLine:
            let size = l < 8 ? 3 : l < 25 ? 4 : 5
            n = size
            let (nodeList, edgeList) = PuzzleGenerators.oneLine(size: size, edgeCount: min(size * size * 2, 6 + l / 2), random: &random)
            nodes = nodeList; edges = edgeList
            grid = Array(repeating: 0, count: n * n)
        case .unblock:
            n = 6; grid = Array(repeating: 0, count: 36)
            pieces = PuzzleGenerators.rushHour(pieceCount: min(12, 6 + l / 6), targetDepth: min(26, 5 + l / 2), random: &random)
            par = PuzzleGenerators.rushHourDepth(pieces) ?? 0
        case .fifteenPuzzle:
            n = l < 6 ? 3 : 4
            grid = Array(1..<(n * n)) + [0]; target = grid
            let shuffles = n == 3 ? 12 + l * 4 : 30 + l * 6
            var last = -1
            for _ in 0..<shuffles {
                let empty = grid.firstIndex(of: 0)!, choices = neighbors(empty).filter { $0 != last }
                let source = choices.randomElement(using: &random)!; grid.swapAt(source, empty); last = empty
            }
            if grid == target { grid.swapAt(grid.count - 2, grid.count - 1); grid.swapAt(grid.count - 3, grid.count - 2) }
            par = min(shuffles, n == 3 ? 30 : 80)
        case .pipeConnect:
            n = min(7, 4 + (l - 1) / 8)
            let (solved, end, exit) = PuzzleGenerators.pipes(n: n, random: &random)
            target = solved; pipeEnd = end; pipeExit = exit
            grid = solved
            for i in grid.indices { for _ in 0..<Int.random(in: 0..<4, using: &random) { grid[i] = rotate(grid[i]) } }
            // Keep the entrance disconnected at the start, without changing solvability.
            while grid[0] & 8 != 0 { grid[0] = rotate(grid[0]) }
            par = zip(grid, solved).filter { $0 != $1 }.count
            updatePipes()
        case .dots:
            n = 6; colorCount = 4; grid = (0..<36).map { _ in Int.random(in: 1...4) }; movesLeft = 20
            grid[1] = grid[0] // At least one opening move.
        case .floodFill:
            n = min(14, 8 + (l - 1) / 5)
            colorCount = l < 15 ? 5 : 6
            grid = (0..<(n * n)).map { _ in Int.random(in: 1...colorCount, using: &random) }
            let greedy = PuzzleGenerators.floodGreedySteps(grid, n: n, colors: colorCount)
            movesLeft = greedy + max(0, 4 - l / 6)
            par = greedy
        case .laser:
            n = min(8, 5 + (l - 1) / 12)
            let turns = min(n + 1, 2 + (l - 1) / 5)
            let (mirrors, source, goal) = PuzzleGenerators.laser(n: n, turns: turns, decoys: min(8, l / 3), random: &random)
            grid = mirrors; laserSource = source; laserTarget = goal
            // Flip some mirrors so the beam starts off course.
            let mirrorCells = grid.indices.filter { grid[$0] > 0 }
            for i in mirrorCells where Bool.random(using: &random) { grid[i] = 3 - grid[i] }
            updateLaser()
            if beam.last == laserTarget, let first = mirrorCells.first { grid[first] = 3 - grid[first]; updateLaser() }
            par = turns
        case .colorLines:
            n = 9; grid = Array(repeating: 0, count: 81); colorCount = 6
            nextBalls = (0..<3).map { _ in Int.random(in: 1...colorCount) }
            spawnBalls(5)
        }
    }

    func tap(_ i: Int) {
        guard state == .playing, grid.indices.contains(i) else { return }
        switch mode {
        case .lightsOut:
            save(); toggle(i); moves += 1
            if grid.allSatisfy({ $0 == 0 }) { win() }
        case .nonogram:
            if markMode { if !marks.insert(i).inserted { marks.remove(i) }; grid[i] = 0 }
            else { grid[i] = 1 - grid[i]; marks.remove(i) }
            moves += 1
            if nonogramSolved { win() }
        case .numberConnect: connect(i)
        case .oneLine: trace(i)
        case .unblock: selected = pieces.firstIndex { $0.cells.contains(i) }
        case .fifteenPuzzle:
            guard let empty = grid.firstIndex(of: 0) else { return }
            // Tapping any tile in the empty cell's row or column slides the whole line.
            let sameRow = i / n == empty / n, sameColumn = i % n == empty % n
            guard i != empty, sameRow || sameColumn else { return }
            save()
            let step = sameRow ? (i > empty ? 1 : -1) : (i > empty ? n : -n)
            var hole = empty
            while hole != i { grid.swapAt(hole, hole + step); hole += step; moves += 1 }
            if grid == target { win() }
        case .pipeConnect:
            save(); grid[i] = rotate(grid[i]); moves += 1; updatePipes()
        case .dots: extendDots(i)
        case .floodFill: break // Color buttons are the controls for this mode.
        case .laser:
            guard grid[i] > 0 else { return }; save(); grid[i] = 3 - grid[i]; moves += 1; updateLaser()
            if beam.last == laserTarget { win() }
        case .colorLines: moveBall(i)
        }
        Haptics.tap(); SoundFX.play(.tap)
    }

    var nonogramSolved: Bool {
        (0..<n).allSatisfy { r in clues(Array(grid[(r*n)..<(r*n+n)])) == rowClues[r] }
            && (0..<n).allSatisfy { c in clues((0..<n).map { grid[$0*n+c] }) == columnClues[c] }
    }
    /// Rows and columns whose current fill already matches their clue.
    func rowSolved(_ r: Int) -> Bool { clues(Array(grid[(r*n)..<(r*n+n)])) == rowClues[r] }
    func columnSolved(_ c: Int) -> Bool { clues((0..<n).map { grid[$0*n+c] }) == columnClues[c] }

    private func toggle(_ i: Int) { for index in [i] + neighbors(i) { grid[index] = 1 - grid[index] } }
    func undo() {
        guard state == .playing else { return }
        if mode == .numberConnect { paths = [:]; activePath = []; selected = nil; return }
        if mode == .oneLine || mode == .dots { if !activePath.isEmpty { activePath.removeLast(); loopClosed = false }; return }
        if let previous = history.popLast() {
            grid = previous.0; score = previous.1; moves += 1
            if mode == .pipeConnect { updatePipes() }
            if mode == .laser { updateLaser() }
        }
    }
    func clues(_ values: [Int]) -> [Int] {
        var result: [Int] = [], count = 0
        for value in values + [0] { if value == 1 { count += 1 } else if count > 0 { result.append(count); count = 0 } }
        return result.isEmpty ? [0] : result
    }
    var rowClues: [[Int]] { (0..<n).map { clues(Array(target[($0 * n)..<($0 * n + n)])) } }
    var columnClues: [[Int]] { (0..<n).map { c in clues((0..<n).map { target[$0 * n + c] }) } }
    var pairCount: Int { Set(grid.filter { $0 > 0 }).count }
    private func connect(_ i: Int) {
        if let color = selected, let last = activePath.last, adjacent(last, i) {
            if activePath.count > 1, activePath[activePath.count - 2] == i {
                activePath.removeLast(); paths[color] = activePath; return
            }
            let occupied = paths.filter { $0.key != color }.values.flatMap { $0 }
            if !activePath.contains(i), !occupied.contains(i), grid[i] == 0 || grid[i] == color {
                activePath.append(i); paths[color] = activePath
                if grid[i] == color {
                    selected = nil; activePath = []
                    SoundFX.play(.place)
                    let complete = paths.values.filter { $0.count > 1 && grid[$0.first!] == grid[$0.last!] }.count
                    if complete == pairCount, Set(paths.values.flatMap { $0 }).count == n * n { win() }
                }
                return
            }
        }
        if grid[i] > 0 { selected = grid[i]; activePath = [i]; paths[grid[i]] = [i] }
    }
    private func trace(_ i: Int) {
        guard nodes.contains(i) else { return }
        if activePath.isEmpty { activePath = [i]; return }
        let a = activePath.last!
        guard edges.contains(where: { Set($0) == Set([a, i]) }) else { return }
        let used = zip(activePath, activePath.dropFirst()).contains { pair in Set([pair.0, pair.1]) == Set([a, i]) }
        guard !used else { return }
        activePath.append(i); moves += 1
        if activePath.count == edges.count + 1 { win() }
    }
    func slide(dr: Int, dc: Int) {
        guard state == .playing, let index = selected, pieces.indices.contains(index) else { return }
        var piece = pieces[index]
        guard piece.horizontal ? (dr == 0 && abs(dc) == 1) : (dc == 0 && abs(dr) == 1) else { return }
        piece.row += dr; piece.col += dc
        guard piece.row >= 0, piece.col >= 0,
              piece.row + (piece.horizontal ? 1 : piece.length) <= 6,
              piece.col + (piece.horizontal ? piece.length : 1) <= 6 else { return }
        let occupied = Set(pieces.filter { $0.id != piece.id }.flatMap(\.cells))
        guard piece.cells.allSatisfy({ !occupied.contains($0) }) else { return }
        pieces[index] = piece; moves += 1; Haptics.move(); SoundFX.play(.place)
        if piece.id == 0, piece.col + piece.length == 6 { win() }
    }
    /// Slides the selected piece as far as a drag of `steps` cells allows.
    func slide(dr: Int, dc: Int, steps: Int) {
        for _ in 0..<max(1, steps) where state == .playing {
            let before = moves
            slide(dr: dr, dc: dc)
            if moves == before { break }
        }
    }
    private func rotate(_ mask: Int) -> Int { ((mask << 1) & 15) | (mask >> 3) }
    private func opposite(_ bit: Int) -> Int { bit == 1 ? 4 : bit == 4 ? 1 : bit == 2 ? 8 : 2 }
    private func updatePipes() {
        var reached: Set<Int> = [], queue = [0]
        guard grid[0] & 8 != 0 else { beam = []; return }
        while let i = queue.popLast() {
            if !reached.insert(i).inserted { continue }
            for (bit, delta) in [(1, -n), (2, 1), (4, n), (8, -1)] where grid[i] & bit != 0 {
                let next = i + delta
                if grid.indices.contains(next), adjacent(i, next), grid[next] & opposite(bit) != 0 { queue.append(next) }
            }
        }
        beam = Array(reached)
        // Each tile has exactly two ports; reaching all cells and the sink makes one sealed route.
        if reached.count == grid.count, grid[pipeEnd] & pipeExit != 0 { win() }
    }
    private func region(_ source: Int) -> Set<Int> {
        var found: Set<Int> = [], queue = [source]
        let value = grid[source]
        while let i = queue.popLast() {
            guard found.insert(i).inserted else { continue }
            queue += neighbors(i).filter { grid[$0] == value && !found.contains($0) }
        }
        return found
    }

    // MARK: Dots

    private func extendDots(_ i: Int) {
        if activePath.isEmpty { activePath = [i]; loopClosed = false; return }
        if activePath.last == i { return }
        if activePath.count > 1, activePath[activePath.count - 2] == i { activePath.removeLast(); loopClosed = false; return }
        guard !loopClosed else { return }
        if grid[i] == grid[activePath[0]], adjacent(activePath.last!, i) {
            if !activePath.contains(i) { activePath.append(i); SoundFX.play(.simon(min(3, activePath.count / 3))) }
            else if activePath.count >= 4 {
                // Closing a loop clears every dot of that colour.
                activePath.append(i); loopClosed = true; Haptics.move(); SoundFX.play(.coin)
            }
        } else { activePath = [i] }
    }
    private var hasGroups: Bool { grid.indices.contains { i in grid[i] > 0 && neighbors(i).contains { grid[$0] == grid[i] } } }
    func collectDots() {
        guard state == .playing, mode == .dots, activePath.count >= 2 else { return }
        let color = grid[activePath[0]]
        let cleared = loopClosed ? Set(grid.indices.filter { grid[$0] == color }) : Set(activePath)
        score += cleared.count * cleared.count * 5 + (loopClosed ? 100 : 0)
        for i in cleared { grid[i] = 0 }
        activePath = []; loopClosed = false; moves += 1; movesLeft -= 1
        Haptics.move(); SoundFX.play(cleared.count >= 6 ? .clear : .pop)
        collapse()
        if movesLeft == 0 { state = .gameOver(won: true) }
        else if !hasGroups { grid[1] = grid[0] }
    }
    private func collapse() {
        for c in 0..<n {
            var values = (0..<n).map { grid[$0 * n + c] }.filter { $0 > 0 }
            let empty = n - values.count
            values = (0..<empty).map { _ in Int.random(in: 1...colorCount) } + values
            for r in 0..<n { grid[r * n + c] = values[r] }
        }
    }

    // MARK: Flood fill

    var floodRegionSize: Int { grid.isEmpty ? 0 : region(0).count }
    func flood(_ color: Int) {
        guard mode == .floodFill, state == .playing, color != grid[0] else { return }
        let before = region(0).count
        let cells = region(0); for i in cells { grid[i] = color }
        moves += 1; movesLeft -= 1
        let gained = region(0).count - before
        Haptics.tap(); SoundFX.play(gained >= 8 ? .pour : .tap)
        if Set(grid).count == 1 { win(); score += movesLeft * 50 }
        else if movesLeft == 0 { score = region(0).count * 5; state = .gameOver(won: false) }
    }

    // MARK: Laser

    private func updateLaser() {
        var cell = laserSource, dr = 0, dc = 1
        var visited: Set<String> = []; beam = []
        while grid.indices.contains(cell) {
            let key = "\(cell):\(dr):\(dc)"
            guard visited.insert(key).inserted else { break }
            beam.append(cell)
            if cell == laserTarget { break }
            if grid[cell] == 1 { let old = dr; dr = -dc; dc = -old }
            else if grid[cell] == 2 { let old = dr; dr = dc; dc = old }
            let r = cell / n + dr, c = cell % n + dc
            guard (0..<n).contains(r), (0..<n).contains(c) else { break }
            cell = r * n + c
        }
    }

    // MARK: Color lines

    private func moveBall(_ i: Int) {
        if grid[i] > 0 { selected = i; return }
        guard let from = selected else { return }
        var seen: Set<Int> = [from], queue = [from]
        while let p = queue.popLast() {
            for next in neighbors(p) where grid[next] == 0 && seen.insert(next).inserted { queue.append(next) }
        }
        guard seen.contains(i) else { SoundFX.play(.wrong); return }
        grid[i] = grid[from]; grid[from] = 0; selected = nil; moves += 1
        if clearLines() {
            combo += 1
        } else {
            combo = 0
            spawnBalls(3); _ = clearLines()
        }
        if !grid.contains(0) { state = .gameOver(won: false) }
    }
    private func spawnBalls(_ count: Int) {
        let free = grid.indices.filter { grid[$0] == 0 }.shuffled()
        for (k, i) in free.prefix(count).enumerated() { grid[i] = k < nextBalls.count ? nextBalls[k] : Int.random(in: 1...colorCount) }
        nextBalls = (0..<3).map { _ in Int.random(in: 1...colorCount) }
    }
    @discardableResult
    private func clearLines() -> Bool {
        var removed: Set<Int> = []
        for i in grid.indices where grid[i] > 0 {
            for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                var line = [i], r = i / n + dr, c = i % n + dc
                while (0..<n).contains(r), (0..<n).contains(c), grid[r * n + c] == grid[i] {
                    line.append(r * n + c); r += dr; c += dc
                }
                if line.count >= 5 { removed.formUnion(line) }
            }
        }
        guard !removed.isEmpty else { return false }
        for i in removed { grid[i] = 0 }
        // Longer lines and back-to-back clears pay more.
        score += removed.count * 10 + max(0, removed.count - 5) * 20 + combo * 25
        Haptics.success(); SoundFX.play(.clear)
        return true
    }
}

private extension String {
    /// Swift's hashValue changes per launch; levels must stay identical.
    var hashValueStable: Int { unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF } }
}
