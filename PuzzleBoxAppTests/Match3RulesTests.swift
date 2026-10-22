import Foundation
import Testing
@testable import PuzzleBoxApp

@MainActor
struct Match3RulesTests {
    /// A board with no lines: yellow, green, blue and purple in a diagonal
    /// pattern, so red and orange placed on top never join the filler.
    private func board(_ gems: [GridPos: GemColor]? = nil, ice: Set<GridPos>? = nil,
                       powers: [GridPos: GemPower]? = nil) -> Match3Board {
        let gems = gems ?? [:], ice = ice ?? [], powers = powers ?? [:]
        let filler: [GemColor] = [.yellow, .green, .blue, .purple]
        var b = Match3Board()
        for p in Match3Board().positions {
            var gem = Gem(id: p.r * 8 + p.c, color: gems[p] ?? filler[(p.r + p.c) % 4])
            if ice.contains(p) { gem.ice = 2 }
            if let power = powers[p] {
                gem.power = power
                if power == .lightning { gem.color = nil }
            }
            b[p] = gem
        }
        return b
    }

    private func state(_ b: Match3Board, seed: UInt64 = 1) -> Match3State {
        Match3State(board: b, random: Match3Random(seed: seed), nextID: 1000, colorCount: 6, crystalChance: 0, assist: 0)
    }

    private func row(_ r: Int, _ cols: ClosedRange<Int>, _ color: GemColor = .red) -> [GridPos: GemColor] {
        Dictionary(uniqueKeysWithValues: cols.map { (GridPos(r: r, c: $0), color) })
    }

    private func col(_ c: Int, _ rows: ClosedRange<Int>, _ color: GemColor = .red) -> [GridPos: GemColor] {
        Dictionary(uniqueKeysWithValues: rows.map { (GridPos(r: $0, c: c), color) })
    }

    // MARK: Finding matches

    @Test func fillerHasNoMatches() {
        #expect(Match3Finder.matches(in: board()).isEmpty)
    }

    @Test func threeInARowIsAPlainMatch() {
        let found = Match3Finder.matches(in: board(row(3, 0...2)))
        #expect(found.count == 1)
        #expect(found[0].power == .none)
        #expect(Set(found[0].cells) == Set(row(3, 0...2).keys))
    }

    @Test func fourInARowMakesABombWhereThePlayerSwapped() {
        let found = Match3Finder.matches(in: board(row(3, 0...3)), swapped: [GridPos(r: 3, c: 2)])
        #expect(found.count == 1)
        #expect(found[0].power == .bomb)
        #expect(found[0].spawnAt == GridPos(r: 3, c: 2))
    }

    @Test func fiveInARowMakesLightning() {
        let found = Match3Finder.matches(in: board(col(5, 1...5)))
        #expect(found.map(\.power) == [.lightning])
    }

    @Test func lShapeMakesACrossAtTheCorner() {
        let gems = row(2, 0...2).merging(col(0, 2...4)) { a, _ in a }
        let found = Match3Finder.matches(in: board(gems))
        #expect(found.count == 1)
        #expect(found[0].cells.count == 5)
        #expect(found[0].power == .cross)
        #expect(found[0].spawnAt == GridPos(r: 2, c: 0))
    }

    @Test func tShapeMakesACross() {
        let gems = row(2, 0...2).merging(col(1, 2...4)) { a, _ in a }
        let found = Match3Finder.matches(in: board(gems))
        #expect(found.map(\.power) == [.cross])
        #expect(found[0].spawnAt == GridPos(r: 2, c: 1))
    }

