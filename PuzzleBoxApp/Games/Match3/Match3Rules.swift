import Foundation

// Gems, a match-3: swap two neighbouring gems to line up three or more of a
// colour. Four in a line leaves a bomb (clears 3×3), an L or T leaves a cross
// (clears its row and column), five in a line leaves lightning (clears every
// gem of the colour it is swapped with). Swapping two powers together sets
// off a bigger combo. Frozen gems can't be moved: each match through one
// cracks a layer, and any blast breaks it at once.
// The state is a plain value with a seeded generator, so the engine, saved
// rounds and tests all run the exact same rules.

enum GemColor: Int, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple
}

enum GemPower: String, Codable {
    case none, bomb, cross, lightning
}

struct Gem: Codable, Equatable, Identifiable {
    let id: Int
    /// nil only for lightning, which never matches by colour.
    var color: GemColor?
    var power: GemPower = .none
    /// Layers of ice, 0…2. A frozen gem can't be swapped.
    var ice = 0
    /// Blitz goal: collected when the gem is cleared.
    var crystal = false
}

/// SplitMix64, so a saved round keeps dealing the same gems.
struct Match3Random: RandomNumberGenerator, Codable, Equatable {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A board of any size and shape: cells outside `mask` are holes that
/// break lines and that falling gems skip over.
struct Match3Board: Codable, Equatable {
    let rows: Int
    let cols: Int
    /// Playable cells, row by row; false is a hole.
    let mask: [Bool]
    /// Playable cells, row by row.
    let positions: [GridPos]
    var cells: [Gem?]

    init(rows: Int = 8, cols: Int = 8, mask: [Bool]? = nil) {
        self.rows = rows
        self.cols = cols
        let mask = mask ?? Array(repeating: true, count: rows * cols)
        self.mask = mask
        positions = (0..<rows).flatMap { r in (0..<cols).map { GridPos(r: r, c: $0) } }.filter { mask[$0.r * cols + $0.c] }
        cells = Array(repeating: nil, count: rows * cols)
    }

    /// A board drawn as one string per row: "." is a hole, anything else a cell.
    init(layout: [String]) {
        let cols = layout.map(\.count).max() ?? 0
        let mask = layout.flatMap { row in
            Array(row).map { $0 != "." } + Array(repeating: false, count: cols - row.count)
        }
        self.init(rows: layout.count, cols: cols, mask: mask)
    }

    func contains(_ p: GridPos) -> Bool {
        (0..<rows).contains(p.r) && (0..<cols).contains(p.c) && mask[p.r * cols + p.c]
    }

    static func adjacent(_ a: GridPos, _ b: GridPos) -> Bool {
        abs(a.r - b.r) + abs(a.c - b.c) == 1
    }

    /// nil for holes and cells off the board.
    subscript(p: GridPos) -> Gem? {
        get { contains(p) ? cells[p.r * cols + p.c] : nil }
        set { if contains(p) { cells[p.r * cols + p.c] = newValue } }
    }

    mutating func clear() {
        cells = Array(repeating: nil, count: rows * cols)
    }

    mutating func swap(_ a: GridPos, _ b: GridPos) {
        (self[a], self[b]) = (self[b], self[a])
    }

