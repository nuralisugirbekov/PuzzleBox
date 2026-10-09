import SwiftUI
import Observation

struct BounceLevel {
    let width: CGFloat
    let spawn: CGPoint
    let platforms: [CGRect]
    let spikes: [CGRect]
    let rings: [CGPoint]
    let exit: CGRect

    // Original layouts. Maximum jump height is ~108 units; gaps stay below 100.
    static let levels: [BounceLevel] = [
        BounceLevel(width: 1080, spawn: CGPoint(x: 45, y: 348),
                    platforms: [CGRect(x: 0,y: 365,width: 380,height: 75), CGRect(x: 450,y: 365,width: 630,height: 75),
                                CGRect(x: 170,y: 295,width: 100,height: 16), CGRect(x: 560,y: 285,width: 110,height: 16), CGRect(x: 740,y: 235,width: 110,height: 16)],
                    spikes: [CGRect(x: 300,y: 347,width: 35,height: 18), CGRect(x: 870,y: 347,width: 40,height: 18)],
                    rings: [CGPoint(x: 100,y: 340),CGPoint(x: 215,y: 265),CGPoint(x: 415,y: 305),CGPoint(x: 610,y: 255),CGPoint(x: 790,y: 205),CGPoint(x: 960,y: 335)],
                    exit: CGRect(x: 1020,y: 310,width: 34,height: 55)),
        BounceLevel(width: 1230, spawn: CGPoint(x: 45,y: 348),
                    platforms: [CGRect(x: 0,y: 365,width: 290,height: 75),CGRect(x: 375,y: 365,width: 330,height: 75),CGRect(x: 790,y: 365,width: 440,height: 75),
                                CGRect(x: 150,y: 295,width: 95,height: 16),CGRect(x: 325,y: 240,width: 100,height: 16),CGRect(x: 500,y: 190,width: 105,height: 16),
                                CGRect(x: 690,y: 255,width: 100,height: 16),CGRect(x: 930,y: 290,width: 110,height: 16)],
                    spikes: [CGRect(x: 580,y: 347,width: 55,height: 18),CGRect(x: 1060,y: 347,width: 40,height: 18)],
                    rings: [CGPoint(x: 195,y: 265),CGPoint(x: 370,y: 210),CGPoint(x: 550,y: 160),CGPoint(x: 740,y: 225),CGPoint(x: 860,y: 335),CGPoint(x: 980,y: 260)],
                    exit: CGRect(x: 1170,y: 310,width: 34,height: 55)),
        BounceLevel(width: 1400, spawn: CGPoint(x: 45,y: 348),
                    platforms: [CGRect(x: 0,y: 365,width: 250,height: 75),CGRect(x: 330,y: 365,width: 360,height: 75),CGRect(x: 780,y: 365,width: 290,height: 75),CGRect(x: 1150,y: 365,width: 250,height: 75),
                                CGRect(x: 140,y: 295,width: 90,height: 16),CGRect(x: 310,y: 235,width: 110,height: 16),CGRect(x: 510,y: 175,width: 100,height: 16),
                                CGRect(x: 700,y: 245,width: 110,height: 16),CGRect(x: 930,y: 280,width: 100,height: 16),CGRect(x: 1100,y: 235,width: 100,height: 16)],
                    spikes: [CGRect(x: 430,y: 347,width: 40,height: 18),CGRect(x: 835,y: 347,width: 45,height: 18),CGRect(x: 1230,y: 347,width: 45,height: 18)],
                    rings: [CGPoint(x: 185,y: 265),CGPoint(x: 365,y: 205),CGPoint(x: 560,y: 145),CGPoint(x: 750,y: 215),CGPoint(x: 980,y: 250),CGPoint(x: 1150,y: 205),CGPoint(x: 1310,y: 335)],
                    exit: CGRect(x: 1340,y: 310,width: 34,height: 55))
    ] + (0..<9).map { index in
        // Four safe landing areas separated by jumpable gaps. Each upper ledge
        // is at most 80 units above the floor (jump height is ~108).
        let length = CGFloat(270 + (index % 3) * 25)
        let gap = CGFloat(60 + (index / 3) * 10)
        let width = length * 4 + gap * 3
        var platforms: [CGRect] = []
        var spikes: [CGRect] = []
        var rings: [CGPoint] = []
        for section in 0..<4 {
            let x = CGFloat(section) * (length + gap)
            let height = CGFloat(55 + ((index + section) % 3) * 12)
            platforms.append(CGRect(x:x,y:365,width:length,height:75))
            platforms.append(CGRect(x:x+85,y:365-height,width:90,height:16))
            rings.append(CGPoint(x:x+125,y:335-height))
            if section < 3 {
                rings.append(CGPoint(x:x+length+gap/2,y:305))
            }
            if section > 0 || index > 2 {
                spikes.append(CGRect(x:x+205,y:347,width:25+CGFloat(index%3)*5,height:18))
            }
        }
        return BounceLevel(width:width,spawn:CGPoint(x:45,y:348),platforms:platforms,
                           spikes:spikes,rings:rings,exit:CGRect(x:width-55,y:310,width:34,height:55))
    }
}

