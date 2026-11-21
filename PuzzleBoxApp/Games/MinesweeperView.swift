import SwiftUI
import Observation

// MARK: - Engine

enum MinesweeperDifficulty: Int, CaseIterable, Codable {
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

    struct Cell: Codable {
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

    /// The difficulty picked last, which the next game opens on.
    static var savedDifficulty: MinesweeperDifficulty {
        MinesweeperDifficulty(rawValue: UserDefaults.standard.integer(forKey: difficultyKey)) ?? .easy
    }

    /// Picked on the sheet before the game opens. A saved round of another
    /// difficulty is dropped, so the game opens on the board that was asked for.
    static func choose(_ difficulty: MinesweeperDifficulty) {
        UserDefaults.standard.set(difficulty.rawValue, forKey: difficultyKey)
        if let saved = GameSessionStore.load(.minesweeper),
           (try? JSONDecoder().decode(SavedDifficulty.self, from: saved.payload))?.difficulty != difficulty {
            GameSessionStore.delete(.minesweeper)
        }
    }

    /// Just the difficulty of a saved round.
    private struct SavedDifficulty: Decodable {
        let difficulty: MinesweeperDifficulty
    }

    init() {
        difficulty = Self.savedDifficulty
        reset()
    }

    func restart() { reset() }

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

    /// An easy board opened from the middle with two flags set, for the Home
    /// preview. Built directly, so no sounds play and nothing is saved.
    func showcase() {
        difficulty = .easy
        reset()
        let mines = [(0, 2), (0, 7), (1, 0), (2, 5), (2, 8), (5, 0), (6, 7), (7, 2), (8, 5), (8, 8)]
        for (r, c) in mines { grid[r][c].isMine = true }
        for r in 0..<rows {
            for c in 0..<cols {
                var count = 0
                for dr in -1...1 { for dc in -1...1 where (dr, dc) != (0, 0) {
                    let nr = r + dr, nc = c + dc
                    if nr >= 0, nr < rows, nc >= 0, nc < cols, grid[nr][nc].isMine { count += 1 }
                } }
                grid[r][c].adjacent = count
            }
        }
        var queue = [GridPos(r: 4, c: 4)]
        grid[4][4].revealed = true
        while !queue.isEmpty {
            let p = queue.removeFirst()
            guard grid[p.r][p.c].adjacent == 0 else { continue }
            for dr in -1...1 { for dc in -1...1 where (dr, dc) != (0, 0) {
                let nr = p.r + dr, nc = p.c + dc
                guard nr >= 0, nr < rows, nc >= 0, nc < cols,
                      !grid[nr][nc].revealed, !grid[nr][nc].isMine else { continue }
                grid[nr][nc].revealed = true
                queue.append(GridPos(r: nr, c: nc))
            } }
        }
        revealedCount = grid.flatMap { $0 }.filter(\.revealed).count
        minesPlaced = true
        grid[2][5].flagged = true
        grid[6][7].flagged = true
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

    /// A late tap from a board that was just swapped for another size is ignored.
    private func contains(_ p: GridPos) -> Bool {
        grid.indices.contains(p.r) && grid[p.r].indices.contains(p.c)
    }

    func tap(_ p: GridPos) {
        guard state == .playing, contains(p) else { return }
        if grid[p.r][p.c].revealed { chord(p); return }
        if flagMode { toggleFlag(p) } else { dig(p) }
    }

    func toggleFlag(_ p: GridPos) {
        guard state == .playing, contains(p), !grid[p.r][p.c].revealed else { return }
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
        guard state == .playing, contains(p), !grid[p.r][p.c].revealed, !grid[p.r][p.c].flagged else { return }
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
    private var isShowcase = false

    init() {}

    /// Just the board, in a fixed position, for the Home preview.
    init(showcase engine: MinesweeperEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }
    /// Bumped on a loss to give the board a short shake.
    @State private var shake = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func tone(_ light: (Double, Double, Double), _ dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
            : UIColor(red: light.0, green: light.1, blue: light.2, alpha: 1) })
    }

    private static let numberColors: [Color] = [
        .clear,
        tone((0.13, 0.38, 0.88), (0.42, 0.64, 1.00)),
        tone((0.09, 0.54, 0.26), (0.36, 0.80, 0.46)),
        tone((0.86, 0.18, 0.18), (1.00, 0.42, 0.40)),
        tone((0.20, 0.18, 0.62), (0.66, 0.58, 1.00)),
        tone((0.62, 0.16, 0.10), (0.96, 0.58, 0.32)),
        tone((0.00, 0.50, 0.55), (0.30, 0.82, 0.84)),
        GameTheme.ink,
        GameTheme.textSecondary,
    ]
    private static let tileTop = tone((0.58, 0.71, 0.89), (0.33, 0.42, 0.57))
    private static let tileBottom = tone((0.43, 0.57, 0.80), (0.23, 0.31, 0.44))
    private static let ground = tone((0.96, 0.94, 0.89), (0.17, 0.18, 0.20))
    private static let groundAlt = tone((0.92, 0.89, 0.83), (0.14, 0.15, 0.17))

