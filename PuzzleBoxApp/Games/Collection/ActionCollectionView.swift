import SwiftUI

struct ActionCollectionView: View {
    @State private var engine: ActionCollectionEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(mode: ActionMode) { _engine = State(initialValue: ActionCollectionEngine(mode: mode)) }

    private var palette: ToyPalette { ToyArcades.palette(for: engine.mode) }

    private var isShowcase = false

    /// Just the scene, a moment into a round, for the Home preview.
    init(showcase engine: ActionCollectionEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }

    var body: some View {
        if isShowcase {
            ToyShowcaseFrame(palette: palette, cornerRadius: 18) {
                Canvas { context, size in
                    context.scaleBy(x: size.width / 320, y: size.height / 460)
                    draw(&context)
                    engine.fx.draw(in: &context)
                }
            }
        } else {
            gameBody
        }
    }

    @ViewBuilder
    private var gameBody: some View {
        let palette = palette
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.mode == .chainReaction ? L10n.format("Level %d", engine.level) : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
          ToyGameStage(palette: palette) {
            comboChip
          } content: {
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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        if !engine.started {
                            TapToStartCard()
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
                .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                // The rules keep their place and fade once the round starts.
                Text(L10n.text(engine.mode.rules))
                    .font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.center)
                    .opacity(engine.started ? 0 : 0.6)
                    .animation(.easeOut(duration: 0.3), value: engine.started)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
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

    private var comboChip: some View {
        ToyChip(color: palette.card) {
            Label { Text(verbatim: "×\(engine.multiplier)") } icon: { Image(systemName: "flame.fill") }
                .foregroundStyle(palette.accent)
                .monospacedDigit()
        }
        .opacity(engine.multiplier > 1 ? 1 : 0)
        .scaleEffect(engine.multiplier > 1 ? 1 : 0.6)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: engine.multiplier > 1)
    }

    private var hud: some View {
        let palette = palette
        return HStack(spacing: 8) {
            if engine.timed {
                let low = engine.timeLeft < 6
                ToyChip(color: low ? ToyArcades.warning : palette.card) {
                    Label(String(format: "0:%02d", Int(ceil(engine.timeLeft))), systemImage: "timer")
                        .foregroundStyle(low ? Color.white : palette.ink)
                        .monospacedDigit()
                }
            }
            if engine.mode == .chainReaction {
                ToyChip(color: palette.card) { Text(L10n.format("Level %d", engine.level)) }
            }
            Spacer(minLength: 0)
            switch engine.mode {
            case .chainReaction:
                ToyChip(color: palette.card) { Text(verbatim: "\(engine.progress) / \(engine.chainTarget)").monospacedDigit() }
            case .redGreen:
                ToyChip(color: palette.card) {
                    Label { Text(verbatim: "\(engine.progress) / \(ActionCollectionEngine.redGreenGoal)") } icon: { Image(systemName: "flag.checkered") }
                        .monospacedDigit()
                }
            default: EmptyView()
            }
            if engine.usesLives {
                ToyChip(color: palette.card) {
                    HStack(spacing: 3) {
                        ForEach(0..<engine.maxLives, id: \.self) { i in
                            Image(systemName: "heart.fill")
                                .foregroundStyle(i < engine.lives ? ToyArcades.warning : palette.ink.opacity(0.18))
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
            }
        }
        .foregroundStyle(palette.ink)
        .frame(minHeight: 40)
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
        let pal = palette
        // The play field: a soft well in the tray.
        context.fill(Path(CGRect(x: -20, y: -20, width: 360, height: 500)), with: .color(pal.socket))
        context.fill(Path(CGRect(x: -20, y: -20, width: 360, height: 80)),
                     with: .linearGradient(Gradient(colors: [.black.opacity(0.10), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 60)))
        switch engine.mode {
        case .redGreen:
            // A clay traffic light with three lamps.
            ToyCanvas.clay(&context, CGRect(x: 118, y: 16, width: 84, height: 176), ToyArcades.slate, radius: 22, lip: 6)
            for (i, color) in [ToyArcades.stop, ToyArcades.amber, ToyArcades.go].enumerated() {
                let lit = (i == 0 && engine.signal == 0) || (i == 1 && engine.signal == 2) || (i == 2 && engine.signal == 1)
                let c = CGPoint(x: 160, y: 48 + CGFloat(i) * 53)
                circle(c, 23, .black.opacity(0.35))
                if lit {
                    circle(c, 34, color.opacity(0.3))
                    ToyCanvas.bead(&context, c, 20, color)
                    circle(CGPoint(x: c.x - 7, y: c.y - 8), 5, .white.opacity(0.6))
                } else {
                    circle(c, 19, color.opacity(0.18))
                }
            }
            label(L10n.text(engine.signal == 1 ? "Go!" : "Stop!"), CGPoint(x: 160, y: 214), 26, engine.signal == 1 ? ToyArcades.go : ToyArcades.stop)
            // A clay track with lane stripes, a finish line and the runner.
            let track = CGRect(x: 122, y: 234, width: 76, height: 206)
            ToyCanvas.clay(&context, track, ToyArcades.clayTrack, radius: 14, lip: 6)
            for y in stride(from: track.minY + 20, to: track.maxY - 14, by: 20) { box(CGRect(x: 158, y: y, width: 4, height: 10), .white.opacity(0.45), 2) }
            for k in 0..<8 {
                box(CGRect(x: track.minX + 4 + CGFloat(k) * 8.5, y: track.minY + 6, width: 8.5, height: 7), k.isMultiple(of: 2) ? .white : Color(white: 0.2), 0)
            }
            let runnerY = 420 - CGFloat(engine.progress) / CGFloat(ActionCollectionEngine.redGreenGoal) * 180
            let bob = engine.pushback > 0 ? CGFloat(sin(engine.clock * 60)) * 3 : 0
            ToyCanvas.bead(&context, CGPoint(x: 160 + bob, y: runnerY), 13, pal.card)
            circle(CGPoint(x: 155 + bob, y: runnerY - 2), 2, pal.ink)
            circle(CGPoint(x: 165 + bob, y: runnerY - 2), 2, pal.ink)
        case .perfectTiming:
            label("\(engine.progress)", CGPoint(x: 160, y: 350), 64, pal.ink.opacity(0.12))
            let bar = CGRect(x: 20, y: 195, width: 280, height: 70)
            ToyCanvas.clay(&context, bar.insetBy(dx: -8, dy: -8).offsetBy(dx: 0, dy: 2), pal.tray, radius: 22, lip: 6)
            ToyCanvas.well(&context, bar, pal.socket, radius: 16)
            let half = engine.zoneHalfWidth
            let zoneRect = CGRect(x: engine.zone - half, y: 199, width: half * 2, height: 62)
            ToyCanvas.clay(&context, zoneRect, pal.accent, radius: 12, lip: 4)
            ToyCanvas.clay(&context, CGRect(x: engine.zone - half * 0.3, y: 203, width: half * 0.6, height: 54), ToyArcades.amber, radius: 8, lip: 3)
            // The marker: a white clay pin.
            ToyCanvas.clay(&context, CGRect(x: engine.marker - 5, y: 178, width: 10, height: 106), pal.card, radius: 5, lip: 3)
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

    private static let grassLight = Color.dynamic(light: (0.62, 0.84, 0.45), dark: (0.24, 0.40, 0.18))
    private static let grassDark = Color.dynamic(light: (0.50, 0.76, 0.37), dark: (0.17, 0.31, 0.13))
    private static let rim = Color.dynamic(light: (0.78, 0.53, 0.33), dark: (0.50, 0.33, 0.20))
    private static let rimLight = Color.dynamic(light: (0.92, 0.70, 0.47), dark: (0.64, 0.45, 0.29))

    /// Mown grass: a soft gradient with lighter lanes and a few tufts.
    private func drawMeadow(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)),
                     with: .linearGradient(Gradient(colors: [Self.grassLight, Self.grassDark]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 460)))
        for lane in stride(from: 0, to: 460, by: 92) {
            context.fill(Path(CGRect(x: 0, y: CGFloat(lane), width: 320, height: 46)), with: .color(.white.opacity(0.08)))
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

/// Clay drawing shared by the canvas arcades: raised pieces with a darker
/// lip and a top sheen, and beads lit from the top left.
enum ToyCanvas {
    static func clay(_ context: inout GraphicsContext, _ r: CGRect, _ color: Color, radius: CGFloat, lip: CGFloat = 4) {
        let face = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - lip)
        context.fill(Path(roundedRect: face.offsetBy(dx: 0, dy: lip + 2), cornerRadius: radius), with: .color(.black.opacity(0.12)))
        context.fill(Path(roundedRect: face.offsetBy(dx: 0, dy: lip), cornerRadius: radius), with: .color(color.toyShade(-0.22)))
        context.fill(Path(roundedRect: face, cornerRadius: radius),
                     with: .linearGradient(Gradient(colors: [color.toyShade(0.08), color, color.toyShade(-0.04)]),
                                           startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.maxY)))
        context.stroke(Path(roundedRect: face.insetBy(dx: 1, dy: 1), cornerRadius: max(1, radius - 1)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                                             startPoint: CGPoint(x: face.midX, y: face.minY), endPoint: CGPoint(x: face.midX, y: face.midY)),
                       lineWidth: 1.5)
    }

    static func bead(_ context: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r + r * 0.25, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.14)))
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r + r * 0.14, width: r * 2, height: r * 2)), with: .color(color.toyShade(-0.25)))
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [color.toyShade(0.2), color, color.toyShade(-0.04)]),
                                           center: CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
    }

    static func well(_ context: inout GraphicsContext, _ r: CGRect, _ color: Color, radius: CGFloat) {
        let path = Path(roundedRect: r, cornerRadius: radius)
        context.fill(path, with: .color(color))
        context.fill(path, with: .linearGradient(Gradient(colors: [.black.opacity(0.16), .clear]),
                                                 startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.minY + min(r.height, 60) * 0.4)))
    }
}

