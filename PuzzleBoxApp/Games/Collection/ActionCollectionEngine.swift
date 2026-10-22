import SwiftUI
import Observation

enum ActionMode: String {
    case redGreen, perfectTiming, bubblePop, whackMole, chainReaction
    var id: GameID {
        switch self {
        case .redGreen: .redGreen
        case .perfectTiming: .perfectTiming
        case .bubblePop: .bubblePop
        case .whackMole: .whackMole
        case .chainReaction: .chainReaction
        }
    }
    /// Short tagline, also shown on the game card.
    var hint: String {
        switch self {
        case .redGreen: "Tap to advance only on green. Reach the finish."
        case .perfectTiming: "Tap when the marker is inside the zone."
        case .bubblePop: "Pop bubbles before they disappear."
        case .whackMole: "Tap the target before it hides."
        case .chainReaction: "One tap sets off a chain. Hit the target to reach the next level."
        }
    }
    /// The detailed rules under the board.
    var rules: String {
        switch self {
        case .redGreen: "Tap only on green. Tapping on yellow or red costs a heart and pushes you back. Beware of fake greens!"
        case .perfectTiming: "Hit the centre of the zone for a Perfect and a streak bonus. Three misses end the game."
        case .bubblePop: "Golden bubbles give big points, clocks add time. Never pop the red bombs!"
        case .whackMole: "Golden moles are worth more. Don't hit the moles holding bombs!"
        case .chainReaction: "One tap sets off a chain. Hit the target to reach the next level."
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
    /// Bubbles: 0 normal, 1 golden, 2 bomb, 3 clock. Chain balls: hue index.
    var kind = 0
}

/// A mole currently out of its hole.
struct ActionMole {
    /// 0 normal, 1 golden, 2 bomb.
    var kind: Int
    var age: Double = 0
    var life: Double
    var whacked = false
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
    private(set) var lives = 3
    private(set) var fx = ArcadeFX()

    private(set) var particles: [ActionParticle] = []
    private(set) var blasts: [ActionParticle] = []

    private(set) var signal = 1 // green, yellow, red = 1, 2, 0
    private(set) var progress = 0
    private(set) var zone: CGFloat = 150
    private(set) var zoneVelocity: CGFloat = 0
    private(set) var marker: CGFloat = 25
    private(set) var holes: [ActionMole?] = Array(repeating: nil, count: 9)
    private(set) var usedTap = false
    private(set) var streak = 0
    private(set) var level = 1
    private(set) var pushback = 0.0
    private(set) var clock = 0.0

    private var elapsed = 0.0
    private var spawnIn = 0.0
    private var cooldown = 0.0
    private var markerDirection: CGFloat = 1
    private var lastHitTime = -10.0
    private var fakeGreen = false

    static let redGreenGoal = 30
    var chainTarget: Int { min(10 + level * 3, chainBallCount - 2) }
    var chainBallCount: Int { min(30 + (level - 1) * 3, 48) }
    var timed: Bool { [.redGreen, .bubblePop, .whackMole].contains(mode) }
    var usesLives: Bool { mode != .chainReaction }
    var maxLives: Int { mode == .bubblePop || mode == .whackMole ? 5 : 3 }
    /// Points per hit grow with a quick streak of hits.
    var multiplier: Int { min(4, 1 + streak / 4) }
    /// Half-width of the Perfect Timing zone, shrinking as you score.
    var zoneHalfWidth: CGFloat { max(11, 32 - CGFloat(progress) * 0.9) }

    init(mode: ActionMode) { self.mode = mode; restart() }

    func restart() {
        state = .playing; score = 0; started = false; timeLeft = 30; lives = maxLives
        particles = []; blasts = []; fx.reset()
        signal = 1; progress = 0; streak = 0; level = 1; pushback = 0; clock = 0
        zone = CGFloat.random(in: 80...240); zoneVelocity = 0; marker = 25; holes = Array(repeating: nil, count: 9); usedTap = false
        elapsed = 0; spawnIn = 1; cooldown = 0; markerDirection = 1; lastHitTime = -10; fakeGreen = false
        if mode == .chainReaction { setupChainLevel() }
    }

    private func lose() { state = .gameOver(won: false); Haptics.error() }

    private func gain(_ base: Int, at p: CGPoint, color: Color = .white) {
        let points = base * multiplier
        score += points
        fx.popup(multiplier > 1 ? "+\(points) ×\(multiplier)" : "+\(points)", at: CGPoint(x: p.x, y: p.y - 20), color: color, size: multiplier > 1 ? 18 : 15)
    }

    private func loseLife(at p: CGPoint) {
        lives -= 1; streak = 0
        fx.burst(at: p, color: .red, count: 16, speed: 160, gravity: 200, size: 3)
        fx.kick(6); fx.flash(.red, 0.25)
        Haptics.error(); SoundFX.play(.wrong)
        if lives <= 0 { lose() }
    }

    func tap(_ p: CGPoint) {
        guard active, state == .playing else { return }
        if !started { started = true; return }
        guard cooldown <= 0 else { return }
        switch mode {
        case .redGreen: tapRedGreen()
        case .perfectTiming: tapTiming()
        case .bubblePop: tapBubble(p)
        case .whackMole: tapMole(p)
        case .chainReaction:
            guard !usedTap else { return }
            usedTap = true; blasts.append(ActionParticle(p: p, radius: 2, life: 2.5))
            Haptics.tap(); SoundFX.play(.whoosh)
        }
    }

    // MARK: Red Light, Green Light

    private func tapRedGreen() {
        let runner = CGPoint(x: 160, y: 420 - CGFloat(progress) / CGFloat(Self.redGreenGoal) * 180)
        if signal != 1 {
            progress = max(0, progress - 3); pushback = 0.4
            loseLife(at: runner)
            cooldown = 0.3
            return
        }
        progress += 1; streak += 1
        score += 10
        cooldown = 0.12
        Haptics.tap(); SoundFX.play(.tap)
        fx.burst(at: CGPoint(x: runner.x, y: runner.y + 10), color: .white.opacity(0.7), count: 3, speed: 50, gravity: 80, size: 2, life: 0.3)
        if progress >= Self.redGreenGoal {
            let bonus = Int(timeLeft) * 10 + lives * 50
            score += bonus
            fx.popup("+\(bonus)", at: CGPoint(x: 160, y: 230), color: .green, size: 24)
            state = .gameOver(won: true)
        }
    }

    // MARK: Perfect Timing

    private func tapTiming() {
        let distance = abs(marker - zone)
        let half = zoneHalfWidth
        let point = CGPoint(x: marker, y: 230)
        guard distance <= half else {
            loseLife(at: point)
            cooldown = 0.35
            return
        }
        progress += 1
        if distance <= half * 0.3 {
            streak += 1
            gain(30, at: point, color: .yellow)
            fx.popup(L10n.text("Perfect!"), at: CGPoint(x: 160, y: 150), color: .yellow, size: 22)
            fx.burst(at: point, color: .yellow, count: 18, speed: 160, gravity: 100, size: 3)
            Haptics.success(); SoundFX.play(.coin)
        } else {
            streak = 0
            gain(10, at: point)
            fx.burst(at: point, color: GameTheme.accent, count: 8, speed: 100, gravity: 100, size: 2.5)
            Haptics.tap(); SoundFX.play(.point)
        }
        zone = CGFloat.random(in: 65...255)
        // Later on, the zone itself drifts.
        zoneVelocity = progress >= 8 ? (Bool.random() ? 1 : -1) * CGFloat.random(in: 20...min(90, 20 + CGFloat(progress) * 3)) : 0
        cooldown = 0.25
    }

    // MARK: Bubble Pop

    private func tapBubble(_ p: CGPoint) {
        guard let i = particles.lastIndex(where: { hypot($0.p.x - p.x, $0.p.y - p.y) < $0.radius + 8 }) else { return }
        let bubble = particles.remove(at: i)
        switch bubble.kind {
        case 2:
            fx.burst(at: bubble.p, color: .orange, count: 26, speed: 220, gravity: 0, size: 3.5)
            loseLife(at: bubble.p)
            return
        case 3:
            timeLeft = min(60, timeLeft + 3)
            fx.popup("+3s", at: CGPoint(x: bubble.p.x, y: bubble.p.y - 20), color: .cyan, size: 18)
            fx.burst(at: bubble.p, color: .cyan, count: 14, speed: 140, gravity: 0, size: 2.5)
            Haptics.move(); SoundFX.play(.win)
            return
        default: break
        }
        streak = elapsed - lastHitTime < 0.9 ? streak + 1 : 1
        lastHitTime = elapsed
        let golden = bubble.kind == 1
        gain(golden ? 50 : 10, at: bubble.p, color: golden ? .yellow : .white)
        fx.burst(at: bubble.p, color: golden ? .yellow : .cyan, count: golden ? 20 : 10, speed: 140, gravity: 60, size: 2.5, life: 0.45)
        Haptics.tap(); SoundFX.play(golden ? .coin : .pop)
    }

    // MARK: Whack-a-Mole

    /// Three rows centred on the 320×460 field, counting the mole that rises above each hole.
    static func holeCenter(_ i: Int) -> CGPoint { CGPoint(x: CGFloat(i % 3) * 106.66 + 53.33, y: CGFloat(i / 3) * 120 + 92) }

    private func tapMole(_ p: CGPoint) {
        // Rows are 120 apart; each band runs from midway to the row above to midway to the next.
        let c = Int(p.x / 106.66), r = Int((p.y - 38) / 120)
        guard p.y >= 38, (0..<3).contains(c), (0..<3).contains(r) else { return }
        let i = r * 3 + c
        let center = Self.holeCenter(i)
        guard let mole = holes[i], !mole.whacked else {
            // Whacking an empty hole breaks the streak but costs nothing else.
            streak = 0; SoundFX.play(.tap)
            return
        }
        // Copy, edit, write back: reading `holes` inside its own mutation is an exclusivity violation.
        var hit = mole
        hit.whacked = true
        hit.life = hit.age + 0.25
        holes[i] = hit
        switch mole.kind {
        case 2:
            fx.burst(at: center, color: .orange, count: 26, speed: 220, gravity: 100, size: 3.5)
            loseLife(at: center)
        default:
            streak = elapsed - lastHitTime < 1.3 ? streak + 1 : 1
            lastHitTime = elapsed
            let golden = mole.kind == 1
            gain(golden ? 50 : 10, at: center, color: golden ? .yellow : .white)
            fx.burst(at: center, color: golden ? .yellow : Color(red: 0.75, green: 0.5, blue: 0.3), count: 12, speed: 150, gravity: 300, size: 3)
            fx.kick(2)
            Haptics.move(); SoundFX.play(golden ? .coin : .hit)
        }
    }

    // MARK: Chain Reaction

    private func setupChainLevel() {
        particles = []; blasts = []; usedTap = false; progress = 0
        let speedBoost = CGFloat(level - 1) * 4
        for i in 0..<chainBallCount {
            let heading = CGFloat.random(in: 0...(.pi * 2)), speed = CGFloat.random(in: 25...65) + speedBoost
            particles.append(ActionParticle(p: CGPoint(x: CGFloat.random(in: 15...305), y: CGFloat.random(in: 25...435)),
                                            v: CGVector(dx: cos(heading) * speed, dy: sin(heading) * speed), radius: 6, kind: i % 5))
        }
    }

    // MARK: Frame loop

    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        let total = min(0.1, max(0, dt))
        var rest = total
        while rest > 0, state == .playing {
            let step = min(rest, 1.0 / 120); update(step); rest -= step
        }
        fx.update(CGFloat(total))
        clock += total
    }

    private func update(_ dt: Double) {
        elapsed += dt; spawnIn -= dt; cooldown = max(0, cooldown - dt); pushback = max(0, pushback - dt)
        if timed {
            timeLeft = max(0, timeLeft - dt)
            if timeLeft == 0 { state = .gameOver(won: mode != .redGreen || progress >= Self.redGreenGoal); return }
        }
        let step = CGFloat(dt)
        switch mode {
        case .redGreen:
            if spawnIn <= 0 {
                if fakeGreen {
                    // A brief yellow flicker that turns back to green.
                    fakeGreen = false; signal = 1; spawnIn = Double.random(in: 0.8...1.6)
                } else if signal == 1 {
                    signal = 2
                    fakeGreen = progress > 8 && Int.random(in: 0..<4) == 0
                    spawnIn = fakeGreen ? 0.3 : max(0.3, 0.55 - Double(progress) * 0.006)
                } else if signal == 2 { signal = 0; spawnIn = Double.random(in: 0.9...2.1) }
                else { signal = 1; spawnIn = Double.random(in: 1.2...2.8) }
            }
        case .perfectTiming:
            marker += markerDirection * CGFloat(160 + progress * 9) * step
            if marker > 295 { marker = 295; markerDirection = -1 }
            if marker < 25 { marker = 25; markerDirection = 1 }
            if zoneVelocity != 0 {
                zone += zoneVelocity * step
                if zone < 50 || zone > 270 { zoneVelocity *= -1; zone = min(270, max(50, zone)) }
            }
        case .bubblePop: updateBubbles(dt)
        case .whackMole: updateMoles(dt)
        case .chainReaction: updateChain(dt)
        }
    }

    private func updateBubbles(_ dt: Double) {
        if spawnIn <= 0 {
            let roll = Int.random(in: 0..<100)
            let kind = elapsed > 4 && roll < 8 ? 2 : roll < 16 ? 1 : roll < 21 ? 3 : 0
            let radius: CGFloat = kind == 1 ? 18 : kind == 3 ? 20 : CGFloat.random(in: 20...28)
            let life = kind == 1 ? 1.3 : kind == 2 ? 2.6 : 2.2 - min(0.7, elapsed / 60)
            particles.append(ActionParticle(p: CGPoint(x: CGFloat.random(in: 32...288), y: CGFloat.random(in: 70...420)),
                                            v: CGVector(dx: CGFloat.random(in: -12...12), dy: CGFloat.random(in: -30 ... -10)),
                                            radius: radius, life: life, kind: kind))
            spawnIn = max(0.28, 0.65 - elapsed / 70)
        }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].p.x += particles[i].v.dx * CGFloat(dt)
            particles[i].p.y += particles[i].v.dy * CGFloat(dt)
        }
        // Missing a normal or golden bubble costs a life; bombs and clocks just fade.
        let missed = particles.filter { $0.age >= $0.life && ($0.kind == 0 || $0.kind == 1) }
        particles.removeAll { $0.age >= $0.life }
        for bubble in missed where state == .playing {
            fx.burst(at: bubble.p, color: .gray, count: 6, speed: 60, gravity: 0, size: 2)
            loseLife(at: bubble.p)
        }
    }

    private func updateMoles(_ dt: Double) {
        for i in holes.indices {
            guard var mole = holes[i] else { continue }
            mole.age += dt
            if mole.age >= mole.life {
                // An escaped normal or golden mole costs a life.
                if !mole.whacked && mole.kind != 2 { loseLife(at: Self.holeCenter(i)) }
                holes[i] = nil
            } else {
                holes[i] = mole
            }
        }
        guard spawnIn <= 0, state == .playing else { return }
        let free = holes.indices.filter { holes[$0] == nil }
        let maxOut = elapsed > 18 ? 3 : elapsed > 8 ? 2 : 1
        if let i = free.randomElement(), holes.compactMap({ $0 }).count < maxOut {
            let roll = Int.random(in: 0..<100)
            let kind = elapsed > 3 && roll < 15 ? 2 : roll < 25 ? 1 : 0
            let life = max(0.75, 1.35 - elapsed / 45) * (kind == 1 ? 0.75 : 1)
            holes[i] = ActionMole(kind: kind, life: life)
        }
        spawnIn = max(0.35, 0.9 - elapsed / 50)
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
        let hit = particles.filter { ball in blasts.contains { hypot($0.p.x - ball.p.x, $0.p.y - ball.p.y) < $0.radius + ball.radius } }
        if !hit.isEmpty {
            let hitIDs = Set(hit.map(\.id))
            for ball in hit {
                progress += 1
                // Later links in the chain are worth more.
                let points = 10 + 2 * progress
                score += points
                blasts.append(ActionParticle(p: ball.p, radius: 2, life: 2.5, kind: ball.kind))
                fx.burst(at: ball.p, color: Self.chainColor(ball.kind), count: 6, speed: 90, gravity: 0, size: 2.5, life: 0.5)
                if progress.isMultiple(of: 5) { fx.popup("×\(progress)", at: ball.p, color: .white, size: 16) }
            }
            particles.removeAll { hitIDs.contains($0.id) }
            SoundFX.play(.pop)
            if progress == chainTarget { fx.popup(L10n.text("Target reached!"), at: CGPoint(x: 160, y: 200), color: .green, size: 22); SoundFX.play(.clear) }
        }
        blasts.removeAll { $0.age >= $0.life }
        if usedTap && blasts.isEmpty {
            if progress >= chainTarget {
                let bonus = particles.isEmpty ? 200 : 50
                score += bonus
                fx.popup(L10n.format("Level %d", level + 1), at: CGPoint(x: 160, y: 230), color: .yellow, size: 26)
                if particles.isEmpty { fx.popup(L10n.text("Board clear! +200"), at: CGPoint(x: 160, y: 270), color: .mint, size: 18) }
                Haptics.success(); SoundFX.play(.win)
                level += 1
                setupChainLevel()
            } else {
                state = .gameOver(won: level > 1)
            }
        }
    }

    static func chainColor(_ kind: Int) -> Color {
        [Color.cyan, .pink, .yellow, .mint, .orange][kind % 5]
    }
}

// MARK: - Saved round

extension ActionCollectionEngine: ResumableGame {
    private struct Session: Codable {
        let score: Int
        let timeLeft: Double
        let lives: Int
        let progress: Int
        let level: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, started, score > 0 || progress > 0 || level > 1 else { return nil }
        return encodeSession(Session(score: score, timeLeft: timeLeft, lives: lives, progress: progress, level: level))
    }

    /// Resumes score, clock, lives and level; the player taps to start again.
    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), s.lives > 0, s.timeLeft > 0 else { return false }
        restart()
        score = s.score; timeLeft = s.timeLeft; lives = s.lives; progress = s.progress; level = s.level
        if mode == .chainReaction { setupChainLevel() }
        return true
    }
}
