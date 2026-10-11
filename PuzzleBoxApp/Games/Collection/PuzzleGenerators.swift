import Foundation

/// Deterministic generator: the same level always produces the same puzzle.
struct PuzzleRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum PuzzleGenerators {
    private static func neighbors(_ i: Int, _ n: Int) -> [Int] {
        var result: [Int] = []
        let r = i / n, c = i % n
        if r > 0 { result.append(i - n) }
        if r < n - 1 { result.append(i + n) }
        if c > 0 { result.append(i - 1) }
        if c < n - 1 { result.append(i + 1) }
        return result
    }

    /// A random Hamiltonian path over an n×n grid, built with "backbite" moves
    /// from a serpentine start. Every cell appears exactly once.
    /// With `fixedStart`, cell 0 stays the first cell and only the tail end moves.
    static func hamiltonianPath(n: Int, fixedStart: Bool = false, random: inout PuzzleRandom) -> [Int] {
        var path = (0..<n).flatMap { r in (0..<n).map { r * n + (r.isMultiple(of: 2) ? $0 : n - 1 - $0) } }
        if fixedStart { path.reverse() } // backbite below always moves path[0], so keep cell 0 at the end
        for _ in 0..<(n * n * 20) {
            if !fixedStart, Bool.random(using: &random) { path.reverse() }
            // Backbite at the head: join it to a grid neighbour further along the path.
            let head = path[0]
            let choices = neighbors(head, n).filter { $0 != path[1] }
            guard let v = choices.randomElement(using: &random), let j = path.firstIndex(of: v) else { continue }
            path = Array(path[0..<j].reversed()) + Array(path[j...])
        }
        if fixedStart { path.reverse() }
        return path
    }

    /// Lights Out board made by pressing random cells, so it is always solvable.
    static func lightsOut(n: Int, presses: Int, random: inout PuzzleRandom) -> [Int] {
        var grid = Array(repeating: 0, count: n * n)
        for i in Array(0..<(n * n)).shuffled(using: &random).prefix(presses) {
            for index in [i] + neighbors(i, n) { grid[index] = 1 - grid[index] }
        }
        if grid.allSatisfy({ $0 == 0 }) { return lightsOut(n: n, presses: presses + 1, random: &random) }
        return grid
    }

    /// A random picture for the nonogram; any grid matching the clues counts as solved.
    static func nonogram(n: Int, random: inout PuzzleRandom) -> [Int] {
        while true {
            let grid = (0..<(n * n)).map { _ in Int.random(in: 0..<100, using: &random) < 58 ? 1 : 0 }
            let rowsOK = (0..<n).allSatisfy { r in (0..<n).contains { grid[r * n + $0] == 1 } }
            let colsOK = (0..<n).allSatisfy { c in (0..<n).contains { grid[$0 * n + c] == 1 } }
            if rowsOK && colsOK { return grid }
        }
    }

    /// Splits a Hamiltonian path into `pairs` segments of at least three cells.
    static func numberConnect(n: Int, pairs: Int, random: inout PuzzleRandom) -> [Int] {
        let path = hamiltonianPath(n: n, random: &random)
        var lengths = Array(repeating: 3, count: pairs)
        for _ in 0..<(n * n - 3 * pairs) { lengths[Int.random(in: 0..<pairs, using: &random)] += 1 }
        var grid = Array(repeating: 0, count: n * n)
        var start = 0
        for (color, length) in lengths.enumerated() {
            grid[path[start]] = color + 1
            grid[path[start + length - 1]] = color + 1
            start += length
        }
        return grid
    }

    /// One closed route through every pipe tile, entering at the top-left from the left
    /// and leaving through the border at the far end. Returns solved masks, end cell and exit bit.
    static func pipes(n: Int, random: inout PuzzleRandom) -> (grid: [Int], end: Int, exit: Int) {
        var path: [Int] = []
        var end = 0
        for attempt in 0..<200 {
            path = hamiltonianPath(n: n, fixedStart: true, random: &random)
            end = path[path.count - 1]
            let r = end / n, c = end % n
            if path[0] == 0, end != 0, r == n - 1 || c == n - 1 || r == 0 || c == 0 { break }
            if attempt == 199 { path = (0..<n).flatMap { r in (0..<n).map { r * n + (r.isMultiple(of: 2) ? $0 : n - 1 - $0) } }; end = path.last! }
        }
        var grid = Array(repeating: 0, count: n * n)
        grid[0] |= 8
        for (a, b) in zip(path, path.dropFirst()) {
            let bit = b == a + 1 ? 2 : b == a - 1 ? 8 : b == a + n ? 4 : 1
            grid[a] |= bit
            grid[b] |= bit == 1 ? 4 : bit == 4 ? 1 : bit == 2 ? 8 : 2
        }
        let r = end / n, c = end % n
        let exit = r == n - 1 ? 4 : c == n - 1 ? 2 : r == 0 ? 1 : 8
        grid[end] |= exit
        return (grid, end, exit)
    }

