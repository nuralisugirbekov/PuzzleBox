import SwiftUI
import Observation

enum MotionMode: String, CaseIterable {
    case slope, keepItUp, wallJump, circlePong, spaceDodge, laneSwitch, gravityFlip, cannonShot, endlessClimb, drift
    var gameID: GameID { GameID(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .slope: "Slope"
        case .keepItUp: "Keep It Up"
        case .wallJump: "Wall Jump"
        case .circlePong: "Circle Pong"
        case .spaceDodge: "Space Dodge"
        case .laneSwitch: "Lane Switch"
        case .gravityFlip: "Gravity Flip"
        case .cannonShot: "Cannon Shot"
        case .endlessClimb: "Endless Climb"
        case .drift: "Drift"
        }
    }
    var hint: String {
        switch self {
        case .slope: "Drag sideways to steer the rolling ball around holes."
        case .keepItUp: "Tap the ball to keep it in the air."
        case .wallJump: "Jump between walls automatically. Tap to switch height and dodge spikes."
        case .circlePong: "Drag around the circle to catch the ball with your paddle."
        case .spaceDodge: "Drag the ship with one finger to dodge asteroids."
        case .laneSwitch: "Swipe left or right to change lanes and avoid barriers."
        case .gravityFlip: "Tap to flip gravity and run along the floor or ceiling."
        case .cannonShot: "Tap when the rotating cannon points at the next cannon."
        case .endlessClimb: "Drag sideways. Jump onto platforms and keep climbing."
        case .drift: "Hold to turn right; release to go straight. Follow the road."
        }
    }
}

