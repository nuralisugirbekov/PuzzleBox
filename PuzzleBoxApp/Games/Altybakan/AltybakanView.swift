import SwiftUI
import Observation

// Алтыбақан — the traditional six-legged Kazakh swing. Tap as the swing passes the
// glowing spot at the bottom to pump it higher, and ring the bells hung along the arc.

@MainActor
@Observable
final class AltybakanEngine: GameEngine {
    /// Bells, in degrees from the vertical. After the last one the top bell can be rung again and again.
    static let bellAngles: [Double] = [25, 40, 55, 70, 85]
    static let maxLives = 3
    private static let gravity = 9.0       // g / L: a calm, two-second swing
    private static let damping = 0.10
    private static let cap = 1.5           // rad, a little over 85°
    private static let step = 1.0 / 240

    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    private(set) var theta = 0.15
    private(set) var omega = 0.0
    private(set) var lives = AltybakanEngine.maxLives
    private(set) var streak = 0
    private(set) var bellsRung = 0
    private(set) var armed = true
    private(set) var amplitude = 0.15
    private(set) var fx = ArcadeFX()
    private(set) var clock = 0.0
    /// Bumped when a bell rings, to swing it.
    private(set) var bellFlash = 0
    private(set) var lastRungSide: Double = 1
    var active = false

    private var accumulator = 0.0
    private var lastExtremeAt = 0.0
    private var lastRingAt = -10.0

    var multiplier: Int { min(5, 1 + streak / 3) }
    /// Half-width of the valid window at the bottom, in radians; it widens with speed so high swings stay playable.
    var zone: Double { 0.22 + 0.20 * min(1, amplitude / 1.2) }
    var perfectZone: Double { 0.09 + 0.06 * min(1, amplitude / 1.2) }
    var nextBellDegrees: Double { Self.bellAngles[min(bellsRung, Self.bellAngles.count - 1)] }

    init() { restart() }

    func restart() {
        state = .playing; score = 0; started = false
        theta = 0.15; omega = 0; lives = Self.maxLives; streak = 0; bellsRung = 0
        armed = true; amplitude = 0.15; clock = 0; accumulator = 0; lastExtremeAt = 0; lastRingAt = -10
        fx.reset()
    }

    // MARK: Input

    func tap() {
        guard active, state == .playing else { return }
        if !started { started = true; return }
        guard armed else { return }
        armed = false
        let offset = abs(theta)
        let towardCentre = theta * omega < 0
        guard offset < zone, towardCentre else { miss(); return }
        let foot = CGPoint(x: 160 + 135 * sin(theta), y: 150 + 135 * cos(theta))
        if offset < perfectZone {
            omega = (omega < 0 ? -1 : 1) * (abs(omega) * 1.10 + 0.05)
            streak += 1
            let points = 10 * multiplier
            score += points
            fx.burst(at: foot, color: .yellow, count: 12, speed: 110, gravity: 60, size: 3, life: 0.5)
            fx.popup(streak > 2 ? "+\(points) ×\(multiplier)" : L10n.text("Perfect!"), at: CGPoint(x: foot.x, y: foot.y - 26), color: .yellow, size: 17)
            Haptics.success(); SoundFX.play(.coin)
        } else {
            omega = (omega < 0 ? -1 : 1) * (abs(omega) * 1.06 + 0.04)
            streak = max(0, streak - 1)
            score += 5
            fx.popup("+5", at: CGPoint(x: foot.x, y: foot.y - 26), color: .white, size: 14)
            Haptics.tap(); SoundFX.play(.point)
        }
    }

    private func miss() {
        lives -= 1; streak = 0
        omega *= 0.82
        fx.kick(4); fx.flash(.red, 0.18)
        fx.popup(L10n.text("Too early or late!"), at: CGPoint(x: 160, y: 330), color: .white, size: 15)
        Haptics.error(); SoundFX.play(.wrong)
        if lives <= 0 { finish() }
    }

    private func finish() {
        fx.burst(at: CGPoint(x: 160, y: 250), color: .orange, count: 24, speed: 160, gravity: 200, size: 3.5, life: 0.7)
        state = .gameOver(won: bellsRung >= 3)
    }

