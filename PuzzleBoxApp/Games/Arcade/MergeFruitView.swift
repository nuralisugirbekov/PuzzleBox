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
        UIColor(hue: CGFloat(stage) / 12, saturation: 0.42, brightness: 0.97, alpha: 1)
    }

    init(stage: Int, birth: Double, physics: Bool = true) {
        self.stage = stage; self.birth = birth
        super.init()
        let r = Self.radii[stage]
        path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        fillColor = Self.color(stage)
        strokeColor = .white.withAlphaComponent(0.5); lineWidth = 1.5
        // A darker lip under the ball, like the other toy pieces.
        let lip = SKShapeNode(circleOfRadius: r)
        lip.position = CGPoint(x: 0, y: -r * 0.1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        Self.color(stage).getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        lip.fillColor = UIColor(hue: h, saturation: min(1, sat + 0.12), brightness: b * 0.76, alpha: 1)
        lip.strokeColor = .clear
        lip.zPosition = -0.5
        addChild(lip)
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
    /// Set by the view; the crate's colours follow light and dark appearance.
    var dark = false { didSet { if dark != oldValue { applyTheme() } } }
    private var crate: SKShapeNode?
    private var planks: [SKShapeNode] = []
    private var walls: SKShapeNode?

    private func applyTheme() {
        backgroundColor = dark ? UIColor(red: 0.27, green: 0.22, blue: 0.18, alpha: 1)
                               : UIColor(red: 0.99, green: 0.94, blue: 0.86, alpha: 1)
        crate?.fillColor = dark ? UIColor(red: 0.33, green: 0.27, blue: 0.21, alpha: 1)
                                : UIColor(red: 0.98, green: 0.90, blue: 0.76, alpha: 1)
        for plank in planks {
            plank.fillColor = dark ? UIColor(red: 0.22, green: 0.17, blue: 0.13, alpha: 0.8)
                                   : UIColor(red: 0.86, green: 0.72, blue: 0.54, alpha: 0.6)
        }
        walls?.strokeColor = dark ? UIColor(red: 0.48, green: 0.36, blue: 0.25, alpha: 1)
                                  : UIColor(red: 0.80, green: 0.62, blue: 0.44, alpha: 1)
        guide.strokeColor = (dark ? UIColor.white : UIColor.black).withAlphaComponent(0.18)
    }
    static let heldY: CGFloat = 445
    var canDrop: Bool { clock >= nextDrop }

    func resetBoard() {
        removeAllChildren(); contacts = []; clock = 0; lastUpdate = nil; nextDrop = 0; overflowTime = 0
        lastMerge = -10; chain = 0; aimX = 160; held = nil
        scaleMode = .aspectFit
        planks = []
        physicsWorld.gravity = CGVector(dx: 0, dy: -6)
        physicsWorld.contactDelegate = self
        // A soft wooden crate behind the fruit.
        let crate = SKShapeNode(rect: CGRect(x: 5, y: 8, width: 310, height: 384), cornerRadius: 6)
        crate.strokeColor = .clear
        crate.zPosition = -3
        addChild(crate)
        self.crate = crate
        for y in stride(from: CGFloat(60), to: 390, by: 64) {
            let plank = SKShapeNode(rect: CGRect(x: 5, y: y, width: 310, height: 1.5))
            plank.strokeColor = .clear; plank.zPosition = -2
            addChild(plank)
            planks.append(plank)
        }
        let wallPath = CGMutablePath()
        wallPath.move(to: CGPoint(x: 5, y: 600))
        wallPath.addLine(to: CGPoint(x: 5, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 8))
        wallPath.addLine(to: CGPoint(x: 315, y: 600))
        physicsBody = SKPhysicsBody(edgeChainFrom: wallPath)
        physicsBody?.categoryBitMask = 2
        let walls = SKShapeNode(path: wallPath)
        walls.lineWidth = 6; walls.zPosition = 2
        addChild(walls)
        self.walls = walls
        limit.removeAllActions(); limit.alpha = 0.5
        limit.fillColor = UIColor(red: 0.95, green: 0.45, blue: 0.42, alpha: 1); limit.strokeColor = .clear
        addChild(limit)
        guide.lineWidth = 2
        addChild(guide)
        applyTheme()
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = ToyFruit.palette
        GameContainerView(gameID: .mergeFruit, engine: engine,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette) {
                comboChip
            } content: {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        ToyChip(color: palette.card) {
                            HStack(spacing: 6) {
                                Text(L10n.text("Next fruit"))
                                Text(verbatim: MergeFruitNode.symbols[engine.nextFruit]).font(.title3)
                            }
                        }
                        Spacer()
                        ToyChip(color: palette.card) {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill").foregroundStyle(palette.accent)
                                Text(verbatim: MergeFruitNode.symbols[engine.biggest]).font(.title3)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.text("Biggest fruit"))
                    }
                    .padding(.top, 14)
                    GeometryReader { geometry in
                        MergeFruitSurface(scene: engine.scene,
                                          paused: engine.state != .playing || scenePhase != .active)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                Color.clear.contentShape(Rectangle())
                                    .gesture(DragGesture(minimumDistance: 0)
                                        .onChanged { value in engine.aim(x: value.location.x / geometry.size.width * 320) }
                                        .onEnded { value in engine.drop(x: value.location.x / geometry.size.width * 320) })
                            }
                    }
                    .aspectRatio(2.0 / 3, contentMode: .fit)
                    // A wooden crate in the game's own clay.
                    .toyTray(palette.tray, cornerRadius: 24, padding: 8)
                    Text(L10n.text("Drag to aim and release to drop. Quick merges build a combo, and two watermelons make a melon party!"))
                        .font(.system(.footnote, design: .rounded))
                        .opacity(engine.score == 0 ? 0.6 : 0)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(engine.score != 0)
                        .animation(.easeOut(duration: 0.3), value: engine.score == 0)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            engine.active = scenePhase == .active
            engine.scene.dark = colorScheme == .dark
        }
        .onDisappear { engine.active = false; engine.scene.isPaused = true }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
        .onChange(of: colorScheme) { _, scheme in engine.scene.dark = scheme == .dark }
    }

    private var comboChip: some View {
        ToyChip(color: ToyFruit.palette.card) {
            Label { Text(verbatim: "×\(min(engine.chain, 5))") } icon: { Image(systemName: "flame.fill") }
                .foregroundStyle(ToyFruit.palette.accent)
        }
        .opacity(engine.chain > 1 ? 1 : 0)
        .scaleEffect(engine.chain > 1 ? 1 : 0.6)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: engine.chain > 1)
    }
}

