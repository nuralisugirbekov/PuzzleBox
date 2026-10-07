import SwiftUI
import Observation

enum ActionMode: String {
    case circleJump, dash, darkTiles, redGreen, perfectTiming, bubblePop, whackMole, avoid, zigZag, chainReaction, orbit
    var id: GameID {
        switch self {
        case .circleJump: .circleJump
        case .dash: .dash
        case .darkTiles: .darkTiles
        case .redGreen: .redGreen
        case .perfectTiming: .perfectTiming
        case .bubblePop: .bubblePop
        case .whackMole: .whackMole
        case .avoid: .avoid
        case .zigZag: .zigZag
        case .chainReaction: .chainReaction
        case .orbit: .orbit
        }
    }
    var hint: String {
        switch self {
        case .circleJump: "Tap to jump over obstacles on the circle."
        case .dash: "Tap to jump over the spikes."
        case .darkTiles: "Tap the dark tile in the lowest row. Avoid white."
        case .redGreen: "Tap to advance only on green. Reach the finish."
        case .perfectTiming: "Tap when the marker is inside the zone."
        case .bubblePop: "Pop bubbles before they disappear."
        case .whackMole: "Tap the target before it hides."
        case .avoid: "Drag the dot to dodge incoming objects."
        case .zigZag: "Tap to turn. Stay on the zigzag path."
        case .chainReaction: "One tap. Destroy at least 20 of the 30 balls."
        case .orbit: "Tap to change orbit and avoid obstacles."
        }
    }
}

struct ActionParticle: Identifiable {
    let id = UUID()
    var p: CGPoint
    var v: CGVector = .zero
    var radius: CGFloat = 10
    var age: Double = 0
    var life: Double = 3
    var kind = 0
}

@MainActor
@Observable
final class ActionCollectionEngine: GameEngine {
    let mode: ActionMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    var active = false
    private(set) var timeLeft = 30.0
    private(set) var lives = 5
    private(set) var player = CGPoint(x: 160, y: 360)
    private(set) var particles: [ActionParticle] = []
    private(set) var blasts: [ActionParticle] = []
    private(set) var tiles: [Int] = []
    private(set) var angle: CGFloat = 0
    private(set) var altitude: CGFloat = 0
    private var jumpSpeed: CGFloat = 0
    private(set) var signal = 1 // green, yellow, red = 1, 2, 0
    private(set) var progress = 0
    private(set) var zone: CGFloat = 150
    private(set) var marker: CGFloat = 25
    private(set) var mole: Int?
    private(set) var usedTap = false
    private(set) var outerOrbit = false
    private(set) var path: [CGPoint] = []
    private(set) var direction: CGFloat = 1
    private var elapsed = 0.0
    private var spawnIn = 0.0
    private var cooldown = 0.0
    private var markerDirection: CGFloat = 1
    private var angleTravel: CGFloat = 0
    private var pathSegment = 0
    private var travelled: CGFloat = 0

