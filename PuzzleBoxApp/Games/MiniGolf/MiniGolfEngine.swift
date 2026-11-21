import SwiftUI
import Observation

struct GolfParticle {
    var p: CGPoint
    var v: CGVector
    var age = 0.0
    var life: Double
    var color: Color
    var size: CGFloat
    var spin: Double
}

/// Mini golf over 100 one-screen holes (`GolfHoles`): 24 hand-made, then
/// six generated worlds that each bring a new piece.
///
/// Pull back from the ball and let go; the dotted line shows the path up to a
/// little past the first bounce. Stars: a hole in one earns three, par or
/// better two, anything else one. A hole allows par + 3 strokes; water adds
/// a penalty stroke and puts the ball back where it was hit from.
@MainActor
@Observable
final class MiniGolfEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var level = 1
    /// The hole being played. Swapped in one piece, so views never mix holes.
    private(set) var hole: GolfHole
    private(set) var ball: CGPoint
    private(set) var rolling = false
    private(set) var strokes = 0
    /// Seconds on this hole; drives moving rails, windmills and the turf's animation.
    private(set) var time: Double = 0
    /// Normalised pull while aiming: the shot heading times power (0…1).
    private(set) var aim: CGVector?
    private(set) var preview: [CGPoint] = []
    /// When the ball dropped, in `time`; drives the sink, the flag and the wave.
    private(set) var sunkAt: Double?
    private(set) var splash: (p: CGPoint, at: Double)?
    private(set) var bumperHit: (index: Int, at: Double)?
    private(set) var portalHit: (index: Int, at: Double)?
    private(set) var teleportHit: (index: Int, at: Double)?
    private(set) var springHit: (index: Int, at: Double)?
    /// Gates whose button has been rolled over, one bit each, and when.
    private(set) var opened: UInt32 = 0
    private(set) var gateOpenedAt: [Int: Double] = [:]
    private(set) var particles: [GolfParticle] = []
    private(set) var notice = ""
    private(set) var bestStars: [Int: Int] = [:]

    var active = false
    var reduceMotion = false

    static var levelCount: Int { GolfHoles.all.count }
    private let levelKey = "miniGolf.level"
    private let starsKey = "miniGolf.stars"
    private var velocity = CGVector.zero
    private var shotFrom: CGPoint
    private var restTime = 0.0
    private var flight = 0.0
    private var bounceQuiet = 0.0
    private var pendingEnd: (won: Bool, at: Double)?
    private var buffer: [GolfSeg] = []

    init() {
        let saved = UserDefaults.standard.integer(forKey: levelKey)
        let start = max(1, min(GolfHoles.all.count, saved))
        level = start
        let first = GolfHoles.all[start - 1]
        hole = first
        ball = first.tee
        shotFrom = first.tee
        if let stored = UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] {
            bestStars = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
        }
        restart()
    }

    // MARK: Hole

    var par: Int { hole.par }
    var maxStrokes: Int { hole.par + 3 }
    var hasNextLevel: Bool { level < Self.levelCount }
    var isSunk: Bool { sunkAt != nil }
    var canShoot: Bool { state == .playing && !rolling && sunkAt == nil && pendingEnd == nil && strokes < maxStrokes }
    /// Stars for the hole as it stands: after the cup, what was earned;
    /// before, what sinking it with the next stroke would earn.
    var stars: Int {
        let count = isSunk ? strokes : strokes + 1
        return count <= 1 ? 3 : count <= hole.par ? 2 : 1
    }
    var strokesLeft: Int { max(0, maxStrokes - strokes) }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    func restart() {
        hole = GolfHoles.all[level - 1]
        ball = hole.tee; shotFrom = hole.tee; velocity = .zero
        rolling = false; strokes = 0; time = 0; aim = nil; preview = []
        sunkAt = nil; splash = nil; bumperHit = nil; portalHit = nil; particles = []
        teleportHit = nil; springHit = nil; opened = 0; gateOpenedAt = [:]
        notice = ""; pendingEnd = nil; restTime = 0; flight = 0
        state = .playing; score = 0
    }

    /// A fixed mid-hole position with the shot being aimed, for the Home
    /// preview. Nothing is saved.
    func showcase() {
        level = GolfHoles.classic.count
        restart()
        strokes = 2
        time = 0.7
        ball = CGPoint(x: 248, y: 268)
        let pull = CGVector(dx: -0.62, dy: -0.78) * 92
        let length = pull.length
        aim = pull * (1 / length) * (length / GolfPhysics.maxPull)
        preview = GolfPhysics.preview(from: ball, velocity: pull * (1 / length) * GolfPhysics.speed(forPull: length), hole: hole)
    }

    // MARK: Aiming

    /// Starts aiming when the touch lands near a ball that can be hit.
    func beginAim(at p: CGPoint) -> Bool {
        guard canShoot, p.distance(to: ball) < 64 else { return false }
        aim = .zero; preview = []
        return true
    }

    /// `pull` is from the finger back to where the drag started, in course points.
    func updateAim(pull: CGVector) {
        guard aim != nil, canShoot else { aim = nil; preview = []; return }
        let length = pull.length
        guard length > 12 else { aim = .zero; preview = []; return }
        let power = min(1, length / GolfPhysics.maxPull)
        let heading = pull * (1 / length)
        let crossed = aim.map { ($0.length < 0.75) != (power < 0.75) || $0.length < 0.01 } ?? false
        aim = heading * power
        preview = GolfPhysics.preview(from: ball, velocity: heading * GolfPhysics.speed(forPull: length), hole: hole, opened: opened)
        if crossed { Haptics.tap() }
    }

    func cancelAim() { aim = nil; preview = [] }

    func release() {
        defer { aim = nil; preview = [] }
        guard let aim, aim.length > 0.01, canShoot else { return }
        let power = aim.length
        let heading = aim * (1 / power)
        velocity = heading * GolfPhysics.speed(forPull: power * GolfPhysics.maxPull)
        shotFrom = ball
        strokes += 1
        rolling = true; restTime = 0; flight = 0; notice = ""
        SoundFX.play(.whoosh); Haptics.tap()
    }

    // MARK: Simulation

    func advance(_ dt: Double) {
        guard active, state == .playing else { return }
        let d = min(0.05, max(0, dt))
        time += d
        updateParticles(d)
        bounceQuiet = max(0, bounceQuiet - d)
        if let pendingEnd, time >= pendingEnd.at {
            self.pendingEnd = nil
            state = .gameOver(won: pendingEnd.won)
            return
        }
        if sunkAt != nil { return }
        if rolling {
            var rest = d
            while rest > 0, rolling {
                let h = min(rest, GolfPhysics.tick)
                tick(h)
                rest -= h
            }
        } else if hole.hasMovingParts, pendingEnd == nil {
            var b = GolfBall(p: ball, v: .zero)
            if GolfPhysics.knock(&b, hole: hole, time: time) {
                ball = b.p; velocity = b.v
                if velocity.length > 10 { rolling = true; restTime = 0; flight = 0; aim = nil; preview = [] }
                bounce()
            }
        }
    }

    private func tick(_ h: Double) {
        var b = GolfBall(p: ball, v: velocity, opened: opened)
        let events = GolfPhysics.step(&b, hole: hole, time: time, moving: true, h: h, buffer: &buffer)
        ball = b.p; velocity = b.v
        if b.opened != opened {
            for i in hole.gates.indices where b.opened & (1 << UInt32(i)) != 0 && opened & (1 << UInt32(i)) == 0 {
                gateOpenedAt[i] = time
                burst(at: hole.gates[i].button, colors: [ToyMiniGolf.starGold, .white], count: 10, speed: 120)
            }
            opened = b.opened
            notice = "Gate open!"
            SoundFX.play(.coin); Haptics.success()
        }
        flight += h
        if events.contains(.sunk) { sink(); return }
        if events.contains(.water) { splashDown(); return }
        if events.contains(.bumper) {
            if let i = hole.bumpers.indices.min(by: { hole.bumpers[$0].center.distance(to: ball) < hole.bumpers[$1].center.distance(to: ball) }) {
                bumperHit = (i, time)
            }
            SoundFX.play(.point); Haptics.tap()
        } else if events.contains(.spring) {
            if let i = hole.springs.indices.min(by: {
                GolfPhysics.closest(ball, hole.springs[$0].a, hole.springs[$0].b).distance(to: ball)
                    < GolfPhysics.closest(ball, hole.springs[$1].a, hole.springs[$1].b).distance(to: ball)
            }) {
                springHit = (i, time)
            }
            SoundFX.play(.point); Haptics.tap()
        } else if events.contains(.bounce) {
            bounce()
        }
        if events.contains(.teleport) {
            if let i = hole.teleports.indices.min(by: { teleportGap(hole.teleports[$0]) < teleportGap(hole.teleports[$1]) }) {
                teleportHit = (i, time)
            }
            SoundFX.play(.whoosh); Haptics.tap()
        }
        if events.contains(.portal) {
            if let i = hole.portals.indices.min(by: { hole.portals[$0].exit.distance(to: ball) < hole.portals[$1].exit.distance(to: ball) }) {
                portalHit = (i, time)
            }
            SoundFX.play(.whoosh)
        }
        if velocity.length < 8 { restTime += h } else { restTime = 0 }
        if restTime > 0.2 || flight > 14 { stop() }
    }

    /// How close the ball is to either pad of a teleport.
    private func teleportGap(_ t: GolfTeleport) -> CGFloat { min(t.a.distance(to: ball), t.b.distance(to: ball)) }

    private func bounce() {
        guard bounceQuiet == 0 else { return }
        bounceQuiet = 0.08
        SoundFX.play(.bounce)
    }

    private func stop() {
        rolling = false; velocity = .zero
        if strokes >= maxStrokes { outOfStrokes() } else { SoundFX.play(.tick) }
    }

    private func outOfStrokes() {
        notice = "Out of strokes"
        Haptics.error(); SoundFX.play(.wrong)
        pendingEnd = (false, time + 1.0)
    }

    private func splashDown() {
        splash = (ball, time)
        burst(at: ball, colors: [Color(red: 0.55, green: 0.8, blue: 1), .white], count: 14, speed: 110)
        rolling = false; velocity = .zero
        ball = shotFrom
        strokes += 1
        notice = "Splash! +1 stroke"
        Haptics.error(); SoundFX.play(.wrong)
        if strokes >= maxStrokes { outOfStrokes() }
    }

    private func sink() {
        rolling = false; velocity = .zero
        ball = hole.cup
        sunkAt = time
        let earned = stars
        score = 100 + level * 50 + earned * 100
        if earned > (bestStars[level] ?? 0) {
            bestStars[level] = earned
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: bestStars.map { (String($0.key), $0.value) }), forKey: starsKey)
        }
        UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: levelKey)
        notice = strokes == 1 ? "Hole in one!" : ""
        burst(at: hole.cup, colors: [ToyMiniGolf.starGold, Color(red: 0.95, green: 0.45, blue: 0.5), Color(red: 0.45, green: 0.7, blue: 0.95), .white],
              count: 34, speed: 210)
        Haptics.success(); SoundFX.play(.coin)
        // Let the ball drop, the flag pop and the wave roll before the result window.
        pendingEnd = (true, time + 1.4)
    }

    // MARK: Effects

    private func burst(at p: CGPoint, colors: [Color], count: Int, speed: CGFloat) {
        guard !reduceMotion else { return }
        for i in 0..<count {
            let heading = CGFloat.random(in: 0...(2 * .pi)), v = speed * CGFloat.random(in: 0.35...1)
            particles.append(GolfParticle(p: p, v: CGVector(dx: cos(heading) * v, dy: sin(heading) * v - speed * 0.5),
                                          life: Double.random(in: 0.7...1.2), color: colors[i % colors.count],
                                          size: CGFloat.random(in: 2.5...4.5), spin: Double.random(in: -8...8)))
        }
    }

    private func updateParticles(_ d: Double) {
        guard !particles.isEmpty else { return }
        let step = CGFloat(d)
        for i in particles.indices {
            particles[i].age += d
            particles[i].p = particles[i].p + particles[i].v * step
            particles[i].v.dy += 420 * step
            particles[i].v = particles[i].v * (1 - 0.8 * step)
        }
        particles.removeAll { $0.age >= $0.life }
    }
}
