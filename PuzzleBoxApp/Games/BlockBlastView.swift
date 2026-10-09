import SwiftUI
import Observation

// MARK: - Engine

struct BBPiece: Identifiable, Equatable {
    let id = UUID()
    let cells: [GridPos]  // normalized: min row/col is 0
    let colorIndex: Int

    var width: Int { (cells.map(\.c).max() ?? 0) + 1 }
    var height: Int { (cells.map(\.r).max() ?? 0) + 1 }
}

@MainActor
@Observable
final class BlockBlastEngine: GameEngine {
    static let size = 8
    static let colors: [Color] = [.orange, .pink, .teal, .purple, .blue, .yellow]

    static let shapes: [[GridPos]] = [
        [GridPos(r: 0, c: 0)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1)],
        [GridPos(r: 0, c: 0), GridPos(r: 1, c: 0)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 0, c: 2)],
        [GridPos(r: 0, c: 0), GridPos(r: 1, c: 0), GridPos(r: 2, c: 0)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 0, c: 2), GridPos(r: 0, c: 3)],
        [GridPos(r: 0, c: 0), GridPos(r: 1, c: 0), GridPos(r: 2, c: 0), GridPos(r: 3, c: 0)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 1, c: 0), GridPos(r: 1, c: 1)],
        [GridPos(r: 0, c: 0), GridPos(r: 1, c: 0), GridPos(r: 1, c: 1)],
        [GridPos(r: 0, c: 1), GridPos(r: 1, c: 0), GridPos(r: 1, c: 1)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 1, c: 1)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 1, c: 0)],
        [GridPos(r: 0, c: 0), GridPos(r: 1, c: 0), GridPos(r: 2, c: 0), GridPos(r: 2, c: 1)],
        [GridPos(r: 0, c: 0), GridPos(r: 0, c: 1), GridPos(r: 0, c: 2), GridPos(r: 1, c: 0)],
    ]

    private(set) var grid: [[Int?]]
    private(set) var tray: [BBPiece?] = []
    private(set) var score = 0
    var state: GameState = .playing

    init() {
        grid = Array(repeating: Array(repeating: nil, count: Self.size), count: Self.size)
        refillTray()
    }

    func restart() {
        grid = Array(repeating: Array(repeating: nil, count: Self.size), count: Self.size)
        score = 0
        refillTray()
        state = .playing
    }

    private func refillTray() {
        tray = (0..<3).map { _ in
            BBPiece(cells: Self.shapes.randomElement()!,
                    colorIndex: Int.random(in: 0..<Self.colors.count))
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

    private func canPlaceAnywhere(_ piece: BBPiece) -> Bool {
        for r in 0..<Self.size {
            for c in 0..<Self.size where canPlace(piece, at: GridPos(r: r, c: c)) {
                return true
            }
        }
        return false
    }

    /// Places the tray piece with its top-left shape cell at `origin`.
    @discardableResult
    func place(trayIndex: Int, at origin: GridPos) -> Bool {
        guard state == .playing,
              tray.indices.contains(trayIndex),
              let piece = tray[trayIndex],
              canPlace(piece, at: origin) else { return false }

        for cell in piece.cells {
            grid[origin.r + cell.r][origin.c + cell.c] = piece.colorIndex
        }
        score += piece.cells.count
        tray[trayIndex] = nil

        let cleared = clearFullLines()
        if cleared > 0 {
            score += cleared * cleared * 10  // multi-line combos pay off quadratically
            Haptics.success()
        } else {
            Haptics.move()
        }

        if tray.allSatisfy({ $0 == nil }) { refillTray() }

        if !tray.compactMap({ $0 }).contains(where: canPlaceAnywhere) {
            state = .gameOver(won: false)
        }
        return true
    }

    private func clearFullLines() -> Int {
        let n = Self.size
        let fullRows = (0..<n).filter { r in (0..<n).allSatisfy { grid[r][$0] != nil } }
        let fullCols = (0..<n).filter { c in (0..<n).allSatisfy { grid[$0][c] != nil } }
        withAnimation(.easeOut(duration: 0.25)) {
            for r in fullRows { for c in 0..<n { grid[r][c] = nil } }
            for c in fullCols { for r in 0..<n { grid[r][c] = nil } }
        }
        return fullRows.count + fullCols.count
    }
}

// MARK: - View

struct BlockBlastView: View {
    @State private var engine = BlockBlastEngine()
    @State private var gridFrame: CGRect = .zero
    @State private var dragIndex: Int?
    @State private var dragLocation: CGPoint = .zero

    private static let space = "blockblast"
    /// The dragged piece floats above the finger so it stays visible.
    private static let lift: CGFloat = 60

    var body: some View {
        GameContainerView(gameID: .blockBlast, engine: engine) {
            VStack(spacing: 28) {
                boardView
                trayView
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

    private var dropTarget: (origin: GridPos, valid: Bool, cells: Set<GridPos>)? {
        guard let index = dragIndex,
              engine.tray.indices.contains(index),
              let piece = engine.tray[index],
              gridFrame != .zero else { return nil }
        let x = (dragLocation.x - gridFrame.minX) / cellPitch - CGFloat(piece.width) / 2
        let y = (dragLocation.y - Self.lift - gridFrame.minY) / cellPitch - CGFloat(piece.height) / 2
        let origin = GridPos(r: Int(y.rounded()), c: Int(x.rounded()))
        let cells = Set(piece.cells.map { GridPos(r: origin.r + $0.r, c: origin.c + $0.c) })
        return (origin, engine.canPlace(piece, at: origin), cells)
    }

    // MARK: Board

    private var boardView: some View {
        let target = dropTarget
        return VStack(spacing: 2) {
            ForEach(0..<BlockBlastEngine.size, id: \.self) { r in
                HStack(spacing: 2) {
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
        .padding(6)
        .gameCard(cornerRadius: 16)
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func boardCell(r: Int, c: Int, target: (origin: GridPos, valid: Bool, cells: Set<GridPos>)?) -> some View {
        let pos = GridPos(r: r, c: c)
        let colorIndex = engine.grid[r][c]
        let isPreview = target?.cells.contains(pos) ?? false

        RoundedRectangle(cornerRadius: 4)
            .fill(cellFill(colorIndex: colorIndex, isPreview: isPreview, previewValid: target?.valid ?? false))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
    }

    private func cellFill(colorIndex: Int?, isPreview: Bool, previewValid: Bool) -> AnyShapeStyle {
        if let colorIndex {
            return AnyShapeStyle(BlockBlastEngine.colors[colorIndex].gradient)
        }
        if isPreview {
            return AnyShapeStyle(previewValid ? GameTheme.accent.opacity(0.45) : Color.red.opacity(0.3))
        }
        return AnyShapeStyle(GameTheme.background)
    }

    // MARK: Tray

    private var trayView: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { index in
                traySlot(index)
            }
        }
        .frame(height: 92)
    }

    @ViewBuilder
    private func traySlot(_ index: Int) -> some View {
        let piece = engine.tray.indices.contains(index) ? engine.tray[index] : nil
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(GameTheme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(GameTheme.stroke, lineWidth: 1)
                }
            if let piece, dragIndex != index {
                PieceView(piece: piece, cellSize: 16, spacing: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(dragGesture(for: index), including: piece == nil ? .none : .all)
    }

    private func dragGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragIndex == nil { Haptics.tap() }
                dragIndex = index
                dragLocation = value.location
            }
            .onEnded { value in
                dragLocation = value.location
                if let target = dropTarget, target.valid {
                    engine.place(trayIndex: index, at: target.origin)
                }
                dragIndex = nil
            }
    }

    @ViewBuilder
    private var floatingPiece: some View {
        if let index = dragIndex,
           engine.tray.indices.contains(index),
           let piece = engine.tray[index],
           gridFrame != .zero {
            PieceView(piece: piece, cellSize: cellPitch - 2, spacing: 2)
                .position(x: dragLocation.x, y: dragLocation.y - Self.lift)
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
                RoundedRectangle(cornerRadius: cellSize * 0.2)
                    .fill(BlockBlastEngine.colors[piece.colorIndex].gradient)
                    .frame(width: cellSize, height: cellSize)
                    .offset(x: CGFloat(cell.c) * pitch, y: CGFloat(cell.r) * pitch)
            }
        }
        .frame(width: CGFloat(piece.width) * pitch - spacing,
               height: CGFloat(piece.height) * pitch - spacing,
               alignment: .topLeading)
    }
}

private struct GridFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