/// Hosts the scene in its own SKView: SwiftUI's SpriteView never presented it here.
private struct MergeFruitSurface: UIViewRepresentable {
    let scene: MergeFruitScene
    let paused: Bool

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.ignoresSiblingOrder = false
        view.presentScene(scene)
        view.isPaused = paused
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        view.isPaused = paused
        scene.isPaused = paused
    }
    static func dismantleUIView(_ view: SKView, coordinator: ()) {
        view.isPaused = true
        view.presentScene(nil)
    }
}

/// The aqua orchard toy world of Merge Fruit: a wooden crate on a cool table.
enum ToyFruit {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.89, 0.97, 0.96), dark: (0.09, 0.17, 0.18)),
        backdropBottom: .dynamic(light: (0.74, 0.91, 0.89), dark: (0.05, 0.10, 0.11)),
        tray: .dynamic(light: (0.86, 0.69, 0.50), dark: (0.42, 0.32, 0.22)),
        socket: .dynamic(light: (0.80, 0.62, 0.44), dark: (0.32, 0.24, 0.16)),
        ink: .dynamic(light: (0.15, 0.37, 0.39), dark: (0.88, 0.98, 0.97)),
        deboss: .dynamic(light: (0.74, 0.90, 0.88), dark: (0.24, 0.40, 0.41)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.02, 0.06, 0.06)),
        card: .dynamic(light: (0.99, 1.0, 1.0), dark: (0.15, 0.25, 0.26)),
        accent: .dynamic(light: (0.95, 0.52, 0.45), dark: (1.0, 0.62, 0.55)))
}
