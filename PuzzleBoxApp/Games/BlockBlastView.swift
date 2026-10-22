import SwiftUI
import Observation

// MARK: - Engine

struct BBPiece: Identifiable, Equatable, Codable {
    var id = UUID()
    let cells: [GridPos]  // normalized: min row/col is 0
    let colorIndex: Int

    var width: Int { (cells.map(\.c).max() ?? 0) + 1 }
    var height: Int { (cells.map(\.r).max() ?? 0) + 1 }
}

/// How kindly the tray is dealt: easy hands out pieces that fit snugly and
/// clear lines, hard hands out awkward ones. Every deal can still be placed.
enum BlockBlastDifficulty: Int, CaseIterable, Codable {
    case easy, medium, hard
    var title: String { ["Easy", "Medium", "Hard"][rawValue] }
}

@MainActor
@Observable
final class BlockBlastEngine: GameEngine {
    static let size = 8
    private static let difficultyKey = "blockBlastDifficulty"
    /// Figma accents; the system colours adapt to light and dark mode.
    static let colors: [Color] = [Color(.systemIndigo), Color(.systemGreen), Color(.systemPurple),
                                  Color(.systemPink), Color(.systemYellow)]

    /// The Figma piece sheet: squares, I4, and every rotation of T, L, J,
    /// the five-cell corner, S and Z. Rows are drawn top to bottom, `#` = block.
    static let shapes: [[GridPos]] = [
        ["###", "###", "###"],                          // 3×3 square
        ["##", "##"],                                    // 2×2 square
        ["####"], ["#", "#", "#", "#"],                  // I4
        ["###", ".#."], ["#.", "##", "#."], [".#.", "###"], [".#", "##", ".#"],   // T
        ["#.", "#.", "##"], ["..#", "###"], ["##", ".#", ".#"], ["###", "#.."],   // L
        [".#", ".#", "##"], ["###", "..#"], ["##", "#.", "#."], ["#..", "###"],   // J
        ["###", "..#", "..#"], ["###", "#..", "#.."],                             // corner
        ["#..", "#..", "###"], ["..#", "..#", "###"],
        ["##.", ".##"], [".#", "##", "#."],                                       // Z
        [".##", "##."], ["#.", "##", ".#"],                                       // S
    ].map(cells)

    private static func cells(_ rows: [String]) -> [GridPos] {
        rows.enumerated().flatMap { r, row in
            row.enumerated().compactMap { c, mark in mark == "#" ? GridPos(r: r, c: c) : nil }
        }
    }

    private(set) var difficulty: BlockBlastDifficulty
    private(set) var grid: [[Int?]]
    private(set) var tray: [BBPiece?] = []
    private(set) var score = 0
    /// Consecutive clearing placements; survives up to `comboGrace` misses.
    private(set) var combo = 0
    private(set) var comboGraceLeft = 0
    /// Cells that just cleared, kept briefly so the view can burst them.
    private(set) var flashCells: [GridPos: Int] = [:]
    var state: GameState = .playing
    let popups = ClassicFXPopupFeed()

    /// Board snapshots before each placement, for "Revert".
    fileprivate struct Snapshot: Codable {
        let grid: [[Int?]], tray: [BBPiece?], score: Int, combo: Int, comboGraceLeft: Int
    }
    fileprivate var history: [Snapshot] = []
    var canUndo: Bool { state == .playing && !history.isEmpty }
    static let comboGrace = 3

    /// The difficulty picked last, which the next game opens on.
    static var savedDifficulty: BlockBlastDifficulty {
        BlockBlastDifficulty(rawValue: UserDefaults.standard.integer(forKey: difficultyKey)) ?? .easy
    }

    /// Picked before the game opens. A saved round of another difficulty is
    /// dropped, so the game opens on the difficulty that was asked for.
    static func choose(_ difficulty: BlockBlastDifficulty) {
        UserDefaults.standard.set(difficulty.rawValue, forKey: difficultyKey)
        if let saved = GameSessionStore.load(.blockBlast),
           (try? JSONDecoder().decode(SavedDifficulty.self, from: saved.payload))?.difficulty ?? .easy != difficulty {
            GameSessionStore.delete(.blockBlast)
        }
    }

