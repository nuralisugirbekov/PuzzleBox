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
    /// The board's outline: every cell that holds an arrow. Cells outside it
    /// are holes that arrows fly straight over.
    var shape: EscapeShape = .rectangle
    var playable: Set<EscapeCell> = []

    /// Cells holding an arrow, for a board built by hand without a shape.
    var cellCount: Int { playable.isEmpty ? columns * rows : playable.count }

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

    /// The board grows every `growthEvery` levels, from 8×11 (fits a phone at
    /// a glance) to 46×68 at level 100, where the player zooms in to read it.
    static let growthEvery = 5

    static func size(level index: Int) -> (columns: Int, rows: Int) {
        let step = min(levelCount - 1, max(0, index)) / growthEvery
        return (8 + step * 2, 11 + step * 3)
    }

    static func make(level: Int) -> Self {
        let index = min(levelCount - 1, max(0, level))
        return make(index: index, attempt: 0)
    }

    private static func make(index: Int, attempt: Int) -> Self {
        let shape = EscapeShape.forLevel(index)
        let (columns, rows, cells) = shape.cells(fitting: size(level: index))
        var random = EscapeRandom(state: (UInt64(index + 1) &+ UInt64(attempt) &* 7919) &* 0x9E3779B97F4A7C15)
        var remaining = cells
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
            var longer = candidates.filter { remaining.contains($0.0.offset($0.1.opposite)) }
            if longer.isEmpty {
                // No row or column end has room behind it. Any free cell will do
                // whose way to the edge is clear and that has a free cell behind,
                // so the arrow gets at least two cells.
                longer = remaining.flatMap { cell in
                    EscapeDirection.allCases.compactMap { direction -> (EscapeCell, EscapeDirection)? in
                        guard remaining.contains(cell.offset(direction.opposite)) else { return nil }
                        var ray = cell.offset(direction)
                        while (0..<columns).contains(ray.x) && (0..<rows).contains(ray.y) {
                            if remaining.contains(ray) { return nil }
                            ray = ray.offset(direction)
                        }
                        return (cell, direction)
                    }
                }.sorted { ($0.0.y, $0.0.x) < ($1.0.y, $1.0.x) }
            }
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
                // A neighbour with no other free neighbour would be left as a
                // one-cell arrow later, so the path takes it now.
                let lonely = options.filter { freeNeighbours(end.offset($0), remaining) == 0 }
                let bends = options.filter { $0 != backwards }
                let choices = !lonely.isEmpty ? lonely
                    : !bends.isEmpty && random.index(100) < 65 ? bends : options
                backwards = choices[random.index(choices.count)]
                let next = end.offset(backwards)
                path.append(next)
                remaining.remove(next)
            }
            // Past its length the path still takes stranded cells at its end.
            while path.count < targetLength + 4 {
                let end = path[path.count - 1]
                // A one-cell path may only grow straight back from its tip.
                let ways = path.count == 1 ? [direction.opposite] : EscapeDirection.allCases
                guard let stray = ways.first(where: {
                    remaining.contains(end.offset($0)) && freeNeighbours(end.offset($0), remaining) == 0
                }) else { break }
                path.append(end.offset(stray))
                remaining.remove(end.offset(stray))
            }
            for cell in path { owners[cell] = arrows.count }
            depths.append(choice.2)
            arrows.append(EscapeArrow(id: arrows.count, cells: Array(path.reversed()), direction: direction))
        }
        // The odd single that can't be joined to anything becomes an empty
        // cell: taking an arrow away never blocks another.
        let merged = absorbSingles(arrows, columns: columns, rows: rows)
        let kept = merged.filter { $0.cells.count > 1 }.enumerated().map { number, arrow in
            EscapeArrow(id: number, cells: arrow.cells, direction: arrow.direction)
        }
        let dropped = Set(merged.filter { $0.cells.count == 1 }.map(\.head))
        return Self(columns: columns, rows: rows, arrows: kept, solution: kept.map(\.id),
                    shape: shape, playable: cells.subtracting(dropped))
    }

    private static func freeNeighbours(_ cell: EscapeCell, _ remaining: Set<EscapeCell>) -> Int {
        EscapeDirection.allCases.filter { remaining.contains(cell.offset($0)) }.count
    }

    /// One-cell arrows read as stray marks, so each is joined to a neighbour:
    /// added to the tail or the tip of an adjacent arrow, or grown backwards
    /// with a cell taken from a neighbour's tail. A change is kept only if the
    /// board still clears in order. Arrows are renumbered in their removal order.
    private static func absorbSingles(_ arrows: [EscapeArrow], columns: Int, rows: Int) -> [EscapeArrow] {
        var list: [EscapeArrow?] = arrows
        func owners() -> [EscapeCell: Int] {
            var map: [EscapeCell: Int] = [:]
            for case let arrow? in list { for cell in arrow.cells { map[cell] = arrow.id } }
            return map
        }
        func solvable(_ candidate: [EscapeArrow?]) -> Bool {
            clearingOrder(candidate.compactMap { $0 }, columns: columns, rows: rows) != nil
        }

        // Each fix can open a way for another, so sweep a few times.
        for _ in 0..<3 {
        for index in list.indices {
            guard let single = list[index], single.cells.count == 1 else { continue }
            let cell = single.head
            let map = owners()
            var options: [[EscapeArrow?]] = []
            for direction in EscapeDirection.allCases {
                let neighbour = cell.offset(direction)
                guard let id = map[neighbour], id != single.id, let other = list[id] else { continue }
                if other.cells[0] == neighbour, other.cells.count >= 2 {
                    // The single cell becomes the neighbour's new tail.
                    var option = list
                    option[id] = EscapeArrow(id: id, cells: [cell] + other.cells, direction: other.direction)
                    option[index] = nil
                    options.append(option)
                }
                if other.head == neighbour, neighbour.offset(other.direction) == cell {
                    // The neighbour's tip moves forward onto the single cell.
                    var option = list
                    option[id] = EscapeArrow(id: id, cells: other.cells + [cell], direction: other.direction)
                    option[index] = nil
                    options.append(option)
                }
                if other.cells[0] == neighbour, other.cells.count >= 3,
                   neighbour == cell.offset(single.direction.opposite) {
                    // The single arrow grows a tail out of the neighbour's.
                    var option = list
                    option[index] = EscapeArrow(id: single.id, cells: [neighbour, cell], direction: single.direction)
                    option[id] = EscapeArrow(id: id, cells: Array(other.cells.dropFirst()), direction: other.direction)
                    options.append(option)
                }
            }
            // Or cut a neighbour in two beside the single cell: its tail end plus
            // the single cell make one new arrow, its head end stays as it was.
            for direction in EscapeDirection.allCases {
                let neighbour = cell.offset(direction)
                guard let id = map[neighbour], id != single.id, let other = list[id],
                      let k = other.cells.firstIndex(of: neighbour), other.cells.count - k - 1 >= 2 else { continue }
                let tail = EscapeArrow(id: 0, cells: Array(other.cells[...k]) + [cell], direction: direction.opposite)
                let head = EscapeArrow(id: 0, cells: Array(other.cells[(k + 1)...]), direction: other.direction)
                for (early, late) in [(head, tail), (tail, head)] {
                    var option = list
                    option[id] = EscapeArrow(id: id, cells: early.cells, direction: early.direction)
                    option[index] = EscapeArrow(id: single.id, cells: late.cells, direction: late.direction)
                    options.append(option)
                }
            }
            // Or cut just before the cell beside it: the single cell leads the
            // head end as its new tail, and the tail end gets its own tip.
            for direction in EscapeDirection.allCases {
                let neighbour = cell.offset(direction)
                guard let id = map[neighbour], id != single.id, let other = list[id],
                      let k = other.cells.firstIndex(of: neighbour), k >= 2, k <= other.cells.count - 2 else { continue }
                let front = EscapeArrow(id: 0, cells: [cell] + Array(other.cells[k...]), direction: other.direction)
                let back = Array(other.cells[..<k])
                let backWay = EscapeDirection.allCases.first { back[back.count - 2].offset($0) == back[back.count - 1] }!
                let rear = EscapeArrow(id: 0, cells: back, direction: backWay)
                for (early, late) in [(front, rear), (rear, front)] {
                    var option = list
                    option[id] = EscapeArrow(id: id, cells: early.cells, direction: early.direction)
                    option[index] = EscapeArrow(id: single.id, cells: late.cells, direction: late.direction)
                    options.append(option)
                }
            }
            // Two neighbouring singles become one two-cell arrow, either way round.
            for direction in EscapeDirection.allCases {
                let neighbour = cell.offset(direction)
                guard let id = map[neighbour], id != single.id, let other = list[id], other.cells.count == 1 else { continue }
                for (from, to, way) in [(neighbour, cell, direction.opposite), (cell, neighbour, direction)] {
                    var option = list
                    option[index] = EscapeArrow(id: single.id, cells: [from, to], direction: way)
                    option[id] = nil
                    options.append(option)
                }
            }
            if let fixed = options.first(where: solvable) { list = fixed }
        }
        }
        // Renumber in an order that clears the board.
        let kept = list.compactMap { $0 }
        let order = clearingOrder(kept, columns: columns, rows: rows) ?? kept.indices.map { $0 }
        return order.enumerated().map { number, index in
            EscapeArrow(id: number, cells: kept[index].cells, direction: kept[index].direction)
        }
    }

    /// Positions in `arrows` in an order that clears the whole board, or nil.
    /// Removing an arrow never blocks another, so taking every free arrow
    /// in sweeps finds an order whenever one exists.
    private static func clearingOrder(_ arrows: [EscapeArrow], columns: Int, rows: Int) -> [Int]? {
        // A flat grid of owners, -1 for empty: this runs for every candidate fix.
        var grid = [Int](repeating: -1, count: columns * rows)
        for (index, arrow) in arrows.enumerated() {
            for cell in arrow.cells { grid[cell.y * columns + cell.x] = index }
        }
        func free(_ index: Int) -> Bool {
            let arrow = arrows[index]
            let dx = arrow.direction.dx, dy = arrow.direction.dy
            var x = arrow.head.x + dx, y = arrow.head.y + dy
            while x >= 0 && x < columns && y >= 0 && y < rows {
                let owner = grid[y * columns + x]
                if owner >= 0 && owner != index { return false }
                x += dx
                y += dy
            }
            return true
        }
        var left = Array(arrows.indices)
        var order: [Int] = []
        order.reserveCapacity(arrows.count)
        while !left.isEmpty {
            var stuck: [Int] = []
            for index in left {
                if free(index) {
                    order.append(index)
                    for cell in arrows[index].cells { grid[cell.y * columns + cell.x] = -1 }
                } else {
                    stuck.append(index)
                }
            }
            if stuck.count == left.count { return nil }
            left = stuck
        }
        return order
    }
}

