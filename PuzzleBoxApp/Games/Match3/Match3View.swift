import SwiftUI

// MARK: - Screen

struct Match3View: View {
    @State private var engine: Match3Engine

    init(mode: Match3Mode) {
        _engine = State(initialValue: Match3Engine(mode: mode))
    }

    var body: some View {
        let palette = ToyGems.palette
        GameContainerView(gameID: engine.mode.gameID, engine: engine,
                          resultSummary: engine.mode == .casual ? nil : L10n.format("Level %d", engine.levelNumber),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette) {
                VStack(spacing: 0) {
                    Group {
                        if engine.mode == .casual {
                            HStack(spacing: 10) {
                                ToyChip(color: palette.card) {
                                    Label {
                                        Text(L10n.format("Combo ×%d", max(engine.bestCascade, 1)))
                                            .contentTransition(.numericText())
                                    } icon: {
                                        Image(systemName: "flame.fill").foregroundStyle(ToyGems.flame)
                                    }
                                }
                                .animation(.snappy, value: engine.bestCascade)
                                Spacer(minLength: 0)
                                ToyCapsuleButton(title: L10n.text("Hint"), symbol: "lightbulb.fill",
                                                 color: palette.card, ink: palette.ink) { engine.showHint() }
                                    .fixedSize()
                                    .disabled(engine.isBusy || engine.isEnding)
                            }
                        } else {
                            Match3GoalBar(engine: engine, toy: true)
                        }
                    }
                    .padding(.top, 14)
                    Spacer(minLength: 12)
                    Match3BoardView(engine: engine)
                        .toyTray(palette.tray, cornerRadius: 22, padding: 8)
                    Spacer(minLength: 12)
                    // Only until the first match.
                    Text(L10n.text("Swipe a gem to swap it with a neighbour."))
                        .font(.system(.footnote, design: .rounded))
                        .opacity(engine.score == 0 ? 0.6 : 0)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(!(engine.score == 0))
                    Spacer(minLength: 4).frame(maxHeight: 16)
                }
                .animation(.easeOut(duration: 0.3), value: engine.score == 0)
            }
        }
        .task { await engine.runClock() }
    }
}

/// Level, crystals collected, and the clock (Blitz) or the moves left (Arcade).
struct Match3GoalBar: View {
    let engine: Match3Engine
    /// Toy chips and a clay time bar, for the toy-styled Gems screen.
    var toy = false

    private var fraction: Double { engine.timeLeft / Match3Level.time }

    var body: some View {
        if toy { toyBody } else { plainBody }
    }