    // MARK: Simulation

    func advance(_ dt: Double) {
        guard active, state == .playing else { return }
        let elapsed = min(0.1, max(0, dt))
        fx.update(CGFloat(elapsed))
        guard started else { clock += elapsed; return }
        accumulator += elapsed
        while accumulator >= Self.step, state == .playing {
            accumulator -= Self.step
            integrate(Self.step)
        }
        clock += elapsed
    }

    private func integrate(_ dt: Double) {
        let previousOmega = omega
        omega += (-Self.gravity * sin(theta) - Self.damping * omega) * dt
        theta += omega * dt
        // The chains never go slack over the top: the swing simply stops at the cap.
        if abs(theta) > Self.cap { theta = theta < 0 ? -Self.cap : Self.cap; omega = 0 }
        if previousOmega * omega <= 0 && abs(previousOmega) + abs(omega) > 0 { reachedExtreme() }
    }

    /// Every turning point re-arms the next tap and checks the bells.
    private func reachedExtreme() {
        armed = true
        amplitude = abs(theta)
        lastRungSide = theta < 0 ? -1 : 1
        let degrees = abs(theta) * 180 / .pi
        if degrees >= nextBellDegrees, clock - lastRingAt > 1.2 {
            ringBell()
        } else if amplitude < 0.05, clock > 3 {
            // The swing has died down.
            state = .gameOver(won: bellsRung >= 3)
        }
        lastExtremeAt = clock
    }

    private func ringBell() {
        lastRingAt = clock
        let points = 100 * (min(bellsRung, Self.bellAngles.count - 1) + 1)
        bellsRung += 1; bellFlash += 1
        score += points
        let a = lastRungSide * nextBellAngleRadians(forRung: bellsRung - 1)
        let at = CGPoint(x: 160 + 150 * sin(a), y: 150 + 150 * cos(a))
        fx.burst(at: at, color: .yellow, count: 22, speed: 150, gravity: 80, size: 3.5, life: 0.8)
        fx.popup("+\(points)", at: CGPoint(x: at.x, y: at.y - 24), color: .yellow, size: 22)
        fx.flash(.yellow, 0.15)
        Haptics.heavy(); SoundFX.play(.bell)
    }

    private func nextBellAngleRadians(forRung index: Int) -> Double {
        Self.bellAngles[min(index, Self.bellAngles.count - 1)] * .pi / 180
    }
}

struct AltybakanView: View {
    @State private var engine = AltybakanEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pivot = CGPoint(x: 160, y: 150)
    private let ropeLength: CGFloat = 135

