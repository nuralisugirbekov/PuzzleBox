import SwiftUI
import Observation

enum PuzzleMode: String {
    case lightsOut, nonogram, numberConnect, oneLine, unblock, parkingJam, fifteenPuzzle, pipeConnect, dots, sameGame, floodFill, laser, balanceScale, colorLines
    var id: GameID {
        switch self {
        case .lightsOut: .lightsOut
        case .nonogram: .nonogram
        case .numberConnect: .numberConnect
        case .oneLine: .oneLine
        case .unblock: .unblock
        case .parkingJam: .parkingJam
        case .fifteenPuzzle: .fifteenPuzzle
        case .pipeConnect: .pipeConnect
        case .dots: .dots
        case .sameGame: .sameGame
        case .floodFill: .floodFill
        case .laser: .laser
        case .balanceScale: .balanceScale
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
        case .parkingJam: "Move cars along their lanes. Drive the red car out."
        case .fifteenPuzzle: "Slide tiles into order, with the empty cell last."
        case .pipeConnect: "Rotate pipes to connect IN to OUT through every cell."
        case .dots: "Connect adjacent matching dots, then release or tap Collect."
        case .sameGame: "Remove groups of at least two matching blocks."
        case .floodFill: "Choose colors to fill the board from the top-left corner."
        case .laser: "Rotate mirrors to guide the beam from the arrow to the star."
        case .balanceScale: "Find the heavier item in two weighings. Compare equal groups."
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
    private(set) var weighing = ""
    private(set) var weighings = 0
    var guessing = false
    private var heavy = 0
    private var history: [([Int], Int)] = []
    let nodes = [6, 8, 5, 3, 1]
    let edges = [[6, 8], [8, 5], [5, 3], [3, 6], [3, 1], [1, 5], [6, 5], [8, 3]]

    init(mode: PuzzleMode) { self.mode = mode; restart() }
    var canUndo: Bool { state == .playing && (!history.isEmpty || !activePath.isEmpty || !paths.isEmpty) }
    private func adjacent(_ a: Int, _ b: Int) -> Bool { abs(a / n - b / n) + abs(a % n - b % n) == 1 }
    private func neighbors(_ i: Int) -> [Int] { [i - n, i + n, i - 1, i + 1].filter { grid.indices.contains($0) && adjacent(i, $0) } }
    private func win() { score = max(score, max(100, 1000 - moves * 10)); state = .gameOver(won: true); Haptics.success() }
    private func save() { history.append((grid, score)) }
    func restart() {
        state = .playing; score = 0; moves = 0; selected = nil; marks = []; markMode = false
        paths = [:]; activePath = []; pieces = []; beam = []; weighing = ""; weighings = 0; guessing = false; history = []
        n = 5; movesLeft = 25; grid = Array(repeating: 0, count: 25); target = []
        switch mode {
        case .lightsOut:
            repeat {
                grid = Array(repeating: 0, count: 25)
                for i in Array(0..<25).shuffled().prefix(12) { toggle(i) }
            } while grid.allSatisfy { $0 == 0 }
        case .nonogram:
            // Full rows/columns make each of these small starter pictures unambiguous.
            let patterns = [
                [1,1,1,1,1, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 1,1,1,1,1],
                [1,0,0,0,1, 1,0,0,0,1, 1,1,1,1,1, 1,0,0,0,1, 1,0,0,0,1],
                [1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,0, 1,1,1,1,1],
                [1,1,1,1,1, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 1,1,1,1,1]
            ]
            target = patterns.randomElement()!
        case .numberConnect:
            var route = (0..<5).flatMap { r in (0..<5).map { r * 5 + (r.isMultiple(of: 2) ? $0 : 4 - $0) } }
            let rotation = Int.random(in: 0..<4)
            route = route.map { index in var r = index / 5, c = index % 5; for _ in 0..<rotation { let old = r; r = c; c = 4 - old }; return r * 5 + c }
            var start = 0
            for (color, count) in [7, 6, 7, 5].enumerated() {
                let segment = Array(route[start..<(start + count)])
                grid[segment.first!] = color + 1; grid[segment.last!] = color + 1; start += count
            }
        case .oneLine: n = 3; grid = Array(repeating: 0, count: 9)
        case .unblock, .parkingJam:
            n = 6; grid = Array(repeating: 0, count: 36)
            if mode == .unblock {
                pieces = [SlidingPiece(id: 0, row: 2, col: 0, length: 2, horizontal: true),
                          SlidingPiece(id: 1, row: 1, col: 2, length: 2, horizontal: false),
                          SlidingPiece(id: 2, row: 2, col: 4, length: 2, horizontal: false),
                          SlidingPiece(id: 3, row: 0, col: 3, length: 2, horizontal: true),
                          SlidingPiece(id: 4, row: 4, col: 0, length: 3, horizontal: true),
                          SlidingPiece(id: 5, row: 5, col: 3, length: 3, horizontal: true)]
            } else {
                pieces = [SlidingPiece(id: 0, row: 2, col: 1, length: 2, horizontal: true),
                          SlidingPiece(id: 1, row: 0, col: 3, length: 3, horizontal: false),
                          SlidingPiece(id: 2, row: 1, col: 5, length: 2, horizontal: false),
                          SlidingPiece(id: 3, row: 0, col: 0, length: 2, horizontal: false),
                          SlidingPiece(id: 4, row: 4, col: 0, length: 3, horizontal: true)]
            }
        case .fifteenPuzzle:
            n = 4; grid = Array(1...15) + [0]; target = grid
            var last = -1
            for _ in 0..<160 {
                let empty = grid.firstIndex(of: 0)!, choices = neighbors(empty).filter { $0 != last }
                let source = choices.randomElement()!; grid.swapAt(source, empty); last = empty
            }
            if grid == target { grid.swapAt(14, 15) }
        case .pipeConnect:
            n = 4; grid = Array(repeating: 0, count: 16)
            let route = (0..<4).flatMap { r in (0..<4).map { r * 4 + (r.isMultiple(of: 2) ? $0 : 3 - $0) } }
            grid[0] = 8; grid[12] = 4
            for (a, b) in zip(route, route.dropFirst()) {
                let bit = b == a + 1 ? 2 : b == a - 1 ? 8 : 4
                grid[a] |= bit; grid[b] |= opposite(bit)
            }
            target = grid
            for i in grid.indices { for _ in 0..<Int.random(in: 0..<4) { grid[i] = rotate(grid[i]) } }
            // Keep the entrance disconnected at the start, without changing solvability.
            while grid[0] & 8 != 0 { grid[0] = rotate(grid[0]) }
            updatePipes()
        case .dots, .sameGame:
            n = 6; grid = (0..<36).map { _ in Int.random(in: 1...4) }; movesLeft = 20
            grid[1] = grid[0] // At least one opening move.
        case .floodFill:
            n = 8; grid = (0..<64).map { _ in Int.random(in: 1...5) }; movesLeft = 30
        case .laser:
            n = 5; grid = Array(repeating: 0, count: 25)
            // Known beam: 10→11→12→7→2→3→4→9→14→19→18→17→16→15.
            for i in [12, 2, 4, 19] { grid[i] = Int.random(in: 1...2) }
            updateLaser()
            if beam.last == 15 { grid[12] = 3 - grid[12]; updateLaser() }
        case .balanceScale:
            n = 3; grid = Array(repeating: 0, count: 9); heavy = Int.random(in: 0..<9)
        case .colorLines:
            n = 9; grid = Array(repeating: 0, count: 81); spawnBalls(5)
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
            moves += 1; if grid == target { win() }
        case .numberConnect: connect(i)
        case .oneLine: trace(i)
        case .unblock, .parkingJam: selected = pieces.firstIndex { $0.cells.contains(i) }
        case .fifteenPuzzle:
            if let empty = grid.firstIndex(of: 0), adjacent(i, empty) {
                save(); grid.swapAt(i, empty); moves += 1; if grid == target { win() }
            }
        case .pipeConnect:
            save(); grid[i] = rotate(grid[i]); moves += 1; updatePipes()
        case .dots:
            if activePath.isEmpty { activePath = [i] }
            else if activePath.last == i { return }
            else if activePath.count > 1, activePath[activePath.count - 2] == i { activePath.removeLast() }
            else if grid[i] == grid[activePath[0]], adjacent(activePath.last!, i), !activePath.contains(i) { activePath.append(i) }
            else { activePath = [i] }
        case .sameGame:
            guard grid[i] > 0 else { return }
            let group = region(i)
            if group.count > 1 {
                save(); for cell in group { grid[cell] = 0 }; score += group.count * group.count * 5; moves += 1
                collapse(refill: false)
                if grid.allSatisfy({ $0 == 0 }) { score += 500; state = .gameOver(won: true) }
                else if !hasGroups { state = .gameOver(won: false) }
            }
        case .floodFill: break // Color buttons are the controls for this mode.
        case .laser:
            guard grid[i] > 0 else { return }; save(); grid[i] = 3 - grid[i]; moves += 1; updateLaser()
            if beam.last == 15 { win() }
        case .balanceScale:
            if guessing {
                if i == heavy { score = max(100, 1000 - weighings * 200); state = .gameOver(won: true) }
                else { state = .gameOver(won: false) }
            } else { grid[i] = (grid[i] + 1) % 3 }
        case .colorLines: moveBall(i)
        }
        Haptics.tap()
    }
    private func toggle(_ i: Int) { for index in [i] + neighbors(i) { grid[index] = 1 - grid[index] } }
    func undo() {
        guard state == .playing else { return }
        if mode == .numberConnect { paths = [:]; activePath = []; selected = nil; return }
        if mode == .oneLine || mode == .dots { if !activePath.isEmpty { activePath.removeLast() }; return }
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
                    let complete = paths.values.filter { $0.count > 1 && grid[$0.first!] == grid[$0.last!] }.count
                    if complete == 4, Set(paths.values.flatMap { $0 }).count == 25 { win() }
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
        pieces[index] = piece; moves += 1; Haptics.move()
        if piece.id == 0, piece.col + piece.length == 6 { win() }
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
        if reached.count == grid.count, grid[12] & 4 != 0 { win() }
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
    private var hasGroups: Bool { grid.indices.contains { i in grid[i] > 0 && neighbors(i).contains { grid[$0] == grid[i] } } }
    func collectDots() {
        guard state == .playing, mode == .dots, activePath.count >= 2 else { return }
        score += activePath.count * activePath.count * 5
        for i in activePath { grid[i] = 0 }; activePath = []; moves += 1; movesLeft -= 1
        collapse(refill: true)
        if movesLeft == 0 { state = .gameOver(won: true) }
        else if !hasGroups { grid[1] = grid[0] }
    }
    private func collapse(refill: Bool) {
        for c in 0..<n {
            var values = (0..<n).map { grid[$0 * n + c] }.filter { $0 > 0 }
            let empty = n - values.count
            values = (0..<empty).map { _ in refill ? Int.random(in: 1...4) : 0 } + values
            for r in 0..<n { grid[r * n + c] = values[r] }
        }
        if !refill {
            let columns = (0..<n).filter { c in (0..<n).contains { grid[$0 * n + c] > 0 } }
                .map { c in (0..<n).map { grid[$0 * n + c] } }
            grid = Array(repeating: 0, count: n * n)
            for (c, values) in columns.enumerated() { for r in 0..<n { grid[r * n + c] = values[r] } }
        }
    }
    func flood(_ color: Int) {
        guard mode == .floodFill, state == .playing, color != grid[0] else { return }
        let cells = region(0); for i in cells { grid[i] = color }
        moves += 1; movesLeft -= 1; score = region(0).count * 10
        if Set(grid).count == 1 { score += movesLeft * 20; state = .gameOver(won: true) }
        else if movesLeft == 0 { state = .gameOver(won: false) }
    }
    private func updateLaser() {
        var cell = 10, dr = 0, dc = 1
        var visited: Set<String> = []; beam = []
        while grid.indices.contains(cell) {
            let key = "\(cell):\(dr):\(dc)"
            guard visited.insert(key).inserted else { break }
            beam.append(cell)
            if cell == 15 { break }
            if grid[cell] == 1 { let old = dr; dr = -dc; dc = -old }
            else if grid[cell] == 2 { let old = dr; dr = dc; dc = old }
            let r = cell / n + dr, c = cell % n + dc
            guard (0..<n).contains(r), (0..<n).contains(c) else { break }
            cell = r * n + c
        }
    }
    func weigh() {
        guard state == .playing, mode == .balanceScale, weighings < 2 else { return }
        let left = grid.indices.filter { grid[$0] == 1 }, right = grid.indices.filter { grid[$0] == 2 }
        guard !left.isEmpty, left.count == right.count else { weighing = "Choose equal groups on both sides."; return }
        weighings += 1
        weighing = left.contains(heavy) ? "Left side is heavier" : right.contains(heavy) ? "Right side is heavier" : "Both sides balance"
        if weighings == 2 { guessing = true }
    }
    private func moveBall(_ i: Int) {
        if grid[i] > 0 { selected = i; return }
        guard let from = selected else { return }
        var seen: Set<Int> = [from], queue = [from]
        while let p = queue.popLast() {
            for next in neighbors(p) where grid[next] == 0 && seen.insert(next).inserted { queue.append(next) }
        }
        guard seen.contains(i) else { return }
        grid[i] = grid[from]; grid[from] = 0; selected = nil; moves += 1
        if !clearLines() { spawnBalls(3); _ = clearLines() }
        if !grid.contains(0) { state = .gameOver(won: false) }
    }
    private func spawnBalls(_ count: Int) {
        for i in grid.indices.filter({ grid[$0] == 0 }).shuffled().prefix(count) { grid[i] = Int.random(in: 1...5) }
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
        for i in removed { grid[i] = 0 }; score += removed.count * 10
        return !removed.isEmpty
    }
}