    private var toyBody: some View {
        let palette = ToyGems.palette
        return VStack(spacing: 12) {
            HStack(spacing: 8) {
                ToyChip(color: palette.card) {
                    Text(L10n.format("Level %d", engine.levelNumber))
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if engine.mode == .arcade {
                    ToyChip(color: engine.movesLeft <= 3 ? ToyGems.warning : palette.card) {
                        Label {
                            Text(verbatim: "\(engine.movesLeft)").monospacedDigit()
                                .contentTransition(.numericText())
                        } icon: {
                            Image(systemName: "hand.draw.fill").foregroundStyle(engine.movesLeft <= 3 ? palette.ink : ToyGems.flame)
                        }
                    }
                    .animation(.snappy, value: engine.movesLeft)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.format("Moves left: %d", engine.movesLeft))
                }
                ToyChip(color: palette.card) {
                    Label {
                        Text(verbatim: "\(min(engine.crystals, engine.crystalsNeeded)) / \(engine.crystalsNeeded)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: "diamond.fill").foregroundStyle(ToyGems.crystal)
                    }
                }
                .animation(.snappy, value: engine.crystals)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Crystals: %d of %d", engine.crystals, engine.crystalsNeeded))
            }
            if engine.mode == .blitz {
                HStack(spacing: 10) {
                    // Time left as clay filling a groove.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            ToySocket(color: palette.socket, shape: Capsule())
                            Capsule()
                                .fill(fraction > 0.25 ? ToyGems.timeOK : ToyGems.warning)
                                .overlay(alignment: .top) {
                                    Capsule().fill(.white.opacity(0.35)).frame(height: 3).padding(.horizontal, 4).padding(.top, 2)
                                }
                                .frame(width: max(12, geo.size.width * fraction))
                                .padding(2)
                                .animation(.linear(duration: 0.1), value: engine.timeLeft)
                        }
                    }
                    .frame(height: 16)
                    Text(verbatim: "\(Int(engine.timeLeft.rounded(.up)))")
                        .font(.system(.headline, design: .rounded).monospacedDigit().weight(.heavy))
                        .foregroundStyle(fraction > 0.25 ? palette.ink : ToyGems.warning)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var plainBody: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Text(L10n.format("Level %d", engine.levelNumber))
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                if engine.mode == .arcade {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill").foregroundStyle(.orange)
                        Text(verbatim: "\(engine.movesLeft)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.headline)
                    .foregroundStyle(engine.movesLeft <= 3 ? Color.red : Color.primary)
                    .animation(.snappy, value: engine.movesLeft)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.format("Moves left: %d", engine.movesLeft))
                }
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill").foregroundStyle(.cyan)
                    Text(verbatim: "\(min(engine.crystals, engine.crystalsNeeded)) / \(engine.crystalsNeeded)")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.headline)
                .animation(.snappy, value: engine.crystals)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Crystals: %d of %d", engine.crystals, engine.crystalsNeeded))
            }
            if engine.mode == .blitz {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(GameTheme.surfaceHigh)
                            Capsule()
                                .fill(fraction > 0.25 ? AnyShapeStyle(Color.green.gradient) : AnyShapeStyle(Color.red.gradient))
                                .frame(width: geo.size.width * fraction)
                                .animation(.linear(duration: 0.1), value: engine.timeLeft)
                        }
                    }
                    .frame(height: 10)
                    Text(verbatim: "\(Int(engine.timeLeft.rounded(.up)))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(fraction > 0.25 ? Color.primary : Color.red)
                        .frame(minWidth: 28, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The board in whatever shape the level draws, with its effects and popups.
struct Match3BoardView: View {
    let engine: Match3Engine
    @State private var dragHandled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: CGFloat { CGFloat(engine.board.rows) }
    private var cols: CGFloat { CGFloat(engine.board.cols) }

    var body: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / cols, geo.size.height / rows)
            let size = CGSize(width: cell * cols, height: cell * rows)
            ZStack(alignment: .topLeading) {
                // Each playable cell gets a tile, so the board's shape reads at a glance.
                ForEach(engine.board.positions, id: \.self) { p in
                    RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                        .fill((p.r + p.c).isMultiple(of: 2) ? Self.tileLight : Self.tileDark)
                        .frame(width: cell + 1, height: cell + 1)
                        .offset(x: CGFloat(p.c) * cell - 0.5, y: CGFloat(p.r) * cell - 0.5)
                }
                ForEach(engine.pieces) { piece in
                    Match3GemView(gem: piece.gem, size: cell,
                                  selected: engine.selected == piece.at,
                                  hinted: engine.hint.contains(piece.at),
                                  faceted: true)
                        .offset(x: CGFloat(piece.at.c) * cell, y: CGFloat(piece.at.r) * cell)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .offset(y: -cell * 2.5).combined(with: .opacity),
                            removal: .scale(scale: 0.2).combined(with: .opacity)))
                }
                ForEach(engine.effects) { effect in
                    Match3EffectView(effect: effect, cell: cell, side: max(size.width, size.height))
                        .position(x: (CGFloat(effect.at.c) + 0.5) * cell, y: (CGFloat(effect.at.r) + 0.5) * cell)
                }
                ClassicFXPopupLayer(feed: engine.popups)
            }
            .frame(width: size.width, height: size.height)
            // Gems dropping in slide out from the top edge rather than over the header.
            .clipped()
            .contentShape(Rectangle())
            .gesture(drag(cell: cell))
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(cols / rows, contentMode: .fit)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: engine.board.rows)
        .animation(.spring(duration: 0.5, bounce: 0.2), value: engine.board.cols)
        .keyframeAnimator(initialValue: CGFloat(0), trigger: engine.shake) { content, x in
            content.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(reduceMotion ? 0 : 7, duration: 0.05)
                CubicKeyframe(reduceMotion ? 0 : -6, duration: 0.06)
                CubicKeyframe(reduceMotion ? 0 : 3, duration: 0.06)
                CubicKeyframe(0, duration: 0.08)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(engine.mode.gameID.info.title)
    }

    private static let tileLight = Color(red: 0.22, green: 0.17, blue: 0.42)
    private static let tileDark = Color(red: 0.17, green: 0.13, blue: 0.34)

    private func cellAt(_ point: CGPoint, cell: CGFloat) -> GridPos {
        GridPos(r: Int((point.y / cell).rounded(.down)), c: Int((point.x / cell).rounded(.down)))
    }

    /// Swiping a gem swaps it as soon as the finger has moved a third of a
    /// cell; a plain tap selects, and a second tap on a neighbour swaps.
    private func drag(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !dragHandled else { return }
                let start = cellAt(value.startLocation, cell: cell)
                let dx = value.translation.width, dy = value.translation.height
                guard engine.board.contains(start), max(abs(dx), abs(dy)) > cell * 0.33 else { return }
                dragHandled = true
                let target = abs(dx) > abs(dy)
                    ? GridPos(r: start.r, c: start.c + (dx > 0 ? 1 : -1))
                    : GridPos(r: start.r + (dy > 0 ? 1 : -1), c: start.c)
                engine.swap(start, target)
            }
            .onEnded { value in
                defer { dragHandled = false }
                guard !dragHandled else { return }
                let p = cellAt(value.location, cell: cell)
                if engine.board.contains(p) { engine.tap(p) }
            }
    }
}

