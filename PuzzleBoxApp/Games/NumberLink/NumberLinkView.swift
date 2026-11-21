import SwiftUI

struct NumberLinkView: View {
    @State private var engine = NumberLinkEngine()
    private let palette = ToyNumberLink.palette

    var body: some View {
        GameContainerView(gameID: .numberConnect, engine: engine,
                          resultSummary: summary,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette, headline: .clock(caption: L10n.format("%d moves", engine.moves))) {
                ToyIconButton(symbol: "arrow.uturn.backward", label: L10n.text("Undo"), color: palette.card, ink: palette.ink) {
                    withAnimation(.snappy(duration: 0.2)) { engine.undo() }
                }
                .disabled(!engine.canUndo)
                .opacity(engine.canUndo ? 1 : 0.45)
            } content: {
                VStack(spacing: 14) {
                    hud
                    NumberLinkBoard(engine: engine, interactive: true)
                        .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                    ToyCapsuleButton(title: L10n.text("Start over"), symbol: "arrow.counterclockwise",
                                     color: palette.card, ink: palette.ink) {
                        withAnimation(.snappy(duration: 0.25)) { engine.reset() }
                    }
                    .frame(maxWidth: 220)
                    .disabled(engine.joinedCount == 0 && !engine.canUndo)
                    Text(L10n.text(ToyNumberLink.hint))
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

    private var summary: String {
        L10n.format("Level %d", engine.level) + "  " + String(repeating: "★", count: engine.stars)
            + String(repeating: "☆", count: 3 - engine.stars)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(1...NumberLinkEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                // A raised chip with a chevron: it opens the level list.
                HStack(spacing: 5) {
                    Text(L10n.format("Level %d", engine.level))
                    Image(systemName: "chevron.down").font(.caption2.weight(.heavy)).opacity(0.6)
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .padding(.bottom, 3)
                .background { ToyBlock(color: palette.card, shape: Capsule(), lip: 3) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            // Pairs joined so far.
            ToyChip(color: palette.card) {
                Label {
                    Text(verbatim: "\(engine.joinedCount)/\(engine.pairCount)").monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: engine.joinedCount)
                } icon: {
                    Image(systemName: "link")
                }
                .foregroundStyle(palette.ink)
            }
            .accessibilityLabel(L10n.format("%d of %d pairs joined", engine.joinedCount, engine.pairCount))
            ToyChip(color: palette.card) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .foregroundStyle(i < engine.stars ? ToyNumberLink.starGold : palette.ink.opacity(0.18))
                    }
                }
            }
            .accessibilityLabel(L10n.format("%d stars", engine.stars))
        }
    }
}

// MARK: - Board

/// The clay tray with its sockets, the tubes and the shaped pieces.
struct NumberLinkBoard: View {
    let engine: NumberLinkEngine
    var interactive = false
    @State private var dragging = false
    /// Resets on its own when the system cancels the drag, so a stroke always ends.
    @GestureState private var touching = false
    @State private var waveStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let palette = ToyNumberLink.palette

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let cell = side / CGFloat(engine.n)
            Group {
                if let waveStart {
                    TimelineView(.animation) { timeline in
                        layers(cell: cell, wave: timeline.date.timeIntervalSince(waveStart))
                    }
                } else {
                    layers(cell: cell, wave: nil)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(interactive ? drag(cell: cell) : nil)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: touching) { _, now in
            guard !now, dragging else { return }
            dragging = false
            withAnimation(.snappy(duration: 0.2)) { engine.end() }
        }
        .onChange(of: engine.solvedWave) { _, _ in
            waveStart = .now
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                waveStart = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.format("%d of %d pairs joined", engine.joinedCount, engine.pairCount))
    }

    private func drag(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                let index = self.index(value.location, cell: cell)
                if !dragging {
                    dragging = true
                    if let start = self.index(value.startLocation, cell: cell) { engine.begin(at: start) }
                }
                if let index { engine.move(to: index) }
            }
            .onEnded { _ in
                guard dragging else { return }
                dragging = false
                withAnimation(.snappy(duration: 0.2)) { engine.end() }
            }
    }