    /// Whether a gem of `color` at `p` would sit in a line of three or more.
    func makesLine(_ color: GemColor, at p: GridPos) -> Bool {
        func count(_ dr: Int, _ dc: Int) -> Int {
            var k = 0
            var q = GridPos(r: p.r + dr, c: p.c + dc)
            while k < 2, contains(q), self[q]?.color == color {
                k += 1
                q = GridPos(r: q.r + dr, c: q.c + dc)
            }
            return k
        }
        return count(0, -1) + count(0, 1) >= 2 || count(-1, 0) + count(1, 0) >= 2
    }
}

// MARK: - Finding matches

struct Match3Match: Equatable {
    var cells: [GridPos]
    var color: GemColor
    /// The power this match leaves behind.
    var power: GemPower
    /// Where that power appears; nil when the match leaves none.
    var spawnAt: GridPos?
}

enum Match3Finder {
    /// Every match on the board. Straight runs of three or more are found in
    /// one pass over rows and columns; runs that share a cell are joined, which
    /// is what makes an L, T or plus. A line made only of frozen gems doesn't
    /// count, otherwise it would crack itself over and over.
    static func matches(in b: Match3Board, swapped: [GridPos] = []) -> [Match3Match] {
        let n = b.cols
        struct Run { let cells: [GridPos]; let horizontal: Bool }
        var runs: [Run] = []
        var hRun = [Int?](repeating: nil, count: b.rows * b.cols)
        var vRun = [Int?](repeating: nil, count: b.rows * b.cols)

        func scan(horizontal: Bool) {
            func pos(_ line: Int, _ i: Int) -> GridPos {
                horizontal ? GridPos(r: line, c: i) : GridPos(r: i, c: line)
            }
            let lines = horizontal ? b.rows : b.cols
            let length = horizontal ? b.cols : b.rows
            for line in 0..<lines {
                var start = 0
                while start < length {
                    guard let color = b[pos(line, start)]?.color else { start += 1; continue }
                    var end = start + 1
                    while end < length, b[pos(line, end)]?.color == color { end += 1 }
                    if end - start >= 3 {
                        let id = runs.count
                        let cells = (start..<end).map { pos(line, $0) }
                        runs.append(Run(cells: cells, horizontal: horizontal))
                        for p in cells {
                            if horizontal { hRun[p.r * n + p.c] = id } else { vRun[p.r * n + p.c] = id }
                        }
                    }
                    start = end
                }
            }
        }
        scan(horizontal: true)
        scan(horizontal: false)

        // Union-find over runs: a cell in both a row run and a column run joins them.
        var parent = Array(runs.indices)
        func root(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for i in hRun.indices {
            if let h = hRun[i], let v = vRun[i] { parent[root(h)] = root(v) }
        }
        var groups: [Int: [Int]] = [:]
        for i in runs.indices { groups[root(i), default: []].append(i) }

        return groups.keys.sorted().compactMap { key in
            let group = groups[key]!.map { runs[$0] }
            var seen = Set<GridPos>()
            var cells: [GridPos] = []
            for run in group { for p in run.cells where seen.insert(p).inserted { cells.append(p) } }
            guard cells.contains(where: { b[$0]?.ice == 0 }) else { return nil }

            let longest = group.map(\.cells.count).max()!
            let corner = group.contains { $0.horizontal } && group.contains { !$0.horizontal }
            var power: GemPower = longest >= 5 ? .lightning : corner ? .cross : longest == 4 ? .bomb : .none

            // The power appears where the player swapped, else at the corner, else mid-line;
            // never on ice or on a gem that is itself a power about to go off.
            var spawnAt: GridPos?
            if power != .none {
                func free(_ p: GridPos) -> Bool { b[p]?.ice == 0 && b[p]?.power == GemPower.none }
                let cornerCell = cells.first { hRun[$0.r * n + $0.c] != nil && vRun[$0.r * n + $0.c] != nil }
                let middle = cells.count / 2
                let ordered = Array(cells[middle...]) + Array(cells[..<middle])
                spawnAt = swapped.first { seen.contains($0) && free($0) }
                    ?? cornerCell.flatMap { free($0) ? $0 : nil }
                    ?? ordered.first(where: free)
                if spawnAt == nil { power = .none }
            }
            return Match3Match(cells: cells, color: b[cells[0]]!.color!, power: power, spawnAt: spawnAt)
        }
    }

    /// The first swap that does something, scanning row by row; nil when the
    /// board is stuck. Each try only looks two cells out from the swapped pair.
    static func firstMove(in b: Match3Board) -> (GridPos, GridPos)? {
        for a in b.positions {
            for d in [GridPos(r: a.r, c: a.c + 1), GridPos(r: a.r + 1, c: a.c)] where b.contains(d) {
                if isValidSwap(b, a, d) { return (a, d) }
            }
        }
        return nil
    }

    static func isValidSwap(_ b: Match3Board, _ a: GridPos, _ d: GridPos) -> Bool {
        guard Match3Board.adjacent(a, d), let x = b[a], let y = b[d], x.ice == 0, y.ice == 0 else { return false }
        if x.power == .lightning || y.power == .lightning { return true }
        if x.power != .none && y.power != .none { return true }
        guard x.color != y.color, let xc = x.color, let yc = y.color else { return false }
        var t = b
        t.swap(a, d)
        return t.makesLine(xc, at: d) || t.makesLine(yc, at: a)
    }
}

// MARK: - Turns

/// A power going off, for the effects layer.
struct Match3Blast: Codable, Equatable {
    let at: GridPos
    let power: GemPower
    /// Combos of two powers reach further.
    var big = false
    var color: GemColor?
}

/// A cleared gem, for the burst it leaves.
struct Match3Burst: Codable, Equatable {
    let at: GridPos
    let color: GemColor?
}

/// One beat of a turn. Each carries the whole board as it stands after it,
/// so the view only has to animate from one board to the next.
struct Match3Step: Equatable {
    enum Kind: Equatable { case swap, charge, clear, fall, shuffle }
    let kind: Kind
    let board: Match3Board
    var bursts: [Match3Burst] = []
    var blasts: [Match3Blast] = []
    var cracked: [GridPos] = []
    var created: [GridPos] = []
    var points = 0
    var crystals = 0
    var cascade = 0
}

struct Match3Turn: Equatable {
    var steps: [Match3Step] = []
    var points: Int { steps.reduce(0) { $0 + $1.points } }
    var crystals: Int { steps.reduce(0) { $0 + $1.crystals } }
    var bestCascade: Int { steps.map(\.cascade).max() ?? 0 }
}

// MARK: - State

struct Match3State: Codable, Equatable {
    static let pointsPerGem = 10
    static let pointsPerIce = 20
    static let pointsPerPower = 50
    static let maxMultiplier = 5

