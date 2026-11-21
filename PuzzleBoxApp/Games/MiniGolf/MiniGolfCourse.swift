import CoreGraphics
import Foundation

// Mini golf course data and ball physics. Pure value code (no SwiftUI), so
// the same step runs the real ball, the aim preview and the offline checks.
// Every hole lives in a 320 × 460 field; y grows downwards.

struct GolfSeg: Codable {
    var a: CGPoint
    var b: CGPoint
}

/// A rounded rectangle on the turf: sand, water or a slope.
struct GolfZone: Codable {
    var rect: CGRect
    var radius: CGFloat = 18

    func contains(_ p: CGPoint) -> Bool {
        guard rect.contains(p) else { return false }
        let r = min(radius, rect.width / 2, rect.height / 2)
        let cx = min(max(p.x, rect.minX + r), rect.maxX - r)
        let cy = min(max(p.y, rect.minY + r), rect.maxY - r)
        return hypot(p.x - cx, p.y - cy) <= r
    }
}

/// A tilted patch that keeps pushing the ball one way (points/s²).
struct GolfSlope: Codable {
    var zone: GolfZone
    var push: CGVector
}

/// A round dip (positive strength pulls the ball in) or hump (negative pushes it out).
struct GolfMound: Codable {
    var center: CGPoint
    var radius: CGFloat
    var strength: CGFloat
}

struct GolfBumper: Codable {
    var center: CGPoint
    var radius: CGFloat
}

/// A rail that slides back and forth along `travel`.
struct GolfMover: Codable {
    var base: GolfSeg
    var travel: CGVector
    var period: Double
    var phase: Double = 0

    private func wave(_ t: Double) -> Double { (t / period + phase) * 2 * .pi }
    func segment(at t: Double) -> GolfSeg {
        let s = CGFloat(sin(wave(t)))
        let d = CGVector(dx: travel.dx * s, dy: travel.dy * s)
        return GolfSeg(a: base.a + d, b: base.b + d)
    }
    func velocity(at t: Double) -> CGVector {
        let c = CGFloat(cos(wave(t)) * 2 * .pi / period)
        return CGVector(dx: travel.dx * c, dy: travel.dy * c)
    }
}

/// A windmill blade turning around its middle.
struct GolfSpinner: Codable {
    var center: CGPoint
    var arm: CGFloat
    /// Radians per second.
    var speed: Double
    var phase: Double = 0

    func angle(at t: Double) -> Double { phase + speed * t }
    func segment(at t: Double) -> GolfSeg {
        let a = angle(at: t)
        let d = CGVector(dx: CGFloat(cos(a)) * arm, dy: CGFloat(sin(a)) * arm)
        return GolfSeg(a: center - d, b: center + d)
    }
}

/// A one-way tunnel: the ball drops into `entry` and rolls out of `exit`
/// with the same speed and heading.
struct GolfPortal: Codable {
    var entry: CGPoint
    var exit: CGPoint
}

/// A two-way teleport: rolling into either pad sends the ball out of the
/// other one with the same heading.
struct GolfTeleport: Codable {
    var a: CGPoint
    var b: CGPoint
}

/// An arrow pad that keeps speeding the ball up one way while it rolls over it.
struct GolfBooster: Codable {
    var center: CGPoint
    /// Unit vector.
    var dir: CGVector
}

/// A rail that drops for good once the ball rolls over its button.
struct GolfGate: Codable {
    var button: CGPoint
    var gate: GolfSeg
}

/// A flipper swinging back and forth around its pivot.
struct GolfPaddle: Codable {
    var pivot: CGPoint
    var length: CGFloat
    /// Middle of the swing, radians.
    var angle: Double
    /// Half the swing, radians.
    var swing: Double
    var period: Double
    var phase: Double = 0

    private func wave(_ t: Double) -> Double { (t / period + phase) * 2 * .pi }
    func theta(at t: Double) -> Double { angle + swing * sin(wave(t)) }
    /// Radians per second.
    func omega(at t: Double) -> Double { swing * cos(wave(t)) * 2 * .pi / period }
    func segment(at t: Double) -> GolfSeg {
        let a = theta(at: t)
        return GolfSeg(a: pivot, b: CGPoint(x: pivot.x + CGFloat(cos(a)) * length, y: pivot.y + CGFloat(sin(a)) * length))
    }
}

