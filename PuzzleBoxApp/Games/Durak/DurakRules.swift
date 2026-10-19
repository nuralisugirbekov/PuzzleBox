import Foundation

// "Podkidnoy" Durak for two to six players with a 36-card deck. The state is
// a plain value so the bot game and an online match (where it is stored in
// Firestore) run the exact same rules.
//
// Turns are strict so every device agrees on who acts. While a card on the
// table is unbeaten the defender acts. Otherwise the attackers may throw in,
// one at a time in order: the main attacker first, then everyone else
// clockwise. Each may throw in a card or pass; once every attacker has passed
// since the last beaten card, the bout is over ("bito"). Attackers with no
// card to throw in pass automatically.
//
// Two optional rules, chosen before the game (`DurakOptions`):
// - Transfer: before beating anything, the defender may add a card of the
//   rank on the table and pass the whole attack on to the next player.
// - Bluffing: a card may be played against the rules (a defence that doesn't
//   beat, a throw-in of a rank not on the table). Nothing marks it. Until the
//   bout ends any other player may call it by tapping the card: a real bluff
//   sends the whole table to the bluffer, a wrong call sends it to the caller.
//   Bouts never close by themselves, so a bluff is always on the table long
//   enough to be called.

/// Optional rules, fixed for a whole game.
struct DurakOptions: Codable, Equatable {
    var transfer = false
    var bluff = false

    static let transferKey = "durak.transfer"
    static let bluffKey = "durak.bluff"

    /// The player's last choice in the game picker.
    static var saved: DurakOptions {
        DurakOptions(transfer: UserDefaults.standard.bool(forKey: transferKey),
                     bluff: UserDefaults.standard.bool(forKey: bluffKey))
    }
}

enum DurakAction: Codable, Equatable {
    /// Lead a bout, or throw in a card whose rank is already on the table.
    case attack(Card)
    /// Beat the unbeaten card on the table.
    case defend(Card)
    /// Defender gives up and picks up the table.
    case take
    /// An attacker passes; when everyone has, the cards are discarded ("bito").
    case done
    /// Defender passes the attack on with a card of the same rank.
    case transfer(Card)
    /// Calls the card on the table a bluff. Allowed out of turn.
    case callBluff(Card)
}

struct DurakState: Codable, Equatable {
    struct Pair: Codable, Equatable {
        var attack: Card
        var defense: Card?
        /// Who played each card, and whether it broke the rules (bluffing only).
        var attackBy: Int?
        var defenseBy: Int?
        var attackBluff: Bool?
        var defenseBluff: Bool?
    }

    enum Outcome: Codable, Equatable {
        /// The last player left holding cards.
        case loser(Int)
        /// The last players ran out of cards in the same bout.
        case draw
    }

    enum RuleError: Error, Equatable {
        case gameOver, notYourTurn, illegalCard, illegalAction
    }

    static let handSize = 6
    static let maxAttacks = 6
    static let playerRange = 2...6

    var hands: [[Card]]
    /// Draws come off the end; the face-up trump card is the first element.
    var deck: [Card]
    let trumpSuit: Suit
    /// The face-up card under the deck, shown until it's drawn.
    let trumpCard: Card
    var table: [Pair] = []
    /// The main attacker, who leads the bout.
    var attacker: Int
    /// The player the bout is played against: the next one still in after the attacker.
    var defender: Int
    var discarded = 0
    /// The discarded cards themselves, for the face-down "bito" pile. Optional
    /// so tables saved before it existed still decode.
    var discardPile: [Card]?
    /// Attacks allowed this bout: six, or fewer if the defender started it with fewer cards.
    var boutLimit = DurakState.maxAttacks
    /// Attackers who passed since the last card was beaten.
    var passed: [Int] = []
    /// Players who got rid of their cards, in the order they went out.
    var finished: [Int] = []
    var outcome: Outcome?
    /// Seat that made the latest move and what it was, for the other players' screens.
    var lastMove: LastMove?
    /// Optional rules; nil in tables saved before they existed.
    var rules: DurakOptions?

