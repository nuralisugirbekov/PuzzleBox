import SwiftUI
import Observation

/// Road layout around the lot, in lot units (one unit per parking cell).
enum CarParkRoad {
    /// Kerb between the lot and the road.
    static let kerb: CGFloat = 0.14
    static let width: CGFloat = 0.95
    /// Distance from the lot's edge to the middle of the road.
    static var lane: CGFloat { kerb + width / 2 }
    /// Pavement beyond the road, to the edge of the board.
    static let pavement: CGFloat = 0.32
    static var margin: CGFloat { kerb + width + pavement }
}

/// A vehicle sliding inside the lot.
struct CarParkSlide {
    /// Where it started, relative to where it is now, in cells.
    let from: CGVector
    let start: Double
    let duration: Double
    /// It ends by hitting something.
    let bumps: Bool
    /// Unit vector of travel, for the shake.
    let heading: CGVector
}

/// A vehicle on its way out: down its lane onto the road, then along the road off the board.
struct CarParkLeaving: Identifiable {
    let id: Int
    let vehicle: CarParkVehicle
    /// Start, the road, the far end of the road.
    let path: [CGPoint]
    /// The nose's angle while it pulls out (it may be reversing).
    let pullOutAngle: Double
    var travelled: CGFloat = 0
    var speed: CGFloat = 3
    var waiting = false
    var honkAt: Double?
    let gate: CarParkEdge

    var lengths: [CGFloat] { zip(path, path.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) } }
    var total: CGFloat { lengths.reduce(0, +) }
    var onRoad: Bool { travelled >= (lengths.first ?? 0) }
}

/// Someone crossing along the road in front of the lot.
struct CarParkWalker {
    let side: CarParkSide
    var along: CGFloat
    var dir: CGFloat
    let speed: CGFloat
    let color: Int
}

struct CarParkPuff {
    let at: CGPoint
    let time: Double
}

