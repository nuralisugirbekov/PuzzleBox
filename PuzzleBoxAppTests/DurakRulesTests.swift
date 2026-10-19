import Foundation
import Testing
@testable import PuzzleBoxApp

/// Deterministic generator so dealt games are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@MainActor
struct DurakRulesTests {
    private func card(_ suit: Suit, _ rank: Int) -> Card { Card(suit: suit, rank: rank) }

    /// Hearts are trump; seat 0 attacks.
    private func state(hands: [[Card]], deck: [Card] = [], attacker: Int = 0,
                       options: DurakOptions = DurakOptions()) -> DurakState {
        let trump = deck.first ?? card(.hearts, 6)
        return DurakState(hands: hands, deck: deck, trumpSuit: .hearts, trumpCard: trump, attacker: attacker,
                          options: options)
    }

    @Test func dealGivesSixCardsEachAndATrump() {
        var generator = SeededGenerator(state: 42)
        let game = DurakState.deal(using: &generator)
        #expect(game.hands.map(\.count) == [6, 6])
        #expect(game.deck.count == 24)
        #expect(game.deck.first == game.trumpCard)
        #expect(game.trumpSuit == game.trumpCard.suit)
        #expect(Set((game.hands.flatMap { $0 } + game.deck).map(\.id)).count == 36)
    }

    @Test func beatingFollowsSuitOrTrump() {
        let game = state(hands: [[], []])
        #expect(game.beats(card(.spades, 9), card(.spades, 7)))
        #expect(!game.beats(card(.spades, 7), card(.spades, 9)))
        #expect(game.beats(card(.spades, 1), card(.spades, 13)), "Ace is high")
        #expect(!game.beats(card(.clubs, 13), card(.spades, 7)), "Off-suit can't beat")
        #expect(game.beats(card(.hearts, 6), card(.spades, 1)), "Any trump beats a non-trump")
        #expect(!game.beats(card(.hearts, 6), card(.hearts, 7)))
    }

    @Test func throwInOnlyMatchesRanksOnTable() throws {
        let attackCard = card(.spades, 7)
        let defenseCard = card(.spades, 10)
        var game = state(hands: [[attackCard, card(.clubs, 7), card(.clubs, 10), card(.clubs, 9)],
                                 [defenseCard, card(.diamonds, 8)]],
                         deck: [card(.hearts, 6)])
        try game.apply(.attack(attackCard), by: 0)
        #expect(game.turn == 1)
        #expect(throws: DurakState.RuleError.notYourTurn) { try game.applying(.done, by: 0) }
        try game.apply(.defend(defenseCard), by: 1)
        #expect(game.turn == 0)
        let hand = game.hands[0]
        #expect(hand.filter(game.canAttack).map(\.rank).sorted() == [7, 10])
    }

    @Test func takingKeepsTheLeadAndPicksUpTable() throws {
        let attackCard = card(.spades, 13)
        var game = state(hands: [[attackCard, card(.clubs, 8)], [card(.diamonds, 7), card(.clubs, 6)]],
                         deck: [card(.hearts, 6), card(.spades, 9), card(.diamonds, 9), card(.clubs, 11)])
        try game.apply(.attack(attackCard), by: 0)
        try game.apply(.take, by: 1)
        #expect(game.table.isEmpty)
        #expect(game.attacker == 0)
        #expect(game.hands[1].contains(attackCard))
        #expect(game.hands[0].count == 5, "Attacker refills from the deck")
    }

    @Test func beatenBoutPassesTheLead() throws {
        let attackCard = card(.spades, 7)
        let defenseCard = card(.spades, 8)
        var game = state(hands: [[attackCard, card(.clubs, 9)], [defenseCard, card(.diamonds, 10)]],
                         deck: [card(.hearts, 6), card(.clubs, 11), card(.diamonds, 11)])
        try game.apply(.attack(attackCard), by: 0)
        try game.apply(.defend(defenseCard), by: 1)
        // Nothing to throw in, so the bout closes by itself.
        #expect(game.table.isEmpty)
        #expect(game.discarded == 2)
        #expect(game.attacker == 1)
    }

    @Test func emptyHandWithEmptyDeckWins() throws {
        let attackCard = card(.spades, 7)
        let defenseCard = card(.spades, 8)
        var game = state(hands: [[attackCard], [defenseCard, card(.clubs, 9)]])
        try game.apply(.attack(attackCard), by: 0)
        try game.apply(.defend(defenseCard), by: 1)
        #expect(game.outcome == .loser(1))
        #expect(game.turn == nil)
    }

