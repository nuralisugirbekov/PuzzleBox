import SwiftUI
import Observation

// MARK: - Engine

enum MinesweeperDifficulty: Int, CaseIterable {
    case easy, medium, hard
    var title: String { ["Easy", "Medium", "Hard"][rawValue] }
    var size: Int { [9, 12, 14][rawValue] }
    var mines: Int { [10, 24, 40][rawValue] }
    var bonus: Int { [100, 300, 600][rawValue] }
}

@MainActor
@Observable
final class MinesweeperEngine: GameEngine {
    private static let difficultyKey = "minesweeperDifficulty"

    struct Cell {
        var isMine = false
        var revealed = false
        var flagged = false
        var adjacent = 0
        /// Distance from the tap that opened it, for a rippling reveal.
        var wave = 0
    }

    private(set) var difficulty: MinesweeperDifficulty
    private(set) var grid: [[Cell]] = []
    private(set) var revealedCount = 0
    private(set) var minesPlaced = false
    private(set) var exploded: GridPos?
    private(set) var startDate: Date?
    private(set) var finishSeconds: Int?
    var flagMode = false
    var state: GameState = .playing

    var rows: Int { difficulty.size }
    var cols: Int { difficulty.size }
    var mineCount: Int { difficulty.mines }
    var flagsUsed: Int { grid.flatMap { $0 }.filter(\.flagged).count }
    var score: Int {
        guard state == .gameOver(won: true) else { return revealedCount * 2 }
        // Faster clears earn more.
        let seconds = finishSeconds ?? 999
        return revealedCount * 2 + difficulty.bonus + max(0, 300 - seconds) * (difficulty.rawValue + 1)
    }

    init() {
        difficulty = MinesweeperDifficulty(rawValue: UserDefaults.standard.integer(forKey: Self.difficultyKey)) ?? .easy
        reset()
    }

    func restart() { reset() }

    func setDifficulty(_ value: MinesweeperDifficulty) {
        guard value != difficulty else { return }
        difficulty = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.difficultyKey)
        reset()
    }

    private func reset() {
        grid = Array(repeating: Array(repeating: Cell(), count: cols), count: rows)
        revealedCount = 0
        minesPlaced = false
        flagMode = false
        exploded = nil
        startDate = nil
        finishSeconds = nil
        state = .playing
    }

    /// Mines are placed after the first dig so the opening tap is always safe.
    private func placeMines(avoiding safe: GridPos) {
        var spots: [GridPos] = []
        for r in 0..<rows {
            for c in 0..<cols where abs(r - safe.r) > 1 || abs(c - safe.c) > 1 {
                spots.append(GridPos(r: r, c: c))
            }
        }
        for spot in spots.shuffled().prefix(mineCount) {
            grid[spot.r][spot.c].isMine = true
        }
        for r in 0..<rows {
            for c in 0..<cols {
                grid[r][c].adjacent = neighbors(GridPos(r: r, c: c))
                    .filter { grid[$0.r][$0.c].isMine }.count
            }
        }
        minesPlaced = true
        startDate = Date()
    }

    private func neighbors(_ p: GridPos) -> [GridPos] {
        var out: [GridPos] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = p.r + dr, c = p.c + dc
                if (0..<rows).contains(r), (0..<cols).contains(c) {
                    out.append(GridPos(r: r, c: c))
                }
            }
        }
        return out
    }

    func tap(_ p: GridPos) {
        guard state == .playing else { return }
        if grid[p.r][p.c].revealed { chord(p); return }
        if flagMode { toggleFlag(p) } else { dig(p) }
    }

    func toggleFlag(_ p: GridPos) {
        guard state == .playing, !grid[p.r][p.c].revealed else { return }
        grid[p.r][p.c].flagged.toggle()
        Haptics.tap(); SoundFX.play(.tap)
    }

    /// Tapping a number whose flags are all placed opens the rest of its neighbours.
    private func chord(_ p: GridPos) {
        let cell = grid[p.r][p.c]
        guard cell.adjacent > 0 else { return }
        let around = neighbors(p)
        guard around.filter({ grid[$0.r][$0.c].flagged }).count == cell.adjacent else { return }
        for n in around where !grid[n.r][n.c].revealed && !grid[n.r][n.c].flagged {
            dig(n)
            if state != .playing { return }
        }
    }

    func dig(_ p: GridPos) {
        guard state == .playing, !grid[p.r][p.c].revealed, !grid[p.r][p.c].flagged else { return }
        if !minesPlaced { placeMines(avoiding: p) }

        if grid[p.r][p.c].isMine {
            exploded = p
            finishSeconds = Int(Date().timeIntervalSince(startDate ?? Date()))
            for r in 0..<rows {
                for c in 0..<cols where grid[r][c].isMine {
                    grid[r][c].revealed = true
                    grid[r][c].wave = abs(r - p.r) + abs(c - p.c)
                }
            }
            Haptics.heavy(); SoundFX.play(.hit)
            state = .gameOver(won: false)
            return
        }

        // Flood reveal from the tapped cell, remembering each cell's distance.
        var stack = [p]
        var opened = 0
        while let cur = stack.popLast() {
            let cell = grid[cur.r][cur.c]
            guard !cell.revealed, !cell.isMine else { continue }
            grid[cur.r][cur.c].revealed = true
            grid[cur.r][cur.c].flagged = false
            grid[cur.r][cur.c].wave = max(abs(cur.r - p.r), abs(cur.c - p.c))
            revealedCount += 1; opened += 1
            if cell.adjacent == 0 {
                stack.append(contentsOf: neighbors(cur).filter { !grid[$0.r][$0.c].revealed })
            }
        }
        Haptics.move(); SoundFX.play(opened > 8 ? .pour : .place)

        if revealedCount == rows * cols - mineCount {
            finishSeconds = Int(Date().timeIntervalSince(startDate ?? Date()))
            // Flag every mine for the finished board.
            for r in 0..<rows { for c in 0..<cols where grid[r][c].isMine { grid[r][c].flagged = true } }
            state = .gameOver(won: true)
        }
    }
}