@MainActor
@Observable
final class CarParkEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var level = 1
    private(set) var lot: CarParkLot
    private(set) var bumps = 0
    private(set) var moves = 0
    private(set) var time: Double = 0
    private(set) var slides: [Int: CarParkSlide] = [:]
    /// Vehicles that were hit, and when.
    private(set) var jolts: [Int: Double] = [:]
    private(set) var leaving: [CarParkLeaving] = []
    private(set) var walkers: [CarParkWalker] = []
    private(set) var puffs: [CarParkPuff] = []
    private(set) var notice = ""
    private(set) var bestStars: [Int: Int] = [:]
    private(set) var cleared = false

    var active = false
    var reduceMotion = false

    static var levelCount: Int { CarParkLevels.count }
    private let levelKey = "carPark.level"
    private let starsKey = "carPark.stars"
    private var pendingEnd: Double?
    private var total = 0
    /// The lot as generated, so a restart skips building it again.
    @ObservationIgnored private var built: (level: Int, lot: CarParkLot)?

    init() {
        let saved = UserDefaults.standard.integer(forKey: levelKey)
        let start = max(1, min(CarParkLevels.count, saved))
        level = start
        lot = CarParkLevels.make(level: start)
        if let stored = UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] {
            bestStars = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, value) } })
        }
        restart()
    }

    var hasNextLevel: Bool { level < Self.levelCount }
    var vehiclesLeft: Int { lot.vehicles.count }
    var vehicleCount: Int { total }
    /// No bumps: three stars; up to two: two; more: one.
    var stars: Int { bumps == 0 ? 3 : bumps <= 2 ? 2 : 1 }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: levelKey)
        restart()
    }

    func nextLevel() { selectLevel(level + 1) }

    func restart() {
        if built?.level != level { built = (level, CarParkLevels.make(level: level)) }
        lot = built!.lot
        total = lot.vehicles.count
        bumps = 0; moves = 0; score = 0
        slides = [:]; jolts = [:]; leaving = []; puffs = []
        notice = ""; pendingEnd = nil; cleared = false
        state = .playing
        walkers = makeWalkers()
    }

    private func makeWalkers() -> [CarParkWalker] {
        let open = CarParkSide.allCases.filter { side in
            let span = side == .top || side == .bottom ? lot.columns : lot.rows
            return (0..<span).contains { !lot.fence.contains(CarParkEdge(side: side, index: $0)) }
        }
        guard !open.isEmpty else { return [] }
        return (0..<lot.walkers).map { i in
            let side = open[(i * 3 + level) % open.count]
            let span = CGFloat(side == .top || side == .bottom ? lot.columns : lot.rows)
            return CarParkWalker(side: side, along: span * CGFloat((i * 37 + level * 13) % 100) / 100,
                                 dir: i.isMultiple(of: 2) ? 1 : -1, speed: 0.55 + 0.1 * CGFloat(i % 3), color: i + level)
        }
    }

    // MARK: Driving

    func vehicle(at cell: GridPos) -> CarParkVehicle? {
        lot.vehicles.first { $0.cells.contains(cell) }
    }

    /// Drives vehicle `id` along its length, `dir` +1 toward growing rows or
    /// columns, −1 back. It goes until something stops it, or out onto the road.
    func drive(_ id: Int, dir: Int) {
        guard state == .playing, pendingEnd == nil, slides[id] == nil,
              let index = lot.vehicles.firstIndex(where: { $0.id == id }) else { return }
        let vehicle = lot.vehicles[index]
        let result = CarParkLot.drive(vehicle, dir: dir, lot: lot,
                                      occupied: lot.occupancy(of: lot.vehicles), propCells: lot.propCells)
        let heading = vehicle.horizontal ? CGVector(dx: CGFloat(dir), dy: 0) : CGVector(dx: 0, dy: CGFloat(dir))
        moves += 1
        notice = ""
        switch result.stop {
        case .exit(let edge):
            lot.vehicles.remove(at: index)
            leaving.append(leave(vehicle, dir: dir, through: edge))
            Haptics.tap(); SoundFX.play(.whoosh)
        case .vehicle, .prop, .fence:
            let moved = vehicle.moved(by: result.cells * dir)
            lot.vehicles[index] = moved
            let duration = reduceMotion ? 0.05 : 0.1 + 0.07 * Double(result.cells)
            slides[id] = CarParkSlide(from: CGVector(dx: -heading.dx * CGFloat(result.cells), dy: -heading.dy * CGFloat(result.cells)),
                                      start: time, duration: duration, bumps: true, heading: heading)
            bumps += 1
            if case .vehicle(let other) = result.stop { jolts[other] = time + duration }
            let front = moved.cell(ahead: dir, by: 0)
            let contact = CGPoint(x: CGFloat(front.c) + 0.5 + heading.dx * 0.5, y: CGFloat(front.r) + 0.5 + heading.dy * 0.5)
            puffs.append(CarParkPuff(at: contact, time: time + duration))
            notice = "Bump!"
            Haptics.error(); SoundFX.play(.hit)
        }
    }

    private func leave(_ vehicle: CarParkVehicle, dir: Int, through edge: CarParkEdge) -> CarParkLeaving {
        let c = vehicle.center
        let lane = CarParkRoad.lane
        let far = CGFloat(3.5)
        let cols = CGFloat(lot.columns), rows = CGFloat(lot.rows)
        let horizontalRoad = edge.side == .top || edge.side == .bottom
        let along = horizontalRoad ? c.x : c.y
        let span = horizontalRoad ? cols : rows
        // Head for the nearer end of the road, unless someone is walking that way.
        var toward: CGFloat = along < span / 2 ? -1 : 1
        let ahead = walkers.contains { $0.side == edge.side && ($0.along - along) * toward > 0 && abs($0.along - along) < 3 }
        if ahead { toward = -toward }
        let target = toward < 0 ? -far : span + far
        let road: CGPoint, end: CGPoint
        switch edge.side {
        case .top:
            road = CGPoint(x: c.x, y: -lane); end = CGPoint(x: target, y: -lane)
        case .bottom:
            road = CGPoint(x: c.x, y: rows + lane); end = CGPoint(x: target, y: rows + lane)
        case .left:
            road = CGPoint(x: -lane, y: c.y); end = CGPoint(x: -lane, y: target)
        case .right:
            road = CGPoint(x: cols + lane, y: c.y); end = CGPoint(x: cols + lane, y: target)
        }
        return CarParkLeaving(id: vehicle.id, vehicle: vehicle, path: [c, road, end],
                              pullOutAngle: CarParkGeometry.noseAngle(vehicle), gate: edge)
    }

    // MARK: Time

    func advance(_ dt: Double) {
        guard active, state == .playing else { return }
        let d = min(0.05, max(0, dt))
        time += d
        if let pendingEnd, time >= pendingEnd {
            self.pendingEnd = nil
            state = .gameOver(won: true)
            return
        }
        for (id, slide) in slides where time > slide.start + slide.duration + 0.35 { slides[id] = nil }
        for (id, at) in jolts where time > at + 0.5 { jolts[id] = nil }
        puffs.removeAll { time > $0.time + 0.6 }
        moveWalkers(CGFloat(d))
        moveLeaving(CGFloat(d))
        if lot.vehicles.isEmpty, leaving.isEmpty, !cleared { finish() }
    }

    private func moveWalkers(_ d: CGFloat) {
        for i in walkers.indices {
            let side = walkers[i].side
            let span = CGFloat(side == .top || side == .bottom ? lot.columns : lot.rows)
            walkers[i].along += walkers[i].dir * walkers[i].speed * d
            if walkers[i].along > span + 0.4 { walkers[i].along = span + 0.4; walkers[i].dir = -1 }
            if walkers[i].along < -0.4 { walkers[i].along = -0.4; walkers[i].dir = 1 }
        }
    }

    /// Where a walker is, in lot units.
    func position(of walker: CarParkWalker) -> CGPoint {
        let lane = CarParkRoad.lane, cols = CGFloat(lot.columns), rows = CGFloat(lot.rows)
        switch walker.side {
        case .top: return CGPoint(x: walker.along, y: -lane)
        case .bottom: return CGPoint(x: walker.along, y: rows + lane)
        case .left: return CGPoint(x: -lane, y: walker.along)
        case .right: return CGPoint(x: cols + lane, y: walker.along)
        }
    }

    private func moveLeaving(_ d: CGFloat) {
        for i in leaving.indices {
            var car = leaving[i]
            let first = car.lengths.first ?? 0
            // At the road, wait for anyone walking past.
            if car.travelled >= first - 0.05, car.travelled < first + 0.4 {
                let road = car.path[1]
                let blocked = walkers.contains { w in
                    let p = position(of: w)
                    return hypot(p.x - road.x, p.y - road.y) < 0.95
                }
                if blocked {
                    if !car.waiting {
                        car.waiting = true
                        car.honkAt = time
                        notice = "Beep! Let them cross."
                        SoundFX.play(.tick)
                    }
                    car.speed = 0
                    leaving[i] = car
                    continue
                }
                if car.waiting { car.waiting = false; notice = "" }
            }
            car.speed = min(car.onRoad ? 9 : 5, car.speed + 14 * d)
            car.travelled += car.speed * d
            leaving[i] = car
        }
        leaving.removeAll { $0.travelled >= $0.total }
    }

    private func finish() {
        cleared = true
        let earned = stars
        score = 100 + level * 20 + earned * 60
        if earned > (bestStars[level] ?? 0) {
            bestStars[level] = earned
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: bestStars.map { (String($0.key), $0.value) }), forKey: starsKey)
        }
        UserDefaults.standard.set(min(Self.levelCount, level + 1), forKey: levelKey)
        notice = bumps == 0 ? "Not a scratch!" : ""
        Haptics.success(); SoundFX.play(.win)
        pendingEnd = time + 0.6
    }

    // MARK: Preview

    /// A mid level with a few vehicles gone and someone on the road, for the
    /// Home preview. Nothing is saved.
    func showcase() {
        level = 18
        restart()
        for _ in 0..<3 {
            let occupied = lot.occupancy(of: lot.vehicles), props = lot.propCells
            guard let index = lot.vehicles.lastIndex(where: { v in
                [1, -1].contains { dir in
                    if case .exit = CarParkLot.drive(v, dir: dir, lot: lot, occupied: occupied, propCells: props).stop { return true }
                    return false
                }
            }) else { break }
            lot.vehicles.remove(at: index)
        }
        walkers = [CarParkWalker(side: .bottom, along: 1.6, dir: 1, speed: 0.6, color: 2)]
    }
}

