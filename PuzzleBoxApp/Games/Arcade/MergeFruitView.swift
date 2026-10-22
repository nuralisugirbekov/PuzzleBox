import SwiftUI
import SpriteKit
import Observation

@MainActor
@Observable
final class MergeFruitEngine: GameEngine {
    private(set) var score = 0
    var state: GameState = .playing
    let scene = MergeFruitScene(size: CGSize(width: 320, height: 480))
    private(set) var currentFruit = Int.random(in: 0...2)
    private(set) var nextFruit = Int.random(in: 0...2)
    private(set) var chain = 0
    private(set) var biggest = 0
    var active = false

    init() { scene.owner = self; scene.resetBoard() }
    func restart() {
        score = 0; state = .playing; chain = 0; biggest = 0
        currentFruit = Int.random(in: 0...2); nextFruit = Int.random(in: 0...2)
        scene.resetBoard()
    }
    /// Moves the held fruit while the finger is down.
    func aim(x: CGFloat) {
        guard active, state == .playing else { return }
        scene.aim(x: x)
    }
    func drop(x: CGFloat) {
        guard active, state == .playing, scene.canDrop else { return }
        scene.drop(stage: currentFruit, x: x)
        currentFruit = nextFruit
        // Bigger starting fruit appear once the board has grown up a little.
        nextFruit = Int.random(in: 0...(biggest >= 5 ? 3 : 2))
        scene.showHeld(stage: currentFruit)
        Haptics.tap(); SoundFX.play(.pop)
    }
    /// Returns the points awarded so the scene can show them.
    func merged(stage: Int, chain: Int) -> Int {
        self.chain = chain
        biggest = max(biggest, stage)
        let points = (1 << stage) * 10 * min(chain, 5)
        score += points
        Haptics.move(); SoundFX.play(chain > 1 ? .coin : .merge)
        return points
    }
    func melonParty() -> Int {
        score += 1000
        Haptics.success(); SoundFX.play(.win)
        return 1000
    }
    func overflow() { guard state == .playing else { return }; state = .gameOver(won: false) }
}

@MainActor
final class MergeFruitNode: SKShapeNode {
    let stage: Int
    let birth: Double
    static let symbols = ["🍒", "🍓", "🍇", "🍊", "🍎", "🍐", "🍑", "🍍", "🍉"]
    static let radii: [CGFloat] = [12, 16, 21, 27, 34, 42, 51, 61, 73]
    static var maxStage: Int { radii.count - 1 }

    static func color(_ stage: Int) -> UIColor {
        UIColor(hue: CGFloat(stage) / 12, saturation: 0.55, brightness: 0.9, alpha: 1)
    }

    init(stage: Int, birth: Double, physics: Bool = true) {
        self.stage = stage; self.birth = birth
        super.init()
        let r = Self.radii[stage]
        path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        fillColor = Self.color(stage)
        strokeColor = .white.withAlphaComponent(0.35); lineWidth = 1.5
        let shine = SKShapeNode(ellipseOf: CGSize(width: r * 0.7, height: r * 0.45))
        shine.position = CGPoint(x: -r * 0.3, y: r * 0.45)
        shine.fillColor = .white.withAlphaComponent(0.3); shine.strokeColor = .clear
        addChild(shine)
        let label = SKLabelNode(text: Self.symbols[stage])
        label.fontSize = r * 1.4; label.verticalAlignmentMode = .center
        addChild(label)
        guard physics else { return }
        physicsBody = SKPhysicsBody(circleOfRadius: r)
        physicsBody?.restitution = 0.12
        physicsBody?.friction = 0.55
        physicsBody?.linearDamping = 0.3
        physicsBody?.categoryBitMask = 1
        physicsBody?.contactTestBitMask = 1
        physicsBody?.collisionBitMask = 3
        physicsBody?.usesPreciseCollisionDetection = true
    }
    required init?(coder aDecoder: NSCoder) { fatalError("Not used") }
}

