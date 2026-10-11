import Foundation
import CoreGraphics

enum ArrowMazeOutcome: Equatable { case moving, crashed, escaped }

/// Deterministic rules with no SpriteKit nodes, timers, persistence or side effects.
struct ArrowMazeSimulation {
    static let tipOffset: CGFloat = 18
    static let tipRadius: CGFloat = 4
    static let bodyRadius: CGFloat = 10
    static let gemRadius: CGFloat = 10
    static let exitRadius: CGFloat = 22
    static let turnAssistDistance: CGFloat = 18
    /// Speed added once every gem is collected; it ramps up gem by gem.
    static let maximumBoost: CGFloat = 0.75
    static let turnCooldown: TimeInterval = 0.12

    let level: ArrowMazeLevel
    private(set) var position: CGPoint
    private(set) var heading: ArrowMazeHeading
    private(set) var collected: Set<Int> = []
    private(set) var elapsed: TimeInterval = 0
    private(set) var turns = 0
    private(set) var outcome: ArrowMazeOutcome = .moving
    private var lastTurnTime: TimeInterval = -.infinity

    init(level: ArrowMazeLevel) {
        self.level = level
        position = level.spawn
        heading = level.initialHeading
    }

    var tip: CGPoint { tip(at: position, angle: heading.angle) }
    var exitUnlocked: Bool { collected.count == level.gemCells.count }
    var speedMultiplier: CGFloat {
        guard !level.gemCells.isEmpty else { return 1 }
        return 1 + Self.maximumBoost * CGFloat(collected.count) / CGFloat(level.gemCells.count)
    }
    var speed: CGFloat { level.speed * speedMultiplier }
    var score: Int {
        collected.count * 100 + (outcome == .escaped ? 500 + max(0, 300 - Int(elapsed) * 5) : 0)
    }

    mutating func step(_ deltaTime: TimeInterval) {
        guard outcome == .moving, deltaTime.isFinite, deltaTime > 0 else { return }
        // The scene supplies 1/120 s. Bound callers as a final safety net.
        let dt = min(deltaTime, 1.0 / 30)
        elapsed += dt
        let oldPosition = position, oldTip = tip
        let dx = cos(heading.angle) * speed * CGFloat(dt)
        let dy = sin(heading.angle) * speed * CGFloat(dt)
        let next = CGPoint(x: oldPosition.x + dx, y: oldPosition.y + dy)
        let nextTip = tip(at: next, angle: heading.angle)
        if hitsWall(from: oldPosition, to: next, radius: Self.bodyRadius)
            || hitsWall(from: oldTip, to: nextTip, radius: Self.tipRadius) {
            outcome = .crashed
            return
        }
        position = next
        collectAlongSegment(from: oldTip, to: nextTip)
        checkExit(from: oldTip, to: nextTip)
    }

    @discardableResult
    mutating func turn(_ direction: ArrowMazeTurn) -> Bool {
        guard outcome == .moving, elapsed - lastTurnTime >= Self.turnCooldown else { return false }
        let center = level.center(of: level.cell(at: position))
        // Faster flight gets a proportionally wider assist window.
        let assist = max(Self.turnAssistDistance, speed * 0.1)
        let aligned = hypot(center.x - position.x, center.y - position.y) <= assist ? center : position
        let oldTip = tip
        let alignedTip = tip(at: aligned, angle: heading.angle)
        guard !hitsWall(from: position, to: aligned, radius: Self.bodyRadius),
              !hitsWall(from: oldTip, to: alignedTip, radius: Self.tipRadius) else {
            outcome = .crashed
            return false
        }
        let rotation: CGFloat = direction == .left ? .pi / 2 : -.pi / 2
        var previousTip = alignedTip
        // Check the swept tip during a turn as well as during forward motion.
        for sample in 1...8 {
            let nextTip = tip(at: aligned, angle: heading.angle + rotation * CGFloat(sample) / 8)
            if hitsWall(from: previousTip, to: nextTip, radius: Self.tipRadius) {
                outcome = .crashed
                return false
            }
            previousTip = nextTip
        }
        position = aligned
        heading = heading.turned(direction)
        turns += 1
        lastTurnTime = elapsed
        // Turning onto a gem/exit counts; repeats remain idempotent.
        collectAlongSegment(from: tip, to: tip)
        checkExit(from: tip, to: tip)
        return true
    }