/// Angles and positions shared by the engine and the board.
enum CarParkGeometry {
    /// The nose's direction in radians, 0 pointing right.
    static func noseAngle(_ v: CarParkVehicle) -> Double {
        if v.horizontal { return v.facesForward ? 0 : .pi }
        return v.facesForward ? .pi / 2 : -.pi / 2
    }

    /// Where a leaving vehicle is, and its nose angle.
    static func place(_ car: CarParkLeaving) -> (CGPoint, Double) {
        let lengths = car.lengths
        var s = car.travelled
        let a = car.path[0], b = car.path[1], c = car.path[2]
        let roadAngle = atan2(Double(c.y - b.y), Double(c.x - b.x))
        if s <= lengths[0] {
            let t = lengths[0] > 0 ? s / lengths[0] : 1
            return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), car.pullOutAngle)
        }
        s -= lengths[0]
        let t = lengths[1] > 0 ? min(1, s / lengths[1]) : 1
        let p = CGPoint(x: b.x + (c.x - b.x) * t, y: b.y + (c.y - b.y) * t)
        // Swing round onto the road over the first stretch of it.
        let turn = min(1, Double(s) / 0.7)
        var delta = roadAngle - car.pullOutAngle
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        let eased = turn * turn * (3 - 2 * turn)
        return (p, car.pullOutAngle + delta * eased)
    }
}