    /// Just the difficulty of a saved round; rounds saved before there was
    /// a choice were dealt like easy ones.
    private struct SavedDifficulty: Decodable {
        let difficulty: BlockBlastDifficulty?
    }

    init() {
        difficulty = Self.savedDifficulty
        grid = Array(repeating: Array(repeating: nil, count: Self.size), count: Self.size)
        refillTray()
    }

    func restart() {
        grid = Array(repeating: Array(repeating: nil, count: Self.size), count: Self.size)
        score = 0
        combo = 0
        comboGraceLeft = 0
        flashCells = [:]
        popups.clear()
        history = []
        refillTray()
        state = .playing
    }

    /// Takes back the last placement, including any lines it cleared.
    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        grid = previous.grid
        tray = previous.tray
        score = previous.score
        combo = previous.combo
        comboGraceLeft = previous.comboGraceLeft
        flashCells = [:]
        Haptics.tap()
        SoundFX.play(.tap)
    }

    /// Deals three pieces chosen for the board as it stands. Each one is
    /// tried on a copy of the board, placed where it fits best, before the
    /// next is chosen, so the whole set can always be placed in that order:
    /// easy picks the best fits, hard the worst ones that still fit.
    private func refillTray() {
        var dealer = BlockBlastDealer(grid: grid.map { $0.map { $0 != nil } }, difficulty: difficulty)
        let shapes = dealer.deal()
        tray = shapes.map { BBPiece(cells: $0, colorIndex: Int.random(in: 0..<Self.colors.count)) }
    }

    func canPlace(_ piece: BBPiece, at origin: GridPos) -> Bool {
        for cell in piece.cells {
            let r = origin.r + cell.r
            let c = origin.c + cell.c
            guard (0..<Self.size).contains(r), (0..<Self.size).contains(c),
                  grid[r][c] == nil else { return false }
        }
        return true
    }

    func canPlaceAnywhere(_ piece: BBPiece) -> Bool {
        for r in 0..<Self.size {
            for c in 0..<Self.size where canPlace(piece, at: GridPos(r: r, c: c)) {
                return true
            }
        }
        return false
    }

    /// Rows and columns that would be completed by dropping `piece` at `origin`.
    func linesCompleted(by piece: BBPiece, at origin: GridPos) -> Set<GridPos> {
        guard canPlace(piece, at: origin) else { return [] }
        let n = Self.size
        let added = Set(piece.cells.map { GridPos(r: origin.r + $0.r, c: origin.c + $0.c) })
        func filled(_ r: Int, _ c: Int) -> Bool { grid[r][c] != nil || added.contains(GridPos(r: r, c: c)) }
        var out = Set<GridPos>()
        for r in Set(added.map(\.r)) where (0..<n).allSatisfy({ filled(r, $0) }) {
            for c in 0..<n { out.insert(GridPos(r: r, c: c)) }
        }
        for c in Set(added.map(\.c)) where (0..<n).allSatisfy({ filled($0, c) }) {
            for r in 0..<n { out.insert(GridPos(r: r, c: c)) }
        }
        return out
    }

    /// Places the tray piece with its top-left shape cell at `origin`.
    @discardableResult
    func place(trayIndex: Int, at origin: GridPos) -> Bool {
        guard state == .playing,
              tray.indices.contains(trayIndex),
              let piece = tray[trayIndex],
              canPlace(piece, at: origin) else { return false }

        history.append(Snapshot(grid: grid, tray: tray, score: score,
                                combo: combo, comboGraceLeft: comboGraceLeft))
        for cell in piece.cells {
            grid[origin.r + cell.r][origin.c + cell.c] = piece.colorIndex
        }
        score += piece.cells.count
        tray[trayIndex] = nil

        let (cleared, cells) = clearFullLines()
        if cleared > 0 {
            combo += 1
            comboGraceLeft = Self.comboGrace
            // Multi-line clears pay off quadratically; streaks multiply them.
            let gained = cleared * cleared * 10 * combo
            score += gained
            let center = UnitPoint(
                x: (Double(cells.map(\.c).reduce(0, +)) / Double(max(cells.count, 1)) + 0.5) / Double(Self.size),
                y: (Double(cells.map(\.r).reduce(0, +)) / Double(max(cells.count, 1)) + 0.5) / Double(Self.size))
            popups.show("+\(gained)", color: .white, at: center, large: cleared > 1)
            if combo > 1 {
                popups.show(L10n.format("Combo ×%d", combo), color: .yellow,
                            at: UnitPoint(x: center.x, y: max(0.12, center.y - 0.14)), large: true)
            }
            if grid.allSatisfy({ $0.allSatisfy { $0 == nil } }) {
                score += 300
                popups.show(L10n.text("Board clear! +300"), color: .mint, at: UnitPoint(x: 0.5, y: 0.5), large: true)
            }
            if combo > 1 || cleared > 1 { Haptics.heavy() } else { Haptics.success() }
            SoundFX.play(combo > 2 ? .coin : .clear)
        } else {
            if comboGraceLeft > 0 { comboGraceLeft -= 1 }
            if comboGraceLeft == 0 { combo = 0 }
            Haptics.move(); SoundFX.play(.place)
        }

        if tray.allSatisfy({ $0 == nil }) { refillTray() }

        if !tray.compactMap({ $0 }).contains(where: canPlaceAnywhere) {
            state = .gameOver(won: false)
        }
        return true
    }

    private func clearFullLines() -> (Int, Set<GridPos>) {
        let n = Self.size
        let fullRows = (0..<n).filter { r in (0..<n).allSatisfy { grid[r][$0] != nil } }
        let fullCols = (0..<n).filter { c in (0..<n).allSatisfy { grid[$0][c] != nil } }
        var cells = Set<GridPos>()
        for r in fullRows { for c in 0..<n { cells.insert(GridPos(r: r, c: c)) } }
        for c in fullCols { for r in 0..<n { cells.insert(GridPos(r: r, c: c)) } }
        guard !cells.isEmpty else { return (0, []) }
        var flash: [GridPos: Int] = [:]
        for p in cells {
            if let color = grid[p.r][p.c] { flash[p] = color }
            grid[p.r][p.c] = nil
        }
        flashCells = flash
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeIn(duration: 0.32)) { self?.flashCells = [:] }
        }
        return (fullRows.count + fullCols.count, cells)
    }
}

