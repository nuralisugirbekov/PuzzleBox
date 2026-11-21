import SwiftUI

struct MiniGolfView: View {
    @State private var engine = MiniGolfEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette = ToyMiniGolf.palette

    var body: some View {
        GameContainerView(gameID: .miniGolf, engine: engine,
                          resultSummary: summary,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette,
                         headline: .clock(caption: L10n.format("Strokes · par %d", engine.par),
                                          time: { "\(engine.strokes)" })) {
                ToyIconButton(symbol: "arrow.counterclockwise", label: L10n.text("Restart hole"),
                              color: palette.card, ink: palette.ink) {
                    engine.restart()
                }
                .disabled(engine.strokes == 0 || engine.isSunk)
                .opacity(engine.strokes == 0 || engine.isSunk ? 0.45 : 1)
            } content: {
                VStack(spacing: 12) {
                    hud
                    MiniGolfCourseView(engine: engine)
                    Text(L10n.text(engine.notice.isEmpty ? (GolfHoles.world(of: engine.level)?.hint ?? ToyMiniGolf.hint) : engine.notice))
                        .font(.system(engine.notice.isEmpty ? .footnote : .subheadline, design: .rounded)
                            .weight(engine.notice.isEmpty ? .regular : .bold))
                        .foregroundStyle(engine.notice.isEmpty ? palette.ink.opacity(0.6) : palette.accent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 36)
                        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: engine.notice)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
        .id(engine.level)
        .onAppear { engine.active = scenePhase == .active; engine.reduceMotion = reduceMotion }
        .onDisappear { engine.active = false }
        .onChange(of: reduceMotion) { _, value in engine.reduceMotion = value }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active; engine.cancelAim() }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(now - last)
                last = now
            }
        }
    }

    private var summary: String {
        guard engine.isSunk else { return L10n.format("Hole %d", engine.level) }
        return L10n.format("Hole %d", engine.level) + "  " + String(repeating: "★", count: engine.stars)
            + String(repeating: "☆", count: 3 - engine.stars)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(GolfHoles.worlds, id: \.first) { world in
                    Menu(L10n.text(world.name)) {
                        ForEach(world.first...min(world.last, MiniGolfEngine.levelCount), id: \.self) { level in
                            let best = engine.bestStars[level] ?? 0
                            Button(L10n.format("Hole %d", level) + (best > 0 ? "  " + String(repeating: "★", count: best) : "")) {
                                engine.selectLevel(level)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.format("Hole %d", engine.level))
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
            // Strokes left on this hole, as golf balls.
            ToyChip(color: palette.card) {
                HStack(spacing: 3) {
                    ForEach(0..<engine.maxStrokes, id: \.self) { i in
                        Circle()
                            .fill(i < engine.strokesLeft ? Color.white : palette.ink.opacity(0.12))
                            .overlay(Circle().strokeBorder(palette.ink.opacity(i < engine.strokesLeft ? 0.3 : 0.12), lineWidth: 1))
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.format("Shots left: %d", engine.strokesLeft))
            ToyChip(color: palette.card) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .foregroundStyle(i < engine.stars ? ToyMiniGolf.starGold : palette.ink.opacity(0.18))
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.format("%d stars", engine.stars))
        }
    }
}

// MARK: - Course

/// The course, drawn in a 320 × 460 field, and the pull-back aiming.
struct MiniGolfCourseView: View {
    let engine: MiniGolfEngine
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let scale = 320 / max(1, geometry.size.width)
            Canvas { context, size in
                context.scaleBy(x: size.width / 320, y: size.height / 460)
                GolfPainter(engine: engine).draw(&context)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = CGPoint(x: value.startLocation.x * scale, y: value.startLocation.y * scale)
                        let p = CGPoint(x: value.location.x * scale, y: value.location.y * scale)
                        if dragStart == nil {
                            guard engine.beginAim(at: start) else { return }
                            dragStart = start
                        }
                        guard let dragStart else { return }
                        engine.updateAim(pull: CGVector(dx: dragStart.x - p.x, dy: dragStart.y - p.y))
                    }
                    .onEnded { _ in
                        if dragStart != nil { engine.release() }
                        dragStart = nil
                    }
            )
        }
        .aspectRatio(320.0 / 460, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Hole %d", engine.level) + ", " + L10n.format("Strokes · par %d", engine.par))
        .accessibilityValue("\(engine.strokes)")
    }
}

/// Draws one frame of the course from the engine's current hole.
private struct GolfPainter {
    let engine: MiniGolfEngine

