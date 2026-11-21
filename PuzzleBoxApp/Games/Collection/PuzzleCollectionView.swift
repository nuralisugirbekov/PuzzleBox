import SwiftUI

struct PuzzleCollectionView: View {
    @State private var engine: PuzzleCollectionEngine
    @State private var lastCell: Int?
    init(mode: PuzzleMode) { _engine = State(initialValue: PuzzleCollectionEngine(mode: mode)) }
    /// Candy clay colours shared by the colour puzzles.
    static let colors: [Color] = [.clear,
                                  Color(red: 0.42, green: 0.76, blue: 0.93), Color(red: 0.96, green: 0.55, blue: 0.72),
                                  Color(red: 0.98, green: 0.67, blue: 0.34), Color(red: 0.49, green: 0.81, blue: 0.52),
                                  Color(red: 0.66, green: 0.56, blue: 0.93), Color(red: 0.98, green: 0.84, blue: 0.36),
                                  Color(red: 0.94, green: 0.42, blue: 0.40)]
    private var palette: ToyPalette { ToyPuzzles.palette(for: engine.mode) }
    private var colors: [Color] { Self.colors }

    private var isShowcase = false

    /// Just the board for the Home preview.
    init(showcase engine: PuzzleCollectionEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }

    var body: some View {
        if isShowcase {
            ToyShowcaseFrame(palette: palette, aspect: 1) {
                Canvas { context, size in draw(&context, size: size) }
            }
        } else {
            gameBody
        }
    }

