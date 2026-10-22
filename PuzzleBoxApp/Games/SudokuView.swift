import SwiftUI
import Observation

// MARK: - Engine

enum SudokuDifficulty: Int, CaseIterable, Codable {
    case easy, medium, hard
    var title: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
    var size: Int { self == .easy ? 6 : 9 }
    var clues: Int {
        switch self {
        case .easy: 14
        case .medium: 34
        case .hard: 27
        }
    }
    var bonus: Int { [200, 500, 900][rawValue] }
}

@MainActor
@Observable
final class SudokuEngine: GameEngine {
    static let hintCount = 3
    private static let difficultyKey = "sudokuDifficulty"

    private(set) var difficulty: SudokuDifficulty
    private(set) var solution: [[Int]] = []
    private(set) var given: [[Bool]] = []
    private(set) var board: [[Int?]] = []
    /// Pencil marks per cell.
    private(set) var notes: [[Set<Int>]] = []
    private(set) var hintsLeft = SudokuEngine.hintCount
    var notesMode = false
    var state: GameState = .playing
    var selected: GridPos?

    var size: Int { difficulty.size }
    var blockRows: Int { size == 6 ? 2 : 3 }
    var blockCols: Int { 3 }

    /// Paid out only on a solved board: a score that grew with each correct
    /// digit would tell the player which digits are wrong.
    var score: Int {
        guard case .gameOver(won: true) = state else { return 0 }
        let filled = given.joined().filter { !$0 }.count
        return filled * 10 + difficulty.bonus + hintsLeft * 50
    }

    /// Every cell is filled but the board isn't the solution. Says that
    /// something is wrong without saying where.
    var isFullButWrong: Bool {
        state == .playing && board.allSatisfy { $0.allSatisfy { $0 != nil } } && board != solution.map { $0.map { $0 } }
    }

    init() {
        difficulty = Self.savedDifficulty
        newPuzzle()
    }

    func restart() {
        newPuzzle()
        state = .playing
    }

    /// The difficulty picked last, which the next game opens on.
    static var savedDifficulty: SudokuDifficulty {
        SudokuDifficulty(rawValue: UserDefaults.standard.integer(forKey: difficultyKey)) ?? .easy
    }

    /// Picked before the game opens. A saved puzzle of another difficulty is
    /// dropped, so the game opens on the difficulty that was asked for.
    static func choose(_ difficulty: SudokuDifficulty) {
        UserDefaults.standard.set(difficulty.rawValue, forKey: difficultyKey)
        if let saved = GameSessionStore.load(.sudoku),
           (try? JSONDecoder().decode(SavedDifficulty.self, from: saved.payload))?.difficulty != difficulty {
            GameSessionStore.delete(.sudoku)
        }
    }

    /// Just the difficulty of a saved puzzle.
    private struct SavedDifficulty: Decodable {
        let difficulty: SudokuDifficulty
    }

    private func newPuzzle() {
        let puzzle = Self.generatePuzzle(size: size, blockRows: blockRows, clues: difficulty.clues)
        solution = puzzle.solution
        given = puzzle.given
        board = (0..<size).map { r in (0..<size).map { c in given[r][c] ? solution[r][c] : nil } }
        notes = Array(repeating: Array(repeating: [], count: size), count: size)
        hintsLeft = Self.hintCount
        selected = nil
        notesMode = false
    }

    // MARK: Generation

    /// Fills a random complete grid, then removes clues while the solution stays unique.
    private static func generatePuzzle(size n: Int, blockRows: Int, clues: Int) -> (solution: [[Int]], given: [[Bool]]) {
        var grid = Array(repeating: 0, count: n * n)
        _ = solve(&grid, n: n, blockRows: blockRows, randomize: true, limit: 1)
        let solution = (0..<n).map { r in Array(grid[(r * n)..<(r * n + n)]) }
        var puzzle = grid
        var remaining = n * n
        for cell in (0..<(n * n)).shuffled() where remaining > clues {
            let saved = puzzle[cell]
            puzzle[cell] = 0
            var copy = puzzle
            if solve(&copy, n: n, blockRows: blockRows, randomize: false, limit: 2) == 1 {
                remaining -= 1
            } else {
                puzzle[cell] = saved
            }
        }
        let given = (0..<n).map { r in (0..<n).map { c in puzzle[r * n + c] != 0 } }
        return (solution, given)
    }

