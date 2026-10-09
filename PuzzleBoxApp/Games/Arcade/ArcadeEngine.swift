import SwiftUI
import Observation

/// Coordinates are in a fixed 320 × 480 playfield, independent of device size.
enum ArcadeMode: String, CaseIterable {
    case stack, colorJump, knifeSpin, helixDrop, skyJump, flappyFlight, brickBreaker, pong, roadHop

    var gameID: GameID {
        switch self {
        case .stack: .stack
        case .colorJump: .colorJump
        case .knifeSpin: .knifeSpin
        case .helixDrop: .helixDrop
        case .skyJump: .skyJump
        case .flappyFlight: .flappyFlight
        case .brickBreaker: .brickBreaker
        case .pong: .pong
        case .roadHop: .roadHop
        }
    }
    var hint: String {
        switch self {
        case .stack: "Tap to stack. Overhanging pieces fall away."
        case .colorJump: "Tap to jump. Cross only your ball’s color."
        case .knifeSpin: "Tap to throw. Avoid the other pins."
        case .helixDrop: "Drag sideways to rotate. Find gaps and avoid red."
        case .skyJump: "Drag sideways to land on platforms."
        case .flappyFlight: "Tap to fly through the gaps."
        case .brickBreaker: "Drag to move the paddle and break every brick."
        case .pong: "Drag your paddle. First to 7 wins."
        case .roadHop: "Swipe to hop. Tap to move forward. Avoid traffic."
        }
    }
}

struct ArcadeBody: Identifiable {
    let id = UUID()
    var rect: CGRect
    var value = 0
    var speed: CGFloat = 0
    var counted = false
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
    private(set) var angle: CGFloat = 0
    private(set) var colorIndex = 0
    private(set) var pins: [CGFloat] = []
    private(set) var projectile: CGFloat?
    private(set) var level = 1
    private(set) var remainingPins = 7
    private(set) var paddle: CGFloat = 160
    private(set) var opponent: CGFloat = 160
    private(set) var opponentScore = 0
    private(set) var lives = 3
    private(set) var bestHeight: CGFloat = 0
    private(set) var climbed: CGFloat = 0
    private var movingX: CGFloat = 20
    private(set) var blockWidth: CGFloat = 180
    private var direction: CGFloat = 1
    private var cooldown: Double = 0
    private var spawnClock: Double = 0
    private var colorGateY: CGFloat = 240
    private var ballWasAbove = false
    private var roadRow = 0
    private var furthestRoadRow = 0
    private var previousDrag: CGFloat?
    private(set) var flash = 0.0

    init(mode: ArcadeMode) { self.mode = mode; restart() }

    func restart() {
        state = .playing; score = 0; started = false
        player = CGPoint(x: 160, y: 400); velocity = .zero
        bodies = []; debris = []; pins = []; projectile = nil
        angle = 0; colorIndex = Int.random(in: 0..<4); level = 1; remainingPins = 7
        paddle = 160; opponent = 160; opponentScore = 0; lives = 3
        climbed = 0; bestHeight = 0; cooldown = 0; spawnClock = 0; flash = 0
        movingX = 0; blockWidth = 180; direction = 1; previousDrag = nil
        colorGateY = 240; ballWasAbove = false; roadRow = 0; furthestRoadRow = 0
        switch mode {
        case .stack:
            bodies = [ArcadeBody(rect: CGRect(x: 70, y: 420, width: 180, height: 22))]
        case .skyJump:
            bodies = [ArcadeBody(rect: CGRect(x: 110, y: 440, width: 100, height: 12))]
            for i in 0..<7 { bodies.append(platform(y: 375 - CGFloat(i) * 65)) }
            velocity.dy = -330
        case .brickBreaker:
            for r in 0..<5 {
                for c in 0..<6 {
                    bodies.append(ArcadeBody(rect: CGRect(x: CGFloat(10 + c * 51), y: CGFloat(42 + r * 25), width: 45, height: 18), value: r))
                }
            }
            player = CGPoint(x: 160, y: 415); velocity = CGVector(dx: 120, dy: -230)
        case .pong:
            player = CGPoint(x: 160, y: 240); serve()
        case .flappyFlight:
            player = CGPoint(x: 78, y: 240)
            addPipe(x: 380); addPipe(x: 580)
        case .helixDrop:
            player = CGPoint(x: 160, y: 130)
            for i in 0..<7 {
                bodies.append(ArcadeBody(rect: CGRect(x: CGFloat.random(in: 0..<320), y: 220 + CGFloat(i) * 85, width: 88, height: 12), value: i % 4))
            }
        case .roadHop:
            player = CGPoint(x: 160, y: 430)
            for lane in 1...7 { addLane(row: lane) }
        case .colorJump, .knifeSpin: break
        }
    }

