import SwiftUI
import Observation

enum ToyMode: String, CaseIterable {
    case basketShot, bottleFlip, paperToss, darts, miniGolf, pinballMini, plinko, ricochet, ropeCut, drawBridge
    var id: GameID { GameID(rawValue:rawValue)! }
    var title: String {
        switch self {
        case .basketShot:"Basket Shot"
        case .bottleFlip:"Bottle Flip"
        case .paperToss:"Paper Toss"
        case .darts:"Darts"
        case .miniGolf:"Golf"
        case .pinballMini:"Pinball Mini"
        case .plinko:"Plinko"
        case .ricochet:"Ricochet"
        case .ropeCut:"Rope Cut"
        case .drawBridge:"Draw Bridge"
        }
    }
    var hint: String {
        switch self {
        case .basketShot:"Pull back from the ball and release to throw in the opposite direction."
        case .bottleFlip:"Swipe up from the bottle. Land upright after a full flip."
        case .paperToss:"Pull back from the paper and release. Aim opposite your drag; watch the wind."
        case .darts:"Pull back from the dart and release. A longer pull throws farther in the opposite direction."
        case .miniGolf:"Pull back from the ball and release. Sink it with one shot."
        case .pinballMini:"Hold the left or right side to raise that flipper. Keep the ball alive."
        case .plinko:"Drag across the top and release. Aim for the highlighted bin."
        case .ricochet:"Swipe to shoot. Bounce off a wall before hitting the target."
        case .ropeCut:"Swipe across ropes to cut them. Swing the candy into the goal."
        case .drawBridge:"Draw a bridge between the platforms, then tap Roll."
        }
    }
}