// MARK: - Gems

struct Match3GemView: View {
    let gem: Gem
    let size: CGFloat
    var selected = false
    var hinted = false
    /// Cut gems with facets on the board; the catalog art keeps the plain symbols.
    var faceted = false

    var body: some View {
        ZStack {
            if selected {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .padding(size * 0.03)
            }
            if gem.power == .lightning {
                Match3LightningOrb(size: size)
            } else if let color = gem.color, faceted {
                Match3CutGem(outline: Match3CutGem.outline(color), rgb: Self.rgb(color),
                             table: Match3CutGem.tableScale(color), crystal: gem.crystal)
                    .shadow(color: Self.tint(color).opacity(gem.power == .none ? 0 : 0.9),
                            radius: gem.power == .none ? 0 : 7)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: size * 0.04)
                    .padding(size * 0.1)
                if gem.power == .bomb { bomb }
                if gem.power == .cross { cross }
            } else if let color = gem.color {
                Image(systemName: Self.symbol(color))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(LinearGradient(colors: [Self.light(color), Self.tint(color)],
                                                    startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .topLeading) {
                        Circle().fill(Color.white.opacity(0.55))
                            .frame(width: size * 0.12, height: size * 0.12)
                            .offset(x: size * 0.12, y: size * 0.1)
                    }
                    .shadow(color: Self.tint(color).opacity(gem.power == .none ? 0.35 : 0.9),
                            radius: gem.power == .none ? 1.5 : 7)
                    .padding(size * 0.14)
                if gem.power == .bomb { bomb }
                if gem.power == .cross { cross }
            }
            if gem.crystal, !(faceted && gem.color != nil && gem.power != .lightning) {
                // A cut gem draws its crystal in its own socket.
                Image(systemName: "diamond.fill")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(.cyan)
                    .shadow(color: .cyan, radius: 4)
                    .overlay { Image(systemName: "diamond").font(.system(size: size * 0.26, weight: .bold)).foregroundStyle(.white) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(size * 0.04)
            }
            if gem.ice > 0 { Match3Ice(layers: gem.ice, size: size) }
        }
        .frame(width: size, height: size)
        .scaleEffect(selected ? 1.12 : 1)
        .animation(.spring(duration: 0.25, bounce: 0.5), value: selected)
        .phaseAnimator(hinted ? [false, true] : [false]) { content, up in
            content.scaleEffect(up ? 1.16 : 1)
        } animation: { _ in .easeInOut(duration: 0.45) }
    }

    private var bomb: some View {
        Image(systemName: "burst.fill")
            .font(.system(size: size * 0.34, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .phaseAnimator([false, true]) { content, up in
                content.scaleEffect(up ? 1.12 : 0.92)
            } animation: { _ in .easeInOut(duration: 0.6) }
    }

    private var cross: some View {
        ZStack {
            Capsule().frame(width: size * 0.62, height: size * 0.11)
            Capsule().frame(width: size * 0.11, height: size * 0.62)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.4), radius: 2)
        .phaseAnimator([false, true]) { content, up in
            content.opacity(up ? 1 : 0.7)
        } animation: { _ in .easeInOut(duration: 0.6) }
    }

    /// A different shape per colour, so the board reads without colour too.
    static func symbol(_ color: GemColor) -> String {
        switch color {
        case .red: "heart.fill"
        case .orange: "hexagon.fill"
        case .yellow: "star.fill"
        case .green: "leaf.fill"
        case .blue: "drop.fill"
        case .purple: "triangle.fill"
        }
    }

    fileprivate static func rgb(_ color: GemColor) -> (Double, Double, Double) {
        switch color {
        case .red: (1.0, 0.25, 0.36)
        case .orange: (1.0, 0.56, 0.12)
        case .yellow: (1.0, 0.83, 0.16)
        case .green: (0.26, 0.84, 0.40)
        case .blue: (0.22, 0.58, 1.0)
        case .purple: (0.70, 0.38, 1.0)
        }
    }

    static func tint(_ color: GemColor?) -> Color {
        guard let color else { return .white }
        let (r, g, b) = rgb(color)
        return Color(red: r, green: g, blue: b)
    }

    static func light(_ color: GemColor) -> Color {
        let (r, g, b) = rgb(color)
        return Color(red: r + (1 - r) * 0.55, green: g + (1 - g) * 0.55, blue: b + (1 - b) * 0.55)
    }
}

/// A cut stone: a ring of facets lit from the top left around a flat table,
/// and a dark girdle. Each colour has its own cut, so the board still reads
/// without colour. Every stone has the same diamond-shaped socket in the
/// middle of its table, which a crystal fills.
private struct Match3CutGem: View {
    /// Half the socket's width and height, as a share of the gem.
    private static let socket = CGSize(width: 0.14, height: 0.19)

    /// How far the table reaches toward the edge. The star and the triangle
    /// have thin middles, so theirs open wider to hold the socket.
    static func tableScale(_ color: GemColor) -> CGFloat {
        switch color {
        case .yellow: 0.76
        case .purple: 0.68
        default: 0.6
        }
    }

    /// Corners in a unit square centred on zero.
    let outline: [CGPoint]
    let rgb: (Double, Double, Double)
    let table: CGFloat
    let crystal: Bool

    static func outline(_ color: GemColor) -> [CGPoint] {
        switch color {
        case .red: polygon(8, radius: 0.5, turn: .pi / 8)
        case .orange: polygon(6, radius: 0.5, turn: 0)
        case .yellow: (0..<10).map { i in
            let a = Double(i) / 10 * 2 * .pi - .pi / 2
            let r = i.isMultiple(of: 2) ? 0.52 : 0.27
            return CGPoint(x: cos(a) * r, y: sin(a) * r + 0.04)
        }
        case .green: [(-0.27, -0.47), (0.27, -0.47), (0.38, -0.36), (0.38, 0.36),
                      (0.27, 0.47), (-0.27, 0.47), (-0.38, 0.36), (-0.38, -0.36)].map { CGPoint(x: $0.0, y: $0.1) }
        case .blue: [(-0.28, -0.4), (0.28, -0.4), (0.5, -0.12), (0, 0.5), (-0.5, -0.12)].map { CGPoint(x: $0.0, y: $0.1) }
        case .purple: [(0, -0.46), (0.52, 0.42), (-0.52, 0.42)].map { CGPoint(x: $0.0, y: $0.1) }
        }
    }

    private static func polygon(_ n: Int, radius: Double, turn: Double) -> [CGPoint] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi + turn
            return CGPoint(x: cos(a) * radius, y: sin(a) * radius)
        }
    }