struct GolfHole: Codable {
    var par: Int
    var tee: CGPoint
    var cup: CGPoint
    /// The course edge, a closed polygon with a rail along it.
    var outline: [CGPoint]
    var walls: [GolfSeg] = []
    var bumpers: [GolfBumper] = []
    var sand: [GolfZone] = []
    var water: [GolfZone] = []
    var slopes: [GolfSlope] = []
    var mounds: [GolfMound] = []
    var movers: [GolfMover] = []
    var spinners: [GolfSpinner] = []
    var portals: [GolfPortal] = []
    var ice: [GolfZone] = []
    var boosters: [GolfBooster] = []
    var teleports: [GolfTeleport] = []
    var gates: [GolfGate] = []
    /// Springy rails that kick the ball off.
    var springs: [GolfSeg] = []
    var paddles: [GolfPaddle] = []
    /// The course's colours (see `ToyMiniGolf.turf(theme:)`).
    var theme = 0

    var edges: [GolfSeg] {
        outline.indices.map { GolfSeg(a: outline[$0], b: outline[($0 + 1) % outline.count]) } + walls
    }
    var hasMovingParts: Bool { !movers.isEmpty || !spinners.isEmpty || !paddles.isEmpty }
}

struct GolfBall {
    var p: CGPoint
    var v: CGVector
    /// Gates whose button the ball has rolled over, one bit each.
    var opened: UInt32 = 0
}

struct GolfEvents: OptionSet {
    let rawValue: Int
    static let bounce = GolfEvents(rawValue: 1)
    static let bumper = GolfEvents(rawValue: 2)
    static let water = GolfEvents(rawValue: 4)
    static let portal = GolfEvents(rawValue: 8)
    static let sunk = GolfEvents(rawValue: 16)
    static let teleport = GolfEvents(rawValue: 32)
    static let button = GolfEvents(rawValue: 64)
    static let spring = GolfEvents(rawValue: 128)
}

enum GolfPhysics {
    static let ballRadius: CGFloat = 7
    static let railRadius: CGFloat = 6
    static let cupRadius: CGFloat = 11
    static let bumperKick: CGFloat = 230
    static let maxPull: CGFloat = 130
    static let minSpeed: CGFloat = 70
    static let maxSpeed: CGFloat = 640
    static let tick = 1.0 / 240
    static let boosterRadius: CGFloat = 17
    static let boosterPush: CGFloat = 1500
    static let buttonRadius: CGFloat = 12
    static let springKick: CGFloat = 330
    static let topSpeed: CGFloat = 780

    /// The shot speed for a pull of the given length.
    static func speed(forPull length: CGFloat) -> CGFloat {
        minSpeed + (maxSpeed - minSpeed) * min(1, length / maxPull)
    }