    @Test func attacksAreCappedByDefenderHand() throws {
        let sevens = [card(.spades, 7), card(.clubs, 7), card(.diamonds, 7)]
        let eights = [card(.spades, 8), card(.clubs, 8)]
        var game = state(hands: [sevens, eights],
                         deck: [card(.hearts, 6), card(.spades, 12)])
        try game.apply(.attack(sevens[0]), by: 0)
        try game.apply(.defend(eights[0]), by: 1)
        try game.apply(.attack(sevens[1]), by: 0)
        try game.apply(.defend(eights[1]), by: 1)
        // The defender started with two cards, so the third seven can't be thrown in.
        #expect(game.table.isEmpty, "Bout closed once the limit was reached")
        #expect(game.hands[0].contains(sevens[2]))
    }

    @Test(arguments: DurakState.playerRange)
    func botsFinishWholeGames(players: Int) throws {
        for seed in 1...100 {
            var generator = SeededGenerator(state: UInt64(seed))
            var game = DurakState.deal(players: players, using: &generator)
            var steps = 0
            while let seat = game.turn {
                let action = try #require(DurakBot.action(for: game, seat: seat))
                #expect(game.legalActions(for: seat).contains(action))
                try game.apply(action, by: seat)
                steps += 1
                try #require(steps < 2000, "Game \(seed) didn't finish")
            }
            #expect(game.outcome != nil)
            let total = game.hands.flatMap { $0 }.count + game.deck.count + game.discarded
            #expect(total == 36, "No card is lost or duplicated")
            if case .loser(let loser) = game.outcome {
                #expect(game.finished.count == players - 1)
                #expect(!game.finished.contains(loser))
            }
        }
    }

    // MARK: More than two players

