import SwiftUI

struct PuzzleCollectionView: View {
    @State private var engine: PuzzleCollectionEngine
    @State private var lastCell: Int?
    init(mode: PuzzleMode) { _engine = State(initialValue: PuzzleCollectionEngine(mode: mode)) }
    static let colors: [Color] = [.clear, .cyan, .pink, .orange, .green, .purple, .yellow, .red]
    private var colors: [Color] { Self.colors }
    private var sliding: Bool { engine.mode == .unblock }

    var body: some View {
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.hasLevels ? L10n.format("Level %d", engine.level) : nil,
                          centersContent: true,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 12) {
                hud
                GeometryReader { geometry in
                    Canvas { context, size in draw(&context, size: size) }
                        .arenaBackground()
                        .environment(\.colorScheme, .dark)
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
                                    let cell = layout(geometry.size).1
                                    if max(abs(dx), abs(dy)) > 15 {
                                        let steps = Int((max(abs(dx), abs(dy)) / cell).rounded())
                                        withAnimation(.snappy(duration: 0.18)) {
                                            engine.slide(dr: abs(dy) > abs(dx) ? (dy > 0 ? 1 : -1) : 0,
                                                         dc: abs(dx) >= abs(dy) ? (dx > 0 ? 1 : -1) : 0, steps: steps)
                                        }
                                    }
                                } else if engine.mode == .dots {
                                    if hypot(value.translation.width, value.translation.height) > 12 { engine.collectDots() }
                                } else if ![.numberConnect, .oneLine].contains(engine.mode), let cell = index(value.location, size: geometry.size) { engine.tap(cell) }
                                lastCell = nil
                            })
                }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 420)
                controls
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .id(engine.level)
    }

    private var hud: some View {
        HStack(spacing: 10) {
            if engine.hasLevels {
                Menu {
                    ForEach(1...PuzzleCollectionEngine.levelCount, id: \.self) { level in
                        Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                    }
                } label: {
                    Label(L10n.format("Level %d", engine.level), systemImage: "square.grid.3x3")
                }
            }
            Text(L10n.format("%d moves", engine.moves))
            Spacer()
            if engine.mode == .dots || engine.mode == .floodFill {
                Text(L10n.format("%d moves left", engine.movesLeft))
                    .foregroundStyle(engine.movesLeft <= 3 ? .red : GameTheme.accent)
            } else if engine.par > 0 {
                // Live star rating against par.
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < engine.stars ? "star.fill" : "star")
                            .foregroundStyle(i < engine.stars ? Color.yellow : GameTheme.textSecondary)
                    }
                }
                .font(.caption)
                .accessibilityLabel(L10n.format("Par %d", engine.par))
            }
            if engine.mode == .colorLines {
                HStack(spacing: 3) {
                    ForEach(Array(engine.nextBalls.enumerated()), id: \.offset) { _, color in
                        Circle().fill(colors[color]).frame(width: 14, height: 14)
                    }
                }
                .accessibilityLabel(L10n.text("Next"))
            }
            if engine.canUndo {
                Button { engine.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .accessibilityLabel(L10n.text("Undo"))
            }
        }
        .font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.accent)
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
            Button(L10n.text(engine.loopClosed ? "Collect all!" : "Collect")) { engine.collectDots() }
                .buttonStyle(.borderedProminent).tint(engine.loopClosed ? .orange : GameTheme.accent)
                .disabled(engine.activePath.count < 2)
        }
        if engine.mode == .floodFill {
            HStack {
                ForEach(1...engine.colorCount, id: \.self) { color in
                    Button { withAnimation(.easeOut(duration: 0.2)) { engine.flood(color) } } label: {
                        Circle().fill(colors[color].gradient).frame(width: 42, height: 42)
                            .overlay { if engine.grid.first == color { Image(systemName: "checkmark").foregroundStyle(.black) } }
                            .shadow(color: colors[color].opacity(0.5), radius: 4)
                    }.accessibilityLabel("\(color)")
                }
            }
        }
    }
    private func arrow(_ symbol: String, dr: Int, dc: Int) -> some View {
        Button { withAnimation(.snappy(duration: 0.15)) { engine.slide(dr: dr, dc: dc) } } label: { Image(systemName: symbol).frame(width: 40, height: 40) }.buttonStyle(.bordered)
    }
    private func layout(_ size: CGSize) -> (CGFloat, CGFloat) {
        var margin: CGFloat = 14
        if engine.mode == .nonogram {
            let longest = (engine.rowClues + engine.columnClues).map(\.count).max() ?? 1
            margin = min(90, 18 + CGFloat(longest) * 12)
        }
        return (margin, (min(size.width, size.height) - margin - 14) / CGFloat(engine.n))
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
            context.draw(Text(verbatim: text).font(.system(size: font, weight: .bold, design: .rounded)).foregroundStyle(color), at: point)
        }
        func tile(_ r: CGRect, _ top: Color, _ bottom: Color, radius: CGFloat = 6) {
            context.fill(Path(roundedRect: r, cornerRadius: radius),
                         with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        func ball(_ r: CGRect, _ color: Color) {
            context.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [.white.opacity(0.9), color, color.opacity(0.75)]),
                                                                  center: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.3),
                                                                  startRadius: 0, endRadius: r.width * 0.75))
        }
        let clueFont = max(9, min(13, cell * 0.32))
        if engine.mode == .nonogram {
            for i in 0..<n {
                let rowColor: Color = engine.rowSolved(i) ? .green : .white
                let colColor: Color = engine.columnSolved(i) ? .green : .white
                text(engine.rowClues[i].map(String.init).joined(separator: " "), CGPoint(x: margin / 2, y: center(i * n).y), rowColor, clueFont)
                text(engine.columnClues[i].map(String.init).joined(separator: "\n"), CGPoint(x: center(i).x, y: margin / 2), colColor, clueFont)
            }
        }
        if engine.mode == .oneLine {
            for edge in engine.edges { line(edge.map(center), GameTheme.textSecondary.opacity(0.45), 6) }
            line(engine.activePath.map(center), GameTheme.accent.opacity(0.35), 14)
            line(engine.activePath.map(center), GameTheme.accent, 7)
            for i in engine.nodes {
                let r = rect(i).insetBy(dx: cell * 0.28, dy: cell * 0.28)
                ball(r, engine.activePath.last == i ? .orange : engine.activePath.contains(i) ? GameTheme.accent : .cyan)
            }
            return
        }
        for i in engine.grid.indices {
            let value = engine.grid[i], r = rect(i), p = center(i)
            switch engine.mode {
            case .lightsOut:
                if value == 1 {
                    context.fill(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: 9), with: .color(.yellow.opacity(0.25)))
                    tile(r, Color(red: 1, green: 0.95, blue: 0.6), .orange, radius: 8)
                } else {
                    tile(r, Color(white: 0.24), Color(white: 0.16), radius: 8)
                }
            case .nonogram:
                if value == 1 { tile(r, .cyan, Color(red: 0, green: 0.55, blue: 0.75), radius: 4) }
                else { context.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(GameTheme.surfaceHigh)) }
                if engine.marks.contains(i) { text("×", p, GameTheme.textSecondary) }
            case .floodFill:
                context.fill(Path(CGRect(x: margin + CGFloat(i % n) * cell, y: margin + CGFloat(i / n) * cell, width: cell + 0.5, height: cell + 0.5)), with: .color(colors[value]))
            case .fifteenPuzzle:
                if value > 0 {
                    let home = value - 1 == i
                    tile(r, home ? Color(red: 0.45, green: 0.8, blue: 0.55) : Color(red: 0.5, green: 0.45, blue: 0.95),
                         home ? Color(red: 0.2, green: 0.55, blue: 0.35) : Color(red: 0.3, green: 0.25, blue: 0.7), radius: 10)
                    text(String(value), p, .white, cell * 0.38)
                } else {
                    context.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(GameTheme.surface.opacity(0.4)))
                }
            case .numberConnect:
                context.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(GameTheme.surfaceHigh))
            case .dots, .colorLines:
                context.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(GameTheme.surfaceHigh.opacity(0.6)))
                if value > 0 {
                    ball(r.insetBy(dx: cell * 0.15, dy: cell * 0.15), colors[value])
                    if engine.selected == i { context.stroke(Path(ellipseIn: r.insetBy(dx: 2, dy: 2)), with: .color(.white), lineWidth: 2.5) }
                }
            case .pipeConnect:
                context.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(GameTheme.surfaceHigh))
                let lit = engine.beam.contains(i)
                for (bit, dx, dy) in [(1, 0, -1), (2, 1, 0), (4, 0, 1), (8, -1, 0)] where value & bit != 0 {
                    let end = CGPoint(x: p.x + CGFloat(dx) * cell / 2, y: p.y + CGFloat(dy) * cell / 2)
                    if lit { line([p, end], .cyan.opacity(0.35), cell * 0.36) }
                    line([p, end], lit ? .cyan : Color(white: 0.5), cell * 0.2)
                }
                context.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.1, y: p.y - cell * 0.1, width: cell * 0.2, height: cell * 0.2)), with: .color(lit ? .cyan : Color(white: 0.5)))
            case .laser:
                context.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(GameTheme.surfaceHigh.opacity(0.6)))
                if value > 0 {
                    let dx = cell * 0.32, dy = value == 1 ? -dx : dx
                    line([CGPoint(x: p.x - dx, y: p.y - dy), CGPoint(x: p.x + dx, y: p.y + dy)], Color(white: 0.85), 6)
                    line([CGPoint(x: p.x - dx, y: p.y - dy), CGPoint(x: p.x + dx, y: p.y + dy)], .cyan.opacity(0.5), 2)
                }
            default:
                context.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(GameTheme.surfaceHigh))
            }
        }
        switch engine.mode {
        case .numberConnect:
            for (color, path) in engine.paths { line(path.map(center), colors[color].opacity(0.7), cell * 0.36) }
            for i in engine.grid.indices where engine.grid[i] > 0 {
                let value = engine.grid[i]
                ball(rect(i).insetBy(dx: cell * 0.14, dy: cell * 0.14), colors[value])
                text(String(value), center(i), .black, cell * 0.34)
            }
        case .dots:
            if let first = engine.activePath.first {
                let color = colors[engine.grid[first]]
                line(engine.activePath.map(center), color.opacity(engine.loopClosed ? 0.9 : 0.6), cell * 0.18)
                if engine.loopClosed {
                    context.stroke(Path(roundedRect: CGRect(x: margin - 4, y: margin - 4, width: cell * CGFloat(n) + 8, height: cell * CGFloat(n) + 8), cornerRadius: 12),
                                   with: .color(color), lineWidth: 3)
                }
            }
        case .laser:
            let beam = engine.beam.map(center)
            line(beam, .red.opacity(0.3), 9)
            line(beam, Color(red: 1, green: 0.4, blue: 0.4), 3)
            let source = center(engine.laserSource)
            context.fill(Path(roundedRect: CGRect(x: margin - 12, y: source.y - 9, width: 14, height: 18), cornerRadius: 3), with: .color(.red))
            let target = center(engine.laserTarget)
            let reached = engine.beam.last == engine.laserTarget
            context.fill(Path(ellipseIn: CGRect(x: target.x - cell * 0.38, y: target.y - cell * 0.38, width: cell * 0.76, height: cell * 0.76)), with: .color(.yellow.opacity(reached ? 0.5 : 0.18)))
            text("★", target, .yellow, cell * 0.5)
        case .pipeConnect:
            let start = center(0)
            text("▶", CGPoint(x: margin / 2, y: start.y), .cyan, 12)
            let end = center(engine.pipeEnd)
            let exit = engine.pipeExit
            let offset = cell / 2 + margin / 2
            let point = CGPoint(x: end.x + (exit == 2 ? offset : exit == 8 ? -offset : 0), y: end.y + (exit == 4 ? offset : exit == 1 ? -offset : 0))
            text(exit == 2 ? "▶" : exit == 8 ? "◀" : exit == 4 ? "▼" : "▲", point, .green, 12)
        default: break
        }
        if sliding {
            context.fill(Path(roundedRect: CGRect(x: margin + cell * 6 - 2, y: margin + cell * 2 + 6, width: 8, height: cell - 12), cornerRadius: 3), with: .color(.green))
            for (index, piece) in engine.pieces.enumerated() {
                let r = CGRect(x: margin + CGFloat(piece.col) * cell + 3, y: margin + CGFloat(piece.row) * cell + 3,
                               width: CGFloat(piece.horizontal ? piece.length : 1) * cell - 6,
                               height: CGFloat(piece.horizontal ? 1 : piece.length) * cell - 6)
                let color = piece.id == 0 ? Color.red : colors[piece.id % 6 + 1]
                context.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 3), cornerRadius: 10), with: .color(.black.opacity(0.35)))
                tile(r, color, color.opacity(0.7), radius: 10)
                context.fill(Path(roundedRect: r.insetBy(dx: 6, dy: 6), cornerRadius: 6), with: .color(.white.opacity(0.15)))
                if engine.selected == index { context.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(.white), lineWidth: 3) }
                text(piece.horizontal ? "↔" : "↕", CGPoint(x: r.midX, y: r.midY), .black.opacity(0.6))
            }
        }
    }
}