    /// One fixed physics tick. `moving` is off for the aim preview, which
    /// shows the course without its timed parts.
    static func step(_ ball: inout GolfBall, hole: GolfHole, time: Double, moving: Bool,
                     h: Double = tick, buffer: inout [GolfSeg]) -> GolfEvents {
        var events: GolfEvents = []
        let dt = CGFloat(h)

        // Forces: slopes, dips and humps, and the cup's own lip.
        var a = CGVector.zero
        for s in hole.slopes where s.zone.contains(ball.p) { a = a + s.push }
        for m in hole.mounds {
            let d = ball.p.distance(to: m.center)
            guard d < m.radius, d > 0.5 else { continue }
            let k = m.strength * (1 - d / m.radius) / d
            a = a + CGVector(dx: (m.center.x - ball.p.x) * k, dy: (m.center.y - ball.p.y) * k)
        }
        let toCup = ball.p.distance(to: hole.cup)
        if toCup < 18, toCup > 0.1 {
            a = a + CGVector(dx: (hole.cup.x - ball.p.x) / toCup * 360, dy: (hole.cup.y - ball.p.y) / toCup * 360)
        }
        for b in hole.boosters where ball.p.distance(to: b.center) < boosterRadius { a = a + b.dir * boosterPush }
        for t in hole.teleports {
            for pad in [t.a, t.b] {
                let d = ball.p.distance(to: pad)
                if d < 15, d > 0.1 {
                    a = a + CGVector(dx: (pad.x - ball.p.x) / d * 260, dy: (pad.y - ball.p.y) / d * 260)
                }
            }
        }
        for portal in hole.portals {
            let d = ball.p.distance(to: portal.entry)
            if d < 20, d > 0.1 {
                a = a + CGVector(dx: (portal.entry.x - ball.p.x) / d * 300, dy: (portal.entry.y - ball.p.y) / d * 300)
            }
        }
        ball.v = ball.v + a * dt

        // Rolling friction, much stronger in sand and almost none on ice.
        let speed = ball.v.length
        if speed > 0 {
            let inSand = hole.sand.contains { $0.contains(ball.p) }
            let onIce = !inSand && hole.ice.contains { $0.contains(ball.p) }
            let decel = (85 + 0.6 * speed) * (inSand ? 5.5 : onIce ? 0.18 : 1)
            ball.v = ball.v * (max(0, speed - decel * dt) / speed)
            let fast = ball.v.length
            if fast > topSpeed { ball.v = ball.v * (topSpeed / fast) }
        }
        ball.p = ball.p + ball.v * dt

        // Rails.
        let reach = railRadius + ballRadius
        buffer.removeAll(keepingCapacity: true)
        buffer.append(contentsOf: hole.edges)
        for s in buffer where collide(&ball, s, radius: reach, restitution: 0.78, surface: .zero) {
            events.insert(.bounce)
        }
        for (i, g) in hole.gates.enumerated() where ball.opened & (1 << UInt32(i)) == 0 {
            if collide(&ball, g.gate, radius: reach, restitution: 0.78, surface: .zero) { events.insert(.bounce) }
        }
        for s in hole.springs where collide(&ball, s, radius: reach, restitution: 0.9, surface: .zero) {
            let q = closest(ball.p, s.a, s.b)
            let d = max(0.001, ball.p.distance(to: q))
            let n = CGVector(dx: (ball.p.x - q.x) / d, dy: (ball.p.y - q.y) / d)
            let out = ball.v.dx * n.dx + ball.v.dy * n.dy
            if out < springKick { ball.v = ball.v + n * (springKick - out) }
            events.insert(.spring)
        }
        if moving {
            for m in hole.movers where collide(&ball, m.segment(at: time), radius: reach, restitution: 0.8, surface: m.velocity(at: time)) {
                events.insert(.bounce)
            }
            for s in hole.spinners {
                let seg = s.segment(at: time)
                let q = closest(ball.p, seg.a, seg.b)
                let w = CGFloat(s.speed)
                let surface = CGVector(dx: -w * (q.y - s.center.y), dy: w * (q.x - s.center.x))
                if collide(&ball, seg, radius: reach, restitution: 0.8, surface: surface) { events.insert(.bounce) }
            }
            for p in hole.paddles where collide(&ball, p.segment(at: time), radius: reach, restitution: 0.8,
                                                surface: paddleSurface(p, at: ball.p, time: time)) {
                events.insert(.bounce)
            }
        }
        for b in hole.bumpers {
            let d = ball.p.distance(to: b.center), limit = b.radius + ballRadius
            guard d < limit else { continue }
            let n = d > 0.001 ? CGVector(dx: (ball.p.x - b.center.x) / d, dy: (ball.p.y - b.center.y) / d) : CGVector(dx: 0, dy: -1)
            ball.p = b.center + n * limit
            let dot = ball.v.dx * n.dx + ball.v.dy * n.dy
            if dot < 0 {
                ball.v = ball.v - n * (2 * dot)
                // Springy: always leaves with a kick.
                let out = ball.v.dx * n.dx + ball.v.dy * n.dy
                if out < bumperKick { ball.v = ball.v + n * (bumperKick - out) }
                events.insert(.bumper)
            }
        }

        for (i, g) in hole.gates.enumerated() where ball.opened & (1 << UInt32(i)) == 0 && ball.p.distance(to: g.button) < buttonRadius {
            ball.opened |= 1 << UInt32(i)
            events.insert(.button)
        }
        if hole.water.contains(where: { $0.contains(ball.p) }) { events.insert(.water) }
        for t in hole.teleports {
            let to: CGPoint
            if ball.p.distance(to: t.a) < 8 { to = t.b } else if ball.p.distance(to: t.b) < 8 { to = t.a } else { continue }
            let v = ball.v.length
            let heading = v > 1 ? ball.v * (1 / v) : CGVector(dx: 0, dy: -1)
            ball.p = to + heading * 22
            ball.v = heading * max(v, 150)
            events.insert(.teleport)
            break
        }
        for portal in hole.portals where ball.p.distance(to: portal.entry) < 9 {
            let v = ball.v.length
            let heading = v > 1 ? ball.v * (1 / v) : CGVector(dx: 0, dy: -1)
            ball.p = portal.exit + heading * 2
            ball.v = heading * max(v, 120)
            events.insert(.portal)
            break
        }
        if ball.p.distance(to: hole.cup) < cupRadius - 3, ball.v.length < 300 { events.insert(.sunk) }
        return events
    }