// MARK: - View

struct BlockBlastView: View {
    @State private var engine = BlockBlastEngine()
    @State private var gridFrame: CGRect = .zero
    @State private var dragIndex: Int?
    @State private var dragLocation: CGPoint = .zero
    @State private var dragStart: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let space = "blockblast"
    /// The dragged piece floats above the finger so it stays visible.
    private static let lift: CGFloat = 90
    /// Upward finger travel is amplified by this much, so the top rows are
    /// reachable without stretching across the whole board.
    private static let reach: CGFloat = 1.8
    /// Sideways finger travel is amplified the same way, so the side columns
    /// are reachable from any tray slot.
    private static let horizontalReach: CGFloat = 1.5
    /// Figma: 4pt gaps and padding on the board, 8pt between tray slots.
    private static let gap: CGFloat = 4

    var body: some View {
        GameContainerView(gameID: .blockBlast, engine: engine,
                          resultSummary: L10n.text(engine.difficulty.title)) {
            // Figma: a full-width 370pt board, 118pt tray slots and 32pt gaps.
            // The board claims its square first, then the tray; the gaps
            // shrink towards 8pt to make room below the score row.
            VStack(spacing: 0) {
                boardView
                    .layoutPriority(2)
                Spacer(minLength: 8).frame(maxHeight: 32)
                trayView
                    .layoutPriority(1)
                Spacer(minLength: 8).frame(maxHeight: 32)
                revertButton
            }
            .frame(maxHeight: .infinity)
            // The Revert label may sit down to the home indicator; the
            // container's bottom padding would otherwise squeeze the tray.
            .padding(.bottom, -16)
            .coordinateSpace(name: Self.space)
            // Overlay so the dragged piece never affects layout — the board
            // must not move while a drag is in progress.
            .overlay { floatingPiece }
        }
    }

