import SwiftUI
import Observation

// Көкпар — the traditional horseback game. Here: ride up the field, pick up the
// "серке" (goat carcass), swerve around rival riders and drop it in the kazan.
// Swipe left and right to change lanes.

struct KokparRider: Identifiable {
    let id: Int
    var x: CGFloat
    /// World distance of the rider along the field.
    var d: CGFloat
    var vx: CGFloat = 0
    let chaser: Bool
    let tint: Int
    var passed = false
}

@MainActor
@Observable
final class KokparEngine: GameEngine {
    static let lanes = 5
    static let laneX: [CGFloat] = [40, 100, 160, 220, 280]
    static let playerScreenY: CGFloat = 372
    static let maxLives = 3

    var state: GameState = .playing
    private var bonus = 0
    var score: Int { Int(distance / 12) + bonus }
    private(set) var started = false
    private(set) var lane = 2
    private(set) var px: CGFloat = 160
    private(set) var distance: CGFloat = 0
    private(set) var riders: [KokparRider] = []
    /// World position of the serke while it lies on the ground.
    private(set) var serke: CGPoint?
    private(set) var carrying = false
    private(set) var goalD: CGFloat = 1500
    private(set) var goals = 0
    private(set) var lives = KokparEngine.maxLives
    private(set) var invulnerable = 0.0
    private(set) var stun = 0.0
    private(set) var streak = 0
    private(set) var fx = ArcadeFX()
    private(set) var gait: CGFloat = 0
    var active = false

    private var nextRow: CGFloat = 520
    private var nextID = 0
    private var random = PuzzleRandom(seed: 99)
    private var roundStart: CGFloat = 0

    var speed: CGFloat { (190 + CGFloat(min(goals, 8)) * 14) * (stun > 0 ? 0.45 : 1) }
    var progress: CGFloat { min(1, max(0, (distance - roundStart) / max(1, goalD - roundStart))) }

    init() { restart() }

    func restart() {
        state = .playing; bonus = 0; started = false
        lane = 2; px = Self.laneX[2]; distance = 0; riders = []; carrying = false
        goals = 0; lives = Self.maxLives; invulnerable = 0; stun = 0; streak = 0; gait = 0
        fx.reset()
        random = PuzzleRandom(seed: UInt64.random(in: 1...UInt64.max))
        beginRound()
    }

    private func beginRound() {
        roundStart = distance
        goalD = distance + 1500 + CGFloat(min(goals, 8)) * 120
        riders.removeAll { $0.d < distance + 40 }
        carrying = false
        serke = CGPoint(x: Self.laneX[Int.random(in: 0..<Self.lanes, using: &random)], y: distance + 300)
        nextRow = distance + 540
    }

    // MARK: Input

    func swipe(_ direction: Int) {
        guard active, state == .playing else { return }
        if !started { started = true; return }
        let target = max(0, min(Self.lanes - 1, lane + direction))
        guard target != lane else { return }
        lane = target
        SoundFX.play(.whoosh); Haptics.tap()
    }

    func start() { if active, state == .playing { started = true } }

    // MARK: Simulation

    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        let step = CGFloat(min(0.05, max(0, dt)))
        fx.update(step)
        invulnerable = max(0, invulnerable - Double(step))
        stun = max(0, stun - Double(step))
        gait += step * 11 * (speed / 200)
        px += (Self.laneX[lane] - px) * min(1, 13 * step)
        distance += speed * step