    /// The base colour, darkened below 1 and lifted toward white above it.
    private func shade(_ k: Double) -> Color {
        func f(_ v: Double) -> Double { k <= 1 ? v * k : v + (1 - v) * (k - 1) }
        return Color(red: f(rgb.0), green: f(rgb.1), blue: f(rgb.2))
    }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = outline.map { CGPoint(x: mid.x + $0.x * s, y: mid.y + $0.y * s) }
            let centre = CGPoint(x: outer.map(\.x).reduce(0, +) / CGFloat(outer.count),
                                 y: outer.map(\.y).reduce(0, +) / CGFloat(outer.count))
            let inner = outer.map { (p: CGPoint) -> CGPoint in
                let x: CGFloat = centre.x + (p.x - centre.x) * table
                let y: CGFloat = centre.y + (p.y - centre.y) * table
                return CGPoint(x: x, y: y)
            }

            var whole = Path()
            whole.addLines(outer); whole.closeSubpath()
            ctx.fill(whole, with: .color(shade(0.6)))

            // Facets facing the light (top left) are brighter.
            for i in outer.indices {
                let j = (i + 1) % outer.count
                var facet = Path()
                facet.addLines([outer[i], outer[j], inner[j], inner[i]]); facet.closeSubpath()
                let dx = (outer[i].x + outer[j].x) / 2 - centre.x
                let dy = (outer[i].y + outer[j].y) / 2 - centre.y
                let len = max(hypot(dx, dy), 0.001)
                let light = Double((-dx * 0.6 - dy * 0.8) / len)
                ctx.fill(facet, with: .color(shade(0.95 + light * 0.35)))
            }

