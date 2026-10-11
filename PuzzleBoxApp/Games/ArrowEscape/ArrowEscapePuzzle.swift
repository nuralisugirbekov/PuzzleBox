import Foundation

struct EscapeCell: Hashable {
    let x: Int
    let y: Int
    func offset(_ direction: EscapeDirection) -> Self {
        Self(x: x + direction.dx, y: y + direction.dy)
    }
}

enum EscapeDirection: CaseIterable {
    case up, right, down, left
    var dx: Int { self == .right ? 1 : self == .left ? -1 : 0 }
    var dy: Int { self == .down ? 1 : self == .up ? -1 : 0 }
    var opposite: Self {
        switch self { case .up: .down; case .down: .up; case .left: .right; case .right: .left }
    }
}

struct EscapeArrow: Identifiable {
    let id: Int
    /// Ordered from tail to head. Single-cell arrows fill residual pockets.
    let cells: [EscapeCell]
    let direction: EscapeDirection
    var head: EscapeCell { cells[cells.count - 1] }
}

struct ArrowEscapePuzzle {
    static let levelCount = 100
    let columns: Int
    let rows: Int
    let arrows: [EscapeArrow]
    /// Construction removes arrows in this order; it is a guaranteed solution.
    let solution: [Int]

    func contains(_ cell: EscapeCell) -> Bool {
        (0..<columns).contains(cell.x) && (0..<rows).contains(cell.y)
    }

    func canRemove(_ arrow: EscapeArrow, occupancy: [EscapeCell: Int]) -> Bool {
        var cell = arrow.head.offset(arrow.direction)
        while contains(cell) {
            if let owner = occupancy[cell], owner != arrow.id { return false }
            cell = cell.offset(arrow.direction)
        }
        return true
    }

    static func make(level: Int) -> Self {
        let index = min(levelCount - 1, max(0, level))
        // Sized so the whole board fits on a phone screen without zooming.
        let columns = 8 + index * 8 / 99
        let rows = 11 + index * 11 / 99
        var random = EscapeRandom(state: UInt64(index + 1) &* 0x9E3779B97F4A7C15)
        var remaining = Set((0..<rows).flatMap { y in (0..<columns).map { EscapeCell(x: $0, y: y) } })
        var arrows: [EscapeArrow] = []
        var owners: [EscapeCell: Int] = [:]
        var depths: [Int] = []
        // Percentage of picks that chase the deepest blocking chain.
        let pickiness = 70 + index * 25 / 99
        while !remaining.isEmpty {
            // Only row/column extrema can see an edge. This avoids ray-casting
            // from every candidate and guarantees at least one valid candidate.
            var candidates: [(EscapeCell, EscapeDirection)] = []
            for y in 0..<rows {
                let xs = (0..<columns).filter { remaining.contains(EscapeCell(x: $0, y: y)) }
                if let first = xs.first, let last = xs.last {
                    candidates.append((EscapeCell(x: first, y: y), .left))
                    candidates.append((EscapeCell(x: last, y: y), .right))
                }
            }
            for x in 0..<columns {
                let ys = (0..<rows).filter { remaining.contains(EscapeCell(x: x, y: $0)) }
                if let first = ys.first, let last = ys.last {
                    candidates.append((EscapeCell(x: x, y: first), .up))
                    candidates.append((EscapeCell(x: x, y: last), .down))
                }
            }
            let longer = candidates.filter { remaining.contains($0.0.offset($0.1.opposite)) }
            let pool = longer.isEmpty ? candidates : longer
            // Difficulty: prefer heads whose exit ray is blocked by the deepest
            // chain of earlier arrows, so few arrows are free at any moment.
            let scored = pool.map { candidate -> (EscapeCell, EscapeDirection, Int, Int) in
                var cell = candidate.0.offset(candidate.1)
                var depth = 0, blockers = Set<Int>()
                while (0..<columns).contains(cell.x) && (0..<rows).contains(cell.y) {
                    if let owner = owners[cell] { blockers.insert(owner); depth = max(depth, depths[owner]) }
                    cell = cell.offset(candidate.1)
                }
                return (candidate.0, candidate.1, depth + 1, blockers.count)
            }
            let bestDepth = scored.map(\.2).max() ?? 1
            let greedy = random.index(100) < pickiness
            let best = scored.filter { !greedy || $0.2 >= bestDepth - 1 }
            let mostBlocked = best.map(\.3).max() ?? 0
            let finalists = best.filter { !greedy || $0.3 >= mostBlocked - 1 }
            let choice = finalists[random.index(finalists.count)]
            let (head, direction) = (choice.0, choice.1)
            var path = [head]
            remaining.remove(head)
            let targetLength = 3 + index / 25 + random.index(5)
            var backwards = direction.opposite
            while path.count < targetLength {
                let end = path[path.count - 1]
                let options = (path.count == 1 ? [backwards] : EscapeDirection.allCases)
                    .filter { remaining.contains(end.offset($0)) }
                guard !options.isEmpty else { break }
                let bends = options.filter { $0 != backwards }
                let choices = !bends.isEmpty && random.index(100) < 65 ? bends : options
                backwards = choices[random.index(choices.count)]
                let next = end.offset(backwards)
                path.append(next)
                remaining.remove(next)
            }
            for cell in path { owners[cell] = arrows.count }
            depths.append(choice.2)
            arrows.append(EscapeArrow(id: arrows.count, cells: Array(path.reversed()), direction: direction))
        }
        return Self(columns: columns, rows: rows, arrows: arrows, solution: arrows.map(\.id))
    }
}

/// Stable integer PRNG: a level is identical across launches and devices.
private struct EscapeRandom {
    var state: UInt64
    mutating func index(_ upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 32) % UInt64(upperBound))
    }
}