    private func index(_ point: CGPoint, cell: CGFloat) -> Int? {
        let n = engine.n
        let c = Int(floor(point.x / cell)), r = Int(floor(point.y / cell))
        guard (0..<n).contains(r), (0..<n).contains(c) else { return nil }
        return r * n + c
    }

    private func center(_ i: Int, _ n: Int, _ cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(i % n) + 0.5) * cell, y: (CGFloat(i / n) + 0.5) * cell)
    }

    /// 0 → 1 → 0 as the wave front passes a cell, `wave` seconds after the win.
    private func waveLift(_ i: Int, _ wave: Double?) -> Double {
        guard let wave else { return 0 }
        let delay = Double(i / engine.n + i % engine.n) * 0.055
        let t = (wave - delay) / 0.42
        guard t > 0, t < 1 else { return 0 }
        return sin(t * .pi)
    }

    @ViewBuilder
    private func layers(cell: CGFloat, wave: Double?) -> some View {
        let n = engine.n
        ZStack(alignment: .topLeading) {
            // Sockets, tinted by the tube lying in them.
            let owners = engine.ownerMap
            Canvas { context, _ in
                for i in 0..<(n * n) {
                    let rect = CGRect(x: CGFloat(i % n) * cell, y: CGFloat(i / n) * cell, width: cell, height: cell)
                        .insetBy(dx: cell * 0.05, dy: cell * 0.05)
                    let shape = Path(roundedRect: rect, cornerRadius: cell * 0.2, style: .continuous)
                    context.fill(shape, with: .color(palette.socket))
                    context.fill(shape, with: .linearGradient(Gradient(colors: [.black.opacity(0.13), .clear]),
                                                              startPoint: rect.origin,
                                                              endPoint: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.35)))
                    if owners.indices.contains(i), owners[i] >= 0 {
                        let pair = owners[i]
                        context.fill(shape, with: .color(ToyNumberLink.color(pair).opacity(0.16)))
                    }
                    let lift = waveLift(i, wave)
                    if lift > 0 { context.fill(shape, with: .color(.white.opacity(0.35 * lift))) }
                }
            }
            // Clay tubes: a darker wall under a lit face with a soft shine.
            let tubes = engine.paths
            Canvas { context, _ in
                let width = cell * 0.36
                for (pair, path) in tubes.enumerated() where path.count > 1 {
                    var line = Path()
                    line.addLines(path.map { center($0, n, cell) })
                    let color = ToyNumberLink.color(pair)
                    let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                    context.stroke(line.applying(.init(translationX: 0, y: cell * 0.07)),
                                   with: .color(color.toyShade(-0.2)), style: style)
                    context.stroke(line, with: .color(color), style: style)
                    context.stroke(line.applying(.init(translationX: 0, y: -width * 0.2)),
                                   with: .color(.white.opacity(0.32)),
                                   style: StrokeStyle(lineWidth: width * 0.22, lineCap: .round, lineJoin: .round))
                }
            }
            // The pieces.
            // Iterates a snapshot, so a level change can never ask for a pair
            // the new level doesn't have.
            ForEach(engine.pieceCells, id: \.cell) { item in
                piece(pair: item.pair, cell: cell, lift: waveLift(item.cell, wave))
                    .position(center(item.cell, n, cell))
            }
        }
    }

    private func piece(pair: Int, cell: CGFloat, lift: Double) -> some View {
        let joined = engine.isJoined(pair)
        let active = engine.drawing == pair
        let size = cell * 0.7
        return PairPiece(color: ToyNumberLink.color(pair), shape: PairShape(kind: pair), lip: max(2, cell * 0.07))
            .frame(width: size, height: size)
            .scaleEffect(1 + (reduceMotion ? 0 : 0.16 * lift) + (active ? 0.08 : 0))
            .offset(y: reduceMotion ? 0 : -cell * 0.08 * lift)
            .overlay(alignment: .center) {
                // A pressed-in dimple shows the pair is joined.
                Circle()
                    .fill(.white.opacity(joined ? 0.55 : 0))
                    .frame(width: size * 0.2, height: size * 0.2)
                    .offset(y: -size * 0.04)
            }
            .animation(.snappy(duration: 0.18), value: active)
            .animation(.spring(duration: 0.3, bounce: 0.5), value: joined)
    }
}