    var movingBlock: CGRect {
        CGRect(x: movingX, y: (bodies.last?.rect.minY ?? 420) - 24, width: blockWidth, height: 22)
    }
    var gateY: CGFloat { colorGateY }
    var roadProgress: Int { furthestRoadRow }

    private func lose() { state = .gameOver(won: false); Haptics.error() }
    private func reward(_ points: Int) { score += points; flash = 0.18; Haptics.tap() }
    private func platform(y: CGFloat) -> ArcadeBody {
        ArcadeBody(rect: CGRect(x: CGFloat.random(in: 10...235), y: y, width: 75, height: 12))
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
            if mode == .flappyFlight { velocity.dy = -235 }
            return
        }
        switch mode {
        case .stack: placeBlock()
        case .colorJump: velocity.dy = -245
        case .knifeSpin:
            if projectile == nil, cooldown <= 0 { projectile = 425 }
        case .flappyFlight: velocity.dy = -235
        case .roadHop: hop(dx: 0, dy: -1)
        default: break
        }
    }

    func drag(x: CGFloat) {
        guard state == .playing, active, started else { return }
        switch mode {
        case .brickBreaker, .pong: paddle = min(278, max(42, x))
        case .skyJump: player.x = min(309, max(11, x))
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
    func hop(dx: Int, dy: Int) {
        guard mode == .roadHop, state == .playing, active, started, cooldown <= 0 else { return }
        let x = player.x + CGFloat(dx) * 40
        guard x >= 20, x <= 300 else { return }
        let nextRow = roadRow - dy
        guard nextRow >= max(0, furthestRoadRow - 3) else { return }
        player.x = x; roadRow = nextRow
        player.y += CGFloat(dy) * 50
        cooldown = 0.12
        if roadRow > furthestRoadRow {
            furthestRoadRow = roadRow; reward(10)
            if player.y < 280 {
                player.y += 50
                for i in bodies.indices { bodies[i].rect.origin.y += 50 }
                bodies.removeAll { $0.rect.minY > 500 }
                addLane(row: roadRow + 4)
            }
        }
        roadCollision()
    }

    /// Small fixed steps prevent fast objects from tunnelling through obstacles.
    func advance(_ elapsed: Double) {
        guard active, started, state == .playing else { return }
        var remaining = min(0.1, max(0, elapsed))
        while remaining > 0, state == .playing {
            let step = min(remaining, 1.0 / 120)
            update(CGFloat(step)); remaining -= step
        }
    }
    private func update(_ dt: CGFloat) {
        cooldown = max(0, cooldown - Double(dt)); flash = max(0, flash - Double(dt))
        switch mode {
        case .stack:
            movingX += direction * CGFloat(105 + min(score, 250)) * dt
            if movingX < 0 { movingX = 0; direction = 1 }
            if movingX + blockWidth > 320 { movingX = 320 - blockWidth; direction = -1 }
            for i in debris.indices { debris[i].speed += 700 * dt; debris[i].rect.origin.y += debris[i].speed * dt }
            debris.removeAll { $0.rect.minY > 500 }
        case .colorJump: updateColor(dt)
        case .knifeSpin: updateKnife(dt)
        case .helixDrop: updateHelix(dt)
        case .skyJump: updateSky(dt)
        case .flappyFlight: updateFlappy(dt)
        case .brickBreaker: updateBall(dt, pong: false)
        case .pong: updateBall(dt, pong: true)
        case .roadHop:
            for i in bodies.indices {
                bodies[i].rect.origin.x += bodies[i].speed * dt
                if bodies[i].speed > 0, bodies[i].rect.minX > 350 { bodies[i].rect.origin.x = -100 }
                if bodies[i].speed < 0, bodies[i].rect.maxX < -30 { bodies[i].rect.origin.x = 350 }
            }
            roadCollision()
        }
    }

    private func placeBlock() {
        guard let base = bodies.last else { return }
        var rect = movingBlock
        if abs(rect.minX - base.rect.minX) < 5 { rect.origin.x = base.rect.minX }
        let left = max(rect.minX, base.rect.minX), right = min(rect.maxX, base.rect.maxX)
        guard right > left else { lose(); return }
        if rect.minX < left { debris.append(ArcadeBody(rect: CGRect(x: rect.minX, y: rect.minY, width: left - rect.minX, height: 22))) }
        if rect.maxX > right { debris.append(ArcadeBody(rect: CGRect(x: right, y: rect.minY, width: rect.maxX - right, height: 22))) }
        rect.origin.x = left; rect.size.width = right - left; blockWidth = rect.width
        bodies.append(ArcadeBody(rect: rect, value: bodies.count % 6)); reward(10)
        if rect.minY < 190 {
            for i in bodies.indices { bodies[i].rect.origin.y += 24 }
            for i in debris.indices { debris[i].rect.origin.y += 24 }
            bodies.removeAll { $0.rect.minY > 480 }
        }
        direction *= -1; movingX = direction > 0 ? 0 : 320 - blockWidth
    }

    private func updateColor(_ dt: CGFloat) {
        angle = wrap(angle + dt * 1.3, period: .pi * 2)
        let oldY = player.y
        velocity.dy += 530 * dt; player.y += velocity.dy * dt
        if player.y > 450 { player.y = 450; velocity.dy = 0 }
        if !ballWasAbove {
            // A horizontal rotating-color gate; check every substep while the ball overlaps it.
            if abs(player.y - colorGateY) <= 16 {
                let segment = Int(wrap(player.x + angle * 70) / 80)
                if segment != colorIndex { lose(); return }
            }
            if oldY >= colorGateY - 18, player.y < colorGateY - 18 {
                ballWasAbove = true; reward(10)
            }
        } else if player.y < colorGateY - 40 {
            player.y += 150
            colorIndex = (colorIndex + Int.random(in: 1...3)) % 4
            ballWasAbove = false
        }
    }

    private func updateKnife(_ dt: CGFloat) {
        angle = wrap(angle + dt * (1.1 + CGFloat(level) * 0.18) * (level.isMultiple(of: 2) ? -1 : 1), period: .pi * 2)
        guard let y = projectile else { return }
        projectile = y - dt * 650
        if projectile! <= 260 {
            let insertion = wrap(.pi / 2 - angle, period: .pi * 2)
            if pins.contains(where: { angularDistance($0, insertion) < 0.19 }) { projectile = nil; lose(); return }
            pins.append(insertion); projectile = nil; remainingPins -= 1; reward(10)
            if remainingPins == 0 {
                level += 1; remainingPins = min(13, 6 + level); pins = []
                for i in 0..<min(4, level / 2) { pins.append(CGFloat(i) * 1.4) }
                cooldown = 0.6
            }
        }
    }

    private func updateHelix(_ dt: CGFloat) {
        let previousY = player.y
        velocity.dy += 600 * dt; player.y += velocity.dy * dt
        if velocity.dy > 0 {
            for i in bodies.indices {
                let platform = bodies[i]
                guard previousY + 10 <= platform.rect.minY, player.y + 10 >= platform.rect.minY else { continue }
                let relative = wrap(player.x - platform.rect.minX)
                if relative < platform.rect.width {
                    if !bodies[i].counted { bodies[i].counted = true; reward(10) }
                } else if relative > 200 && relative < 265 {
                    lose(); return
                } else {
                    player.y = platform.rect.minY - 10; velocity.dy = -230; break
                }
            }
        }
        if player.y > 250 {
            let offset = player.y - 250; player.y = 250
            for i in bodies.indices { bodies[i].rect.origin.y -= offset }
            bodies.removeAll { $0.rect.maxY < 0 }
            while (bodies.last?.rect.minY ?? 0) < 560 {
                bodies.append(ArcadeBody(rect: CGRect(x: CGFloat.random(in: 0..<320), y: (bodies.last?.rect.minY ?? 0) + 85, width: 88, height: 12)))
            }
        }
    }

    private func updateSky(_ dt: CGFloat) {
        let old = player.y
        velocity.dy += 600 * dt; player.y += velocity.dy * dt
        if velocity.dy > 0 {
            for platform in bodies where old + 11 <= platform.rect.minY && player.y + 11 >= platform.rect.minY {
                if player.x + 9 > platform.rect.minX, player.x - 9 < platform.rect.maxX {
                    player.y = platform.rect.minY - 11; velocity.dy = -330; Haptics.tap(); break
                }
            }
        }
        if player.y < 190 {
            let offset = 190 - player.y; player.y = 190; climbed += offset
            score = Int(climbed / 10)
            for i in bodies.indices { bodies[i].rect.origin.y += offset }
            bodies.removeAll { $0.rect.minY > 500 }
            while (bodies.map(\.rect.minY).min() ?? 0) > -60 {
                bodies.append(platform(y: (bodies.map(\.rect.minY).min() ?? 0) - 65))
            }
        }
        if player.y > 495 { lose() }
    }

    private func addPipe(x: CGFloat) {
        bodies.append(ArcadeBody(rect: CGRect(x: x, y: CGFloat.random(in: 150...330) - 72.5, width: 48, height: 145)))
    }
    private func updateFlappy(_ dt: CGFloat) {
        velocity.dy += 640 * dt; player.y += velocity.dy * dt
        guard player.y > 10, player.y < 470 else { lose(); return }
        for i in bodies.indices {
            bodies[i].rect.origin.x -= CGFloat(110 + min(60, score)) * dt
            let pipe = bodies[i].rect
            if pipe.minX < player.x + 10, pipe.maxX > player.x - 10,
               player.y - 10 < pipe.midY - 72.5 || player.y + 10 > pipe.midY + 72.5 {
                lose(); return
            }
            if !bodies[i].counted, pipe.maxX < player.x { bodies[i].counted = true; reward(10) }
        }
        bodies.removeAll { $0.rect.maxX < -10 }
        if (bodies.last?.rect.minX ?? 0) < 190 { addPipe(x: (bodies.last?.rect.minX ?? 190) + 200) }
    }

    private func serve() {
        player = CGPoint(x: 160, y: 240)
        velocity = CGVector(dx: CGFloat.random(in: -100...100), dy: Bool.random() ? 230 : -230)
        cooldown = 0.8
    }
    private func updateBall(_ dt: CGFloat, pong: Bool) {
        if pong {
            let target = player.x - opponent
            opponent += min(140 * dt, max(-140 * dt, target))
            opponent = min(278, max(42, opponent))
        }
        guard cooldown <= 0 else { return }
        let old = player
        player.x += velocity.dx * dt; player.y += velocity.dy * dt
        if player.x < 7 { player.x = 7; velocity.dx = abs(velocity.dx) }
        if player.x > 313 { player.x = 313; velocity.dx = -abs(velocity.dx) }
        if !pong, player.y < 7 { player.y = 7; velocity.dy = abs(velocity.dy) }
        if velocity.dy > 0, old.y <= 433, player.y >= 433, abs(player.x - paddle) < 47 {
            player.y = 433; velocity.dy = -max(220, abs(velocity.dy))
            velocity.dx = (player.x - paddle) * 5; Haptics.tap()
        }
        if pong, velocity.dy < 0, old.y >= 47, player.y <= 47, abs(player.x - opponent) < 47 {
            player.y = 47; velocity.dy = abs(velocity.dy); velocity.dx = (player.x - opponent) * 5
        }
        if pong, player.y < -10 {
            reward(1)
            if score == 7 { state = .gameOver(won: true) } else { serve() }
            return
        }
        if player.y > 490 {
            if pong { opponentScore += 1; if opponentScore == 7 { lose() } else { serve() } }
            else {
                lives -= 1
                if lives == 0 { lose() } else { player = CGPoint(x: paddle, y: 415); velocity = CGVector(dx: 100, dy: -230); cooldown = 0.7 }
            }
            return
        }
        if !pong, let hit = bodies.firstIndex(where: { $0.rect.insetBy(dx: -7, dy: -7).contains(player) }) {
            let rect = bodies[hit].rect
            if old.y < rect.minY - 6 || old.y > rect.maxY + 6 { velocity.dy *= -1 } else { velocity.dx *= -1 }
            bodies.remove(at: hit); reward(10)
            if bodies.isEmpty { state = .gameOver(won: true) }
        }
    }

    private func addLane(row: Int) {
        guard row % 4 != 0 else { return } // Every fourth row is a safe grass strip.
        let y = player.y - CGFloat(row - roadRow) * 50
        let speed: CGFloat = (row.isMultiple(of: 2) ? 1 : -1) * CGFloat(50 + row % 6 * 13)
        let offset = CGFloat.random(in: -80...20)
        for i in 0..<2 {
            bodies.append(ArcadeBody(rect: CGRect(x: offset + CGFloat(i) * 220, y: y - 16, width: 65, height: 32), value: row, speed: speed))
        }
    }
    private func roadCollision() {
        let rect = CGRect(x: player.x - 11, y: player.y - 11, width: 22, height: 22)
        if bodies.contains(where: { $0.rect.intersects(rect) }) { lose() }
    }
}