    @Test func parallelLinesStaySeparate() {
        let gems = row(0, 0...2).merging(row(1, 0...2, .orange)) { a, _ in a }
        let found = Match3Finder.matches(in: board(gems))
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.power == .none })
    }

    @Test func aLineOfOnlyFrozenGemsDoesNotCount() {
        let cells = Set(row(3, 0...2).keys)
        #expect(Match3Finder.matches(in: board(row(3, 0...2), ice: cells)).isEmpty)
        let oneFree = cells.subtracting([GridPos(r: 3, c: 0)])
        #expect(Match3Finder.matches(in: board(row(3, 0...2), ice: oneFree)).count == 1)
    }

    // MARK: Moves

    @Test func findsAMoveAndRejectsFrozenGems() {
        // Red at (4,0) (4,1) and (3,2): dropping (3,2) down lines them up.
        var gems = row(4, 0...1)
        gems[GridPos(r: 3, c: 2)] = .red
        let b = board(gems)
        #expect(Match3Finder.isValidSwap(b, GridPos(r: 3, c: 2), GridPos(r: 4, c: 2)))
        #expect(Match3Finder.firstMove(in: b) != nil)
        let frozen = board(gems, ice: [GridPos(r: 3, c: 2)])
        #expect(!Match3Finder.isValidSwap(frozen, GridPos(r: 3, c: 2), GridPos(r: 4, c: 2)))
    }

    @Test func stuckBoardHasNoMoves() {
        // Every row cycles six colours, shifted by two each row: no swap can line up three.
        var b = Match3Board()
        for p in Match3Board().positions {
            b[p] = Gem(id: p.r * 8 + p.c, color: GemColor(rawValue: (p.c + 2 * p.r) % 6)!)
        }
        #expect(Match3Finder.matches(in: b).isEmpty)
        #expect(Match3Finder.firstMove(in: b) == nil)
    }

    @Test func lightningAndPowerPairsAlwaysMove() {
        let lightning = board(powers: [GridPos(r: 0, c: 0): .lightning])
        #expect(Match3Finder.isValidSwap(lightning, GridPos(r: 0, c: 0), GridPos(r: 0, c: 1)))
        let pair = board(powers: [GridPos(r: 0, c: 0): .bomb, GridPos(r: 0, c: 1): .cross])
        #expect(Match3Finder.isValidSwap(pair, GridPos(r: 0, c: 0), GridPos(r: 0, c: 1)))
    }

    @Test(arguments: 1...20)
    func swapAgreesWithTheMoveFinder(seed: Int) {
        let start = Match3State.newGame(colors: 6, ice: 6, seed: UInt64(seed))
        for a in Match3Board().positions {
            for d in [GridPos(r: a.r, c: a.c + 1), GridPos(r: a.r + 1, c: a.c)] where start.board.contains(d) {
                var s = start
                let turn = s.swap(a, d)
                #expect((turn != nil) == Match3Finder.isValidSwap(start.board, a, d))
                if turn == nil { #expect(s == start) }
            }
        }
    }

    // MARK: Turns

    @Test(arguments: 1...40)
    func newBoardsAreStillAndPlayable(seed: Int) {
        let s = Match3State.newGame(colors: 6, ice: 8, crystalChance: 0.1, seed: UInt64(seed))
        #expect(Match3Finder.matches(in: s.board).isEmpty)
        #expect(s.hasMoves)
        let frozen = Match3Board().positions.filter { s.board[$0]?.ice ?? 0 > 0 }
        #expect(frozen.count == 8)
        #expect(frozen.allSatisfy { $0.r >= 2 && s.board[$0]?.ice == 2 })
    }

    @Test func matchingThroughIceCracksOneLayer() {
        let gems = row(4, 0...1).merging([GridPos(r: 3, c: 2): .red]) { a, _ in a }
        var s = state(board(gems, ice: [GridPos(r: 4, c: 0)]))
        let turn = s.swap(GridPos(r: 3, c: 2), GridPos(r: 4, c: 2))
        let clear = turn?.steps.first { $0.kind == .clear }
        #expect(clear?.cracked == [GridPos(r: 4, c: 0)])
        #expect(clear?.board[GridPos(r: 4, c: 0)]?.ice == 1)
        #expect(clear?.bursts.count == 2)
    }

    @Test func bombBlastsThreeByThreeAndBreaksIce() {
        let center = GridPos(r: 4, c: 4)
        var s = state(board(ice: [GridPos(r: 5, c: 5)], powers: [center: .bomb]))
        let turn = s.finale()
        let clear = turn.steps.first { $0.kind == .clear }!
        #expect(clear.blasts.map(\.power) == [.bomb])
        #expect(clear.bursts.count == 8)
        #expect(clear.cracked == [GridPos(r: 5, c: 5)])
        #expect(clear.board[GridPos(r: 5, c: 5)]?.ice == 0)
    }

    @Test func crossClearsItsRowAndColumn() {
        var s = state(board(powers: [GridPos(r: 2, c: 6): .cross]))
        let clear = s.finale().steps.first { $0.kind == .clear }!
        #expect(Set(clear.bursts.map(\.at)) == Set(Match3Board().positions.filter { $0.r == 2 || $0.c == 6 }))
    }

    @Test func lightningClearsTheColourItIsSwappedWith() {
        let bolt = GridPos(r: 4, c: 4), partner = GridPos(r: 4, c: 5)
        let b = board(powers: [bolt: .lightning])
        let color = b[partner]!.color!
        var s = state(b)
        let turn = s.swap(bolt, partner)!
        let clear = turn.steps.first { $0.kind == .clear }!
        let expected = Set(Match3Board().positions.filter { b[$0]?.color == color })
        // After the swap the bolt sits where the partner was, and vice versa.
        #expect(Set(clear.bursts.map(\.at)) == expected.subtracting([partner]).union([bolt, partner]))
    }

    @Test func twoBombsBlastFiveByFive() {
        let a = GridPos(r: 4, c: 3), b = GridPos(r: 4, c: 4)
        var s = state(board(powers: [a: .bomb, b: .bomb]))
        let clear = s.swap(a, b)!.steps.first { $0.kind == .clear }!
        #expect(clear.bursts.count == 25)
        #expect(clear.blasts.first?.big == true)
    }

    @Test func blastsSetOffOtherPowers() {
        var s = state(board(powers: [GridPos(r: 4, c: 4): .bomb, GridPos(r: 4, c: 5): .cross]))
        let clear = s.finale().steps.first { $0.kind == .clear }!
        #expect(Set(clear.blasts.map(\.power)) == [.bomb, .cross])
    }

    @Test func finaleLeavesNoPowers() {
        var s = state(board(powers: [GridPos(r: 0, c: 0): .bomb, GridPos(r: 7, c: 7): .cross, GridPos(r: 3, c: 3): .lightning]))
        let turn = s.finale()
        #expect(turn.points > 0)
        #expect(!s.board.cells.contains { ($0?.power ?? GemPower.none) != GemPower.none })
    }

    @Test(arguments: 1...10)
    func shuffleLeavesAPlayableStillBoard(seed: Int) {
        var s = Match3State.newGame(colors: 6, ice: 10, seed: UInt64(seed))
        let frozen = Match3Board().positions.filter { s.board[$0]?.ice ?? 0 > 0 }
        _ = s.shuffle()
        #expect(Match3Finder.matches(in: s.board).isEmpty)
        #expect(s.hasMoves)
        #expect(frozen.allSatisfy { s.board[$0]?.ice == 2 })
    }

    // MARK: Shapes

    @Test func holesBreakLines() {
        // Three reds in row 3 with a hole between the second and third.
        var b = Match3Board(layout: ["oooooooo", "oooooooo", "oooooooo", "oo.ooooo", "oooooooo"])
        let filler: [GemColor] = [.yellow, .green, .blue, .purple]
        for p in b.positions { b[p] = Gem(id: p.r * 8 + p.c, color: filler[(p.r + p.c) % 4]) }
        for c in [0, 1, 3] { b[GridPos(r: 3, c: c)] = Gem(id: 100 + c, color: .red) }
        #expect(Match3Finder.matches(in: b).isEmpty)
        #expect(b[GridPos(r: 3, c: 2)] == nil)
        b[GridPos(r: 3, c: 2)] = Gem(id: 99, color: .red)
        #expect(b[GridPos(r: 3, c: 2)] == nil, "a hole never holds a gem")
    }

    @Test func gemsFallPastHoles() {
        // Column 0 has a hole at row 2. A cross in column 2 clears row 3, so
        // the two gems above the hole drop past it and a new one fills the top.
        let shape = Match3Board(layout: ["ooo", "ooo", ".oo", "ooo"])
        var s = Match3State.newGame(shape: shape, colors: 4, assist: 0, seed: 3)
        let top = s.board[GridPos(r: 0, c: 0)]!.id, middle = s.board[GridPos(r: 1, c: 0)]!.id
        s.board[GridPos(r: 3, c: 2)]?.power = .cross
        let fall = s.finale().steps.first { $0.kind == .fall }!
        #expect(fall.board[GridPos(r: 3, c: 0)]?.id == middle)
        #expect(fall.board[GridPos(r: 1, c: 0)]?.id == top)
        #expect(fall.board[GridPos(r: 2, c: 0)] == nil)
        #expect(fall.board[GridPos(r: 0, c: 0)] != nil)
    }

    @Test(arguments: 1...24)
    func arcadeLevelsDealPlayableBoards(level: Int) {
        let arcade = Match3ArcadeLevel(number: level)
        #expect(arcade.crystalsNeeded > 0 && arcade.moves > 0)
        for seed in 1...5 {
            let s = arcade.newGame(seed: UInt64(seed))
            #expect(s.board.positions.count == arcade.shape.positions.count)
            #expect(!s.board.positions.contains { s.board[$0] == nil })
            #expect(Match3Finder.matches(in: s.board).isEmpty)
            #expect(s.hasMoves)
            #expect(arcade.frozen.allSatisfy { s.board[$0]?.ice == 2 })
        }
    }

    @Test func arcadeComesRoundWithBiggerGoals() {
        let count = Match3ArcadeLevel.plans.count
        let first = Match3ArcadeLevel(number: 3)
        let again = Match3ArcadeLevel(number: count + 1)
        #expect(again.plan.layout == first.plan.layout)
        #expect(again.crystalsNeeded == first.crystalsNeeded + 1)
        #expect(Match3ArcadeLevel(number: 1).colors == 4)
    }

    // MARK: Race

    @Test func raceReportsOnlyGrowAndRankPlayers() throws {
        var race = Match3RaceState.newGame(players: 3, seed: 7)
        race = try race.applying(.report(score: 500, level: 2, finished: false), by: 0)
        race = try race.applying(.report(score: 300, level: 1, finished: false), by: 0)
        #expect(race.scores[0] == 500 && race.levels[0] == 2)
        race = try race.applying(.report(score: 900, level: 3, finished: true), by: 1)
        #expect(throws: Match3RaceState.RuleError.alreadyFinished) {
            try race.applying(.report(score: 1000, level: 3, finished: true), by: 1)
        }
        #expect(race.isOut(1) && !race.isOut(0))
        #expect(race.result(for: 0, names: ["A", "B", "C"]) == nil)
        race = try race.applying(.report(score: 500, level: 2, finished: true), by: 0)
        race = try race.applying(.report(score: 500, level: 2, finished: true), by: 2)
        #expect(race.isFinished)
        #expect(race.standings == [1, 0, 2])
        #expect(race.result(for: 1, names: ["A", "B", "C"])?.won == true)
        // Equal scores share second place.
        #expect(race.place(of: 0) == 2 && race.place(of: 2) == 2)
        #expect(race.result(for: 0, names: ["A", "B", "C"])?.won == false)
    }

    // MARK: Simulation

    /// A bot plays random valid moves; every turn must leave a full, still
    /// board, cascades must score their multiplier, and casual runs must end.
    @Test func casualRunsStaySaneAndEnd() {
        var lengths: [Int] = []
        var scores: [Int] = []
        for seed in 1...30 {
            var s = Match3Casual.newGame(seed: UInt64(seed))
            var bot = Match3Random(seed: UInt64(seed) &* 7919)
            var score = 0
            var moves = 0
            while moves < 3000 {
                let options = Match3Board().positions.flatMap { a in
                    [GridPos(r: a.r, c: a.c + 1), GridPos(r: a.r + 1, c: a.c)]
                        .filter { s.board.contains($0) && Match3Finder.isValidSwap(s.board, a, $0) }
                        .map { (a, $0) }
                }
                guard let (a, b) = options.randomElement(using: &bot) else { break }
                guard let turn = s.swap(a, b) else {
                    Issue.record("valid swap refused")
                    break
                }
                for step in turn.steps where step.kind == .clear {
                    #expect(step.points % min(max(step.cascade, 1), Match3State.maxMultiplier) == 0)
                }
                #expect(!s.board.cells.contains { $0 == nil })
                #expect(Match3Finder.matches(in: s.board).isEmpty)
                score += turn.points
                s.assist = Match3Casual.assist(forScore: score)
                s.iceChance = Match3Casual.iceChance(forScore: score)
                moves += 1
            }
            lengths.append(moves)
            scores.append(score)
        }
        lengths.sort()
        scores.sort()
        print("Gems casual, random bot: median \(lengths[15]) moves (\(lengths.first!)…\(lengths.last!)), median score \(scores[15])")
        #expect(lengths[15] < 3000, "most casual runs should get stuck eventually")
    }
}