    /// For a ball at rest: does a moving rail or blade knock it? Pushes it out if so.
    static func knock(_ ball: inout GolfBall, hole: GolfHole, time: Double) -> Bool {
        let reach = railRadius + ballRadius
        var hit = false
        for m in hole.movers where collide(&ball, m.segment(at: time), radius: reach, restitution: 0.8, surface: m.velocity(at: time)) { hit = true }
        for s in hole.spinners {
            let seg = s.segment(at: time)
            let q = closest(ball.p, seg.a, seg.b)
            let w = CGFloat(s.speed)
            let surface = CGVector(dx: -w * (q.y - s.center.y), dy: w * (q.x - s.center.x))
            if collide(&ball, seg, radius: reach, restitution: 0.8, surface: surface) { hit = true }
        }
        for p in hole.paddles where collide(&ball, p.segment(at: time), radius: reach, restitution: 0.8,
                                            surface: paddleSurface(p, at: ball.p, time: time)) { hit = true }
        return hit
    }

    /// How fast a swinging paddle's face moves at a point on it.
    static func paddleSurface(_ p: GolfPaddle, at point: CGPoint, time: Double) -> CGVector {
        let seg = p.segment(at: time)
        let q = closest(point, seg.a, seg.b)
        let w = CGFloat(p.omega(at: time))
        return CGVector(dx: -w * (q.y - p.pivot.y), dy: w * (q.x - p.pivot.x))
    }

    /// The path the ball would take, up to a little past its first bounce.
    static func preview(from p: CGPoint, velocity: CGVector, hole: GolfHole, opened: UInt32 = 0) -> [CGPoint] {
        var ball = GolfBall(p: p, v: velocity, opened: opened)
        var points: [CGPoint] = []
        var buffer: [GolfSeg] = []
        var last = p, travelled: CGFloat = 0, afterBounce: CGFloat?
        for _ in 0..<600 {
            let e = step(&ball, hole: hole, time: 0, moving: false, h: 1.0 / 120, buffer: &buffer)
            let moved = ball.p.distance(to: last)
            if e.contains(.portal) || e.contains(.teleport) || e.contains(.water) { break }
            travelled += moved
            if let a = afterBounce { afterBounce = a + moved }
            if e.contains(.bounce) || e.contains(.bumper) || e.contains(.spring), afterBounce == nil { afterBounce = 0 }
            if travelled >= 13 * CGFloat(points.count + 1) { points.append(ball.p) }
            last = ball.p
            if (afterBounce ?? 0) > 46 || travelled > 340 || ball.v.length < 20 || e.contains(.sunk) { break }
        }
        return points
    }

