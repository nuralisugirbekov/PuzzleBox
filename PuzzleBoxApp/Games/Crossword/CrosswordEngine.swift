import SwiftUI
import Observation

struct CrosswordCell: Hashable {
    let row: Int
    let col: Int
}

struct CrosswordClue: Identifiable {
    let id: Int
    let number: Int
    let answer: [Character]
    let clue: String
    let start: CrosswordCell
    let across: Bool
    var cells: [CrosswordCell] {
        answer.indices.map { across ? CrosswordCell(row: start.row, col: start.col + $0) : CrosswordCell(row: start.row + $0, col: start.col) }
    }
}

/// Builds a small crossing grid from a word list: each new word must cross an
/// existing one and may not touch other words side by side.
enum CrosswordGenerator {
    static let maxSide = 11

    static func make(level: Int, language: CrosswordWords.Language) -> (rows: Int, cols: Int, clues: [CrosswordClue]) {
        var random = PuzzleRandom(seed: UInt64(level) &* 2_654_435_761 &+ UInt64(language.rawValue.unicodeScalars.reduce(0) { $0 * 31 + Int($1.value) }))
        let target = min(11, 6 + level / 6)
        var best: [(word: [Character], clue: String, row: Int, col: Int, across: Bool)] = []
        for _ in 0..<20 {
            let pool = language.entries.shuffled(using: &random)
            let placed = attempt(pool: pool, target: target, random: &random)
            if placed.count > best.count { best = placed }
            if best.count >= target { break }
        }
        // Normalise to a 0-based grid.
        let minRow = best.map(\.row).min() ?? 0, minCol = best.map(\.col).min() ?? 0
        let maxRow = best.map { $0.row + ($0.across ? 0 : $0.word.count - 1) }.max() ?? 0
        let maxCol = best.map { $0.col + ($0.across ? $0.word.count - 1 : 0) }.max() ?? 0
        let shifted = best.map { (word: $0.word, clue: $0.clue, row: $0.row - minRow, col: $0.col - minCol, across: $0.across) }
        // Classic numbering: scan in reading order; a cell that starts any word gets the next number.
        let starts = Set(shifted.map { CrosswordCell(row: $0.row, col: $0.col) })
        var numbers: [CrosswordCell: Int] = [:]
        var next = 1
        for r in 0...(maxRow - minRow) {
            for c in 0...(maxCol - minCol) where starts.contains(CrosswordCell(row: r, col: c)) {
                numbers[CrosswordCell(row: r, col: c)] = next; next += 1
            }
        }
        let clues = shifted.enumerated().map { index, entry in
            CrosswordClue(id: index, number: numbers[CrosswordCell(row: entry.row, col: entry.col)] ?? 0, answer: entry.word,
                          clue: entry.clue, start: CrosswordCell(row: entry.row, col: entry.col), across: entry.across)
        }
        .sorted { ($0.across ? 0 : 1, $0.number) < ($1.across ? 0 : 1, $1.number) }
        return (maxRow - minRow + 1, maxCol - minCol + 1, clues)
    }

    private static func attempt(pool: [CrosswordWords.Entry], target: Int,
                                random: inout PuzzleRandom) -> [(word: [Character], clue: String, row: Int, col: Int, across: Bool)] {
        var grid: [CrosswordCell: Character] = [:]
        var placed: [(word: [Character], clue: String, row: Int, col: Int, across: Bool)] = []
        var remaining = pool.sorted { $0.word.count > $1.word.count }
        guard let first = remaining.first else { return [] }
        remaining.removeFirst()
        let firstWord = Array(first.word)
        for (i, ch) in firstWord.enumerated() { grid[CrosswordCell(row: 0, col: i)] = ch }
        placed.append((firstWord, first.clue, 0, 0, true))
        remaining.shuffle(using: &random)

        for entry in remaining where placed.count < target {
            let word = Array(entry.word)
            var options: [(row: Int, col: Int, across: Bool, crossings: Int)] = []
            // Sorted so a level is identical on every launch (dictionary order is random).
            for (cell, letter) in grid.sorted(by: { ($0.key.row, $0.key.col) < ($1.key.row, $1.key.col) }) {
                for (i, ch) in word.enumerated() where ch == letter {
                    for across in [true, false] {
                        let row = across ? cell.row : cell.row - i
                        let col = across ? cell.col - i : cell.col
                        if let crossings = fits(word, row: row, col: col, across: across, grid: grid) {
                            options.append((row, col, across, crossings))
                        }
                    }
                }
            }
            guard let top = options.map(\.crossings).max() else { continue }
            let choices = options.filter { $0.crossings == top }
            let pick = choices[Int.random(in: 0..<choices.count, using: &random)]
            for (i, ch) in word.enumerated() {
                grid[pick.across ? CrosswordCell(row: pick.row, col: pick.col + i) : CrosswordCell(row: pick.row + i, col: pick.col)] = ch
            }
            placed.append((word, entry.clue, pick.row, pick.col, pick.across))
        }
        return placed
    }