    // MARK: Drop target math

    /// Cell size plus one gap: the grid is `size` cells and `size - 1` gaps wide.
    private var cellPitch: CGFloat {
        (gridFrame.width + Self.gap) / CGFloat(BlockBlastEngine.size)
    }

    private typealias DropTarget = (origin: GridPos, valid: Bool, cells: Set<GridPos>, clears: Set<GridPos>)

    private var dropTarget: DropTarget? {
        guard let index = dragIndex,
              engine.tray.indices.contains(index),
              let piece = engine.tray[index],
              gridFrame != .zero else { return nil }
        let center = pieceCenter(for: piece)
        let x = (center.x - gridFrame.minX + Self.gap / 2) / cellPitch - CGFloat(piece.width) / 2
        let y = (center.y - gridFrame.minY + Self.gap / 2) / cellPitch - CGFloat(piece.height) / 2
        let origin = GridPos(r: Int(y.rounded()), c: Int(x.rounded()))
        let cells = Set(piece.cells.map { GridPos(r: origin.r + $0.r, c: origin.c + $0.c) })
        return (origin, engine.canPlace(piece, at: origin), cells, engine.linesCompleted(by: piece, at: origin))
    }

    /// Where the dragged piece is drawn: above the finger, pulling further
    /// ahead the further the finger moves up or sideways, but never past the
    /// top row or the side columns.
    private func pieceCenter(for piece: BBPiece) -> CGPoint {
        let climbed = max(0, dragStart.y - dragLocation.y)
        let y = dragLocation.y - Self.lift - climbed * (Self.reach - 1)
        let topRow = gridFrame.minY + (CGFloat(piece.height) * cellPitch - Self.gap) / 2
        let x = dragStart.x + (dragLocation.x - dragStart.x) * Self.horizontalReach
        let halfWidth = (CGFloat(piece.width) * cellPitch - Self.gap) / 2
        return CGPoint(x: min(max(x, gridFrame.minX + halfWidth), gridFrame.maxX - halfWidth),
                       y: max(y, topRow))
    }

    // MARK: Board

    private var boardView: some View {
        let target = dropTarget
        return VStack(spacing: Self.gap) {
            ForEach(0..<BlockBlastEngine.size, id: \.self) { r in
                HStack(spacing: Self.gap) {
                    ForEach(0..<BlockBlastEngine.size, id: \.self) { c in
                        boardCell(r: r, c: c, target: target)
                    }
                }
            }
        }
        .overlay {
            GeometryReader { geo in
                Color.clear.preference(key: GridFrameKey.self,
                                       value: geo.frame(in: .named(Self.space)))
            }
        }
        .onPreferenceChange(GridFrameKey.self) { gridFrame = $0 }
        .overlay { ClassicFXPopupLayer(feed: engine.popups) }
        .padding(Self.gap)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func boardCell(r: Int, c: Int, target: DropTarget?) -> some View {
        let pos = GridPos(r: r, c: c)
        let colorIndex = engine.grid[r][c]
        let isPreview = target?.cells.contains(pos) ?? false
        let willClear = target?.clears.contains(pos) ?? false
        let previewColor = dragIndex.flatMap { engine.tray.indices.contains($0) ? engine.tray[$0]?.colorIndex : nil }

        ZStack {
            if let colorIndex {
                BlockBlastCell(color: BlockBlastEngine.colors[colorIndex])
            } else if isPreview, let previewColor, target?.valid == true {
                BlockBlastCell(color: BlockBlastEngine.colors[previewColor]).opacity(0.5)
            } else {
                BlockBlastCell(color: isPreview ? Color.red.opacity(0.35) : Color(.tertiarySystemBackground))
            }
            if willClear {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary, lineWidth: 2)
            }
            if let flash = engine.flashCells[pos] {
                BlockBlastCell(color: BlockBlastEngine.colors[flash])
                    .overlay { RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.55)) }
                    .transition(.asymmetric(insertion: .identity,
                                            removal: reduceMotion ? .opacity : .scale(scale: 0.05).combined(with: .opacity)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tray

    /// Figma: three square slots, 8pt apart, flush with the board edges.
    private var trayView: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                traySlot(index)
            }
        }
        .frame(maxHeight: 118)
    }

