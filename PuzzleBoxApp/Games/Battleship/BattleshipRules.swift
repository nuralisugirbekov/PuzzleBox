import Foundation

// Battleship (sea battle) for two on 10×10 boards, by the classic rules:
// a four-decker, two three-deckers, three two-deckers and four single
// boats, which never touch, not even at the corners. First each player sets
// up their fleet (shuffling until they like it) and says they're ready. Then
// they take turns firing at the other board: a hit goes again, a miss passes
// the turn. A sunk ship's surroundings are marked as misses, since no other
// ship can be there. Whoever sinks the whole enemy fleet wins.
// The state is a plain value so the bot game and an online match (stored in
// Firestore) run the exact same rules.

enum BattleshipAction: Codable, Equatable {
    /// Replaces this player's fleet while setting up.
    case place([BattleshipShip])
    /// Done setting up; the battle starts once both are ready.
    case ready
    /// A shot at the other player's board.
    case fire(GridPos)
}

struct BattleshipShip: Codable, Equatable, Hashable {
    let origin: GridPos
    let length: Int
    let horizontal: Bool

    var cells: [GridPos] {
        (0..<length).map { horizontal ? GridPos(r: origin.r, c: origin.c + $0) : GridPos(r: origin.r + $0, c: origin.c) }
    }

    /// The ship's cells and every cell around them.
    var halo: Set<GridPos> {
        var area = Set<GridPos>()
        for cell in cells {
            for dr in -1...1 {
                for dc in -1...1 {
                    let pos = GridPos(r: cell.r + dr, c: cell.c + dc)
                    if BattleshipState.contains(pos) { area.insert(pos) }
                }
            }
        }
        return area
    }
}

struct BattleshipState: Codable, Equatable {
    enum Outcome: Codable, Equatable {
        case winner(Int)
    }

    enum RuleError: Error, Equatable {
        case gameOver, notYourTurn, stillPlacing, alreadyPlaced, invalidFleet, offBoard, alreadyShot
    }

    struct LastShot: Codable, Equatable {
        let seat: Int
        let target: GridPos
        let hit: Bool
        let sunk: Bool
    }

    static let size = 10
    /// Ship lengths, biggest first.
    static let fleetLengths = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1]
    static let playerRange = 2...2

    /// Each seat's ships.
    var fleets: [[BattleshipShip]]
    /// Cells each seat has fired at on the other board, plus the misses
    /// marked around ships it sank.
    var shots: [[GridPos]] = [[], []]
    var ready = [false, false]
    /// The seat to fire next, once both fleets are set.
    var turn: Int
    var outcome: Outcome?
    var lastShot: LastShot?

    var playerCount: Int { fleets.count }
    var isPlacing: Bool { !ready.allSatisfy { $0 } }
    var currentTurn: Int? { outcome == nil && !isPlacing ? turn : nil }

    static func contains(_ pos: GridPos) -> Bool {
        (0..<size).contains(pos.r) && (0..<size).contains(pos.c)
    }

    func opponent(of seat: Int) -> Int { (seat + 1) % playerCount }

    // MARK: Boards

    /// The ship of `seat`'s fleet on `cell`, if any.
    func ship(of seat: Int, at cell: GridPos) -> BattleshipShip? {
        fleets[seat].first { $0.cells.contains(cell) }
    }

    /// Whether `seat`'s ship has been sunk by the other player.
    func isSunk(_ ship: BattleshipShip, of seat: Int) -> Bool {
        let fired = Set(shots[opponent(of: seat)])
        return ship.cells.allSatisfy(fired.contains)
    }

    /// Ships of `seat` still afloat.
    func shipsAfloat(of seat: Int) -> [BattleshipShip] {
        fleets[seat].filter { !isSunk($0, of: seat) }
    }

    /// Cells of `seat`'s fleet not hit yet.
    func cellsAfloat(of seat: Int) -> Int {
        let fired = Set(shots[opponent(of: seat)])
        return fleets[seat].flatMap(\.cells).filter { !fired.contains($0) }.count
    }

    // MARK: Fleets

    /// Whether `ships` is a full fleet that fits the board without ships touching.
    static func isValidFleet(_ ships: [BattleshipShip]) -> Bool {
        guard ships.map(\.length).sorted(by: >) == fleetLengths else { return false }
        var taken = Set<GridPos>()
        for ship in ships {
            guard ship.cells.allSatisfy(contains) else { return false }
            if !ship.halo.isDisjoint(with: taken) { return false }
            taken.formUnion(ship.cells)
        }
        return true
    }

    static func randomFleet<G: RandomNumberGenerator>(using generator: inout G) -> [BattleshipShip] {
        // Random tries almost always fit; start over in the rare dead end.
        while true {
            var ships: [BattleshipShip] = []
            var blocked = Set<GridPos>()
            var placedAll = true
            for length in fleetLengths {
                var options: [BattleshipShip] = []
                for horizontal in [true, false] {
                    for r in 0..<size {
                        for c in 0..<size {
                            let ship = BattleshipShip(origin: GridPos(r: r, c: c), length: length, horizontal: horizontal)
                            if ship.cells.allSatisfy({ contains($0) && !blocked.contains($0) }) { options.append(ship) }
                        }
                    }
                }
                guard let ship = options.randomElement(using: &generator) else { placedAll = false; break }
                ships.append(ship)
                blocked.formUnion(ship.halo)
            }
            if placedAll { return ships }
        }
    }

    static func randomFleet() -> [BattleshipShip] {
        var generator = SystemRandomNumberGenerator()
        return randomFleet(using: &generator)
    }

    // MARK: Dealing

    /// Both fleets placed at random; each player may reshuffle theirs before saying ready.
    static func newGame<G: RandomNumberGenerator>(using generator: inout G) -> BattleshipState {
        BattleshipState(fleets: [randomFleet(using: &generator), randomFleet(using: &generator)],
                        turn: Int.random(in: 0..<2, using: &generator))
    }

    static func newGame() -> BattleshipState {
        var generator = SystemRandomNumberGenerator()
        return newGame(using: &generator)
    }

    // MARK: Rules

    func canFire(at target: GridPos, by seat: Int) -> Bool {
        currentTurn == seat && Self.contains(target) && !shots[seat].contains(target)
    }

    func applying(_ action: BattleshipAction, by seat: Int) throws -> BattleshipState {
        var next = self
        try next.apply(action, by: seat)
        return next
    }

    mutating func apply(_ action: BattleshipAction, by seat: Int) throws {
        guard outcome == nil else { throw RuleError.gameOver }
        switch action {
        case .place(let ships):
            guard isPlacing, !ready[seat] else { throw RuleError.alreadyPlaced }
            guard Self.isValidFleet(ships) else { throw RuleError.invalidFleet }
            fleets[seat] = ships
        case .ready:
            guard !ready[seat] else { throw RuleError.alreadyPlaced }
            ready[seat] = true
        case .fire(let target):
            guard !isPlacing else { throw RuleError.stillPlacing }
            guard seat == turn else { throw RuleError.notYourTurn }
            guard Self.contains(target) else { throw RuleError.offBoard }
            guard !shots[seat].contains(target) else { throw RuleError.alreadyShot }

            shots[seat].append(target)
            let enemy = opponent(of: seat)
            var sunk = false
            if let ship = ship(of: enemy, at: target) {
                if isSunk(ship, of: enemy) {
                    sunk = true
                    // Nothing else can be next to a sunk ship: mark it all as missed.
                    let fired = Set(shots[seat])
                    shots[seat] += ship.halo.subtracting(fired).sorted { ($0.r, $0.c) < ($1.r, $1.c) }
                    if shipsAfloat(of: enemy).isEmpty { outcome = .winner(seat) }
                }
                lastShot = LastShot(seat: seat, target: target, hit: true, sunk: sunk)
            } else {
                turn = enemy
                lastShot = LastShot(seat: seat, target: target, hit: false, sunk: false)
            }
        }
    }
}