    struct LastMove: Codable, Equatable {
        let seat: Int
        let action: DurakAction
        /// For a bluff call: whose card was called, and whether it was a bluff.
        var target: Int?
        var caught: Bool?
    }

    init(hands: [[Card]], deck: [Card], trumpSuit: Suit, trumpCard: Card, attacker: Int,
         options: DurakOptions = DurakOptions()) {
        self.hands = hands
        self.deck = deck
        self.trumpSuit = trumpSuit
        self.trumpCard = trumpCard
        self.attacker = attacker
        defender = attacker
        rules = options
        defender = nextActive(after: attacker)
    }

    var options: DurakOptions { rules ?? DurakOptions() }
    var playerCount: Int { hands.count }

    func isOut(_ seat: Int) -> Bool { finished.contains(seat) }

    /// The next seat clockwise that is still in the game.
    func nextActive(after seat: Int) -> Int {
        var next = seat
        for _ in 0..<playerCount {
            next = (next + 1) % playerCount
            if !isOut(next) { return next }
        }
        return seat
    }

    /// Who may throw in, in order: the main attacker, then the others clockwise.
    var throwOrder: [Int] {
        var order: [Int] = []
        var seat = attacker
        for _ in 0..<playerCount {
            if seat != defender && !isOut(seat) && !order.contains(seat) { order.append(seat) }
            seat = (seat + 1) % playerCount
        }
        return order
    }

    /// The seat expected to act, or nil once the game is over.
    var turn: Int? {
        guard outcome == nil else { return nil }
        if table.isEmpty { return attacker }
        if table.contains(where: { $0.defense == nil }) { return defender }
        return throwOrder.first { !passed.contains($0) }
    }

    var unbeaten: Card? { table.first { $0.defense == nil }?.attack }

    // MARK: Dealing

    static func deck36() -> [Card] {
        Suit.allCases.flatMap { suit in ([1] + Array(6...13)).map { Card(suit: suit, rank: $0) } }
    }

    /// A fresh shuffled deal. The player holding the lowest trump leads.
    static func deal<G: RandomNumberGenerator>(players: Int = 2, options: DurakOptions = DurakOptions(),
                                               using generator: inout G) -> DurakState {
        let players = min(max(players, playerRange.lowerBound), playerRange.upperBound)
        var deck = deck36().shuffled(using: &generator)
        // With six players the whole deck is dealt; the trump is still its bottom card.
        let trump = deck[0]
        var hands = Array(repeating: [Card](), count: players)
        for _ in 0..<handSize {
            for seat in 0..<players { hands[seat].append(deck.removeLast()) }
        }
        func lowestTrump(_ seat: Int) -> Int {
            hands[seat].filter { $0.suit == trump.suit }.map(\.highValue).min() ?? .max
        }
        let lowest = (0..<players).map(lowestTrump)
        let first: Int
        if let best = lowest.min(), best != .max, let seat = lowest.firstIndex(of: best) {
            first = seat
        } else {
            first = Int.random(in: 0..<players, using: &generator)
        }
        return DurakState(hands: hands, deck: deck, trumpSuit: trump.suit, trumpCard: trump,
                          attacker: first, options: options)
    }

    static func deal(players: Int = 2, options: DurakOptions = DurakOptions()) -> DurakState {
        var generator = SystemRandomNumberGenerator()
        return deal(players: players, options: options, using: &generator)
    }

    // MARK: Rules

    func isTrump(_ card: Card) -> Bool { card.suit == trumpSuit }

    /// Ordering used for "cheapest card" choices: trumps above everything else.
    func strength(_ card: Card) -> Int { (isTrump(card) ? 100 : 0) + card.highValue }

    func beats(_ defense: Card, _ attack: Card) -> Bool {
        if defense.suit == attack.suit { return defense.highValue > attack.highValue }
        return isTrump(defense) && !isTrump(attack)
    }

    private var ranksOnTable: Set<Int> {
        Set(table.flatMap { [$0.attack.rank] + ($0.defense.map { [$0.rank] } ?? []) })
    }

