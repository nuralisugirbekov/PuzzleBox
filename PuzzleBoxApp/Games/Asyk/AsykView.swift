import SwiftUI
import Observation

// Асық ату — the traditional Kazakh knucklebone game. Asyks stand inside a ring;
// the player flicks a heavy "сақа" to knock them out. Every asyk that leaves the
// ring is won. Each level has its own arrangement and a limited number of throws.

struct AsykBody: Identifiable {
    let id: Int
    var p: CGPoint
    var v: CGVector = .zero
    let r: CGFloat
    let mass: CGFloat
    /// nil for a сақа; otherwise the asyk's dye colour index.
    let dye: Int?
    /// Which side faces up: 0 алшы, 1 тәйкі, 2 бүк, 3 шік.
    let side: Int
    var angle: CGFloat
    var out = false
    var counted = false
}

/// Arrangements of asyks inside the ring, one family per level (cycling every 8 levels).
enum AsykLayouts {
    static let names = ["Line", "Double row", "Pyramid", "Cross", "Circle", "Diamond", "Two camps", "Scattered"]
    static let spacing: CGFloat = 23

    static func count(level: Int) -> Int { min(16, 7 + (level - 1) / 3) }
    static func throwsFor(level: Int, count: Int) -> Int { max(3, Int((Double(count) * 0.5).rounded(.up))) + (level < 4 ? 1 : 0) }

    /// Positions relative to the ring centre.
    static func points(level: Int, count n: Int) -> [CGPoint] {
        let s = spacing
        func rows(_ counts: [Int], dy: CGFloat = 20, dx: CGFloat = 23, offset: CGPoint = .zero) -> [CGPoint] {
            var result: [CGPoint] = []
            for (k, c) in counts.enumerated() {
                let y = (CGFloat(k) - CGFloat(counts.count - 1) / 2) * dy
                for i in 0..<c { result.append(CGPoint(x: (CGFloat(i) - CGFloat(c - 1) / 2) * dx + offset.x, y: y + offset.y)) }
            }
            return result
        }
        var pts: [CGPoint]
        switch (level - 1) % 8 {
        case 0: // one or two straight rows
            pts = n <= 9 ? rows([n], dy: s) : rows([9, n - 9], dy: s)
        case 1:
            pts = rows([(n + 1) / 2, n / 2], dy: s)
        case 2: // pyramid, point up
            var counts: [Int] = [], total = 0, row = 1
            while total < n { let c = min(row, n - total); counts.append(c); total += c; row += 1 }
            pts = rows(counts)
        case 3: // plus sign
            let arm = max(2, (n - 1) / 4)
            pts = [.zero]
            for k in 1...arm { for sign in [-1, 1] as [CGFloat] {
                pts.append(CGPoint(x: sign * CGFloat(k) * s, y: 0)); pts.append(CGPoint(x: 0, y: sign * CGFloat(k) * s))
            } }
        case 4: // ring
            let radius = min(88, max(42, CGFloat(n) * s / (2 * .pi)))
            pts = (0..<n).map { CGPoint(x: cos(CGFloat($0) / CGFloat(n) * .pi * 2) * radius, y: sin(CGFloat($0) / CGFloat(n) * .pi * 2) * radius) }
        case 5: // diamond
            var counts: [Int] = [], total = 0, row = 1, growing = true
            while total < n {
                let c = min(row, n - total); counts.append(c); total += c
                if growing { row += 1; if row > 4 { growing = false; row = 3 } } else { row = max(1, row - 1) }
            }
            pts = rows(counts)
        case 6: // two camps facing each other
            let a = (n + 1) / 2, b = n / 2
            let left = rows(a > 3 ? [3, a - 3] : [a], offset: CGPoint(x: -62, y: 0))
            let right = rows(b > 3 ? [3, b - 3] : [b], offset: CGPoint(x: 62, y: 0))
            pts = left + right
        default: // scattered, but the same every time for a given level
            var random = PuzzleRandom(seed: UInt64(level) &* 40_503)
            pts = []
            var tries = 0
            while pts.count < n && tries < 4000 {
                tries += 1
                let a = CGFloat.random(in: 0..<(.pi * 2), using: &random), d = CGFloat.random(in: 0...90, using: &random)
                let q = CGPoint(x: cos(a) * d, y: sin(a) * d)
                if pts.allSatisfy({ hypot($0.x - q.x, $0.y - q.y) >= s }) { pts.append(q) }
            }
        }
        // Never outside the ring.
        return Array(pts.filter { hypot($0.x, $0.y) <= AsykEngine.ringRadius - 16 }.prefix(n))
    }
}