    var board = Match3Board()
    var random: Match3Random
    var nextID = 0
    /// How many colours the spawner deals: 5 is relaxed, 6 needs thought.
    var colorCount: Int
    /// Chance that a new gem carries a crystal; 0 outside Blitz.
    var crystalChance: Double
    /// Chance that a falling gem picks a colour that lines up where it lands.
    var assist: Double
    /// Chance that a falling gem arrives frozen; Casual raises it with the score.
    var iceChance: Double = 0

    var palette: ArraySlice<GemColor> { GemColor.allCases.prefix(colorCount) }
    var hasMoves: Bool { Match3Finder.firstMove(in: board) != nil }
    var hint: (GridPos, GridPos)? { Match3Finder.firstMove(in: board) }

    /// A board of `shape` with no lines on it and at least one move: the
    /// `frozen` cells plus `ice` more frozen gems below the top two rows.
    static func newGame(shape: Match3Board = Match3Board(), colors: Int, ice: Int = 0, frozen: [GridPos] = [],
                        crystalChance: Double = 0, assist: Double = 0.1,
                        seed: UInt64 = .random(in: 0...UInt64.max)) -> Match3State {
        var state = Match3State(board: shape, random: Match3Random(seed: seed), colorCount: colors,
                                crystalChance: crystalChance, assist: assist)
        state.deal(ice: ice, frozen: frozen)
        return state
    }

    private mutating func deal(ice: Int, frozen: [GridPos]) {
        for _ in 0..<100 {
            board.clear()
            for p in board.positions {
                let banned = palette.filter { board.makesLine($0, at: p) }
                let color = palette.filter { !banned.contains($0) }.randomElement(using: &random)!
                board[p] = newGem(color: color)
            }
            let extra = board.positions.filter { $0.r >= 2 && !frozen.contains($0) }.shuffled(using: &random).prefix(ice)
            for p in frozen + extra { board[p]?.ice = 2; board[p]?.crystal = false }
            if hasMoves { return }
        }
    }

    private mutating func newGem(color: GemColor) -> Gem {
        nextID += 1
        let crystal = crystalChance > 0 && Double.random(in: 0..<1, using: &random) < crystalChance
        return Gem(id: nextID, color: color, crystal: crystal)
    }