    @ViewBuilder
    private func traySlot(_ index: Int) -> some View {
        let piece = engine.tray.indices.contains(index) ? engine.tray[index] : nil
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(.secondarySystemBackground))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let piece, dragIndex != index {
                    // Figma tray blocks: 24pt cells, 2pt apart (scaled down for the 3×3).
                    PieceView(piece: piece, cellSize: piece.width > 3 || piece.height > 3 ? 18 : 24, spacing: 2)
                        .opacity(engine.canPlaceAnywhere(piece) ? 1 : 0.3)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(for: index), including: piece == nil ? .none : .all)
    }

    private func dragGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragIndex == nil {
                    dragStart = value.startLocation
                    Haptics.tap(); SoundFX.play(.tap)
                }
                dragIndex = index
                dragLocation = value.location
            }
            .onEnded { value in
                dragLocation = value.location
                if let target = dropTarget, target.valid {
                    withAnimation(.snappy(duration: 0.25)) {
                        _ = engine.place(trayIndex: index, at: target.origin)
                    }
                }
                dragIndex = nil
            }
    }

    // MARK: Revert

    /// Figma "Revert": a 50pt glass undo button over a Title 1 label.
    private var revertButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { engine.undo() }
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .glassCircle()
                Text(L10n.text("Revert"))
                    .font(.title)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(!engine.canUndo)
        .opacity(engine.canUndo ? 1 : 0.4)
    }

    @ViewBuilder
    private var floatingPiece: some View {
        if let index = dragIndex,
           engine.tray.indices.contains(index),
           let piece = engine.tray[index],
           gridFrame != .zero {
            PieceView(piece: piece, cellSize: cellPitch - Self.gap, spacing: Self.gap)
                .position(pieceCenter(for: piece))
                .allowsHitTesting(false)
                .shadow(radius: 8, y: 4)
        }
    }
}

// MARK: - Piece rendering

struct PieceView: View {
    let piece: BBPiece
    let cellSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        let pitch = cellSize + spacing
        ZStack(alignment: .topLeading) {
            ForEach(Array(piece.cells.enumerated()), id: \.offset) { _, cell in
                BlockBlastCell(color: BlockBlastEngine.colors[piece.colorIndex])
                    .frame(width: cellSize, height: cellSize)
                    .offset(x: CGFloat(cell.c) * pitch, y: CGFloat(cell.r) * pitch)
            }
        }
        .frame(width: CGFloat(piece.width) * pitch - spacing,
               height: CGFloat(piece.height) * pitch - spacing,
               alignment: .topLeading)
    }
}

/// A flat block with a 4pt corner, as in the Figma board.
struct BlockBlastCell: View {
    let color: Color
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius).fill(color)
    }
}

private struct GridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

// MARK: - Saved round

extension BlockBlastEngine: ResumableGame {
    private struct Session: Codable {
        let board: Snapshot
        let history: [Snapshot]
        var difficulty: BlockBlastDifficulty?
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, !history.isEmpty else { return nil }
        return encodeSession(Session(board: Snapshot(grid: grid, tray: tray, score: score,
                                                     combo: combo, comboGraceLeft: comboGraceLeft),
                                     history: history, difficulty: difficulty))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        grid = session.board.grid
        tray = session.board.tray
        score = session.board.score
        combo = session.board.combo
        comboGraceLeft = session.board.comboGraceLeft
        history = session.history
        difficulty = session.difficulty ?? .easy
        flashCells = [:]
        popups.clear()
        state = .playing
        return true
    }
}

// MARK: - Dealing

/// Picks the next three tray shapes for a board, by difficulty.
private struct BlockBlastDealer {
    var grid: [[Bool]]
    let difficulty: BlockBlastDifficulty