    @Test(arguments: DurakState.playerRange)
    func dealSeatsEveryPlayer(players: Int) {
        var generator = SeededGenerator(state: 7)
        let game = DurakState.deal(players: players, using: &generator)
        #expect(game.hands.count == players)
        #expect(game.hands.allSatisfy { $0.count == 6 })
        #expect(game.deck.count == 36 - 6 * players)
        #expect(game.defender == (game.attacker + 1) % players)
        // With six players the whole deck is dealt, trump card included.
        if players == 6 { #expect(game.hands.joined().contains(game.trumpCard)) }
    }

    /// Three players, hearts trump: 0 attacks 1, and 2 may throw in too.
    private func threePlayers(_ hands: [[Card]], deck: [Card]) -> DurakState {
        state(hands: hands, deck: deck)
    }

    @Test func othersThrowInAfterTheMainAttackerPasses() throws {
        let lead = card(.spades, 7), beat = card(.spades, 9), extra = card(.clubs, 7), beatExtra = card(.clubs, 10)
        var game = threePlayers([[lead, card(.diamonds, 13)],
                                 [beat, beatExtra, card(.diamonds, 6)],
                                 [extra, card(.diamonds, 12)]],
                                deck: [card(.hearts, 6), card(.clubs, 6), card(.clubs, 8), card(.diamonds, 7)])
        #expect(game.defender == 1)
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        // Seat 0 has nothing to throw in and passes automatically: seat 2's turn.
        #expect(game.turn == 2)
        #expect(game.canAttack(with: extra))
        try game.apply(.attack(extra), by: 2)
        try game.apply(.defend(beatExtra), by: 1)
        // Nobody can throw in any more: bito, and the defender leads next.
        #expect(game.table.isEmpty)
        #expect(game.discarded == 4)
        #expect(game.attacker == 1)
        #expect(game.defender == 2)
    }

    @Test func passingByEveryAttackerEndsTheBout() throws {
        let lead = card(.spades, 7), beat = card(.spades, 9)
        var game = threePlayers([[lead, card(.clubs, 9)],
                                 [beat, card(.diamonds, 6)],
                                 [card(.clubs, 7), card(.spades, 12)]],
                                deck: [card(.hearts, 6), card(.clubs, 6), card(.clubs, 8), card(.diamonds, 7)])
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        #expect(game.turn == 0, "The main attacker can throw in the nine")
        try game.apply(.done, by: 0)
        #expect(game.turn == 2, "Then the next attacker clockwise")
        try game.apply(.done, by: 2)
        #expect(game.table.isEmpty)
        #expect(game.attacker == 1)
    }

    @Test func takingSkipsTheDefenderForTheNextLead() throws {
        let lead = card(.spades, 13)
        var game = threePlayers([[lead, card(.clubs, 8)],
                                 [card(.diamonds, 7)],
                                 [card(.clubs, 9)]],
                                deck: [card(.hearts, 6), card(.spades, 6), card(.diamonds, 9), card(.clubs, 11),
                                       card(.diamonds, 11), card(.clubs, 12), card(.spades, 8)])
        try game.apply(.attack(lead), by: 0)
        try game.apply(.take, by: 1)
        #expect(game.hands[1].contains(lead))
        #expect(game.attacker == 2, "The player after the defender leads")
        #expect(game.defender == 0)
    }

    @Test func playersGoOutAndTheLastHolderIsTheDurak() throws {
        let lead = card(.spades, 7), beat = card(.spades, 8)
        // Empty deck: seat 0 plays its last card, seat 1 beats with its last card.
        var game = threePlayers([[lead], [beat], [card(.clubs, 9), card(.clubs, 10)]], deck: [])
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        #expect(game.finished.sorted() == [0, 1])
        #expect(game.outcome == .loser(2))
    }

    @Test func aPlayerOutOfCardsIsSkipped() throws {
        let lead = card(.spades, 7), beat = card(.spades, 8)
        var game = state(hands: [[lead], [beat, card(.diamonds, 9)], [card(.clubs, 9)], [card(.clubs, 10)]], deck: [])
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        #expect(game.finished == [0])
        #expect(game.outcome == nil)
        #expect(game.attacker == 1)
        #expect(game.defender == 2)
        #expect(game.throwOrder == [1, 3])
    }

    // MARK: Transfers

    private let transfers = DurakOptions(transfer: true)
    private let bluffing = DurakOptions(bluff: true)
    private var spareDeck: [Card] { [card(.hearts, 6), card(.clubs, 6), card(.clubs, 8), card(.diamonds, 7)] }

    @Test func transferPassesTheAttackOn() throws {
        let lead = card(.spades, 7), pass = card(.clubs, 7)
        var game = state(hands: [[lead, card(.diamonds, 9)],
                                 [pass, card(.diamonds, 10)],
                                 [card(.spades, 9), card(.clubs, 9), card(.diamonds, 13)]],
                         deck: spareDeck, options: transfers)
        try game.apply(.attack(lead), by: 0)
        #expect(game.canTransfer(with: pass))
        try game.apply(.transfer(pass), by: 1)
        #expect(game.attacker == 1)
        #expect(game.defender == 2)
        #expect(game.turn == 2)
        #expect(game.table.map(\.attack) == [lead, pass])
    }

    @Test func transferNeedsTheOptionAndEnoughCards() throws {
        let lead = card(.spades, 7), pass = card(.clubs, 7)
        var off = state(hands: [[lead], [pass, card(.diamonds, 10)], [card(.spades, 9), card(.clubs, 9)]],
                        deck: spareDeck)
        try off.apply(.attack(lead), by: 0)
        #expect(!off.canTransfer(with: pass), "Transfers are off")
        // Seat 2 holds one card but would face two.
        var short = state(hands: [[lead], [pass, card(.diamonds, 10)], [card(.spades, 9)]],
                          deck: spareDeck, options: transfers)
        try short.apply(.attack(lead), by: 0)
        #expect(!short.canTransfer(with: pass))
        #expect(throws: DurakState.RuleError.illegalCard) { try short.applying(.transfer(pass), by: 1) }
    }

    @Test func noTransferOnceACardIsBeaten() throws {
        let sevens = [card(.spades, 7), card(.diamonds, 7)]
        let beat = card(.spades, 8), pass = card(.clubs, 7)
        var game = state(hands: [sevens, [beat, pass, card(.clubs, 10)]],
                         deck: spareDeck, options: transfers)
        try game.apply(.attack(sevens[0]), by: 0)
        try game.apply(.defend(beat), by: 1)
        try game.apply(.attack(sevens[1]), by: 0)
        #expect(!game.canTransfer(with: pass))
    }

    // MARK: Bluffing

    @Test func bluffsAreRejectedWhenBluffingIsOff() throws {
        let lead = card(.spades, 9), fake = card(.clubs, 6)
        var game = state(hands: [[lead], [fake, card(.diamonds, 7)]], deck: spareDeck)
        try game.apply(.attack(lead), by: 0)
        #expect(!game.canPlay(fake))
        #expect(throws: DurakState.RuleError.illegalCard) { try game.applying(.defend(fake), by: 1) }
    }

    @Test func aBluffedDefenceStandsUntilCalled() throws {
        let lead = card(.spades, 9), fake = card(.clubs, 6)
        var game = state(hands: [[lead, card(.diamonds, 13)], [fake, card(.diamonds, 7)]],
                         deck: spareDeck, options: bluffing)
        try game.apply(.attack(lead), by: 0)
        #expect(game.canPlay(fake))
        try game.apply(.defend(fake), by: 1)
        // Looks beaten: the bout goes on, and nothing closes by itself.
        #expect(game.turn == 0)
        #expect(game.table.count == 1)
        #expect(game.owner(of: fake) == 1)
        #expect(!game.canCall(fake, by: 1), "Nobody calls their own card")
    }

    @Test func callingARealBluffSendsTheTableToTheBluffer() throws {
        let lead = card(.spades, 9), fake = card(.clubs, 6)
        var game = state(hands: [[lead, card(.diamonds, 13)], [fake, card(.diamonds, 7)]],
                         deck: spareDeck, options: bluffing)
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(fake), by: 1)
        try game.apply(.callBluff(fake), by: 0)
        #expect(game.table.isEmpty)
        #expect(game.hands[1].contains(lead) && game.hands[1].contains(fake))
        #expect(game.lastMove?.caught == true)
        #expect(game.lastMove?.target == 1)
        #expect(game.attacker == 0, "Like a pick-up: the bluffer doesn't lead")
    }

