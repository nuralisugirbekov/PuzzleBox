import SwiftUI
import Observation

// MARK: - Engine

@MainActor
@Observable
final class SudokuEngine: GameEngine {
    static let size = 6
    static let blockRows = 2  // each block is 2 rows × 3 columns
    static let blockCols = 3

    private(set) var solution: [[Int]]
    private(set) var given: [[Bool]]
    private(set) var board: [[Int?]]
    private(set) var mistakes = 0
    var state: GameState = .playing
    var selected: GridPos?

    var score: Int {
        var s = 0
        for r in 0..<Self.size {
            for c in 0..<Self.size where !given[r][c] && board[r][c] == solution[r][c] {
                s += 10
            }
        }
        return max(0, s - mistakes * 5)
    }

    init() {
        let puzzle = Self.generatePuzzle()
        solution = puzzle.solution
        given = puzzle.given
        board = Self.startingBoard(solution: puzzle.solution, given: puzzle.given)
    }

    func restart() {
        let puzzle = Self.generatePuzzle()
        solution = puzzle.solution
        given = puzzle.given
        board = Self.startingBoard(solution: puzzle.solution, given: puzzle.given)
        mistakes = 0
        selected = nil
        state = .playing
    }

    private static func startingBoard(solution: [[Int]], given: [[Bool]]) -> [[Int?]] {
        (0..<size).map { r in
            (0..<size).map { c in given[r][c] ? solution[r][c] : nil }
        }
    }

    /// Builds a fresh valid 6×6 board from a base pattern, then shuffles digits,
    /// row bands, rows, column stacks, and columns — all validity-preserving.
    private static func generatePuzzle() -> (solution: [[Int]], given: [[Bool]]) {
        let n = size
        var base = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
        for r in 0..<n {
            for c in 0..<n {
                base[r][c] = (r * blockCols + r / blockRows + c) % n + 1
            }
        }

        let digits = Array(1...n).shuffled()
        var rowOrder: [Int] = []
        for band in (0..<(n / blockRows)).shuffled() {
            for r in (0..<blockRows).shuffled() { rowOrder.append(band * blockRows + r) }
        }
        var colOrder: [Int] = []
        for stack in (0..<(n / blockCols)).shuffled() {
            for c in (0..<blockCols).shuffled() { colOrder.append(stack * blockCols + c) }
        }

        var solution = base
        for r in 0..<n {
            for c in 0..<n {
                solution[r][c] = digits[base[rowOrder[r]][colOrder[c]] - 1]
            }
        }

        var given = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
        let keep = 16
        for cell in (0..<(n * n)).shuffled().prefix(keep) {
            given[cell / n][cell % n] = true
        }
        return (solution, given)
    }

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
        let n = Self.size
        for r in 0..<n { check((0..<n).map { GridPos(r: r, c: $0) }) }
        for c in 0..<n { check((0..<n).map { GridPos(r: $0, c: c) }) }
        for br in 0..<(n / Self.blockRows) {
            for bc in 0..<(n / Self.blockCols) {
                var cells: [GridPos] = []
                for r in 0..<Self.blockRows {
                    for c in 0..<Self.blockCols {
                        cells.append(GridPos(r: br * Self.blockRows + r, c: bc * Self.blockCols + c))
                    }
                }
                check(cells)
            }
        }
        return conflicted
    }

    func select(_ pos: GridPos) {
        guard state == .playing else { return }
        selected = selected == pos ? nil : pos
        Haptics.tap()
    }

    /// Enters a digit (or erases with nil) in the selected cell.
    func enter(_ value: Int?) {
        guard state == .playing, let sel = selected, !given[sel.r][sel.c] else { return }
        if let value {
            guard board[sel.r][sel.c] != value else { return }
            board[sel.r][sel.c] = value
            if value == solution[sel.r][sel.c] {
                Haptics.move()
            } else {
                mistakes += 1
                Haptics.error()
            }
            checkCompletion()
        } else {
            board[sel.r][sel.c] = nil
            Haptics.tap()
        }
    }

    private func checkCompletion() {
        for r in 0..<Self.size {
            for c in 0..<Self.size where board[r][c] != solution[r][c] {
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
        GameContainerView(gameID: .sudoku, engine: engine) {
            VStack(spacing: 20) {
                mistakesBar
                board
                numberPad
            }
        }
    }

    private var mistakesBar: some View {
        HStack {
            Label(L10n.format("%d mistakes", engine.mistakes), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(engine.mistakes > 0 ? .red : .secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var board: some View {
        let conflicts = engine.conflicts
        return VStack(spacing: 1) {
            ForEach(0..<SudokuEngine.size, id: \.self) { r in
                HStack(spacing: 1) {
                    ForEach(0..<SudokuEngine.size, id: \.self) { c in
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
    }

    @ViewBuilder
    private func cell(r: Int, c: Int, conflicts: Set<GridPos>) -> some View {
        let pos = GridPos(r: r, c: c)
        let value = engine.board[r][c]
        let isGiven = engine.given[r][c]
        let isSelected = engine.selected == pos
        let isWrong = !isGiven && value != nil
            && (conflicts.contains(pos) || value != engine.solution[r][c])
        let sameUnit = isInSelectedUnit(pos)

        ZStack {
            Rectangle()
                .fill(cellBackground(isSelected: isSelected, isWrong: isWrong, sameUnit: sameUnit))
            if let value {
                Text("\(value)")
                    .font(.system(.title2, design: .rounded).weight(isGiven ? .bold : .medium))
                    .foregroundStyle(isWrong ? .red : (isGiven ? GameTheme.ink : GameTheme.accent))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { engine.select(pos) }
    }

    private func isInSelectedUnit(_ pos: GridPos) -> Bool {
        guard let sel = engine.selected, sel != pos else { return false }
        return sel.r == pos.r || sel.c == pos.c
    }

    private func cellBackground(isSelected: Bool, isWrong: Bool, sameUnit: Bool) -> Color {
        if isSelected { return GameTheme.accent.opacity(0.30) }
        if isWrong { return .red.opacity(0.18) }
        if sameUnit { return GameTheme.accent.opacity(0.07) }
        return GameTheme.surface
    }

    /// Thick separators outlining the 2×3 blocks.
    private var blockLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w / 2, y: 0))
                p.addLine(to: CGPoint(x: w / 2, y: h))
                p.move(to: CGPoint(x: 0, y: h / 3))
                p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: 2 * h / 3))
                p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.primary.opacity(0.6), lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private var numberPad: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(1...SudokuEngine.size, id: \.self) { n in
                    Button {
                        engine.enter(n)
                    } label: {
                        Text("\(n)")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(GameTheme.accent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(GameTheme.accent.opacity(0.3), lineWidth: 1)
                            }
                            .foregroundStyle(GameTheme.accent)
                    }
                }
            }
            Button {
                engine.enter(nil)
            } label: {
                Label(L10n.text("Erase"), systemImage: "eraser.fill")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(GameTheme.surfaceHigh,
                                in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(GameTheme.ink)
            }
        }
    }
}
