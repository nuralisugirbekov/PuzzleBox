import SwiftUI
import Observation

enum MotionMode: String, CaseIterable {
    case slope, circlePong, spaceDodge, endlessClimb
    var gameID: GameID { GameID(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .slope: "Slope"
        case .circlePong: "Circle Pong"
        case .spaceDodge: "Space Dodge"
        case .endlessClimb: "Endless Climb"
        }
    }
    var hint: String {
        switch self {
        case .slope: "Drag sideways to steer the rolling ball around holes."
        case .circlePong: "Drag around the circle to catch the ball with your paddle."
        case .spaceDodge: "Drag the ship with one finger to dodge asteroids."
        case .endlessClimb: "Drag sideways. Jump onto platforms and keep climbing."
        }
    }
    /// Second line under the board: what earns the extra points.
    var bonusHint: String {
        switch self {
        case .slope: "Grab gems in a row to build a combo. Blocks start moving as you speed up."
        case .circlePong: "Hit the star with the ball for bonus points. The paddle shrinks as the rally grows."
        case .spaceDodge: "Collect stars for points. A blue shield saves you from one hit."
        case .endlessClimb: "Springs launch you higher. Cracked platforms break after one jump."
        }
    }
}

struct MotionObstacle: Identifiable {
    let id = UUID()
    var p: CGPoint
    var size: CGSize
    var velocity: CGVector = .zero
    var counted = false
    /// Slope: 0 block, 1 sliding block. Climb: 0 plain, 1 moving, 2 cracked, 3 spring.
    /// Pickups: 0 gem/star/coin, 1 shield.
    var kind = 0
    var spin: CGFloat = 0
    var rect: CGRect { CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height) }
}

@MainActor @Observable
final class MotionEngine: GameEngine {
    let mode: MotionMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    private(set) var player = CGPoint(x: 160, y: 365)
    private(set) var velocity = CGVector.zero
    private(set) var obstacles: [MotionObstacle] = []
    private(set) var pickups: [MotionObstacle] = []
    private(set) var trail: [CGPoint] = []
    private(set) var fx = ArcadeFX()

    private(set) var paddle: CGFloat = .pi / 2
    private(set) var rally = 0
    private(set) var combo = 0
    private(set) var shield = false
    private(set) var invulnerable = 0.0
    private(set) var squash: CGFloat = 0

    private(set) var distance: CGFloat = 0
    private(set) var elapsed = 0.0
    var active = false

    private var spawn = 0.0
    private var pickupSpawn = 0.0
    private var shieldSpawn = 0.0
    private var bonus = 0
    private var lastMilestone = 0

    init(mode: MotionMode) { self.mode = mode; restart() }

    /// Paddle half-width in radians; the target narrows as the rally grows.
    var paddleHalfWidth: CGFloat { max(0.2, 0.36 - CGFloat(rally) * 0.006) }

    func restart() {
        state = .playing; score = 0; started = false
        player = CGPoint(x: 160, y: 365); velocity = .zero; obstacles = []; pickups = []; trail = []
        paddle = .pi / 2; rally = 0; combo = 0; shield = false; invulnerable = 0; squash = 0
        distance = 0; spawn = 1; pickupSpawn = 1.6; shieldSpawn = 9; elapsed = 0; bonus = 0; lastMilestone = 0
        fx.reset()

        switch mode {
        case .circlePong:
            player = CGPoint(x: 160, y: 230); velocity = CGVector(dx: 65, dy: 140)
            placePongStar()
        case .endlessClimb:
            player = CGPoint(x: 160, y: 355); velocity.dy = -320
            obstacles = (0..<7).map { i in
                MotionObstacle(p: CGPoint(x: i == 0 ? 160 : CGFloat.random(in: 75...245), y: 390 - CGFloat(i) * 65),
                               size: CGSize(width: 95, height: 10))
            }
        default: break
        }
    }