    /// Beam route with mirrors at each turn. Returns mirror cells (1 = "/", 2 = "\"),
    /// the source cell (fires to the right from column 0) and the target cell.
    static func laser(n: Int, turns: Int, decoys: Int, random: inout PuzzleRandom) -> (grid: [Int], source: Int, target: Int) {
        func freeAhead(_ cell: Int, _ dr: Int, _ dc: Int, _ used: Set<Int>) -> Int {
            var count = 0, r = cell / n + dr, c = cell % n + dc
            while (0..<n).contains(r), (0..<n).contains(c), !used.contains(r * n + c) { count += 1; r += dr; c += dc }
            return count
        }
        for _ in 0..<500 {
            var grid = Array(repeating: 0, count: n * n)
            let source = Int.random(in: 0..<n, using: &random) * n
            var cell = source, dr = 0, dc = 1
            var used: Set<Int> = [cell]
            var ok = true
            for turn in 0...turns {
                let room = freeAhead(cell, dr, dc, used)
                guard room > 0 else { ok = false; break }
                let steps = Int.random(in: 1...room, using: &random)
                for _ in 0..<steps { cell = (cell / n + dr) * n + cell % n + dc; used.insert(cell) }
                guard turn < turns else { break }
                // Turn only where the beam can keep going afterwards.
                let options = [(-dc, dr), (dc, -dr)].filter { freeAhead(cell, $0.0, $0.1, used) > 0 }
                guard let (ndr, ndc) = options.randomElement(using: &random) else { ok = false; break }
                // Mirror 1 maps (dr, dc) → (-dc, -dr); mirror 2 maps (dr, dc) → (dc, dr).
                grid[cell] = (ndr == -dc && ndc == -dr) ? 1 : 2
                dr = ndr; dc = ndc
            }
            guard ok, grid[cell] == 0, cell != source else { continue }
            let free = (0..<(n * n)).filter { !used.contains($0) }.shuffled(using: &random)
            for i in free.prefix(decoys) { grid[i] = Int.random(in: 1...2, using: &random) }
            return (grid, source, cell)
        }
        return (Array(repeating: 0, count: n * n), 0, n - 1)
    }

    // MARK: Rush hour

    /// Breadth-first search over single-step slides; returns the shortest solution length.
    static func rushHourDepth(_ pieces: [SlidingPiece], limit: Int = 25_000) -> Int? {
        func key(_ p: [SlidingPiece]) -> UInt64 { p.reduce(0) { $0 << 3 | UInt64($1.horizontal ? $1.col : $1.row) } }
        var seen: Set<UInt64> = [key(pieces)]
        var frontier = [pieces]
        var depth = 0
        while !frontier.isEmpty, seen.count < limit {
            var next: [[SlidingPiece]] = []
            for state in frontier {
                if state[0].col + state[0].length == 6 { return depth }
                var occupied = Set<Int>()
                for p in state { occupied.formUnion(p.cells) }
                for (index, piece) in state.enumerated() {
                    for delta in [-1, 1] {
                        var moved = piece
                        if piece.horizontal { moved.col += delta } else { moved.row += delta }
                        guard moved.row >= 0, moved.col >= 0,
                              moved.row + (moved.horizontal ? 1 : moved.length) <= 6,
                              moved.col + (moved.horizontal ? moved.length : 1) <= 6 else { continue }
                        let fresh = Set(moved.cells).subtracting(piece.cells)
                        guard fresh.isDisjoint(with: occupied) else { continue }
                        var copy = state; copy[index] = moved
                        if seen.insert(key(copy)).inserted { next.append(copy) }
                    }
                }
            }
            frontier = next
            depth += 1
        }
        return nil
    }