    @ViewBuilder
    private var gameBody: some View {
        let palette = palette
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.hasLevels ? L10n.format("Level %d", engine.level) : nil,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
          ToyGameStage(palette: palette, headline: .clock(caption: L10n.format("%d moves", engine.moves))) {
            ToyIconButton(symbol: "arrow.uturn.backward", label: L10n.text("Undo"), color: palette.card, ink: palette.ink) {
                engine.undo()
            }
            .disabled(!engine.canUndo)
            .opacity(engine.canUndo ? 1 : 0.45)
          } content: {
            VStack(spacing: 14) {
                hud
                GeometryReader { geometry in
                    Canvas { context, size in draw(&context, size: size) }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let cell = index(value.location, size: geometry.size) else { return }
                                if [.dots, .oneLine].contains(engine.mode), lastCell != cell {
                                    engine.tap(cell); lastCell = cell
                                }
                            }
                            .onEnded { value in
                                if engine.mode == .dots {
                                    if hypot(value.translation.width, value.translation.height) > 12 { engine.collectDots() }
                                } else if engine.mode != .oneLine, let cell = index(value.location, size: geometry.size) { engine.tap(cell) }
                                lastCell = nil
                            })
                }
                .aspectRatio(1, contentMode: .fit)
                .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                controls
                Text(L10n.text(engine.mode.hint))
                    .font(.system(.footnote, design: .rounded))
                    .opacity(0.6)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
          }
        }
        .id(engine.level)
    }

    private var hud: some View {
        let palette = palette
        return HStack(spacing: 8) {
            if engine.hasLevels {
                Menu {
                    ForEach(1...PuzzleCollectionEngine.levelCount, id: \.self) { level in
                        Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                    }
                } label: {
                    ToyMenuChip(color: palette.card, ink: palette.ink) {
                        Text(L10n.format("Level %d", engine.level))
                    }
                }
            }
            Spacer(minLength: 0)
            if engine.mode == .dots || engine.mode == .floodFill {
                ToyChip(color: engine.movesLeft <= 3 ? palette.accent : palette.card) {
                    Text(L10n.format("%d moves left", engine.movesLeft))
                        .foregroundStyle(engine.movesLeft <= 3 ? Color.white : palette.ink)
                        .monospacedDigit()
                }
            } else if engine.par > 0 {
                // Live star rating against par.
                ToyChip(color: palette.card) {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: "star.fill")
                                .foregroundStyle(i < engine.stars ? Self.starGold : palette.ink.opacity(0.18))
                        }
                    }
                }
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
        }
    }

    static let starGold = Color(red: 0.98, green: 0.76, blue: 0.22)

    @ViewBuilder private var controls: some View {
        if engine.mode == .nonogram {
            Picker("", selection: $engine.markMode) {
                Text(L10n.text("Fill")).tag(false)
                Text(L10n.text("Mark empty")).tag(true)
            }.pickerStyle(.segmented)
        }
        if engine.mode == .dots {
            ToyCapsuleButton(title: L10n.text(engine.loopClosed ? "Collect all!" : "Collect"), symbol: "sparkles",
                             color: palette.accent, ink: .white) { engine.collectDots() }
                .frame(maxWidth: 220)
                .disabled(engine.activePath.count < 2)
        }
        if engine.mode == .floodFill {
            HStack(spacing: 12) {
                ForEach(1...engine.colorCount, id: \.self) { color in
                    let current = engine.grid.first == color
                    Button { withAnimation(.easeOut(duration: 0.2)) { engine.flood(color) } } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .opacity(current ? 1 : 0)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(ToyPressStyle(color: colors[color], lip: 4, cornerRadius: 22))
                    .offset(y: current ? 3 : 0)
                    .accessibilityLabel("\(color)")
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
        }
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
        let pal = palette
        let lipH = max(2, cell * 0.07)
        /// A raised clay piece: darker lip, gradient face, sheen along the top.
        func clay(_ r: CGRect, _ color: Color, radius: CGFloat) {
            let face = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - lipH)
            context.fill(Path(roundedRect: face.offsetBy(dx: 0, dy: lipH + 1), cornerRadius: radius), with: .color(.black.opacity(0.12)))
            context.fill(Path(roundedRect: face.offsetBy(dx: 0, dy: lipH), cornerRadius: radius), with: .color(color.toyShade(-0.22)))
            context.fill(Path(roundedRect: face, cornerRadius: radius),
                         with: .linearGradient(Gradient(colors: [color.toyShade(0.08), color, color.toyShade(-0.04)]),
                                               startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)))
            context.stroke(Path(roundedRect: face.insetBy(dx: 1, dy: 1), cornerRadius: max(1, radius - 1)),
                           with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                                                 startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.midY)),
                           lineWidth: 1.5)
        }
        /// A shallow well pressed into the tray.
        func socket(_ r: CGRect, radius: CGFloat) {
            let path = Path(roundedRect: r, cornerRadius: radius)
            context.fill(path, with: .color(pal.socket))
            context.fill(path, with: .linearGradient(Gradient(colors: [.black.opacity(0.14), .clear]),
                                                     startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.minY + r.height * 0.35)))
        }
        /// Centre of a raised piece's face, for its label.
        func faceCenter(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY - lipH / 2) }
        func tile(_ r: CGRect, _ top: Color, _ bottom: Color, radius: CGFloat = 6) {
            context.fill(Path(roundedRect: r, cornerRadius: radius),
                         with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))
        }
        func ball(_ r: CGRect, _ color: Color) {
            // A clay bead: darker underside, then the face with a soft highlight.
            context.fill(Path(ellipseIn: r.offsetBy(dx: 0, dy: r.height * 0.08)), with: .color(color.toyShade(-0.25)))
            context.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [color.toyShade(0.18), color, color.toyShade(-0.05)]),
                                                                  center: CGPoint(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.32),
                                                                  startRadius: 0, endRadius: r.width * 0.7))
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
                let radius = cell * 0.22
                socket(r, radius: radius)
                if value == 1 {
                    // A lit lamp: warm glow around a raised yellow key.
                    context.fill(Path(roundedRect: r.insetBy(dx: -3, dy: -3), cornerRadius: radius + 3),
                                 with: .radialGradient(Gradient(colors: [pal.accent.opacity(0.55), pal.accent.opacity(0)]),
                                                       center: p, startRadius: cell * 0.2, endRadius: cell * 0.7))
                    clay(r.insetBy(dx: 2, dy: 2), pal.accent, radius: radius - 1)
                    let bulb = faceCenter(r)
                    context.fill(Path(ellipseIn: CGRect(x: bulb.x - cell * 0.12, y: bulb.y - cell * 0.12, width: cell * 0.24, height: cell * 0.24)),
                                 with: .color(.white.opacity(0.85)))
                } else {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - cell * 0.08, y: p.y - cell * 0.08, width: cell * 0.16, height: cell * 0.16)),
                                 with: .color(pal.ink.opacity(0.15)))
                }
            case .nonogram:
                if value == 1 { tile(r, .cyan, Color(red: 0, green: 0.55, blue: 0.75), radius: 4) }
                else { context.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(GameTheme.surfaceHigh)) }
                if engine.marks.contains(i) { text("×", p, GameTheme.textSecondary) }
            case .floodFill:
                let full = CGRect(x: margin + CGFloat(i % n) * cell, y: margin + CGFloat(i / n) * cell, width: cell + 0.5, height: cell + 0.5)
                context.fill(Path(full), with: .color(colors[value]))
                // A soft lighter top edge, like wet paint catching the light.
                context.fill(Path(CGRect(x: full.minX, y: full.minY, width: full.width, height: full.height * 0.35)),
                             with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear]),
                                                   startPoint: CGPoint(x: full.midX, y: full.minY), endPoint: CGPoint(x: full.midX, y: full.minY + full.height * 0.35)))
            case .fifteenPuzzle:
                if value > 0 {
                    // Tiles in their place turn the accent colour.
                    let home = value - 1 == i
                    clay(r, home ? pal.accent : pal.card, radius: cell * 0.2)
                    text(String(value), faceCenter(r), home ? .white : pal.ink, cell * 0.4)
                } else {
                    socket(r, radius: cell * 0.2)
                }
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
                socket(r, radius: cell * 0.18)
                if value > 0 {
                    // A clay mirror: dark edge under a silver face.
                    let dx = cell * 0.3, dy = value == 1 ? -dx : dx
                    let a = CGPoint(x: p.x - dx, y: p.y - dy), b = CGPoint(x: p.x + dx, y: p.y + dy)
                    line([a.applying(.init(translationX: 0, y: 2)), b.applying(.init(translationX: 0, y: 2))], pal.ink.opacity(0.45), cell * 0.16)
                    line([a, b], pal.card, cell * 0.16)
                    line([a, b], pal.accent.opacity(0.6), cell * 0.05)
                }
            default:
                socket(r, radius: cell * 0.18)
            }
        }
        switch engine.mode {
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
            let beamColor = Color(red: 0.96, green: 0.36, blue: 0.40)
            line(beam, beamColor.opacity(0.3), 10)
            line(beam, beamColor, 3.5)
            let source = center(engine.laserSource)
            clay(CGRect(x: margin - 13, y: source.y - 11, width: 16, height: 22), beamColor, radius: 4)
            let target = center(engine.laserTarget)
            let reached = engine.beam.last == engine.laserTarget
            context.fill(Path(ellipseIn: CGRect(x: target.x - cell * 0.4, y: target.y - cell * 0.4, width: cell * 0.8, height: cell * 0.8)),
                         with: .color(Self.starGold.opacity(reached ? 0.55 : 0.2)))
            text("★", target, Self.starGold, cell * 0.52)
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
    }
}

