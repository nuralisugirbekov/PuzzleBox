import CoreGraphics

// MARK: - Pieces

/// A side of the lot.
enum CarParkSide: Int, Codable, CaseIterable {
    case top, right, bottom, left
}

/// One cell-wide stretch of the lot's edge: `index` is the column for the top
/// and bottom sides and the row for the left and right sides.
struct CarParkEdge: Hashable, Codable {
    let side: CarParkSide
    let index: Int
}

/// What a vehicle looks like; the length follows from it.
enum CarParkKind: Int, Codable {
    case car, taxi, van, truck, bus

    var length: Int { self == .truck || self == .bus ? 3 : 2 }
}

struct CarParkVehicle: Identifiable, Hashable, Codable {
    let id: Int
    /// Top-left cell.
    var row: Int
    var col: Int
    let kind: CarParkKind
    let horizontal: Bool
    /// The nose points toward growing columns (horizontal) or rows (vertical).
    let facesForward: Bool
    let color: Int

    var length: Int { kind.length }

    var cells: [GridPos] {
        (0..<length).map { horizontal ? GridPos(r: row, c: col + $0) : GridPos(r: row + $0, c: col) }
    }

    /// The cell `dir` (+1 or −1 along the axis) leads into from the vehicle's end.
    func cell(ahead dir: Int, by steps: Int) -> GridPos {
        if horizontal {
            return GridPos(r: row, c: dir > 0 ? col + length - 1 + steps : col - steps)
        }
        return GridPos(r: dir > 0 ? row + length - 1 + steps : row - steps, c: col)
    }

    func moved(by cells: Int) -> CarParkVehicle {
        var copy = self
        if horizontal { copy.col += cells } else { copy.row += cells }
        return copy
    }

    /// Centre in lot units, one unit per cell.
    var center: CGPoint {
        CGPoint(x: CGFloat(col) + (horizontal ? CGFloat(length) : 1) / 2,
                y: CGFloat(row) + (horizontal ? 1 : CGFloat(length)) / 2)
    }
}

/// Things that never move.
enum CarParkPropKind: Int, Codable {
    case cone, flowers, booth, tree
}

struct CarParkProp: Hashable, Codable {
    let cell: GridPos
    let kind: CarParkPropKind
}

/// Where a drive ends.
enum CarParkStop: Equatable {
    /// Out through an open edge and onto the road.
    case exit(CarParkEdge)
    /// Into another vehicle.
    case vehicle(Int)
    /// Into a cone, flowerbed, booth or tree.
    case prop(GridPos)
    /// Into the fence.
    case fence(CarParkEdge)
}

// MARK: - Lot

struct CarParkLot {
    let columns: Int
    let rows: Int
    var vehicles: [CarParkVehicle]
    let props: [CarParkProp]
    /// Fenced stretches of edge; every other stretch opens onto the road.
    let fence: Set<CarParkEdge>
    /// Gaps in a fenced side, drawn with a barrier arm.
    let gates: Set<CarParkEdge>
    /// People walking along the road, as many as the level has.
    let walkers: Int

    func inside(_ p: GridPos) -> Bool { p.r >= 0 && p.r < rows && p.c >= 0 && p.c < columns }

    /// The edge a vehicle crosses when it leaves through `p`, the first cell past the lot.
    func edge(beyond p: GridPos) -> CarParkEdge {
        if p.r < 0 { return CarParkEdge(side: .top, index: p.c) }
        if p.r >= rows { return CarParkEdge(side: .bottom, index: p.c) }
        if p.c < 0 { return CarParkEdge(side: .left, index: p.r) }
        return CarParkEdge(side: .right, index: p.r)
    }

    /// How far `vehicle` drives in `dir` and what stops it, with `others` in place.
    static func drive(_ vehicle: CarParkVehicle, dir: Int, lot: CarParkLot,
                      occupied: [GridPos: Int], propCells: Set<GridPos>) -> (cells: Int, stop: CarParkStop) {
        var steps = 0
        while true {
            let next = vehicle.cell(ahead: dir, by: steps + 1)
            if !lot.inside(next) {
                let edge = lot.edge(beyond: next)
                return (steps, lot.fence.contains(edge) ? .fence(edge) : .exit(edge))
            }
            if propCells.contains(next) { return (steps, .prop(next)) }
            if let other = occupied[next], other != vehicle.id { return (steps, .vehicle(other)) }
            steps += 1
        }
    }