    /// Whether `seat` could legally put `card` on the table if it were their turn.
    private func canThrow(_ card: Card, by seat: Int) -> Bool {
        guard seat != defender, hands[seat].contains(card) else { return false }
        if table.isEmpty { return seat == attacker }
        guard table.count < boutLimit else { return false }
        return ranksOnTable.contains(card.rank)
    }

    /// Whether the player on turn may legally attack with `card` now.
    func canAttack(with card: Card) -> Bool {
        guard let turn, turn != defender || table.isEmpty else { return false }
        return canThrow(card, by: turn)
    }

    func canDefend(with card: Card) -> Bool {
        guard turn == defender, hands[defender].contains(card), let target = unbeaten else { return false }
        return beats(card, target)
    }

    /// With bluffing on: whether the player on turn may play `card` at all,
    /// within the rules or not.
    func canPlay(_ card: Card) -> Bool {
        if canAttack(with: card) || canDefend(with: card) { return true }
        guard options.bluff, let turn, hands[turn].contains(card), !table.isEmpty else { return false }
        if turn == defender && unbeaten != nil { return true }
        return turn != defender && table.count < boutLimit
    }

    /// The defender may pass the attack on with `card`: nothing beaten yet,
    /// every card on the table of its rank, and the next player holding
    /// enough cards to answer them all.
    func canTransfer(with card: Card) -> Bool {
        guard options.transfer, turn == defender, hands[defender].contains(card), !table.isEmpty,
              table.allSatisfy({ $0.defense == nil && $0.attack.rank == card.rank }) else { return false }
        let next = nextActive(after: defender)
        return next != defender && table.count + 1 <= min(Self.maxAttacks, hands[next].count)
    }

    /// The player who put `card` on the table, if it is there.
    func owner(of card: Card) -> Int? {
        for pair in table {
            if pair.attack.id == card.id { return pair.attackBy }
            if pair.defense?.id == card.id { return pair.defenseBy }
        }
        return nil
    }

    /// Whether `seat` may call `card` a bluff: bluffing is on, the card is on
    /// the table and someone else played it.
    func canCall(_ card: Card, by seat: Int) -> Bool {
        guard options.bluff, outcome == nil, !isOut(seat), let owner = owner(of: card) else { return false }
        return owner != seat
    }

    /// Every action `seat` may take right now within the rules (no bluffs, no calls).
    func legalActions(for seat: Int) -> [DurakAction] {
        guard turn == seat else { return [] }
        if seat == defender && !table.isEmpty {
            return hands[seat].filter(canDefend).map(DurakAction.defend)
                + hands[seat].filter(canTransfer).map(DurakAction.transfer) + [.take]
        }
        var actions = hands[seat].filter(canAttack).map(DurakAction.attack)
        if !table.isEmpty { actions.append(.done) }
        return actions
    }

    func applying(_ action: DurakAction, by seat: Int) throws -> DurakState {
        var next = self
        try next.apply(action, by: seat)
        return next
    }