    private static let n = BlockBlastEngine.size

    /// Where a shape fits best, and how well: cleared lines count most, then
    /// how snugly it sits against blocks and walls, per block so big and
    /// small pieces compare fairly.
    private struct Fit {
        let shape: [GridPos]
        let origin: GridPos
        let lines: Int
        let snug: Int
        var value: Int { lines * 100 + snug * 10 / shape.count }
    }

    mutating func deal() -> [[GridPos]] {
        var dealt: [[GridPos]] = []
        for _ in 0..<3 {
            let fits = BlockBlastEngine.shapes.compactMap(bestFit)
            // A full board takes nothing: deal at random and let the round end.
            guard let fit = choose(from: fits) else {
                dealt.append(BlockBlastEngine.shapes.randomElement()!)
                continue
            }
            dealt.append(fit.shape)
            place(fit)
        }
        return dealt.shuffled()
    }

    /// Easy mostly hands out one of the best fits, hard mostly one of the
    /// worst; every so often either deals any shape that fits, so the tray
    /// never feels scripted. Medium is plain random among shapes that fit.
    private func choose(from fits: [Fit]) -> Fit? {
        guard !fits.isEmpty else { return nil }
        let ranked = fits.sorted { $0.value > $1.value }
        let top = max(1, ranked.count / 4)
        switch difficulty {
        case .easy:
            return Double.random(in: 0..<1) < 0.75 ? ranked.prefix(top).randomElement() : ranked.randomElement()
        case .medium:
            return ranked.randomElement()
        case .hard:
            // Among the awkward ones, the bigger the piece the harder it is.
            let awkward = ranked.suffix(max(top, 6)).sorted { $0.shape.count > $1.shape.count }
            return Double.random(in: 0..<1) < 0.7 ? awkward.prefix(top).randomElement() : ranked.randomElement()
        }
    }

    private func bestFit(_ shape: [GridPos]) -> Fit? {
        var best: Fit?
        for r in 0..<Self.n {
            for c in 0..<Self.n {
                let origin = GridPos(r: r, c: c)
                guard let fit = fit(shape, at: origin) else { continue }
                if best.map({ fit.value > $0.value }) ?? true { best = fit }
            }
        }
        return best
    }

    private func fit(_ shape: [GridPos], at origin: GridPos) -> Fit? {
        let cells = shape.map { GridPos(r: origin.r + $0.r, c: origin.c + $0.c) }
        guard cells.allSatisfy({ (0..<Self.n).contains($0.r) && (0..<Self.n).contains($0.c) && !grid[$0.r][$0.c] })
        else { return nil }
        let added = Set(cells)
        func filled(_ r: Int, _ c: Int) -> Bool { grid[r][c] || added.contains(GridPos(r: r, c: c)) }
        let rows = Set(cells.map(\.r)).filter { r in (0..<Self.n).allSatisfy { filled(r, $0) } }.count
        let cols = Set(cells.map(\.c)).filter { c in (0..<Self.n).allSatisfy { filled($0, c) } }.count
        var snug = 0
        for cell in cells {
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let r = cell.r + dr, c = cell.c + dc
                if !(0..<Self.n).contains(r) || !(0..<Self.n).contains(c) {
                    snug += 1
                } else if grid[r][c] {
                    snug += 2
                }
            }
        }
        return Fit(shape: shape, origin: origin, lines: rows + cols, snug: snug)
    }

    /// Drops the piece on the copy of the board and clears what it completes.
    private mutating func place(_ fit: Fit) {
        for cell in fit.shape { grid[fit.origin.r + cell.r][fit.origin.c + cell.c] = true }
        let rows = (0..<Self.n).filter { r in grid[r].allSatisfy { $0 } }
        let cols = (0..<Self.n).filter { c in (0..<Self.n).allSatisfy { grid[$0][c] } }
        for r in rows { for c in 0..<Self.n { grid[r][c] = false } }
        for c in cols { for r in 0..<Self.n { grid[r][c] = false } }
    }
}