/// Outlines for the board. Shapes are drawn on a square grid as big as the
/// level's board, then trimmed to the rows and columns they use.
enum EscapeShape: String, CaseIterable {
    case rectangle, heart, circle, house, flower, diamond, ring, plus, hourglass, tree, star, butterfly

    /// The first level is a plain rectangle; after that the outlines take turns.
    static func forLevel(_ index: Int) -> Self {
        index == 0 ? .rectangle : allCases[index % allCases.count]
    }

    /// The shape's cells, with the board's width and height after trimming.
    func cells(fitting size: (columns: Int, rows: Int)) -> (columns: Int, rows: Int, cells: Set<EscapeCell>) {
        if self == .rectangle {
            let all = Set((0..<size.rows).flatMap { y in (0..<size.columns).map { EscapeCell(x: $0, y: y) } })
            return (size.columns, size.rows, all)
        }
        // A square a little bigger than the rectangle's long side keeps the
        // arrow count close to a rectangle's, since a shape leaves corners empty.
        let side = max(size.columns, size.rows) + 2
        var inside: [EscapeCell] = []
        for y in 0..<side {
            for x in 0..<side {
                // -1…1 across the square, y pointing down.
                let u = (Double(x) + 0.5) / Double(side) * 2 - 1
                let v = (Double(y) + 0.5) / Double(side) * 2 - 1
                if contains(u: u, v: v) { inside.append(EscapeCell(x: x, y: y)) }
            }
        }
        let minX = inside.map(\.x).min() ?? 0, minY = inside.map(\.y).min() ?? 0
        let maxX = inside.map(\.x).max() ?? 0, maxY = inside.map(\.y).max() ?? 0
        let cells = Set(inside.map { EscapeCell(x: $0.x - minX, y: $0.y - minY) })
        return (maxX - minX + 1, maxY - minY + 1, cells)
    }