// MARK: - Bot

enum BattleshipBot {
    /// How often the bot hunts on the checkerboard that every ship of two or
    /// more must cross; the rest of the time it fires anywhere, which keeps
    /// it beatable. Once it hits, it always finishes the ship off.
    static let skill = 0.6

    static func action<G: RandomNumberGenerator>(for state: BattleshipState, seat: Int,
                                                 using generator: inout G) -> BattleshipAction? {
        guard state.outcome == nil else { return nil }
        if state.isPlacing { return state.ready[seat] ? nil : .ready }
        guard state.currentTurn == seat else { return nil }
        return target(for: state, seat: seat, using: &generator).map(BattleshipAction.fire)
    }

    static func action(for state: BattleshipState, seat: Int) -> BattleshipAction? {
        var generator = SystemRandomNumberGenerator()
        return action(for: state, seat: seat, using: &generator)
    }

    static func target<G: RandomNumberGenerator>(for state: BattleshipState, seat: Int,
                                                 using generator: inout G) -> GridPos? {
        let enemy = state.opponent(of: seat)
        let fired = Set(state.shots[seat])
        let open = (0..<BattleshipState.size).flatMap { r in
            (0..<BattleshipState.size).map { GridPos(r: r, c: $0) }
        }.filter { !fired.contains($0) }
        guard !open.isEmpty else { return nil }

        // Hits on ships not sunk yet: keep firing next to them, along their line.
        let wounded = state.shots[seat].filter { cell in
            guard let ship = state.ship(of: enemy, at: cell) else { return false }
            return !state.isSunk(ship, of: enemy)
        }
        if !wounded.isEmpty {
            let candidates = followUps(of: wounded).filter { BattleshipState.contains($0) && !fired.contains($0) }
            if let pick = candidates.randomElement(using: &generator) { return pick }
        }

        if Double.random(in: 0..<1, using: &generator) < skill {
            let parity = open.filter { ($0.r + $0.c) % 2 == 0 }
            if let pick = parity.randomElement(using: &generator) { return pick }
        }
        return open.randomElement(using: &generator)
    }

    /// Cells that may hold the rest of a wounded ship: along the line of two
    /// or more hits, or on any side of a single one.
    private static func followUps(of hits: [GridPos]) -> [GridPos] {
        if hits.count >= 2 {
            let rows = Set(hits.map(\.r)), cols = Set(hits.map(\.c))
            if rows.count == 1, let row = rows.first {
                let cs = hits.map(\.c)
                return [GridPos(r: row, c: cs.min()! - 1), GridPos(r: row, c: cs.max()! + 1)]
            }
            if cols.count == 1, let col = cols.first {
                let rs = hits.map(\.r)
                return [GridPos(r: rs.min()! - 1, c: col), GridPos(r: rs.max()! + 1, c: col)]
            }
        }
        return hits.flatMap { hit in
            [GridPos(r: hit.r - 1, c: hit.c), GridPos(r: hit.r + 1, c: hit.c),
             GridPos(r: hit.r, c: hit.c - 1), GridPos(r: hit.r, c: hit.c + 1)]
        }
    }
}