/// The toy worlds of the grid puzzles that share this screen.
enum ToyPuzzles {
    static func palette(for mode: PuzzleMode) -> ToyPalette {
        switch mode {
        case .lightsOut: lightsOut
        case .fifteenPuzzle: fifteen
        case .floodFill: flood
        default: laser
        }
    }

    static func world(top: (Double, Double, Double), bottom: (Double, Double, Double),
                              darkTop: (Double, Double, Double), darkBottom: (Double, Double, Double),
                              tray: (Double, Double, Double), darkTray: (Double, Double, Double),
                              ink: (Double, Double, Double),
                              accent: (Double, Double, Double), darkAccent: (Double, Double, Double)) -> ToyPalette {
        func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        return ToyPalette(
            backdropTop: .dynamic(light: top, dark: darkTop),
            backdropBottom: .dynamic(light: bottom, dark: darkBottom),
            tray: .dynamic(light: tray, dark: darkTray),
            socket: .dynamic(light: mix(tray, (1, 1, 1), 0.35), dark: mix(darkTray, (0, 0, 0), 0.45)),
            ink: .dynamic(light: ink, dark: mix(top, (1, 1, 1), 0.85)),
            deboss: .dynamic(light: mix(top, bottom, 0.6), dark: mix(darkTop, (1, 1, 1), 0.06)),
            debossRim: .dynamic(light: (1, 1, 1), dark: (0.02, 0.02, 0.04)),
            card: .dynamic(light: (1.0, 1.0, 0.99), dark: mix(darkTray, (1, 1, 1), 0.12)),
            accent: .dynamic(light: accent, dark: darkAccent))
    }

    /// Twilight lilac with warm lamp keys.
    static let lightsOut = world(top: (0.88, 0.89, 0.99), bottom: (0.74, 0.76, 0.94),
                                 darkTop: (0.11, 0.11, 0.24), darkBottom: (0.05, 0.05, 0.13),
                                 tray: (0.58, 0.60, 0.86), darkTray: (0.22, 0.22, 0.42),
                                 ink: (0.22, 0.22, 0.46), accent: (0.99, 0.80, 0.32), darkAccent: (1.0, 0.82, 0.36))
    /// Terracotta clay with cream tiles; placed tiles turn teal.
    static let fifteen = world(top: (0.99, 0.91, 0.86), bottom: (0.95, 0.79, 0.71),
                               darkTop: (0.22, 0.13, 0.10), darkBottom: (0.12, 0.07, 0.05),
                               tray: (0.85, 0.58, 0.46), darkTray: (0.42, 0.24, 0.18),
                               ink: (0.45, 0.22, 0.15), accent: (0.27, 0.66, 0.62), darkAccent: (0.33, 0.72, 0.68))
    /// Fresh lime paint pots.
    static let flood = world(top: (0.94, 0.98, 0.89), bottom: (0.82, 0.93, 0.76),
                             darkTop: (0.12, 0.18, 0.10), darkBottom: (0.06, 0.10, 0.05),
                             tray: (0.60, 0.76, 0.52), darkTray: (0.24, 0.34, 0.20),
                             ink: (0.20, 0.36, 0.16), accent: (0.94, 0.45, 0.42), darkAccent: (1.0, 0.56, 0.52))
    /// Cool teal glass.
    static let laser = world(top: (0.87, 0.96, 0.97), bottom: (0.72, 0.88, 0.92),
                             darkTop: (0.07, 0.17, 0.20), darkBottom: (0.03, 0.09, 0.11),
                             tray: (0.45, 0.70, 0.76), darkTray: (0.16, 0.32, 0.36),
                             ink: (0.10, 0.32, 0.38), accent: (0.62, 0.70, 0.95), darkAccent: (0.70, 0.78, 1.0))
}