    @discardableResult
    static func collide(_ ball: inout GolfBall, _ s: GolfSeg, radius: CGFloat, restitution: CGFloat, surface: CGVector) -> Bool {
        let q = closest(ball.p, s.a, s.b)
        let dx = ball.p.x - q.x, dy = ball.p.y - q.y
        let d = hypot(dx, dy)
        guard d < radius else { return false }
        let n = d > 0.001 ? CGVector(dx: dx / d, dy: dy / d) : CGVector(dx: 0, dy: -1)
        ball.p = q + n * radius
        let rel = ball.v - surface
        let dot = rel.dx * n.dx + rel.dy * n.dy
        guard dot < 0 else { return false }
        ball.v = ball.v - n * ((1 + restitution) * dot)
        return true
    }

    static func closest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.001, dx * dx + dy * dy)))
        return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    }
}

extension CGPoint {
    func distance(to p: CGPoint) -> CGFloat { hypot(x - p.x, y - p.y) }
    static func + (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x + v.dx, y: p.y + v.dy) }
    static func - (p: CGPoint, v: CGVector) -> CGPoint { CGPoint(x: p.x - v.dx, y: p.y - v.dy) }
}

extension CGVector {
    var length: CGFloat { hypot(dx, dy) }
    static func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
    static func - (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx - b.dx, dy: a.dy - b.dy) }
    static func * (a: CGVector, k: CGFloat) -> CGVector { CGVector(dx: a.dx * k, dy: a.dy * k) }
}

// MARK: - Holes

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func box(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
    [P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)]
}
private func wall(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> GolfSeg { GolfSeg(a: P(x0, y0), b: P(x1, y1)) }
private func zone(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ r: CGFloat = 18) -> GolfZone {
    GolfZone(rect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), radius: r)
}

enum GolfHoles {
    /// 24 hand-made holes, then 76 generated ones (`GolfHoles.generated`) in six worlds.
    static let all: [GolfHole] = classic + generated

    /// A world: a run of holes with its own colours and its own new piece.
    struct World {
        let name: String
        let first: Int
        let last: Int
        /// What's new here, shown under the course.
        var hint: String?
    }

    static let worlds: [World] = [
        World(name: "First Steps", first: 1, last: 24),
        World(name: "Ice Rink", first: 25, last: 37, hint: "Ice keeps the ball sliding. Arrow pads speed it up."),
        World(name: "Portal Park", first: 38, last: 50, hint: "Roll into a ring and the ball pops out of its twin."),
        World(name: "Switch Yard", first: 51, last: 63, hint: "Roll over a button to drop the gate of the same colour."),
        World(name: "Spring Fair", first: 64, last: 76, hint: "Yellow springs kick the ball away. Mind the swinging paddles."),
        World(name: "Clockwork", first: 77, last: 89, hint: "Time your shot past the moving rails, windmills and paddles."),
        World(name: "Grand Tour", first: 90, last: 100),
    ]

    static func world(of level: Int) -> World? { worlds.first { (($0.first)...($0.last)).contains(level) } }