    /// A gem falling into `p`. Keeps a crystal around in Blitz so the goal
    /// never stalls on bad luck.
    private mutating func spawn(at p: GridPos) -> Gem {
        var color = palette.randomElement(using: &random)!
        if Double.random(in: 0..<1, using: &random) < assist,
           let helpful = palette.filter({ board.makesLine($0, at: p) }).randomElement(using: &random) {
            color = helpful
        }
        var gem = newGem(color: color)
        if crystalChance > 0 && !board.cells.contains(where: { $0?.crystal == true }) { gem.crystal = true }
        if iceChance > 0 && Double.random(in: 0..<1, using: &random) < iceChance { gem.ice = 2 }
        return gem
    }

    // MARK: Moves

    /// Plays a swap. Returns nil, leaving the state untouched, when the swap
    /// is not allowed or lines nothing up.
    mutating func swap(_ a: GridPos, _ b: GridPos) -> Match3Turn? {
        guard Match3Board.adjacent(a, b), let x = board[a], let y = board[b], x.ice == 0, y.ice == 0 else { return nil }
        let combo = x.power == .lightning || y.power == .lightning || (x.power != .none && y.power != .none)
        var turn = Match3Turn()
        board.swap(a, b)
        if !combo && Match3Finder.matches(in: board).isEmpty {
            board.swap(a, b)
            return nil
        }
        turn.steps.append(Match3Step(kind: .swap, board: board))
        if combo {
            // After the swap `x` sits at `b` and `y` at `a`.
            fireCombo(moved: x, at: b, other: y, at: a, turn: &turn)
            collapse(&turn)
            settle(&turn, cascade: 2)
        } else {
            settle(&turn, swapped: [a, b], cascade: 1)
        }
        return turn
    }

    private mutating func fireCombo(moved x: Gem, at b: GridPos, other y: Gem, at a: GridPos, turn: inout Match3Turn) {
        let all = Set(board.positions.filter { board[$0] != nil })
        func square(_ p: GridPos, _ radius: Int) -> Set<GridPos> {
            Set(board.positions.filter { abs($0.r - p.r) <= radius && abs($0.c - p.c) <= radius })
        }
        func lines(rows: [Int], cols: [Int]) -> Set<GridPos> {
            Set(board.positions.filter { rows.contains($0.r) || cols.contains($0.c) })
        }

        switch (x.power, y.power) {
        case (.lightning, .lightning):
            explode(all, blasted: all, blasts: [Match3Blast(at: b, power: .lightning, big: true)],
                    fired: [a, b], cascade: 1, turn: &turn)

        case (.lightning, _), (_, .lightning):
            let (boltAt, other, otherAt) = x.power == .lightning ? (b, y, a) : (a, x, b)
            guard let color = other.color else { return }
            let targets = board.positions.filter { board[$0]?.color == color }
            var hit = Set(targets).union([boltAt, otherAt])
            if other.power != .none {
                // Every gem of that colour becomes the same power, then they all go off.
                for p in targets where board[p]?.ice == 0 { board[p]?.power = other.power }
                turn.steps.append(Match3Step(kind: .charge, board: board, created: targets.filter { board[$0]?.ice == 0 }))
                hit.formUnion(targets)
            }
            explode(hit, blasted: [], blasts: [Match3Blast(at: boltAt, power: .lightning, color: color)],
                    fired: [boltAt], cascade: 1, turn: &turn)

        case (.bomb, .bomb):
            let area = square(b, 2)
            explode(area, blasted: area, blasts: [Match3Blast(at: b, power: .bomb, big: true)],
                    fired: [a, b], cascade: 1, turn: &turn)

        case (.cross, .cross):
            let area = lines(rows: [a.r, b.r], cols: [a.c, b.c])
            explode(area, blasted: area, blasts: [Match3Blast(at: a, power: .cross), Match3Blast(at: b, power: .cross)],
                    fired: [a, b], cascade: 1, turn: &turn)

        default: // bomb + cross: three rows and three columns
            let area = lines(rows: Array(b.r - 1...b.r + 1), cols: Array(b.c - 1...b.c + 1))
            explode(area, blasted: area, blasts: [Match3Blast(at: b, power: .cross, big: true)],
                    fired: [a, b], cascade: 1, turn: &turn)
        }
    }

