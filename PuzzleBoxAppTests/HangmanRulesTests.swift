import Foundation
import Testing
@testable import PuzzleBoxApp

@MainActor
struct HangmanRulesTests {
    /// "BALL" in English; seat 0 names the first letter.
    private func state(word: String = "BALL", turn: Int = 0) -> HangmanState {
        HangmanState(language: .english, word: word.map(String.init), turn: turn)
    }

    @Test(arguments: HangmanLanguage.allCases)
    func wordListsAreValid(language: HangmanLanguage) {
        let alphabet = Set(language.alphabet)
        #expect(language.words.count >= 80)
        #expect(Set(language.words).count == language.words.count, "duplicate words")
        for word in language.words {
            #expect((4...10).contains(word.count), "\(word) has \(word.count) letters")
            #expect(word.allSatisfy { alphabet.contains(String($0)) }, "\(word) has a letter missing from the keyboard")
        }
    }

    @Test func appLanguagesWithoutAnAlphabetUseEnglish() {
        #expect(HangmanLanguage(app: .russian) == .russian)
        #expect(HangmanLanguage(app: .kazakh) == .kazakh)
        #expect(HangmanLanguage(app: .chinese) == .english)
        #expect(HangmanLanguage(app: .korean) == .english)
        #expect(HangmanLanguage(app: .hindi) == .english)
    }

    @Test func hitOpensEveryCopyAndKeepsTheTurn() throws {
        let next = try state().applying(.guess("L"), by: 0)
        #expect(next.opened == [2, 0])
        #expect(next.turn == 0)
        #expect(next.mistakes == 0)
        #expect(next.isRevealed(2) && next.isRevealed(3))
        #expect(next.lastMove == .init(seat: 0, letter: "L", hit: true))
    }

    @Test func missAddsAMistakeAndPassesTheTurn() throws {
        let next = try state().applying(.guess("Z"), by: 0)
        #expect(next.mistakes == 1)
        #expect(next.turn == 1)
        #expect(next.misses == ["Z"])
    }

    @Test func onlyTheSeatOnTurnMayGuess() {
        #expect(throws: HangmanState.RuleError.notYourTurn) { try state().applying(.guess("B"), by: 1) }
    }

    @Test func aLetterCanBeNamedOnce() throws {
        let next = try state().applying(.guess("B"), by: 0)
        #expect(throws: HangmanState.RuleError.alreadyGuessed) { try next.applying(.guess("B"), by: 0) }
        #expect(!next.canGuess("B"))
    }

    @Test func lettersOffTheKeyboardAreRejected() {
        #expect(throws: HangmanState.RuleError.notALetter) { try state().applying(.guess("Ж"), by: 0) }
    }

    @Test func openingTheLastLetterWins() throws {
        var game = state()
        try game.apply(.guess("Z"), by: 0)   // seat 1's turn
        try game.apply(.guess("B"), by: 1)
        try game.apply(.guess("A"), by: 1)
        try game.apply(.guess("L"), by: 1)
        #expect(game.outcome == .winner(1))
        #expect(game.currentTurn == nil)
        #expect(game.opened == [0, 4])
        #expect(throws: HangmanState.RuleError.gameOver) { try game.applying(.guess("Q"), by: 1) }
    }

    @Test func theSixthMistakeLoses() throws {
        var game = state()
        let misses = ["Q", "W", "E", "R", "T", "Y"]
        for (index, letter) in misses.enumerated() {
            try game.apply(.guess(letter), by: index % 2)
        }
        // Seat 1 made the sixth mistake: out, and seat 0 is the last one left.
        #expect(game.eliminated == [1])
        #expect(game.outcome == .winner(0))
    }

    @Test func withMorePlayersTheGameGoesOnAfterAKnockOut() throws {
        var game = HangmanState(language: .english, word: "BALL".map(String.init), turn: 0, opened: [0, 0, 0])
        for (index, letter) in ["Q", "W", "E", "R", "T", "Y"].enumerated() {
            try game.apply(.guess(letter), by: index % 3)
        }
        // Seat 2 made the sixth mistake: out, a fresh man, and play goes on.
        #expect(game.eliminated == [2])
        #expect(game.mistakes == 0)
        #expect(game.outcome == nil)
        #expect(game.turn == 0, "Seat 2 is skipped")
        try game.apply(.guess("Z"), by: 0)
        #expect(game.turn == 1)
        #expect(throws: HangmanState.RuleError.notYourTurn) { try game.applying(.guess("B"), by: 2) }
    }

    @Test(arguments: HangmanState.playerRange)
    func newGameSeatsEveryPlayer(players: Int) {
        let game = HangmanState.newGame(language: .english, players: players)
        #expect(game.playerCount == players)
        #expect((0..<players).contains(game.turn))
    }

    @Test func botNamesALegalLetter() throws {
        var game = state(turn: 1)
        try game.apply(.guess("Z"), by: 1)
        try game.apply(.guess("B"), by: 0)
        for _ in 0..<20 {
            guard case .guess(let letter)? = HangmanBot.action(for: game) else {
                Issue.record("bot gave no move"); return
            }
            #expect(game.canGuess(letter))
        }
    }

    @Test func botsBestLetterFitsThePattern() throws {
        // "PUZZLE" with every letter but E open: the only fitting word ends in E.
        var game = state(word: "PUZZLE")
        for letter in ["P", "U", "Z", "L"] { try game.apply(.guess(letter), by: 0) }
        let open = game.language.letterFrequency.filter { !game.guessed.contains($0) }
        #expect(HangmanBot.bestLetter(for: game, among: open) == "E")
    }

    @Test func newGamePicksAWordFromTheLanguage() {
        let game = HangmanState.newGame(language: .russian)
        #expect(HangmanLanguage.russian.words.contains(game.word.joined()))
        #expect(game.guessed.isEmpty && game.mistakes == 0 && game.outcome == nil)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let game = try state().applying(.guess("A"), by: 0)
        let decoded = try JSONDecoder().decode(HangmanState.self, from: JSONEncoder().encode(game))
        #expect(decoded == game)
    }
}
