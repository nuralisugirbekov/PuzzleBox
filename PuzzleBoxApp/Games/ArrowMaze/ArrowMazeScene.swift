import SpriteKit
import UIKit

enum ArrowMazePhysics {
    static let arrow: UInt32 = 1 << 0
    static let wall: UInt32 = 1 << 1
    static let gem: UInt32 = 1 << 2
    static let exit: UInt32 = 1 << 3
}

/// SpriteKit owns the frame loop and rendering; the engine owns game state.
@MainActor
final class ArrowMazeScene: SKScene, @preconcurrency SKPhysicsContactDelegate {
    private weak var engine: ArrowMazeEngine?
    private let trackingCamera = SKCameraNode()
    private let rocket = SKNode()
    private let flame = SKNode()
    private let exhaust = SKEmitterNode()
    private let tipSensor = SKNode()
    private let exitRing = SKShapeNode(circleOfRadius: ArrowMazeSimulation.exitRadius)
    private var gemNodes: [Int: SKNode] = [:]
    private var exploded = false
    private var shownBoost: CGFloat = 1
    private var appliedRevision = -1
    private var previousTime: TimeInterval?
    private var accumulator: TimeInterval = 0
    private var pendingWall = false
    private var pendingExit = false
    private var pendingGems: Set<Int> = []
    private let fixedStep: TimeInterval = 1.0 / 120
    private let maximumFrameTime: TimeInterval = 1.0 / 15
    var reduceMotion = false

    init(engine: ArrowMazeEngine) {
        self.engine = engine
        super.init(size: CGSize(width: 360, height: 460))
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.02, green: 0.025, blue: 0.07, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
    }
    required init?(coder: NSCoder) { fatalError("ArrowMazeScene is created programmatically") }

    override func didMove(to view: SKView) { synchronizeLevel() }
    override func didChangeSize(_ oldSize: CGSize) { updateCamera(deltaTime: 0, snap: true) }

    func resetFrameClock() {
        previousTime = nil
        accumulator = 0
        pendingWall = false
        pendingExit = false
        pendingGems.removeAll(keepingCapacity: true)
    }
    func detach() {
        resetFrameClock()
        physicsWorld.contactDelegate = nil
        removeAllActions()
    }

