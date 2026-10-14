import SwiftUI
import Observation

// Бәйге — the long-distance horse race. A side-scrolling runner: tap to jump (hold
// for a higher jump), clear fences, rocks and ditches, collect coins and grab the
// golden whip for a burst of speed.

struct BaigeThing: Identifiable {
    enum Kind { case fence, rock, ditch, coin, boost }
    let id: Int
    let kind: Kind
    /// World position along the track.
    let d: CGFloat
    /// Width on the ground; for collectibles, their height above the ground.
    let w: CGFloat
    let h: CGFloat
    var taken = false
}

@MainActor
@Observable
final class BaigeEngine: GameEngine {
    static let horseX: CGFloat = 84
    static let groundY: CGFloat = 338
    static let maxLives = 3
    private static let gravity: CGFloat = 1900
    private static let jumpSpeed: CGFloat = 660

    var state: GameState = .playing
    private var bonus = 0
    var score: Int { Int(distance / 10) + bonus }
    private(set) var started = false
    private(set) var distance: CGFloat = 0
    private(set) var height: CGFloat = 0
    private(set) var verticalSpeed: CGFloat = 0
    private(set) var things: [BaigeThing] = []
    private(set) var lives = BaigeEngine.maxLives
    private(set) var coins = 0
    private(set) var boostLeft = 0.0
    private(set) var invulnerable = 0.0
    private(set) var stumble = 0.0
    private(set) var gait: CGFloat = 0
    private(set) var fx = ArcadeFX()
    var active = false

    private var holding = false
    private var buffered = 0.0
    private var nextD: CGFloat = 520
    private var nextID = 0
    private var sinceBoost: CGFloat = 0
    private var random = PuzzleRandom(seed: 5)
    private var strideClock: CGFloat = 0

    var onGround: Bool { height <= 0.5 && verticalSpeed <= 0 }
    var speed: CGFloat {
        let base = 235 + min(150, distance / 60)
        return base * (boostLeft > 0 ? 1.45 : 1) * (stumble > 0 ? 0.55 : 1)
    }

    init() { restart() }

    func restart() {
        state = .playing; bonus = 0; started = false
        distance = 0; height = 0; verticalSpeed = 0; things = []; lives = Self.maxLives; coins = 0
        boostLeft = 0; invulnerable = 0; stumble = 0; gait = 0; holding = false; buffered = 0
        nextD = 520; nextID = 0; sinceBoost = 0; strideClock = 0
        random = PuzzleRandom(seed: UInt64.random(in: 1...UInt64.max))
        fx.reset()
    }

    // MARK: Input

    func press() {
        guard active, state == .playing else { return }
        if !started { started = true }
        holding = true
        if onGround { jump() } else { buffered = 0.14 }
    }
    func release() { holding = false }

    private func jump() {
        verticalSpeed = Self.jumpSpeed
        height = 1
        buffered = 0
        SoundFX.play(.jump); Haptics.tap()
        fx.burst(at: CGPoint(x: Self.horseX - 14, y: Self.groundY), color: Color(red: 0.8, green: 0.7, blue: 0.5), count: 6, speed: 60, gravity: -40, size: 3, life: 0.4)
    }

    // MARK: Simulation

    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        let step = CGFloat(min(0.05, max(0, dt)))
        fx.update(step)
        invulnerable = max(0, invulnerable - Double(step)); stumble = max(0, stumble - Double(step))
        boostLeft = max(0, boostLeft - Double(step)); buffered = max(0, buffered - Double(step))
        let v = speed
        distance += v * step
        gait += step * 12 * (v / 240)
        strideClock += step
        if onGround && strideClock > 0.22 { strideClock = 0; SoundFX.play(.gallop) }