    /// Number of crossings if `word` can be placed there, else nil.
    private static func fits(_ word: [Character], row: Int, col: Int, across: Bool, grid: [CrosswordCell: Character]) -> Int? {
        let dr = across ? 0 : 1, dc = across ? 1 : 0
        func at(_ r: Int, _ c: Int) -> Character? { grid[CrosswordCell(row: r, col: c)] }
        // Cells just before and after the word must be empty.
        if at(row - dr, col - dc) != nil || at(row + dr * word.count, col + dc * word.count) != nil { return nil }
        var crossings = 0
        for (i, ch) in word.enumerated() {
            let r = row + dr * i, c = col + dc * i
            if let existing = at(r, c) {
                guard existing == ch else { return nil }
                crossings += 1
            } else {
                // A new letter may not sit beside another word.
                if at(r + dc, c + dr) != nil || at(r - dc, c - dr) != nil { return nil }
            }
        }
        guard crossings > 0, crossings < word.count else { return nil }
        // Keep the whole board within the screen-friendly bounds.
        let cells = grid.keys.map { ($0.row, $0.col) } + word.indices.map { (row + dr * $0, col + dc * $0) }
        let rows = (cells.map(\.0).max() ?? 0) - (cells.map(\.0).min() ?? 0) + 1
        let cols = (cells.map(\.1).max() ?? 0) - (cells.map(\.1).min() ?? 0) + 1
        guard rows <= maxSide, cols <= maxSide else { return nil }
        return crossings
    }
}

@MainActor
@Observable
final class CrosswordEngine: GameEngine {
    static let levelCount = 60
    static let hintCount = 3

    var state: GameState = .playing
    private(set) var score = 0
    private(set) var level = 1
    let language = CrosswordWords.Language.current
    private(set) var rows = 1
    private(set) var cols = 1
    private(set) var clues: [CrosswordClue] = []
    private(set) var solution: [CrosswordCell: Character] = [:]
    private(set) var letters: [CrosswordCell: Character] = [:]
    private(set) var solved: Set<Int> = []
    private(set) var selected: CrosswordCell?
    private(set) var across = true
    private(set) var hintsLeft = CrosswordEngine.hintCount
    private(set) var mistakes = 0
    /// Bumped when a filled word turns out wrong, to shake it.
    private(set) var wrongFlash = 0
    private(set) var wrongClue: Int?

    private var levelKey: String { "crosswordLevel." + language.rawValue }
    var hasNextLevel: Bool { level < Self.levelCount }

