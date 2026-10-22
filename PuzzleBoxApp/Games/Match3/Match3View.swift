import SwiftUI

// MARK: - Screen

struct Match3View: View {
    @State private var engine: Match3Engine

    init(mode: Match3Mode) {
        _engine = State(initialValue: Match3Engine(mode: mode))
    }

    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine,
                          resultSummary: engine.mode == .casual ? nil : L10n.format("Level %d", engine.levelNumber),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 14) {
                if engine.mode == .casual {
                    HStack {
                        Label(L10n.format("Combo ×%d", max(engine.bestCascade, 1)), systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: engine.bestCascade)
                        Spacer()
                        ClassicTableButton(title: L10n.text("Hint"), symbol: "lightbulb",
                                           isEnabled: !engine.isBusy && !engine.isEnding) { engine.showHint() }
                    }
                } else {
                    Match3GoalBar(engine: engine)
                }
                Match3BoardView(engine: engine)
                Text(L10n.text("Swipe a gem to swap it with a neighbour."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .task { await engine.runClock() }
    }
}

/// Level, crystals collected, and the clock (Blitz) or the moves left (Arcade).
struct Match3GoalBar: View {
    let engine: Match3Engine

    private var fraction: Double { engine.timeLeft / Match3Level.time }

    var body: some View {
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
                                  hinted: engine.hint.contains(piece.at))
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

    var body: some View {
        ZStack {
            if selected {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .padding(size * 0.03)
            }
            if gem.power == .lightning {
                Match3LightningOrb(size: size)
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
            if gem.crystal {
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

    private static func rgb(_ color: GemColor) -> (Double, Double, Double) {
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