@MainActor
final class MergeFruitScene: SKScene, @preconcurrency SKPhysicsContactDelegate {
    weak var owner: MergeFruitEngine?
    private var contacts: [(MergeFruitNode, MergeFruitNode)] = []
    private var clock = 0.0
    private var lastUpdate: TimeInterval?
    private var nextDrop = 0.0
    private var overflowTime = 0.0
    private var lastMerge = -10.0
    private var chain = 0
    private var aimX: CGFloat = 160
    private var held: MergeFruitNode?
    private let guide = SKShapeNode()
    private let limit = SKShapeNode(rect: CGRect(x: 6, y: 389, width: 308, height: 3))
    static let heldY: CGFloat = 445
    var canDrop: Bool { clock >= nextDrop }

    func resetBoard() {
        removeAllChildren(); contacts = []; clock = 0; lastUpdate = nil; nextDrop = 0; overflowTime = 0
        lastMerge = -10; chain = 0; aimX = 160; held = nil
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.98, green: 0.93, blue: 0.84, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.contactDelegate = self
        // A soft wooden crate behind the fruit.
        let crate = SKShapeNode(rect: CGRect(x: 5, y: 8, width: 310, height: 384), cornerRadius: 6)
        crate.fillColor = UIColor(red: 0.95, green: 0.84, blue: 0.66, alpha: 1); crate.strokeColor = .clear
        crate.zPosition = -3
        addChild(crate)
        for y in stride(from: CGFloat(60), to: 390, by: 64) {
            let plank = SKShapeNode(rect: CGRect(x: 5, y: y, width: 310, height: 1.5))
            plank.fillColor = UIColor(red: 0.8, green: 0.64, blue: 0.45, alpha: 0.6); plank.strokeColor = .clear; plank.zPosition = -2
            addChild(plank)
        }
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 5, y: 600))
        wallPath.addLine(to: CGPoint(x: 5, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 600))
        physicsBody = SKPhysicsBody(edgeChainFrom: wallPath)
        physicsBody?.categoryBitMask = 2
        let walls = SKShapeNode(path: wallPath)
        walls.strokeColor = UIColor(red: 0.6, green: 0.42, blue: 0.25, alpha: 1); walls.lineWidth = 6; walls.zPosition = 2
        addChild(walls)
        limit.removeAllActions(); limit.alpha = 0.5
        limit.fillColor = .systemRed; limit.strokeColor = .clear
        addChild(limit)
        guide.strokeColor = UIColor.black.withAlphaComponent(0.18); guide.lineWidth = 2
        addChild(guide)
        if let stage = owner?.currentFruit { showHeld(stage: stage) }
    }

    /// The fruit waiting at the top, following the player's finger.
    func showHeld(stage: Int) {
        held?.removeFromParent()
        let node = MergeFruitNode(stage: stage, birth: 0, physics: false)
        node.alpha = canDrop ? 1 : 0.4
        node.zPosition = 3
        addChild(node)
        held = node
        aim(x: aimX)
    }

    func aim(x: CGFloat) {
        guard let held else { return }
        let radius = MergeFruitNode.radii[held.stage]
        aimX = min(314 - radius, max(6 + radius, x))
        held.position = CGPoint(x: aimX, y: Self.heldY)
        let path = CGMutablePath()
        for y in stride(from: Self.heldY - radius - 6, to: 12, by: -14) {
            path.move(to: CGPoint(x: aimX, y: y)); path.addLine(to: CGPoint(x: aimX, y: y - 7))
        }
        guide.path = path
    }

    func drop(stage: Int, x: CGFloat) {
        let radius = MergeFruitNode.radii[stage]
        let fruit = MergeFruitNode(stage: stage, birth: clock)
        fruit.position = CGPoint(x: min(314 - radius, max(6 + radius, x)), y: Self.heldY)
        addChild(fruit); nextDrop = clock + 0.55
        aimX = fruit.position.x
    }

    func didBegin(_ contact: SKPhysicsContact) {
        guard let a = contact.bodyA.node as? MergeFruitNode,
              let b = contact.bodyB.node as? MergeFruitNode,
              a.stage == b.stage else { return }
        // Do not mutate the physics world inside the contact callback.
        contacts.append((a, b))
    }

    private func popup(_ text: String, at p: CGPoint, color: UIColor, size: CGFloat = 20) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Heavy"; label.fontSize = size; label.fontColor = color
        label.position = p; label.zPosition = 10
        addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 0.8), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]), .removeFromParent()]))
    }

    private func burst(at p: CGPoint, color: UIColor, count: Int, radius: CGFloat) {
        for i in 0..<count {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...4))
            dot.fillColor = color; dot.strokeColor = .clear; dot.position = p; dot.zPosition = 9
            addChild(dot)
            let angle = CGFloat(i) / CGFloat(count) * .pi * 2 + CGFloat.random(in: -0.2...0.2)
            let distance = radius * CGFloat.random(in: 0.8...1.6)
            dot.run(.sequence([.group([.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.45),
                                       .fadeOut(withDuration: 0.45), .scale(to: 0.3, duration: 0.45)]), .removeFromParent()]))
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = min(0.05, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        guard let owner, owner.active, owner.state == .playing else { return }
        clock += dt
        held?.alpha = canDrop ? 1 : 0.4
        let pending = contacts; contacts.removeAll()
        for (a, b) in pending where a.parent != nil && b.parent != nil {
            let position = CGPoint(x: (a.position.x + b.position.x) / 2, y: (a.position.y + b.position.y) / 2)
            a.removeFromParent(); b.removeFromParent()
            if a.stage == MergeFruitNode.maxStage {
                // Two watermelons pop together for a big bonus.
                let points = owner.melonParty()
                burst(at: position, color: .systemGreen, count: 30, radius: 110)
                popup(L10n.text("Melon party!") + " +\(points)", at: position, color: .systemGreen, size: 24)
                continue
            }
            chain = clock - lastMerge < 0.9 ? chain + 1 : 1
            lastMerge = clock
            let stage = a.stage + 1
            let merged = MergeFruitNode(stage: stage, birth: clock)
            let radius = MergeFruitNode.radii[stage]
            merged.position = CGPoint(x: min(314 - radius, max(9 + radius, position.x)), y: max(9 + radius, position.y))
            merged.setScale(0.6)
            merged.run(.sequence([.scale(to: 1.12, duration: 0.1), .scale(to: 1, duration: 0.08)]))
            addChild(merged)
            let points = owner.merged(stage: stage, chain: chain)
            burst(at: merged.position, color: MergeFruitNode.color(stage), count: 10 + stage * 2, radius: radius + 20)
            popup(chain > 1 ? "+\(points) ×\(min(chain, 5))" : "+\(points)", at: CGPoint(x: merged.position.x, y: merged.position.y + radius),
                  color: chain > 1 ? .systemOrange : .white, size: chain > 1 ? 22 : 18)
        }
        let tooHigh = children.compactMap { $0 as? MergeFruitNode }.contains {
            $0.physicsBody != nil && clock - $0.birth > 1.5 && $0.position.y + MergeFruitNode.radii[$0.stage] > 390
        }
        overflowTime = tooHigh ? overflowTime + dt : 0
        // The red line flashes while the stack is over it.
        limit.alpha = tooHigh ? 0.5 + 0.5 * abs(sin(clock * 12)) : 0.5
        if overflowTime > 1.6 { owner.overflow() }
    }
}

