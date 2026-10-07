import SwiftUI

struct PuzzleCollectionView: View {
    @State private var engine: PuzzleCollectionEngine
    @State private var lastCell: Int?
    init(mode: PuzzleMode) { _engine = State(initialValue: PuzzleCollectionEngine(mode: mode)) }
    private let colors: [Color] = [.clear, .cyan, .pink, .orange, .green, .purple]
    private var sliding: Bool { engine.mode == .unblock || engine.mode == .parkingJam }

    var body: some View {
        GameContainerView(gameID: engine.mode.id, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.format("%d moves", engine.moves))
                    Spacer()
                    if engine.mode == .dots || engine.mode == .floodFill {
                        Text(L10n.format("%d moves left", engine.movesLeft))
                    }
                    if engine.canUndo { Button { engine.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel(L10n.text("Undo")) }
                }.font(.subheadline.monospacedDigit()).foregroundStyle(Theme.neon)
                GeometryReader { geometry in
                    Canvas { context, size in draw(&context, size: size) }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let cell = index(value.location, size: geometry.size) else { return }
                                if sliding {
                                    if lastCell == nil, let start = index(value.startLocation, size: geometry.size) { engine.tap(start); lastCell = start }
                                } else if [.dots, .numberConnect, .oneLine].contains(engine.mode), lastCell != cell {
                                    engine.tap(cell); lastCell = cell
                                }
                            }
                            .onEnded { value in
                                if sliding {
                                    let dx = value.translation.width, dy = value.translation.height
                                    if max(abs(dx), abs(dy)) > 15 {
                                        engine.slide(dr: abs(dy) > abs(dx) ? (dy > 0 ? 1 : -1) : 0,
                                                     dc: abs(dx) >= abs(dy) ? (dx > 0 ? 1 : -1) : 0)
                                    }
                                } else if engine.mode == .dots {
                                    if hypot(value.translation.width, value.translation.height) > 12 { engine.collectDots() }
                                } else if ![.numberConnect, .oneLine].contains(engine.mode), let cell = index(value.location, size: geometry.size) { engine.tap(cell) }
                                lastCell = nil
                            })
                }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 420)
                controls
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private var controls: some View {
        if engine.mode == .nonogram {
            Picker("", selection: $engine.markMode) {
                Text(L10n.text("Fill")).tag(false)
                Text(L10n.text("Mark empty")).tag(true)
            }.pickerStyle(.segmented)
        }
        if sliding {
            HStack(spacing: 24) {
                arrow("arrow.left", dr: 0, dc: -1); arrow("arrow.up", dr: -1, dc: 0)
                arrow("arrow.down", dr: 1, dc: 0); arrow("arrow.right", dr: 0, dc: 1)
            }.disabled(engine.selected == nil)
        }
        if engine.mode == .dots {
            Button(L10n.text("Collect")) { engine.collectDots() }.buttonStyle(.borderedProminent).tint(Theme.neon)
                .disabled(engine.activePath.count < 2)
        }
        if engine.mode == .floodFill {
            HStack {
                ForEach(1...5, id: \.self) { color in
                    Button { engine.flood(color) } label: {
                        Circle().fill(colors[color]).frame(width: 40, height: 40)
                            .overlay { if engine.grid[0] == color { Image(systemName: "checkmark").foregroundStyle(.black) } }
                    }.accessibilityLabel("\(color)")
                }
            }
        }
        if engine.mode == .balanceScale {
            Text(L10n.text(engine.guessing ? "Tap the heavier item" : "Tap items: left, right, off")).font(.caption)
            Text(L10n.text(engine.weighing)).font(.subheadline).foregroundStyle(Theme.neon)
            HStack {
                Button(L10n.text("Weigh") + " (\(engine.weighings)/2)") { engine.weigh() }.disabled(engine.weighings >= 2 || engine.guessing)
                Button(L10n.text("Guess")) { engine.guessing = true }.disabled(engine.guessing)
            }.buttonStyle(.bordered)
        }
    }
    private func arrow(_ symbol: String, dr: Int, dc: Int) -> some View {
        Button { engine.slide(dr: dr, dc: dc) } label: { Image(systemName: symbol).frame(width: 40, height: 40) }.buttonStyle(.bordered)
    }
    private func layout(_ size: CGSize) -> (CGFloat, CGFloat) {
        let margin: CGFloat = engine.mode == .nonogram ? 48 : 12
        return (margin, (min(size.width, size.height) - margin - 12) / CGFloat(engine.n))
    }
    private func index(_ p: CGPoint, size: CGSize) -> Int? {
        let (margin, cell) = layout(size)
        let x = p.x - margin, y = p.y - margin
        guard x >= 0, y >= 0, x < cell * CGFloat(engine.n), y < cell * CGFloat(engine.n) else { return nil }
        return Int(y / cell) * engine.n + Int(x / cell)
    }
    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let (margin, cell) = layout(size), n = engine.n
        func center(_ i: Int) -> CGPoint { CGPoint(x: margin + (CGFloat(i % n) + 0.5) * cell, y: margin + (CGFloat(i / n) + 0.5) * cell) }
        func rect(_ i: Int) -> CGRect { CGRect(x: margin + CGFloat(i % n) * cell + 2, y: margin + CGFloat(i / n) * cell + 2, width: cell - 4, height: cell - 4) }
        func line(_ points: [CGPoint], _ color: Color, _ width: CGFloat) {
            guard let first = points.first else { return }
            var path = Path(); path.move(to: first); for p in points.dropFirst() { path.addLine(to: p) }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        func text(_ text: String, _ point: CGPoint, _ color: Color = .white, _ font: CGFloat = 18) {
            context.draw(Text(verbatim: text).font(.system(size: font, weight: .bold)).foregroundStyle(color), at: point)
        }
        if engine.mode == .nonogram {
            for i in 0..<n {
                text(engine.rowClues[i].map(String.init).joined(separator: " "), CGPoint(x: margin / 2, y: center(i * n).y), .white, 12)
                text(engine.columnClues[i].map(String.init).joined(separator: "\n"), CGPoint(x: center(i).x, y: margin / 2), .white, 12)
            }
        }
        if engine.mode == .oneLine {
            for edge in engine.edges { line(edge.map(center), Theme.textSecondary.opacity(0.5), 5) }
            line(engine.activePath.map(center), Theme.neon, 7)
            for i in engine.nodes {
                context.fill(Path(ellipseIn: rect(i).insetBy(dx: cell * 0.24, dy: cell * 0.24)), with: .color(engine.activePath.last == i ? Theme.neon : .cyan))
            }
            return
        }
        for i in engine.grid.indices {
            let value = engine.grid[i], r = rect(i), p = center(i)
            var fill = Theme.surfaceHigh
            if engine.mode == .lightsOut && value == 1 { fill = .yellow }
            if engine.mode == .nonogram && value == 1 { fill = .cyan }
            if [.sameGame, .floodFill].contains(engine.mode) { fill = colors[value] }
            if engine.mode == .fifteenPuzzle { fill = value == 0 ? Theme.surface : .indigo }
            context.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(fill))
            switch engine.mode {
            case .nonogram: if engine.marks.contains(i) { text("×", p, Theme.textSecondary) }
            case .fifteenPuzzle: if value > 0 { text(String(value), p) }
            case .numberConnect:
                if value > 0 { context.fill(Path(ellipseIn: r.insetBy(dx: 6, dy: 6)), with: .color(colors[value])); text(String(value), p, .black) }
            case .dots, .colorLines:
                if value > 0 {
                    context.fill(Path(ellipseIn: r.insetBy(dx: cell * 0.15, dy: cell * 0.15)), with: .color(colors[value]))
                    if engine.selected == i { context.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: 2) }
                }
            case .pipeConnect:
                for (bit, dx, dy) in [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0)] where value & bit != 0 {
                    line([p, CGPoint(x: p.x + CGFloat(dx) * cell / 2, y: p.y + CGFloat(dy) * cell / 2)], engine.beam.contains(i) ? .cyan : .gray, 8)
                }
                if i == 0 { text("→", CGPoint(x: margin / 2, y: p.y), .cyan) }
                if i == 12 { text("↓", CGPoint(x: p.x, y: margin + cell * 4 + 5), .cyan, 13) }
            case .laser:
                if value > 0 {
                    let dx = cell * 0.3, dy = value == 1 ? -dx : dx
                    line([CGPoint(x: p.x - dx, y: p.y - dy), CGPoint(x: p.x + dx, y: p.y + dy)], .white, 5)
                }
                if i == 10 { text("→", p, .yellow) }; if i == 15 { text("★", p, .yellow) }
            case .balanceScale:
                text(String(i + 1), CGPoint(x: p.x, y: p.y - 10), .white, 24)
                if value > 0 { text(L10n.text(value == 1 ? "Left" : "Right"), CGPoint(x: p.x, y: p.y + 19), value == 1 ? .cyan : .pink, 12) }
            default: break
            }
        }
        if engine.mode == .numberConnect {
            for (color, path) in engine.paths { line(path.map(center), colors[color].opacity(0.65), 10) }
        }
        if engine.mode == .dots { line(engine.activePath.map(center), .white.opacity(0.7), 5) }
        if engine.mode == .laser { line(engine.beam.map(center), .yellow.opacity(0.7), 3) }
        if sliding {
            for (index, piece) in engine.pieces.enumerated() {
                let r = CGRect(x: margin + CGFloat(piece.col) * cell + 3, y: margin + CGFloat(piece.row) * cell + 3,
                               width: CGFloat(piece.horizontal ? piece.length : 1) * cell - 6,
                               height: CGFloat(piece.horizontal ? 1 : piece.length) * cell - 6)
                context.fill(Path(roundedRect: r, cornerRadius: 9), with: .color(piece.id == 0 ? .red : colors[piece.id % 5 + 1]))
                if engine.selected == index { context.stroke(Path(roundedRect: r, cornerRadius: 9), with: .color(.white), lineWidth: 3) }
                if engine.mode == .parkingJam {
                    let window = r.insetBy(dx: piece.horizontal ? r.width * 0.3 : 7,
                                          dy: piece.horizontal ? 7 : r.height * 0.3)
                    context.fill(Path(roundedRect: window, cornerRadius: 4), with: .color(.black.opacity(0.35)))
                }
                text(piece.horizontal ? "↔" : "↕", CGPoint(x: r.midX, y: r.midY), .black)
            }
            text("→", CGPoint(x: margin + cell * 6 + 5, y: center(12).y), Theme.neon, 14)
        }
    }
}