        // Gravity is lighter while the finger is down, so a long press makes a high jump.
        if height > 0 || verticalSpeed > 0 {
            let g = Self.gravity * ((holding && verticalSpeed > 0) ? 0.55 : 1)
            verticalSpeed -= g * step
            height += verticalSpeed * step
            if height <= 0 {
                height = 0; verticalSpeed = 0
                fx.burst(at: CGPoint(x: Self.horseX + 10, y: Self.groundY), color: Color(red: 0.8, green: 0.7, blue: 0.5), count: 5, speed: 50, gravity: -30, size: 3, life: 0.35)
                if buffered > 0 { jump() }
            }
        }
        if boostLeft > 0 {
            fx.burst(at: CGPoint(x: Self.horseX - 30, y: Self.groundY - 26 - height), color: [Color.orange, .yellow].randomElement()!, count: 1, speed: 40, gravity: 0, size: 3, life: 0.35)
        }

        spawn()
        interact()
        things.removeAll { $0.d + $0.w < distance - 160 }
    }

    private func spawn() {
        let level = min(1, distance / 6000)
        while nextD < distance + 560 {
            let pick = Int.random(in: 0..<100, using: &random)
            var next: CGFloat = nextD
            func add(_ kind: BaigeThing.Kind, at d: CGFloat, w: CGFloat, h: CGFloat) {
                things.append(BaigeThing(id: nextID, kind: kind, d: d, w: w, h: h)); nextID += 1
            }
            func arc(over center: CGFloat, count: Int = 5, peak: CGFloat = 92) {
                for i in 0..<count {
                    let t = CGFloat(i) / CGFloat(count - 1) * 2 - 1
                    add(.coin, at: center + t * 70, w: 14, h: 26 + peak * (1 - t * t))
                }
            }
            switch pick {
            case 0..<30: add(.fence, at: nextD, w: 24, h: 36); arc(over: nextD + 12); next += 24
            case 30..<52: add(.rock, at: nextD, w: 28, h: 24); arc(over: nextD + 14, count: 4, peak: 70); next += 28
            case 52..<72:
                let width = 74 + level * 40
                add(.ditch, at: nextD, w: width, h: 0); arc(over: nextD + width / 2, count: 5, peak: 100); next += width
            case 72..<88:
                // A rock quickly followed by a fence: two short jumps.
                add(.rock, at: nextD, w: 28, h: 24); add(.fence, at: nextD + 130, w: 24, h: 36)
                arc(over: nextD + 65, count: 3, peak: 55); next += 154
            default:
                // A breather: a line of coins on the ground.
                for i in 0..<6 { add(.coin, at: nextD + CGFloat(i) * 30, w: 14, h: 24) }
                next += 180
            }
            sinceBoost += next - nextD
            if sinceBoost > 1500, pick > 40 {
                sinceBoost = 0
                add(.boost, at: next + 90, w: 22, h: 54 + CGFloat(Int.random(in: 0...30, using: &random)))
                next += 140
            }
            // Leave room to land and read the next obstacle: more at higher speed.
            nextD = next + max(200, speed * 0.78) + CGFloat(Int.random(in: 0...120, using: &random)) * (1 - level)
        }
    }

    private func interact() {
        let hx = Self.horseX + distance
        for i in things.indices where !things[i].taken {
            let t = things[i]
            switch t.kind {
            case .coin:
                // A generous pick-up box around the horse's body.
                guard abs(t.d - hx) < 24, t.h >= height - 14, t.h <= height + 60 else { continue }
                things[i].taken = true
                coins += 1
                let points = 10 * (boostLeft > 0 ? 2 : 1)
                bonus += points
                fx.popup("+\(points)", at: CGPoint(x: Self.horseX + 20, y: Self.groundY - t.h - 18), color: .yellow, size: 15)
                fx.burst(at: CGPoint(x: Self.horseX + 10, y: Self.groundY - t.h), color: .yellow, count: 6, speed: 80, gravity: 40, size: 2.5, life: 0.4)
                SoundFX.play(.coin)
            case .boost:
                guard abs(t.d - hx) < 28, t.h >= height - 20, t.h <= height + 70 else { continue }
                things[i].taken = true
                boostLeft = 3.5; invulnerable = max(invulnerable, 3.5)
                bonus += 50
                fx.popup(L10n.text("Speed up!"), at: CGPoint(x: Self.horseX + 30, y: Self.groundY - 90), color: .orange, size: 19)
                fx.flash(.orange, 0.2)
                Haptics.heavy(); SoundFX.play(.clear)
            case .fence, .rock:
                guard invulnerable == 0 else { continue }
                if hx + 14 > t.d && hx - 14 < t.d + t.w && height < t.h - 4 { hit(things: i) }
            case .ditch:
                guard invulnerable == 0 else { continue }
                // Falling in needs the horse to be low while over the middle of the gap.
                if hx > t.d + 8 && hx < t.d + t.w - 8 && height < 6 { hit(things: i, ditch: true) }
            }
        }
    }

    private func hit(things i: Int, ditch: Bool = false) {
        lives -= 1
        invulnerable = 1.5; stumble = 0.6
        if ditch { verticalSpeed = 560; height = 2 }
        else { things[i].taken = true }
        fx.burst(at: CGPoint(x: Self.horseX + 16, y: Self.groundY - 24 - height), color: .orange, count: 16, speed: 140, gravity: 120, size: 3, life: 0.6)
        fx.kick(7); fx.flash(.red, 0.22)
        Haptics.error(); SoundFX.play(.hit)
        if lives <= 0 { state = .gameOver(won: distance > 1500) }
    }
}