    /// SpriteKit contacts supplement the deterministic swept checks. A delayed
    /// callback is accepted only if it still matches the current simulation pose.
    mutating func contactWall() {
        guard outcome == .moving else { return }
        if hitsWall(from: tip, to: tip, radius: Self.tipRadius) { outcome = .crashed }
    }
    mutating func contactGem(_ index: Int) {
        guard outcome == .moving, level.gemCells.indices.contains(index), !collected.contains(index) else { return }
        let gem = level.center(of: level.gemCells[index])
        if hypot(tip.x - gem.x, tip.y - gem.y) <= Self.tipRadius + Self.gemRadius {
            collected.insert(index)
        }
    }
    mutating func contactExit() {
        guard outcome == .moving else { return }
        checkExit(from: tip, to: tip)
    }

    private func tip(at p: CGPoint, angle: CGFloat) -> CGPoint {
        CGPoint(x: p.x + cos(angle) * Self.tipOffset, y: p.y + sin(angle) * Self.tipOffset)
    }
    private mutating func collectAlongSegment(from a: CGPoint, to b: CGPoint) {
        for index in level.gemCells.indices where !collected.contains(index) {
            let gem = level.center(of: level.gemCells[index])
            if Self.distance(gem, toSegmentFrom: a, to: b) <= Self.tipRadius + Self.gemRadius {
                collected.insert(index)
            }
        }
    }
    private mutating func checkExit(from a: CGPoint, to b: CGPoint) {
        if exitUnlocked, Self.distance(level.exit, toSegmentFrom: a, to: b) <= Self.exitRadius + Self.tipRadius {
            outcome = .escaped
        }
    }

    private func hitsWall(from a: CGPoint, to b: CGPoint, radius: CGFloat) -> Bool {
        // Spatial query touches only nearby grid cells, not every maze wall.
        let tile = ArrowMazeLevel.tileSize
        let left = Int(floor((min(a.x, b.x) - radius) / tile))
        let right = Int(floor((max(a.x, b.x) + radius) / tile))
        let bottom = Int(floor((min(a.y, b.y) - radius) / tile))
        let top = Int(floor((max(a.y, b.y) + radius) / tile))
        for row in bottom...top {
            for column in left...right {
                let cell = ArrowMazeCell(column: column, row: row)
                if !level.floors.contains(cell), Self.intersectsSegment(from: a, to: b, rect: level.rect(of: cell).insetBy(dx: -radius, dy: -radius)) {
                    return true
                }
            }
        }
        return false
    }

    /// Slab intersection against an expanded AABB. Conservative at wall corners,
    /// exact on straight corridor faces; prevents manually moved bodies tunnelling.
    static func intersectsSegment(from a: CGPoint, to b: CGPoint, rect: CGRect) -> Bool {
        var enter: CGFloat = 0, exit: CGFloat = 1
        for (origin, delta, low, high) in [(a.x, b.x - a.x, rect.minX, rect.maxX),
                                          (a.y, b.y - a.y, rect.minY, rect.maxY)] {
            if abs(delta) < 0.000001 {
                if origin < low || origin > high { return false }
            } else {
                let first = (low - origin) / delta, last = (high - origin) / delta
                enter = max(enter, min(first, last))
                exit = min(exit, max(first, last))
                if enter > exit { return false }
            }
        }
        return true
    }
    static func distance(_ p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let fraction = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.000001, dx * dx + dy * dy)))
        return hypot(p.x - a.x - fraction * dx, p.y - a.y - fraction * dy)
    }
}