    func touch(_ p: CGPoint) {
        guard active, started, state == .playing else { return }
        switch mode {
        case .slope, .endlessClimb: player.x = min(287, max(33, p.x))
        case .spaceDodge: player = CGPoint(x: min(307, max(13, p.x)), y: min(442, max(18, p.y)))
        case .circlePong: paddle = atan2(p.y - 230, p.x - 160)
        }
    }
    func start() {
        guard active, state == .playing else { return }
        started = true
    }
    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        let total = min(0.08, max(0, dt))
        var remainder = total
        while remainder > 0 && state == .playing {
            let step = min(remainder, 1.0 / 120); update(step); remainder -= step
        }
        fx.update(CGFloat(total))
        squash = max(0, squash - CGFloat(total) * 5)
        trail.append(player)
        if trail.count > 14 { trail.removeFirst() }
    }

    private func lose() {
        fx.burst(at: player, color: GameTheme.accent, count: 30, speed: 220, size: 3.5, life: 0.8)
        fx.burst(at: player, color: .white, count: 12, speed: 150, size: 2)
        fx.kick(9); fx.flash(.red, 0.3)
        Haptics.error()
        state = .gameOver(won: false)
    }

    private func addBonus(_ points: Int, at p: CGPoint, color: Color = .yellow) {
        bonus += points
        fx.popup("+\(points)", at: CGPoint(x: p.x, y: p.y - 14), color: color)
        fx.burst(at: p, color: color, count: 10, speed: 120, gravity: 120, size: 2.5, life: 0.5)
    }

    /// Distance-based score plus collected bonuses; a short chime every 100 points.
    private func refreshScore(divisor: CGFloat) {
        score = Int(distance / divisor) + bonus
        let milestone = Int(distance / divisor) / 100
        if milestone > lastMilestone {
            lastMilestone = milestone
            SoundFX.play(.point)
            fx.popup("\(milestone * 100)", at: CGPoint(x: 160, y: 90), color: .white.opacity(0.8), size: 26)
        }
    }

    private func update(_ dt: Double) {
        let d = CGFloat(dt)
        elapsed += dt; spawn -= dt; pickupSpawn -= dt; shieldSpawn -= dt
        invulnerable = max(0, invulnerable - dt)
        switch mode {
        case .slope: updateSlope(d)
        case .spaceDodge: updateSpace(d)
        case .circlePong: updatePong(d)
        case .endlessClimb: updateClimb(d)
        }
    }

    // MARK: Slope

    private var runSpeed: CGFloat { 110 + min(150, distance / 60) }

    private func updateSlope(_ d: CGFloat) {
        let speed = runSpeed
        distance += speed * d
        if spawn <= 0 {
            var block = MotionObstacle(p: CGPoint(x: CGFloat.random(in: 60...260), y: -35),
                                       size: CGSize(width: CGFloat.random(in: 55...100), height: 45))
            // Faster runs bring sideways-sliding blocks.
            if distance > 1800, CGFloat.random(in: 0..<1) < min(0.5, (distance - 1800) / 6000 + 0.2) {
                block.kind = 1
                block.velocity.dx = (Bool.random() ? 1 : -1) * CGFloat.random(in: 40...75)
            }
            obstacles.append(block)
            spawn = max(0.55, 0.9 - Double(distance) / 12000)
        }
        if pickupSpawn <= 0 {
            let x = CGFloat.random(in: 50...270)
            if !obstacles.contains(where: { abs($0.p.x - x) < $0.size.width / 2 + 20 && $0.p.y < 40 }) {
                pickups.append(MotionObstacle(p: CGPoint(x: x, y: -20), size: CGSize(width: 18, height: 18)))
            }
            pickupSpawn = Double.random(in: 0.8...1.4)
        }
        for i in obstacles.indices {
            obstacles[i].p.y += speed * d
            if obstacles[i].kind == 1 {
                obstacles[i].p.x += obstacles[i].velocity.dx * d
                let half = obstacles[i].size.width / 2
                if obstacles[i].p.x < 22 + half || obstacles[i].p.x > 298 - half { obstacles[i].velocity.dx *= -1 }
            }
        }
        for i in pickups.indices { pickups[i].p.y += speed * d; pickups[i].spin += d * 3 }
        obstacles.removeAll { $0.p.y > 500 }
        if pickups.contains(where: { $0.p.y > 480 }) { combo = 0 }
        pickups.removeAll { $0.p.y > 480 }
        collectPickups(radius: 22) { _ in
            combo += 1
            let points = 10 * min(combo, 5)
            return (points, combo >= 2 ? "×\(combo)" : nil)
        }
        refreshScore(divisor: 12)
        for obstacle in obstacles where obstacle.rect.insetBy(dx: -9, dy: -9).contains(player) { lose(); return }
    }

    // MARK: Space Dodge

    private func updateSpace(_ d: CGFloat) {
        let speed = runSpeed
        distance += speed * d
        if spawn <= 0 {
            let small = distance > 1200 && Bool.random()
            let radius = small ? CGFloat.random(in: 9...13) : CGFloat.random(in: 15...25)
            let drift = small ? CGFloat.random(in: -70...70) : CGFloat.random(in: -25...25)
            obstacles.append(MotionObstacle(p: CGPoint(x: CGFloat.random(in: 20...300), y: -30),
                                            size: CGSize(width: radius * 2, height: radius * 2),
                                            velocity: CGVector(dx: drift, dy: small ? speed * 0.5 : 0),
                                            kind: Int.random(in: 0..<3), spin: CGFloat.random(in: 0..<(.pi * 2))))
            spawn = max(0.32, 0.55 - Double(distance) / 15000)
        }
        if pickupSpawn <= 0 {
            pickups.append(MotionObstacle(p: CGPoint(x: CGFloat.random(in: 30...290), y: -20), size: CGSize(width: 18, height: 18)))
            pickupSpawn = Double.random(in: 1.0...1.8)
        }
        if shieldSpawn <= 0 {
            if !shield { pickups.append(MotionObstacle(p: CGPoint(x: CGFloat.random(in: 40...280), y: -20), size: CGSize(width: 22, height: 22), kind: 1)) }
            shieldSpawn = Double.random(in: 12...18)
        }
        for i in obstacles.indices {
            obstacles[i].p.y += (speed + obstacles[i].velocity.dy) * d
            obstacles[i].p.x += obstacles[i].velocity.dx * d
            obstacles[i].spin += obstacles[i].velocity.dx * 0.01 * d + 0.4 * d
        }
        for i in pickups.indices { pickups[i].p.y += speed * 0.8 * d; pickups[i].spin += d * 3 }
        obstacles.removeAll { $0.p.y > 500 }
        pickups.removeAll { $0.p.y > 480 }
        collectPickups(radius: 24) { pickup in
            if pickup.kind == 1 {
                shield = true
                fx.popup(L10n.text("Shield!"), at: CGPoint(x: player.x, y: player.y - 30), color: .cyan, size: 18)
                return (0, nil)
            }
            return (25, nil)
        }
        refreshScore(divisor: 12)
        guard invulnerable == 0 else { return }
        if let hit = obstacles.firstIndex(where: { hypot(player.x - $0.p.x, player.y - $0.p.y) < 10 + $0.size.width / 2 }) {
            if shield {
                let rock = obstacles.remove(at: hit)
                shield = false; invulnerable = 1
                fx.burst(at: rock.p, color: .gray, count: 20, speed: 180, gravity: 0, size: 3)
                fx.burst(at: player, color: .cyan, count: 16, speed: 140, gravity: 0, size: 2.5)
                fx.kick(5); Haptics.heavy(); SoundFX.play(.hit)
            } else {
                lose()
            }
        }
    }

    // MARK: Circle Pong

    private func placePongStar() {
        let angle = CGFloat.random(in: 0..<(.pi * 2)), radius = CGFloat.random(in: 25...85)
        pickups = [MotionObstacle(p: CGPoint(x: 160 + cos(angle) * radius, y: 230 + sin(angle) * radius), size: CGSize(width: 20, height: 20))]
    }

    private func updatePong(_ d: CGFloat) {
        player.x += velocity.dx * d; player.y += velocity.dy * d
        for i in pickups.indices { pickups[i].spin += d * 2 }
        if let star = pickups.first, hypot(star.p.x - player.x, star.p.y - player.y) < 20 {
            combo += 1
            addBonus(20 + 10 * min(combo, 5), at: star.p)
            SoundFX.play(.coin); Haptics.move()
            placePongStar()
        }
        score = bonus
        let dx = player.x - 160, dy = player.y - 230, radius = hypot(dx, dy)
        guard radius >= 124 else { return }
        let normal = CGVector(dx: dx / radius, dy: dy / radius)
        let dot = velocity.dx * normal.dx + velocity.dy * normal.dy
        guard dot > 0 else { return }
        let a = atan2(dy, dx)
        let delta = atan2(sin(a - paddle), cos(a - paddle))
        guard abs(delta) <= paddleHalfWidth else { lose(); return }
        velocity.dx -= 2 * dot * normal.dx; velocity.dy -= 2 * dot * normal.dy
        // Hitting off-centre angles the return, so aiming at the star is a real skill.
        let turn = -delta * 0.9 + CGFloat.random(in: -0.08...0.08)
        let x = velocity.dx
        velocity.dx = x * cos(turn) - velocity.dy * sin(turn); velocity.dy = x * sin(turn) + velocity.dy * cos(turn)
        let speed = min(320, hypot(velocity.dx, velocity.dy) * 1.03)
        let current = max(1, hypot(velocity.dx, velocity.dy))
        velocity.dx *= speed / current; velocity.dy *= speed / current
        player = CGPoint(x: 160 + normal.dx * 123, y: 230 + normal.dy * 123)
        rally += 1
        bonus += 10
        score = bonus
        fx.burst(at: player, color: GameTheme.accent, count: 8, speed: 110, gravity: 0, size: 2.5, life: 0.4)
        if rally.isMultiple(of: 10) {
            fx.popup(L10n.format("Rally %d!", rally), at: CGPoint(x: 160, y: 200), color: .white, size: 22)
            SoundFX.play(.clear)
        } else {
            SoundFX.play(.bounce)
        }
        Haptics.tap()
    }

    // MARK: Endless Climb

    private func climbPlatform(at y: CGFloat, above top: MotionObstacle) -> MotionObstacle {
        let x = min(255, max(65, top.p.x + CGFloat.random(in: -95...95)))
        var platform = MotionObstacle(p: CGPoint(x: x, y: y), size: CGSize(width: 85, height: 10))
        let height = distance
        let roll = CGFloat.random(in: 0..<1)
        if height > 2500, roll < 0.18 { platform.kind = 2 }
        else if height > 900, roll < 0.42 {
            platform.kind = 1
            platform.velocity.dx = (Bool.random() ? 1 : -1) * CGFloat.random(in: 40...70 + min(60, height / 100))
        } else if roll > 0.9 { platform.kind = 3 }
        if platform.kind != 2, CGFloat.random(in: 0..<1) < 0.3 {
            pickups.append(MotionObstacle(p: CGPoint(x: x, y: y - 26), size: CGSize(width: 16, height: 16), velocity: platform.velocity))
        }
        // Narrower footholds the higher you climb.
        platform.size.width = max(62, 85 - height / 250)
        return platform
    }

    private func updateClimb(_ d: CGFloat) {
        let previousY = player.y
        velocity.dy += 520 * d; player.y += velocity.dy * d
        for i in obstacles.indices where obstacles[i].kind == 1 {
            obstacles[i].p.x += obstacles[i].velocity.dx * d
            if obstacles[i].p.x < 50 || obstacles[i].p.x > 270 { obstacles[i].velocity.dx *= -1 }
        }
        for i in pickups.indices {
            pickups[i].p.x += pickups[i].velocity.dx * d
            if pickups[i].p.x < 50 || pickups[i].p.x > 270 { pickups[i].velocity.dx *= -1 }
            pickups[i].spin += d * 3
        }
        if velocity.dy > 0 {
            for (index, platform) in obstacles.enumerated() where abs(player.x - platform.p.x) < platform.size.width / 2 + 8 {
                guard previousY + 10 <= platform.p.y && player.y + 10 >= platform.p.y else { continue }
                player.y = platform.p.y - 10
                squash = 1
                switch platform.kind {
                case 3:
                    velocity.dy = -540
                    fx.burst(at: CGPoint(x: player.x, y: platform.p.y), color: .yellow, count: 12, speed: 140, gravity: 300, size: 2.5)
                    SoundFX.play(.whoosh); Haptics.move()
                case 2:
                    velocity.dy = -320
                    fx.burst(at: platform.p, color: Color(red: 0.75, green: 0.55, blue: 0.35), count: 18, speed: 120, gravity: 500, size: 3)
                    obstacles.remove(at: index)
                    SoundFX.play(.hit)
                default:
                    velocity.dy = -320
                    SoundFX.play(.jump)
                }
                break
            }
        }
        collectPickups(radius: 20) { _ in (15, nil) }
        if player.y < 220 {
            let shift = 220 - player.y; player.y = 220; distance += shift
            for i in obstacles.indices { obstacles[i].p.y += shift }
            for i in pickups.indices { pickups[i].p.y += shift }
            obstacles.removeAll { $0.p.y > 490 }
            pickups.removeAll { $0.p.y > 490 }
            while let top = obstacles.min(by: { $0.p.y < $1.p.y }), top.p.y > -40 {
                obstacles.append(climbPlatform(at: top.p.y - 65, above: top))
            }
        }
        refreshScore(divisor: 10)
        if player.y > 480 { lose() }
    }

    // MARK: Pickups

    private func collectPickups(radius: CGFloat, reward: (MotionObstacle) -> (Int, String?)) {
        guard let index = pickups.firstIndex(where: { hypot($0.p.x - player.x, $0.p.y - player.y) < radius }) else { return }
        let pickup = pickups.remove(at: index)
        let (points, label) = reward(pickup)
        if points > 0 {
            addBonus(points, at: pickup.p, color: mode == .spaceDodge ? .white : .yellow)
            SoundFX.play(.coin)
        } else {
            fx.burst(at: pickup.p, color: .cyan, count: 14, speed: 120, gravity: 0, size: 2.5)
            SoundFX.play(.win)
        }
        if let label { fx.popup(label, at: CGPoint(x: pickup.p.x + 22, y: pickup.p.y - 26), color: .orange, size: 15) }
        Haptics.tap()
    }
}