            var flat = Path()
            flat.addLines(inner); flat.closeSubpath()
            let top = inner.map(\.y).min() ?? centre.y, bottom = inner.map(\.y).max() ?? centre.y
            ctx.fill(flat, with: .linearGradient(Gradient(colors: [shade(1.4), shade(1.0)]),
                                                 startPoint: CGPoint(x: centre.x, y: top),
                                                 endPoint: CGPoint(x: centre.x, y: bottom)))

            // The socket: top, right, bottom, left corners.
            let w = s * Self.socket.width, h = s * Self.socket.height
            let corners = [CGPoint(x: centre.x, y: centre.y - h), CGPoint(x: centre.x + w, y: centre.y),
                           CGPoint(x: centre.x, y: centre.y + h), CGPoint(x: centre.x - w, y: centre.y)]
            var socket = Path()
            socket.addLines(corners); socket.closeSubpath()
            if crystal {
                // The crystal fills the socket: four facets around a point.
                let ice: [Color] = [Color(red: 0.75, green: 0.97, blue: 1), Color(red: 0.2, green: 0.8, blue: 0.95),
                                    Color(red: 0.05, green: 0.55, blue: 0.8), Color(red: 0.45, green: 0.9, blue: 1)]
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: .cyan, radius: s * 0.08))
                    layer.fill(socket, with: .color(.cyan))
                }
                for i in corners.indices {
                    var facet = Path()
                    facet.addLines([corners[i], corners[(i + 1) % 4], centre]); facet.closeSubpath()
                    ctx.fill(facet, with: .color(ice[i]))
                }
                ctx.stroke(socket, with: .color(.white), lineWidth: max(1, s * 0.03))
            } else {
                // An empty socket is hollow: dark under its top edge, lit along the bottom.
                ctx.fill(socket, with: .linearGradient(Gradient(colors: [shade(0.3), shade(0.5), shade(1.1)]),
                                                       startPoint: corners[0], endPoint: corners[2]))
                ctx.stroke(socket, with: .color(shade(0.35)), lineWidth: max(1, s * 0.025))
            }

            ctx.stroke(whole, with: .color(shade(0.45)), lineWidth: max(1, s * 0.035))

            // A glint on the facet nearest the light.
            let lit = outer.min { $0.x + $0.y < $1.x + $1.y } ?? centre
            let glintAt = CGPoint(x: lit.x + (centre.x - lit.x) * 0.32, y: lit.y + (centre.y - lit.y) * 0.32)
            ctx.fill(Path(ellipseIn: CGRect(x: glintAt.x - s * 0.045, y: glintAt.y - s * 0.045,
                                            width: s * 0.09, height: s * 0.09)),
                     with: .color(.white.opacity(0.85)))
        }
    }
}

private struct Match3LightningOrb: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.5) / 2.5
            Circle()
                .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                                      center: .center, angle: .degrees(turn * 360)))
                .overlay { Circle().fill(Color.black.opacity(0.3)).padding(size * 0.1) }
                .overlay {
                    Image(systemName: "bolt.fill")
                        .resizable().scaledToFit()
                        .foregroundStyle(.white)
                        .padding(size * 0.2)
                }
                .shadow(color: .white.opacity(0.7), radius: 6)
                .padding(size * 0.12)
        }
    }
}

private struct Match3Ice: View {
    let layers: Int
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        shape
            .fill(Color(red: 0.72, green: 0.9, blue: 1).opacity(layers > 1 ? 0.55 : 0.35))
            .overlay { shape.strokeBorder(Color.white.opacity(0.9), lineWidth: layers > 1 ? 2.5 : 1.5) }
            .overlay {
                if layers == 1 {
                    Path { p in
                        p.move(to: CGPoint(x: size * 0.18, y: size * 0.12))
                        p.addLine(to: CGPoint(x: size * 0.42, y: size * 0.4))
                        p.addLine(to: CGPoint(x: size * 0.34, y: size * 0.58))
                        p.addLine(to: CGPoint(x: size * 0.62, y: size * 0.84))
                        p.move(to: CGPoint(x: size * 0.42, y: size * 0.4))
                        p.addLine(to: CGPoint(x: size * 0.74, y: size * 0.3))
                    }
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }
            }
            .padding(size * 0.04)
            .frame(width: size, height: size)
    }
}