    var body: some View {
        GameContainerView(gameID: .altybakan, engine: engine,
                          resultSummary: L10n.format("Bells: %d", engine.bellsRung)) {
            VStack(spacing: 10) {
                hud
                GeometryReader { geo in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 460)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        draw(&context)
                        engine.fx.draw(in: &context)
                        engine.fx.drawFlash(in: &context, bounds: CGRect(x: -20, y: -20, width: 360, height: 500), reduceMotion: reduceMotion)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        if !engine.started {
                            VStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill").font(.largeTitle)
                                Text(L10n.text("Tap to start")).font(.headline)
                            }
                            .padding(22).background(GameTheme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { engine.tap() }
                }
                .aspectRatio(320.0 / 460, contentMode: .fit)
                .frame(maxWidth: 380, maxHeight: 460)
                Text(L10n.text("Tap as the swing passes the glowing spot to pump it higher. Reach the bells on both sides. Three mistimed taps end the ride."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
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
            Label("\(engine.bellsRung)", systemImage: "bell.fill").foregroundStyle(.yellow)
            Text(L10n.format("Next bell: %d°", Int(engine.nextBellDegrees))).foregroundStyle(GameTheme.textSecondary)
            if engine.multiplier > 1 {
                Label { Text(verbatim: "×\(engine.multiplier)") } icon: { Image(systemName: "flame.fill") }.foregroundStyle(.orange)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<AltybakanEngine.maxLives, id: \.self) { i in
                    Image(systemName: i < engine.lives ? "heart.fill" : "heart")
                        .foregroundStyle(i < engine.lives ? Color.pink : GameTheme.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(GameTheme.accent)
        .animation(.snappy, value: engine.multiplier)
    }

    // MARK: Drawing

    private func seatPosition(_ angle: Double) -> CGPoint {
        CGPoint(x: pivot.x + ropeLength * CGFloat(sin(angle)), y: pivot.y + ropeLength * CGFloat(cos(angle)))
    }

    private func draw(_ context: inout GraphicsContext) {
        let wood = Color(red: 0.55, green: 0.33, blue: 0.17), woodDark = Color(red: 0.38, green: 0.22, blue: 0.1)
        // Morning steppe sky.
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.62, blue: 0.92), Color(red: 1, green: 0.84, blue: 0.62)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 380)))
        context.fill(Path(ellipseIn: CGRect(x: 232, y: 40, width: 44, height: 44)), with: .color(Color(red: 1, green: 0.95, blue: 0.7)))
        for (x, y, w) in [(30.0, 60.0, 70.0), (150.0, 30.0, 54.0), (230.0, 110.0, 64.0)] {
            context.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: 16), cornerRadius: 8), with: .color(.white.opacity(0.55)))
            context.fill(Path(ellipseIn: CGRect(x: x + w * 0.2, y: y - 9, width: w * 0.4, height: 22)), with: .color(.white.opacity(0.55)))
        }
        // Distant hills, a yurt, grass.
        var hills = Path(); hills.move(to: CGPoint(x: 0, y: 340))
        hills.addQuadCurve(to: CGPoint(x: 140, y: 330), control: CGPoint(x: 60, y: 285))
        hills.addQuadCurve(to: CGPoint(x: 320, y: 335), control: CGPoint(x: 240, y: 290))
        hills.addLine(to: CGPoint(x: 320, y: 460)); hills.addLine(to: CGPoint(x: 0, y: 460)); hills.closeSubpath()
        context.fill(hills, with: .color(Color(red: 0.55, green: 0.7, blue: 0.4)))
        yurt(&context, at: CGPoint(x: 262, y: 345))
        context.fill(Path(CGRect(x: 0, y: 358, width: 320, height: 102)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.42, green: 0.64, blue: 0.3), Color(red: 0.3, green: 0.5, blue: 0.22)]),
                                           startPoint: CGPoint(x: 0, y: 358), endPoint: CGPoint(x: 0, y: 460)))
        for k in 0..<26 {
            let x = CGFloat((k * 53) % 320), y = 366 + CGFloat((k * 31) % 84)
            var tuft = Path(); tuft.move(to: CGPoint(x: x, y: y)); tuft.addLine(to: CGPoint(x: x - 2, y: y - 6)); tuft.move(to: CGPoint(x: x, y: y)); tuft.addLine(to: CGPoint(x: x + 2, y: y - 7))
            context.stroke(tuft, with: .color(Color(red: 0.2, green: 0.4, blue: 0.15).opacity(0.7)), lineWidth: 1.3)
        }

        // Bells along the arc on both sides.
        let radius: CGFloat = 150
        var arc = Path()
        arc.addArc(center: pivot, radius: radius, startAngle: .degrees(90 - 88), endAngle: .degrees(90 + 88), clockwise: false)
        context.stroke(arc, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 2, dash: [3, 7]))
        for (index, degrees) in AltybakanEngine.bellAngles.enumerated() {
            let rung = index < engine.bellsRung
            let isNext = index == min(engine.bellsRung, AltybakanEngine.bellAngles.count - 1)
            for side in [-1.0, 1.0] {
                let a = side * degrees * .pi / 180
                let p = CGPoint(x: pivot.x + radius * CGFloat(sin(a)), y: pivot.y + radius * CGFloat(cos(a)))
                drawBell(&context, at: p, rung: rung, next: isNext, swinging: index == engine.bellsRung - 1 && side == engine.lastRungSide)
            }
        }

        // The A-frame: three pairs of legs seen from the side, a top beam and braces.
        var legs = Path()
        legs.move(to: CGPoint(x: pivot.x, y: pivot.y - 8)); legs.addLine(to: CGPoint(x: 58, y: 372))
        legs.move(to: CGPoint(x: pivot.x, y: pivot.y - 8)); legs.addLine(to: CGPoint(x: 262, y: 372))
        context.stroke(legs, with: .color(woodDark.opacity(0.55)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        context.stroke(legs, with: .color(wood.opacity(0.75)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        var brace = Path(); brace.move(to: CGPoint(x: 100, y: 275)); brace.addLine(to: CGPoint(x: 220, y: 275))
        context.stroke(brace, with: .color(wood.opacity(0.6)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.fill(Path(ellipseIn: CGRect(x: pivot.x - 9, y: pivot.y - 15, width: 18, height: 18)), with: .color(woodDark))
        context.fill(Path(ellipseIn: CGRect(x: pivot.x - 4, y: pivot.y - 10, width: 8, height: 8)), with: .color(.yellow.opacity(0.8)))

        // Glowing sweet spot on the ground arc, only while a tap would count.
        let zone = engine.zone, perfect = engine.perfectZone
        let glowing = engine.armed && engine.started
        for (width, color, alpha) in [(zone, Color.white, 0.18), (perfect, Color.yellow, 0.5)] {
            var spot = Path()
            spot.addArc(center: pivot, radius: ropeLength + 6, startAngle: .radians(.pi / 2 - width), endAngle: .radians(.pi / 2 + width), clockwise: false)
            context.stroke(spot, with: .color(color.opacity(glowing ? alpha : alpha * 0.4)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        }

        // The swing itself.
        let seat = seatPosition(engine.theta)
        var ropes = Path()
        ropes.move(to: CGPoint(x: pivot.x - 5, y: pivot.y)); ropes.addLine(to: CGPoint(x: seat.x - 14, y: seat.y))
        ropes.move(to: CGPoint(x: pivot.x + 5, y: pivot.y)); ropes.addLine(to: CGPoint(x: seat.x + 14, y: seat.y))
        var seatLayer = context
        seatLayer.stroke(ropes, with: .color(Color(red: 0.88, green: 0.8, blue: 0.62)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        seatLayer.translateBy(x: seat.x, y: seat.y)
        seatLayer.rotate(by: .radians(-engine.theta))
        riders(&seatLayer)
        seatLayer.fill(Path(roundedRect: CGRect(x: -22, y: -2, width: 44, height: 7), cornerRadius: 3), with: .color(wood))
        seatLayer.fill(Path(roundedRect: CGRect(x: -22, y: -2, width: 44, height: 2.5), cornerRadius: 1), with: .color(.white.opacity(0.35)))
        // Colourful ornamental stripe on the seat.
        for (i, c) in [Color.red, .yellow, .cyan, .red, .yellow].enumerated() {
            seatLayer.fill(Path(CGRect(x: -14 + CGFloat(i) * 7, y: 1.5, width: 4, height: 2.5)), with: .color(c))
        }
    }

    private func riders(_ layer: inout GraphicsContext) {
        // Two children sitting side by side: a boy and a girl in festive chapans.
        for (x, shirt, hat, hair) in [(-9.0, Color(red: 0.2, green: 0.55, blue: 0.9), Color(red: 0.15, green: 0.3, blue: 0.7), Color(red: 0.1, green: 0.07, blue: 0.05)),
                                      (9.0, Color(red: 0.9, green: 0.25, blue: 0.4), Color(red: 0.95, green: 0.75, blue: 0.2), Color(red: 0.25, green: 0.12, blue: 0.06))] {
            layer.fill(Path(roundedRect: CGRect(x: x - 7, y: -22, width: 14, height: 22), cornerRadius: 5), with: .color(shirt))
            layer.fill(Path(roundedRect: CGRect(x: x - 7, y: -10, width: 14, height: 3), cornerRadius: 1), with: .color(.white.opacity(0.7)))
            layer.fill(Path(ellipseIn: CGRect(x: x - 6.5, y: -35, width: 13, height: 13)), with: .color(Color(red: 0.97, green: 0.8, blue: 0.64)))
            layer.fill(Path(ellipseIn: CGRect(x: x - 7, y: -37, width: 14, height: 9)), with: .color(hair))
            layer.fill(Path(roundedRect: CGRect(x: x - 5.5, y: -41, width: 11, height: 6), cornerRadius: 3), with: .color(hat))
            layer.fill(Path(ellipseIn: CGRect(x: x - 2.5, y: -31, width: 2, height: 2)), with: .color(.black))
            layer.fill(Path(ellipseIn: CGRect(x: x + 1, y: -31, width: 2, height: 2)), with: .color(.black))
            // Legs hanging over the edge.
            layer.fill(Path(roundedRect: CGRect(x: x - 4, y: -1, width: 3.5, height: 9), cornerRadius: 1.5), with: .color(shirt.opacity(0.8)))
            layer.fill(Path(roundedRect: CGRect(x: x + 0.5, y: -1, width: 3.5, height: 9), cornerRadius: 1.5), with: .color(shirt.opacity(0.8)))
        }
    }

    private func drawBell(_ context: inout GraphicsContext, at p: CGPoint, rung: Bool, next: Bool, swinging: Bool) {
        var layer = context
        layer.translateBy(x: p.x, y: p.y)
        if swinging && !reduceMotion {
            layer.rotate(by: .radians(sin(engine.clock * 22) * 0.35 * max(0, 1 - (engine.clock - 0) * 0)))
        }
        let scale: CGFloat = next ? 1.15 : 0.85
        layer.scaleBy(x: scale, y: scale)
        if next { layer.fill(Path(ellipseIn: CGRect(x: -17, y: -17, width: 34, height: 34)), with: .color(.yellow.opacity(0.28))) }
        var body = Path()
        body.move(to: CGPoint(x: -9, y: 7)); body.addQuadCurve(to: CGPoint(x: -6, y: -6), control: CGPoint(x: -9, y: -3))
        body.addQuadCurve(to: CGPoint(x: 6, y: -6), control: CGPoint(x: 0, y: -13))
        body.addQuadCurve(to: CGPoint(x: 9, y: 7), control: CGPoint(x: 9, y: -3)); body.closeSubpath()
        let gold = rung ? Color.white.opacity(0.45) : Color(red: 1, green: 0.78, blue: 0.2)
        layer.fill(body, with: .linearGradient(Gradient(colors: [gold, gold.opacity(0.7)]), startPoint: CGPoint(x: -9, y: -10), endPoint: CGPoint(x: 9, y: 8)))
        layer.stroke(body, with: .color(.black.opacity(0.25)), lineWidth: 1)
        layer.fill(Path(ellipseIn: CGRect(x: -2.5, y: 6, width: 5, height: 5)), with: .color(rung ? .gray : Color(red: 0.7, green: 0.45, blue: 0.1)))
        if rung { layer.draw(Text(Image(systemName: "checkmark")).font(.system(size: 8, weight: .black)).foregroundStyle(.green), at: CGPoint(x: 0, y: -1)) }
    }

    private func yurt(_ context: inout GraphicsContext, at p: CGPoint) {
        var wall = Path(); wall.addRoundedRect(in: CGRect(x: p.x - 28, y: p.y - 16, width: 56, height: 28), cornerSize: CGSize(width: 4, height: 4))
        context.fill(wall, with: .color(Color(red: 0.95, green: 0.92, blue: 0.84)))
        var dome = Path(); dome.move(to: CGPoint(x: p.x - 30, y: p.y - 14)); dome.addQuadCurve(to: CGPoint(x: p.x + 30, y: p.y - 14), control: CGPoint(x: p.x, y: p.y - 48))
        dome.closeSubpath()
        context.fill(dome, with: .color(Color(red: 0.98, green: 0.96, blue: 0.9)))
        context.stroke(dome, with: .color(Color(red: 0.2, green: 0.5, blue: 0.65)), lineWidth: 2)
        context.fill(Path(roundedRect: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 18), cornerRadius: 3), with: .color(Color(red: 0.2, green: 0.5, blue: 0.65)))
        var band = Path(); band.move(to: CGPoint(x: p.x - 28, y: p.y - 12)); band.addLine(to: CGPoint(x: p.x + 28, y: p.y - 12))
        context.stroke(band, with: .color(Color(red: 0.85, green: 0.3, blue: 0.2)), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
    }
}
