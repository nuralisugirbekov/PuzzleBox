import Foundation

/// Rules of Togyzkumalak ("nine pebbles") for two players, with a shortened variant.
///
/// The board is a ring of `2 × n` pits. Indices `0..<n` are the bottom player's pits
/// (left to right) and `n..<2n` the top player's pits in the same counter-clockwise
/// order, so sowing simply walks the indices upward and wraps around.
struct TogyzBoard: Equatable {
    enum Side: Int { case bottom = 0, top = 1
        var other: Side { self == .bottom ? .top : .bottom }
    }

    /// Classic: 9 pits of 9 pebbles, tuzdyks, 82 to win. Quick: 6 pits of 5 pebbles, no tuzdyks, 31 to win.
    struct Rules: Equatable {
        let pits: Int
        let start: Int
        let tuzdyksEnabled: Bool
        var total: Int { pits * 2 * start }
        var winning: Int { total / 2 + 1 }
        static let classic = Rules(pits: 9, start: 9, tuzdyksEnabled: true)
        static let quick = Rules(pits: 6, start: 5, tuzdyksEnabled: false)
    }

    let rules: Rules
    var pits: [Int]
    var kazan = [0, 0]
    /// Index of the pit each side owns as a tuzdyk (located on the other side), if any.
    var tuzdyk: [Int?] = [nil, nil]
    var turn: Side = .bottom

    init(rules: Rules) {
        self.rules = rules
        pits = Array(repeating: rules.start, count: rules.pits * 2)
    }

    var n: Int { rules.pits }
    func side(of index: Int) -> Side { index < n ? .bottom : .top }
    /// Pit number from its owner's point of view, 1 ... n.
    func number(of index: Int) -> Int { index % n + 1 }
    func pitIndexes(of side: Side) -> Range<Int> { side == .bottom ? 0..<n : n..<(2 * n) }
    func isTuzdyk(_ index: Int) -> Side? {
        if tuzdyk[0] == index { return .bottom }
        if tuzdyk[1] == index { return .top }
        return nil
    }

    func legalMoves(for side: Side) -> [Int] { pitIndexes(of: side).filter { pits[$0] > 0 } }

    struct Outcome {
        /// Pits that received a pebble, in order (a pebble dropped into a tuzdyk still lists its pit).
        var drops: [Int] = []
        var last = 0
        var captured = 0
        var newTuzdyk: Int?
    }

    /// Plays `index` for the side to move and passes the turn. Returns nil if the move is illegal.
    @discardableResult
    mutating func play(_ index: Int) -> Outcome? {
        guard pits.indices.contains(index), side(of: index) == turn, pits[index] > 0 else { return nil }
        let mover = turn
        var outcome = Outcome()
        let count = pits[index]
        pits[index] = 0
        // One pebble moves on to the next pit; more are sown starting in the same pit.
        let first = count == 1 ? (index + 1) % (2 * n) : index
        var position = first
        for _ in 0..<count {
            outcome.drops.append(position)
            if let owner = isTuzdyk(position) { kazan[owner.rawValue] += 1 } else { pits[position] += 1 }
            outcome.last = position
            position = (position + 1) % (2 * n)
        }
        let last = outcome.last
        if side(of: last) != mover, isTuzdyk(last) == nil {
            if pits[last] % 2 == 0 {
                outcome.captured = pits[last]
                kazan[mover.rawValue] += pits[last]
                pits[last] = 0
            } else if rules.tuzdyksEnabled, pits[last] == 3, canMakeTuzdyk(at: last, for: mover) {
                tuzdyk[mover.rawValue] = last
                kazan[mover.rawValue] += 3
                pits[last] = 0
                outcome.captured = 3
                outcome.newTuzdyk = last
            }
        }
        turn = mover.other
        return outcome
    }

    /// A tuzdyk cannot be the last pit, mirror an existing one, or be a second for the same player.
    private func canMakeTuzdyk(at index: Int, for mover: Side) -> Bool {
        guard tuzdyk[mover.rawValue] == nil, number(of: index) != n else { return false }
        if let theirs = tuzdyk[mover.other.rawValue], number(of: theirs) == number(of: index) { return false }
        return true
    }

    var isOver: Bool { winner != nil || isDraw }

    var isDraw: Bool { kazan[0] == kazan[1] && kazan[0] * 2 == rules.total && pitsAreEmpty }
    private var pitsAreEmpty: Bool { pits.allSatisfy { $0 == 0 } }

    /// Settles the game when it is over: the side to move having no pebbles hands the rest to the opponent.
    mutating func finishIfStuck() {
        if kazan[0] >= rules.winning || kazan[1] >= rules.winning { return }
        guard legalMoves(for: turn).isEmpty else { return }
        for index in pits.indices where pits[index] > 0 {
            kazan[side(of: index).rawValue] += pits[index]
            pits[index] = 0
        }
    }

    var winner: Side? {
        if kazan[0] >= rules.winning { return .bottom }
        if kazan[1] >= rules.winning { return .top }
        if pitsAreEmpty { return kazan[0] > kazan[1] ? .bottom : kazan[1] > kazan[0] ? .top : nil }
        return nil
    }

    var pebblesInPlay: Int { pits.reduce(0, +) }

    // MARK: Computer opponent

    /// Static score from `side`'s point of view.
    func evaluate(for side: Side) -> Int {
        let me = side.rawValue, you = side.other.rawValue
        var score = (kazan[me] - kazan[you]) * 10
        if tuzdyk[me] != nil { score += 30 + (tuzdyk[me].map { n - number(of: $0) } ?? 0) * 2 }
        if tuzdyk[you] != nil { score -= 30 }
        // Pebbles on your own side are a mild reserve for later; the opponent's side is a risk.
        for index in pits.indices {
            score += (self.side(of: index) == side ? 1 : -1) * pits[index]
        }
        return score
    }

    /// Negamax with alpha-beta pruning; returns the best pit for the side to move.
    /// `randomness` adds noise to each move's score so weaker levels make human-like slips.
    func bestMove(depth: Int, randomness: Int = 0) -> Int? {
        let moves = legalMoves(for: turn)
        guard !moves.isEmpty else { return nil }
        var scored: [(move: Int, score: Int)] = []
        for move in moves {
            var next = self
            next.play(move)
            let value = -next.negamax(depth: depth - 1, alpha: -Self.infinity, beta: Self.infinity)
            scored.append((move, value + (randomness > 0 ? Int.random(in: 0...randomness) : 0)))
        }
        let top = scored.map(\.score).max() ?? 0
        return scored.filter { $0.score == top }.randomElement()?.move
    }

    private static let infinity = 1_000_000

    /// Score from the point of view of the side to move at this node.
    private func negamax(depth: Int, alpha: Int, beta: Int) -> Int {
        var node = self
        node.finishIfStuck()
        if let winner = node.winner { return winner == node.turn ? 100_000 : -100_000 }
        if node.isDraw { return 0 }
        let moves = node.legalMoves(for: node.turn)
        if depth <= 0 || moves.isEmpty { return node.evaluate(for: node.turn) }
        var best = -Self.infinity
        var a = alpha
        for move in moves {
            var next = node
            next.play(move)
            best = max(best, -next.negamax(depth: depth - 1, alpha: -beta, beta: -a))
            a = max(a, best)
            if a >= beta { break }
        }
        return best
    }
}
