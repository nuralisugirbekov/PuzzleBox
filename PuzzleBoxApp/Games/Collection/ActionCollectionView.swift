import SwiftUI

struct ActionCollectionView: View {
    @State private var engine: ActionCollectionEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(mode: ActionMode) { _engine = State(initialValue: ActionCollectionEngine(mode: mode)) }

    var body: some View {
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.mode == .chainReaction ? L10n.format("Level %d", engine.level) : nil,
                          centersContent: true) {
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
                .aspectRatio(320.0 / 460, contentMode: .fit).frame(maxWidth: 380, maxHeight: 460)
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
            box(CGRect(x: 0, y: 0, width: 320, height: 460), Color(red: 0.25, green: 0.5, blue: 0.22), 0)
            for i in 0..<9 {
                let p = ActionCollectionEngine.holeCenter(i)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 42, y: p.y + 2, width: 84, height: 34)), with: .color(Color(red: 0.25, green: 0.15, blue: 0.08)))
                if let mole = engine.holes[i] {
                    // Rise out of the hole, then duck back down.
                    let t = mole.age / mole.life
                    let rise = CGFloat(min(1, min(t, 1 - t) * 6))
                    var m = context
                    m.clip(to: Path(CGRect(x: p.x - 45, y: p.y - 70, width: 90, height: 90)))
                    let c = CGPoint(x: p.x, y: p.y + 30 - rise * 34)
                    let body: (Color, Color) = mole.kind == 1 ? (.yellow, .orange) : (Color(red: 0.7, green: 0.5, blue: 0.35), Color(red: 0.45, green: 0.3, blue: 0.18))
                    m.fill(Path(roundedRect: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 60), cornerRadius: 26),
                           with: .linearGradient(Gradient(colors: [body.0, body.1]), startPoint: CGPoint(x: c.x, y: c.y - 26), endPoint: CGPoint(x: c.x, y: c.y + 30)))
                    if mole.whacked {
                        m.draw(Text(verbatim: "x  x").font(.system(size: 12, weight: .black)).foregroundStyle(.black), at: CGPoint(x: c.x, y: c.y - 6))
                    } else {
                        m.fill(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 12, width: 7, height: 8)), with: .color(.black))
                        m.fill(Path(ellipseIn: CGRect(x: c.x + 6, y: c.y - 12, width: 7, height: 8)), with: .color(.black))
                    }
                    m.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 3, width: 12, height: 8)), with: .color(.pink))
                    if mole.kind == 2 {
                        let bomb = CGPoint(x: c.x + 22, y: c.y + 6)
                        m.fill(Path(ellipseIn: CGRect(x: bomb.x - 11, y: bomb.y - 11, width: 22, height: 22)), with: .color(.black))
                        m.fill(Path(ellipseIn: CGRect(x: bomb.x + 2, y: bomb.y - 17, width: 6, height: 6)), with: .color(sin(engine.clock * 25) > 0 ? .orange : .yellow))
                    }
                }
                // Front lip of the hole hides the mole's lower body.
                context.fill(Path(ellipseIn: CGRect(x: p.x - 44, y: p.y + 20, width: 88, height: 26)), with: .color(Color(red: 0.32, green: 0.6, blue: 0.27)))
            }
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
}