/// The toy worlds of the quick arcades.
enum ToyArcades {
    static func palette(for mode: ActionMode) -> ToyPalette {
        switch mode {
        case .whackMole: mole
        case .redGreen: redGreen
        default: timing
        }
    }

    /// A spring meadow with wooden mounds.
    static let mole = ToyPuzzles.world(top: (0.93, 0.98, 0.85), bottom: (0.80, 0.91, 0.67),
                                       darkTop: (0.10, 0.16, 0.08), darkBottom: (0.05, 0.09, 0.04),
                                       tray: (0.80, 0.62, 0.42), darkTray: (0.36, 0.26, 0.17),
                                       ink: (0.24, 0.36, 0.14), accent: (0.96, 0.52, 0.40), darkAccent: (1.0, 0.60, 0.48))
    /// A coral playground with a green go signal.
    static let redGreen = ToyPuzzles.world(top: (1.0, 0.93, 0.89), bottom: (0.98, 0.82, 0.76),
                                           darkTop: (0.22, 0.12, 0.10), darkBottom: (0.12, 0.06, 0.05),
                                           tray: (0.90, 0.62, 0.54), darkTray: (0.42, 0.24, 0.20),
                                           ink: (0.48, 0.20, 0.16), accent: (0.40, 0.76, 0.48), darkAccent: (0.46, 0.80, 0.54))
    /// A honey metronome with a blue sweet spot.
    static let timing = ToyPuzzles.world(top: (1.0, 0.97, 0.86), bottom: (0.98, 0.89, 0.66),
                                         darkTop: (0.20, 0.16, 0.08), darkBottom: (0.10, 0.08, 0.03),
                                         tray: (0.90, 0.72, 0.40), darkTray: (0.42, 0.32, 0.16),
                                         ink: (0.42, 0.30, 0.10), accent: (0.36, 0.56, 0.94), darkAccent: (0.48, 0.66, 1.0))
    /// Mint with a coral paddle.
    static let pong = ToyPuzzles.world(top: (0.89, 0.98, 0.95), bottom: (0.72, 0.92, 0.86),
                                       darkTop: (0.07, 0.18, 0.16), darkBottom: (0.03, 0.10, 0.09),
                                       tray: (0.46, 0.74, 0.66), darkTray: (0.16, 0.34, 0.30),
                                       ink: (0.10, 0.34, 0.30), accent: (0.96, 0.46, 0.58), darkAccent: (1.0, 0.56, 0.66))
}

extension ToyArcades {
    static let warning = Color.dynamic(light: (0.94, 0.42, 0.42), dark: (0.90, 0.42, 0.44))
    static let slate = Color.dynamic(light: (0.34, 0.37, 0.45), dark: (0.24, 0.26, 0.32))
    static let stop = Color(red: 0.96, green: 0.38, blue: 0.38)
    static let amber = Color(red: 0.99, green: 0.78, blue: 0.30)
    static let go = Color(red: 0.36, green: 0.80, blue: 0.46)
    static let clayTrack = Color.dynamic(light: (0.86, 0.50, 0.40), dark: (0.56, 0.30, 0.24))
}
