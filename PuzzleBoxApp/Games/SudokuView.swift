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
                          resultSummary: L10n.text(engine.difficulty.title),
                          chrome: .inGame,
                          backdrop: AnyView(ToySudoku.palette.backdrop),
                          toyStyle: ToySudoku.palette.style) {
            ToyGameStage(palette: ToySudoku.palette,
                         headline: .clock(caption: L10n.text(engine.difficulty.title))) {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    board
                        .overlay(alignment: .bottom) {
                            if engine.isFullButWrong {
                                Text(L10n.text("Some digits are wrong"))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(ToySudoku.wrong, in: Capsule())
                                    .offset(y: 16)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.2), value: engine.isFullButWrong)
                    Spacer(minLength: 16).frame(maxHeight: 28)
                    numberPad
                    Spacer(minLength: 4)
                }
            }
        }
    }

    // MARK: Board

    /// Cells sit in sockets pressed into a lavender tray; wider gaps mark the blocks.
    private var board: some View {
        let conflicts = engine.conflicts
        let n = engine.size
        return GeometryReader { geo in
            // Equal cells: 2pt between cells, 6pt between blocks.
            let gap: CGFloat = 2, blockGap: CGFloat = 6
            let colBreaks = CGFloat(n / engine.blockCols - 1), rowBreaks = CGFloat(n / engine.blockRows - 1)
            let cw = (geo.size.width - gap * CGFloat(n - 1) - (blockGap - gap) * colBreaks) / CGFloat(n)
            let ch = (geo.size.height - gap * CGFloat(n - 1) - (blockGap - gap) * rowBreaks) / CGFloat(n)
            ForEach(0..<(n * n), id: \.self) { index in
                let r = index / n, c = index % n
                let x = CGFloat(c) * (cw + gap) + CGFloat(c / engine.blockCols) * (blockGap - gap)
                let y = CGFloat(r) * (ch + gap) + CGFloat(r / engine.blockRows) * (blockGap - gap)
                cell(r: r, c: c, conflicts: conflicts)
                    .frame(width: cw, height: ch)
                    .position(x: x + cw / 2, y: y + ch / 2)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .toyTray(ToySudoku.palette.tray, cornerRadius: 20, padding: 8)
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
        let shape = RoundedRectangle(cornerRadius: n == 9 ? 5 : 8, style: .continuous)

        ZStack {
            if isSelected {
                // The chosen cell pops up out of its socket.
                ToyBlock(color: ToySudoku.selected, shape: shape, lip: 2, castsShadow: false)
            } else {
                ToySocket(color: cellColor(isWrong: isWrong, sameUnit: sameUnit, sameValue: sameValue), shape: shape)
            }
            if let value {
                Text("\(value)")
                    .font(.system(n == 9 ? .title3 : .title2, design: .rounded).weight(isGiven ? .heavy : .semibold))
                    .foregroundStyle(isWrong ? ToySudoku.wrong : (isGiven ? ToySudoku.palette.ink : ToySudoku.palette.accent))
                    .offset(y: isSelected ? -1 : 0)
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
                                    .font(.system(size: n == 9 ? 8 : 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(ToySudoku.palette.ink.opacity(0.55))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }
                .padding(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { engine.select(pos) }
        .animation(.snappy(duration: 0.15), value: value)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }

    private func isInSelectedUnit(_ pos: GridPos) -> Bool {
        guard let sel = engine.selected, sel != pos else { return false }
        let sameBox = sel.r / engine.blockRows == pos.r / engine.blockRows && sel.c / engine.blockCols == pos.c / engine.blockCols
        return sel.r == pos.r || sel.c == pos.c || sameBox
    }

    private func cellColor(isWrong: Bool, sameUnit: Bool, sameValue: Bool) -> Color {
        if isWrong { return ToySudoku.wrongCell }
        if sameValue { return ToySudoku.sameValue }
        if sameUnit { return ToySudoku.sameUnit }
        return ToySudoku.palette.socket
    }

    // MARK: Pad

    private var numberPad: some View {
        VStack(spacing: 12) {
            HStack(spacing: engine.size == 9 ? 5 : 10) {
                ForEach(1...engine.size, id: \.self) { n in
                    let left = engine.remaining(n)
                    Button {
                        engine.enter(n)
                    } label: {
                        VStack(spacing: 0) {
                            Text("\(n)").font(.system(.title2, design: .rounded).weight(.heavy))
                            Text("\(max(0, left))").font(.system(.caption2, design: .rounded).monospacedDigit()).opacity(0.6)
                        }
                        .foregroundStyle(engine.notesMode ? ToySudoku.palette.ink.opacity(0.7) : ToySudoku.palette.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ToyPressStyle(color: engine.notesMode ? ToySudoku.notesKey : ToySudoku.palette.card,
                                               lip: 4, cornerRadius: 12))
                    .disabled(left <= 0)
                    .opacity(left <= 0 ? 0.35 : 1)
                }
            }
            HStack(spacing: 10) {
                ToyCapsuleButton(title: L10n.text("Erase"), symbol: "eraser.fill",
                                 color: ToySudoku.palette.card, ink: ToySudoku.palette.ink) { engine.enter(nil) }
                ToyCapsuleButton(title: L10n.text("Notes"), symbol: engine.notesMode ? "pencil.circle.fill" : "pencil.circle",
                                 color: engine.notesMode ? ToySudoku.palette.accent : ToySudoku.palette.card,
                                 ink: engine.notesMode ? .white : ToySudoku.palette.ink) {
                    engine.notesMode.toggle(); Haptics.tap()
                }
                ToyCapsuleButton(title: L10n.text("Hint"), symbol: "lightbulb.fill",
                                 color: ToySudoku.palette.card, ink: ToySudoku.palette.ink,
                                 badge: engine.hintsLeft, badgeColor: ToySudoku.palette.accent) { engine.hint() }
                    .disabled(engine.hintsLeft == 0)
                    .opacity(engine.hintsLeft == 0 ? 0.5 : 1)
            }
        }
    }
}

/// The lavender toy world of Sudoku.
enum ToySudoku {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.96, 0.95, 1.0), dark: (0.13, 0.12, 0.19)),
        backdropBottom: .dynamic(light: (0.89, 0.87, 0.97), dark: (0.08, 0.07, 0.12)),
        tray: .dynamic(light: (0.74, 0.70, 0.89), dark: (0.31, 0.28, 0.44)),
        socket: .dynamic(light: (0.99, 0.98, 1.0), dark: (0.19, 0.18, 0.27)),
        ink: .dynamic(light: (0.25, 0.22, 0.42), dark: (0.92, 0.90, 0.99)),
        deboss: .dynamic(light: (0.84, 0.81, 0.95), dark: (0.29, 0.27, 0.41)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.06, 0.05, 0.09)),
        card: .dynamic(light: (0.99, 0.98, 1.0), dark: (0.21, 0.20, 0.29)),
        accent: .dynamic(light: (0.47, 0.38, 0.85), dark: (0.66, 0.58, 0.98)))
    static let selected = Color.dynamic(light: (0.84, 0.79, 1.0), dark: (0.38, 0.33, 0.58))
    static let sameValue = Color.dynamic(light: (0.88, 0.85, 0.99), dark: (0.30, 0.27, 0.45))
    static let sameUnit = Color.dynamic(light: (0.94, 0.92, 1.0), dark: (0.23, 0.22, 0.33))
    static let wrongCell = Color.dynamic(light: (1.0, 0.88, 0.88), dark: (0.40, 0.20, 0.22))
    static let wrong = Color.dynamic(light: (0.86, 0.33, 0.36), dark: (0.98, 0.52, 0.54))
    static let notesKey = Color.dynamic(light: (0.93, 0.91, 0.99), dark: (0.26, 0.24, 0.36))
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