    func occupancy(of vehicles: [CarParkVehicle]) -> [GridPos: Int] {
        var map: [GridPos: Int] = [:]
        for v in vehicles { for cell in v.cells { map[cell] = v.id } }
        return map
    }

    var propCells: Set<GridPos> { Set(props.map(\.cell)) }
}

// MARK: - Levels

enum CarParkLevels {
    static let count = 60

    /// The lot for `level` (1-based). Every vehicle can leave: the lot is built
    /// backwards, each new vehicle parked only where it could still drive out
    /// past the ones already there, so leaving in reverse order clears it.
    static func make(level: Int) -> CarParkLot {
        let l = max(1, min(count, level))
        var random = PuzzleRandom(seed: UInt64(l) &* 7_919 &+ 31)
        let (columns, rows) = size(level: l)
        let fence = fencedEdges(level: l, columns: columns, rows: rows, random: &random)
        var best: CarParkLot?
        var bestScore = Int.min
        // A few tries; keep the fullest lot with the fewest vehicles free at the start.
        for _ in 0..<80 {
            let props = placeProps(level: l, columns: columns, rows: rows, random: &random)
            var lot = CarParkLot(columns: columns, rows: rows, vehicles: [], props: props,
                                 fence: fence.closed, gates: fence.gates, walkers: walkers(level: l))
            lot.vehicles = park(level: l, lot: lot, random: &random)
            let (rounds, free) = depth(lot.vehicles, lot: lot, props: lot.propCells)
            let filled = lot.vehicles.reduce(0) { $0 + $1.length }
            let score = rounds * 24 + filled * 4 - free * 3
            if score > bestScore { bestScore = score; best = lot }
        }
        return best!
    }

    static func size(level l: Int) -> (Int, Int) {
        switch l {
        case ...4: (4, 5)
        case ...12: (5, 6)
        case ...24: (6, 7)
        case ...40: (6, 8)
        default: (7, 9)
        }
    }

    private static func walkers(level l: Int) -> Int { l < 10 ? 0 : l < 30 ? 1 : l < 45 ? 2 : 3 }

    /// Vehicles that can leave straight away.
    static func freeAtStart(_ lot: CarParkLot) -> Int {
        let occupied = lot.occupancy(of: lot.vehicles), props = lot.propCells
        return lot.vehicles.filter { v in
            [1, -1].contains { dir in
                if case .exit = CarParkLot.drive(v, dir: dir, lot: lot, occupied: occupied, propCells: props).stop { return true }
                return false
            }
        }.count
    }

    /// From level 12 one side is fenced, from level 26 two; each fenced side
    /// keeps one or two gates.
    private static func fencedEdges(level l: Int, columns: Int, rows: Int,
                                    random: inout PuzzleRandom) -> (closed: Set<CarParkEdge>, gates: Set<CarParkEdge>) {
        let sides = l < 12 ? 0 : l < 26 ? 1 : 2
        guard sides > 0 else { return ([], []) }
        var closed: Set<CarParkEdge> = [], gates: Set<CarParkEdge> = []
        var options = CarParkSide.allCases.shuffled(using: &random)
        // Two fenced sides sit opposite each other, so every lot still has a way out on each axis.
        if sides == 2, let first = options.first {
            options = [first, CarParkSide(rawValue: (first.rawValue + 2) % 4)!]
        }
        for side in options.prefix(sides) {
            let span = side == .top || side == .bottom ? columns : rows
            let gateCount = l < 45 ? max(2, span / 2) : max(2, span / 3)
            let open = Set((0..<span).shuffled(using: &random).prefix(gateCount))
            for i in 0..<span {
                let edge = CarParkEdge(side: side, index: i)
                if open.contains(i) { gates.insert(edge) } else { closed.insert(edge) }
            }
        }
        return (closed, gates)
    }