    /// Clears matches, lets gems fall and repeats until the board is still.
    /// Every round after the first is a cascade and scores more.
    private mutating func settle(_ turn: inout Match3Turn, swapped: [GridPos] = [], cascade start: Int) {
        var cascade = start
        while cascade < start + 40 {
            let found = Match3Finder.matches(in: board, swapped: cascade == start ? swapped : [])
            if found.isEmpty { return }
            var hit = Set<GridPos>()
            var created: [GridPos: Gem] = [:]
            for match in found {
                hit.formUnion(match.cells)
                if let at = match.spawnAt, let old = board[at] {
                    created[at] = Gem(id: old.id, color: match.power == .lightning ? nil : match.color,
                                      power: match.power, crystal: old.crystal)
                }
            }
            explode(hit, created: created, cascade: cascade, turn: &turn)
            collapse(&turn)
            cascade += 1
        }
    }

    /// Clears `hit`, setting off every power caught in it (and in what those
    /// blasts reach). Ice cracks by one layer, or breaks outright when a blast
    /// reaches it. `created` cells turn into new powers instead of vanishing.
    private mutating func explode(_ hit: Set<GridPos>, blasted: Set<GridPos>? = nil, blasts: [Match3Blast] = [],
                                  fired: Set<GridPos>? = nil, created: [GridPos: Gem]? = nil,
                                  cascade: Int, turn: inout Match3Turn) {
        var hit = hit
        var blasted = blasted ?? []
        var blasts = blasts
        var fired = fired ?? []
        let created = created ?? [:]
        var queue = hit.sorted { ($0.r, $0.c) < ($1.r, $1.c) }
        while let p = queue.popLast() {
            guard !fired.contains(p), created[p] == nil, let gem = board[p], gem.power != .none else { continue }
            fired.insert(p)
            let area = area(of: gem, at: p)
            blasts.append(Match3Blast(at: p, power: gem.power, color: gem.color ?? lightningColor()))
            blasted.formUnion(area)
            for q in area where hit.insert(q).inserted { queue.append(q) }
        }

        var bursts: [Match3Burst] = []
        var cracked: [GridPos] = []
        var made: [GridPos] = []
        var crystals = 0
        var points = 0
        for p in hit.sorted(by: { ($0.r, $0.c) < ($1.r, $1.c) }) {
            guard var gem = board[p] else { continue }
            if let power = created[p] {
                if power.crystal { crystals += 1 }
                board[p] = Gem(id: power.id, color: power.color, power: power.power)
                made.append(p)
                points += Self.pointsPerPower
            } else if gem.ice > 0 {
                gem.ice = blasted.contains(p) ? 0 : gem.ice - 1
                board[p] = gem
                cracked.append(p)
                points += Self.pointsPerIce
            } else {
                if gem.crystal { crystals += 1 }
                bursts.append(Match3Burst(at: p, color: gem.color))
                board[p] = nil
                points += Self.pointsPerGem
            }
        }
        turn.steps.append(Match3Step(kind: .clear, board: board, bursts: bursts, blasts: blasts,
                                     cracked: cracked, created: made,
                                     points: points * min(max(cascade, 1), Self.maxMultiplier),
                                     crystals: crystals, cascade: cascade))
    }

    private func area(of gem: Gem, at p: GridPos) -> [GridPos] {
        switch gem.power {
        case .none: return [p]
        case .bomb: return board.positions.filter { abs($0.r - p.r) <= 1 && abs($0.c - p.c) <= 1 }
        case .cross: return board.positions.filter { $0.r == p.r || $0.c == p.c }
        case .lightning:
            // Set off by a blast rather than a swap: takes the commonest colour.
            guard let color = lightningColor() else { return [p] }
            return [p] + board.positions.filter { board[$0]?.color == color }
        }
    }

    private func lightningColor() -> GemColor? {
        var counts: [GemColor: Int] = [:]
        for gem in board.cells { if let c = gem?.color { counts[c, default: 0] += 1 } }
        return counts.max { ($0.value, $1.key.rawValue) < ($1.value, $0.key.rawValue) }?.key
    }