    private typealias C = ToyMiniGolf
    private var turf: Color { C.turf(theme: engine.hole.theme) }
    private var turfWall: Color { C.turfWall(theme: engine.hole.theme) }

    func draw(_ context: inout GraphicsContext) {
        let hole = engine.hole
        let time = engine.time
        var outline = Path()
        outline.addLines(hole.outline)
        outline.closeSubpath()

        // The course plate: a contact shadow, a clay side wall, then the turf.
        context.fill(outline.offsetBy(dx: 0, dy: 14), with: .color(.black.opacity(0.10)))
        for k in stride(from: 10, through: 2, by: -2) {
            context.fill(outline.offsetBy(dx: 0, dy: CGFloat(k)), with: .color(turfWall))
        }
        let bounds = outline.boundingRect
        context.fill(outline, with: .linearGradient(Gradient(colors: [turf.toyShade(0.05), turf.toyShade(-0.04)]),
                                                    startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
                                                    endPoint: CGPoint(x: bounds.midX, y: bounds.maxY)))
        context.drawLayer { layer in
            layer.clip(to: outline)
            // Mowing stripes.
            for i in stride(from: -460.0, to: 320.0, by: 48.0) {
                var band = Path()
                band.addLines([CGPoint(x: i, y: 0), CGPoint(x: i + 24, y: 0), CGPoint(x: i + 24 + 460, y: 460), CGPoint(x: i + 460, y: 460)])
                band.closeSubpath()
                layer.fill(band, with: .color(.white.opacity(0.05)))
            }
            for s in hole.slopes { drawSlope(&layer, s, time: time) }
            for m in hole.mounds { drawMound(&layer, m) }
            // The win wave rolls out from the cup.
            if let sunkAt = engine.sunkAt {
                let age = time - sunkAt
                if age < 1.3 {
                    let r = CGFloat(age) * 380
                    layer.stroke(Path(ellipseIn: CGRect(x: hole.cup.x - r, y: hole.cup.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity(0.35 * (1 - age / 1.3))), lineWidth: 18)
                }
            }
        }
        for z in hole.sand { drawSand(&context, z) }
        for z in hole.water { drawWater(&context, z, time: time) }
        for z in hole.ice { drawIce(&context, z) }
        for b in hole.boosters { drawBooster(&context, b, time: time) }
        for (i, g) in hole.gates.enumerated() { drawButton(&context, g, index: i, time: time) }

        // Tee mat.
        ToyCanvas.clay(&context, CGRect(x: hole.tee.x - 16, y: hole.tee.y - 8, width: 32, height: 19), turf.toyShade(0.1), radius: 7, lip: 3)

        for (i, portal) in hole.portals.enumerated() { drawPortal(&context, portal, index: i, time: time) }
        for (i, t) in hole.teleports.enumerated() { drawTeleport(&context, t, index: i, time: time) }
        drawCup(&context, hole.cup)

        // Rails along the edge and across the course.
        var rails = outline
        for w in hole.walls { rails.move(to: w.a); rails.addLine(to: w.b) }
        drawRail(&context, rails, C.rail)
        for m in hole.movers {
            let s = m.segment(at: time)
            drawRail(&context, Path { $0.move(to: s.a); $0.addLine(to: s.b) }, C.mover)
        }
        for (i, g) in hole.gates.enumerated() { drawGate(&context, g, index: i, time: time) }
        for (i, s) in hole.springs.enumerated() { drawSpring(&context, s, index: i, time: time) }
        for (i, b) in hole.bumpers.enumerated() { drawBumper(&context, b, index: i, time: time) }

        drawAim(&context)
        drawBall(&context)
        for s in hole.spinners { drawSpinner(&context, s, time: time) }
        for p in hole.paddles { drawPaddle(&context, p, time: time) }
        drawFlag(&context, hole.cup, time: time)
        drawSplash(&context, time: time)

        for p in engine.particles {
            var piece = context
            piece.opacity = max(0, 1 - p.age / p.life)
            piece.translateBy(x: p.p.x, y: p.p.y)
            piece.rotate(by: .radians(p.spin * p.age))
            piece.fill(Path(roundedRect: CGRect(x: -p.size, y: -p.size * 0.6, width: p.size * 2, height: p.size * 1.2), cornerRadius: 1),
                       with: .color(p.color))
        }
    }

    // MARK: Pieces

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }

    private func zonePath(_ z: GolfZone) -> Path {
        Path(roundedRect: z.rect, cornerRadius: min(z.radius, z.rect.width / 2, z.rect.height / 2), style: .continuous)
    }