    func synchronizeLevel() {
        guard let engine, appliedRevision != engine.revision else { return }
        appliedRevision = engine.revision
        resetFrameClock()
        removeAllChildren()
        // Reusable nodes must be detached from their old parents too.
        rocket.removeAllChildren()
        rocket.removeAllActions()
        rocket.isHidden = false
        exitRing.removeAllChildren()
        exitRing.removeAllActions()
        gemNodes.removeAll(keepingCapacity: true)
        exploded = false
        shownBoost = 1
        addChild(trackingCamera)
        camera = trackingCamera
        physicsWorld.contactDelegate = self

        let level = engine.level
        let landscape = SKSpriteNode(texture: ArrowMazeArt.landscape(for: level, seed: engine.levelIndex))
        landscape.anchorPoint = .zero
        landscape.size = level.bounds.size
        landscape.zPosition = -10
        addChild(landscape)
        addTwinklingStars(level: level, seed: engine.levelIndex)

        // Invisible physics: one static body per horizontal wall run, instead of one per tile.
        for row in 0..<level.rows {
            var start: Int?
            for column in 0...level.columns {
                let wall = column < level.columns && !level.floors.contains(ArrowMazeCell(column: column, row: row))
                if wall && start == nil { start = column }
                if !wall, let first = start {
                    let tile = ArrowMazeLevel.tileSize
                    let rect = CGRect(x: CGFloat(first) * tile, y: CGFloat(row) * tile,
                                      width: CGFloat(column - first) * tile, height: tile)
                    let node = SKNode()
                    node.position = CGPoint(x: rect.midX, y: rect.midY)
                    node.physicsBody = sensor(rectangle: rect.size, category: ArrowMazePhysics.wall)
                    addChild(node)
                    start = nil
                }
            }
        }
        for (index, point) in level.gems.enumerated() {
            let node = ArrowMazeArt.star(radius: ArrowMazeSimulation.gemRadius, reduceMotion: reduceMotion, phase: Double(index) * 0.37)
            node.name = "gem:\(index)"
            node.position = point
            node.zPosition = 2
            node.physicsBody = sensor(circle: ArrowMazeSimulation.gemRadius, category: ArrowMazePhysics.gem)
            gemNodes[index] = node
            addChild(node)
        }
        exitRing.position = level.exit
        exitRing.lineWidth = 3
        exitRing.glowWidth = 4
        exitRing.zPosition = 2
        exitRing.physicsBody = sensor(circle: ArrowMazeSimulation.exitRadius, category: ArrowMazePhysics.exit)
        ArrowMazeArt.decoratePortal(exitRing, reduceMotion: reduceMotion)
        addChild(exitRing)

        exhaust.particleTexture = ArrowMazeArt.softDot
        exhaust.particleBirthRate = reduceMotion ? 0 : 90
        exhaust.particleLifetime = 0.55
        exhaust.particleLifetimeRange = 0.2
        exhaust.particleSpeed = 50
        exhaust.particleSpeedRange = 20
        exhaust.emissionAngle = .pi
        exhaust.emissionAngleRange = 0.35
        exhaust.particleAlpha = 0.85
        exhaust.particleAlphaSpeed = -1.6
        exhaust.particleScale = 0.32
        exhaust.particleScaleRange = 0.1
        exhaust.particleScaleSpeed = 0.5
        exhaust.particleColorBlendFactor = 1
        exhaust.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor(red: 1, green: 0.93, blue: 0.55, alpha: 1), UIColor.systemOrange,
                        UIColor(red: 0.45, green: 0.42, blue: 0.6, alpha: 1)],
            times: [0, 0.25, 1])
        exhaust.particleBlendMode = .add
        exhaust.position = CGPoint(x: -20, y: 0)
        exhaust.targetNode = self
        exhaust.zPosition = 4
        exhaust.resetSimulation()
        rocket.addChild(exhaust)
        ArrowMazeArt.buildRocket(in: rocket, flame: flame, reduceMotion: reduceMotion)
        rocket.zPosition = 5
        addChild(rocket)

        // Independent world-space tip node avoids nested dynamic-body transforms.
        let body = SKPhysicsBody(circleOfRadius: ArrowMazeSimulation.tipRadius)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.categoryBitMask = ArrowMazePhysics.arrow
        body.collisionBitMask = 0 // Failure, not a physical bounce, is the response.
        body.contactTestBitMask = ArrowMazePhysics.wall | ArrowMazePhysics.gem | ArrowMazePhysics.exit
        body.usesPreciseCollisionDetection = true
        tipSensor.physicsBody = body
        addChild(tipSensor)
        renderPose()
        updateCamera(deltaTime: 0, snap: true)
    }

    override func update(_ currentTime: TimeInterval) {
        synchronizeLevel()
        guard let engine, engine.canAdvance, currentTime.isFinite else {
            // Still show the crash burst after the round ends.
            if engine?.simulation.outcome == .crashed { renderPose() }
            resetFrameClock(); return
        }
        engine.receiveContacts(wall: pendingWall, gems: pendingGems, exit: pendingExit)
        pendingWall = false
        pendingExit = false
        pendingGems.removeAll(keepingCapacity: true)
        guard let previousTime else { self.previousTime = currentTime; renderPose(); return }
        let elapsed = min(maximumFrameTime, max(0, currentTime - previousTime))
        self.previousTime = currentTime
        accumulator += elapsed
        var steps = 0
        while accumulator >= fixedStep && engine.canAdvance && steps < 8 {
            engine.advance(fixedStep)
            accumulator -= fixedStep
            steps += 1
        }
        renderPose()
        updateCamera(deltaTime: elapsed, snap: false)
        if !engine.canAdvance { resetFrameClock() }
    }

    private func renderPose() {
        guard let engine else { return }
        let simulation = engine.simulation
        rocket.position = simulation.position
        rocket.zRotation = simulation.heading.angle
        tipSensor.position = simulation.tip
        tipSensor.physicsBody?.velocity = .zero
        for index in simulation.collected {
            guard let node = gemNodes.removeValue(forKey: index) else { continue }
            node.physicsBody = nil
            node.removeAllActions()
            node.run(.sequence([.group([.scale(to: 2.2, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
            addChild(ArrowMazeArt.sparkBurst(at: node.position, color: .systemYellow))
        }
        // Brighter, longer flame as the ship speeds up.
        let boost = simulation.speedMultiplier
        if boost != shownBoost {
            shownBoost = boost
            flame.setScale(boost)
            if !reduceMotion { exhaust.particleBirthRate = 90 * boost; exhaust.particleSpeed = 50 * boost }
        }
        let unlocked = simulation.exitUnlocked
        let portalColor = unlocked ? UIColor.systemGreen : UIColor(white: 0.55, alpha: 1)
        if exitRing.strokeColor != portalColor {
            exitRing.strokeColor = portalColor
            exitRing.fillColor = portalColor.withAlphaComponent(unlocked ? 0.22 : 0.08)
            exitRing.children.forEach { ($0 as? SKShapeNode)?.strokeColor = portalColor }
            if unlocked && !reduceMotion {
                exitRing.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.5), .scale(to: 1, duration: 0.5)])))
            }
        }
        if simulation.outcome == .crashed && !exploded {
            exploded = true
            rocket.isHidden = true
            exhaust.particleBirthRate = 0
            addChild(ArrowMazeArt.sparkBurst(at: simulation.position, color: .systemOrange, count: 28))
        }
    }
    private func updateCamera(deltaTime: TimeInterval, snap: Bool) {
        guard let engine, size.width > 0, size.height > 0 else { return }
        let scale = max(1, 360 / size.width)
        trackingCamera.setScale(scale)
        let lead: CGFloat = reduceMotion ? 0 : 54
        let unit = engine.simulation.heading.unit
        let raw = CGPoint(x: engine.simulation.position.x + unit.dx * lead,
                          y: engine.simulation.position.y + unit.dy * lead)
        let bounds = engine.level.bounds
        func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat, half: CGFloat) -> CGFloat {
            if maximum - minimum <= half * 2 { return (minimum + maximum) / 2 }
            return min(maximum - half, max(minimum + half, value))
        }
        let target = CGPoint(x: clamp(raw.x, minimum: bounds.minX, maximum: bounds.maxX, half: size.width * scale / 2),
                             y: clamp(raw.y, minimum: bounds.minY, maximum: bounds.maxY, half: size.height * scale / 2))
        let alpha: CGFloat = snap || reduceMotion ? 1 : CGFloat(1 - exp(-8 * deltaTime))
        trackingCamera.position.x += (target.x - trackingCamera.position.x) * alpha
        trackingCamera.position.y += (target.y - trackingCamera.position.y) * alpha
    }

    private func addTwinklingStars(level: ArrowMazeLevel, seed: Int) {
        guard !reduceMotion else { return }
        var random = ArrowMazeArt.Random(seed: UInt64(seed + 11))
        let floors = Array(level.floors).sorted { ($0.row, $0.column) < ($1.row, $1.column) }
        for _ in 0..<min(40, floors.count) {
            let cell = floors[random.int(floors.count)]
            let rect = level.rect(of: cell)
            let star = SKShapeNode(circleOfRadius: 1.4)
            star.fillColor = .white
            star.strokeColor = .clear
            star.position = CGPoint(x: rect.minX + random.unit() * rect.width, y: rect.minY + random.unit() * rect.height)
            star.alpha = 0.2
            star.zPosition = -5
            let duration = 0.6 + random.unit() * 1.4
            star.run(.sequence([.wait(forDuration: random.unit() * 2),
                                .repeatForever(.sequence([.fadeAlpha(to: 0.95, duration: duration),
                                                          .fadeAlpha(to: 0.15, duration: duration)]))]))
            addChild(star)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first, let view, let engine else { return }
        if !engine.started { engine.start(); return }
        // Screen space, not world space: camera tracking never changes left/right.
        engine.turn(touch.location(in: view).x < view.bounds.midX ? .left : .right)
    }
    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA, b = contact.bodyB
        guard a.categoryBitMask == ArrowMazePhysics.arrow || b.categoryBitMask == ArrowMazePhysics.arrow else { return }
        let other = a.categoryBitMask == ArrowMazePhysics.arrow ? b : a
        switch other.categoryBitMask {
        case ArrowMazePhysics.wall: pendingWall = true
        case ArrowMazePhysics.exit: pendingExit = true
        case ArrowMazePhysics.gem:
            if let name = other.node?.name, name.hasPrefix("gem:"), let index = Int(name.dropFirst(4)) { pendingGems.insert(index) }
        default: break
        }
    }
    private func configureSensor(_ body: SKPhysicsBody, category: UInt32) -> SKPhysicsBody {
        body.isDynamic = false
        body.categoryBitMask = category
        body.collisionBitMask = 0
        body.contactTestBitMask = 0 // The arrow requests these pairs.
        return body
    }
    private func sensor(circle radius: CGFloat, category: UInt32) -> SKPhysicsBody {
        configureSensor(SKPhysicsBody(circleOfRadius: radius), category: category)
    }
    private func sensor(rectangle size: CGSize, category: UInt32) -> SKPhysicsBody {
        configureSensor(SKPhysicsBody(rectangleOf: size), category: category)
    }
}