@MainActor @Observable
final class BounceEngine: GameEngine {
    var state: GameState = .playing {
        didSet { if state != .playing { releaseControls() } }
    }
    private(set) var score = 0
    private(set) var levelIndex = 0
    private(set) var lives = 3
    private(set) var ball = CGPoint.zero
    private(set) var rotation: CGFloat = 0
    private(set) var collected: Set<Int> = []
    private(set) var started = false
    private(set) var message = ""
    private(set) var transition = 0.0
    private(set) var invulnerable = 0.0
    var active = false { didSet { if !active { releaseControls() } } }
    private var velocity = CGVector.zero
    private var left = false
    private var right = false
    private var jumpHeld = false
    private var jumpBuffer = 0.0
    private var coyote = 0.0
    private var grounded = false
    private var changingLevel = false
    let radius: CGFloat = 12
    var level: BounceLevel { BounceLevel.levels[levelIndex] }
    var cameraX: CGFloat { max(0,min(level.width-360,ball.x-130)) }
    var gateOpen: Bool { collected.count == level.rings.count }
    init() { restart() }
    func restart() {
        state = .playing; score = 0; levelIndex = 0; lives = 3; started = false
        collected = []; transition = 0; changingLevel = false; message = ""; respawn()
    }
    func start() { guard active,state == .playing else { return }; started = true }
    func holdLeft(_ value: Bool) { left = value && canControl }
    func holdRight(_ value: Bool) { right = value && canControl }
    func holdJump(_ value: Bool) {
        if value && !jumpHeld && canControl { jumpBuffer = 0.13 }
        jumpHeld = value && canControl
    }
    private var canControl: Bool { active && started && state == .playing && transition == 0 }
    func releaseControls() { left = false; right = false; jumpHeld = false; jumpBuffer = 0 }
    private func respawn() {
        ball = level.spawn; velocity = .zero; rotation = 0; grounded = false; coyote = 0
        invulnerable = 0.8; releaseControls()
    }
    func advance(_ elapsed: Double) {
        guard active,started,state == .playing else { return }
        let dt = min(0.08,max(0,elapsed))
        if transition > 0 {
            transition = max(0,transition-dt)
            if transition == 0 {
                if changingLevel { levelIndex += 1; collected = []; changingLevel = false }
                message = ""; respawn()
            }
            return
        }
        var remaining = dt
        while remaining > 0 && transition == 0 && state == .playing {
            let step = min(remaining,1.0/180); update(step); remaining -= step
        }
    }
    private func update(_ dt: Double) {
        let d = CGFloat(dt)
        invulnerable = max(0,invulnerable-dt); jumpBuffer = max(0,jumpBuffer-dt)
        coyote = grounded ? 0.1 : max(0,coyote-dt)
        if jumpBuffer > 0 && coyote > 0 {
            velocity.dy = -405; grounded = false; coyote = 0; jumpBuffer = 0; Haptics.tap()
        }
        let direction: CGFloat = (right ? 1 : 0) - (left ? 1 : 0)
        let target = direction*180,acceleration: CGFloat = direction == 0 ? 1000 : 1300
        velocity.dx += min(acceleration*d,max(-acceleration*d,target-velocity.dx))
        velocity.dy = min(600,velocity.dy+760*d)
        let oldX = ball.x
        ball.x += velocity.dx*d
        // Resolve axes separately so floors, walls and platform undersides are solid.
        for p in level.platforms where ball.y+radius > p.minY+0.5 && ball.y-radius < p.maxY-0.5 {
            if velocity.dx > 0 && oldX+radius <= p.minX+0.5 && ball.x+radius > p.minX { ball.x = p.minX-radius; velocity.dx = 0 }
            if velocity.dx < 0 && oldX-radius >= p.maxX-0.5 && ball.x-radius < p.maxX { ball.x = p.maxX+radius; velocity.dx = 0 }
        }
        ball.x = min(level.width-radius,max(radius,ball.x)); rotation += (ball.x-oldX)/radius
        let oldY = ball.y
        ball.y += velocity.dy*d; grounded = false
        for p in level.platforms where ball.x+radius > p.minX+0.5 && ball.x-radius < p.maxX-0.5 {
            if velocity.dy >= 0 && oldY+radius <= p.minY+0.5 && ball.y+radius >= p.minY {
                ball.y = p.minY-radius; velocity.dy = 0; grounded = true
            } else if velocity.dy < 0 && oldY-radius >= p.maxY-0.5 && ball.y-radius < p.maxY {
                ball.y = p.maxY+radius; velocity.dy = 0
            }
        }
        for (i,ring) in level.rings.enumerated() where !collected.contains(i) {
            if hypot(ball.x-ring.x,ball.y-ring.y) < 24 { collected.insert(i); score += 50; Haptics.success() }
        }
        if ball.y > 460 || (invulnerable == 0 && level.spikes.contains(where: { touches($0) })) { die(); return }
        if gateOpen && level.exit.insetBy(dx:-radius,dy:0).contains(ball) {
            score += 250
            if levelIndex == BounceLevel.levels.count-1 { score += lives*100; state = .gameOver(won:true) }
            else { changingLevel = true; message = "Level complete!"; transition = 1; releaseControls() }
        }
    }
    private func touches(_ rect: CGRect) -> Bool {
        let x = min(rect.maxX,max(rect.minX,ball.x)),y = min(rect.maxY,max(rect.minY,ball.y))
        return hypot(ball.x-x,ball.y-y) < radius-2
    }
    private func die() {
        lives -= 1; Haptics.error(); releaseControls()
        if lives == 0 { state = .gameOver(won:false) }
        else { message = "Try again"; transition = 0.8; changingLevel = false }
        // Collected rings remain collected, so a respawn cannot farm points.
    }
}