    /// The 24 hand-made holes. New pieces arrive one at a time: rails, then
    /// slopes, sand and water, bumpers, moving rails and windmills, and tunnels.
    static let classic: [GolfHole] = [
        // 1. Straight in.
        GolfHole(par: 2, tee: P(160, 395), cup: P(160, 95), outline: box(80, 40, 240, 440)),
        // 2. Dogleg: bank off the far rail.
        GolfHole(par: 2, tee: P(95, 400), cup: P(240, 100),
                 outline: [P(40, 440), P(150, 440), P(150, 180), P(285, 180), P(285, 35), P(40, 35)]),
        // 3. A rail across the middle.
        GolfHole(par: 2, tee: P(160, 400), cup: P(160, 90), outline: box(45, 35, 275, 440),
                 walls: [wall(110, 250, 210, 250)]),
        // 4. Zigzag.
        GolfHole(par: 3, tee: P(90, 405), cup: P(220, 90), outline: box(40, 35, 280, 450),
                 walls: [wall(40, 320, 190, 320), wall(130, 175, 280, 175)]),
        // 5. The cup in a pocket that opens at the top.
        GolfHole(par: 2, tee: P(160, 405), cup: P(160, 135), outline: [P(50, 35), P(270, 35), P(270, 440), P(50, 440)],
                 walls: [wall(110, 175, 210, 175), wall(110, 175, 110, 112), wall(210, 175, 210, 112)]),
        // 6. First slope.
        GolfHole(par: 2, tee: P(160, 400), cup: P(105, 90), outline: box(60, 35, 260, 440),
                 slopes: [GolfSlope(zone: zone(60, 170, 260, 300, 8), push: CGVector(dx: 190, dy: 0))]),
        // 7. Two slopes, opposite ways.
        GolfHole(par: 3, tee: P(160, 410), cup: P(160, 85), outline: [P(40, 35), P(280, 35), P(280, 450), P(40, 450)],
                 walls: [wall(160, 200, 160, 250)],
                 slopes: [GolfSlope(zone: zone(40, 270, 280, 345, 8), push: CGVector(dx: -200, dy: 0)),
                          GolfSlope(zone: zone(40, 120, 280, 195, 8), push: CGVector(dx: 200, dy: 0))]),
        // 8. A dip around the cup behind a rail.
        GolfHole(par: 2, tee: P(160, 405), cup: P(160, 135), outline: box(50, 35, 270, 445),
                 walls: [wall(105, 245, 215, 245)],
                 mounds: [GolfMound(center: P(160, 135), radius: 90, strength: 260)]),
        // 9. A hump in the way.
        GolfHole(par: 2, tee: P(160, 405), cup: P(160, 85),
                 outline: [P(110, 35), P(210, 35), P(270, 120), P(270, 360), P(210, 445), P(110, 445), P(50, 360), P(50, 120)],
                 mounds: [GolfMound(center: P(160, 240), radius: 85, strength: -320)]),
        // 10. Bunker.
        GolfHole(par: 2, tee: P(110, 405), cup: P(110, 95),
                 outline: [P(160, 30), P(285, 110), P(285, 445), P(35, 445), P(35, 110)],
                 sand: [zone(35, 210, 212, 290, 24)]),
        // 11. Pond.
        GolfHole(par: 3, tee: P(95, 405), cup: P(95, 90), outline: box(40, 35, 280, 450),
                 sand: [zone(200, 120, 280, 175, 20)],
                 water: [zone(40, 190, 212, 285, 28)]),
        // 12. Bridge between two ponds.
        GolfHole(par: 2, tee: P(160, 410), cup: P(232, 80), outline: box(30, 35, 290, 450),
                 water: [zone(30, 150, 128, 320, 26), zone(192, 150, 290, 320, 26)]),
        // 13. Dogleg with a bunker at the bend and a pond at the end.
        GolfHole(par: 3, tee: P(225, 405), cup: P(80, 85),
                 outline: [P(170, 445), P(285, 445), P(285, 35), P(35, 35), P(35, 195), P(170, 195)],
                 sand: [zone(200, 40, 285, 125, 26)],
                 water: [zone(110, 140, 170, 195, 18)]),
        // 14. Pinball.
        GolfHole(par: 2, tee: P(160, 410), cup: P(160, 80), outline: box(40, 35, 280, 450),
                 bumpers: [GolfBumper(center: P(160, 300), radius: 18), GolfBumper(center: P(102, 210), radius: 16),
                           GolfBumper(center: P(218, 210), radius: 16), GolfBumper(center: P(160, 145), radius: 18)]),
        // 15. Crossroads with a bumper in the middle.
        GolfHole(par: 2, tee: P(160, 405), cup: P(250, 210),
                 outline: [P(120, 445), P(200, 445), P(200, 250), P(290, 250), P(290, 170), P(200, 170), P(200, 35),
                           P(120, 35), P(120, 170), P(30, 170), P(30, 250), P(120, 250)],
                 bumpers: [GolfBumper(center: P(160, 210), radius: 18)]),
        // 16. Bumpers over a bunker.
        GolfHole(par: 3, tee: P(80, 410), cup: P(225, 90), outline: box(40, 35, 280, 450),
                 walls: [wall(40, 340, 170, 340)],
                 bumpers: [GolfBumper(center: P(110, 240), radius: 16), GolfBumper(center: P(210, 240), radius: 16),
                           GolfBumper(center: P(160, 170), radius: 16)],
                 sand: [zone(40, 60, 140, 130, 22)]),
        // 17. A sliding gate.
        GolfHole(par: 2, tee: P(160, 405), cup: P(160, 90), outline: box(60, 35, 260, 445),
                 walls: [wall(60, 240, 118, 240), wall(202, 240, 260, 240)],
                 movers: [GolfMover(base: wall(132, 240, 188, 240), travel: CGVector(dx: 42, dy: 0), period: 2.6)]),
        // 18. Windmill.
        GolfHole(par: 2, tee: P(160, 405), cup: P(160, 85), outline: box(70, 35, 250, 445),
                 spinners: [GolfSpinner(center: P(160, 250), arm: 74, speed: 1.3)]),
        // 19. Two gates out of step.
        GolfHole(par: 3, tee: P(160, 412), cup: P(160, 82), outline: box(50, 35, 270, 450),
                 walls: [wall(50, 320, 115, 320), wall(205, 320, 270, 320), wall(50, 175, 115, 175), wall(205, 175, 270, 175)],
                 movers: [GolfMover(base: wall(135, 320, 185, 320), travel: CGVector(dx: 45, dy: 0), period: 2.2),
                          GolfMover(base: wall(135, 175, 185, 175), travel: CGVector(dx: 45, dy: 0), period: 2.8, phase: 0.5)]),
        // 20. First tunnel: the only way through the wall.
        GolfHole(par: 2, tee: P(90, 405), cup: P(232, 85), outline: box(30, 35, 290, 450),
                 walls: [wall(30, 240, 290, 240)],
                 portals: [GolfPortal(entry: P(240, 330), exit: P(80, 160))]),
        // 21. Tunnel over a pond.
        GolfHole(par: 3, tee: P(160, 410), cup: P(240, 80), outline: box(30, 35, 290, 450),
                 water: [zone(30, 170, 290, 250, 20)],
                 portals: [GolfPortal(entry: P(160, 300), exit: P(75, 120))]),
        // 22. A windmill guarding the tunnel.
        GolfHole(par: 3, tee: P(160, 412), cup: P(225, 80), outline: box(40, 35, 280, 450),
                 walls: [wall(40, 225, 280, 225)],
                 spinners: [GolfSpinner(center: P(160, 335), arm: 68, speed: -1.2)],
                 portals: [GolfPortal(entry: P(160, 270), exit: P(90, 175))]),
        // 23. Uphill around the corner.
        GolfHole(par: 3, tee: P(90, 405), cup: P(175, 75),
                 outline: [P(40, 445), P(200, 445), P(200, 330), P(285, 330), P(285, 35), P(130, 35), P(130, 140), P(40, 140)],
                 bumpers: [GolfBumper(center: P(200, 235), radius: 15)],
                 slopes: [GolfSlope(zone: zone(40, 150, 200, 300, 10), push: CGVector(dx: 0, dy: 150))]),
        // 24. Everything at once.
        GolfHole(par: 4, tee: P(70, 410), cup: P(80, 80), outline: box(30, 35, 290, 450),
                 walls: [wall(30, 300, 200, 300), wall(30, 150, 140, 150)],
                 bumpers: [GolfBumper(center: P(105, 235), radius: 14), GolfBumper(center: P(178, 240), radius: 14)],
                 sand: [zone(200, 40, 290, 105, 22)],
                 water: [zone(30, 160, 125, 200, 16)],
                 slopes: [GolfSlope(zone: zone(200, 320, 290, 450, 10), push: CGVector(dx: 0, dy: 120))],
                 spinners: [GolfSpinner(center: P(215, 150), arm: 58, speed: 1.1)]),
    ]
}
