import SwiftUI

struct MotionView: View {
    @State private var engine: MotionEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(mode: MotionMode) { _engine = State(initialValue: MotionEngine(mode: mode)) }
    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine) {
            VStack(spacing: 12) {
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
                            Text(L10n.text("Tap to start")).font(.title2.bold()).foregroundStyle(GameTheme.accent)
                                .padding(24).background(GameTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in engine.touch(normalize(v.location, geometry.size)) }
                        .onEnded { _ in engine.start() })
                }
                .arenaFit(320.0 / 460)
                VStack(spacing: 4) {
                    Text(L10n.text(engine.mode.hint))
                    Text(L10n.text(engine.mode.bonusHint)).foregroundStyle(GameTheme.accent)
                }
                .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false }
        .onChange(of: scenePhase) { _, value in engine.active = value == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(now - last); last = now
            }
        }
    }
    /// Stable pseudo-random 0..<1 per star, so the field never lines up in rows.
    private func hash(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
    private func normalize(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x / size.width * 320, y: p.y / size.height * 460) }
    private func draw(_ context: inout GraphicsContext) {
        func ball(_ p: CGPoint, _ r: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        func shinyBall(_ p: CGPoint, _ r: CGFloat, _ light: Color, _ dark: Color) {
            ball(CGPoint(x: p.x + 1.5, y: p.y + 2.5), r, .black.opacity(0.35))
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [light, dark]), center: CGPoint(x: p.x - r * 0.35, y: p.y - r * 0.4),
                                               startRadius: 0, endRadius: r * 1.5))
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat = 3) {
            var p = Path(); p.move(to: a); p.addLine(to: b); context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        func box(_ rect: CGRect, _ color: Color, _ radius: CGFloat = 5) { context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color)) }
        func background(_ top: Color, _ bottom: Color) {
            context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)),
                         with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 460)))
        }
        func star(_ p: CGPoint, _ r: CGFloat, _ spin: CGFloat, _ color: Color) {
            var path = Path()
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5 - .pi / 2 + spin, len = i.isMultiple(of: 2) ? r : r * 0.45
                let q = CGPoint(x: p.x + cos(a) * len, y: p.y + sin(a) * len)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            ball(p, r * 1.5, color.opacity(0.18))
            context.fill(path, with: .color(color))
        }
        func gem(_ p: CGPoint, _ r: CGFloat, _ spin: CGFloat) {
            let w = r * (0.55 + 0.45 * abs(cos(spin)))
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - r)); path.addLine(to: CGPoint(x: p.x + w, y: p.y))
            path.addLine(to: CGPoint(x: p.x, y: p.y + r)); path.addLine(to: CGPoint(x: p.x - w, y: p.y)); path.closeSubpath()
            ball(p, r * 1.4, Color.mint.opacity(0.18))
            context.fill(path, with: .linearGradient(Gradient(colors: [.white, .mint, .teal]), startPoint: CGPoint(x: p.x, y: p.y - r), endPoint: CGPoint(x: p.x, y: p.y + r)))
        }
        func trail(_ color: Color, _ radius: CGFloat) {
            for (i, p) in engine.trail.enumerated() {
                let t = CGFloat(i) / CGFloat(max(1, engine.trail.count))
                ball(p, radius * t, color.opacity(Double(t) * 0.35))
            }
        }
        switch engine.mode {
        case .slope:
            background(Color(red: 0.05, green: 0.03, blue: 0.14), Color(red: 0.02, green: 0.08, blue: 0.16))
            // Neon track with scrolling rungs and side rails.
            context.fill(Path(CGRect(x: 22, y: 0, width: 276, height: 460)),
                         with: .linearGradient(Gradient(colors: [.cyan.opacity(0.03), .cyan.opacity(0.14)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 460)))
            for i in -1..<10 {
                let y = CGFloat(i) * 55 + engine.distance.truncatingRemainder(dividingBy: 55)
                line(CGPoint(x: 22, y: y), CGPoint(x: 298, y: y), .cyan.opacity(0.08 + Double(y / 460) * 0.25), 1)
            }
            for x in [91, 160, 229] { line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 460), .cyan.opacity(0.15), 1) }
            for x in [22, 298] {
                line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 460), .pink.opacity(0.3), 6)
                line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 460), .pink, 2)
            }
            for o in engine.obstacles {
                let edge: Color = o.kind == 1 ? .orange : .pink
                box(o.rect.insetBy(dx: -3, dy: -3), edge.opacity(0.2), 8)
                context.fill(Path(roundedRect: o.rect, cornerRadius: 6),
                             with: .linearGradient(Gradient(colors: [Color(white: 0.02), Color(red: 0.15, green: 0.02, blue: 0.12)]),
                                                   startPoint: CGPoint(x: 0, y: o.rect.minY), endPoint: CGPoint(x: 0, y: o.rect.maxY)))
                context.stroke(Path(roundedRect: o.rect, cornerRadius: 6), with: .color(edge), lineWidth: 2)
                if o.kind == 1 {
                    let arrow = o.velocity.dx > 0 ? "›" : "‹"
                    context.draw(Text(arrow).font(.system(size: 22, weight: .heavy)).foregroundStyle(edge), at: CGPoint(x: o.p.x, y: o.p.y))
                }
            }
            for p in engine.pickups { gem(p.p, 9, p.spin) }
            trail(GameTheme.accent, 11)
            shinyBall(engine.player, 12, .white, GameTheme.accent)
            let a = engine.distance / 12
            ball(CGPoint(x: engine.player.x + sin(a) * 6, y: engine.player.y + cos(a) * 6), 2.5, .black.opacity(0.45))
            if engine.combo >= 2 {
                context.draw(Text(verbatim: "×\(min(engine.combo, 5))").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.mint),
                             at: CGPoint(x: engine.player.x + 26, y: engine.player.y - 16))
            }
        case .circlePong:
            background(Color(red: 0.06, green: 0.04, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.07))
            let center = CGPoint(x: 160, y: 230)
            for r in stride(from: 30, through: 120, by: 30) {
                context.stroke(Path(ellipseIn: CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r), width: CGFloat(r) * 2, height: CGFloat(r) * 2)),
                               with: .color(.white.opacity(0.04)), lineWidth: 1)
            }
            context.stroke(Path(ellipseIn: CGRect(x: 26, y: 96, width: 268, height: 268)), with: .color(.pink.opacity(0.35)), lineWidth: 2)
            context.draw(Text(verbatim: "\(engine.rally)").font(.system(size: 64, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.07)), at: center)
            for p in engine.pickups { star(p.p, 10, p.spin, .yellow) }
            var arc = Path()
            arc.addArc(center: center, radius: 134, startAngle: .radians(Double(engine.paddle - engine.paddleHalfWidth)),
                       endAngle: .radians(Double(engine.paddle + engine.paddleHalfWidth)), clockwise: false)
            context.stroke(arc, with: .color(GameTheme.accent.opacity(0.3)), style: StrokeStyle(lineWidth: 18, lineCap: .round))
            context.stroke(arc, with: .color(GameTheme.accent), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            trail(.white, 7)
            shinyBall(engine.player, 8, .white, Color(white: 0.7))
        case .spaceDodge:
            background(Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.08, green: 0.03, blue: 0.14))
            for i in 0..<40 {
                let layer = CGFloat(i % 3 + 1)
                let y = (hash(i, 1) * 460 + engine.distance * 0.25 * layer).truncatingRemainder(dividingBy: 460)
                ball(CGPoint(x: hash(i, 2) * 320, y: y), 0.5 * layer, .white.opacity(0.2 + 0.15 * Double(layer)))
            }
            for o in engine.obstacles {
                var rock = context
                rock.translateBy(x: o.p.x, y: o.p.y)
                rock.rotate(by: .radians(Double(o.spin)))
                let r = o.size.width / 2
                var shape = Path()
                for k in 0..<9 {
                    let a = CGFloat(k) / 9 * .pi * 2
                    let wobble = 0.82 + 0.18 * sin(CGFloat(k * (o.kind + 3)) * 1.7)
                    let q = CGPoint(x: cos(a) * r * wobble, y: sin(a) * r * wobble)
                    if k == 0 { shape.move(to: q) } else { shape.addLine(to: q) }
                }
                shape.closeSubpath()
                rock.fill(shape, with: .linearGradient(Gradient(colors: [Color(white: 0.6), Color(red: 0.35, green: 0.3, blue: 0.32)]),
                                                       startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)))
                rock.fill(Path(ellipseIn: CGRect(x: -r * 0.45, y: -r * 0.35, width: r * 0.5, height: r * 0.45)), with: .color(.black.opacity(0.25)))
                rock.fill(Path(ellipseIn: CGRect(x: r * 0.15, y: r * 0.2, width: r * 0.3, height: r * 0.3)), with: .color(.black.opacity(0.2)))
            }
            for p in engine.pickups {
                if p.kind == 1 {
                    ball(p.p, 16, .cyan.opacity(0.2))
                    context.stroke(Path(ellipseIn: CGRect(x: p.p.x - 11, y: p.p.y - 11, width: 22, height: 22)), with: .color(.cyan), lineWidth: 3)
                    context.draw(Text(Image(systemName: "shield.fill")).font(.system(size: 11)).foregroundStyle(.cyan), at: p.p)
                } else {
                    star(p.p, 9, p.spin, .yellow)
                }
            }
            let p = engine.player
            // Engine flame flickers behind the ship.
            let flame = 10 + 5 * abs(sin(engine.elapsed * 30))
            var fire = Path(); fire.move(to: CGPoint(x: p.x - 5, y: p.y + 8)); fire.addLine(to: CGPoint(x: p.x, y: p.y + 8 + flame)); fire.addLine(to: CGPoint(x: p.x + 5, y: p.y + 8)); fire.closeSubpath()
            context.fill(fire, with: .linearGradient(Gradient(colors: [.yellow, .orange.opacity(0)]), startPoint: CGPoint(x: p.x, y: p.y + 8), endPoint: CGPoint(x: p.x, y: p.y + 8 + flame)))
            var ship = Path(); ship.move(to: CGPoint(x: p.x, y: p.y - 15))
            ship.addLine(to: CGPoint(x: p.x - 12, y: p.y + 12)); ship.addLine(to: CGPoint(x: p.x, y: p.y + 6)); ship.addLine(to: CGPoint(x: p.x + 12, y: p.y + 12)); ship.closeSubpath()
            var hull = context
            if engine.invulnerable > 0 { hull.opacity = engine.elapsed.truncatingRemainder(dividingBy: 0.2) < 0.1 ? 0.35 : 1 }
            hull.fill(ship, with: .linearGradient(Gradient(colors: [.white, GameTheme.accent]), startPoint: CGPoint(x: p.x, y: p.y - 15), endPoint: CGPoint(x: p.x, y: p.y + 12)))
            ball(CGPoint(x: p.x, y: p.y - 2), 3, .cyan)
            if engine.shield {
                let pulse = 1 + 0.06 * sin(engine.elapsed * 6)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 21 * pulse, y: p.y - 21 * pulse, width: 42 * pulse, height: 42 * pulse)),
                               with: .color(.cyan.opacity(0.75)), lineWidth: 2.5)
                ball(p, 21 * pulse, .cyan.opacity(0.12))
            }
        case .endlessClimb:
            // The sky darkens into space as you climb.
            let height = min(1, Double(engine.distance) / 6000)
            background(Color(hue: 0.6 + height * 0.15, saturation: 0.6, brightness: 0.45 - height * 0.33),
                       Color(hue: 0.55 + height * 0.1, saturation: 0.5, brightness: 0.25 - height * 0.18))
            for i in 0..<16 {
                let y = (hash(i, 3) * 460 + engine.distance * 0.3).truncatingRemainder(dividingBy: 460)
                ball(CGPoint(x: hash(i, 4) * 300 + 10, y: y), 1.2, .white.opacity(0.1 + height * 0.5))
            }
            for o in engine.obstacles {
                let r = o.rect
                switch o.kind {
                case 1:
                    box(r, .orange, 5)
                    box(CGRect(x: r.minX + 3, y: r.minY + 1, width: r.width - 6, height: 3), .white.opacity(0.4), 2)
                case 2:
                    box(r, Color(red: 0.6, green: 0.45, blue: 0.3), 5)
                    var crack = Path(); crack.move(to: CGPoint(x: r.midX - 10, y: r.minY)); crack.addLine(to: CGPoint(x: r.midX, y: r.maxY - 3)); crack.addLine(to: CGPoint(x: r.midX + 8, y: r.minY + 2))
                    context.stroke(crack, with: .color(.black.opacity(0.55)), lineWidth: 1.5)
                default:
                    box(r, .mint, 5)
                    box(CGRect(x: r.minX + 3, y: r.minY + 1, width: r.width - 6, height: 3), .white.opacity(0.5), 2)
                }
                if o.kind == 3 {
                    var spring = Path()
                    for k in 0..<5 { spring.addLine(to: CGPoint(x: r.midX + (k.isMultiple(of: 2) ? -6 : 6), y: r.minY - CGFloat(k) * 2.5)) }
                    context.stroke(spring, with: .color(.yellow), lineWidth: 2)
                    box(CGRect(x: r.midX - 9, y: r.minY - 13, width: 18, height: 4), .red, 2)
                }
            }
            for p in engine.pickups {
                let squeeze = abs(cos(p.spin))
                context.fill(Path(ellipseIn: CGRect(x: p.p.x - 8 * squeeze, y: p.p.y - 8, width: 16 * squeeze, height: 16)), with: .color(.yellow))
                context.stroke(Path(ellipseIn: CGRect(x: p.p.x - 5 * squeeze, y: p.p.y - 5, width: 10 * squeeze, height: 10)), with: .color(.orange), lineWidth: 1.5)
            }
            trail(GameTheme.accent, 8)
            let s = engine.squash
            let w = 20 * (1 + s * 0.3), h = 20 * (1 - s * 0.25)
            let body = CGRect(x: engine.player.x - w / 2, y: engine.player.y + 10 - h, width: w, height: h)
            context.fill(Path(ellipseIn: body), with: .radialGradient(Gradient(colors: [.white, GameTheme.accent]), center: CGPoint(x: body.midX - 3, y: body.midY - 4), startRadius: 0, endRadius: 14))
            ball(CGPoint(x: body.midX - 4, y: body.midY - 1), 2, .black)
            ball(CGPoint(x: body.midX + 4, y: body.midY - 1), 2, .black)
        }
    }
}