    /// Gems fall into the gaps, skipping over holes, and new ones drop in
    /// from the top of each column.
    private mutating func collapse(_ turn: inout Match3Turn) {
        for c in 0..<board.cols {
            let column = (0..<board.rows).map { GridPos(r: $0, c: c) }.filter(board.contains)
            let gems = column.compactMap { board[$0] }
            let empty = column.count - gems.count
            guard empty > 0 else { continue }
            for (i, p) in column.enumerated() { board[p] = i < empty ? nil : gems[i - empty] }
            for p in column.prefix(empty).reversed() { board[p] = spawn(at: p) }
        }
        turn.steps.append(Match3Step(kind: .fall, board: board))
    }

    // MARK: Endings

    /// "Last chord": sets off every power left on the board, one after another,
    /// with all the cascades that follow.
    mutating func finale() -> Match3Turn {
        var turn = Match3Turn()
        for _ in 0..<30 {
            guard let p = board.positions.first(where: { (board[$0]?.power ?? GemPower.none) != GemPower.none }) else { break }
            explode([p], cascade: 1, turn: &turn)
            collapse(&turn)
            settle(&turn, cascade: 2)
        }
        return turn
    }

    /// Reshuffles the unfrozen gems until the board has a move and no lines.
    mutating func shuffle() -> Match3Step {
        let movable = board.positions.filter { board[$0]?.ice == 0 }
        let original = board
        for _ in 0..<200 {
            var gems = movable.compactMap { original[$0] }
            gems.shuffle(using: &random)
            for (p, gem) in zip(movable, gems) { board[p] = gem }
            if Match3Finder.matches(in: board).isEmpty && hasMoves {
                return Match3Step(kind: .shuffle, board: board)
            }
        }
        // Too few colours left to shuffle into shape: deal fresh plain gems.
        for p in movable where board[p]?.power == GemPower.none { board[p]?.color = nil }
        let palette = self.palette
        for p in movable where board[p]?.color == nil && board[p]?.power == GemPower.none {
            let banned = palette.filter { board.makesLine($0, at: p) }
            let color = palette.filter { !banned.contains($0) }.randomElement(using: &random)
            board[p]?.color = color
        }
        return Match3Step(kind: .shuffle, board: board)
    }
}

// MARK: - Blitz levels

/// Blitz difficulty by level: more crystals to collect, more ice, and a sixth
/// colour from level 6. The timer is the same every level.
struct Match3Level: Equatable {
    static let time: Double = 60

    let number: Int

    var colors: Int { number <= 5 ? 5 : 6 }
    /// Two more a level while there are five colours; the sixth colour is a
    /// big jump on its own, so from there the goal grows by one.
    var crystalsNeeded: Int { number <= 5 ? 6 + 2 * number : min(8 + number, 30) }
    var iceCount: Int { number == 1 ? 0 : min(2 * number, 16) }
    var crystalChance: Double { 0.03 + 0.002 * Double(min(number, 10)) }
    var assist: Double { max(0.04, 0.14 - 0.01 * Double(number)) }

    func newGame(seed: UInt64 = .random(in: 0...UInt64.max)) -> Match3State {
        .newGame(colors: colors, ice: iceCount, crystalChance: crystalChance, assist: assist, seed: seed)
    }
}

// MARK: - Arcade levels

/// Arcade: hand-drawn boards that grow and change shape, each with a crystal
/// goal to reach within a number of moves. After the last drawing the boards
/// come round again (all but the first two), one crystal harder each time.
struct Match3ArcadeLevel: Equatable {
    /// One drawing: "." is a hole, "*" a gem that starts frozen, "o" a cell.
    struct Plan {
        let layout: [String]
        let crystals: Int
        let moves: Int
    }