    var body: some View {
        if isShowcase {
            ZStack {
                ToyMinesweeper.palette.backdrop
                board.padding(24)
            }
            .environment(\.toyStyle, ToyMinesweeper.palette.style)
            .frame(width: 360, height: 360)
        } else {
            gameBody
        }
    }

    @ViewBuilder
    private var gameBody: some View {
        GameContainerView(gameID: .minesweeper, engine: engine,
                          resultSummary: engine.finishSeconds.map { L10n.format("Time: %@", Self.clock($0)) } ?? L10n.text(engine.difficulty.title),
                          chrome: .inGame,
                          backdrop: AnyView(ToyMinesweeper.palette.backdrop),
                          toyStyle: ToyMinesweeper.palette.style) {
            ToyGameStage(palette: ToyMinesweeper.palette,
                         headline: .clock(caption: L10n.text(engine.difficulty.title), time: { mineClock })) {
                VStack(spacing: 0) {
                    statusBar
                        .padding(.top, 14)
                    Spacer(minLength: 12)
                    board
                    Spacer(minLength: 12)
                    // Only until the first cell is opened.
                    Text(L10n.text("Long-press to flag. Tap a number with all its flags placed to open the cells around it."))
                        .font(.system(.footnote, design: .rounded))
                        .opacity(engine.revealedCount == 0 ? 0.6 : 0)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(!(engine.revealedCount == 0))
                    Spacer(minLength: 4).frame(maxHeight: 16)
                }
                .animation(.easeOut(duration: 0.3), value: engine.revealedCount == 0)
            }
        }
    }

    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// Runs from the first opened cell and stops on the result.
    private var mineClock: String {
        let seconds = engine.finishSeconds ?? engine.startDate.map { Int(Date().timeIntervalSince($0)) } ?? 0
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Flags left and the dig/flag switch.
    private var statusBar: some View {
        let palette = ToyMinesweeper.palette
        return HStack(spacing: 10) {
            ToyChip(color: palette.card) {
                Label {
                    Text(verbatim: "\(engine.mineCount - engine.flagsUsed)").monospacedDigit()
                } icon: {
                    Image(systemName: "flag.fill").foregroundStyle(ToyMinesweeper.flag)
                }
            }
            Spacer(minLength: 0)
            ToyCapsuleButton(title: engine.flagMode ? L10n.text("Flag Mode") : L10n.text("Dig Mode"),
                             symbol: engine.flagMode ? "flag.fill" : "hammer.fill",
                             color: engine.flagMode ? palette.accent : palette.card,
                             ink: engine.flagMode ? .white : palette.ink) {
                engine.flagMode.toggle()
                Haptics.tap(); SoundFX.play(.tap)
            }
            .fixedSize()
        }
    }

    private var board: some View {
        let spacing: CGFloat = engine.rows > 10 ? 2 : 3
        // Built from the grid itself, so each cell carries its own value: when the
        // difficulty shrinks the board, a cell still on its way out never reads
        // past the end of the new, smaller grid.
        return VStack(spacing: spacing) {
            ForEach(Array(engine.grid.enumerated()), id: \.offset) { r, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { c, cell in
                        self.cell(cell, at: GridPos(r: r, c: c))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .toyTray(ToyMinesweeper.palette.tray, cornerRadius: 20, padding: 8)
        .id(engine.difficulty)
        // A short, soft shake when a mine goes off.
        .keyframeAnimator(initialValue: CGFloat(0), trigger: shake) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(reduceMotion ? 0 : -9, duration: 0.05)
                CubicKeyframe(reduceMotion ? 0 : 8, duration: 0.07)
                CubicKeyframe(reduceMotion ? 0 : -5, duration: 0.07)
                CubicKeyframe(reduceMotion ? 0 : 3, duration: 0.07)
                SpringKeyframe(0, duration: 0.2)
            }
        }
        .onChange(of: engine.exploded) { _, spot in
            if spot != nil { shake += 1 }
        }
    }

    @ViewBuilder
    private func cell(_ cell: MinesweeperEngine.Cell, at pos: GridPos) -> some View {
        let lost = engine.state == .gameOver(won: false)
        let fontSize: CGFloat = engine.rows > 10 ? 12 : 16
        let corner: CGFloat = engine.rows > 10 ? 3 : 5
        ZStack {
            if cell.revealed {
                RoundedRectangle(cornerRadius: corner)
                    .fill(engine.exploded == pos ? ToyMinesweeper.boom
                          : (pos.r + pos.c).isMultiple(of: 2) ? Self.ground : Self.groundAlt)
                if engine.exploded == pos {
                    // A soft "pow" behind the mine that went off.
                    BurstShape(points: 10)
                        .fill(ToyMinesweeper.boomGlow)
                        .padding(fontSize * 0.08)
                }
            } else {
                // A raised tile: lit top edge, shaded bottom edge.
                RoundedRectangle(cornerRadius: corner)
                    .fill(LinearGradient(colors: [Self.tileTop, Self.tileBottom], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: corner)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .black.opacity(0.22)],
                                                         startPoint: .top, endPoint: .bottom),
                                          lineWidth: engine.rows > 10 ? 1 : 1.5)
                    }
            }
            if cell.revealed {
                if cell.isMine {
                    if cell.flagged {
                        flag(size: fontSize)
                    } else {
                        MineGlyph(color: ToyMinesweeper.mine)
                            .padding(fontSize * 0.24)
                    }
                } else if cell.adjacent > 0 {
                    Text("\(cell.adjacent)")
                        .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(Self.numberColors[cell.adjacent])
                }
            } else if cell.flagged {
                // After a loss, flags on safe cells are crossed out.
                if lost && !cell.isMine {
                    Image(systemName: "xmark")
                        .font(.system(size: fontSize - 2, weight: .black))
                        .foregroundStyle(.white)
                } else {
                    flag(size: fontSize)
                }
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

    private func flag(size: CGFloat) -> some View {
        Image(systemName: "flag.fill")
            .font(.system(size: size - 3, weight: .bold))
            .foregroundStyle(Color(red: 0.92, green: 0.20, blue: 0.18))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
    }
}

/// A soft clay mine: a round body on its darker lip, stubby rounded
/// spikes all around and a glint, lit from the top like the other toys.
private struct MineGlyph: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(0..<8) { i in
                    let a = Double(i) * .pi / 4
                    Circle()
                        .fill(color.toyShade(-0.12))
                        .frame(width: s * 0.22, height: s * 0.22)
                        .offset(x: cos(a) * s * 0.38, y: sin(a) * s * 0.38)
                }
                Circle().fill(color.toyShade(-0.22))
                    .frame(width: s * 0.68, height: s * 0.68)
                    .offset(y: s * 0.05)
                Circle()
                    .fill(LinearGradient(colors: [color.toyShade(0.12), color, color.toyShade(-0.06)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.68, height: s * 0.68)
                Ellipse().fill(.white.opacity(0.6))
                    .frame(width: s * 0.2, height: s * 0.13)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -s * 0.13, y: -s * 0.15)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// A rounded star: the "pow" behind the mine that went off.
private struct BurstShape: Shape {
    var points: Int

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * 0.68
        var path = Path()
        for i in 0..<(points * 2) {
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Saved round

extension MinesweeperEngine: ResumableGame {
    private struct Session: Codable {
        let difficulty: MinesweeperDifficulty
        let grid: [[Cell]]
        let revealedCount: Int
        /// Seconds played so far; the clock carries on from here.
        let elapsed: TimeInterval
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, minesPlaced else { return nil }
        return encodeSession(Session(difficulty: difficulty, grid: grid, revealedCount: revealedCount,
                                     elapsed: startDate.map { Date().timeIntervalSince($0) } ?? 0))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        difficulty = session.difficulty
        grid = session.grid.map { row in row.map { var cell = $0; cell.wave = 0; return cell } }
        revealedCount = session.revealedCount
        minesPlaced = true
        exploded = nil
        finishSeconds = nil
        flagMode = false
        startDate = Date().addingTimeInterval(-session.elapsed)
        state = .playing
        return true
    }
}


/// The sage meadow toy world of Minesweeper; the blue tiles stay as they are.
enum ToyMinesweeper {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.95, 0.97, 0.91), dark: (0.12, 0.15, 0.11)),
        backdropBottom: .dynamic(light: (0.85, 0.90, 0.80), dark: (0.07, 0.09, 0.06)),
        tray: .dynamic(light: (0.69, 0.77, 0.60), dark: (0.28, 0.34, 0.24)),
        socket: .dynamic(light: (0.60, 0.69, 0.52), dark: (0.21, 0.26, 0.18)),
        ink: .dynamic(light: (0.24, 0.32, 0.20), dark: (0.92, 0.96, 0.88)),
        deboss: .dynamic(light: (0.84, 0.89, 0.78), dark: (0.37, 0.45, 0.32)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.04, 0.05, 0.03)),
        card: .dynamic(light: (0.99, 1.0, 0.97), dark: (0.20, 0.24, 0.18)),
        accent: .dynamic(light: (0.42, 0.58, 0.86), dark: (0.52, 0.66, 0.94)))
    static let flag = Color.dynamic(light: (0.88, 0.36, 0.33), dark: (0.98, 0.50, 0.46))
    /// Mines: soft slate-plum clay instead of black.
    static let mine = Color.dynamic(light: (0.42, 0.40, 0.54), dark: (0.66, 0.63, 0.80))
    /// The cell of the mine that went off, and the burst behind it.
    static let boom = Color.dynamic(light: (0.97, 0.62, 0.55), dark: (0.78, 0.38, 0.36))
    static let boomGlow = Color.dynamic(light: (1.0, 0.86, 0.62), dark: (0.98, 0.70, 0.45))
}
