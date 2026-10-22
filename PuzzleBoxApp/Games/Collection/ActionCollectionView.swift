import SwiftUI

struct ActionCollectionView: View {
    @State private var engine: ActionCollectionEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(mode: ActionMode) { _engine = State(initialValue: ActionCollectionEngine(mode: mode)) }

    var body: some View {
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.mode == .chainReaction ? L10n.format("Level %d", engine.level) : nil) {
            VStack(spacing: 12) {
                hud
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 460)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        draw(&context)
                        engine.fx.draw(in: &context)
                        engine.fx.drawFlash(in: &context, bounds: CGRect(x: -20, y: -20, width: 360, height: 500), reduceMotion: reduceMotion)
                    }
                    .arenaBackground()
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        if !engine.started {
                            Text(L10n.text("Tap to start")).font(.title2.bold())
                                .padding(24).background(GameTheme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if !engine.started || max(abs(value.translation.width), abs(value.translation.height)) < 20 {
                                engine.tap(CGPoint(x: value.location.x / geometry.size.width * 320, y: value.location.y / geometry.size.height * 460))
                            }
                        })
                }
                .arenaFit(320.0 / 460)
                Text(L10n.text(engine.mode.rules)).font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(GameTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(now - last); last = now
            }
        }
    }

    private var hud: some View {
        HStack(spacing: 10) {
            if engine.timed {
                Label(String(format: "0:%02d", Int(ceil(engine.timeLeft))), systemImage: "timer")
                    .foregroundStyle(engine.timeLeft < 6 ? .red : GameTheme.accent)
            }
            if engine.mode == .chainReaction {
                Text(L10n.format("Level %d", engine.level))
            }
            if engine.multiplier > 1 {
                Label { Text(verbatim: "×\(engine.multiplier)") } icon: { Image(systemName: "flame.fill") }
                    .foregroundStyle(.orange).transition(.scale.combined(with: .opacity))
            }
            Spacer()
            switch engine.mode {
            case .chainReaction: Text(verbatim: "\(engine.progress) / \(engine.chainTarget)")
            case .redGreen: Text(verbatim: "\(engine.progress) / \(ActionCollectionEngine.redGreenGoal)")
            default: EmptyView()
            }
            if engine.usesLives {
                HStack(spacing: 2) {
                    ForEach(0..<engine.maxLives, id: \.self) { i in
                        Image(systemName: i < engine.lives ? "heart.fill" : "heart")
                            .foregroundStyle(i < engine.lives ? Color.pink : GameTheme.textSecondary)
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
            }
        }
        .font(.headline.monospacedDigit()).foregroundStyle(GameTheme.accent)
        .animation(.snappy, value: engine.multiplier)
    }

    private func draw(_ context: inout GraphicsContext) {
        func circle(_ p: CGPoint, _ r: CGFloat, _ color: Color, stroke: CGFloat = 0) {
            let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            if stroke > 0 { context.stroke(path, with: .color(color), lineWidth: stroke) }
            else { context.fill(path, with: .color(color)) }
        }
        func shiny(_ p: CGPoint, _ r: CGFloat, _ light: Color, _ dark: Color) {
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [light, dark]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4), startRadius: 0, endRadius: r * 1.5))
        }
        func box(_ rect: CGRect, _ color: Color, _ radius: CGFloat = 5) {
            context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
        }
        func label(_ text: String, _ p: CGPoint, _ size: CGFloat, _ color: Color) {
            context.draw(Text(text).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundStyle(color), at: p)
        }
        switch engine.mode {
        case .redGreen:
            // Traffic light with three lamps.
            box(CGRect(x: 120, y: 18, width: 80, height: 170), Color(white: 0.12), 20)
            for (i, color) in [Color.red, .yellow, .green].enumerated() {
                let lit = (i == 0 && engine.signal == 0) || (i == 1 && engine.signal == 2) || (i == 2 && engine.signal == 1)
                let c = CGPoint(x: 160, y: 50 + CGFloat(i) * 53)
                if lit { circle(c, 32, color.opacity(0.3)) }
                circle(c, 22, lit ? color : color.opacity(0.15))
            }
            label(L10n.text(engine.signal == 1 ? "Go!" : "Stop!"), CGPoint(x: 160, y: 210), 26, engine.signal == 1 ? .green : .red)
            // Track with lane stripes, finish line and the runner.
            let track = CGRect(x: 125, y: 232, width: 70, height: 200)
            box(track, Color(red: 0.45, green: 0.25, blue: 0.2), 8)
            for y in stride(from: track.minY + 10, to: track.maxY, by: 20) { box(CGRect(x: 158, y: y, width: 4, height: 10), .white.opacity(0.25), 1) }
            for k in 0..<7 { box(CGRect(x: track.minX + CGFloat(k) * 10, y: track.minY, width: 10, height: 6), k.isMultiple(of: 2) ? .white : .black, 0) }
            let runnerY = 420 - CGFloat(engine.progress) / CGFloat(ActionCollectionEngine.redGreenGoal) * 180
            let bob = engine.pushback > 0 ? CGFloat(sin(engine.clock * 60)) * 3 : 0
            shiny(CGPoint(x: 160 + bob, y: runnerY), 13, .white, GameTheme.accent)
        case .perfectTiming:
            let bar = CGRect(x: 20, y: 195, width: 280, height: 70)
            box(bar, Color(white: 0.16), 14)
            let half = engine.zoneHalfWidth
            let zoneRect = CGRect(x: engine.zone - half, y: 195, width: half * 2, height: 70)
            context.fill(Path(roundedRect: zoneRect, cornerRadius: 10), with: .linearGradient(Gradient(colors: [GameTheme.accent.opacity(0.3), GameTheme.accent.opacity(0.8), GameTheme.accent.opacity(0.3)]), startPoint: CGPoint(x: zoneRect.minX, y: 0), endPoint: CGPoint(x: zoneRect.maxX, y: 0)))
            box(CGRect(x: engine.zone - half * 0.3, y: 195, width: half * 0.6, height: 70), .yellow.opacity(0.7), 6)
            box(CGRect(x: engine.marker - 4, y: 180, width: 8, height: 100), .white.opacity(0.3), 4)
            box(CGRect(x: engine.marker - 2.5, y: 183, width: 5, height: 94), .white, 2.5)
            label("\(engine.progress)", CGPoint(x: 160, y: 340), 54, .white.opacity(0.12))
        case .bubblePop:
            for p in engine.particles {
                let fade = 1 - p.age / p.life
                // Bubbles grow in, then shrink as they are about to pop.
                let scale = CGFloat(min(1, p.age * 6)) * (fade < 0.25 ? CGFloat(0.75 + fade) : 1)
                let r = p.radius * scale
                switch p.kind {
                case 1:
                    circle(p.p, r * 1.3, .yellow.opacity(0.2)); shiny(p.p, r, .white, .yellow)
                case 2:
                    shiny(p.p, r, Color(red: 1, green: 0.4, blue: 0.4), Color(red: 0.5, green: 0, blue: 0.05))
                    context.draw(Text(Image(systemName: "flame.fill")).font(.system(size: r * 0.8)).foregroundStyle(.yellow), at: p.p)
                case 3:
                    shiny(p.p, r, .white, .cyan)
                    context.draw(Text(Image(systemName: "clock.fill")).font(.system(size: r * 0.85)).foregroundStyle(.white), at: p.p)
                default:
                    circle(p.p, r, Color.cyan.opacity(0.25))
                    circle(p.p, r, .cyan.opacity(0.8), stroke: 2)
                    circle(CGPoint(x: p.p.x - r * 0.35, y: p.p.y - r * 0.4), r * 0.22, .white.opacity(0.8))
                }
                if fade < 0.3 && p.kind != 2 { circle(p.p, r + 4, .red.opacity(0.6 * (0.3 - fade) / 0.3), stroke: 2) }
            }
        case .whackMole:
            drawMeadow(&context)
            for i in 0..<9 { drawHole(&context, i) }
        case .chainReaction:
            for p in engine.particles { shiny(p.p, p.radius, .white, ActionCollectionEngine.chainColor(p.kind)) }
            for p in engine.blasts {
                let color = ActionCollectionEngine.chainColor(p.kind)
                circle(p.p, p.radius, color.opacity(0.28))
                circle(p.p, p.radius, color, stroke: 2)
            }
            if !engine.usedTap && engine.started {
                label(L10n.format("Destroy %d", engine.chainTarget), CGPoint(x: 160, y: 30), 16, .white.opacity(0.7))
            }
        }
    }

    // MARK: Whack-a-Mole

    private static let grassLight = Color(red: 0.36, green: 0.62, blue: 0.28)
    private static let grassDark = Color(red: 0.22, green: 0.46, blue: 0.19)
    private static let rim = Color(red: 0.52, green: 0.34, blue: 0.18)
    private static let rimLight = Color(red: 0.66, green: 0.45, blue: 0.25)

    /// Mown grass: a soft gradient with lighter lanes and a few tufts.
    private func drawMeadow(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)),
                     with: .linearGradient(Gradient(colors: [Self.grassLight, Self.grassDark]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 460)))
        for lane in stride(from: 0, to: 460, by: 92) {
            context.fill(Path(CGRect(x: 0, y: CGFloat(lane), width: 320, height: 46)), with: .color(.white.opacity(0.04)))
        }
        for k in 0..<14 {
            let x = CGFloat((k * 89 + 23) % 300) + 10, y = CGFloat((k * 157 + 41) % 440) + 10
            var tuft = Path()
            for (dx, height) in [(-3.0, 5.0), (0.0, 7.0), (3.0, 5.0)] {
                tuft.move(to: CGPoint(x: x, y: y)); tuft.addQuadCurve(to: CGPoint(x: x + dx * 1.6, y: y - height), control: CGPoint(x: x + dx * 0.3, y: y - height * 0.6))
            }
            context.stroke(tuft, with: .color(Self.grassDark.opacity(0.55)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }

    /// The lower half of an ellipse from its right end to its left end.
    private func lowerHalf(_ path: inout Path, center c: CGPoint, rx: CGFloat, ry: CGFloat, reversed: Bool = false) {
        let k: CGFloat = 0.5523 // Cubic approximation of a quarter ellipse.
        let (from, to): (CGFloat, CGFloat) = reversed ? (-1, 1) : (1, -1)
        path.addCurve(to: CGPoint(x: c.x, y: c.y + ry),
                      control1: CGPoint(x: c.x + from * rx, y: c.y + ry * k), control2: CGPoint(x: c.x + from * rx * k, y: c.y + ry))
        path.addCurve(to: CGPoint(x: c.x + to * rx, y: c.y),
                      control1: CGPoint(x: c.x + to * rx * k, y: c.y + ry), control2: CGPoint(x: c.x + to * rx, y: c.y + ry * k))
    }

    /// A dirt mound with a hole; the mole climbs out of the hole and the
    /// front of the mound hides its lower body.
    private func drawHole(_ context: inout GraphicsContext, _ i: Int) {
        let p = ActionCollectionEngine.holeCenter(i)
        let hole = CGPoint(x: p.x, y: p.y + 18)
        let outer = (rx: CGFloat(48), ry: CGFloat(19)), inner = (rx: CGFloat(37), ry: CGFloat(13))
        context.fill(Path(ellipseIn: CGRect(x: hole.x - outer.rx - 3, y: hole.y - outer.ry + 6, width: outer.rx * 2 + 6, height: outer.ry * 2)),
                     with: .color(.black.opacity(0.18)))
        context.fill(Path(ellipseIn: CGRect(x: hole.x - outer.rx, y: hole.y - outer.ry, width: outer.rx * 2, height: outer.ry * 2)),
                     with: .linearGradient(Gradient(colors: [Self.rimLight, Self.rim]), startPoint: CGPoint(x: 0, y: hole.y - outer.ry), endPoint: CGPoint(x: 0, y: hole.y + outer.ry)))
        context.fill(Path(ellipseIn: CGRect(x: hole.x - inner.rx, y: hole.y - inner.ry, width: inner.rx * 2, height: inner.ry * 2)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.08, green: 0.05, blue: 0.03), Color(red: 0.2, green: 0.12, blue: 0.06)]),
                                           startPoint: CGPoint(x: 0, y: hole.y - inner.ry), endPoint: CGPoint(x: 0, y: hole.y + inner.ry)))

        if let mole = engine.holes[i] {
            // Rise out of the hole, then duck back down.
            let t = mole.age / mole.life
            let rise = CGFloat(min(1, min(t, 1 - t) * 6))
            var clip = Path()
            clip.move(to: CGPoint(x: hole.x - 60, y: hole.y - 120))
            clip.addLine(to: CGPoint(x: hole.x + 60, y: hole.y - 120))
            clip.addLine(to: CGPoint(x: hole.x + 60, y: hole.y))
            clip.addLine(to: CGPoint(x: hole.x + inner.rx, y: hole.y))
            lowerHalf(&clip, center: hole, rx: inner.rx, ry: inner.ry)
            clip.addLine(to: CGPoint(x: hole.x - 60, y: hole.y))
            clip.closeSubpath()
            var m = context
            m.clip(to: clip)
            drawMole(&m, mole, at: CGPoint(x: hole.x, y: hole.y + 48 - rise * 66))
        }

        // The front of the mound, in front of the mole.
        var lip = Path()
        lip.move(to: CGPoint(x: hole.x + outer.rx, y: hole.y))
        lowerHalf(&lip, center: hole, rx: outer.rx, ry: outer.ry)
        lip.addLine(to: CGPoint(x: hole.x - inner.rx, y: hole.y))
        lowerHalf(&lip, center: hole, rx: inner.rx, ry: inner.ry, reversed: true)
        lip.closeSubpath()
        context.fill(lip, with: .linearGradient(Gradient(colors: [Self.rimLight, Self.rim]),
                                                startPoint: CGPoint(x: 0, y: hole.y), endPoint: CGPoint(x: 0, y: hole.y + outer.ry)))
        var edge = Path()
        edge.move(to: CGPoint(x: hole.x + inner.rx, y: hole.y))
        lowerHalf(&edge, center: hole, rx: inner.rx, ry: inner.ry)
        context.stroke(edge, with: .color(Color(red: 0.8, green: 0.6, blue: 0.38).opacity(0.7)), lineWidth: 2)
    }

    /// `c` is the centre of the face; the body runs down into the hole.
    private func drawMole(_ m: inout GraphicsContext, _ mole: ActionMole, at c: CGPoint) {
        let golden = mole.kind == 1
        let fur: (Color, Color) = golden ? (Color(red: 1, green: 0.85, blue: 0.3), .orange)
                                         : (Color(red: 0.62, green: 0.44, blue: 0.3), Color(red: 0.4, green: 0.26, blue: 0.16))
        let muzzle = golden ? Color(red: 1, green: 0.95, blue: 0.7) : Color(red: 0.86, green: 0.7, blue: 0.54)
        m.fill(Path(roundedRect: CGRect(x: c.x - 25, y: c.y - 30, width: 50, height: 80), cornerRadius: 25),
               with: .linearGradient(Gradient(colors: [fur.0, fur.1]), startPoint: CGPoint(x: c.x, y: c.y - 30), endPoint: CGPoint(x: c.x, y: c.y + 30)))
        m.fill(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 3, width: 26, height: 20)), with: .color(muzzle))
        if mole.whacked {
            for dx in [-9.0, 9.0] {
                var cross = Path()
                cross.move(to: CGPoint(x: c.x + dx - 4, y: c.y - 15)); cross.addLine(to: CGPoint(x: c.x + dx + 4, y: c.y - 7))
                cross.move(to: CGPoint(x: c.x + dx + 4, y: c.y - 15)); cross.addLine(to: CGPoint(x: c.x + dx - 4, y: c.y - 7))
                m.stroke(cross, with: .color(.black), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        } else {
            for dx in [-9.0, 9.0] {
                m.fill(Path(ellipseIn: CGRect(x: c.x + dx - 5, y: c.y - 17, width: 10, height: 12)), with: .color(.white))
                m.fill(Path(ellipseIn: CGRect(x: c.x + dx - 2.5, y: c.y - 13, width: 5.5, height: 6.5)), with: .color(.black))
            }
        }
        m.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 2, width: 12, height: 8)), with: .color(Color(red: 0.95, green: 0.45, blue: 0.55)))
        m.fill(Path(roundedRect: CGRect(x: c.x - 4, y: c.y + 7, width: 8, height: 6), cornerRadius: 1.5), with: .color(.white))
        if golden {
            m.draw(Text(Image(systemName: "sparkle")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: c.x + 17, y: c.y - 24))
        }
        if mole.kind == 2 {
            let bomb = CGPoint(x: c.x + 20, y: c.y + 12)
            m.fill(Path(ellipseIn: CGRect(x: bomb.x - 11, y: bomb.y - 11, width: 22, height: 22)), with: .color(Color(white: 0.12)))
            m.fill(Path(ellipseIn: CGRect(x: bomb.x - 6, y: bomb.y - 7, width: 6, height: 5)), with: .color(.white.opacity(0.35)))
            var fuse = Path(); fuse.move(to: CGPoint(x: bomb.x + 5, y: bomb.y - 9)); fuse.addQuadCurve(to: CGPoint(x: bomb.x + 9, y: bomb.y - 17), control: CGPoint(x: bomb.x + 10, y: bomb.y - 11))
            m.stroke(fuse, with: .color(Color(red: 0.6, green: 0.45, blue: 0.3)), lineWidth: 2)
            m.fill(Path(ellipseIn: CGRect(x: bomb.x + 6, y: bomb.y - 20, width: 6, height: 6)), with: .color(sin(engine.clock * 25) > 0 ? .orange : .yellow))
        }
    }
}