@MainActor @Observable
final class ToyEngine: GameEngine {
    let mode: ToyMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    private(set) var ball = CGPoint(x:70,y:380)
    private(set) var velocity = CGVector.zero
    private(set) var target = CGPoint(x:245,y:190)
    private(set) var launched = false
    private(set) var angle: CGFloat = 0
    private(set) var trail: [CGPoint] = []
    private(set) var bridge: [CGPoint] = []
    private(set) var bridgePath = Path()
    private(set) var ropes = [true,true]
    private(set) var attempts = 0
    private(set) var successes = 0
    private(set) var lives = 3
    private(set) var timeLeft = 30.0
    private(set) var notice = ""
    private(set) var wind: CGFloat = 0
    private(set) var selectedBin = 3
    private(set) var leftHeld = false
    private(set) var rightHeld = false
    private(set) var leftLift: CGFloat = 0
    private(set) var rightLift: CGFloat = 0
    private var bridgeSegments: [(CGPoint, CGPoint)] = []
    var active = false
    let anchors = [CGPoint(x:75,y:60),CGPoint(x:245,y:60)]
    let bumpers = [CGPoint(x:90,y:130),CGPoint(x:220,y:170),CGPoint(x:160,y:250)]
    private var spin: CGFloat = 0
    private var flight = 0.0
    private var delay = 0.0
    private var cooldown = 0.0
    private var bounces = 0
    private var dartStart = CGPoint.zero
    private var dartEnd = CGPoint.zero
    private var trailClock = 0.0
    init(mode:ToyMode) { self.mode = mode; restart() }
    var pegs: [CGPoint] {
        (0..<7).flatMap { row in (0..<6).compactMap { col -> CGPoint? in
            let x = CGFloat(col)*50 + (row.isMultiple(of:2) ? 35 : 60)
            return x < 300 ? CGPoint(x:x,y:95+CGFloat(row)*38) : nil
        } }
    }
    func restart() {
        state = .playing; score = 0; started = false; attempts = 0; successes = 0; lives = 3; timeLeft = 30; delay = 0
        leftLift = 0; rightLift = 0; release(); prepare()
    }
    private func prepare() {
        ball = CGPoint(x:70,y:380); velocity = .zero; target = CGPoint(x:245,y:190)
        launched = false; angle = 0; spin = 0; flight = 0; trail = []; bridge = []; bridgePath = Path(); bridgeSegments = []; notice = ""; ropes = [true,true]; bounces = 0; cooldown = 0
        switch mode {
        case .basketShot: ball = CGPoint(x:80,y:310); target.x = CGFloat.random(in:205...260)
        case .bottleFlip: ball = CGPoint(x:130,y:370)
        case .paperToss: ball = CGPoint(x:160,y:320); target = CGPoint(x:CGFloat.random(in:90...250),y:185); wind = CGFloat.random(in:-22...22)
        case .darts: ball = CGPoint(x:160,y:320); target = CGPoint(x:160,y:160)
        case .miniGolf: ball = CGPoint(x:60,y:380); target = CGPoint(x:250,y:85)
        case .pinballMini: ball = CGPoint(x:275,y:370); velocity = CGVector(dx:-80,dy:-520); launched = true
        case .plinko: ball = CGPoint(x:160,y:35); selectedBin = Int.random(in:0..<6)
        case .ricochet: ball = CGPoint(x:60,y:390); target = CGPoint(x:250,y:110)
        case .ropeCut: ball = CGPoint(x:160,y:210); target = CGPoint(x:attempts.isMultiple(of:2) ? 250 : 70,y:400)
        case .drawBridge: ball = CGPoint(x:45,y:188); target = CGPoint(x:270,y:288)
        }
    }
    func start() { guard active, state == .playing else { return }; started = true }
    func release() { leftHeld = false; rightHeld = false }
    func holdFlipper(left: Bool, held: Bool) {
        let pressed = held && active && started && state == .playing
        if left { leftHeld = pressed } else { rightHeld = pressed }
    }
    func flipperTip(left: Bool) -> CGPoint {
        let lift = left ? leftLift : rightLift
        let angle = CGFloat(0.38) - lift * 0.85
        return CGPoint(x: (left ? 70 : 250) + (left ? 1 : -1) * 80 * cos(angle), y: 375 + 80 * sin(angle))
    }
    func touch(_ p:CGPoint) {
        guard active, started, state == .playing, delay == 0 else { return }
        if mode == .pinballMini { leftHeld = p.x < 160; rightHeld = !leftHeld }
        if mode == .plinko && !launched { ball.x = min(300,max(20,p.x)) }
        if mode == .drawBridge && !launched {
            let q = CGPoint(x:min(310,max(10,p.x)),y:min(410,max(160,p.y)))
            if bridge.count < 100, bridge.last.map({ hypot($0.x-q.x,$0.y-q.y) > 5 }) ?? true {
                if bridge.isEmpty { bridgePath.move(to:q) } else { bridgePath.addLine(to:q) }
                bridge.append(q)
            }
        }
    }
    func clearBridge() { guard state == .playing,!launched else { return }; bridge = []; bridgePath = Path(); bridgeSegments = []; notice = "" }
    func roll() {
        guard active, started, state == .playing,!launched,mode == .drawBridge,let first = bridge.first,let last = bridge.last else { return }
        let forward = hypot(first.x-80,first.y-195) < 35 && hypot(last.x-240,last.y-295) < 35
        let reverse = hypot(last.x-80,last.y-195) < 35 && hypot(first.x-240,first.y-295) < 35
        guard forward || reverse else { notice = "Connect both platform edges."; return }
        // Sample the drawn surface once. A single contact per step avoids snagging
        // on overlapping endpoint circles at every joint of the drawn polyline.
        bridgeSegments = Array(zip(bridge, bridge.dropFirst())).filter { hypot($0.1.x-$0.0.x,$0.1.y-$0.0.y) > 0.5 }
        launched = true; velocity = CGVector(dx:110,dy:0); notice = ""
    }
    func gesture(from:CGPoint,to:CGPoint) {
        release()
        guard active,started,state == .playing,delay == 0 else { return }
        if mode == .ropeCut {
            for i in anchors.indices where ropes[i] {
                if intersects(from,to,anchors[i],ball) || distance(to,anchors[i],ball) < 12 { ropes[i] = false; launched = true }
            }
            return
        }
        guard !launched,mode != .drawBridge,mode != .pinballMini else { return }
        if mode == .plinko { launched = true; ball.x = min(300,max(20,to.x)); return }
        guard hypot(from.x-ball.x,from.y-ball.y) < 65 else { return }
        let dx = to.x-from.x,dy = to.y-from.y
        guard hypot(dx,dy) > 18 else { return }
        launched = true; trail = []
        switch mode {
        case .bottleFlip:
            guard dy < -18 else { launched = false; return }
            let power = min(440,max(240,-dy*3))
            velocity = CGVector(dx:min(100,max(-100,dx*1.2)),dy:-power)
            // Flight time is 2*v/g; swipe strength controls the rotation independently.
            spin = 2.5 + (-dy)*0.045
        case .miniGolf: velocity = capped(CGVector(dx:-dx*3,dy:-dy*3),limit:530)
        case .darts:
            dartStart = ball; dartEnd = CGPoint(x:ball.x-dx*2.4,y:ball.y-dy*2.4)
        case .ricochet:
            let length = hypot(dx,dy); velocity = CGVector(dx:dx/length*260,dy:dy/length*260)
        case .basketShot, .paperToss: velocity = capped(CGVector(dx:-dx*4,dy:-dy*4),limit:580)
        default: break
        }
    }
    private func capped(_ v:CGVector,limit:CGFloat) -> CGVector {
        let scale = min(1,limit/max(1,hypot(v.dx,v.dy))); return CGVector(dx:v.dx*scale,dy:v.dy*scale)
    }
    private func finish(_ points:Int) {
        guard delay == 0 else { return }
        score += points; if points > 0 { successes += 1 }
        attempts += 1; notice = points > 0 ? "Nice shot!" : "Missed!"; delay = 1
        if points > 0 { Haptics.success() } else { Haptics.error() }
    }
    func advance(_ dt:Double) {
        guard active,started,state == .playing else { release(); return }
        let d = min(0.08,max(0,dt))
        if delay > 0 {
            delay = max(0,delay-d)
            if delay == 0 { if attempts >= 5 { state = .gameOver(won:successes > 0) } else { prepare() } }
            return
        }
        if mode == .pinballMini { timeLeft = max(0,timeLeft-d); if timeLeft == 0 { state = .gameOver(won:true); return } }
        guard launched || mode == .ropeCut else { return }
        var rest = d
        while rest > 0 && state == .playing && delay == 0 { let step = min(rest,1.0/120); update(step); rest -= step }
    }
    private func update(_ dt:Double) {
        let d = CGFloat(dt),previous = ball
        if launched { flight += dt }; cooldown = max(0,cooldown-dt)
        if mode == .darts {
            let t = CGFloat(min(1,flight/0.65)); ball = CGPoint(x:dartStart.x+(dartEnd.x-dartStart.x)*t,y:dartStart.y+(dartEnd.y-dartStart.y)*t)
            if t == 1 { let r = hypot(ball.x-target.x,ball.y-target.y); finish(r <= 75 ? (r < 12 ? 100 : r < 35 ? 60 : 30) : 0) }; return
        }
        if ![.miniGolf,.ricochet].contains(mode) { velocity.dy += (mode == .bottleFlip ? 500 : 400)*d }
        if mode == .paperToss { velocity.dx += wind*d }
        ball.x += velocity.dx*d; ball.y += velocity.dy*d
        angle += spin*d
        trailClock += dt
        if trailClock > 0.035 { trailClock = 0; trail.append(ball); if trail.count > 30 { trail.removeFirst() } }
        switch mode {
        case .basketShot,.paperToss:
            if velocity.dy > 0,previous.y <= target.y,ball.y >= target.y,abs(ball.x-target.x) < (mode == .basketShot ? 21 : 25) { finish(100); return }
            if mode == .basketShot {
                circleCollision(CGPoint(x:target.x-25,y:target.y),radius:4,restitution:0.6)
                circleCollision(CGPoint(x:target.x+25,y:target.y),radius:4,restitution:0.6)
                segmentCollision(CGPoint(x:target.x+30,y:target.y-55),CGPoint(x:target.x+30,y:target.y+8),radius:8,restitution:0.7)
            }
            if ball.y > 470 || ball.x < -30 || ball.x > 350 || flight > 5 { finish(0) }
        case .bottleFlip:
            if velocity.dy > 0 && ball.y >= 370 {
                ball.y = 370
                let difference = abs(atan2(sin(angle),cos(angle)))
                finish(difference < 0.28 && angle >= 2 * .pi - 0.28 && ball.x > 20 && ball.x < 300 ? 100 : 0)
            }
        case .miniGolf:
            walls(restitution:0.8)
            segmentCollision(CGPoint(x:100,y:240),CGPoint(x:225,y:240),radius:9,restitution:0.75)
            let speed = hypot(velocity.dx,velocity.dy),factor = max(0,1-75*d/max(1,speed)); velocity.dx *= factor; velocity.dy *= factor
            if hypot(ball.x-target.x,ball.y-target.y) < 13 && speed < 185 { ball = target; finish(100) }
            else if speed < 4 || flight > 10 { finish(0) }
        case .pinballMini:
            if ball.x < 12 { ball.x = 12; velocity.dx = abs(velocity.dx)*0.85 }
            if ball.x > 308 { ball.x = 308; velocity.dx = -abs(velocity.dx)*0.85 }
            if ball.y < 20 { ball.y = 20; velocity.dy = abs(velocity.dy)*0.85 }
            for bumper in bumpers {
                if circleCollision(bumper,radius:23,restitution:1.05) && cooldown == 0 { score += 10; cooldown = 0.1 }
            }
            segmentCollision(CGPoint(x:10,y:300),CGPoint(x:70,y:375),radius:9,restitution:0.6)
            segmentCollision(CGPoint(x:310,y:300),CGPoint(x:250,y:375),radius:9,restitution:0.6)
            for left in [true,false] {
                let oldTip = flipperTip(left: left)
                let held = left ? leftHeld : rightHeld
                let lift = left ? leftLift : rightLift
                let next = min(1,max(0,lift + (held ? 12 : -7)*d))
                if left { leftLift = next } else { rightLift = next }
                let a = CGPoint(x:left ? 70 : 250,y:375), b = flipperTip(left: left)
                let contact = closest(ball,a,b)
                let fraction = min(1,hypot(contact.x-a.x,contact.y-a.y)/80)
                let surface = CGVector(dx:(b.x-oldTip.x)/d*fraction,dy:(b.y-oldTip.y)/d*fraction)
                // Resolve in the moving flipper's frame: only a moving stroke
                // adds energy; holding a raised flipper does not repeatedly kick.
                velocity.dx -= surface.dx; velocity.dy -= surface.dy
                segmentCollision(a,b,radius:14,restitution:0.8)
                velocity.dx += surface.dx; velocity.dy += surface.dy
            }
            velocity = capped(velocity,limit:650)
            if ball.y > 475 {
                lives -= 1
                if lives == 0 { state = .gameOver(won:false) }
                else { ball = CGPoint(x:275,y:370); velocity = CGVector(dx:-80,dy:-520); trail = []; leftLift = 0; rightLift = 0; release() }
            }
        case .plinko:
            if ball.x < 9 { ball.x = 9; velocity.dx = abs(velocity.dx)*0.7 }
            if ball.x > 311 { ball.x = 311; velocity.dx = -abs(velocity.dx)*0.7 }
            for peg in pegs {
                if circleCollision(peg,radius:5,restitution:0.55),abs(velocity.dx) < 8 { velocity.dx += Bool.random() ? 22 : -22 }
            }
            if ball.y > 420 { finish(min(5,max(0,Int(ball.x/(320/6)))) == selectedBin ? 100 : 10) }
            else if flight > 12 { finish(0) }
        case .ricochet:
            walls(restitution:1)
            if hypot(ball.x-target.x,ball.y-target.y) < 19 { finish(bounces > 0 ? 100 : 0) }
            else if flight > 8 { finish(0) }
        case .ropeCut:
            for _ in 0..<4 {
                for i in anchors.indices where ropes[i] {
                    let dx = ball.x-anchors[i].x,dy = ball.y-anchors[i].y,length = max(1,hypot(dx,dy)),limit:CGFloat = hypot(85,150)
                    if length > limit {
                        let nx = dx/length,ny = dy/length
                        ball = CGPoint(x:anchors[i].x+nx*limit,y:anchors[i].y+ny*limit)
                        let out = velocity.dx*nx+velocity.dy*ny
                        if out > 0 { velocity.dx -= out*nx; velocity.dy -= out*ny }
                    }
                }
            }
            if ball.y > 390 && ball.y < 425 && abs(ball.x-target.x) < 28 { finish(100) }
            else if ball.y > 470 || ball.x < -30 || ball.x > 350 || flight > 12 { finish(0) }
        case .drawBridge:
            segmentCollision(CGPoint(x:0,y:200),CGPoint(x:90,y:200),radius:10,restitution:0)
            segmentCollision(CGPoint(x:230,y:300),CGPoint(x:320,y:300),radius:10,restitution:0)
            var nearest: (CGPoint, CGPoint)?
            var best: CGFloat = 11
            for (a,b) in bridgeSegments {
                guard ball.x >= min(a.x,b.x)-11, ball.x <= max(a.x,b.x)+11,
                      ball.y >= min(a.y,b.y)-11, ball.y <= max(a.y,b.y)+11 else { continue }
                let gap = distance(ball,a,b)
                if gap < best { best = gap; nearest = (a,b) }
            }
            if let (a,b) = nearest {
                segmentCollision(a,b,radius:11,restitution:0)
                // Preserve rolling momentum over small joints, without pushing
                // through a steep wall or pulling the ball across a broken bridge.
                let dx = abs(b.x-a.x), dy = abs(b.y-a.y)
                if dx > dy, velocity.dx > 0 { velocity.dx = max(80,velocity.dx) }
            }
            if hypot(ball.x-target.x,ball.y-target.y) < 23 { finish(100) }
            else if ball.y > 470 || ball.x > 340 || ball.x < -20 || flight > 10 { finish(0) }
        case .darts: break
        }
    }
    private func walls(restitution:CGFloat) {
        if ball.x < 10 { ball.x = 10; velocity.dx = abs(velocity.dx)*restitution; bounces += 1 }
        if ball.x > 310 { ball.x = 310; velocity.dx = -abs(velocity.dx)*restitution; bounces += 1 }
        if ball.y < 30 { ball.y = 30; velocity.dy = abs(velocity.dy)*restitution; bounces += 1 }
        if ball.y > 445 { ball.y = 445; velocity.dy = -abs(velocity.dy)*restitution; bounces += 1 }
    }
    @discardableResult private func circleCollision(_ p:CGPoint,radius:CGFloat,restitution:CGFloat) -> Bool {
        let dx = ball.x-p.x,dy = ball.y-p.y,length = max(0.001,hypot(dx,dy)),limit = radius+8
        guard length < limit else { return false }
        let nx = length <= 0.001 ? CGFloat(0) : dx/length,ny = length <= 0.001 ? CGFloat(-1) : dy/length,dot = velocity.dx*nx+velocity.dy*ny
        ball = CGPoint(x:p.x+nx*limit,y:p.y+ny*limit)
        if dot < 0 { velocity.dx -= (1+restitution)*dot*nx; velocity.dy -= (1+restitution)*dot*ny; return true }
        return false
    }
    @discardableResult private func segmentCollision(_ a:CGPoint,_ b:CGPoint,radius:CGFloat,restitution:CGFloat) -> Bool {
        let p = closest(ball,a,b),dx = ball.x-p.x,dy = ball.y-p.y,length = max(0.001,hypot(dx,dy))
        guard length < radius else { return false }
        let nx = length <= 0.001 ? CGFloat(0) : dx/length,ny = length <= 0.001 ? CGFloat(-1) : dy/length,dot = velocity.dx*nx+velocity.dy*ny
        ball = CGPoint(x:p.x+nx*radius,y:p.y+ny*radius)
        if dot < 0 { velocity.dx -= (1+restitution)*dot*nx; velocity.dy -= (1+restitution)*dot*ny; return true }
        return false
    }
    private func closest(_ p:CGPoint,_ a:CGPoint,_ b:CGPoint) -> CGPoint {
        let dx = b.x-a.x,dy = b.y-a.y,t = min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(0.001,dx*dx+dy*dy)))
        return CGPoint(x:a.x+t*dx,y:a.y+t*dy)
    }
    private func distance(_ p:CGPoint,_ a:CGPoint,_ b:CGPoint) -> CGFloat { let q = closest(p,a,b); return hypot(q.x-p.x,q.y-p.y) }
    private func intersects(_ a:CGPoint,_ b:CGPoint,_ c:CGPoint,_ d:CGPoint) -> Bool {
        func cross(_ p:CGPoint,_ q:CGPoint,_ r:CGPoint) -> CGFloat { (q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x) }
        guard max(a.x,b.x) >= min(c.x,d.x),max(c.x,d.x) >= min(a.x,b.x),max(a.y,b.y) >= min(c.y,d.y),max(c.y,d.y) >= min(a.y,b.y) else { return false }
        return cross(a,b,c)*cross(a,b,d) <= 0 && cross(c,d,a)*cross(c,d,b) <= 0
    }
}