        spawnRows()
        updateRiders(step)
        collide()
        pickUp()
        checkGoal()
        riders.removeAll { $0.d < distance - 120 }
    }

    private func spawnRows() {
        guard nextRow < goalD - 220 else { return }
        while nextRow < distance + 700 && nextRow < goalD - 220 {
            let level = min(goals, 10)
            let count = 1 + (Int.random(in: 0..<100, using: &random) < 25 + level * 6 ? 1 : 0) + (level >= 4 && Int.random(in: 0..<100, using: &random) < 25 ? 1 : 0)
            var free = Array(0..<Self.lanes).shuffled(using: &random)
            for _ in 0..<min(count, 3) {
                let lane = free.removeLast()
                let chaser = level >= 1 && Int.random(in: 0..<100, using: &random) < 20 + level * 5
                riders.append(KokparRider(id: nextID, x: Self.laneX[lane], d: nextRow, chaser: chaser, tint: chaser ? 1 : 0))
                nextID += 1
            }
            nextRow += CGFloat(Int.random(in: 170...250, using: &random)) - CGFloat(level * 6)
        }
    }

    private func updateRiders(_ dt: CGFloat) {
        for i in riders.indices {
            let ahead = riders[i].d - distance
            if riders[i].chaser && ahead > 30 && ahead < 280 {
                // Rivals cut across to block the player.
                riders[i].vx = max(-80, min(80, (px - riders[i].x) * 1.8))
            } else if ahead < 30 { riders[i].vx *= 0.9 }
            riders[i].x = max(30, min(290, riders[i].x + riders[i].vx * dt))
            if !riders[i].passed && ahead < -30 {
                riders[i].passed = true
                if abs(riders[i].x - px) < 58 {
                    streak += 1
                    let bonus = 15 * min(streak, 5)
                    self.bonus += bonus
                    fx.popup(L10n.text("Close call!") + " +\(bonus)", at: CGPoint(x: px, y: Self.playerScreenY + 30), color: .yellow, size: 14)
                    SoundFX.play(.point)
                } else { streak = 0 }
            }
        }
    }

    private func collide() {
        guard invulnerable == 0 else { return }
        guard let hit = riders.first(where: { abs($0.d - distance) < 38 && abs($0.x - px) < 30 }) else { return }
        lives -= 1; streak = 0
        invulnerable = 1.4; stun = 0.7
        fx.burst(at: CGPoint(x: px, y: Self.playerScreenY), color: .orange, count: 18, speed: 150, gravity: 0, size: 3, life: 0.6)
        fx.kick(7); fx.flash(.red, 0.22)
        Haptics.error(); SoundFX.play(.hit)
        if carrying {
            // The serke is knocked loose and lands just ahead.
            carrying = false
            serke = CGPoint(x: hit.x, y: distance + 70)
            fx.popup(L10n.text("Dropped it!"), at: CGPoint(x: px, y: Self.playerScreenY - 60), color: .white, size: 18)
        }
        if lives <= 0 {
            state = .gameOver(won: goals >= 1)
        }
    }

    private func pickUp() {
        guard !carrying, let s = serke else { return }
        if abs(s.y - distance) < 34 && abs(s.x - px) < 34 {
            carrying = true; serke = nil
            bonus += 50
            fx.popup(L10n.text("Got the serke! +50"), at: CGPoint(x: px, y: Self.playerScreenY - 50), color: .yellow, size: 17)
            fx.burst(at: CGPoint(x: px, y: Self.playerScreenY - 20), color: .yellow, count: 14, speed: 120, gravity: 60, size: 3)
            Haptics.success(); SoundFX.play(.coin)
        } else if s.y < distance - 80 {
            // Missed it: a new serke is thrown ahead so the round can go on.
            serke = CGPoint(x: Self.laneX[Int.random(in: 0..<Self.lanes, using: &random)], y: distance + 260)
        }
    }

    private func checkGoal() {
        guard distance >= goalD else { return }
        if carrying {
            goals += 1
            let reward = 300 + lives * 50
            bonus += reward
            fx.burst(at: CGPoint(x: 160, y: 130), color: .yellow, count: 40, speed: 220, gravity: 150, size: 4, life: 1)
            fx.popup(L10n.format("Goal %d! +%d", goals, reward), at: CGPoint(x: 160, y: 190), color: .white, size: 24)
            fx.flash(.yellow, 0.25)
            Haptics.heavy(); SoundFX.play(.bell)
            beginRound()
        } else {
            goalD += 700
            fx.popup(L10n.text("Bring the serke first!"), at: CGPoint(x: 160, y: 200), color: .white, size: 17)
            Haptics.error(); SoundFX.play(.wrong)
        }
    }
}

