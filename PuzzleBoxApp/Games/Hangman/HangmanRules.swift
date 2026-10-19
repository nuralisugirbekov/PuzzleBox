import Foundation

// Hangman for two to four players on one shared word. Players take turns
// naming a letter: a hit opens every copy of it and the same player goes
// again, a miss adds a part to the hanged man and passes the turn. Whoever
// makes the mistake that completes the man is out, and a fresh man is drawn
// for the rest. Whoever opens the last letter, or is the last one left, wins.
// The state is a plain value so the bot game and an online match (stored in
// Firestore) run the exact same rules.

enum HangmanAction: Codable, Equatable {
    case guess(String)
}

struct HangmanState: Codable, Equatable {
    enum Outcome: Codable, Equatable {
        case winner(Int)
    }

    enum RuleError: Error, Equatable {
        case gameOver, notYourTurn, notALetter, alreadyGuessed
    }

    struct LastMove: Codable, Equatable {
        let seat: Int
        let letter: String
        let hit: Bool
    }

    /// Head, body, two arms, two legs.
    static let maxMistakes = 6
    static let playerRange = 2...4

    let language: HangmanLanguage
    /// The word, one letter per element.
    let word: [String]
    /// Letters named so far, hits and misses, in order.
    var guessed: [String] = []
    /// Mistakes on the current man; back to zero when a player is knocked out.
    var mistakes = 0
    /// The seat to name the next letter.
    var turn: Int
    /// Letters of the word each seat opened; one entry per player.
    var opened = [0, 0]
    /// Players knocked out by completing a man, in order.
    var eliminated: [Int] = []
    var outcome: Outcome?
    var lastMove: LastMove?

    var playerCount: Int { opened.count }
    var currentTurn: Int? { outcome == nil ? turn : nil }

    func isOut(_ seat: Int) -> Bool { eliminated.contains(seat) }

    /// The next seat clockwise still in the game.
    func nextActive(after seat: Int) -> Int {
        var next = seat
        for _ in 0..<playerCount {
            next = (next + 1) % playerCount
            if !isOut(next) { return next }
        }
        return seat
    }
    var isSolved: Bool { word.allSatisfy(guessed.contains) }
    var misses: [String] { guessed.filter { !word.contains($0) } }

    func isRevealed(_ index: Int) -> Bool { guessed.contains(word[index]) }

    // MARK: Dealing

    static func newGame<G: RandomNumberGenerator>(language: HangmanLanguage, players: Int = 2,
                                                  using generator: inout G) -> HangmanState {
        let players = min(max(players, playerRange.lowerBound), playerRange.upperBound)
        let word = language.words.randomElement(using: &generator) ?? "PUZZLE"
        return HangmanState(language: language, word: word.map(String.init),
                            turn: Int.random(in: 0..<players, using: &generator),
                            opened: Array(repeating: 0, count: players))
    }

    static func newGame(language: HangmanLanguage, players: Int = 2) -> HangmanState {
        var generator = SystemRandomNumberGenerator()
        return newGame(language: language, players: players, using: &generator)
    }

    // MARK: Rules

    func canGuess(_ letter: String) -> Bool {
        outcome == nil && language.alphabet.contains(letter) && !guessed.contains(letter)
    }

    func applying(_ action: HangmanAction, by seat: Int) throws -> HangmanState {
        var next = self
        try next.apply(action, by: seat)
        return next
    }

    mutating func apply(_ action: HangmanAction, by seat: Int) throws {
        guard outcome == nil else { throw RuleError.gameOver }
        guard seat == turn else { throw RuleError.notYourTurn }
        guard case .guess(let letter) = action else { return }
        guard language.alphabet.contains(letter) else { throw RuleError.notALetter }
        guard !guessed.contains(letter) else { throw RuleError.alreadyGuessed }

        guessed.append(letter)
        let hits = word.filter { $0 == letter }.count
        if hits > 0 {
            opened[seat] += hits
            if isSolved { outcome = .winner(seat) }
        } else {
            mistakes += 1
            if mistakes >= Self.maxMistakes {
                // This player completed the man: out, and a new man for the rest.
                eliminated.append(seat)
                mistakes = 0
                let remaining = (0..<playerCount).filter { !isOut($0) }
                if remaining.count == 1 { outcome = .winner(remaining[0]) }
            }
            turn = nextActive(after: seat)
        }
        lastMove = LastMove(seat: seat, letter: letter, hit: hits > 0)
    }
}

// MARK: - Bot

enum HangmanBot {
    /// How often the bot names the letter most likely to be in the word; the
    /// rest of the time it picks a common letter, which keeps it beatable.
    static let skill = 0.55

    static func action<G: RandomNumberGenerator>(for state: HangmanState, using generator: inout G) -> HangmanAction? {
        guard state.outcome == nil else { return nil }
        let open = state.language.letterFrequency.filter { !state.guessed.contains($0) }
        guard !open.isEmpty else { return nil }

        if Double.random(in: 0..<1, using: &generator) < skill, let best = bestLetter(for: state, among: open) {
            return .guess(best)
        }
        // A common letter from the top of the frequency list.
        let pool = open.prefix(8)
        return .guess(pool.randomElement(using: &generator) ?? open[0])
    }

    static func action(for state: HangmanState) -> HangmanAction? {
        var generator = SystemRandomNumberGenerator()
        return action(for: state, using: &generator)
    }

    /// The open letter found in the most dictionary words that still fit the
    /// pattern: same length, opened letters in place, no missed letters.
    static func bestLetter(for state: HangmanState, among open: [String]) -> String? {
        let misses = Set(state.misses)
        let candidates = state.language.words.filter { word in
            let letters = word.map(String.init)
            guard letters.count == state.word.count else { return false }
            for (index, letter) in letters.enumerated() {
                if misses.contains(letter) { return false }
                if state.isRevealed(index) {
                    if letter != state.word[index] { return false }
                } else if state.guessed.contains(letter) {
                    return false
                }
            }
            return true
        }
        guard !candidates.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for word in candidates {
            for letter in Set(word.map(String.init)) where open.contains(letter) {
                counts[letter, default: 0] += 1
            }
        }
        return open.max { counts[$0, default: 0] < counts[$1, default: 0] }
    }
}