// MARK: - View

struct MinesweeperView: View {
    @State private var engine = MinesweeperEngine()

    private static let numberColors: [Color] =
        [.clear, .blue, .green, .orange, .red, .purple, .cyan, .yellow, GameTheme.ink]

    var body: some View {
        GameContainerView(gameID: .minesweeper, engine: engine,
                          resultSummary: engine.finishSeconds.map { L10n.format("Time: %@", Self.clock($0)) } ?? L10n.text(engine.difficulty.title)) {
            VStack(spacing: 14) {
                Picker("", selection: Binding(get: { engine.difficulty }, set: { engine.setDifficulty($0) })) {
                    ForEach(MinesweeperDifficulty.allCases, id: \.self) { Text(L10n.text($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                statusBar
                board
                Text(L10n.text("Long-press to flag. Tap a number with all its flags placed to open the cells around it."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
    }

    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label("\(engine.mineCount - engine.flagsUsed)", systemImage: "flag.fill")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.red)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = engine.finishSeconds ?? engine.startDate.map { Int(context.date.timeIntervalSince($0)) } ?? 0
                Label(Self.clock(seconds), systemImage: "timer")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(GameTheme.textSecondary)
            }
            Spacer()
            Button {
                engine.flagMode.toggle()
                Haptics.tap(); SoundFX.play(.tap)
            } label: {
                Label(engine.flagMode ? L10n.text("Flag Mode") : L10n.text("Dig Mode"),
                      systemImage: engine.flagMode ? "flag.fill" : "hammer.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.flagMode ? .white : GameTheme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(engine.flagMode ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(GameTheme.surface),
                                in: Capsule())
                    .overlay { Capsule().strokeBorder(GameTheme.stroke, lineWidth: 1) }
            }
        }
        .padding(.horizontal, 4)
    }

    private var board: some View {
        let spacing: CGFloat = engine.rows > 10 ? 2 : 3
        return VStack(spacing: spacing) {
            ForEach(0..<engine.rows, id: \.self) { r in
                HStack(spacing: spacing) {
                    ForEach(0..<engine.cols, id: \.self) { c in
                        cell(r: r, c: c)
                    }
                }
            }
        }
        .padding(8)
        .gameCard(cornerRadius: 16)
        .aspectRatio(1, contentMode: .fit)
        .id(engine.difficulty)
    }

    @ViewBuilder
    private func cell(r: Int, c: Int) -> some View {
        let cell = engine.grid[r][c]
        let pos = GridPos(r: r, c: c)
        let lost = engine.state == .gameOver(won: false)
        let fontSize: CGFloat = engine.rows > 10 ? 12 : 16
        ZStack {
            RoundedRectangle(cornerRadius: engine.rows > 10 ? 3 : 5)
                .fill(cell.revealed
                      ? (engine.exploded == pos ? AnyShapeStyle(Color.red) : AnyShapeStyle(GameTheme.background))
                      : AnyShapeStyle(LinearGradient(colors: [GameTheme.surfaceHigh, GameTheme.surfaceHigh.opacity(0.6)], startPoint: .top, endPoint: .bottom)))
            if cell.revealed {
                if cell.isMine {
                    Text(cell.flagged ? "🚩" : "💣").font(.system(size: fontSize - 1))
                } else if cell.adjacent > 0 {
                    Text("\(cell.adjacent)")
                        .font(.system(size: fontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.numberColors[cell.adjacent])
                }
            } else if cell.flagged {
                // After a loss, flags on safe cells are crossed out.
                Text(lost && !cell.isMine ? "❌" : "🚩").font(.system(size: fontSize - 2))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .scaleEffect(cell.revealed ? 1 : 0.96)
        .animation(.easeOut(duration: 0.18).delay(Double(min(cell.wave, 12)) * 0.025), value: cell.revealed)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(pos) }
        .onLongPressGesture(minimumDuration: 0.3) { engine.toggleFlag(pos) }
    }
}