// MARK: - Look

/// A calm oat-and-clay world, so the coloured pieces carry the board.
enum ToyNumberLink {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.97, 0.95, 0.91), dark: (0.15, 0.15, 0.17)),
        backdropBottom: .dynamic(light: (0.90, 0.87, 0.81), dark: (0.08, 0.08, 0.10)),
        tray: .dynamic(light: (0.80, 0.75, 0.68), dark: (0.29, 0.28, 0.31)),
        socket: .dynamic(light: (0.87, 0.84, 0.79), dark: (0.16, 0.15, 0.17)),
        ink: .dynamic(light: (0.34, 0.30, 0.26), dark: (0.97, 0.96, 0.94)),
        deboss: .dynamic(light: (0.92, 0.89, 0.84), dark: (0.21, 0.21, 0.23)),
        debossRim: .dynamic(light: (1, 1, 1), dark: (0.02, 0.02, 0.04)),
        card: .dynamic(light: (1.0, 1.0, 0.99), dark: (0.37, 0.37, 0.39)),
        accent: .dynamic(light: (0.42, 0.64, 0.88), dark: (0.52, 0.72, 0.94)))

    static let starGold = Color(red: 0.98, green: 0.76, blue: 0.22)

    static let hint = "Join each pair of matching pieces. Tubes can't cross."

    /// Soft clay colours, one per pair; each pair also has its own shape.
    private static let colors: [Color] = [
        .dynamic(light: (0.93, 0.52, 0.47), dark: (0.90, 0.50, 0.46)),   // coral, circle
        .dynamic(light: (0.42, 0.65, 0.90), dark: (0.46, 0.66, 0.92)),   // sky, square
        .dynamic(light: (0.96, 0.76, 0.33), dark: (0.93, 0.74, 0.34)),   // sun, triangle
        .dynamic(light: (0.47, 0.74, 0.52), dark: (0.46, 0.72, 0.52)),   // sage, diamond
        .dynamic(light: (0.65, 0.55, 0.88), dark: (0.66, 0.57, 0.90)),   // lavender, star
        .dynamic(light: (0.32, 0.71, 0.72), dark: (0.34, 0.70, 0.71)),   // teal, hexagon
        .dynamic(light: (0.96, 0.62, 0.36), dark: (0.93, 0.61, 0.37)),   // apricot, plus
        .dynamic(light: (0.92, 0.57, 0.74), dark: (0.90, 0.56, 0.73)),   // rose, heart
        .dynamic(light: (0.66, 0.53, 0.42), dark: (0.68, 0.56, 0.45)),   // cocoa, drop
    ]

    static func color(_ pair: Int) -> Color { colors[pair % colors.count] }
}

/// A clay piece in any silhouette: the face over its own darker side wall.
/// (`ToyBlock` joins face and lip with a full-width band, which shows beside
/// pointed shapes such as stars and triangles.)
struct PairPiece: View {
    let color: Color
    let shape: PairShape
    var lip: CGFloat = 4

    var body: some View {
        let wall = color.toyShade(-0.2)
        ZStack(alignment: .top) {
            Extrusion(shape: shape, depth: lip).fill(wall)
            shape.fill(LinearGradient(colors: [color.toyShade(0.06), color], startPoint: .top, endPoint: .bottom)
                .shadow(.inner(color: .white.opacity(0.5), radius: 0.5, y: 1.5))
                .shadow(.inner(color: wall.opacity(0.35), radius: 1, y: -1)))
        }
        .padding(.bottom, lip)
        .compositingGroup()
        .shadow(color: color.toyShade(-0.45).opacity(0.3), radius: 2, y: 2)
    }
}

/// `shape` swept straight down by `depth`: the piece's side wall.
private struct Extrusion: Shape {
    let shape: PairShape
    let depth: CGFloat