    @Test func aWrongCallSendsTheTableToTheCaller() throws {
        let lead = card(.spades, 9), beat = card(.spades, 10)
        var game = state(hands: [[lead, card(.diamonds, 13)], [beat, card(.diamonds, 7)]],
                         deck: spareDeck, options: bluffing)
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        try game.apply(.callBluff(beat), by: 0)
        #expect(game.hands[0].contains(lead) && game.hands[0].contains(beat))
        #expect(game.lastMove?.caught == false)
        #expect(game.attacker == 1, "The defender held, so they lead next")
    }

    @Test func aThrowInOfTheWrongRankIsABluff() throws {
        let lead = card(.spades, 9), beat = card(.spades, 10), stray = card(.clubs, 7)
        var game = state(hands: [[lead, stray], [beat, card(.diamonds, 7), card(.clubs, 8)]],
                         deck: spareDeck, options: bluffing)
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        #expect(!game.canAttack(with: stray))
        #expect(game.canPlay(stray))
        try game.apply(.attack(stray), by: 0)
        // The defender may call it out of turn order too.
        try game.apply(.callBluff(stray), by: 1)
        #expect(game.hands[0].contains(stray))
        #expect(game.lastMove?.caught == true)
    }

    @Test func callsOnlyWithBluffingOn() throws {
        let lead = card(.spades, 9), beat = card(.spades, 10)
        var game = state(hands: [[lead, card(.diamonds, 13)], [beat, card(.diamonds, 7)]], deck: spareDeck)
        try game.apply(.attack(lead), by: 0)
        try game.apply(.defend(beat), by: 1)
        #expect(throws: DurakState.RuleError.illegalAction) { try game.applying(.callBluff(beat), by: 0) }
    }

    @Test(arguments: [DurakOptions(transfer: true), DurakOptions(bluff: true), DurakOptions(transfer: true, bluff: true)])
    func botsFinishGamesWithOptionalRules(options: DurakOptions) throws {
        for seed in 1...60 {
            var generator = SeededGenerator(state: UInt64(seed))
            var game = DurakState.deal(players: 2 + seed % 5, options: options, using: &generator)
            var steps = 0
            while let seat = game.turn {
                let action = try #require(DurakBot.action(for: game, seat: seat, using: &generator))
                try game.apply(action, by: seat)
                // Other players sometimes notice a bluff.
                for pair in game.table {
                    for card in [pair.attack] + (pair.defense.map { [$0] } ?? []) {
                        let callers = (0..<game.playerCount).filter { game.canCall(card, by: $0) }
                        if let caller = callers.first,
                           DurakBot.notices(card, in: game, by: caller, using: &generator) {
                            try game.apply(.callBluff(card), by: caller)
                        }
                    }
                    if game.table.isEmpty { break }
                }
                steps += 1
                try #require(steps < 3000, "Game \(seed) didn't finish")
            }
            let total = game.hands.flatMap { $0 }.count + game.deck.count + game.discarded
            #expect(total == 36, "No card is lost or duplicated")
        }
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let game = DurakState.deal()
        let data = try JSONEncoder().encode(game)
        #expect(try JSONDecoder().decode(DurakState.self, from: data) == game)
    }
}
