import SwiftUI
import Observation

/// Coordinates are in a fixed 320 × 480 playfield, independent of device size.
enum ArcadeMode: String, CaseIterable {
    case stack, knifeSpin, helixDrop, flappyFlight, roadHop

    var gameID: GameID {
        switch self {
        case .stack: .stack
        case .knifeSpin: .knifeSpin
        case .helixDrop: .helixDrop
        case .flappyFlight: .flappyFlight
        case .roadHop: .roadHop
        }
    }
    var hint: String {
        switch self {
        case .stack: "Tap to stack. Perfect drops keep the block whole, and three in a row make it grow."
        case .knifeSpin: "Tap to throw. Avoid the other pins and slice apples for bonus points."
        case .helixDrop: "Drag sideways to rotate. Fall through three gaps in a row to smash the next floor."
        case .flappyFlight: "Tap to fly through the gaps and grab the coins."
        case .roadHop: "Swipe to hop. Tap to move forward. Avoid traffic and grab coins."
        }
    }
}

/// A Stack block in world space: a footprint on the x–z floor at a level.
/// Levels are `StackSlab.height` tall; level 0 is the plinth.
struct StackSlab: Identifiable {
    static let height: CGFloat = 16
    let id = UUID()
    var x: CGFloat, z: CGFloat, w: CGFloat, d: CGFloat
    var level: Int
    var hue: Double
    /// Cut-off pieces fall: how far they have dropped, how fast, and which way they drift.
    var drop: CGFloat = 0
    var fall: CGFloat = 0
    var drift: CGVector = .zero
}

struct ArcadeBody: Identifiable {
    let id = UUID()
    var rect: CGRect
    var value = 0
    var speed: CGFloat = 0
    var counted = false
    /// Mode-specific extras: hue for colouring, phase/baseY for oscillation, vx/spin for debris.
    var hue: Double = 0
    var phase: CGFloat = 0
    var baseY: CGFloat = 0
    var vx: CGFloat = 0
}

@MainActor
@Observable
final class ArcadeEngine: GameEngine {
    let mode: ArcadeMode
    private(set) var score = 0
    var state: GameState = .playing
    private(set) var started = false
    var active = false
    private(set) var player = CGPoint(x: 160, y: 400)
    private(set) var velocity = CGVector.zero
    private(set) var bodies: [ArcadeBody] = []
    private(set) var debris: [ArcadeBody] = []
    private(set) var coins: [CGPoint] = []
    private(set) var angle: CGFloat = 0
    private(set) var fx = ArcadeFX()
    /// Seconds since the round started; drives idle animations.
    private(set) var time: CGFloat = 0

    // Knife Spin
    private(set) var pins: [CGFloat] = []
    private(set) var apples: [CGFloat] = []
    private(set) var projectile: CGFloat?
    private(set) var level = 1
    private(set) var remainingPins = 7
    private(set) var totalPins = 7
    private(set) var targetKick: CGFloat = 0
    private(set) var levelIntro: CGFloat = 0
    private var spinClock: CGFloat = 0
    var isBossLevel: Bool { level.isMultiple(of: 5) }

    // Stack
    static let stackSize: CGFloat = 120
    /// How far the sliding block travels past the tower on either side.
    private static let stackReach: CGFloat = 150
    private(set) var slabs: [StackSlab] = []
    private(set) var stackDebris: [StackSlab] = []
    /// Offset of the sliding block from the top of the tower, along `stackAlongX` or z.
    private(set) var slide: CGFloat = -150
    private var direction: CGFloat = 1
    private(set) var placed = 0
    private(set) var perfectStreak = 0
    /// The level the view is centred on; eases up to `placed`.
    private(set) var stackCamera: CGFloat = 0
    private(set) var ripple: (slab: StackSlab, t: CGFloat)?
    /// Blocks slide along x on even turns and along z on odd ones.
    var stackAlongX: Bool { placed.isMultiple(of: 2) }
    var stackHue: Double { Self.stackHue(placed) }
    static func stackHue(_ level: Int) -> Double { (0.52 + Double(level) * 0.031).truncatingRemainder(dividingBy: 1) }

    /// The block in play, sliding over the top of the tower.
    var movingSlab: StackSlab? {
        guard let top = slabs.last else { return nil }
        var slab = top
        slab.level = top.level + 1
        slab.hue = Self.stackHue(placed + 1)
        if stackAlongX { slab.x += slide } else { slab.z += slide }
        return slab
    }

