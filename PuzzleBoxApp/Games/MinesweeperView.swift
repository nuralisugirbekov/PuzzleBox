import SwiftUI
import Observation

// MARK: - Engine

@MainActor
@Observable
final class MinesweeperEngine: GameEngine {
    static let rows = 9
    static let cols = 9
    static let mineCount = 10

    struct Cell {
        var isMine = false
        var revealed = false
        var flagged = false
        var adjacent = 0
    }

    private(set) var grid: [[Cell]] = []
    private(set) var revealedCount = 0
    private(set) var minesPlaced = false
    var flagMode = false
    var state: GameState = .playing

    var flagsUsed: Int { grid.flatMap { $0 }.filter(\.flagged).count }
    var score: Int {
        revealedCount * 2 + (state == .gameOver(won: true) ? 100 : 0)
    }

    init() { reset() }

    func restart() { reset() }

    private func reset() {
        grid = Array(repeating: Array(repeating: Cell(), count: Self.cols), count: Self.rows)
        revealedCount = 0
        minesPlaced = false
        flagMode = false
        state = .playing
    }

    /// Mines are placed after the first dig so the opening tap is always safe.
    private func placeMines(avoiding safe: GridPos) {
        var spots: [GridPos] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols where abs(r - safe.r) > 1 || abs(c - safe.c) > 1 {
                spots.append(GridPos(r: r, c: c))
            }
        }
        for spot in spots.shuffled().prefix(Self.mineCount) {
            grid[spot.r][spot.c].isMine = true
        }
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                grid[r][c].adjacent = neighbors(GridPos(r: r, c: c))
                    .filter { grid[$0.r][$0.c].isMine }.count
            }
        }
        minesPlaced = true
    }

    private func neighbors(_ p: GridPos) -> [GridPos] {
        var out: [GridPos] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = p.r + dr, c = p.c + dc
                if (0..<Self.rows).contains(r), (0..<Self.cols).contains(c) {
                    out.append(GridPos(r: r, c: c))
                }
            }
        }
        return out
    }

    func tap(_ p: GridPos) {
        guard state == .playing else { return }
        if flagMode { toggleFlag(p) } else { dig(p) }
    }

    func toggleFlag(_ p: GridPos) {
        guard state == .playing, !grid[p.r][p.c].revealed else { return }
        grid[p.r][p.c].flagged.toggle()
        Haptics.tap()
    }

    func dig(_ p: GridPos) {
        guard state == .playing, !grid[p.r][p.c].revealed, !grid[p.r][p.c].flagged else { return }
        if !minesPlaced { placeMines(avoiding: p) }

        if grid[p.r][p.c].isMine {
            for r in 0..<Self.rows {
                for c in 0..<Self.cols where grid[r][c].isMine {
                    grid[r][c].revealed = true
                }
            }
            state = .gameOver(won: false)
            return
        }

        // Flood reveal from the tapped cell.
        var stack = [p]
        while let cur = stack.popLast() {
            let cell = grid[cur.r][cur.c]
            guard !cell.revealed, !cell.isMine else { continue }
            grid[cur.r][cur.c].revealed = true
            grid[cur.r][cur.c].flagged = false
            revealedCount += 1
            if cell.adjacent == 0 {
                stack.append(contentsOf: neighbors(cur).filter { !grid[$0.r][$0.c].revealed })
            }
        }
        Haptics.move()

        if revealedCount == Self.rows * Self.cols - Self.mineCount {
            state = .gameOver(won: true)
        }
    }
}

// MARK: - View

struct MinesweeperView: View {
    @State private var engine = MinesweeperEngine()

    private static let numberColors: [Color] =
        [.clear, .blue, .green, .orange, .red, .purple, .cyan, .yellow, .white]

    var body: some View {
        GameContainerView(gameID: .minesweeper, engine: engine) {
            VStack(spacing: 16) {
                statusBar
                board
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Label("\(MinesweeperEngine.mineCount - engine.flagsUsed)", systemImage: "flag.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Spacer()
            Button {
                engine.flagMode.toggle()
                Haptics.tap()
            } label: {
                Label(engine.flagMode ? L10n.text("Flag Mode") : L10n.text("Dig Mode"),
                      systemImage: engine.flagMode ? "flag.fill" : "hammer.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.flagMode ? .black : Theme.neon)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(engine.flagMode ? AnyShapeStyle(Theme.neon) : AnyShapeStyle(Theme.surface),
                                in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.stroke, lineWidth: 1) }
            }
        }
        .padding(.horizontal, 4)
    }

    private var board: some View {
        VStack(spacing: 3) {
            ForEach(0..<MinesweeperEngine.rows, id: \.self) { r in
                HStack(spacing: 3) {
                    ForEach(0..<MinesweeperEngine.cols, id: \.self) { c in
                        cell(r: r, c: c)
                    }
                }
            }
        }
        .padding(8)
        .themeCard(cornerRadius: 16)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func cell(r: Int, c: Int) -> some View {
        let cell = engine.grid[r][c]
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(cell.revealed ? Theme.background : Theme.surfaceHigh)
            if cell.revealed {
                if cell.isMine {
                    Text("💣").font(.system(size: 15))
                } else if cell.adjacent > 0 {
                    Text("\(cell.adjacent)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.numberColors[cell.adjacent])
                }
            } else if cell.flagged {
                Text("🚩").font(.system(size: 14))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(GridPos(r: r, c: c)) }
        .onLongPressGesture { engine.toggleFlag(GridPos(r: r, c: c)) }
    }
}