    private func contains(u: Double, v: Double) -> Bool {
        let r = hypot(u, v)
        let angle = atan2(v, u)
        switch self {
        case .rectangle:
            return true
        case .circle:
            return r <= 1
        case .ring:
            return r <= 1 && r >= 0.42
        case .diamond:
            return abs(u) + abs(v) <= 1.02
        case .plus:
            return (abs(u) <= 0.36 || abs(v) <= 0.36) && max(abs(u), abs(v)) <= 1
        case .hourglass:
            return abs(v) <= 0.95 && abs(u) <= 0.22 + 0.78 * abs(v)
        case .heart:
            // The classic implicit heart, point down.
            let x = u * 1.25, y = -v * 1.25 + 0.3
            let a = x * x + y * y - 1
            return a * a * a - x * x * y * y * y <= 0
        case .house:
            // A roof over a body, with a doorway cut out of the bottom.
            let roof = v < -0.15 && abs(u) <= (v + 1) / 0.85
            let body = v >= -0.15 && abs(u) <= 0.72
            let door = v > 0.42 && abs(u) < 0.17
            return (roof || body) && !door
        case .flower:
            // Five round petals around a round centre, with gaps between the petals.
            let petals = (0..<5).contains { k in
                let a = -Double.pi / 2 + Double(k) * 2 * .pi / 5
                return hypot(u - 0.64 * cos(a), v - 0.64 * sin(a)) <= 0.32
            }
            return r <= 0.3 || petals
        case .star:
            // Five points, the top one straight up.
            let corners = (0..<10).map { k -> (Double, Double) in
                let a = -Double.pi / 2 + Double(k) * .pi / 5
                let radius = k.isMultiple(of: 2) ? 1.0 : 0.45
                return (radius * cos(a), radius * sin(a) + 0.08)
            }
            return Self.polygon(corners, contains: (u, v))
        case .tree:
            // Three stacked tiers and a trunk.
            let tiers = [(-1.0, -0.35, 0.55), (-0.55, 0.15, 0.78), (-0.1, 0.6, 1.0)]
            let crown = tiers.contains { top, bottom, half in
                v >= top && v <= bottom && abs(u) <= half * (v - top) / (bottom - top) + 0.08
            }
            return crown || (v > 0.6 && abs(u) <= 0.2)
        case .butterfly:
            // Big upper wings, small lower wings and a slim body, with gaps between them.
            let x = abs(u)
            let upper = x > 0.2 && hypot((x - 0.55) / 0.45, (v + 0.3) / 0.55) <= 1
            let lower = x > 0.2 && hypot((x - 0.42) / 0.3, (v - 0.48) / 0.36) <= 1
            let body = x <= 0.08 && abs(v) <= 0.75
            return upper || lower || body
        }
    }

    /// Even-odd test for a point inside a polygon.
    private static func polygon(_ corners: [(Double, Double)], contains point: (Double, Double)) -> Bool {
        var inside = false
        var j = corners.count - 1
        for i in corners.indices {
            let (xi, yi) = corners[i], (xj, yj) = corners[j]
            if (yi > point.1) != (yj > point.1),
               point.0 < (xj - xi) * (point.1 - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
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