    /// World point to the 320×480 canvas, isometric, with the camera on the top.
    func stackScreen(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let c: CGFloat = 0.866, s: CGFloat = 0.5
        return CGPoint(x: 160 + (x - z) * c,
                       y: 250 + (x + z) * s - (y - stackCamera * StackSlab.height))
    }

    // Helix Drop
    private(set) var combo = 0
    private var helixSpawned = 0
    var fireball: Bool { mode == .helixDrop && combo >= 3 }

    // Flappy Flight
    private(set) var scroll: CGFloat = 0
    private(set) var flap: CGFloat = 0
    private var pipesSpawned = 0
    private var pipesPassed = 0

    // Road Hop
    private var roadRow = 0
    private var furthestRoadRow = 0
    private(set) var hopTimer: CGFloat = 0
    private(set) var facing: CGFloat = -1

    private var cooldown: Double = 0
    private var emitClock: CGFloat = 0
    private var previousDrag: CGFloat?
    private(set) var flash = 0.0

    init(mode: ArcadeMode) { self.mode = mode; restart() }

    func restart() {
        state = .playing; score = 0; started = false
        player = CGPoint(x: 160, y: 400); velocity = .zero
        bodies = []; debris = []; coins = []; pins = []; apples = []; projectile = nil
        angle = 0; level = 1; remainingPins = 7; totalPins = 7; targetKick = 0; levelIntro = 0; spinClock = 0
        fx.reset(); time = 0
        cooldown = 0; flash = 0; emitClock = 0
        direction = 1; previousDrag = nil
        slabs = []; stackDebris = []; slide = -Self.stackReach
        placed = 0; perfectStreak = 0; stackCamera = 0; ripple = nil
        combo = 0; helixSpawned = 0
        scroll = 0; flap = 0; pipesSpawned = 0; pipesPassed = 0
        roadRow = 0; furthestRoadRow = 0; hopTimer = 0; facing = -1
        switch mode {
        case .stack:
            // A tall plinth so the tower never seems to float.
            let half = Self.stackSize / 2
            slabs = (-4...0).map { StackSlab(x: -half, z: -half, w: Self.stackSize, d: Self.stackSize, level: $0, hue: Self.stackHue(0)) }
        case .flappyFlight:
            player = CGPoint(x: 78, y: 240)
            addPipe(x: 380); addPipe(x: 580)
        case .helixDrop:
            player = CGPoint(x: 160, y: 130)
            for i in 0..<7 { addHelixPlatform(y: 220 + CGFloat(i) * 85) }
        case .roadHop:
            player = CGPoint(x: 160, y: 430)
            for lane in 1...7 { addLane(row: lane) }
        case .knifeSpin:
            setupKnifeLevel()
        }
    }

    var roadProgress: Int { furthestRoadRow }

    private func lose(at point: CGPoint? = nil, color: Color = .red) {
        if let point {
            fx.burst(at: point, color: color, count: 26, speed: 220, size: 3.5, life: 0.8)
            fx.burst(at: point, color: .white, count: 10, speed: 160, size: 2)
        }
        fx.kick(9); fx.flash(.red, 0.3)
        state = .gameOver(won: false); Haptics.error()
    }
    private func reward(_ points: Int, sound: SoundFX.Sound? = .point) {
        score += points; flash = 0.18; Haptics.tap()
        if let sound { SoundFX.play(sound) }
    }