    /// Backtracking with bitmasks. Returns the number of solutions found, up to `limit`;
    /// when it returns at least 1, `grid` holds the first solution.
    private static func solve(_ grid: inout [Int], n: Int, blockRows: Int, randomize: Bool, limit: Int) -> Int {
        let blockCols = 3
        var rows = Array(repeating: 0, count: n), cols = Array(repeating: 0, count: n), boxes = Array(repeating: 0, count: n)
        func box(_ r: Int, _ c: Int) -> Int { (r / blockRows) * (n / blockCols) + c / blockCols }
        for i in grid.indices where grid[i] != 0 {
            let bit = 1 << grid[i], r = i / n, c = i % n
            rows[r] |= bit; cols[c] |= bit; boxes[box(r, c)] |= bit
        }
        var found = 0
        var firstSolution: [Int]?
        func search() {
            // Most constrained empty cell first.
            var best = -1, bestCount = Int.max, bestMask = 0
            for i in grid.indices where grid[i] == 0 {
                let r = i / n, c = i % n
                let used = rows[r] | cols[c] | boxes[box(r, c)]
                var count = 0
                for d in 1...n where used & (1 << d) == 0 { count += 1 }
                if count < bestCount { best = i; bestCount = count; bestMask = used; if count <= 1 { break } }
            }
            if best < 0 {
                found += 1
                if firstSolution == nil { firstSolution = grid }
                return
            }
            if bestCount == 0 { return }
            let r = best / n, c = best % n, b = box(r, c)
            var digits = (1...n).filter { bestMask & (1 << $0) == 0 }
            if randomize { digits.shuffle() }
            for d in digits {
                let bit = 1 << d
                grid[best] = d; rows[r] |= bit; cols[c] |= bit; boxes[b] |= bit
                search()
                grid[best] = 0; rows[r] &= ~bit; cols[c] &= ~bit; boxes[b] &= ~bit
                if found >= limit { return }
            }
        }
        search()
        if let firstSolution { grid = firstSolution }
        return found
    }

    // MARK: Play

    /// Cells whose value duplicates another in its row, column, or block.
    var conflicts: Set<GridPos> {
        var conflicted = Set<GridPos>()
        func check(_ cells: [GridPos]) {
            var seen: [Int: [GridPos]] = [:]
            for p in cells {
                if let v = board[p.r][p.c] { seen[v, default: []].append(p) }
            }
            for (_, positions) in seen where positions.count > 1 {
                conflicted.formUnion(positions)
            }
        }
        let n = size
        for r in 0..<n { check((0..<n).map { GridPos(r: r, c: $0) }) }
        for c in 0..<n { check((0..<n).map { GridPos(r: $0, c: c) }) }
        for br in 0..<(n / blockRows) {
            for bc in 0..<(n / blockCols) {
                var cells: [GridPos] = []
                for r in 0..<blockRows {
                    for c in 0..<blockCols {
                        cells.append(GridPos(r: br * blockRows + r, c: bc * blockCols + c))
                    }
                }
                check(cells)
            }
        }
        return conflicted
    }

    /// How many more of each digit are still needed on the board.
    func remaining(_ digit: Int) -> Int {
        size - board.joined().filter { $0 == digit }.count
    }

    func select(_ pos: GridPos) {
        guard state == .playing else { return }
        selected = selected == pos ? nil : pos
        Haptics.tap(); SoundFX.play(.tap)
    }

    /// Enters a digit (or erases with nil) in the selected cell.
    func enter(_ value: Int?) {
        guard state == .playing, let sel = selected, !given[sel.r][sel.c] else { return }
        guard let value else {
            board[sel.r][sel.c] = nil
            notes[sel.r][sel.c] = []
            Haptics.tap(); SoundFX.play(.tap)
            return
        }
        if notesMode {
            guard board[sel.r][sel.c] == nil else { return }
            if notes[sel.r][sel.c].contains(value) { notes[sel.r][sel.c].remove(value) } else { notes[sel.r][sel.c].insert(value) }
            Haptics.tap(); SoundFX.play(.tap)
            return
        }
        guard board[sel.r][sel.c] != value else { return }
        board[sel.r][sel.c] = value
        // Right and wrong digits are entered alike, so the board never gives
        // the answer away; only clashes in a row, column or block show red.
        notes[sel.r][sel.c] = []
        clearNotes(value, around: sel)
        Haptics.move(); SoundFX.play(.place)
        celebrateCompletedUnits(at: sel)
        checkCompletion()
        if isFullButWrong { Haptics.error(); SoundFX.play(.wrong) }
    }

