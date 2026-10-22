import Foundation
import Testing
@testable import PuzzleBoxApp

@MainActor
struct BattleshipRulesTests {
    /// A fixed fleet along the left edge, rows two apart so nothing touches.
    private static let fleet: [BattleshipShip] = [
        BattleshipShip(origin: GridPos(r: 0, c: 0), length: 4, horizontal: true),
        BattleshipShip(origin: GridPos(r: 2, c: 0), length: 3, horizontal: true),
        BattleshipShip(origin: GridPos(r: 2, c: 5), length: 3, horizontal: true),
        BattleshipShip(origin: GridPos(r: 4, c: 0), length: 2, horizontal: true),
        BattleshipShip(origin: GridPos(r: 4, c: 4), length: 2, horizontal: true),
        BattleshipShip(origin: GridPos(r: 4, c: 8), length: 2, horizontal: true),
        BattleshipShip(origin: GridPos(r: 6, c: 0), length: 1, horizontal: true),
        BattleshipShip(origin: GridPos(r: 6, c: 3), length: 1, horizontal: true),
        BattleshipShip(origin: GridPos(r: 6, c: 6), length: 1, horizontal: true),
        BattleshipShip(origin: GridPos(r: 6, c: 9), length: 1, horizontal: true),
    ]

    /// Both fleets set and ready; seat 0 fires first.
    private func battle(turn: Int = 0) -> BattleshipState {
        BattleshipState(fleets: [Self.fleet, Self.fleet], ready: [true, true], turn: turn)
    }

    @Test func randomFleetsAreAlwaysValid() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            #expect(BattleshipState.isValidFleet(BattleshipState.randomFleet(using: &generator)))
        }
    }

    @Test func fleetValidation() {
        #expect(BattleshipState.isValidFleet(Self.fleet))
        // Touching at a corner.
        var touching = Self.fleet
        touching[6] = BattleshipShip(origin: GridPos(r: 5, c: 2), length: 1, horizontal: true)
        #expect(!BattleshipState.isValidFleet(touching))
        // Off the board.
        var off = Self.fleet
        off[0] = BattleshipShip(origin: GridPos(r: 8, c: 8), length: 4, horizontal: true)
        #expect(!BattleshipState.isValidFleet(off))
        // A ship missing.
        #expect(!BattleshipState.isValidFleet(Array(Self.fleet.dropLast())))
    }

    @Test func noFiringUntilBothAreReady() throws {
        var state = BattleshipState(fleets: [Self.fleet, Self.fleet], turn: 0)
        #expect(throws: BattleshipState.RuleError.stillPlacing) {
            try state.applying(.fire(GridPos(r: 0, c: 0)), by: 0)
        }
        state = try state.applying(.ready, by: 0)
        #expect(throws: BattleshipState.RuleError.alreadyPlaced) {
            try state.applying(.place(BattleshipState.randomFleet()), by: 0)
        }
        state = try state.applying(.ready, by: 1)
        #expect(!state.isPlacing)
        #expect(state.currentTurn == 0)
    }

    @Test func missPassesTheTurn() throws {
        let next = try battle().applying(.fire(GridPos(r: 9, c: 9)), by: 0)
        #expect(next.turn == 1)
        #expect(next.lastShot == .init(seat: 0, target: GridPos(r: 9, c: 9), hit: false, sunk: false))
        #expect(throws: BattleshipState.RuleError.notYourTurn) {
            try next.applying(.fire(GridPos(r: 0, c: 0)), by: 0)
        }
    }

    @Test func hitKeepsTheTurnAndCantRepeat() throws {
        let next = try battle().applying(.fire(GridPos(r: 0, c: 0)), by: 0)
        #expect(next.turn == 0)
        #expect(next.lastShot?.hit == true && next.lastShot?.sunk == false)
        #expect(throws: BattleshipState.RuleError.alreadyShot) {
            try next.applying(.fire(GridPos(r: 0, c: 0)), by: 0)
        }
    }

    @Test func sinkingMarksTheSurroundings() throws {
        let next = try battle().applying(.fire(GridPos(r: 6, c: 3)), by: 0)
        #expect(next.lastShot?.sunk == true)
        #expect(next.turn == 0)
        // The 3×3 block around the single boat is all marked.
        for r in 5...7 { for c in 2...4 { #expect(next.shots[0].contains(GridPos(r: r, c: c))) } }
        #expect(next.shipsAfloat(of: 1).count == 9)
    }

    @Test func sinkingTheWholeFleetWins() throws {
        var state = battle()
        for cell in Self.fleet.flatMap(\.cells) {
            state = try state.applying(.fire(cell), by: 0)
        }
        #expect(state.outcome == .winner(0))
        #expect(state.result(for: 0, names: ["A", "B"])?.won == true)
        #expect(state.result(for: 1, names: ["A", "B"])?.won == false)
        #expect(throws: BattleshipState.RuleError.gameOver) {
            try state.applying(.fire(GridPos(r: 9, c: 9)), by: 0)
        }
    }

    @Test func botFinishesAWoundedShipAlongItsLine() throws {
        // Seat 1 hit two decks of seat 0's four-decker.
        var state = battle(turn: 1)
        state = try state.applying(.fire(GridPos(r: 0, c: 1)), by: 1)
        state = try state.applying(.fire(GridPos(r: 0, c: 2)), by: 1)
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let target = BattleshipBot.target(for: state, seat: 1, using: &generator)
            #expect(target == GridPos(r: 0, c: 0) || target == GridPos(r: 0, c: 3))
        }
    }

    @Test func botPlaysAFullGameByTheRules() throws {
        // The bot fires until the fleet is gone without ever breaking a rule.
        var state = battle(turn: 1)
        state.shots[0] = []
        var moves = 0
        while state.outcome == nil, moves < 200 {
            if state.turn == 0 {
                // Seat 0 just passes by missing on cells it hasn't fired at.
                let open = (0..<100).map { GridPos(r: $0 / 10, c: $0 % 10) }
                    .first { !state.shots[0].contains($0) && state.ship(of: 1, at: $0) == nil }!
                state = try state.applying(.fire(open), by: 0)
            } else {
                let action = try #require(BattleshipBot.action(for: state, seat: 1))
                state = try state.applying(action, by: 1)
            }
            moves += 1
        }
        #expect(state.outcome == .winner(1))
    }

    @Test func survivesAJSONRoundTrip() throws {
        let state = try battle().applying(.fire(GridPos(r: 2, c: 5)), by: 0)
        let decoded = try JSONDecoder().decode(BattleshipState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