    init(mode: ActionMode) { self.mode = mode; restart() }
    var timed: Bool { [.darkTiles, .redGreen, .bubblePop, .whackMole, .avoid].contains(mode) }
    var jumpPosition: CGPoint {
        CGPoint(x: 160 + cos(angle) * (105 + altitude), y: 215 + sin(angle) * (105 + altitude))
    }
    var orbitPosition: CGPoint {
        let r: CGFloat = outerOrbit ? 125 : 75
        return CGPoint(x: 160 + cos(angle) * r, y: 220 + sin(angle) * r)
    }
    func restart() {
        state = .playing; score = 0; started = false; timeLeft = 30; lives = 5
        player = CGPoint(x: 160, y: 360); particles = []; blasts = []; tiles = []
        angle = 0; altitude = 0; jumpSpeed = 0; signal = 1; progress = 0
        zone = CGFloat.random(in: 80...240); marker = 25; mole = nil; usedTap = false
        outerOrbit = false; elapsed = 0; spawnIn = 1; cooldown = 0; markerDirection = 1
        angleTravel = 0; pathSegment = 0; travelled = 0; direction = 1
        switch mode {
        case .darkTiles: tiles = (0..<4).map { _ in Int.random(in: 0..<4) }
        case .circleJump:
            particles = [1.6, 3.7, 5.3].map { ActionParticle(p: .zero, radius: 12, life: 0, kind: Int($0 * 1000)) }
        case .orbit:
            for (a, lane) in [(1.8, 0), (3.2, 1), (4.6, 0), (5.7, 1)] {
                particles.append(ActionParticle(p: .zero, radius: 11, age: a, life: 0, kind: lane))
            }
        case .chainReaction:
            for _ in 0..<30 {
                let heading = CGFloat.random(in: 0...(.pi * 2)), speed = CGFloat.random(in: 25...65)
                particles.append(ActionParticle(p: CGPoint(x: CGFloat.random(in: 15...305), y: CGFloat.random(in: 25...435)),
                                                v: CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed), radius: 6))
            }
        case .zigZag:
            player = CGPoint(x: 160, y: 370)
            path = [player]
            for i in 1...12 {
                let last = path.last!
                let length = min(CGFloat.random(in: 65...100), i.isMultiple(of: 2) ? last.x - 45 : 275 - last.x)
                path.append(CGPoint(x: last.x + (i.isMultiple(of: 2) ? -length : length), y: last.y - length))
            }
        case .dash: player = CGPoint(x: 65, y: 372)
        default: break
        }
    }
    private func lose() { state = .gameOver(won: false); Haptics.error() }
    private func hit(_ points: Int = 10) { score += points; Haptics.tap() }
    private func miss() { lives -= 1; Haptics.error(); if lives <= 0 { lose() } }
    private func wrapped(_ x: CGFloat) -> CGFloat {
        let y = x.truncatingRemainder(dividingBy: 2 * .pi)
        return y < 0 ? y + 2 * .pi : y
    }
    private func gap(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = wrapped(a - b); return min(d, 2 * .pi - d)
    }
    func drag(_ p: CGPoint) {
        guard active, started, state == .playing, mode == .avoid else { return }
        player = CGPoint(x: min(310, max(10, p.x)), y: min(450, max(10, p.y)))
        if particles.contains(where: { hypot($0.p.x - player.x, $0.p.y - player.y) < $0.radius + 8 }) { lose() }
    }
    func tap(_ p: CGPoint) {
        guard active, state == .playing else { return }
        if !started { started = true; return }
        guard cooldown <= 0 else { return }
        switch mode {
        case .circleJump, .dash:
            if altitude <= 0 { jumpSpeed = mode == .dash ? 350 : 240 }
        case .darkTiles:
            let col = Int(p.x / 80), row = Int((p.y - 20) / 100)
            guard p.y >= 20, row == 3, (0..<4).contains(col) else { return }
            if col != tiles[3] { lose() }
            else { hit(); tiles.removeLast(); tiles.insert(Int.random(in: 0..<4), at: 0) }
        case .redGreen:
            if signal != 1 { lose() }
            else { progress += 1; hit(); cooldown = 0.15; if progress == 30 { state = .gameOver(won: true) } }
        case .perfectTiming:
            let half = max(12, 30 - CGFloat(progress))
            if abs(marker - zone) > half { lose() }
            else {
                progress += 1; hit(); zone = CGFloat.random(in: 65...255); cooldown = 0.3
                if progress == 10 { state = .gameOver(won: true) }
            }
        case .bubblePop:
            if let i = particles.lastIndex(where: { hypot($0.p.x - p.x, $0.p.y - p.y) < $0.radius + 6 }) {
                particles.remove(at: i); hit()
            }
        case .whackMole:
            let c = Int(p.x / 106.66), r = Int((p.y - 60) / 110)
            guard p.y >= 60, (0..<3).contains(c), (0..<3).contains(r) else { return }
            if mole == r * 3 + c { mole = nil; hit(); spawnIn = 0.2 } else { miss() }
        case .avoid: break
        case .zigZag: direction *= -1; cooldown = 0.09
        case .chainReaction:
            guard !usedTap else { return }
            usedTap = true; blasts.append(ActionParticle(p: p, radius: 2, life: 2.5)); hit(0)
        case .orbit:
            outerOrbit.toggle(); cooldown = 0.12
            checkOrbit()
        }
    }
    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        var rest = min(0.1, max(0, dt))
        while rest > 0, state == .playing {
            let step = min(rest, 1.0 / 120); update(step); rest -= step
        }
    }
    private func update(_ dt: Double) {
        elapsed += dt; spawnIn -= dt; cooldown = max(0, cooldown - dt)
        if timed {
            timeLeft = max(0, timeLeft - dt)
            if timeLeft == 0 { state = .gameOver(won: mode != .redGreen || progress >= 30); return }
        }
        let step = CGFloat(dt)
        switch mode {
        case .circleJump, .dash:
            if altitude > 0 || jumpSpeed > 0 { jumpSpeed -= (mode == .dash ? 800 : 620) * step; altitude = max(0, altitude + jumpSpeed * step) }
            if mode == .circleJump {
                let speed = 1.1 + CGFloat(score) / 800
                angleTravel += speed * step; angle = wrapped(angleTravel)
                for b in particles {
                    if gap(angle, CGFloat(b.kind) / 1000) < 0.16 && altitude < 22 { lose(); return }
                }
                let completed = Int(angleTravel / (2 * .pi)) * 30
                if completed > score { score = completed }
            } else {
                if spawnIn <= 0 {
                    particles.append(ActionParticle(p: CGPoint(x: 345, y: 382), radius: CGFloat.random(in: 15...26)))
                    spawnIn = Double.random(in: 1.6...2.1)
                }
                for i in particles.indices { particles[i].p.x -= (145 + CGFloat(score) / 10) * step }
                if particles.contains(where: { abs($0.p.x - player.x) < $0.radius + 10 && altitude < $0.radius * 2 - 4 }) { lose(); return }
                let passed = particles.filter { $0.p.x < -30 }.count
                particles.removeAll { $0.p.x < -30 }; if passed > 0 { hit(passed * 10) }
            }
        case .redGreen:
            if spawnIn <= 0 {
                if signal == 1 { signal = 2; spawnIn = 0.55 }
                else if signal == 2 { signal = 0; spawnIn = Double.random(in: 1...2.3) }
                else { signal = 1; spawnIn = Double.random(in: 1.5...3) }
            }
        case .perfectTiming:
            marker += markerDirection * CGFloat(160 + progress * 13) * step
            if marker > 295 { marker = 295; markerDirection = -1 }
            if marker < 25 { marker = 25; markerDirection = 1 }
        case .bubblePop:
            if spawnIn <= 0 {
                particles.append(ActionParticle(p: CGPoint(x: CGFloat.random(in: 32...288), y: CGFloat.random(in: 45...410)), radius: 25, life: 2.2))
                spawnIn = max(0.3, 0.65 - Double(score) / 1500)
            }
            for i in particles.indices { particles[i].age += dt }
            let missed = particles.filter { $0.age >= $0.life }.count
            particles.removeAll { $0.age >= $0.life }
            if missed > 0 { for _ in 0..<missed { miss() } }
        case .whackMole:
            if spawnIn <= 0 {
                if mole != nil { miss() }
                mole = Int.random(in: 0..<9); spawnIn = max(0.48, 1.1 - Double(score) / 700)
            }
        case .avoid:
            if spawnIn <= 0 {
                let p = CGPoint(x: CGFloat.random(in: 0...320), y: -15)
                let dx = player.x - p.x, dy = player.y - p.y, distance = max(1, hypot(dx, dy))
                let speed = CGFloat.random(in: 85...145)
                particles.append(ActionParticle(p: p, v: CGVector(dx: dx / distance * speed, dy: dy / distance * speed), radius: 8))
                spawnIn = max(0.16, 0.6 - elapsed / 80)
            }
            for i in particles.indices { particles[i].p.x += particles[i].v.dx * step; particles[i].p.y += particles[i].v.dy * step }
            particles.removeAll { $0.p.y > 490 || $0.p.x < -40 || $0.p.x > 360 }
            if particles.contains(where: { hypot($0.p.x - player.x, $0.p.y - player.y) < $0.radius + 8 }) { lose() }
            score = Int(elapsed) * 10
        case .zigZag:
            let speed: CGFloat = 60 + min(35, CGFloat(score) / 100)
            player.x += direction * speed * step; player.y -= speed * step
            // Distance to the polyline, not its bounding box, defines the safe path.
            let distance = zip(path, path.dropFirst()).map { a, b -> CGFloat in
                let dx = b.x - a.x, dy = b.y - a.y
                let t = min(1, max(0, ((player.x - a.x) * dx + (player.y - a.y) * dy) / (dx * dx + dy * dy)))
                return hypot(player.x - a.x - t * dx, player.y - a.y - t * dy)
            }.min() ?? 100
            if distance > 16 { lose(); return }
            travelled += speed * step; score = Int(travelled / 10)
            if player.y < 320 {
                let offset = 320 - player.y; player.y = 320
                for i in path.indices { path[i].y += offset }
                while path.count > 2 && path[1].y > 510 { path.removeFirst(); pathSegment += 1 }
                while (path.last?.y ?? 0) > -120 {
                    let last = path.last!, prior = path[path.count - 2]
                    let sign: CGFloat = last.x > prior.x ? -1 : 1
                    let length = min(CGFloat.random(in: 65...95), sign > 0 ? 275 - last.x : last.x - 45)
                    path.append(CGPoint(x: last.x + sign * length, y: last.y - length))
                }
            }
        case .chainReaction: updateChain(dt)
        case .orbit:
            angleTravel += (1.1 + CGFloat(score) / 550) * step; angle = wrapped(angleTravel)
            checkOrbit()
            score = Int(angleTravel / (2 * .pi)) * 30
        case .darkTiles: break
        }
    }
    private func checkOrbit() {
        for obstacle in particles where obstacle.kind == (outerOrbit ? 1 : 0) {
            if gap(angle, CGFloat(obstacle.age)) < 0.19 { lose(); return }
        }
    }
    private func updateChain(_ dt: Double) {
        for i in particles.indices {
            particles[i].p.x += particles[i].v.dx * CGFloat(dt); particles[i].p.y += particles[i].v.dy * CGFloat(dt)
            if particles[i].p.x < 6 { particles[i].p.x = 6; particles[i].v.dx = abs(particles[i].v.dx) }
            if particles[i].p.x > 314 { particles[i].p.x = 314; particles[i].v.dx = -abs(particles[i].v.dx) }
            if particles[i].p.y < 6 { particles[i].p.y = 6; particles[i].v.dy = abs(particles[i].v.dy) }
            if particles[i].p.y > 454 { particles[i].p.y = 454; particles[i].v.dy = -abs(particles[i].v.dy) }
        }
        for i in blasts.indices {
            blasts[i].age += dt
            let age = blasts[i].age
            blasts[i].radius = CGFloat(age < 0.5 ? age / 0.5 * 43 : age < 1.7 ? 43 : max(0, (2.5 - age) / 0.8 * 43))
        }
        let hitIDs = Set(particles.filter { ball in blasts.contains { hypot($0.p.x - ball.p.x, $0.p.y - ball.p.y) < $0.radius + ball.radius } }.map(\.id))
        for ball in particles where hitIDs.contains(ball.id) { blasts.append(ActionParticle(p: ball.p, radius: 2, life: 2.5)); score += 10; progress += 1 }
        particles.removeAll { hitIDs.contains($0.id) }; blasts.removeAll { $0.age >= $0.life }
        if usedTap && blasts.isEmpty { state = .gameOver(won: progress >= 20) }
    }
}