    /// A clay rail: its darker wall below, the face, and a thin highlight on top.
    private func drawRail(_ context: inout GraphicsContext, _ path: Path, _ color: Color) {
        let style = StrokeStyle(lineWidth: GolfPhysics.railRadius * 2, lineCap: .round, lineJoin: .round)
        context.stroke(path.offsetBy(dx: 0, dy: 6), with: .color(.black.opacity(0.12)), style: style)
        context.stroke(path.offsetBy(dx: 0, dy: 4), with: .color(color.toyShade(-0.22)), style: style)
        context.stroke(path, with: .color(color), style: style)
        context.stroke(path.offsetBy(dx: 0, dy: -2.5), with: .color(.white.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }

    private func drawSlope(_ context: inout GraphicsContext, _ s: GolfSlope, time: Double) {
        let path = zonePath(s.zone)
        context.fill(path, with: .color(turf.toyShade(0.07)))
        let length = s.push.length
        guard length > 0 else { return }
        let dir = s.push * (1 / length)
        let angle = atan2(dir.dy, dir.dx)
        let spacing: CGFloat = 30
        let shift = CGFloat((time * 22).truncatingRemainder(dividingBy: Double(spacing)))
        context.drawLayer { layer in
            layer.clip(to: path)
            let r = s.zone.rect
            var y = r.minY + spacing / 2
            var row = 0
            while y < r.maxY + spacing {
                var x = r.minX + (row.isMultiple(of: 2) ? spacing / 2 : spacing)
                while x < r.maxX + spacing {
                    let p = CGPoint(x: x + dir.dx * shift - dir.dx * spacing, y: y + dir.dy * shift - dir.dy * spacing)
                    var chevron = layer
                    chevron.translateBy(x: p.x, y: p.y)
                    chevron.rotate(by: .radians(Double(angle)))
                    var mark = Path()
                    mark.move(to: CGPoint(x: -4, y: -6)); mark.addLine(to: CGPoint(x: 3, y: 0)); mark.addLine(to: CGPoint(x: -4, y: 6))
                    chevron.stroke(mark, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    x += spacing
                }
                y += spacing; row += 1
            }
        }
    }

    private func drawMound(_ context: inout GraphicsContext, _ m: GolfMound) {
        let bowl = m.strength > 0
        let center = bowl ? turf.toyShade(-0.14) : turf.toyShade(0.14)
        context.fill(circle(m.center, m.radius),
                     with: .radialGradient(Gradient(colors: [center, center.opacity(0)]), center: m.center,
                                           startRadius: 0, endRadius: m.radius))
        for k in 1...3 {
            let r = m.radius * CGFloat(k) / 3.4
            context.stroke(circle(m.center, r), with: .color((bowl ? Color.black : .white).opacity(0.08)), lineWidth: 1.5)
        }
    }

    /// Sand and water are pressed into the turf: a darker rim shows at the top.
    private func drawSand(_ context: inout GraphicsContext, _ z: GolfZone) {
        let path = zonePath(z)
        context.fill(path, with: .color(C.sand.toyShade(-0.16)))
        context.drawLayer { layer in
            layer.clip(to: path)
            layer.fill(path.offsetBy(dx: 0, dy: 3), with: .color(C.sand))
            // A fixed scatter of grains.
            var i = 0
            var y = z.rect.minY + 6
            while y < z.rect.maxY {
                var x = z.rect.minX + 5 + CGFloat((i * 7) % 11)
                while x < z.rect.maxX {
                    let jitter = CGFloat(sin(Double(x * 12.9 + y * 78.2)) * 3)
                    layer.fill(circle(CGPoint(x: x + jitter, y: y - jitter), 1.2), with: .color(C.sand.toyShade(-0.12)))
                    x += 13
                }
                y += 10; i += 1
            }
        }
    }

    private func drawWater(_ context: inout GraphicsContext, _ z: GolfZone, time: Double) {
        let path = zonePath(z)
        context.fill(path, with: .color(C.water.toyShade(-0.18)))
        context.drawLayer { layer in
            layer.clip(to: path)
            layer.fill(path.offsetBy(dx: 0, dy: 3), with: .linearGradient(Gradient(colors: [C.water, C.water.toyShade(-0.06)]),
                                                                          startPoint: CGPoint(x: z.rect.midX, y: z.rect.minY),
                                                                          endPoint: CGPoint(x: z.rect.midX, y: z.rect.maxY)))
            var y = z.rect.minY + 14
            var row = 0
            while y < z.rect.maxY - 6 {
                var wave = Path()
                let phase = time * 1.6 + Double(row)
                for x in stride(from: z.rect.minX - 4, through: z.rect.maxX + 4, by: 6) {
                    let p = CGPoint(x: x, y: y + CGFloat(sin(Double(x) / 11 + phase)) * 2.2)
                    if x == z.rect.minX - 4 { wave.move(to: p) } else { wave.addLine(to: p) }
                }
                layer.stroke(wave, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [10, 14], dashPhase: CGFloat(row) * 9))
                y += 16; row += 1
            }
        }
    }

    private func drawCup(_ context: inout GraphicsContext, _ cup: CGPoint) {
        context.fill(circle(cup, GolfPhysics.cupRadius + 4), with: .color(turf.toyShade(0.1)))
        context.fill(circle(cup, GolfPhysics.cupRadius),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.04), Color(white: 0.24)]),
                                           startPoint: CGPoint(x: cup.x, y: cup.y - GolfPhysics.cupRadius),
                                           endPoint: CGPoint(x: cup.x, y: cup.y + GolfPhysics.cupRadius)))
    }

    private func drawFlag(_ context: inout GraphicsContext, _ cup: CGPoint, time: Double) {
        // The flag pops up out of the cup when the ball drops.
        var lift: CGFloat = 0
        if let sunkAt = engine.sunkAt {
            let t = min(1, (time - sunkAt) / 0.6)
            lift = CGFloat(16 * sin(t * .pi) + 8 * t)
        }
        let top = CGPoint(x: cup.x, y: cup.y - 48 - lift)
        let base = CGPoint(x: cup.x, y: cup.y - lift * 0.4)
        var pole = Path(); pole.move(to: base); pole.addLine(to: top)
        context.stroke(pole.offsetBy(dx: 3, dy: 3), with: .color(.black.opacity(0.15)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        context.stroke(pole, with: .color(C.pole), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        let flutter = CGFloat(sin(time * 4.5)) * 2.5
        var cloth = Path()
        cloth.move(to: top)
        cloth.addQuadCurve(to: CGPoint(x: top.x + 26, y: top.y + 8 + flutter), control: CGPoint(x: top.x + 13, y: top.y - 2 + flutter))
        cloth.addQuadCurve(to: CGPoint(x: top.x, y: top.y + 18), control: CGPoint(x: top.x + 12, y: top.y + 16 - flutter))
        cloth.closeSubpath()
        context.fill(cloth.offsetBy(dx: 0, dy: 2.5), with: .color(C.flag.toyShade(-0.22)))
        context.fill(cloth, with: .color(C.flag))
        context.fill(circle(top, 3), with: .color(C.pole))
    }

    private func drawPortal(_ context: inout GraphicsContext, _ portal: GolfPortal, index: Int, time: Double) {
        let color = C.portal
        // Entry: a hole with a turning swirl.
        context.fill(circle(portal.entry, 15), with: .color(color.toyShade(-0.25)))
        context.fill(circle(portal.entry, 12), with: .radialGradient(Gradient(colors: [Color(white: 0.05), color.toyShade(-0.35)]),
                                                                     center: portal.entry, startRadius: 0, endRadius: 12))
        for k in 0..<3 {
            let a = time * 3 + Double(k) * 2 * .pi / 3
            var arc = Path()
            arc.addArc(center: portal.entry, radius: 8, startAngle: .radians(a), endAngle: .radians(a + 1.2), clockwise: false)
            context.stroke(arc, with: .color(color.toyShade(0.2).opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        context.stroke(circle(portal.entry, 14), with: .color(color), lineWidth: 4)
        // Exit: a raised ring that pulses when the ball comes out.
        var pulse: CGFloat = 0
        if let hit = engine.portalHit, hit.index == index {
            let age = time - hit.at
            if age < 0.4 { pulse = CGFloat(1 - age / 0.4) * 5 }
        }
        let r = 13 + pulse
        context.stroke(circle(portal.exit, r).offsetBy(dx: 0, dy: 3), with: .color(color.toyShade(-0.25)), lineWidth: 5)
        context.stroke(circle(portal.exit, r), with: .color(color), lineWidth: 5)
        context.fill(circle(portal.exit, r - 5), with: .color(color.opacity(0.18)))
        // A dashed thread from entry to exit, so the pair reads as one tunnel.
        var thread = Path(); thread.move(to: portal.entry); thread.addLine(to: portal.exit)
        context.stroke(thread, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
    }

    private func drawBumper(_ context: inout GraphicsContext, _ b: GolfBumper, index: Int, time: Double) {
        var r = b.radius
        if let hit = engine.bumperHit, hit.index == index {
            let age = time - hit.at
            if age < 0.25 { r *= 1 + 0.18 * CGFloat(1 - age / 0.25) }
        }
        let c = b.center
        context.fill(circle(CGPoint(x: c.x, y: c.y + 7), r), with: .color(.black.opacity(0.12)))
        context.fill(circle(CGPoint(x: c.x, y: c.y + 5), r), with: .color(C.bumper.toyShade(-0.24)))
        context.fill(circle(c, r), with: .radialGradient(Gradient(colors: [C.bumper.toyShade(0.12), C.bumper]),
                                                         center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35),
                                                         startRadius: 0, endRadius: r * 1.3))
        context.stroke(circle(c, r * 0.58), with: .color(.white.opacity(0.55)), lineWidth: 2.5)
        context.fill(circle(c, r * 0.2), with: .color(.white.opacity(0.7)))
    }

    private func drawSpinner(_ context: inout GraphicsContext, _ s: GolfSpinner, time: Double) {
        let seg = s.segment(at: time)
        drawRail(&context, Path { $0.move(to: seg.a); $0.addLine(to: seg.b) }, C.spinner)
        context.fill(circle(CGPoint(x: s.center.x, y: s.center.y + 4), 9), with: .color(C.rail.toyShade(-0.22)))
        context.fill(circle(s.center, 9), with: .color(C.rail))
        context.fill(circle(s.center, 3), with: .color(C.spinner.toyShade(-0.2)))
    }

    private func drawAim(_ context: inout GraphicsContext) {
        guard let aim = engine.aim, aim.length > 0.01 else { return }
        let ball = engine.ball
        let power = aim.length
        let count = engine.preview.count
        for (i, p) in engine.preview.enumerated() {
            let t = CGFloat(i) / CGFloat(max(1, count))
            context.fill(circle(p, 3.2 - 1.6 * t), with: .color(.white.opacity(0.95 - 0.6 * Double(t))))
        }
        // The rubber band behind the ball, and a power ring around it.
        let heading = aim * (1 / power)
        let back = ball - heading * (12 + 34 * power)
        var band = Path(); band.move(to: ball); band.addLine(to: back)
        context.stroke(band, with: .color(C.ink.opacity(0.22)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        context.fill(circle(back, 5), with: .color(C.ink.opacity(0.22)))
        let tint = Color(hue: 0.33 * (1 - Double(power)) , saturation: 0.7, brightness: 0.95)
        var ring = Path()
        let start = atan2(heading.dy, heading.dx) - Double(power) * .pi
        ring.addArc(center: ball, radius: 15, startAngle: .radians(start), endAngle: .radians(start + Double(power) * 2 * .pi), clockwise: false)
        context.stroke(circle(ball, 15), with: .color(.white.opacity(0.25)), lineWidth: 4)
        context.stroke(ring, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    private func drawBall(_ context: inout GraphicsContext) {
        var p = engine.ball
        var r = GolfPhysics.ballRadius
        var ball = context
        if let sunkAt = engine.sunkAt {
            let t = min(1, (engine.time - sunkAt) / 0.3)
            r *= CGFloat(1 - 0.55 * t)
            p = engine.hole.cup
            ball.opacity = 1 - t
        }
        ToyCanvas.bead(&ball, p, r, C.ball)
        ball.fill(circle(CGPoint(x: p.x - r * 0.3, y: p.y - r * 0.35), r * 0.28), with: .color(.white.opacity(0.8)))
    }

    private func drawSplash(_ context: inout GraphicsContext, time: Double) {
        guard let splash = engine.splash else { return }
        let age = time - splash.at
        guard age < 0.8 else { return }
        for k in 0..<2 {
            let a = age - Double(k) * 0.15
            guard a > 0 else { continue }
            let r = 6 + CGFloat(a) * 40
            context.stroke(circle(splash.p, r), with: .color(.white.opacity(0.7 * (1 - a / 0.8))), lineWidth: 2.5)
        }
    }

    // MARK: Newer pieces

    /// Ice: pale and glassy, with a few fixed glints.
    private func drawIce(_ context: inout GraphicsContext, _ z: GolfZone) {
        let path = zonePath(z)
        context.fill(path, with: .color(C.ice.toyShade(-0.14)))
        context.drawLayer { layer in
            layer.clip(to: path)
            layer.fill(path.offsetBy(dx: 0, dy: 3), with: .linearGradient(Gradient(colors: [C.ice.toyShade(0.06), C.ice]),
                                                                          startPoint: CGPoint(x: z.rect.minX, y: z.rect.minY),
                                                                          endPoint: CGPoint(x: z.rect.maxX, y: z.rect.maxY)))
            var x = z.rect.minX - z.rect.height
            var k = 0
            while x < z.rect.maxX {
                var glint = Path()
                let w: CGFloat = k.isMultiple(of: 2) ? 7 : 3
                glint.addLines([CGPoint(x: x, y: z.rect.maxY), CGPoint(x: x + w, y: z.rect.maxY),
                                CGPoint(x: x + w + z.rect.height, y: z.rect.minY), CGPoint(x: x + z.rect.height, y: z.rect.minY)])
                glint.closeSubpath()
                layer.fill(glint, with: .color(.white.opacity(0.28)))
                x += k.isMultiple(of: 2) ? 12 : 34
                k += 1
            }
        }
    }

    /// A raised arrow pad with chevrons running the way it pushes.
    private func drawBooster(_ context: inout GraphicsContext, _ b: GolfBooster, time: Double) {
        let r = GolfPhysics.boosterRadius
        ToyCanvas.clay(&context, CGRect(x: b.center.x - r, y: b.center.y - r, width: 2 * r, height: 2 * r), C.booster, radius: 9, lip: 3)
        var pad = context
        pad.translateBy(x: b.center.x, y: b.center.y)
        pad.rotate(by: .radians(Double(atan2(b.dir.dy, b.dir.dx))))
        pad.clip(to: Path(roundedRect: CGRect(x: -r + 2, y: -r + 2, width: 2 * r - 4, height: 2 * r - 4), cornerRadius: 7))
        let shift = CGFloat((time * 30).truncatingRemainder(dividingBy: 12))
        for k in -2...1 {
            let x = CGFloat(k) * 12 + shift
            var mark = Path()
            mark.move(to: CGPoint(x: x - 4, y: -7)); mark.addLine(to: CGPoint(x: x + 3, y: 0)); mark.addLine(to: CGPoint(x: x - 4, y: 7))
            pad.stroke(mark, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    /// Two matching rings with a turning swirl; either one sends the ball to the other.
    private func drawTeleport(_ context: inout GraphicsContext, _ t: GolfTeleport, index: Int, time: Double) {
        let color = C.teleport(index)
        var thread = Path(); thread.move(to: t.a); thread.addLine(to: t.b)
        context.stroke(thread, with: .color(color.opacity(0.25)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
        var pulse: CGFloat = 0
        if let hit = engine.teleportHit, hit.index == index {
            let age = time - hit.at
            if age < 0.45 { pulse = CGFloat(1 - age / 0.45) * 6 }
        }
        for (k, c) in [t.a, t.b].enumerated() {
            context.fill(circle(CGPoint(x: c.x, y: c.y + 3), 15 + pulse), with: .color(color.toyShade(-0.28)))
            context.fill(circle(c, 15 + pulse), with: .color(color))
            context.fill(circle(c, 10.5), with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95), color.toyShade(0.15)]),
                                                                center: c, startRadius: 0, endRadius: 10.5))
            for j in 0..<2 {
                let a = time * (k == 0 ? 3.2 : -3.2) + Double(j) * .pi
                var arc = Path()
                arc.addArc(center: c, radius: 7, startAngle: .radians(a), endAngle: .radians(a + 1.6), clockwise: false)
                context.stroke(arc, with: .color(color.toyShade(-0.2)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
    }

    /// The button on the turf: raised until the ball rolls over it.
    private func drawButton(_ context: inout GraphicsContext, _ g: GolfGate, index: Int, time: Double) {
        let pressed = engine.opened & (1 << UInt32(index)) != 0
        let r = GolfPhysics.buttonRadius
        let c = g.button
        context.fill(circle(c, r + 3), with: .color(turf.toyShade(-0.12)))
        let lip: CGFloat = pressed ? 1 : 4
        context.fill(circle(CGPoint(x: c.x, y: c.y + lip), r), with: .color(C.gate(index).toyShade(-0.25)))
        context.fill(circle(c, r), with: .color(pressed ? C.gate(index).toyShade(-0.1) : C.gate(index)))
        context.fill(circle(c, r * 0.4), with: .color(.white.opacity(pressed ? 0.35 : 0.75)))
    }

    /// A gate rail in its button's colour; once open it sinks into the turf.
    private func drawGate(_ context: inout GraphicsContext, _ g: GolfGate, index: Int, time: Double) {
        let color = C.gate(index)
        var path = Path(); path.move(to: g.gate.a); path.addLine(to: g.gate.b)
        if let at = engine.gateOpenedAt[index] {
            let t = min(1, (time - at) / 0.35)
            if t < 1 {
                var sinking = context
                sinking.opacity = 1 - t
                drawRail(&sinking, path.offsetBy(dx: 0, dy: CGFloat(t) * 5), color)
            }
            context.stroke(path, with: .color(color.opacity(0.35)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 7]))
            return
        }
        drawRail(&context, path, color)
        // Stripes, so a gate reads apart from a fixed rail.
        context.stroke(path, with: .color(.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: GolfPhysics.railRadius * 2 - 4, lineCap: .butt, dash: [5, 9]))
    }

    /// A springy rail: a yellow coil that wobbles when the ball is kicked off it.
    private func drawSpring(_ context: inout GraphicsContext, _ s: GolfSeg, index: Int, time: Double) {
        var wobble: CGFloat = 0
        if let hit = engine.springHit, hit.index == index {
            let age = time - hit.at
            if age < 0.4 { wobble = CGFloat(sin(age * 50) * (1 - age / 0.4)) * 3 }
        }
        let dx = s.b.x - s.a.x, dy = s.b.y - s.a.y
        let length = max(1, hypot(dx, dy))
        let n = CGVector(dx: -dy / length * wobble, dy: dx / length * wobble)
        var path = Path(); path.move(to: s.a); path.addQuadCurve(to: s.b, control: CGPoint(x: (s.a.x + s.b.x) / 2 + n.dx * 2, y: (s.a.y + s.b.y) / 2 + n.dy * 2))
        drawRail(&context, path, C.spring)
        context.stroke(path, with: .color(C.spring.toyShade(-0.3)),
                       style: StrokeStyle(lineWidth: GolfPhysics.railRadius * 2 - 3, lineCap: .butt, dash: [2, 5]))
    }

    /// A flipper on a round pivot.
    private func drawPaddle(_ context: inout GraphicsContext, _ p: GolfPaddle, time: Double) {
        let seg = p.segment(at: time)
        drawRail(&context, Path { $0.move(to: seg.a); $0.addLine(to: seg.b) }, C.paddle)
        context.fill(circle(CGPoint(x: p.pivot.x, y: p.pivot.y + 4), 9), with: .color(C.rail.toyShade(-0.22)))
        context.fill(circle(p.pivot, 9), with: .color(C.rail))
        context.fill(circle(p.pivot, 3), with: .color(C.paddle.toyShade(-0.2)))
    }
}

// MARK: - Palette

enum ToyMiniGolf {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.89, 0.95, 0.98), dark: (0.10, 0.14, 0.17)),
        backdropBottom: .dynamic(light: (0.80, 0.90, 0.88), dark: (0.05, 0.08, 0.09)),
        tray: .dynamic(light: (0.72, 0.84, 0.80), dark: (0.20, 0.27, 0.27)),
        socket: .dynamic(light: (0.84, 0.92, 0.90), dark: (0.13, 0.18, 0.19)),
        ink: .dynamic(light: (0.16, 0.33, 0.28), dark: (0.93, 0.97, 0.95)),
        deboss: .dynamic(light: (0.84, 0.92, 0.92), dark: (0.14, 0.19, 0.21)),
        debossRim: .dynamic(light: (1, 1, 1), dark: (0.02, 0.03, 0.04)),
        card: .dynamic(light: (1.0, 1.0, 0.98), dark: (0.27, 0.33, 0.33)),
        accent: .dynamic(light: (0.93, 0.42, 0.46), dark: (0.98, 0.52, 0.55)))

    static let hint = "Pull back from the ball, aim and let go. Sink it in as few strokes as you can."
    static let starGold = Color(red: 0.98, green: 0.76, blue: 0.22)

    static let turf = Color.dynamic(light: (0.55, 0.79, 0.46), dark: (0.30, 0.52, 0.32))
    static let turfWall = Color.dynamic(light: (0.38, 0.58, 0.33), dark: (0.17, 0.32, 0.19))

    /// Each world has its own turf: meadow, frost, dusk, autumn, candy, brass and twilight.
    private static let turfs: [(Color, Color)] = [
        (turf, turfWall),
        (.dynamic(light: (0.56, 0.80, 0.72), dark: (0.27, 0.48, 0.45)), .dynamic(light: (0.38, 0.60, 0.56), dark: (0.15, 0.30, 0.29))),
        (.dynamic(light: (0.62, 0.70, 0.90), dark: (0.33, 0.38, 0.58)), .dynamic(light: (0.44, 0.50, 0.72), dark: (0.20, 0.23, 0.38))),
        (.dynamic(light: (0.74, 0.78, 0.42), dark: (0.45, 0.48, 0.24)), .dynamic(light: (0.56, 0.58, 0.28), dark: (0.28, 0.30, 0.14))),
        (.dynamic(light: (0.92, 0.66, 0.74), dark: (0.58, 0.36, 0.44)), .dynamic(light: (0.74, 0.47, 0.56), dark: (0.38, 0.21, 0.28))),
        (.dynamic(light: (0.80, 0.70, 0.52), dark: (0.50, 0.42, 0.30)), .dynamic(light: (0.62, 0.52, 0.36), dark: (0.32, 0.26, 0.17))),
        (.dynamic(light: (0.47, 0.70, 0.62), dark: (0.22, 0.40, 0.40)), .dynamic(light: (0.31, 0.50, 0.45), dark: (0.11, 0.24, 0.25))),
    ]
    static func turf(theme: Int) -> Color { turfs[max(0, theme) % turfs.count].0 }
    static func turfWall(theme: Int) -> Color { turfs[max(0, theme) % turfs.count].1 }

    static let ice = Color.dynamic(light: (0.86, 0.95, 1.0), dark: (0.62, 0.76, 0.86))
    static let booster = Color.dynamic(light: (0.98, 0.62, 0.30), dark: (0.92, 0.55, 0.26))
    static let spring = Color.dynamic(light: (0.99, 0.82, 0.30), dark: (0.92, 0.74, 0.26))
    static let paddle = Color.dynamic(light: (0.40, 0.72, 0.95), dark: (0.38, 0.64, 0.88))
    private static let teleports: [Color] = [
        .dynamic(light: (0.25, 0.80, 0.80), dark: (0.28, 0.74, 0.76)),
        .dynamic(light: (0.98, 0.58, 0.20), dark: (0.94, 0.56, 0.24)),
        .dynamic(light: (0.92, 0.42, 0.78), dark: (0.88, 0.44, 0.76)),
    ]
    static func teleport(_ i: Int) -> Color { teleports[i % teleports.count] }
    private static let gates: [Color] = [
        .dynamic(light: (0.95, 0.40, 0.40), dark: (0.92, 0.42, 0.42)),
        .dynamic(light: (0.30, 0.62, 0.95), dark: (0.36, 0.60, 0.92)),
        .dynamic(light: (0.60, 0.45, 0.90), dark: (0.62, 0.50, 0.92)),
    ]
    static func gate(_ i: Int) -> Color { gates[i % gates.count] }
    static let rail = Color.dynamic(light: (0.99, 0.88, 0.70), dark: (0.80, 0.68, 0.52))
    static let mover = Color.dynamic(light: (0.94, 0.55, 0.70), dark: (0.86, 0.50, 0.65))
    static let spinner = Color.dynamic(light: (0.67, 0.58, 0.92), dark: (0.62, 0.54, 0.88))
    static let bumper = Color.dynamic(light: (0.96, 0.50, 0.47), dark: (0.90, 0.46, 0.44))
    static let portal = Color.dynamic(light: (0.58, 0.44, 0.92), dark: (0.66, 0.54, 0.96))
    static let sand = Color.dynamic(light: (0.97, 0.87, 0.62), dark: (0.66, 0.57, 0.40))
    static let water = Color.dynamic(light: (0.46, 0.73, 0.96), dark: (0.24, 0.45, 0.66))
    static let flag = Color.dynamic(light: (0.95, 0.38, 0.44), dark: (0.95, 0.44, 0.48))
    static let pole = Color.dynamic(light: (1, 1, 0.98), dark: (0.92, 0.92, 0.90))
    static let ball = Color(red: 1, green: 0.99, blue: 0.96)
    static let ink = palette.ink
}

/// The top of the last hole with a shot being aimed, for the Home preview.
struct MiniGolfShowcase: View {
    let engine: MiniGolfEngine

    var body: some View {
        let palette = ToyMiniGolf.palette
        let side: CGFloat = 300
        let scale = side / 320
        ZStack {
            palette.backdrop
            MiniGolfCourseView(engine: engine)
                .frame(width: side, height: 460 * scale)
                .offset(y: -28 * scale)
                .frame(width: side, height: side, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .toyTray(palette.tray, cornerRadius: 24, padding: 6)
        }
        .environment(\.toyStyle, palette.style)
        .frame(width: 360, height: 360)
    }
}