@MainActor
@Observable
final class AsykEngine: GameEngine {
    static let field = CGSize(width: 360, height: 540)
    static let ringCenter = CGPoint(x: 180, y: 262)
    static let ringRadius: CGFloat = 122
    static let playerStart = CGPoint(x: 180, y: 486)
    static let sideNames = ["Алшы", "Тәйкі", "Бүк", "Шік"]
    static let levelCount = 40
    private static let levelKey = "asykLevel"

    var state: GameState = .playing
    private(set) var score = 0
    private(set) var level = 1
    private(set) var bodies: [AsykBody] = []
    private(set) var moving = false
    private(set) var aim: CGVector?
    private(set) var fx = ArcadeFX()
    private(set) var throwsLeft = 0
    private(set) var totalAsyks = 0
    private(set) var knocked = 0
    var active = false

    private var knockedThisShot = 0
    private var restTime = 0.0
    private var nextID = 0

    var hasNextLevel: Bool { level < Self.levelCount }

    init() {
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: Self.levelKey)))
        restart()
    }

    func restart() {
        state = .playing; score = 0; fx.reset(); aim = nil; moving = false
        loadLevel()
    }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: Self.levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    private func loadLevel() {
        bodies = []; nextID = 0; knocked = 0
        let n = AsykLayouts.count(level: level)
        var random = PuzzleRandom(seed: UInt64(level) &* 7_177)
        let pts = AsykLayouts.points(level: level, count: n)
        for (i, q) in pts.enumerated() {
            bodies.append(AsykBody(id: nextID, p: CGPoint(x: Self.ringCenter.x + q.x, y: Self.ringCenter.y + q.y), r: 10.5, mass: 1,
                                   dye: i % 5, side: Int.random(in: 0..<4, using: &random),
                                   angle: CGFloat.random(in: -0.35...0.35, using: &random)))
            nextID += 1
        }
        totalAsyks = bodies.count
        throwsLeft = AsykLayouts.throwsFor(level: level, count: totalAsyks)
        placeSaqa()
    }

    private func placeSaqa() {
        bodies.removeAll { $0.dye == nil }
        bodies.append(AsykBody(id: nextID, p: Self.playerStart, r: 14, mass: 2.4, dye: nil, side: 0, angle: 0))
        nextID += 1
        knockedThisShot = 0
    }

    var saqaIndex: Int? { bodies.firstIndex { $0.dye == nil } }
    var saqaPosition: CGPoint? { saqaIndex.map { bodies[$0].p } }
    var canAim: Bool { active && state == .playing && !moving && throwsLeft > 0 }

    /// Moves the сақа along the throwing line before a shot.
    func slide(to x: CGFloat) {
        guard canAim, let i = saqaIndex else { return }
        bodies[i].p.x = min(Self.field.width - 30, max(30, x))
    }

    /// `drag` points from the сақа toward the finger: the throw goes that way.
    func updateAim(drag: CGVector) {
        guard canAim else { return }
        aim = hypot(drag.dx, drag.dy) < 12 ? nil : drag
    }

    func release() {
        guard canAim, let vector = aim, let i = saqaIndex else { aim = nil; return }
        aim = nil
        let length = max(1, hypot(vector.dx, vector.dy))
        let speed = min(950, length * 8)
        bodies[i].v = CGVector(dx: vector.dx / length * speed, dy: vector.dy / length * speed)
        throwsLeft -= 1
        moving = true; restTime = 0
        SoundFX.play(.whoosh); Haptics.tap()
    }

    // MARK: Simulation

    func advance(_ dt: Double) {
        guard active, state == .playing else { return }
        let total = min(0.05, max(0, dt))
        fx.update(CGFloat(total))
        guard moving else { return }
        var remaining = total
        while remaining > 0 {
            let step = min(remaining, 1.0 / 240)
            physics(CGFloat(step)); remaining -= step
        }
        let still = bodies.allSatisfy { hypot($0.v.dx, $0.v.dy) < 4 }
        restTime = still ? restTime + total : 0
        if restTime > 0.25 { endShot() }
    }

    private func physics(_ dt: CGFloat) {
        for i in bodies.indices {
            var speed = hypot(bodies[i].v.dx, bodies[i].v.dy)
            guard speed > 0 else { continue }
            // Rolling friction on hard steppe ground.
            let newSpeed = max(0, speed - (bodies[i].dye == nil ? 300 : 420) * dt)
            bodies[i].v.dx *= newSpeed / speed; bodies[i].v.dy *= newSpeed / speed
            speed = newSpeed
            bodies[i].p.x += bodies[i].v.dx * dt; bodies[i].p.y += bodies[i].v.dy * dt
            bodies[i].angle += speed * dt * 0.04 * (bodies[i].id.isMultiple(of: 2) ? 1 : -1)
            // Field edges stop pieces dead.
            if bodies[i].p.x < bodies[i].r || bodies[i].p.x > Self.field.width - bodies[i].r
                || bodies[i].p.y < bodies[i].r || bodies[i].p.y > Self.field.height - bodies[i].r {
                bodies[i].p.x = min(Self.field.width - bodies[i].r, max(bodies[i].r, bodies[i].p.x))
                bodies[i].p.y = min(Self.field.height - bodies[i].r, max(bodies[i].r, bodies[i].p.y))
                bodies[i].v = .zero
            }
        }
        for i in bodies.indices {
            for j in (i + 1)..<bodies.count {
                let dx = bodies[j].p.x - bodies[i].p.x, dy = bodies[j].p.y - bodies[i].p.y
                let distance = hypot(dx, dy), minimum = bodies[i].r + bodies[j].r
                guard distance < minimum, distance > 0.001 else { continue }
                let nx = dx / distance, ny = dy / distance
                let overlap = minimum - distance
                let total = bodies[i].mass + bodies[j].mass
                bodies[i].p.x -= nx * overlap * bodies[j].mass / total; bodies[i].p.y -= ny * overlap * bodies[j].mass / total
                bodies[j].p.x += nx * overlap * bodies[i].mass / total; bodies[j].p.y += ny * overlap * bodies[i].mass / total
                let relative = (bodies[i].v.dx - bodies[j].v.dx) * nx + (bodies[i].v.dy - bodies[j].v.dy) * ny
                guard relative > 0 else { continue }
                let impulse = (1 + 0.86) * relative / (1 / bodies[i].mass + 1 / bodies[j].mass)
                bodies[i].v.dx -= impulse / bodies[i].mass * nx; bodies[i].v.dy -= impulse / bodies[i].mass * ny
                bodies[j].v.dx += impulse / bodies[j].mass * nx; bodies[j].v.dy += impulse / bodies[j].mass * ny
                if relative > 120 {
                    let contact = CGPoint(x: bodies[i].p.x + nx * bodies[i].r, y: bodies[i].p.y + ny * bodies[i].r)
                    fx.burst(at: contact, color: Color(red: 0.85, green: 0.75, blue: 0.55), count: 6, speed: 80, gravity: 0, size: 2.5, life: 0.4)
                    SoundFX.play(.hit)
                }
            }
        }
        // Asyks that leave the ring are won; several in one throw pay a growing bonus.
        for i in bodies.indices where bodies[i].dye != nil && !bodies[i].counted {
            let d = hypot(bodies[i].p.x - Self.ringCenter.x, bodies[i].p.y - Self.ringCenter.y)
            guard d > Self.ringRadius + bodies[i].r else { continue }
            bodies[i].out = true; bodies[i].counted = true
            knockedThisShot += 1; knocked += 1
            let alshy = bodies[i].side == 0
            let points = 100 + 50 * (knockedThisShot - 1) + (alshy ? 50 : 0)
            score += points
            let label = knockedThisShot > 1 ? "+\(points) ×\(knockedThisShot)" : "+\(points)"
            fx.popup(alshy ? "\(Self.sideNames[0])! \(label)" : label,
                     at: CGPoint(x: bodies[i].p.x, y: bodies[i].p.y - 18), color: knockedThisShot > 1 ? .orange : .yellow, size: knockedThisShot > 1 ? 20 : 17)
            fx.burst(at: bodies[i].p, color: .yellow, count: 14, speed: 120, gravity: 0, size: 3)
            SoundFX.play(knockedThisShot > 1 ? .merge : .coin); Haptics.success()
        }
    }

    private func endShot() {
        moving = false
        for i in bodies.indices { bodies[i].v = .zero }
        bodies.removeAll { $0.out }
        let remaining = bodies.filter { $0.dye != nil }.count
        if remaining == 0 {
            score += throwsLeft * 75 + 200
            UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: Self.levelKey)
            state = .gameOver(won: true)
        } else if throwsLeft == 0 {
            state = .gameOver(won: false)
        } else {
            if knockedThisShot == 0 { fx.popup(L10n.text("Missed!"), at: CGPoint(x: 180, y: 430), color: .white.opacity(0.8), size: 16) }
            placeSaqa()
        }
    }
}