struct MergeFruitView: View {
    @State private var engine = MergeFruitEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GameContainerView(gameID: .mergeFruit, engine: engine) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.text("Next fruit"))
                    Text(verbatim: MergeFruitNode.symbols[engine.nextFruit]).font(.title)
                    Spacer()
                    if engine.chain > 1 {
                        Label { Text(verbatim: "×\(min(engine.chain, 5))") } icon: { Image(systemName: "flame.fill") }
                            .foregroundStyle(.orange)
                    }
                    Text(verbatim: MergeFruitNode.symbols[engine.biggest]).font(.title2)
                        .accessibilityLabel(L10n.text("Biggest fruit"))
                }
                .font(.headline)
                .foregroundStyle(GameTheme.accent)
                GeometryReader { geometry in
                    SpriteView(scene: engine.scene, isPaused: engine.state != .playing || scenePhase != .active)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { value in engine.aim(x: value.location.x / geometry.size.width * 320) }
                                    .onEnded { value in engine.drop(x: value.location.x / geometry.size.width * 320) })
                        }
                }
                .aspectRatio(2.0 / 3, contentMode: .fit)
                Text(L10n.text("Drag to aim and release to drop. Quick merges build a combo, and two watermelons make a melon party!"))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false; engine.scene.isPaused = true }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
    }
}
