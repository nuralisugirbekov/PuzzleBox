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

@MainActor
@Observable
final class BlockBlastEngine: GameEngine {
    static let size = 8
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

    init() {
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

    /// Deals three random pieces, re-rolling a few times so at least one fits.
    private func refillTray() {
        for attempt in 0..<12 {
            let pieces = (0..<3).map { _ in
                BBPiece(cells: Self.shapes.randomElement()!,
                        colorIndex: Int.random(in: 0..<Self.colors.count))
            }
            tray = pieces
            if attempt == 11 || pieces.contains(where: canPlaceAnywhere) { return }
        }
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
    /// Figma: 4pt gaps and padding on the board, 8pt between tray slots.
    private static let gap: CGFloat = 4

    var body: some View {
        GameContainerView(gameID: .blockBlast, engine: engine) {
            // Figma spaces these 32pt apart; 24pt keeps the board full width
            // below the score row on a 6.3" screen.
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                boardView
                trayView
                revertButton
                Spacer(minLength: 0)
            }
            .coordinateSpace(name: Self.space)
            // Overlay so the dragged piece never affects layout — the board
            // must not move while a drag is in progress.
            .overlay { floatingPiece }
        }
    }

    // MARK: Drop target math

    private var cellPitch: CGFloat {
        gridFrame.width / CGFloat(BlockBlastEngine.size)
    }

    private typealias DropTarget = (origin: GridPos, valid: Bool, cells: Set<GridPos>, clears: Set<GridPos>)

    private var dropTarget: DropTarget? {
        guard let index = dragIndex,
              engine.tray.indices.contains(index),
              let piece = engine.tray[index],
              gridFrame != .zero else { return nil }
        let center = pieceCenter(for: piece)
        let x = (center.x - gridFrame.minX) / cellPitch - CGFloat(piece.width) / 2
        let y = (center.y - gridFrame.minY) / cellPitch - CGFloat(piece.height) / 2
        let origin = GridPos(r: Int(y.rounded()), c: Int(x.rounded()))
        let cells = Set(piece.cells.map { GridPos(r: origin.r + $0.r, c: origin.c + $0.c) })
        return (origin, engine.canPlace(piece, at: origin), cells, engine.linesCompleted(by: piece, at: origin))
    }

    /// Where the dragged piece is drawn: above the finger, pulling further
    /// ahead the higher the finger moves, but never past the top row.
    private func pieceCenter(for piece: BBPiece) -> CGPoint {
        let climbed = max(0, dragStart.y - dragLocation.y)
        let y = dragLocation.y - Self.lift - climbed * (Self.reach - 1)
        let topRow = gridFrame.minY + CGFloat(piece.height) * cellPitch / 2
        return CGPoint(x: dragLocation.x, y: max(y, topRow))
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

    /// Figma: three square slots, 8pt apart and 8pt in from the board edges.
    private var trayView: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                traySlot(index)
            }
        }
        .padding(.horizontal, 8)
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
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, !history.isEmpty else { return nil }
        return encodeSession(Session(board: Snapshot(grid: grid, tray: tray, score: score,
                                                     combo: combo, comboGraceLeft: comboGraceLeft),
                                     history: history))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        grid = session.board.grid
        tray = session.board.tray
        score = session.board.score
        combo = session.board.combo
        comboGraceLeft = session.board.comboGraceLeft
        history = session.history
        flashCells = [:]
        popups.clear()
        state = .playing
        return true
    }
}
