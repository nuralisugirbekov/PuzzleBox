import SwiftUI
import SpriteKit
import Observation

@MainActor
@Observable
final class MergeFruitEngine: GameEngine {
    private(set) var score = 0
    var state: GameState = .playing
    let scene = MergeFruitScene(size: CGSize(width: 320, height: 480))
    private(set) var nextFruit = Int.random(in: 0...2)
    var active = false

    init() { scene.owner = self; scene.resetBoard() }
    func restart() {
        score = 0; state = .playing; nextFruit = Int.random(in: 0...2)
        scene.resetBoard()
    }
    func drop(x: CGFloat) {
        guard active, state == .playing, scene.canDrop else { return }
        scene.drop(stage: nextFruit, x: x)
        nextFruit = Int.random(in: 0...2)
        Haptics.tap()
    }
    func merged(stage: Int) { score += (1 << stage) * 10; Haptics.move() }
    func overflow() { guard state == .playing else { return }; state = .gameOver(won: false) }
}

@MainActor
final class MergeFruitNode: SKShapeNode {
    let stage: Int
    let birth: Double
    static let symbols = ["🍒", "🍓", "🍇", "🍊", "🍎", "🍐", "🍑", "🍍", "🍉"]
    static let radii: [CGFloat] = [12, 16, 21, 27, 34, 42, 51, 61, 73]

    init(stage: Int, birth: Double) {
        self.stage = stage; self.birth = birth
        super.init()
        let r = Self.radii[stage]
        path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        fillColor = UIColor(hue: CGFloat(stage) / 12, saturation: 0.6, brightness: 0.85, alpha: 1)
        strokeColor = .white.withAlphaComponent(0.25); lineWidth = 1
        let label = SKLabelNode(text: Self.symbols[stage])
        label.fontSize = r * 1.5; label.verticalAlignmentMode = .center
        addChild(label)
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
    var canDrop: Bool { clock >= nextDrop }

    func resetBoard() {
        removeAllChildren(); contacts = []; clock = 0; lastUpdate = nil; nextDrop = 0; overflowTime = 0
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.086, green: 0.102, blue: 0.145, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.contactDelegate = self
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 5, y: 600))
        wallPath.addLine(to: CGPoint(x: 5, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 600))
        physicsBody = SKPhysicsBody(edgeChainFrom: wallPath)
        physicsBody?.categoryBitMask = 2
        let limit = SKShapeNode(rect: CGRect(x: 6, y: 390, width: 308, height: 2))
        limit.fillColor = .systemRed.withAlphaComponent(0.7); limit.strokeColor = .clear
        addChild(limit)
    }
    func drop(stage: Int, x: CGFloat) {
        let radius = MergeFruitNode.radii[stage]
        let fruit = MergeFruitNode(stage: stage, birth: clock)
        fruit.position = CGPoint(x: min(314 - radius, max(6 + radius, x)), y: 445)
        addChild(fruit); nextDrop = clock + 0.55
    }
    func didBegin(_ contact: SKPhysicsContact) {
        guard let a = contact.bodyA.node as? MergeFruitNode,
              let b = contact.bodyB.node as? MergeFruitNode,
              a.stage == b.stage, a.stage < MergeFruitNode.radii.count - 1 else { return }
        // Do not mutate the physics world inside the contact callback.
        contacts.append((a, b))
    }
    override func update(_ currentTime: TimeInterval) {
        let dt = min(0.05, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        guard owner?.active == true, owner?.state == .playing else { return }
        clock += dt
        let pending = contacts; contacts.removeAll()
        for (a, b) in pending where a.parent != nil && b.parent != nil {
            let position = CGPoint(x: (a.position.x + b.position.x) / 2, y: (a.position.y + b.position.y) / 2)
            let stage = a.stage + 1
            a.removeFromParent(); b.removeFromParent()
            let merged = MergeFruitNode(stage: stage, birth: clock)
            let radius = MergeFruitNode.radii[stage]
            merged.position = CGPoint(x: min(314 - radius, max(6 + radius, position.x)), y: max(9 + radius, position.y))
            addChild(merged); owner?.merged(stage: stage)
        }
        let tooHigh = children.compactMap { $0 as? MergeFruitNode }.contains {
            clock - $0.birth > 1.5 && $0.position.y + MergeFruitNode.radii[$0.stage] > 390
        }
        overflowTime = tooHigh ? overflowTime + dt : 0
        if overflowTime > 1.2 { owner?.overflow() }
    }
}

struct MergeFruitView: View {
    @State private var engine = MergeFruitEngine()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GameContainerView(gameID: .mergeFruit, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.text("Next fruit"))
                    Text(verbatim: MergeFruitNode.symbols[engine.nextFruit]).font(.title)
                }
                .foregroundStyle(GameTheme.accent)
                GeometryReader { geometry in
                    SpriteView(scene: engine.scene, isPaused: engine.state != .playing || scenePhase != .active)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay {
                            Color.clear.contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                                    engine.drop(x: value.location.x / geometry.size.width * 320)
                                })
                        }
                }
                .aspectRatio(2.0 / 3, contentMode: .fit).frame(maxWidth: 400, maxHeight: 480)
                Text(L10n.text("Tap to drop fruit. Match pairs and stay below the red line."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false; engine.scene.isPaused = true }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
    }
}