    /// Fills the selected empty cell (or a random one) with its correct digit.
    func hint() {
        guard state == .playing, hintsLeft > 0 else { return }
        let empties = (0..<size).flatMap { r in (0..<size).map { GridPos(r: r, c: $0) } }
            .filter { board[$0.r][$0.c] != solution[$0.r][$0.c] }
        let target = selected.flatMap { sel in empties.contains(sel) ? sel : nil } ?? empties.randomElement()
        guard let target else { return }
        hintsLeft -= 1
        board[target.r][target.c] = solution[target.r][target.c]
        notes[target.r][target.c] = []
        clearNotes(solution[target.r][target.c], around: target)
        selected = target
        Haptics.move(); SoundFX.play(.coin)
        checkCompletion()
    }

    private func clearNotes(_ value: Int, around pos: GridPos) {
        for r in 0..<size { for c in 0..<size {
            let sameBox = r / blockRows == pos.r / blockRows && c / blockCols == pos.c / blockCols
            if r == pos.r || c == pos.c || sameBox { notes[r][c].remove(value) }
        } }
    }

    /// A row or column filled without repeats, checked against the rules
    /// rather than the solution so it can't confirm a guess.
    private func celebrateCompletedUnits(at pos: GridPos) {
        func complete(_ values: [Int?]) -> Bool { Set(values.compactMap { $0 }).count == size }
        let rowDone = complete(board[pos.r])
        let colDone = complete((0..<size).map { board[$0][pos.c] })
        if rowDone || colDone { SoundFX.play(.clear) }
    }

    private func checkCompletion() {
        for r in 0..<size {
            for c in 0..<size where board[r][c] != solution[r][c] {
                return
            }
        }
        state = .gameOver(won: true)
    }
}

// MARK: - View

struct SudokuView: View {
    @State private var engine = SudokuEngine()