    init() {
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: "crosswordLevel." + CrosswordWords.Language.current.rawValue)))
        restart()
    }

    func restart() {
        let puzzle = CrosswordGenerator.make(level: level, language: language)
        rows = puzzle.rows; cols = puzzle.cols; clues = puzzle.clues
        solution = [:]
        for clue in clues { for (cell, ch) in zip(clue.cells, clue.answer) { solution[cell] = ch } }
        letters = [:]; solved = []; hintsLeft = Self.hintCount; mistakes = 0; wrongClue = nil; score = 0
        across = clues.first?.across ?? true
        selected = clues.first?.start
        state = .playing
    }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    /// The clue that runs through the selection in the current direction.
    var activeClue: CrosswordClue? {
        guard let selected else { return nil }
        return clues.first { $0.across == across && $0.cells.contains(selected) }
            ?? clues.first { $0.cells.contains(selected) }
    }

    func isLocked(_ cell: CrosswordCell) -> Bool { clues.contains { solved.contains($0.id) && $0.cells.contains(cell) } }

    func tap(_ cell: CrosswordCell) {
        guard state == .playing, solution[cell] != nil else { return }
        if selected == cell {
            // A second tap on a crossing switches direction.
            if clues.contains(where: { $0.across != across && $0.cells.contains(cell) }) { across.toggle() }
        } else {
            selected = cell
            if !clues.contains(where: { $0.across == across && $0.cells.contains(cell) }) { across.toggle() }
        }
        Haptics.tap(); SoundFX.play(.tap)
    }

    func select(_ clue: CrosswordClue) {
        across = clue.across
        selected = clue.cells.first { letters[$0] == nil } ?? clue.start
        SoundFX.play(.tap)
    }

    func stepClue(_ delta: Int) {
        guard let current = activeClue, let index = clues.firstIndex(where: { $0.id == current.id }) else { return }
        let open = clues.indices.map { (index + delta * ($0 + 1) + clues.count * 4) % clues.count }.first { !solved.contains(clues[$0].id) }
        if let open { select(clues[open]) }
    }

    func type(_ letter: Character) {
        guard state == .playing, let cell = selected, let clue = activeClue else { return }
        if !isLocked(cell) { letters[cell] = letter }
        SoundFX.play(.tap)
        evaluate(clue)
        // Advance to the next open cell in the word.
        let cells = clue.cells
        if let i = cells.firstIndex(of: cell) {
            selected = cells[(i + 1)...].first { !isLocked($0) && letters[$0] == nil } ?? cells[min(i + 1, cells.count - 1)]
        }
        if solved.contains(clue.id) { stepClue(1) }
    }

    func backspace() {
        guard state == .playing, let cell = selected, let clue = activeClue else { return }
        if letters[cell] != nil && !isLocked(cell) {
            letters[cell] = nil
        } else if let i = clue.cells.firstIndex(of: cell), i > 0 {
            let previous = clue.cells[i - 1]
            selected = previous
            if !isLocked(previous) { letters[previous] = nil }
        }
        SoundFX.play(.tap)
    }

    func hint() {
        guard state == .playing, hintsLeft > 0 else { return }
        let target = selected.flatMap { letters[$0] != solution[$0] && !isLocked($0) ? $0 : nil }
            ?? activeClue?.cells.first { letters[$0] != solution[$0] }
        guard let cell = target, let answer = solution[cell] else { return }
        hintsLeft -= 1
        letters[cell] = answer
        Haptics.move(); SoundFX.play(.coin)
        for clue in clues where clue.cells.contains(cell) { evaluate(clue) }
    }

    private func evaluate(_ clue: CrosswordClue) {
        guard !solved.contains(clue.id) else { return }
        let entered = clue.cells.map { letters[$0] }
        guard entered.allSatisfy({ $0 != nil }) else { return }
        if entered.compactMap({ $0 }) == clue.answer {
            solved.insert(clue.id)
            score += 20 + clue.answer.count * 5
            Haptics.success(); SoundFX.play(.clear)
            // A finished word may complete crossing words too.
            for other in clues where other.id != clue.id && !solved.contains(other.id) && Set(other.cells).intersection(clue.cells).count > 0 {
                evaluate(other)
            }
            if solved.count == clues.count {
                score += 200 + level * 20 + hintsLeft * 50 + max(0, 100 - mistakes * 20)
                UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: levelKey)
                state = .gameOver(won: true)
            }
        } else {
            mistakes += 1
            wrongClue = clue.id
            wrongFlash += 1
            Haptics.error(); SoundFX.play(.wrong)
        }
    }
}
