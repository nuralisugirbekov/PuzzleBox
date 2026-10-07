import SwiftUI

struct MotionView: View {
    @State private var engine: MotionEngine
    @Environment(\.scenePhase) private var scenePhase
    init(mode: MotionMode) { _engine = State(initialValue: MotionEngine(mode: mode)) }
    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 460)
                        draw(&context)
                    }
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        if !engine.started {
                            Text(L10n.text("Tap to start")).font(.title2.bold()).foregroundStyle(Theme.neon)
                                .padding(24).background(Theme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 18))
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in engine.touch(normalize(v.location, geometry.size)) }
                        .onEnded { v in engine.input(normalize(v.location, geometry.size), swipe: v.translation.width / geometry.size.width * 320) })
                }
                .aspectRatio(320.0 / 460, contentMode: .fit).frame(maxWidth: 380, maxHeight: 460)
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false; engine.release() }
        .onChange(of: scenePhase) { _, value in engine.active = value == .active; engine.release() }
        .onChange(of: engine.state) { _, _ in engine.release() }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(now - last); last = now
            }
        }
    }
    private func normalize(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x / size.width * 320, y: p.y / size.height * 460) }
    private func draw(_ context: inout GraphicsContext) {
        func ball(_ p: CGPoint, _ r: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat = 3) {
            var p = Path(); p.move(to: a); p.addLine(to: b); context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        func box(_ rect: CGRect, _ color: Color) { context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color)) }
        switch engine.mode {
        case .slope:
            box(CGRect(x: 22, y: 0, width: 276, height: 460), .cyan.opacity(0.09))
            for i in -1..<10 {
                let y = CGFloat(i) * 55 + engine.distance.truncatingRemainder(dividingBy: 55)
                line(CGPoint(x: 22, y: y), CGPoint(x: 298, y: y), .cyan.opacity(0.25), 1)
            }
            for x in [22, 91, 160, 229, 298] { line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 460), .cyan.opacity(0.25), 1) }
            for o in engine.obstacles {
                box(o.rect, .black)
                context.stroke(Path(roundedRect: o.rect, cornerRadius: 5), with: .color(.pink), lineWidth: 2)
            }
            ball(engine.player, 12, Theme.neon)
            let a = engine.distance / 12
            ball(CGPoint(x: engine.player.x + sin(a) * 6, y: engine.player.y + cos(a) * 6), 3, .black.opacity(0.5))
        case .keepItUp:
            line(CGPoint(x: 0, y: 449), CGPoint(x: 320, y: 449), .pink)
            ball(engine.player, 18, .orange)
            line(CGPoint(x: engine.player.x - 13, y: engine.player.y), CGPoint(x: engine.player.x + 13, y: engine.player.y), .black.opacity(0.4), 2)
        case .wallJump:
            box(CGRect(x: 0, y: 45, width: 15, height: 370), .cyan.opacity(0.5)); box(CGRect(x: 305, y: 45, width: 15, height: 370), .cyan.opacity(0.5))
            for o in engine.obstacles {
                for offset in [-25, 0, 25] {
                    let wall: CGFloat = o.p.x < 160 ? 15 : 305
                    var spike = Path(); spike.move(to: CGPoint(x: wall, y: o.p.y + CGFloat(offset) - 12))
                    spike.addLine(to: CGPoint(x: o.p.x, y: o.p.y + CGFloat(offset)))
                    spike.addLine(to: CGPoint(x: wall, y: o.p.y + CGFloat(offset) + 12)); spike.closeSubpath()
                    context.fill(spike, with: .color(.pink))
                }
            }
            box(CGRect(x: engine.player.x - 10, y: engine.player.y - 10, width: 20, height: 20), Theme.neon)
        case .circlePong:
            context.stroke(Path(ellipseIn: CGRect(x: 26, y: 96, width: 268, height: 268)), with: .color(Theme.textSecondary.opacity(0.3)), lineWidth: 2)
            var arc = Path(); arc.addArc(center: CGPoint(x: 160, y: 230), radius: 134, startAngle: .radians(Double(engine.paddle - 0.34)), endAngle: .radians(Double(engine.paddle + 0.34)), clockwise: false)
            context.stroke(arc, with: .color(Theme.neon), style: StrokeStyle(lineWidth: 10, lineCap: .round))
            ball(engine.player, 8, .white)
        case .spaceDodge:
            for i in 0..<30 {
                let y = (CGFloat(i * 47) + engine.distance * 0.4).truncatingRemainder(dividingBy: 460)
                ball(CGPoint(x: CGFloat((i * 97) % 320), y: y), 1, .white.opacity(0.35))
            }
            for o in engine.obstacles { ball(o.p, o.size.width / 2, .gray); ball(CGPoint(x: o.p.x - 4, y: o.p.y - 3), 4, .black.opacity(0.4)) }
            var ship = Path(); ship.move(to: CGPoint(x: engine.player.x, y: engine.player.y - 15))
            ship.addLine(to: CGPoint(x: engine.player.x - 12, y: engine.player.y + 12)); ship.addLine(to: CGPoint(x: engine.player.x, y: engine.player.y + 6)); ship.addLine(to: CGPoint(x: engine.player.x + 12, y: engine.player.y + 12)); ship.closeSubpath()
            context.fill(ship, with: .color(Theme.neon))
        case .laneSwitch:
            for x in [25, 115, 205, 295] { line(CGPoint(x: CGFloat(x), y: 0), CGPoint(x: CGFloat(x), y: 460), .gray.opacity(0.4), 2) }
            for o in engine.obstacles { box(o.rect, .pink) }
            box(CGRect(x: engine.player.x - 13, y: engine.player.y - 15, width: 26, height: 30), Theme.neon)
        case .gravityFlip:
            line(CGPoint(x: 0, y: 58), CGPoint(x: 320, y: 58), .cyan)
            line(CGPoint(x: 0, y: 402), CGPoint(x: 320, y: 402), .cyan)
            for o in engine.obstacles { box(o.rect, .pink) }
            box(CGRect(x: engine.player.x - 10, y: engine.player.y - 10, width: 20, height: 20), Theme.neon)
            context.draw(Text(engine.gravity > 0 ? "↓" : "↑").font(.title).foregroundStyle(.white.opacity(0.5)), at: CGPoint(x: 160, y: 230))
        case .cannonShot:
            ball(engine.target, 22, .cyan)
            ball(engine.target, 12, Theme.surface)
            ball(engine.cannon, 22, Theme.neon)
            line(engine.cannon, CGPoint(x: engine.cannon.x + cos(engine.angle) * 37, y: engine.cannon.y + sin(engine.angle) * 37), Theme.neon, 16)
            if !engine.loaded { ball(engine.player, 7, .white) }
        case .endlessClimb:
            for o in engine.obstacles { box(o.rect, .cyan) }
            ball(engine.player, 10, Theme.neon)
        case .drift:
            // Camera follows the car; the complete track remains continuous in world space.
            func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: 160 + (p.x - engine.player.x) * 0.65, y: 310 + (p.y - engine.player.y) * 0.65) }
            var track = Path()
            for (i, p) in engine.road.enumerated() { if i == 0 { track.move(to: screen(p)) } else { track.addLine(to: screen(p)) } }
            context.stroke(track, with: .color(.cyan.opacity(0.3)), style: StrokeStyle(lineWidth: 48, lineCap: .round, lineJoin: .round))
            context.stroke(track, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [9, 9]))
            var car = context; car.translateBy(x: 160, y: 310); car.rotate(by: .radians(Double(engine.angle)))
            car.fill(Path(roundedRect: CGRect(x: -13, y: -7, width: 26, height: 14), cornerRadius: 4), with: .color(Theme.neon))
            car.fill(Path(CGRect(x: 2, y: -5, width: 5, height: 10)), with: .color(.black.opacity(0.6)))
        }
    }
}