    private static func placeProps(level l: Int, columns: Int, rows: Int,
                                   random: inout PuzzleRandom) -> [CarParkProp] {
        let count = l < 7 ? 0 : min(5, 1 + (l - 7) / 10)
        var props: [CarParkProp] = []
        var used: Set<GridPos> = []
        let kinds: [CarParkPropKind] = [.cone, .flowers, .booth, .tree]
        var tries = 0
        while props.count < count, tries < 100 {
            tries += 1
            let cell = GridPos(r: Int.random(in: 0..<rows, using: &random), c: Int.random(in: 0..<columns, using: &random))
            // Keep props apart so they never wall off a corner.
            guard !used.contains(where: { abs($0.r - cell.r) + abs($0.c - cell.c) < 3 }) else { continue }
            used.insert(cell)
            props.append(CarParkProp(cell: cell, kind: kinds[Int.random(in: 0..<kinds.count, using: &random)]))
        }
        return props
    }

    /// Fills the lot tight with random vehicles, then takes out vehicles that
    /// could never leave until the rest clears. Leaving never blocks anyone,
    /// so a lot is solvable exactly when letting every free vehicle go, round
    /// after round, empties it.
    private static func park(level l: Int, lot: CarParkLot, random: inout PuzzleRandom) -> [CarParkVehicle] {
        var vehicles: [CarParkVehicle] = []
        var occupied: Set<GridPos> = []
        let props = lot.propCells
        let longShare = l < 4 ? 0 : min(30, 10 + l / 3)
        var color = Int.random(in: 0..<8, using: &random)
        // Few vehicles on the first lots, then as many as fit.
        let cap = 3 + l
        for _ in 0..<400 where vehicles.count < cap {
            guard let v = randomVehicle(id: vehicles.count, color: color % 8, longShare: longShare, lot: lot, random: &random),
                  v.cells.allSatisfy({ !occupied.contains($0) && !props.contains($0) }) else { continue }
            vehicles.append(v)
            occupied.formUnion(v.cells)
            color += 3
        }
        while true {
            var left = vehicles
            while true {
                let map = lot.occupancy(of: left)
                let free = Set(left.filter { canLeave($0, lot: lot, occupied: map, props: props) }.map(\.id))
                if free.isEmpty { break }
                left.removeAll { free.contains($0.id) }
            }
            if left.isEmpty { break }
            let stuck = left[Int.random(in: 0..<left.count, using: &random)].id
            vehicles.removeAll { $0.id == stuck }
        }
        return vehicles
    }

    private static func randomVehicle(id: Int, color: Int, longShare: Int, lot: CarParkLot,
                                      random: inout PuzzleRandom) -> CarParkVehicle? {
        let long = Int.random(in: 0..<100, using: &random) < longShare
        let kind: CarParkKind = long ? (Bool.random(using: &random) ? .truck : .bus)
            : [.car, .car, .car, .taxi, .van][Int.random(in: 0..<5, using: &random)]
        let horizontal = Bool.random(using: &random)
        let maxRow = horizontal ? lot.rows : lot.rows - kind.length + 1
        let maxCol = horizontal ? lot.columns - kind.length + 1 : lot.columns
        guard maxRow > 0, maxCol > 0 else { return nil }
        return CarParkVehicle(id: id, row: Int.random(in: 0..<maxRow, using: &random),
                              col: Int.random(in: 0..<maxCol, using: &random),
                              kind: kind, horizontal: horizontal,
                              facesForward: Bool.random(using: &random), color: color)
    }

    /// How many rounds it takes to clear `vehicles` letting every free one go
    /// each round, and how many are free at the start.
    static func depth(_ vehicles: [CarParkVehicle], lot: CarParkLot, props: Set<GridPos>) -> (rounds: Int, free: Int) {
        var left = vehicles
        var rounds = 0, first = 0
        while !left.isEmpty {
            let occupied = lot.occupancy(of: left)
            let free = Set(left.filter { canLeave($0, lot: lot, occupied: occupied, props: props) }.map(\.id))
            if rounds == 0 { first = free.count }
            if free.isEmpty { return (rounds, first) }
            left.removeAll { free.contains($0.id) }
            rounds += 1
        }
        return (rounds, first)
    }

    static func canLeave(_ v: CarParkVehicle, lot: CarParkLot, occupied: [GridPos: Int], props: Set<GridPos>) -> Bool {
        [1, -1].contains { dir in
            if case .exit = CarParkLot.drive(v, dir: dir, lot: lot, occupied: occupied, propCells: props).stop { return true }
            return false
        }
    }
}