struct MotionObstacle: Identifiable {
    let id = UUID()
    var p: CGPoint
    var size: CGSize
    var velocity: CGVector = .zero
    var counted = false
    var kind = 0
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
    private(set) var angle: CGFloat = -.pi / 2
    private(set) var paddle: CGFloat = .pi / 2
    private(set) var lane = 1
    private(set) var gravity: CGFloat = 1
    private(set) var loaded = true
    private(set) var cannon = CGPoint(x: 160, y: 350)
    private(set) var target = CGPoint(x: 160, y: 130)
    private(set) var road: [CGPoint] = []
    private(set) var distance: CGFloat = 0
    var active = false
    private var holding = false
    private var spawn = 0.0
    private var elapsed = 0.0
    private var cooldown = 0.0
    private var flightTime = 0.0
    private var cannonPhase: CGFloat = 0
    private var heightLane = 0
    private var desiredY: CGFloat = 275
    private var wallDirection: CGFloat = 1
    private var driftPosition: CGFloat = 0
    private var driftHeading: CGFloat = 0
    private let trackRadius: CGFloat = 155
    private let trackStraight: CGFloat = 230
    init(mode: MotionMode) { self.mode = mode; restart() }
    var lapLength: CGFloat { 2 * trackStraight + 2 * .pi * trackRadius }
    var driftRate: CGFloat { (90 + min(45, CGFloat(score) / 30)) / trackRadius }
    var trackProgress: CGFloat { driftPosition }
    func restart() {
        state = .playing; score = 0; started = false; holding = false
        player = CGPoint(x: 160, y: 365); velocity = .zero; obstacles = []
        angle = -.pi / 2; paddle = .pi / 2; lane = 1; gravity = 1
        loaded = true; cannon = CGPoint(x: 160, y: 350); target = CGPoint(x: CGFloat.random(in: 65...255), y: 120)
        distance = 0; spawn = 1; elapsed = 0; cooldown = 0; flightTime = 0
        cannonPhase = 0; heightLane = 0; desiredY = 275; wallDirection = 1
        driftPosition = 0; driftHeading = 0; road = []
        switch mode {
        case .keepItUp: player = CGPoint(x: 160, y: 190); velocity = CGVector(dx: 35, dy: -100)
        case .wallJump: player = CGPoint(x: 28, y: 275)
        case .circlePong: player = CGPoint(x: 160, y: 230); velocity = CGVector(dx: 65, dy: 140)
        case .gravityFlip: player = CGPoint(x: 70, y: 390)
        case .cannonShot: player = cannon; updateAim()
        case .endlessClimb:
            player = CGPoint(x: 160, y: 355); velocity.dy = -320
            obstacles = (0..<7).map { i in MotionObstacle(p: CGPoint(x: i == 0 ? 160 : CGFloat.random(in: 75...245), y: 390 - CGFloat(i) * 65), size: CGSize(width: 95, height: 10)) }
        case .drift:
            player = trackPoint(0); angle = 0
            road = stride(from: CGFloat(0), through: lapLength, by: 8).map { trackPoint($0) }
            road.append(trackPoint(0))
        default: break
        }
    }
    func release() { holding = false }
    func touch(_ p: CGPoint) {
        guard active, started, state == .playing else { return }
        switch mode {
        case .slope, .endlessClimb: player.x = min(287, max(33, p.x))
        case .spaceDodge: player = CGPoint(x: min(307, max(13, p.x)), y: min(442, max(18, p.y)))
        case .circlePong: paddle = atan2(p.y - 230, p.x - 160)
        case .drift: holding = true
        default: break
        }
    }
    func input(_ p: CGPoint, swipe: CGFloat) {
        holding = false
        guard active, state == .playing else { return }
        if !started { started = true; return }
        guard cooldown <= 0 else { return }
        switch mode {
        case .keepItUp:
            if hypot(player.x - p.x, player.y - p.y) < 48 {
                velocity.dy = -320; velocity.dx = min(110, max(-110, (player.x - p.x) * 5)); score += 10; cooldown = 0.12; Haptics.tap()
            }
        case .wallJump: heightLane = 1 - heightLane; desiredY = heightLane == 0 ? 275 : 160; cooldown = 0.12
        case .laneSwitch:
            if abs(swipe) > 18 { lane = min(2, max(0, lane + (swipe > 0 ? 1 : -1))); player.x = CGFloat(lane) * 90 + 70 }
        case .gravityFlip: gravity *= -1; cooldown = 0.15
        case .cannonShot:
            if loaded { loaded = false; player = cannon; velocity = CGVector(dx: cos(angle) * 270, dy: sin(angle) * 270); flightTime = 0 }
        default: break
        }
    }
    func advance(_ dt: Double) {
        guard active, started, state == .playing else { holding = false; return }
        var remainder = min(0.08, max(0, dt))
        while remainder > 0 && state == .playing {
            let step = min(remainder, 1.0 / 120); update(step); remainder -= step
        }
    }
    private func lose() { state = .gameOver(won: false); holding = false }
    private func update(_ dt: Double) {
        let d = CGFloat(dt)
        elapsed += dt; cooldown = max(0, cooldown - dt); spawn -= dt
        switch mode {
        case .slope, .spaceDodge, .laneSwitch:
            let speed: CGFloat = 110 + min(140, CGFloat(score) / 8)
            distance += speed * d; score = Int(distance / 12)
            if spawn <= 0 {
                if mode == .slope {
                    obstacles.append(MotionObstacle(p: CGPoint(x: CGFloat.random(in: 60...260), y: -35), size: CGSize(width: CGFloat.random(in: 55...100), height: 45)))
                } else if mode == .laneSwitch {
                    // One blocked lane per row leaves enough room for one-lane swipes.
                    obstacles.append(MotionObstacle(p: CGPoint(x: CGFloat(Int.random(in: 0...2)) * 90 + 70, y: -30), size: CGSize(width: 63, height: 30)))
                } else {
                    let radius = CGFloat.random(in: 13...23)
                    obstacles.append(MotionObstacle(p: CGPoint(x: CGFloat.random(in: 20...300), y: -30), size: CGSize(width: radius * 2, height: radius * 2), velocity: CGVector(dx: CGFloat.random(in: -25...25), dy: 0)))
                }
                spawn = mode == .spaceDodge ? 0.55 : 0.9
            }
            for i in obstacles.indices { obstacles[i].p.y += speed * d; obstacles[i].p.x += obstacles[i].velocity.dx * d }
            obstacles.removeAll { $0.p.y > 500 }
            for obstacle in obstacles {
                if mode == .spaceDodge {
                    if hypot(player.x - obstacle.p.x, player.y - obstacle.p.y) < 10 + obstacle.size.width / 2 { lose() }
                } else if obstacle.rect.insetBy(dx: -9, dy: -9).contains(player) { lose() }
            }
        case .keepItUp:
            velocity.dy += 420 * d; player.x += velocity.dx * d; player.y += velocity.dy * d
            if player.x < 18 { player.x = 18; velocity.dx = abs(velocity.dx) }
            if player.x > 302 { player.x = 302; velocity.dx = -abs(velocity.dx) }
            if player.y < 18 { player.y = 18; velocity.dy = max(0, velocity.dy) }
            if player.y > 448 { lose() }
        case .wallJump:
            player.x += wallDirection * (105 + min(65, CGFloat(score) / 10)) * d
            player.y += min(1, d * 9) * (desiredY - player.y)
            if obstacles.isEmpty { wallSpike(at: 292) }
            if player.x >= 292 || player.x <= 28 {
                if obstacles.contains(where: { abs($0.p.x - player.x) < 30 && abs($0.p.y - player.y) < 48 }) { lose(); return }
                player.x = wallDirection > 0 ? 292 : 28; wallDirection *= -1; score += 10
                wallSpike(at: wallDirection > 0 ? 292 : 28)
            }
        case .circlePong:
            player.x += velocity.dx * d; player.y += velocity.dy * d
            let dx = player.x - 160, dy = player.y - 230, radius = hypot(dx, dy)
            if radius >= 124 {
                let normal = CGVector(dx: dx / radius, dy: dy / radius)
                let dot = velocity.dx * normal.dx + velocity.dy * normal.dy
                if dot > 0 {
                    let a = atan2(dy, dx)
                    let delta = atan2(sin(a - paddle), cos(a - paddle))
                    guard abs(delta) <= 0.34 else { lose(); return }
                    velocity.dx -= 2 * dot * normal.dx; velocity.dy -= 2 * dot * normal.dy
                    let turn: CGFloat = CGFloat.random(in: -0.14...0.14)
                    let x = velocity.dx; velocity.dx = x * cos(turn) - velocity.dy * sin(turn); velocity.dy = x * sin(turn) + velocity.dy * cos(turn)
                    let scale = min(1.035, 280 / max(1, hypot(velocity.dx, velocity.dy)))
                    velocity.dx *= scale; velocity.dy *= scale
                    player = CGPoint(x: 160 + normal.dx * 123, y: 230 + normal.dy * 123); score += 10
                }
            }
        case .gravityFlip:
            velocity.dy = min(300, max(-300, velocity.dy + gravity * 1000 * d))
            player.y += velocity.dy * d
            if player.y <= 70 { player.y = 70; velocity.dy = 0 }
            if player.y >= 390 { player.y = 390; velocity.dy = 0 }
            if spawn <= 0 {
                obstacles.append(MotionObstacle(p: CGPoint(x: 345, y: Bool.random() ? 80 : 380), size: CGSize(width: 35, height: 55)))
                spawn = 1.8
            }
            for i in obstacles.indices {
                obstacles[i].p.x -= (135 + min(70, CGFloat(score) / 8)) * d
                if obstacles[i].p.x < 40 && !obstacles[i].counted { obstacles[i].counted = true; score += 10 }
                if obstacles[i].rect.insetBy(dx: -10, dy: -10).contains(player) { lose() }
            }
            obstacles.removeAll { $0.p.x < -40 }
        case .cannonShot:
            if loaded { cannonPhase += d * (1.3 + min(1.4, CGFloat(score) / 150)); updateAim() }
            else {
                flightTime += dt; player.x += velocity.dx * d; player.y += velocity.dy * d
                if hypot(player.x - target.x, player.y - target.y) < 22 {
                    score += 25; loaded = true; cannon = CGPoint(x: target.x, y: 350); player = cannon
                    target = CGPoint(x: CGFloat.random(in: 50...270), y: CGFloat.random(in: 90...160))
                    cannonPhase = -.pi / 2; updateAim(); Haptics.success()
                } else if player.x < -20 || player.x > 340 || player.y < -20 || player.y > 480 || flightTime > 3 { lose() }
            }
        case .endlessClimb:
            let previousY = player.y
            velocity.dy += 520 * d; player.y += velocity.dy * d
            if velocity.dy > 0 {
                for platform in obstacles where abs(player.x - platform.p.x) < platform.size.width / 2 + 8 {
                    if previousY + 10 <= platform.p.y && player.y + 10 >= platform.p.y {
                        player.y = platform.p.y - 10; velocity.dy = -320; break
                    }
                }
            }
            if player.y < 220 {
                let shift = 220 - player.y; player.y = 220; distance += shift; score = Int(distance / 10)
                for i in obstacles.indices { obstacles[i].p.y += shift }
                obstacles.removeAll { $0.p.y > 490 }
                while let top = obstacles.min(by: { $0.p.y < $1.p.y }), top.p.y > -40 {
                    let x = min(255, max(65, top.p.x + CGFloat.random(in: -95...95)))
                    obstacles.append(MotionObstacle(p: CGPoint(x: x, y: top.p.y - 65), size: CGSize(width: 85, height: 10)))
                }
            }
            if player.y > 480 { lose() }
        case .drift:
            let speed = 90 + min(45, CGFloat(score) / 30)
            if holding { driftHeading += driftRate * d }
            player.x += cos(driftHeading) * speed * d; player.y += sin(driftHeading) * speed * d
            // Nearest point to the closed stadium track controls both safety and progress.
            let nearest = nearestTrackPoint(player)
            if nearest.distance > 29 { lose(); return }
            var delta = nearest.progress - driftPosition
            if delta < -lapLength / 2 { delta += lapLength }
            if delta > lapLength / 2 { delta -= lapLength }
            distance = max(0, distance + delta); driftPosition = nearest.progress; score = Int(distance / 10)
            angle = driftHeading
        }
    }
    private func wallSpike(at x: CGFloat) {
        obstacles = [MotionObstacle(p: CGPoint(x: x, y: Bool.random() ? 160 : 275), size: CGSize(width: 30, height: 70))]
    }
    private func updateAim() { angle = atan2(target.y - cannon.y, target.x - cannon.x) + sin(cannonPhase) * 0.85 }
    func trackPoint(_ progress: CGFloat) -> CGPoint {
        let s = progress.truncatingRemainder(dividingBy: lapLength), r = trackRadius, length = trackStraight
        if s < length { return CGPoint(x: s, y: 0) }
        if s < length + .pi * r { let a = (s - length) / r - .pi / 2; return CGPoint(x: length + cos(a) * r, y: r + sin(a) * r) }
        if s < 2 * length + .pi * r { return CGPoint(x: length - (s - length - .pi * r), y: 2 * r) }
        let a = (s - 2 * length - .pi * r) / r + .pi / 2
        return CGPoint(x: cos(a) * r, y: r + sin(a) * r)
    }
    private func nearestTrackPoint(_ p: CGPoint) -> (distance: CGFloat, progress: CGFloat) {
        // Sampling at two world units keeps the error below the road tolerance.
        var best: CGFloat = .greatestFiniteMagnitude, progress: CGFloat = 0
        for s in stride(from: CGFloat(0), to: lapLength, by: 2) {
            let q = trackPoint(s), d = hypot(p.x - q.x, p.y - q.y)
            if d < best { best = d; progress = s }
        }
        return (best, progress)
    }
}