    /// Random solvable rush-hour layout whose shortest solution is as close as possible to `targetDepth`.
    static func rushHour(pieceCount: Int, targetDepth: Int, random: inout PuzzleRandom) -> [SlidingPiece] {
        var best: [SlidingPiece] = []
        var bestDepth = -1
        let deadline = Date().addingTimeInterval(0.25)
        for _ in 0..<60 where Date() < deadline {
            var pieces = [SlidingPiece(id: 0, row: 2, col: Int.random(in: 0...1, using: &random), length: 2, horizontal: true)]
            var occupied = Set(pieces[0].cells)
            var attempts = 0
            while pieces.count < pieceCount, attempts < 200 {
                attempts += 1
                let horizontal = Bool.random(using: &random)
                let length = Int.random(in: 0..<100, using: &random) < 70 ? 2 : 3
                let row = Int.random(in: 0..<(horizontal ? 6 : 7 - length), using: &random)
                let col = Int.random(in: 0..<(horizontal ? 7 - length : 6), using: &random)
                if horizontal && row == 2 { continue } // would wall in the red block
                let piece = SlidingPiece(id: pieces.count, row: row, col: col, length: length, horizontal: horizontal)
                guard Set(piece.cells).isDisjoint(with: occupied) else { continue }
                pieces.append(piece); occupied.formUnion(piece.cells)
            }
            guard let depth = rushHourDepth(pieces, limit: 12_000), depth >= 3 else { continue }
            if abs(depth - targetDepth) < abs(bestDepth - targetDepth) || bestDepth < 0 {
                best = pieces; bestDepth = depth
            }
            if depth >= targetDepth { break }
        }
        return best.isEmpty ? [SlidingPiece(id: 0, row: 2, col: 0, length: 2, horizontal: true),
                               SlidingPiece(id: 1, row: 1, col: 3, length: 3, horizontal: false)] : best
    }

    /// Greedy flood-fill solution length: an upper bound used to set a fair move limit.
    static func floodGreedySteps(_ grid: [Int], n: Int, colors: Int) -> Int {
        var grid = grid
        func region() -> Set<Int> {
            var found: Set<Int> = [], queue = [0]
            let value = grid[0]
            while let i = queue.popLast() {
                guard found.insert(i).inserted else { continue }
                queue += neighbors(i, n).filter { grid[$0] == value && !found.contains($0) }
            }
            return found
        }
        var steps = 0
        while Set(grid).count > 1, steps < 200 {
            let current = region()
            var bestColor = grid[0], bestSize = -1
            for color in 1...colors where color != grid[0] {
                var trial = grid
                for i in current { trial[i] = color }
                let saved = grid; grid = trial
                let size = region().count
                grid = saved
                if size > bestSize { bestSize = size; bestColor = color }
            }
            for i in current { grid[i] = bestColor }
            steps += 1
        }
        return steps
    }

    /// One-line puzzle: a random trail over a node lattice; the trail itself is an Euler path.
    static func oneLine(size: Int, edgeCount: Int, random: inout PuzzleRandom) -> (nodes: [Int], edges: [[Int]]) {
        let n = size
        func adjacent(_ i: Int) -> [Int] {
            var result: [Int] = []
            let r = i / n, c = i % n
            for dr in -1...1 { for dc in -1...1 where dr != 0 || dc != 0 {
                let nr = r + dr, nc = c + dc
                if (0..<n).contains(nr), (0..<n).contains(nc) { result.append(nr * n + nc) }
            } }
            return result
        }
        var best: [[Int]] = []
        for _ in 0..<300 {
            var current = Int.random(in: 0..<(n * n), using: &random)
            var edges: [[Int]] = []
            var used = Set<[Int]>()
            while edges.count < edgeCount {
                // Avoid diagonals that would cross an existing diagonal in the same square.
                let options = adjacent(current).filter { next in
                    let e = [min(current, next), max(current, next)]
                    guard !used.contains(e) else { return false }
                    let dr = next / n - current / n, dc = next % n - current % n
                    if dr != 0 && dc != 0 {
                        let a = current + dc, b = current + dr * n
                        if used.contains([min(a, b), max(a, b)]) { return false }
                    }
                    return true
                }
                guard let next = options.randomElement(using: &random) else { break }
                let e = [min(current, next), max(current, next)]
                used.insert(e); edges.append([current, next]); current = next
            }
            if edges.count > best.count { best = edges }
            if edges.count == edgeCount { break }
        }
        let nodes = Array(Set(best.flatMap { $0 })).sorted()
        return (nodes, best.shuffled(using: &random))
    }
}