    private func wrap(_ value: CGFloat, period: CGFloat = 320) -> CGFloat {
        let result = value.truncatingRemainder(dividingBy: period)
        return result < 0 ? result + period : result
    }
    private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let value = wrap(a - b, period: .pi * 2)
        return min(value, .pi * 2 - value)
    }

    func tap() {
        guard state == .playing, active else { return }
        if !started {
            started = true
            if mode == .flappyFlight { flapUp() }
            return
        }
        switch mode {
        case .stack: placeBlock()
        case .knifeSpin:
            if projectile == nil, cooldown <= 0 { projectile = 425; SoundFX.play(.whoosh) }
        case .flappyFlight: flapUp()
        case .roadHop: hop(dx: 0, dy: -1)
        default: break
        }
    }

    func drag(x: CGFloat) {
        guard state == .playing, active, started else { return }
        switch mode {
        case .helixDrop:
            if let previousDrag {
                let delta = x - previousDrag
                for i in bodies.indices { bodies[i].rect.origin.x = wrap(bodies[i].rect.minX + delta) }
            }
            previousDrag = x
        default: break
        }
    }
    func endDrag() { previousDrag = nil }

    /// Small fixed steps prevent fast objects from tunnelling through obstacles.
    func advance(_ elapsed: Double) {
        guard active, started, state == .playing else { return }
        let total = min(0.1, max(0, elapsed))
        var remaining = total
        while remaining > 0, state == .playing {
            let step = min(remaining, 1.0 / 120)
            update(CGFloat(step)); remaining -= step
        }
        time += CGFloat(total)
        fx.update(CGFloat(total))
    }
    private func update(_ dt: CGFloat) {
        cooldown = max(0, cooldown - Double(dt)); flash = max(0, flash - Double(dt))
        switch mode {
        case .stack: updateStack(dt)
        case .knifeSpin: updateKnife(dt)
        case .helixDrop: updateHelix(dt)
        case .flappyFlight: updateFlappy(dt)
        case .roadHop: updateRoad(dt)
        }
    }

    // MARK: Stack

    private func updateStack(_ dt: CGFloat) {
        slide += direction * (105 + min(CGFloat(placed) * 4.5, 190)) * dt
        if slide > Self.stackReach { slide = Self.stackReach; direction = -1 }
        if slide < -Self.stackReach { slide = -Self.stackReach; direction = 1 }
        for i in stackDebris.indices {
            stackDebris[i].fall += 520 * dt
            stackDebris[i].drop += stackDebris[i].fall * dt
            stackDebris[i].x += stackDebris[i].drift.dx * dt
            stackDebris[i].z += stackDebris[i].drift.dy * dt
        }
        stackDebris.removeAll { $0.drop > 700 }
        stackCamera += (CGFloat(placed) - stackCamera) * min(1, dt * 6)
        if let current = ripple {
            ripple = current.t + dt > 0.5 ? nil : (current.slab, current.t + dt)
        }
    }

    private func placeBlock() {
        guard let top = slabs.last, var slab = movingSlab else { return }
        let alongX = stackAlongX
        let blockColor = Color(hue: slab.hue, saturation: 0.6, brightness: 0.95)
        // Positions along the sliding axis.
        let topMin = alongX ? top.x : top.z, length = alongX ? top.w : top.d
        let slabMin = alongX ? slab.x : slab.z
        let center = stackScreen(slab.x + slab.w / 2, CGFloat(slab.level + 1) * StackSlab.height, slab.z + slab.d / 2)

        if abs(slabMin - topMin) < 4.5 {
            // Perfect drop: snap onto the tower; a streak of three or more regrows the block.
            perfectStreak += 1
            if alongX { slab.x = top.x } else { slab.z = top.z }
            if perfectStreak >= 3 {
                let gw = min(10, Self.stackSize - slab.w), gd = min(10, Self.stackSize - slab.d)
                slab.x -= gw / 2; slab.w += gw
                slab.z -= gd / 2; slab.d += gd
            }
            let bonus = 5 * min(perfectStreak, 6)
            score += 10 + bonus; flash = 0.18
            ripple = (slab, 0)
            let label = perfectStreak > 1 ? L10n.text("Perfect!") + " ×\(perfectStreak)" : L10n.text("Perfect!")
            fx.popup(label, at: CGPoint(x: center.x, y: center.y - 30), color: .white, size: 18)
            fx.burst(at: center, color: blockColor, count: 14, speed: 140, gravity: 200)
            if perfectStreak >= 3 { Haptics.success(); SoundFX.play(.coin) } else { Haptics.move(); SoundFX.play(.pop) }
        } else {
            let low = max(slabMin, topMin), high = min(slabMin + length, topMin + length)
            guard high > low else {
                var miss = slab
                miss.drift = alongX ? CGVector(dx: direction * 60, dy: 0) : CGVector(dx: 0, dy: direction * 60)
                stackDebris.append(miss)
                lose(at: center, color: blockColor)
                return
            }
            perfectStreak = 0
            // The overhang breaks off and falls; the rest stays on the tower.
            for (from, to, sign) in [(slabMin, low, -1.0), (high, slabMin + length, 1.0)] where to - from > 0.5 {
                var piece = slab
                if alongX { piece.x = from; piece.w = to - from; piece.drift = CGVector(dx: sign * 50, dy: 0) }
                else { piece.z = from; piece.d = to - from; piece.drift = CGVector(dx: 0, dy: sign * 50) }
                stackDebris.append(piece)
            }
            if alongX { slab.x = low; slab.w = high - low } else { slab.z = low; slab.d = high - low }
            reward(10, sound: .place)
        }
        placed += 1
        slabs.append(slab)
        // Only the top of the tower is ever on screen.
        if slabs.count > 40 { slabs.removeFirst(slabs.count - 40) }
        direction = 1; slide = -Self.stackReach
    }

    // MARK: Knife Spin

    private func setupKnifeLevel() {
        pins = []; apples = []
        totalPins = isBossLevel ? min(14, 8 + level / 5) : min(12, 5 + level)
        remainingPins = totalPins
        let preplaced = isBossLevel ? 3 : min(5, (level - 1) / 2)
        for _ in 0..<preplaced {
            if let a = freeAngle(minGap: 0.55) { pins.append(a) }
        }
        let appleCount = level == 1 ? 1 : (isBossLevel ? 3 : Int.random(in: 1...2))
        for _ in 0..<appleCount {
            if let a = freeAngle(minGap: 0.5) { apples.append(a) }
        }
        levelIntro = 0.45
    }

    private func freeAngle(minGap: CGFloat) -> CGFloat? {
        for _ in 0..<40 {
            let a = CGFloat.random(in: 0..<(.pi * 2))
            if pins.allSatisfy({ angularDistance($0, a) > minGap }) && apples.allSatisfy({ angularDistance($0, a) > minGap }) {
                return a
            }
        }
        return nil
    }

    /// Angular velocity: steady early on, wobbling later, and swinging back and forth on boss levels.
    private var spinSpeed: CGFloat {
        let base = 1.1 + CGFloat(min(level, 14)) * 0.12
        let sign: CGFloat = level.isMultiple(of: 2) ? -1 : 1
        if isBossLevel { return base * (1.9 * sin(spinClock * 0.85) + 0.25) }
        if level >= 3 { return sign * base * (0.8 + 0.45 * sin(spinClock * 1.4)) }
        return sign * base
    }

    private func updateKnife(_ dt: CGFloat) {
        spinClock += dt
        angle = wrap(angle + dt * spinSpeed, period: .pi * 2)
        targetKick = max(0, targetKick - dt * 6)
        levelIntro = max(0, levelIntro - dt)
        guard let y = projectile else { return }
        let next = y - dt * 700
        projectile = next
        guard next <= 260 else { return }
        projectile = nil
        let insertion = wrap(.pi / 2 - angle, period: .pi * 2)
        let contact = CGPoint(x: 160, y: 262)
        if pins.contains(where: { angularDistance($0, insertion) < 0.19 }) {
            fx.burst(at: contact, color: .yellow, count: 14, speed: 200, gravity: 500, size: 2.5)
            lose(at: contact, color: .white)
            return
        }
        pins.append(insertion); remainingPins -= 1; targetKick = 1
        reward(10, sound: .hit)
        fx.burst(at: contact, color: Color(red: 0.85, green: 0.6, blue: 0.35), count: 6, speed: 90, gravity: 400, size: 2)
        if let hit = apples.firstIndex(where: { angularDistance($0, insertion) < 0.24 }) {
            apples.remove(at: hit)
            score += 25
            fx.burst(at: CGPoint(x: 160, y: 270), color: .red, count: 16, speed: 170, size: 3)
            fx.burst(at: CGPoint(x: 160, y: 270), color: .green, count: 6, speed: 120, size: 2.5)
            fx.popup("+25", at: CGPoint(x: 200, y: 290), color: .red, size: 18)
            SoundFX.play(.pop); Haptics.move()
        }
        if remainingPins == 0 {
            let bonus = isBossLevel ? 100 : 20
            score += bonus
            fx.burst(at: CGPoint(x: 160, y: 180), color: isBossLevel ? .red : .orange, count: 40, speed: 260, size: 4, life: 0.9)
            fx.flash(.white, 0.25); fx.kick(5)
            fx.popup("+\(bonus)", at: CGPoint(x: 160, y: 180), color: .yellow, size: 22)
            Haptics.success(); SoundFX.play(.clear)
            level += 1
            setupKnifeLevel()
            if isBossLevel { fx.popup(L10n.text("Boss!"), at: CGPoint(x: 160, y: 130), color: .red, size: 26) }
            cooldown = 0.6
        }
    }

    // MARK: Helix Drop

    private func addHelixPlatform(y: CGFloat) {
        let n = helixSpawned
        helixSpawned += 1
        let gap = max(62, 92 - CGFloat(n) * 0.6)
        var red = 0
        if n >= 3 { red = 1 }
        if n >= 18, CGFloat.random(in: 0..<1) < min(0.75, CGFloat(n - 18) * 0.03 + 0.25) { red = 2 }
        // Keep the first platform safe directly under the start position.
        let x = n == 0 ? wrap(160 - gap - 60) : CGFloat.random(in: 0..<320)
        bodies.append(ArcadeBody(rect: CGRect(x: x, y: y, width: gap, height: 12), value: red,
                                 hue: (0.5 + Double(n) * 0.045).truncatingRemainder(dividingBy: 1)))
    }

    /// Relative ranges (0..<320 from the platform's origin) that are deadly.
    func helixRedZones(_ body: ArcadeBody) -> [Range<CGFloat>] {
        var zones: [Range<CGFloat>] = []
        if body.value >= 1 { zones.append(200..<265) }
        if body.value >= 2 { zones.append((body.rect.width + 24)..<(body.rect.width + 64)) }
        return zones
    }

    private func updateHelix(_ dt: CGFloat) {
        let previousY = player.y
        velocity.dy = min(velocity.dy + 600 * dt, 560); player.y += velocity.dy * dt
        if fireball {
            emitClock -= dt
            if emitClock <= 0 {
                emitClock = 0.025
                fx.burst(at: player, color: [Color.orange, .yellow, .red].randomElement()!, count: 2, speed: 40, gravity: -120, size: 4, life: 0.35)
            }
        }
        if velocity.dy > 0 {
            var i = 0
            while i < bodies.count {
                let platform = bodies[i]
                guard previousY + 10 <= platform.rect.minY, player.y + 10 >= platform.rect.minY else { i += 1; continue }
                let relative = wrap(player.x - platform.rect.minX)
                if relative < platform.rect.width {
                    if !bodies[i].counted {
                        bodies[i].counted = true
                        combo += 1
                        let points = 10 * min(combo, 5)
                        reward(points, sound: combo >= 3 ? .whoosh : .point)
                        if combo == 3 {
                            fx.popup(L10n.text("Fireball!"), at: CGPoint(x: 160, y: player.y - 40), color: .orange, size: 22)
                            Haptics.move()
                        } else if combo > 1 {
                            fx.popup("+\(points)", at: CGPoint(x: player.x + 24, y: player.y - 10), color: .yellow)
                        }
                    }
                    i += 1
                } else if fireball {
                    // Smash straight through the floor, even red.
                    let color = Color(hue: platform.hue, saturation: 0.7, brightness: 0.95)
                    bodies.remove(at: i)
                    score += 30
                    fx.burst(at: CGPoint(x: player.x, y: platform.rect.minY), color: color, count: 30, speed: 240, gravity: 500, size: 4, life: 0.7)
                    fx.burst(at: CGPoint(x: player.x, y: platform.rect.minY), color: .orange, count: 12, speed: 160, size: 3)
                    fx.popup(L10n.text("Smash!") + " +30", at: CGPoint(x: 160, y: platform.rect.minY - 20), color: .orange, size: 20)
                    fx.kick(6)
                    combo = 0; velocity.dy = 120
                    Haptics.heavy(); SoundFX.play(.clear)
                    break
                } else if helixRedZones(platform).contains(where: { $0.contains(relative) }) {
                    lose(at: player, color: .red); return
                } else {
                    player.y = platform.rect.minY - 10; velocity.dy = -230; SoundFX.play(.bounce)
                    fx.burst(at: CGPoint(x: player.x, y: platform.rect.minY), color: Color(hue: platform.hue, saturation: 0.6, brightness: 1),
                             count: 6, speed: 90, gravity: 400, size: 2.5, life: 0.4, angles: CGFloat.pi...(2 * .pi))
                    combo = 0
                    break
                }
            }
        }
        if player.y > 250 {
            let offset = player.y - 250; player.y = 250
            for i in bodies.indices { bodies[i].rect.origin.y -= offset }
            bodies.removeAll { $0.rect.maxY < 0 }
            while (bodies.last?.rect.minY ?? 0) < 560 {
                addHelixPlatform(y: (bodies.last?.rect.minY ?? 250) + 85)
            }
        }
    }

    // MARK: Flappy Flight

    private func flapUp() {
        velocity.dy = -235; flap = 1; SoundFX.play(.jump)
        fx.burst(at: CGPoint(x: player.x - 8, y: player.y + 6), color: .white.opacity(0.8), count: 4, speed: 60, gravity: 100, size: 2, life: 0.35,
                 angles: (CGFloat.pi * 0.5)...(CGFloat.pi * 1.1))
    }

    private func addPipe(x: CGFloat) {
        let n = pipesSpawned
        pipesSpawned += 1
        let gap = max(114, 150 - CGFloat(n) * 1.4)
        let center = CGFloat.random(in: 150...330)
        var pipe = ArcadeBody(rect: CGRect(x: x, y: center - gap / 2, width: 52, height: gap), baseY: center)
        if n > 7, CGFloat.random(in: 0..<1) < min(0.55, CGFloat(n - 7) * 0.05) {
            pipe.speed = CGFloat.random(in: 26...46)
            pipe.phase = CGFloat.random(in: 0..<(.pi * 2))
            pipe.baseY = min(330, max(150, center))
        }
        bodies.append(pipe)
        // Coins float between pipes, sometimes off the safe line to tempt a risky move.
        if n > 0, CGFloat.random(in: 0..<1) < 0.6 {
            coins.append(CGPoint(x: x - 74, y: min(400, max(80, center + CGFloat.random(in: -60...60)))))
        }
    }
    private func updateFlappy(_ dt: CGFloat) {
        velocity.dy += 640 * dt; player.y += velocity.dy * dt
        flap = max(0, flap - dt * 4)
        guard player.y > 10, player.y < 462 else { lose(at: player, color: .yellow); return }
        let speed = 110 + min(70, CGFloat(pipesPassed) * 2)
        scroll += speed * dt
        for i in bodies.indices {
            bodies[i].rect.origin.x -= speed * dt
            if bodies[i].speed > 0 {
                bodies[i].phase += dt * 1.6
                bodies[i].rect.origin.y = bodies[i].baseY + sin(bodies[i].phase) * bodies[i].speed - bodies[i].rect.height / 2
            }
            let pipe = bodies[i].rect
            if pipe.minX < player.x + 10, pipe.maxX > player.x - 10,
               player.y - 10 < pipe.minY || player.y + 10 > pipe.maxY {
                lose(at: player, color: .yellow); return
            }
            if !bodies[i].counted, pipe.maxX < player.x {
                bodies[i].counted = true; pipesPassed += 1; reward(10)
            }
        }
        for i in coins.indices { coins[i].x -= speed * dt }
        if let hit = coins.firstIndex(where: { hypot($0.x - player.x, $0.y - player.y) < 20 }) {
            let coin = coins.remove(at: hit)
            score += 5
            fx.burst(at: coin, color: .yellow, count: 10, speed: 110, gravity: 100, size: 2.5)
            fx.popup("+5", at: CGPoint(x: coin.x, y: coin.y - 16), color: .yellow)
            SoundFX.play(.coin); Haptics.tap()
        }
        coins.removeAll { $0.x < -20 }
        bodies.removeAll { $0.rect.maxX < -10 }
        if (bodies.last?.rect.minX ?? 0) < 190 { addPipe(x: (bodies.last?.rect.minX ?? 190) + 200) }
    }

    // MARK: Road Hop

    func hop(dx: Int, dy: Int) {
        guard mode == .roadHop, state == .playing, active, started, cooldown <= 0 else { return }
        let x = player.x + CGFloat(dx) * 40
        guard x >= 20, x <= 300 else { return }
        let nextRow = roadRow - dy
        guard nextRow >= max(0, furthestRoadRow - 3) else { return }
        player.x = x; roadRow = nextRow
        player.y += CGFloat(dy) * 50
        if dx != 0 { facing = CGFloat(dx) }
        cooldown = 0.12; hopTimer = 0.14
        SoundFX.play(.tap)
        if let hit = coins.firstIndex(where: { abs($0.x - player.x) < 20 && abs($0.y - player.y) < 20 }) {
            let coin = coins.remove(at: hit)
            score += 25
            fx.burst(at: coin, color: .yellow, count: 12, speed: 120, gravity: 150, size: 2.5)
            fx.popup("+25", at: CGPoint(x: coin.x, y: coin.y - 18), color: .yellow)
            SoundFX.play(.coin); Haptics.move()
        }
        if roadRow > furthestRoadRow {
            furthestRoadRow = roadRow; reward(10, sound: furthestRoadRow.isMultiple(of: 5) ? .point : nil)
            if furthestRoadRow.isMultiple(of: 10) {
                fx.popup("\(furthestRoadRow)", at: CGPoint(x: player.x, y: player.y - 30), color: GameTheme.accent, size: 22)
            }
            if player.y < 280 {
                player.y += 50
                for i in bodies.indices { bodies[i].rect.origin.y += 50 }
                for i in coins.indices { coins[i].y += 50 }
                bodies.removeAll { $0.rect.minY > 500 }
                coins.removeAll { $0.y > 500 }
                addLane(row: roadRow + 4)
            }
        }
        roadCollision()
    }

    func isGrassRow(_ row: Int) -> Bool { row <= 0 || row % 4 == 0 }
    /// Visible rows, bottom to top, with their centre y.
    var visibleRoadRows: [(row: Int, y: CGFloat)] {
        (roadRow - 4...roadRow + 9).map { ($0, player.y - CGFloat($0 - roadRow) * 50) }
    }

    private func updateRoad(_ dt: CGFloat) {
        hopTimer = max(0, hopTimer - dt)
        for i in bodies.indices {
            bodies[i].rect.origin.x += bodies[i].speed * dt
            if bodies[i].speed > 0, bodies[i].rect.minX > 350 { bodies[i].rect.origin.x -= 450 }
            if bodies[i].speed < 0, bodies[i].rect.maxX < -30 { bodies[i].rect.origin.x += 450 }
        }
        roadCollision()
    }

    private func addLane(row: Int) {
        let y = player.y - CGFloat(row - roadRow) * 50
        if row > 2, CGFloat.random(in: 0..<1) < 0.22 {
            coins.append(CGPoint(x: 40 * CGFloat(Int.random(in: 1...7)), y: y))
        }
        guard !isGrassRow(row) else { return } // Every fourth row is a safe grass strip.
        let truck = row > 8 && CGFloat.random(in: 0..<1) < 0.25
        let base = CGFloat(50 + row % 6 * 13) + min(70, CGFloat(row) * 1.2)
        let speed: CGFloat = (row.isMultiple(of: 2) ? 1 : -1) * base * (truck ? 0.75 : 1)
        let count = !truck && row > 20 && CGFloat.random(in: 0..<1) < 0.4 ? 3 : 2
        let spacing: CGFloat = 450 / CGFloat(count)
        let width: CGFloat = truck ? 100 : 62
        let offset = CGFloat.random(in: -80...20)
        for i in 0..<count {
            bodies.append(ArcadeBody(rect: CGRect(x: offset + CGFloat(i) * spacing, y: y - 16, width: width, height: 32),
                                     value: truck ? -1 : row + i, speed: speed))
        }
    }
    private func roadCollision() {
        let rect = CGRect(x: player.x - 11, y: player.y - 11, width: 22, height: 22)
        if bodies.contains(where: { $0.rect.intersects(rect) }) { lose(at: player, color: GameTheme.accent) }
    }
}

// MARK: - Saved round

extension ArcadeEngine: ResumableGame {
    private struct Session: Codable {
        let score: Int
        let level: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, started, score > 0 || level > 1 else { return nil }
        return encodeSession(Session(score: score, level: level))
    }

    /// Endless runs keep their score on a fresh course; Knife Spin returns
    /// to the start of the saved level. The player taps to start again.
    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data) else { return false }
        restart()
        score = s.score
        if mode == .knifeSpin {
            level = max(1, s.level)
            setupKnifeLevel()
        }
        return true
    }
}