    var body: some View {
        GameContainerView(gameID: .sudoku, engine: engine,
                          resultSummary: L10n.text(engine.difficulty.title)) {
            VStack(spacing: 16) {
                board
                    .overlay(alignment: .bottom) {
                        if engine.isFullButWrong {
                            Text(L10n.text("Some digits are wrong"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.red.opacity(0.85), in: Capsule())
                                .offset(y: 20)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.2), value: engine.isFullButWrong)
                numberPad
            }
        }
    }

    private var board: some View {
        let conflicts = engine.conflicts
        let n = engine.size
        return VStack(spacing: 1) {
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<n, id: \.self) { c in
                        cell(r: r, c: c, conflicts: conflicts)
                    }
                }
            }
        }
        .background(Color(UIColor.separator))
        .overlay(blockLines)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.6), lineWidth: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .id(n)
    }

    @ViewBuilder
    private func cell(r: Int, c: Int, conflicts: Set<GridPos>) -> some View {
        let pos = GridPos(r: r, c: c)
        let value = engine.board[r][c]
        let isGiven = engine.given[r][c]
        let isSelected = engine.selected == pos
        // Only clashes the player could spot themselves; never a check against the solution.
        let isWrong = !isGiven && value != nil && conflicts.contains(pos)
        let sameUnit = isInSelectedUnit(pos)
        let selectedValue = engine.selected.flatMap { engine.board[$0.r][$0.c] }
        let sameValue = value != nil && value == selectedValue && !isSelected
        let n = engine.size

        ZStack {
            Rectangle()
                .fill(cellBackground(isSelected: isSelected, isWrong: isWrong, sameUnit: sameUnit, sameValue: sameValue))
            if let value {
                Text("\(value)")
                    .font(.system(n == 9 ? .title3 : .title2, design: .rounded).weight(isGiven ? .bold : .medium))
                    .foregroundStyle(isWrong ? .red : (isGiven ? GameTheme.ink : GameTheme.accent))
                    .transition(.scale.combined(with: .opacity))
            } else if !engine.notes[r][c].isEmpty {
                // Pencil marks laid out in a small grid matching the digit pad.
                let columns = 3
                VStack(spacing: 0) {
                    ForEach(0..<(n / columns), id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(1...columns, id: \.self) { col in
                                let digit = row * columns + col
                                Text(engine.notes[r][c].contains(digit) ? "\(digit)" : " ")
                                    .font(.system(size: n == 9 ? 8 : 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(GameTheme.textSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .padding(1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { engine.select(pos) }
        .animation(.snappy(duration: 0.15), value: value)
    }

    private func isInSelectedUnit(_ pos: GridPos) -> Bool {
        guard let sel = engine.selected, sel != pos else { return false }
        let sameBox = sel.r / engine.blockRows == pos.r / engine.blockRows && sel.c / engine.blockCols == pos.c / engine.blockCols
        return sel.r == pos.r || sel.c == pos.c || sameBox
    }

    private func cellBackground(isSelected: Bool, isWrong: Bool, sameUnit: Bool, sameValue: Bool) -> Color {
        if isSelected { return GameTheme.accent.opacity(0.30) }
        if isWrong { return .red.opacity(0.18) }
        if sameValue { return GameTheme.accent.opacity(0.2) }
        if sameUnit { return GameTheme.accent.opacity(0.07) }
        return GameTheme.surface
    }

    /// Thick separators outlining the blocks (2×3 on 6×6, 3×3 on 9×9).
    private var blockLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let n = CGFloat(engine.size)
            let rowsPerBlock = CGFloat(engine.blockRows), colsPerBlock = CGFloat(engine.blockCols)
            Path { p in
                for k in stride(from: colsPerBlock, to: n, by: colsPerBlock) {
                    p.move(to: CGPoint(x: w * k / n, y: 0)); p.addLine(to: CGPoint(x: w * k / n, y: h))
                }
                for k in stride(from: rowsPerBlock, to: n, by: rowsPerBlock) {
                    p.move(to: CGPoint(x: 0, y: h * k / n)); p.addLine(to: CGPoint(x: w, y: h * k / n))
                }
            }
            .stroke(Color.primary.opacity(0.6), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private var numberPad: some View {
        VStack(spacing: 10) {
            HStack(spacing: engine.size == 9 ? 5 : 10) {
                ForEach(1...engine.size, id: \.self) { n in
                    let left = engine.remaining(n)
                    Button {
                        engine.enter(n)
                    } label: {
                        VStack(spacing: 0) {
                            Text("\(n)").font(.title2.bold())
                            Text("\(max(0, left))").font(.caption2.monospacedDigit()).opacity(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(GameTheme.accent.opacity(engine.notesMode ? 0.05 : 0.12),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(GameTheme.accent.opacity(engine.notesMode ? 0.6 : 0.3), lineWidth: 1)
                        }
                        .foregroundStyle(GameTheme.accent)
                    }
                    .disabled(left <= 0)
                    .opacity(left <= 0 ? 0.3 : 1)
                }
            }
            HStack(spacing: 10) {
                toolButton(L10n.text("Erase"), symbol: "eraser.fill", active: false) { engine.enter(nil) }
                toolButton(L10n.text("Notes"), symbol: engine.notesMode ? "pencil.circle.fill" : "pencil.circle", active: engine.notesMode) {
                    engine.notesMode.toggle(); Haptics.tap()
                }
                toolButton(L10n.format("Hint (%d)", engine.hintsLeft), symbol: "lightbulb.fill", active: false) { engine.hint() }
                    .disabled(engine.hintsLeft == 0)
            }
        }
    }

    private func toolButton(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.bold())
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(active ? GameTheme.accent : GameTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(active ? Color.white : GameTheme.ink)
        }
    }
}

// MARK: - Saved round

extension SudokuEngine: ResumableGame {
    private struct Session: Codable {
        let difficulty: SudokuDifficulty
        let solution: [[Int]]
        let given: [[Bool]]
        let board: [[Int?]]
        let notes: [[Set<Int>]]
        let hintsLeft: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused else { return nil }
        let touched = (0..<size).contains { r in
            (0..<size).contains { c in (!given[r][c] && board[r][c] != nil) || !notes[r][c].isEmpty }
        }
        guard touched else { return nil }
        return encodeSession(Session(difficulty: difficulty, solution: solution, given: given, board: board,
                                     notes: notes, hintsLeft: hintsLeft))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        difficulty = session.difficulty
        solution = session.solution
        given = session.given
        board = session.board
        notes = session.notes
        hintsLeft = session.hintsLeft
        selected = nil
        notesMode = false
        state = .playing
        return true
    }
}