    static let plans: [Plan] = [
        Plan(layout: ["oooooo", "oooooo", "oooooo", "oooooo", "oooooo", "oooooo"],
             crystals: 10, moves: 15),
        Plan(layout: ["ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo"],
             crystals: 12, moves: 15),
        Plan(layout: [".ooooo.", "ooooooo", "ooooooo", "ooooooo", "ooooooo", "ooooooo", ".ooooo."],
             crystals: 14, moves: 18),
        Plan(layout: ["oooooooo", "oooooooo", "oooooooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oooooooo", "oooooooo"],
             crystals: 16, moves: 18),
        Plan(layout: ["..oooo..", "..oooo..", "oooooooo", "oooooooo", "oooooooo", "oooooooo", "..oooo..", "..oooo.."],
             crystals: 16, moves: 16),
        Plan(layout: ["oooooooo", "oooooooo", ".oooooo.", "..oooo..", "..oooo..", ".oooooo.", "oooooooo", "oooooooo"],
             crystals: 18, moves: 18),
        Plan(layout: ["ooo..ooo", "ooo..ooo", "ooo..ooo", "ooo..ooo", "ooo..ooo", "oooooooo", "oo*oo*oo", "oooooooo"],
             crystals: 13, moves: 22),
        Plan(layout: ["oooooooo", "oo*oo*oo", "oooooooo", "o*oooo*o", "o*oooo*o", "oooooooo", "oo*oo*oo", "oooooooo"],
             crystals: 12, moves: 22),
        Plan(layout: [".oo..oo.", "oooooooo", "oooooooo", "oooooooo", ".oooooo.", "..oooo..", "...oo..."],
             crystals: 10, moves: 20),
        Plan(layout: ["oooooooo", "o.oooo.o", "oooooooo", "ooo**ooo", "ooo**ooo", "oooooooo", "o.oooo.o", "oooooooo"],
             crystals: 11, moves: 22),
        Plan(layout: ["oooooooo", "oooooooo", "oo*oo*oo", "oooooooo", "o*oooo*o", "oooooooo", "oo*oo*oo", "oooooooo", "oooooooo"],
             crystals: 13, moves: 22),
        Plan(layout: ["...oo...", "..oooo..", ".oooooo.", "oooo*ooo", "ooo*oooo", ".oooooo.", "..oooo..", "...oo..."],
             crystals: 10, moves: 20),
    ]

    let number: Int

    /// Which drawing this level uses, and how many times the drawings have come round before.
    private var index: (plan: Int, lap: Int) {
        let count = Self.plans.count
        guard number > count else { return (number - 1, 0) }
        let past = number - 1 - count
        return (2 + past % (count - 2), 1 + past / (count - 2))
    }

    var plan: Plan { Self.plans[index.plan] }
    /// Four colours on the first two boards, five up to the seventh, then six.
    var colors: Int { index.plan < 2 ? 4 : index.plan < 7 ? 5 : 6 }
    var crystalsNeeded: Int { plan.crystals + index.lap }
    var moves: Int { plan.moves }
    var crystalChance: Double { 0.05 }
    var assist: Double { max(0.04, 0.12 - 0.01 * Double(number)) }

    var shape: Match3Board { Match3Board(layout: plan.layout) }

    /// Cells drawn with "*".
    var frozen: [GridPos] {
        plan.layout.enumerated().flatMap { r, row in
            Array(row).enumerated().compactMap { c, ch in ch == "*" ? GridPos(r: r, c: c) : nil }
        }
    }

    func newGame(seed: UInt64 = .random(in: 0...UInt64.max)) -> Match3State {
        .newGame(shape: shape, colors: colors, frozen: frozen, crystalChance: crystalChance,
                 assist: assist, seed: seed)
    }
}

/// Casual settings: six colours and a handful of ice. As the score grows the
/// helping hand fades and more gems fall in frozen, so a run eventually gets
/// stuck and ends; six colours alone almost never run out of moves.
enum Match3Casual {
    static let colors = 6
    static let iceCount = 4

    static func assist(forScore score: Int) -> Double {
        max(0, 0.12 - Double(score) / 30_000)
    }

    static func iceChance(forScore score: Int) -> Double {
        min(0.12, Double(score) / 150_000)
    }

    static func newGame(seed: UInt64 = .random(in: 0...UInt64.max)) -> Match3State {
        .newGame(colors: colors, ice: iceCount, assist: assist(forScore: 0), seed: seed)
    }
}