// MARK: - Effects

private struct Match3EffectView: View {
    let effect: Match3Effect
    let cell: CGFloat
    let side: CGFloat
    @State private var t: CGFloat = 0

    var body: some View {
        content
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.55)) { t = 1 } }
    }

    @ViewBuilder private var content: some View {
        switch effect.kind {
        case .burst(let color):
            let tint = Match3GemView.tint(color)
            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    let angle = Double(i) / 6 * 2 * .pi + 0.4
                    Circle()
                        .fill(tint)
                        .frame(width: cell * 0.18, height: cell * 0.18)
                        .offset(x: cos(angle) * cell * 0.75 * t, y: sin(angle) * cell * 0.75 * t)
                }
                Circle()
                    .stroke(tint.opacity(0.8), lineWidth: 2)
                    .frame(width: cell * (0.4 + 0.7 * t), height: cell * (0.4 + 0.7 * t))
            }
            .opacity(Double(1 - t))
        case .blast(let power, let big, let color):
            switch power {
            case .cross:
                let width = cell * (big ? 3 : 1) * 0.7
                ZStack {
                    Capsule().frame(width: side * 2 * t, height: width * (1 - t * 0.6))
                    Capsule().frame(width: width * (1 - t * 0.6), height: side * 2 * t)
                }
                .foregroundStyle(.white)
                .shadow(color: .yellow, radius: 12)
                .opacity(Double(1 - t * 0.9))
            case .lightning:
                Circle()
                    .fill(RadialGradient(colors: [.white, Match3GemView.tint(color).opacity(0.7), .clear],
                                         center: .center, startRadius: 0, endRadius: side * t))
                    .frame(width: side * 2 * t, height: side * 2 * t)
                    .opacity(Double(1 - t))
            default:
                let reach = cell * (big ? 5 : 3) * (0.3 + t)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.white, .orange.opacity(0.85), .clear],
                                             center: .center, startRadius: 0, endRadius: reach / 2))
                    Circle().stroke(Color.white, lineWidth: 3)
                }
                .frame(width: reach, height: reach)
                .opacity(Double(1 - t))
            }
        case .crack:
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) / 4 * 2 * .pi + 0.8
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: cell * 0.16, height: cell * 0.07)
                        .rotationEffect(.radians(angle + Double(t) * 2))
                        .offset(x: cos(angle) * cell * 0.6 * t, y: sin(angle) * cell * 0.6 * t)
                }
            }
            .opacity(Double(1 - t))
        }
    }
}


/// The dusty plum toy world of Gems, a jewellery box for the faceted stones.
enum ToyGems {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.96, 0.93, 0.97), dark: (0.15, 0.11, 0.17)),
        backdropBottom: .dynamic(light: (0.88, 0.82, 0.91), dark: (0.08, 0.06, 0.10)),
        tray: .dynamic(light: (0.58, 0.46, 0.64), dark: (0.32, 0.24, 0.37)),
        socket: .dynamic(light: (0.50, 0.38, 0.56), dark: (0.24, 0.18, 0.28)),
        ink: .dynamic(light: (0.33, 0.21, 0.39), dark: (0.96, 0.91, 0.98)),
        deboss: .dynamic(light: (0.86, 0.79, 0.89), dark: (0.40, 0.31, 0.45)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.05, 0.03, 0.06)),
        card: .dynamic(light: (0.99, 0.97, 1.0), dark: (0.23, 0.18, 0.26)),
        accent: .dynamic(light: (0.78, 0.42, 0.70), dark: (0.90, 0.56, 0.82)))
    static let flame = Color.dynamic(light: (0.95, 0.55, 0.30), dark: (1.0, 0.66, 0.40))
    static let crystal = Color.dynamic(light: (0.30, 0.70, 0.88), dark: (0.48, 0.82, 0.96))
    static let timeOK = Color.dynamic(light: (0.47, 0.76, 0.56), dark: (0.42, 0.70, 0.50))
    static let warning = Color.dynamic(light: (0.95, 0.52, 0.50), dark: (0.88, 0.42, 0.42))
}