struct KokparView: View {
    @State private var engine = KokparEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .kokpar, engine: engine,
                          resultSummary: L10n.format("Goals: %d", engine.goals)) {
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
                                Image(systemName: "arrow.left.and.right").font(.largeTitle)
                                Text(L10n.text("Swipe to start")).font(.headline)
                            }
                            .padding(22).background(GameTheme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                        let dx = value.translation.width
                        if abs(dx) > 18 { engine.swipe(dx > 0 ? 1 : -1) }
                        else if !engine.started { engine.start() }
                        else { engine.swipe(value.location.x < geo.size.width / 2 ? -1 : 1) }
                    })
                }
                .aspectRatio(320.0 / 460, contentMode: .fit)
                .frame(maxWidth: 380, maxHeight: 460)
                Text(L10n.text("Swipe left or right to change lanes. Grab the serke, dodge the rival riders and carry it to the kazan."))
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
            Label("\(engine.goals)", systemImage: "flag.checkered")
            // Progress to the kazan.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(GameTheme.surfaceHigh)
                    Capsule().fill(engine.carrying ? Color.yellow : GameTheme.accent).frame(width: geo.size.width * engine.progress)
                }
            }
            .frame(height: 8)
            Image(systemName: engine.carrying ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(engine.carrying ? Color.yellow : GameTheme.textSecondary)
                .accessibilityLabel(L10n.text("Serke"))
            HStack(spacing: 2) {
                ForEach(0..<KokparEngine.maxLives, id: \.self) { i in
                    Image(systemName: i < engine.lives ? "heart.fill" : "heart").foregroundStyle(i < engine.lives ? Color.pink : GameTheme.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(GameTheme.accent)
    }

    // MARK: Drawing

    private func screenY(_ d: CGFloat) -> CGFloat { KokparEngine.playerScreenY - (d - engine.distance) }

    private func draw(_ context: inout GraphicsContext) {
        // Mown stripes scroll with the distance.
        let stripe: CGFloat = 70
        let offset = engine.distance.truncatingRemainder(dividingBy: stripe * 2)
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)), with: .color(Color(red: 0.36, green: 0.62, blue: 0.27)))
        var y = -stripe * 2 + offset
        while y < 480 {
            context.fill(Path(CGRect(x: 0, y: y, width: 320, height: stripe)), with: .color(Color(red: 0.4, green: 0.67, blue: 0.3)))
            y += stripe * 2
        }
        // Dusty lane marks and field edges.
        for x in [10.0, 310.0] {
            var edge = Path(); edge.move(to: CGPoint(x: x, y: 0)); edge.addLine(to: CGPoint(x: x, y: 460))
            context.stroke(edge, with: .color(.white.opacity(0.5)), lineWidth: 3)
        }
        for x in [70.0, 130.0, 190.0, 250.0] {
            var lane = Path(); lane.move(to: CGPoint(x: x, y: 0)); lane.addLine(to: CGPoint(x: x, y: 460))
            context.stroke(lane, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 2, dash: [14, 14], dashPhase: -offset))
        }
        // Spectators' flags along the edges, fixed to the field.
        let firstFlag = (engine.distance / 170).rounded(.down) * 170
        for k in -1...3 {
            let yy = screenY(firstFlag + CGFloat(k) * 170)
            for (x, c) in [(4.0, Color.red), (316.0, Color.yellow)] {
                var pole = Path(); pole.move(to: CGPoint(x: x, y: yy)); pole.addLine(to: CGPoint(x: x, y: yy - 14))
                context.stroke(pole, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
                context.fill(Path(CGRect(x: x, y: yy - 14, width: x < 160 ? 9 : -9, height: 6)), with: .color(c))
            }
        }

        // The kazan at the end of the field.
        let gy = screenY(engine.goalD)
        if gy > -90 && gy < 520 { goal(&context, y: gy) }

        // Serke on the ground.
        if let s = engine.serke {
            let sy = screenY(s.y)
            if sy > -40 && sy < 500 { serkeShape(&context, at: CGPoint(x: s.x, y: sy), carried: false) }
        }

        for rider in engine.riders {
            let ry = screenY(rider.d)
            guard ry > -60 && ry < 520 else { continue }
            horse(&context, at: CGPoint(x: rider.x, y: ry), body: rider.chaser ? Color(red: 0.25, green: 0.25, blue: 0.3) : Color(red: 0.55, green: 0.55, blue: 0.6),
                  coat: rider.chaser ? Color(red: 0.2, green: 0.45, blue: 0.9) : Color(red: 0.2, green: 0.65, blue: 0.5),
                  hat: .white, facingUp: false, phase: engine.gait + CGFloat(rider.id))
        }

        // The player: blinks while protected.
        if !(engine.invulnerable > 0 && Int(engine.invulnerable * 12).isMultiple(of: 2)) {
            let p = CGPoint(x: engine.px, y: KokparEngine.playerScreenY)
            horse(&context, at: p, body: Color(red: 0.55, green: 0.32, blue: 0.16), coat: Color(red: 0.9, green: 0.2, blue: 0.25),
                  hat: Color(red: 1, green: 0.85, blue: 0.25), facingUp: true, phase: engine.gait)
            if engine.carrying { serkeShape(&context, at: CGPoint(x: p.x + 13, y: p.y - 4), carried: true) }
        }
    }

    private func goal(_ context: inout GraphicsContext, y: CGFloat) {
        // Chalk line and goal circle with the kazan in the middle.
        context.fill(Path(CGRect(x: 0, y: y - 4, width: 320, height: 8)), with: .color(.white.opacity(0.85)))
        context.fill(Path(ellipseIn: CGRect(x: 60, y: y - 90, width: 200, height: 180)), with: .color(Color(red: 0.88, green: 0.78, blue: 0.5).opacity(0.7)))
        context.stroke(Path(ellipseIn: CGRect(x: 60, y: y - 90, width: 200, height: 180)), with: .color(.white), lineWidth: 4)
        let c = CGPoint(x: 160, y: y)
        context.fill(Path(ellipseIn: CGRect(x: c.x - 44, y: c.y - 44 + 6, width: 88, height: 88)), with: .color(.black.opacity(0.25)))
        context.fill(Path(ellipseIn: CGRect(x: c.x - 44, y: c.y - 44, width: 88, height: 88)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.32, green: 0.3, blue: 0.34), Color(red: 0.1, green: 0.1, blue: 0.13)]),
                                           center: c, startRadius: 2, endRadius: 46))
        context.stroke(Path(ellipseIn: CGRect(x: c.x - 44, y: c.y - 44, width: 88, height: 88)), with: .color(Color(red: 1, green: 0.8, blue: 0.25)), lineWidth: 6)
        // Ornament on the rim and the two handles.
        for k in 0..<10 {
            let a = CGFloat(k) / 10 * .pi * 2
            context.fill(Path(ellipseIn: CGRect(x: c.x + cos(a) * 44 - 3, y: c.y + sin(a) * 44 - 3, width: 6, height: 6)), with: .color(Color(red: 0.9, green: 0.25, blue: 0.25)))
        }
        for side in [-1.0, 1.0] {
            context.stroke(Path(ellipseIn: CGRect(x: c.x + side * 50 - 6, y: c.y - 8, width: 12, height: 16)), with: .color(Color(red: 1, green: 0.8, blue: 0.25)), lineWidth: 3)
        }
        context.draw(Text("🔥").font(.system(size: 24)), at: CGPoint(x: c.x, y: c.y))
        for x in [34.0, 286.0] {
            var pole = Path(); pole.move(to: CGPoint(x: x, y: y + 20)); pole.addLine(to: CGPoint(x: x, y: y - 50))
            context.stroke(pole, with: .color(.white), lineWidth: 3)
            context.fill(Path(CGRect(x: x, y: y - 50, width: x < 160 ? 22 : -22, height: 14)), with: .color(Color(red: 0.2, green: 0.65, blue: 0.9)))
        }
    }

    private func serkeShape(_ context: inout GraphicsContext, at p: CGPoint, carried: Bool) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        if carried { c.rotate(by: .degrees(75)) }
        if !carried {
            let pulse = 1 + 0.12 * sin(engine.gait * 0.6)
            c.fill(Path(ellipseIn: CGRect(x: -22 * pulse, y: -26 * pulse, width: 44 * pulse, height: 52 * pulse)), with: .color(.yellow.opacity(0.25)))
        }
        c.fill(Path(ellipseIn: CGRect(x: -8, y: -4, width: 16, height: 30)), with: .color(.black.opacity(0.2)))
        c.fill(Path(ellipseIn: CGRect(x: -8, y: -14, width: 16, height: 28)),
               with: .linearGradient(Gradient(colors: [Color(red: 0.72, green: 0.52, blue: 0.3), Color(red: 0.45, green: 0.3, blue: 0.16)]),
                                     startPoint: CGPoint(x: -8, y: -14), endPoint: CGPoint(x: 8, y: 14)))
        c.fill(Path(ellipseIn: CGRect(x: -6, y: -22, width: 8, height: 10)), with: .color(Color(red: 0.55, green: 0.38, blue: 0.2)))
        for (dx, dy) in [(-9.0, -8.0), (9.0, -8.0), (-9.0, 8.0), (9.0, 8.0)] {
            var leg = Path(); leg.move(to: CGPoint(x: dx * 0.6, y: dy)); leg.addLine(to: CGPoint(x: dx * 1.6, y: dy + (dy < 0 ? -3 : 3)))
            c.stroke(leg, with: .color(Color(red: 0.35, green: 0.22, blue: 0.1)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }

    /// A horse and rider seen from above.
    private func horse(_ context: inout GraphicsContext, at p: CGPoint, body: Color, coat: Color, hat: Color, facingUp: Bool, phase: CGFloat) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        if !facingUp { c.rotate(by: .radians(.pi)) }
        c.fill(Path(ellipseIn: CGRect(x: -13, y: -18, width: 26, height: 48)), with: .color(.black.opacity(0.22)))
        // Legs, galloping in pairs.
        for (i, (dx, dy)) in [(-7.0, -14.0), (7.0, -14.0), (-7.0, 13.0), (7.0, 13.0)].enumerated() {
            let swing = sin(phase + (i % 2 == 0 ? 0 : .pi)) * 5
            c.fill(Path(roundedRect: CGRect(x: dx - 2, y: dy + swing - 5, width: 4, height: 10), cornerRadius: 2), with: .color(body.opacity(0.85)))
        }
        // Tail, body, neck, head.
        var tail = Path(); tail.move(to: CGPoint(x: 0, y: 22)); tail.addQuadCurve(to: CGPoint(x: sin(phase) * 3, y: 38), control: CGPoint(x: 6, y: 30))
        c.stroke(tail, with: .color(body.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        c.fill(Path(ellipseIn: CGRect(x: -10, y: -18, width: 20, height: 42)),
               with: .linearGradient(Gradient(colors: [body.opacity(0.95), body]), startPoint: CGPoint(x: -10, y: 0), endPoint: CGPoint(x: 10, y: 0)))
        c.fill(Path(ellipseIn: CGRect(x: -4.5, y: -32, width: 9, height: 18)), with: .color(body))
        c.fill(Path(ellipseIn: CGRect(x: -4, y: -40, width: 8, height: 13)), with: .color(body.opacity(0.9)))
        var mane = Path(); mane.move(to: CGPoint(x: 0, y: -30)); mane.addLine(to: CGPoint(x: 0, y: -14))
        c.stroke(mane, with: .color(.black.opacity(0.45)), lineWidth: 2)
        // Rider: saddle cloth, shoulders, head with a feathered hat.
        c.fill(Path(roundedRect: CGRect(x: -7, y: -4, width: 14, height: 12), cornerRadius: 3), with: .color(coat.opacity(0.85)))
        c.fill(Path(ellipseIn: CGRect(x: -9.5, y: -9, width: 19, height: 9)), with: .color(coat))
        c.fill(Path(ellipseIn: CGRect(x: -5, y: -10, width: 10, height: 10)), with: .color(Color(red: 0.95, green: 0.78, blue: 0.62)))
        c.fill(Path(ellipseIn: CGRect(x: -5.5, y: -12, width: 11, height: 9)), with: .color(hat))
        c.fill(Path(CGRect(x: -5.5, y: -8.5, width: 11, height: 2)), with: .color(.black.opacity(0.35)))
    }
}