    mutating func apply(_ action: DurakAction, by seat: Int) throws {
        guard outcome == nil else { throw RuleError.gameOver }
        if case .callBluff(let card) = action {
            try call(card, by: seat)
            return
        }
        guard turn == seat else { throw RuleError.notYourTurn }
        let defending = seat == defender && !table.isEmpty
        switch action {
        case .attack(let card):
            guard !defending else { throw RuleError.illegalAction }
            let legal = canAttack(with: card)
            guard legal || canPlay(card) else { throw RuleError.illegalCard }
            if table.isEmpty { boutLimit = min(Self.maxAttacks, hands[defender].count) }
            remove(card, from: seat)
            table.append(Pair(attack: card, attackBy: seat, attackBluff: !legal))
        case .defend(let card):
            guard defending else { throw RuleError.illegalAction }
            let legal = canDefend(with: card)
            guard legal || canPlay(card), let index = table.firstIndex(where: { $0.defense == nil })
            else { throw RuleError.illegalCard }
            remove(card, from: seat)
            table[index].defense = card
            table[index].defenseBy = seat
            table[index].defenseBluff = !legal
            // Everyone may throw in again after a beaten card.
            passed = []
            settle()
        case .transfer(let card):
            guard defending, canTransfer(with: card) else { throw RuleError.illegalCard }
            remove(card, from: seat)
            table.append(Pair(attack: card, attackBy: seat, attackBluff: false))
            attacker = seat
            defender = nextActive(after: seat)
            boutLimit = min(Self.maxAttacks, hands[defender].count)
            passed = []
        case .take:
            guard defending else { throw RuleError.illegalAction }
            endBout(collector: defender)
        case .done:
            guard !defending, !table.isEmpty else { throw RuleError.illegalAction }
            passed.append(seat)
            settle()
        case .callBluff:
            break
        }
        lastMove = LastMove(seat: seat, action: action)
    }

    /// A call ends the bout: the table goes to the bluffer, or to the caller
    /// if the card was fair.
    private mutating func call(_ card: Card, by seat: Int) throws {
        guard canCall(card, by: seat), let owner = owner(of: card) else { throw RuleError.illegalAction }
        let pair = table.first { $0.attack.id == card.id || $0.defense?.id == card.id }
        let bluff = pair?.attack.id == card.id ? pair?.attackBluff == true : pair?.defenseBluff == true
        endBout(collector: bluff ? owner : seat)
        lastMove = LastMove(seat: seat, action: .callBluff(card), target: owner, caught: bluff)
    }

    /// With every card beaten, passes for attackers who have nothing to throw
    /// in, and closes the bout once nobody is left to throw in. With bluffing
    /// on, attackers always decide for themselves, so a bluff stays callable.
    private mutating func settle() {
        guard !table.isEmpty, !table.contains(where: { $0.defense == nil }) else { return }
        if options.bluff {
            if throwOrder.allSatisfy(passed.contains) { endBout(collector: nil) }
            return
        }
        while let next = throwOrder.first(where: { !passed.contains($0) }) {
            if hands[next].contains(where: { canThrow($0, by: next) }) { return }
            passed.append(next)
        }
        endBout(collector: nil)
    }

    private mutating func remove(_ card: Card, from seat: Int) {
        hands[seat].removeAll { $0.id == card.id }
    }

    /// Clears the table into `collector`'s hand (a pick-up or a bluff call),
    /// or onto the bito pile when nil, then refills hands and passes the lead.
    private mutating func endBout(collector: Int?) {
        let cards = table.flatMap { [$0.attack] + ($0.defense.map { [$0] } ?? []) }
        let drawOrder = throwOrder + [defender]
        table.removeAll()
        passed = []
        if let collector {
            hands[collector].append(contentsOf: cards)
        } else {
            discarded += cards.count
            discardPile = (discardPile ?? []) + cards
        }
        // Attackers refill first, the main attacker leading; the defender last.
        for seat in drawOrder {
            while hands[seat].count < Self.handSize, let card = deck.popLast() {
                hands[seat].append(card)
            }
        }
        if deck.isEmpty {
            for seat in drawOrder where hands[seat].isEmpty && !isOut(seat) {
                finished.append(seat)
            }
        }
        let remaining = (0..<playerCount).filter { !isOut($0) }
        switch remaining.count {
        case 0: outcome = .draw
        case 1: outcome = .loser(remaining[0])
        default: break
        }
        guard outcome == nil else { return }
        // The defender leads next unless they picked the table up.
        let previousDefender = defender
        if collector != previousDefender && !isOut(previousDefender) {
            attacker = previousDefender
        } else {
            attacker = nextActive(after: previousDefender)
        }
        defender = nextActive(after: attacker)
    }
}

// MARK: - Display