    /// Stacked copies of the same outline wind the same way, so the
    /// non-zero fill paints their union without any costly boolean ops.
    func path(in rect: CGRect) -> Path {
        let base = shape.path(in: rect)
        var path = base
        var step: CGFloat = 0.75
        while step < depth {
            path.addPath(base, transform: .init(translationX: 0, y: step))
            step += 0.75
        }
        path.addPath(base, transform: .init(translationX: 0, y: depth))
        return path
    }
}

/// One silhouette per pair, so pairs read without colour alone.
struct PairShape: InsettableShape {
    let kind: Int
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> PairShape { var copy = self; copy.inset += amount; return copy }

    func path(in frame: CGRect) -> Path {
        let rect = frame.insetBy(dx: inset, dy: inset)
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: x + u * w, y: y + v * h) }
        let soft = min(w, h) * 0.12
        switch kind % 9 {
        case 0:
            return Path(ellipseIn: rect)
        case 1:
            return Path(roundedRect: rect.insetBy(dx: w * 0.06, dy: h * 0.06), cornerRadius: w * 0.22, style: .continuous)
        case 2:
            return rounded([p(0.5, 0.04), p(1, 0.92), p(0, 0.92)], soft)
        case 3:
            return rounded([p(0.5, 0), p(1, 0.5), p(0.5, 1), p(0, 0.5)], soft)
        case 4:
            let points = (0..<10).map { k -> CGPoint in
                let angle = -CGFloat.pi / 2 + CGFloat(k) * .pi / 5
                let r: CGFloat = k.isMultiple(of: 2) ? 0.52 : 0.25
                return p(0.5 + r * cos(angle), 0.54 + r * sin(angle))
            }
            return rounded(points, soft * 0.5)
        case 5:
            let points = (0..<6).map { k -> CGPoint in
                let angle = CGFloat(k) * .pi / 3
                return p(0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
            }
            return rounded(points, soft)
        case 6:
            let a: CGFloat = 0.32, b: CGFloat = 0.68
            return rounded([p(a, 0), p(b, 0), p(b, a), p(1, a), p(1, b), p(b, b), p(b, 1), p(a, 1), p(a, b), p(0, b), p(0, a), p(a, a)], soft * 0.7)
        case 7:
            var path = Path()
            path.move(to: p(0.5, 0.96))
            path.addCurve(to: p(0, 0.34), control1: p(0.2, 0.76), control2: p(0, 0.58))
            path.addCurve(to: p(0.5, 0.2), control1: p(0, 0.02), control2: p(0.42, 0.0))
            path.addCurve(to: p(1, 0.34), control1: p(0.58, 0.0), control2: p(1, 0.02))
            path.addCurve(to: p(0.5, 0.96), control1: p(1, 0.58), control2: p(0.8, 0.76))
            path.closeSubpath()
            return path
        default:
            var path = Path()
            path.move(to: p(0.5, 0))
            path.addCurve(to: p(0.86, 0.62), control1: p(0.62, 0.18), control2: p(0.86, 0.38))
            path.addArc(center: p(0.5, 0.64), radius: 0.36 * w, startAngle: .degrees(-3), endAngle: .degrees(183), clockwise: false)
            path.addCurve(to: p(0.5, 0), control1: p(0.14, 0.38), control2: p(0.38, 0.18))
            path.closeSubpath()
            return path
        }
    }

    /// A polygon with its corners rounded off, like a moulded piece.
    private func rounded(_ points: [CGPoint], _ radius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let last = points[points.count - 1], first = points[0]
        path.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for k in points.indices {
            path.addArc(tangent1End: points[k], tangent2End: points[(k + 1) % points.count], radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

/// The board as it looks in play, nearly solved, for the Home preview.
struct NumberLinkShowcase: View {
    let engine: NumberLinkEngine

    var body: some View {
        ZStack {
            ToyNumberLink.palette.backdrop
            NumberLinkBoard(engine: engine)
                .toyTray(ToyNumberLink.palette.tray, cornerRadius: 24, padding: 6)
                .padding(24)
        }
        .environment(\.toyStyle, ToyNumberLink.palette.style)
        .frame(width: 360, height: 360)
    }
}