struct AsykView: View {
    @State private var engine = AsykEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let dyes: [Color] = [Color(red: 0.96, green: 0.9, blue: 0.78), .red, Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.2, green: 0.7, blue: 0.4), .purple]

    var body: some View {
        GameContainerView(gameID: .asyk, engine: engine,
                          resultSummary: L10n.format("Level %d", engine.level),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 10) {
                hud
                GeometryReader { geo in
                    let scale = geo.size.width / AsykEngine.field.width
                    Canvas { context, size in
                        context.scaleBy(x: scale, y: scale)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        draw(&context)
                        engine.fx.draw(in: &context)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let p = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                            let start = CGPoint(x: value.startLocation.x / scale, y: value.startLocation.y / scale)
                            guard let saqa = engine.saqaPosition else { return }
                            if hypot(start.x - saqa.x, start.y - saqa.y) < 46 {
                                engine.updateAim(drag: CGVector(dx: p.x - saqa.x, dy: p.y - saqa.y))
                            } else if start.y > 430 {
                                engine.slide(to: p.x)
                            }
                        }
                        .onEnded { _ in engine.release() })
                }
                .aspectRatio(AsykEngine.field.width / AsykEngine.field.height, contentMode: .fit)
                .frame(maxWidth: 400)
                Text(L10n.text("Swipe from your saqa toward the asyks. Knock them all out of the ring before you run out of throws. Several in one throw earn a bonus."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .id(engine.level)
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
            Menu {
                ForEach(1...AsykEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                Label(L10n.format("Level %d", engine.level), systemImage: "square.grid.3x3")
            }
            Text(L10n.format("Out: %d / %d", engine.knocked, engine.totalAsyks)).monospacedDigit()
            Spacer()
            // One mark per remaining throw.
            HStack(spacing: 4) {
                ForEach(0..<max(engine.throwsLeft, 0), id: \.self) { _ in
                    Capsule().fill(Color(red: 0.85, green: 0.15, blue: 0.2)).frame(width: 16, height: 10)
                        .overlay { Capsule().stroke(Color(red: 1, green: 0.82, blue: 0.3), lineWidth: 1.5) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Throws: %d", engine.throwsLeft))
            .animation(.snappy, value: engine.throwsLeft)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(GameTheme.accent)
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext) {
        let size = AsykEngine.field
        // Packed steppe earth with scattered pebbles and grass.
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.78, green: 0.62, blue: 0.42), Color(red: 0.62, green: 0.46, blue: 0.3)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        for k in 0..<70 {
            let x = CGFloat((k * 137) % 360), y = CGFloat((k * 89 + k * k * 7) % 540)
            if k.isMultiple(of: 3) {
                var tuft = Path()
                for blade in -1...1 { tuft.move(to: CGPoint(x: x, y: y)); tuft.addLine(to: CGPoint(x: x + CGFloat(blade) * 4, y: y - 8)) }
                context.stroke(tuft, with: .color(Color(red: 0.45, green: 0.55, blue: 0.25).opacity(0.7)), lineWidth: 1.5)
            } else {
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3 + CGFloat(k % 3), height: 2 + CGFloat(k % 2))),
                             with: .color(.black.opacity(0.12)))
            }
        }
        // The ring, scratched into the ground.
        let c = AsykEngine.ringCenter, r = AsykEngine.ringRadius
        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        context.fill(ring, with: .color(Color(red: 0.86, green: 0.72, blue: 0.5).opacity(0.5)))
        context.stroke(ring, with: .color(Color(red: 0.4, green: 0.28, blue: 0.16)), lineWidth: 4)
        context.stroke(Path(ellipseIn: CGRect(x: c.x - r + 3, y: c.y - r + 3, width: r * 2 - 6, height: r * 2 - 6)),
                       with: .color(.white.opacity(0.25)), lineWidth: 1.5)
        // The throwing line.
        let y = AsykEngine.playerStart.y - 22
        var throwLine = Path(); throwLine.move(to: CGPoint(x: 24, y: y)); throwLine.addLine(to: CGPoint(x: size.width - 24, y: y))
        context.stroke(throwLine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, dash: [10, 6]))

        if let aim = engine.aim, let saqa = engine.saqaPosition { drawAim(&context, from: saqa, vector: aim) }
        for body in engine.bodies.sorted(by: { ($0.dye == nil ? 1 : 0) < ($1.dye == nil ? 1 : 0) }) { drawPiece(&context, body) }
    }

    private func drawAim(_ context: inout GraphicsContext, from p: CGPoint, vector: CGVector) {
        let length = hypot(vector.dx, vector.dy)
        let power = min(1, length * 8 / 950)
        let unit = CGVector(dx: vector.dx / length, dy: vector.dy / length)
        let tint = Color(hue: 0.33 * (1 - power), saturation: 0.9, brightness: 1)
        for k in 1...9 {
            let t = CGFloat(k) / 9
            let q = CGPoint(x: p.x + unit.dx * (26 + 190 * power * t), y: p.y + unit.dy * (26 + 190 * power * t))
            context.fill(Path(ellipseIn: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)), with: .color(tint.opacity(0.4 + 0.6 * Double(t))))
        }
        context.stroke(Path(ellipseIn: CGRect(x: p.x - 22, y: p.y - 22, width: 44, height: 44)), with: .color(tint.opacity(0.7)), lineWidth: 2)
    }

    /// Top-down knucklebone: a waisted bone shape with knuckles at both ends.
    private func drawPiece(_ context: inout GraphicsContext, _ body: AsykBody) {
        var c = context
        c.translateBy(x: body.p.x, y: body.p.y)
        c.fill(Path(ellipseIn: CGRect(x: -body.r * 0.9, y: -body.r * 0.6 + 3, width: body.r * 1.8, height: body.r * 1.4)), with: .color(.black.opacity(0.25)))
        c.rotate(by: .radians(Double(body.angle)))
        let r = body.r
        var bone = Path()
        bone.addEllipse(in: CGRect(x: -r, y: -r * 0.62, width: r * 0.95, height: r * 1.24))
        bone.addEllipse(in: CGRect(x: r * 0.05, y: -r * 0.62, width: r * 0.95, height: r * 1.24))
        bone.addRoundedRect(in: CGRect(x: -r * 0.55, y: -r * 0.42, width: r * 1.1, height: r * 0.84), cornerSize: CGSize(width: 3, height: 3))
        let base: Color = body.dye.map { Self.dyes[$0] } ?? Color(red: 0.85, green: 0.15, blue: 0.2)
        c.fill(bone, with: .linearGradient(Gradient(colors: [base.opacity(0.75), base, base.opacity(0.85)]),
                                          startPoint: CGPoint(x: 0, y: -r), endPoint: CGPoint(x: 0, y: r)))
        c.fill(Path(ellipseIn: CGRect(x: -r * 0.7, y: -r * 0.5, width: r * 0.6, height: r * 0.35)), with: .color(.white.opacity(0.35)))
        // The face that lands up: a hollow for бүк/шік, a ridge for алшы/тәйкі.
        if body.side >= 2 {
            c.fill(Path(ellipseIn: CGRect(x: -r * 0.25, y: -r * 0.22, width: r * 0.5, height: r * 0.44)), with: .color(.black.opacity(0.22)))
        } else {
            var ridge = Path(); ridge.move(to: CGPoint(x: -r * 0.45, y: body.side == 0 ? -r * 0.1 : r * 0.1)); ridge.addLine(to: CGPoint(x: r * 0.45, y: body.side == 0 ? -r * 0.1 : r * 0.1))
            c.stroke(ridge, with: .color(.black.opacity(0.25)), lineWidth: 1.5)
        }
        if body.dye == nil { c.stroke(bone, with: .color(Color(red: 1, green: 0.82, blue: 0.3)), lineWidth: 2) }
    }
}