struct BaigeView: View {
    @State private var engine = BaigeEngine()
    @State private var pressed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .baige, engine: engine,
                          resultSummary: L10n.format("Distance: %d m", Int(engine.distance / 10)), centersContent: true) {
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
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !pressed { pressed = true; engine.press() } }
                        .onEnded { _ in pressed = false; engine.release() })
                }
                .aspectRatio(320.0 / 460, contentMode: .fit)
                .frame(maxWidth: 380, maxHeight: 460)
                Text(L10n.text("Tap to jump, hold to jump higher. Clear fences, rocks and ditches, collect coins and grab the golden whip for a burst of speed."))
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
        HStack(spacing: 12) {
            Label(L10n.format("%d m", Int(engine.distance / 10)), systemImage: "arrow.right").monospacedDigit()
            Label("\(engine.coins)", systemImage: "circle.circle.fill").foregroundStyle(.yellow).monospacedDigit()
            if engine.boostLeft > 0 {
                Label(String(format: "%.1f", engine.boostLeft), systemImage: "bolt.fill").foregroundStyle(.orange).monospacedDigit()
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(0..<BaigeEngine.maxLives, id: \.self) { i in
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

    private func screenX(_ d: CGFloat) -> CGFloat { BaigeEngine.horseX + d - engine.distance }

    private func draw(_ context: inout GraphicsContext) {
        let ground = BaigeEngine.groundY
        let dist = engine.distance
        // Sky.
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 460)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.4, green: 0.7, blue: 0.98), Color(red: 1, green: 0.88, blue: 0.68)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: ground)))
        context.fill(Path(ellipseIn: CGRect(x: 238, y: 46, width: 46, height: 46)), with: .color(Color(red: 1, green: 0.96, blue: 0.75)))
        // Clouds, mountains and yurts at different parallax speeds.
        for k in 0..<4 {
            let x = (CGFloat(k) * 150 - dist * 0.05).truncatingRemainder(dividingBy: 600)
            let cx = x < -90 ? x + 600 : x
            context.fill(Path(roundedRect: CGRect(x: cx, y: 70 + CGFloat(k * 37 % 90), width: 80, height: 16), cornerRadius: 8), with: .color(.white.opacity(0.6)))
            context.fill(Path(ellipseIn: CGRect(x: cx + 18, y: 60 + CGFloat(k * 37 % 90), width: 36, height: 26)), with: .color(.white.opacity(0.6)))
        }
        for layer in 0..<2 {
            let factor: CGFloat = layer == 0 ? 0.12 : 0.28
            let period: CGFloat = layer == 0 ? 420 : 330
            let tone = layer == 0 ? Color(red: 0.55, green: 0.62, blue: 0.82) : Color(red: 0.4, green: 0.58, blue: 0.5)
            let base = (-(dist * factor)).truncatingRemainder(dividingBy: period)
            for k in -1...3 {
                let x0 = base + CGFloat(k) * period
                var m = Path(); m.move(to: CGPoint(x: x0, y: ground - 30))
                m.addLine(to: CGPoint(x: x0 + period * 0.45, y: ground - (layer == 0 ? 190 : 110) - CGFloat((k + 8) * 17 % 30)))
                m.addLine(to: CGPoint(x: x0 + period, y: ground - 30)); m.closeSubpath()
                context.fill(m, with: .color(tone))
                if layer == 0 {
                    var snow = Path(); snow.move(to: CGPoint(x: x0 + period * 0.36, y: ground - 150)); snow.addLine(to: CGPoint(x: x0 + period * 0.45, y: ground - 190 - CGFloat((k + 8) * 17 % 30)))
                    snow.addLine(to: CGPoint(x: x0 + period * 0.54, y: ground - 150))
                    context.fill(snow, with: .color(.white.opacity(0.85)))
                }
            }
        }
        let yurtPeriod: CGFloat = 520
        let yurtBase = (-(dist * 0.5)).truncatingRemainder(dividingBy: yurtPeriod)
        for k in 0...1 { yurt(&context, at: CGPoint(x: yurtBase + CGFloat(k) * yurtPeriod + 200, y: ground - 8)) }

        // Ground with the ditches cut out of it.
        context.fill(Path(CGRect(x: 0, y: ground, width: 320, height: 460 - ground)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.45, green: 0.7, blue: 0.3), Color(red: 0.3, green: 0.5, blue: 0.2)]),
                                           startPoint: CGPoint(x: 0, y: ground), endPoint: CGPoint(x: 0, y: 460)))
        context.fill(Path(CGRect(x: 0, y: ground, width: 320, height: 6)), with: .color(Color(red: 0.55, green: 0.8, blue: 0.35)))
        let tuftBase = (-dist).truncatingRemainder(dividingBy: 40)
        for k in -1...8 {
            let x = tuftBase + CGFloat(k) * 40
            var tuft = Path()
            for blade in -1...1 { tuft.move(to: CGPoint(x: x, y: ground + 22 + CGFloat(k % 3) * 12)); tuft.addLine(to: CGPoint(x: x + CGFloat(blade) * 3, y: ground + 14 + CGFloat(k % 3) * 12)) }
            context.stroke(tuft, with: .color(Color(red: 0.2, green: 0.4, blue: 0.14).opacity(0.7)), lineWidth: 1.5)
        }
        for t in engine.things where t.kind == .ditch {
            let x = screenX(t.d)
            guard x < 340 && x + t.w > -20 else { continue }
            context.fill(Path(CGRect(x: x, y: ground, width: t.w, height: 460 - ground)), with: .color(Color(red: 0.18, green: 0.1, blue: 0.06)))
            context.fill(Path(CGRect(x: x, y: ground, width: t.w, height: 14)), with: .linearGradient(Gradient(colors: [Color(red: 0.3, green: 0.18, blue: 0.1), Color(red: 0.12, green: 0.07, blue: 0.04)]), startPoint: CGPoint(x: 0, y: ground), endPoint: CGPoint(x: 0, y: ground + 14)))
            for edge in [x, x + t.w - 5] { context.fill(Path(roundedRect: CGRect(x: edge, y: ground - 3, width: 5, height: 8), cornerRadius: 2), with: .color(Color(red: 0.4, green: 0.65, blue: 0.28))) }
        }

        // Fences, rocks and collectibles.
        for t in engine.things where !t.taken {
            let x = screenX(t.d)
            guard x > -80 && x < 360 else { continue }
            switch t.kind {
            case .fence: fence(&context, x: x, w: t.w, h: t.h, ground: ground)
            case .rock: rock(&context, x: x, w: t.w, h: t.h, ground: ground)
            case .coin: coin(&context, at: CGPoint(x: x, y: ground - t.h), phase: CGFloat(t.id))
            case .boost: boost(&context, at: CGPoint(x: x, y: ground - t.h))
            case .ditch: break
            }
        }

        // Horse and rider; blinking while protected (but steady glow during a boost).
        let blink = engine.invulnerable > 0 && engine.boostLeft == 0 && Int(engine.invulnerable * 12).isMultiple(of: 2)
        if !blink {
            if engine.boostLeft > 0 {
                var halo = context
                halo.fill(Path(ellipseIn: CGRect(x: BaigeEngine.horseX - 52, y: ground - engine.height - 62, width: 112, height: 80)), with: .color(.orange.opacity(0.28)))
                for k in 1...4 {
                    var line = Path(); let y = ground - engine.height - 14 - CGFloat(k) * 9
                    line.move(to: CGPoint(x: BaigeEngine.horseX - 34 - CGFloat(k) * 4, y: y)); line.addLine(to: CGPoint(x: BaigeEngine.horseX - 70 - CGFloat(k) * 8, y: y))
                    halo.stroke(line, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            galloper(&context, at: CGPoint(x: BaigeEngine.horseX, y: ground - engine.height))
        }
    }

    private func fence(_ c: inout GraphicsContext, x: CGFloat, w: CGFloat, h: CGFloat, ground: CGFloat) {
        let wood = Color(red: 0.62, green: 0.4, blue: 0.2)
        c.fill(Path(ellipseIn: CGRect(x: x - 4, y: ground - 3, width: w + 8, height: 8)), with: .color(.black.opacity(0.2)))
        for px in [x, x + w - 5] { c.fill(Path(roundedRect: CGRect(x: px, y: ground - h, width: 5, height: h), cornerRadius: 2), with: .color(wood)) }
        for ry in [ground - h + 6, ground - h * 0.5] { c.fill(Path(roundedRect: CGRect(x: x - 2, y: ry, width: w + 4, height: 5), cornerRadius: 2), with: .color(wood.opacity(0.9))) }
        c.fill(Path(CGRect(x: x + w / 2 - 3, y: ground - h - 2, width: 6, height: 8)), with: .color(Color(red: 0.9, green: 0.25, blue: 0.25)))
    }

    private func rock(_ c: inout GraphicsContext, x: CGFloat, w: CGFloat, h: CGFloat, ground: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: x, y: ground)); path.addQuadCurve(to: CGPoint(x: x + w * 0.35, y: ground - h), control: CGPoint(x: x + 1, y: ground - h * 0.9))
        path.addQuadCurve(to: CGPoint(x: x + w, y: ground), control: CGPoint(x: x + w + 3, y: ground - h * 0.8)); path.closeSubpath()
        c.fill(path, with: .linearGradient(Gradient(colors: [Color(white: 0.72), Color(white: 0.45)]), startPoint: CGPoint(x: x, y: ground - h), endPoint: CGPoint(x: x + w, y: ground)))
        c.fill(Path(ellipseIn: CGRect(x: x + w * 0.22, y: ground - h * 0.75, width: w * 0.22, height: h * 0.2)), with: .color(.white.opacity(0.4)))
    }

    private func coin(_ c: inout GraphicsContext, at p: CGPoint, phase: CGFloat) {
        let squash = max(0.2, abs(cos(engine.gait * 0.4 + phase)))
        c.fill(Path(ellipseIn: CGRect(x: p.x - 8 * squash - 3, y: p.y - 11, width: 16 * squash + 6, height: 22)), with: .color(.yellow.opacity(0.22)))
        c.fill(Path(ellipseIn: CGRect(x: p.x - 8 * squash, y: p.y - 8, width: 16 * squash, height: 16)), with: .color(Color(red: 1, green: 0.8, blue: 0.2)))
        c.stroke(Path(ellipseIn: CGRect(x: p.x - 5 * squash, y: p.y - 5, width: 10 * squash, height: 10)), with: .color(Color(red: 0.85, green: 0.55, blue: 0.1)), lineWidth: 1.5)
    }

    private func boost(_ c: inout GraphicsContext, at p: CGPoint) {
        let pulse = 1 + 0.12 * sin(engine.gait * 0.5)
        c.fill(Path(ellipseIn: CGRect(x: p.x - 22 * pulse, y: p.y - 22 * pulse, width: 44 * pulse, height: 44 * pulse)), with: .color(.orange.opacity(0.28)))
        c.fill(Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)), with: .linearGradient(Gradient(colors: [.yellow, .orange]), startPoint: CGPoint(x: p.x, y: p.y - 14), endPoint: CGPoint(x: p.x, y: p.y + 14)))
        var bolt = Path()
        bolt.move(to: CGPoint(x: p.x + 2, y: p.y - 9)); bolt.addLine(to: CGPoint(x: p.x - 5, y: p.y + 1)); bolt.addLine(to: CGPoint(x: p.x, y: p.y + 1))
        bolt.addLine(to: CGPoint(x: p.x - 2, y: p.y + 9)); bolt.addLine(to: CGPoint(x: p.x + 5, y: p.y - 2)); bolt.addLine(to: CGPoint(x: p.x, y: p.y - 2)); bolt.closeSubpath()
        c.fill(bolt, with: .color(.white))
    }

    private func yurt(_ context: inout GraphicsContext, at p: CGPoint) {
        context.fill(Path(roundedRect: CGRect(x: p.x - 26, y: p.y - 18, width: 52, height: 26), cornerRadius: 4), with: .color(Color(red: 0.96, green: 0.93, blue: 0.85)))
        var dome = Path(); dome.move(to: CGPoint(x: p.x - 28, y: p.y - 16)); dome.addQuadCurve(to: CGPoint(x: p.x + 28, y: p.y - 16), control: CGPoint(x: p.x, y: p.y - 46))
        dome.closeSubpath()
        context.fill(dome, with: .color(Color(red: 0.99, green: 0.97, blue: 0.92)))
        context.stroke(dome, with: .color(Color(red: 0.2, green: 0.5, blue: 0.65)), lineWidth: 2)
        context.fill(Path(roundedRect: CGRect(x: p.x - 5, y: p.y - 8, width: 10, height: 16), cornerRadius: 3), with: .color(Color(red: 0.2, green: 0.5, blue: 0.65)))
    }

    /// Side view of a galloping horse with a young rider.
    private func galloper(_ context: inout GraphicsContext, at p: CGPoint) {
        var c = context
        c.translateBy(x: p.x, y: p.y)
        let airborne = engine.height > 2
        let phase = engine.gait
        // Soft shadow stays on the ground.
        var shadow = context
        shadow.translateBy(x: p.x, y: BaigeEngine.groundY)
        shadow.fill(Path(ellipseIn: CGRect(x: -30, y: -3, width: 60, height: 8)), with: .color(.black.opacity(max(0.05, 0.22 - engine.height / 600))))
        let coat = Color(red: 0.5, green: 0.3, blue: 0.16), dark = Color(red: 0.32, green: 0.18, blue: 0.09)
        // Tail streams behind.
        var tail = Path(); tail.move(to: CGPoint(x: -26, y: -34)); tail.addCurve(to: CGPoint(x: -52, y: -22 + sin(phase * 1.3) * 4), control1: CGPoint(x: -38, y: -42), control2: CGPoint(x: -46, y: -34))
        c.stroke(tail, with: .color(Color(red: 0.12, green: 0.08, blue: 0.05)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // Legs: far pair first, then body, then near pair.
        func leg(hipX: CGFloat, offset: CGFloat, near: Bool) {
            let swing = airborne ? (hipX > 0 ? 0.9 : -0.9) : sin(phase + offset) * 0.95
            let upper: CGFloat = 12, lower: CGFloat = 13
            let hip = CGPoint(x: hipX, y: -16)
            let knee = CGPoint(x: hip.x + sin(swing) * upper, y: hip.y + cos(swing) * upper)
            let bend = airborne ? (hipX > 0 ? 0.2 : 1.1) : swing - 0.6 * sin(phase + offset + 1.2)
            let hoof = CGPoint(x: knee.x + sin(bend) * lower, y: min(0, knee.y + cos(bend) * lower))
            var l = Path(); l.move(to: hip); l.addLine(to: knee); l.addLine(to: hoof)
            c.stroke(l, with: .color(near ? coat : dark), style: StrokeStyle(lineWidth: near ? 5 : 4.5, lineCap: .round, lineJoin: .round))
            c.fill(Path(ellipseIn: CGRect(x: hoof.x - 2.5, y: hoof.y - 2, width: 5, height: 4)), with: .color(.black.opacity(0.6)))
        }
        leg(hipX: -20, offset: .pi, near: false); leg(hipX: 18, offset: 0.0, near: false)
        // Body, neck and head.
        c.fill(Path(ellipseIn: CGRect(x: -30, y: -40, width: 62, height: 28)), with: .linearGradient(Gradient(colors: [coat.opacity(1), dark]), startPoint: CGPoint(x: 0, y: -40), endPoint: CGPoint(x: 0, y: -12)))
        var neck = Path(); neck.move(to: CGPoint(x: 18, y: -36)); neck.addLine(to: CGPoint(x: 32, y: -56)); neck.addLine(to: CGPoint(x: 40, y: -50)); neck.addLine(to: CGPoint(x: 28, y: -22)); neck.closeSubpath()
        c.fill(neck, with: .color(coat))
        c.fill(Path(ellipseIn: CGRect(x: 30, y: -64, width: 24, height: 13)).applying(CGAffineTransform(rotationAngle: 0.45)), with: .color(coat))
        c.fill(Path(ellipseIn: CGRect(x: 41, y: -52, width: 3.5, height: 3.5)), with: .color(.black))
        var ear = Path(); ear.move(to: CGPoint(x: 32, y: -56)); ear.addLine(to: CGPoint(x: 30, y: -66)); ear.addLine(to: CGPoint(x: 37, y: -58)); ear.closeSubpath()
        c.fill(ear, with: .color(dark))
        var mane = Path(); mane.move(to: CGPoint(x: 34, y: -58)); mane.addCurve(to: CGPoint(x: 16, y: -38), control1: CGPoint(x: 22, y: -62 + sin(phase * 1.4) * 2), control2: CGPoint(x: 18, y: -50))
        c.stroke(mane, with: .color(Color(red: 0.12, green: 0.08, blue: 0.05)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        leg(hipX: -16, offset: .pi * 0.5, near: true); leg(hipX: 22, offset: -.pi * 0.5, near: true)
        // Saddle cloth with a Kazakh pattern and the young rider leaning forward.
        c.fill(Path(roundedRect: CGRect(x: -8, y: -43, width: 22, height: 10), cornerRadius: 3), with: .color(Color(red: 0.85, green: 0.18, blue: 0.25)))
        c.fill(Path(CGRect(x: -6, y: -39, width: 18, height: 2)), with: .color(Color(red: 1, green: 0.85, blue: 0.3)))
        c.fill(Path(ellipseIn: CGRect(x: -3, y: -66, width: 14, height: 24)).applying(CGAffineTransform(rotationAngle: 0.35)), with: .color(Color(red: 0.2, green: 0.5, blue: 0.9)))
        c.fill(Path(ellipseIn: CGRect(x: 8, y: -75, width: 11, height: 11)), with: .color(Color(red: 0.96, green: 0.78, blue: 0.62)))
        c.fill(Path(roundedRect: CGRect(x: 7.5, y: -80, width: 12, height: 7), cornerRadius: 3), with: .color(Color(red: 1, green: 0.85, blue: 0.25)))
        var rein = Path(); rein.move(to: CGPoint(x: 14, y: -58)); rein.addLine(to: CGPoint(x: 38, y: -52))
        c.stroke(rein, with: .color(.black.opacity(0.6)), lineWidth: 1.2)
    }
}