extension DurakState {
    /// When `next` is a defence that also closed the bout, the table between
    /// the two: the beating card in place and nothing cleared yet. Shown for a
    /// moment so the player sees which card beat theirs before it goes to bito.
    func revealingDefense(before next: DurakState) -> DurakState? {
        guard let move = next.lastMove, case .defend(let card) = move.action,
              next.table.isEmpty, let index = table.firstIndex(where: { $0.defense == nil })
        else { return nil }
        var shown = self
        shown.hands[move.seat].removeAll { $0.id == card.id }
        shown.table[index].defense = card
        shown.lastMove = move
        return shown
    }
}

// MARK: - Bot

enum DurakBot {
    /// How often a bot bluffs instead of picking up, or throws in a card it
    /// shouldn't; and how often it notices someone else's bluff.
    static let bluffChance = 0.3
    static let throwInBluffChance = 0.1
    static let catchChance = 0.45

    /// A simple, reasonable opponent: lead and beat with the cheapest card,
    /// save trumps while the deck is large, and pick up rather than spend a
    /// high trump early. With the optional rules it passes attacks on with a
    /// spare card, and now and then bluffs.
    static func action<G: RandomNumberGenerator>(for state: DurakState, seat: Int,
                                                 using generator: inout G) -> DurakAction? {
        guard state.turn == seat else { return nil }
        let hand = state.hands[seat].sorted { state.strength($0) < state.strength($1) }
        let deckIsLarge = state.deck.count > 6

        if seat == state.defender && !state.table.isEmpty {
            guard let target = state.unbeaten else { return .take }
            // Pass the attack on with a non-trump rather than spend a card.
            if let pass = hand.first(where: { !state.isTrump($0) && state.canTransfer(with: $0) }) {
                return .transfer(pass)
            }
            let card = hand.first(where: { state.beats($0, target) })
            let spendsBigTrump = card.map { state.isTrump($0) && !state.isTrump(target) && $0.highValue >= 12 } ?? false
            if let card, !(spendsBigTrump && deckIsLarge && state.table.count <= 2) {
                return .defend(card)
            }
            // Can't (or won't) beat it: maybe cover it with the cheapest card and hope.
            if state.options.bluff, let cheap = hand.first, Double.random(in: 0..<1, using: &generator) < bluffChance {
                return .defend(cheap)
            }
            return .take
        }

        let playable = hand.filter(state.canAttack)
        if state.table.isEmpty {
            // Lead the cheapest card, preferring a rank we hold twice.
            let counts = Dictionary(grouping: hand.filter { !state.isTrump($0) }, by: \.rank)
            if let pair = hand.first(where: { !state.isTrump($0) && (counts[$0.rank]?.count ?? 0) > 1 && $0.highValue <= 10 }) {
                return .attack(pair)
            }
            return playable.first.map(DurakAction.attack)
        }
        // Throw in cheap non-trumps; trumps and picture cards only once the deck is gone.
        if let extra = playable.first(where: { deckIsLarge ? (!state.isTrump($0) && $0.highValue <= 11) : true }) {
            return .attack(extra)
        }
        if state.options.bluff, let cheap = hand.first(where: { !state.isTrump($0) && $0.highValue <= 9 }),
           state.canPlay(cheap), Double.random(in: 0..<1, using: &generator) < throwInBluffChance {
            return .attack(cheap)
        }
        return .done
    }

    static func action(for state: DurakState, seat: Int) -> DurakAction? {
        var generator = SystemRandomNumberGenerator()
        return action(for: state, seat: seat, using: &generator)
    }

    /// Whether bot `seat` notices that `card` is a bluff. Bots only ever call
    /// real bluffs, and miss them often.
    static func notices<G: RandomNumberGenerator>(_ card: Card, in state: DurakState, by seat: Int,
                                                  using generator: inout G) -> Bool {
        guard state.canCall(card, by: seat),
              let pair = state.table.first(where: { $0.attack.id == card.id || $0.defense?.id == card.id }) else { return false }
        let bluff = pair.attack.id == card.id ? pair.attackBluff == true : pair.defenseBluff == true
        return bluff && Double.random(in: 0..<1, using: &generator) < catchChance
    }
}
