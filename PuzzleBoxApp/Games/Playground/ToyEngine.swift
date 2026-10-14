import SwiftUI
import Observation

enum ToyMode: String, CaseIterable {
    case basketShot, bottleFlip, miniGolf, plinko, ropeCut, drawBridge
    var id: GameID { GameID(rawValue:rawValue)! }
    var title: String {
        switch self {
        case .basketShot:"Basket Shot"
        case .bottleFlip:"Bottle Flip"
        case .miniGolf:"Golf"
        case .plinko:"Plinko"
        case .ropeCut:"Rope Cut"
        case .drawBridge:"Draw Bridge"
        }
    }
    var hint: String {
        switch self {
        case .basketShot:"Pull back from the ball and release to throw in the opposite direction."
        case .bottleFlip:"Swipe up from the bottle. Land upright after a full flip."
        case .miniGolf:"Pull back from the ball and release. Sink it in 3 shots or fewer."
        case .plinko:"Drag across the top and release. Aim for the highlighted bin."
        case .ropeCut:"Swipe across ropes to cut them. Swing the candy into the goal."
        case .drawBridge:"Draw a bridge between the platforms, then tap Roll."
        }
    }
    /// Plinko is mostly luck, so it gets a few more balls than the skill games get lives.
    var maxLives: Int { self == .plinko ? 5 : 3 }
}

struct ToySegment { var a: CGPoint; var b: CGPoint }

struct ToyFXParticle {
    var p: CGPoint
    var v: CGVector
    var age = 0.0
    var life: Double
    var color: Color
    var size: CGFloat
}

struct ToyFXPopup: Identifiable {
    let id: Int
    let text: String
    var p: CGPoint
    var age = 0.0
    let color: Color
    let big: Bool
}

/// Endless arcade run: every success raises the level (moving targets, wind,
/// obstacles, less ink), consecutive successes multiply points, and misses cost lives.
@MainActor @Observable
final class ToyEngine: GameEngine {
    private enum Outcome { case success, safe, miss }

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
    private(set) var anchors = [CGPoint(x:75,y:60),CGPoint(x:245,y:60)]
    private(set) var successes = 0
    private(set) var lives = 3
    private(set) var streak = 0
    private(set) var notice = ""
    private(set) var selectedBin = 3
    private(set) var particles: [ToyFXParticle] = []
    private(set) var popups: [ToyFXPopup] = []

    // Mode-specific layout, varied by level.
    private(set) var wind: CGFloat = 0
    private(set) var strokes = 0
    private(set) var obstacles: [ToySegment] = []
    private(set) var movingBar: ToySegment?
    private(set) var goldPegs: Set<Int> = []
    private(set) var stars: [CGPoint] = []
    private(set) var leftTop: CGFloat = 200
    private(set) var leftEdge: CGFloat = 90
    private(set) var rightTop: CGFloat = 300
    private(set) var rightEdge: CGFloat = 230
    private(set) var inkUsed: CGFloat = 0
    private(set) var inkMax: CGFloat = 420
    private(set) var padX: CGFloat = 200
    private(set) var padWidth: CGFloat = 56
    private(set) var targetHalfWidth: CGFloat = 30
    let pegs: [CGPoint]

    var active = false
    var reduceMotion = false

    private var bridgeSegments: [ToySegment] = []
    private var ropeLengths: [CGFloat] = []
    private var spin: CGFloat = 0
    private var flight = 0.0
    private var delay = 0.0
    private var trailClock = 0.0
    private var clock = 0.0
    private var movingBaseX: CGFloat = 0
    private var movingAmplitude: CGFloat = 0
    private var touchedRim = false
    private var cutLast: CGPoint?
    private var popupID = 0

    var level: Int { successes + 1 }
    /// Multiplier the next success would earn.
    var nextMultiplier: Int { multiplier(for:streak+1) }
    var maxLives: Int { mode.maxLives }
    var binValues: [Int] {
        (0..<6).map { i in i == selectedBin ? 100 + 25*(level-1) : abs(i-selectedBin) == 1 ? 30 : 10 }
    }
    var leftConnector: CGPoint { CGPoint(x:leftEdge-10,y:leftTop-5) }
    var rightConnector: CGPoint { CGPoint(x:rightEdge+10,y:rightTop-5) }

    init(mode:ToyMode) {
        self.mode = mode
        pegs = (0..<7).flatMap { row in (0..<6).compactMap { col -> CGPoint? in
            let x = CGFloat(col)*50 + (row.isMultiple(of:2) ? 35 : 60)
            return x < 300 ? CGPoint(x:x,y:95+CGFloat(row)*38) : nil
        } }
        restart()
    }
    private func multiplier(for streak:Int) -> Int { streak >= 5 ? 3 : streak >= 3 ? 2 : 1 }

    func restart() {
        state = .playing; score = 0; started = false; successes = 0; streak = 0; delay = 0
        lives = mode.maxLives; particles = []; popups = []; clock = 0
        prepare()
    }

    private func prepare() {
        ball = CGPoint(x:70,y:380); velocity = .zero; target = CGPoint(x:245,y:190)
        launched = false; angle = 0; spin = 0; flight = 0; trail = []; bridge = []; bridgePath = Path(); bridgeSegments = []
        notice = ""; strokes = 0; wind = 0; movingAmplitude = 0; movingBar = nil; touchedRim = false; cutLast = nil
        stars = []; inkUsed = 0
        let level = CGFloat(self.level)
        switch mode {
        case .basketShot:
            ball = CGPoint(x:80,y:310)
            let spread = min(1,(level-1)/5)
            target = CGPoint(x:CGFloat.random(in:(225-35*spread)...(250+12*spread)),
                             y:CGFloat.random(in:(190-40*spread)...(190+50*spread)))
            if self.level >= 3 { wind = CGFloat.random(in:20...min(90,20+level*8)) * (Bool.random() ? 1 : -1) }
            if self.level >= 5 { movingAmplitude = min(40,15+level*3) }
            movingBaseX = min(282-movingAmplitude,max(200,target.x)); target.x = movingBaseX
        case .bottleFlip:
            ball = CGPoint(x:130,y:370)
            padWidth = max(30,62-level*4)
            padX = CGFloat.random(in:40...280)
            while abs(padX-130) < 40 { padX = CGFloat.random(in:40...280) }
        case .miniGolf: layoutGolf()
        case .plinko:
            ball = CGPoint(x:160,y:35); selectedBin = Int.random(in:0..<6)
            goldPegs = Set(pegs.indices.shuffled().prefix(4))
        case .ropeCut: layoutRopes()
        case .drawBridge: layoutBridge()
        }
    }

    private func layoutGolf() {
        ball = CGPoint(x:CGFloat.random(in:60...260),y:405)
        target = CGPoint(x:CGFloat.random(in:45...275),y:CGFloat.random(in:70...140))
        let templates: [[ToySegment]] = [
            [ToySegment(a:CGPoint(x:100,y:240),b:CGPoint(x:225,y:240))],
            [ToySegment(a:CGPoint(x:10,y:280),b:CGPoint(x:170,y:280)),ToySegment(a:CGPoint(x:150,y:190),b:CGPoint(x:310,y:190))],
            [ToySegment(a:CGPoint(x:55,y:265),b:CGPoint(x:145,y:215)),ToySegment(a:CGPoint(x:175,y:215),b:CGPoint(x:265,y:265))],
            [ToySegment(a:CGPoint(x:130,y:200),b:CGPoint(x:190,y:200)),ToySegment(a:CGPoint(x:190,y:200),b:CGPoint(x:190,y:260)),
             ToySegment(a:CGPoint(x:190,y:260),b:CGPoint(x:130,y:260)),ToySegment(a:CGPoint(x:130,y:260),b:CGPoint(x:130,y:200))],
            [ToySegment(a:CGPoint(x:10,y:230),b:CGPoint(x:120,y:230)),ToySegment(a:CGPoint(x:200,y:230),b:CGPoint(x:310,y:230))],
        ]
        var layout = level == 1 ? templates[0] : templates[Int.random(in:0..<templates.count)]
        // Mirror half of the layouts so they feel less familiar.
        if level > 1, Bool.random() {
            layout = layout.map { ToySegment(a:CGPoint(x:320-$0.a.x,y:$0.a.y),b:CGPoint(x:320-$0.b.x,y:$0.b.y)) }
        }
        obstacles = layout
        if level >= 3 {
            movingBaseX = 160; movingAmplitude = 105
            movingBar = ToySegment(a:CGPoint(x:125,y:340),b:CGPoint(x:195,y:340))
        }
    }

    private func layoutRopes() {
        ball = CGPoint(x:160,y:210)
        if level >= 3 {
            anchors = [CGPoint(x:CGFloat.random(in:45...100),y:CGFloat.random(in:55...85)),
                       CGPoint(x:CGFloat.random(in:140...180),y:CGFloat.random(in:35...50)),
                       CGPoint(x:CGFloat.random(in:220...275),y:CGFloat.random(in:55...85))]
        } else {
            anchors = [CGPoint(x:CGFloat.random(in:55...95),y:CGFloat.random(in:50...80)),
                       CGPoint(x:CGFloat.random(in:225...265),y:CGFloat.random(in:50...80))]
        }
        ropes = anchors.map { _ in true }
        ropeLengths = anchors.map { hypot(ball.x-$0.x,ball.y-$0.y) }
        targetHalfWidth = max(20,30-CGFloat(level-1)*2)
        let side: Bool = Bool.random()
        movingBaseX = side ? CGFloat.random(in:210...270) : CGFloat.random(in:50...110)
        target = CGPoint(x:movingBaseX,y:400)
        if level >= 4 { movingAmplitude = min(45,15+CGFloat(level)*4); movingBaseX = min(320-movingAmplitude-30,max(movingAmplitude+30,movingBaseX)) }
        // Stars sit on the arc the candy follows when it swings from one rope.
        let swings = anchors.indices.filter { abs(atan2(ball.x-anchors[$0].x,ball.y-anchors[$0].y)) > 0.35 }
        stars = swings.shuffled().prefix(level >= 2 ? 2 : 1).map { i in
            let a = anchors[i],length = ropeLengths[i]
            let start = atan2(ball.x-a.x,ball.y-a.y)
            let theta = start*CGFloat.random(in:-0.8...0.4)
            return CGPoint(x:a.x+sin(theta)*length,y:a.y+cos(theta)*length)
        }
    }

    private func layoutBridge() {
        leftTop = CGFloat.random(in:170...235); leftEdge = CGFloat.random(in:75...105)
        rightTop = min(370,leftTop+CGFloat.random(in:40...min(140,50+CGFloat(level)*15)))
        rightEdge = CGFloat.random(in:max(leftEdge+100,195)...245)
        ball = CGPoint(x:leftEdge-45,y:leftTop-12)
        target = CGPoint(x:rightEdge+40,y:rightTop-12)
        let gap = hypot(rightConnector.x-leftConnector.x,rightConnector.y-leftConnector.y)
        inkMax = max(gap*1.45,480-CGFloat(level)*25)
        let mid = CGPoint(x:(leftConnector.x+rightConnector.x)/2,y:(leftConnector.y+rightConnector.y)/2)
        stars = [CGPoint(x:mid.x+CGFloat.random(in:-20...20),y:mid.y-CGFloat.random(in:18...min(55,20+CGFloat(level)*6)))]
    }

    func start() { guard active, state == .playing else { return }; started = true }

    func touch(_ p:CGPoint) {
        guard active, started, state == .playing, delay == 0 else { return }
        if mode == .ropeCut {
            if let last = cutLast { cut(last,p) }
            cutLast = p
            return
        }
        if mode == .plinko && !launched { ball.x = min(300,max(20,p.x)) }
        if mode == .drawBridge && !launched {
            let q = CGPoint(x:min(310,max(10,p.x)),y:min(430,max(100,p.y)))
            if let last = bridge.last {
                let step = hypot(last.x-q.x,last.y-q.y)
                guard step > 5, inkUsed+step <= inkMax else { return }
                inkUsed += step; bridgePath.addLine(to:q)
            } else { bridgePath.move(to:q) }
            bridge.append(q)
        }
    }
    func endTouch() { cutLast = nil }
    func clearBridge() { guard state == .playing,!launched else { return }; bridge = []; bridgePath = Path(); bridgeSegments = []; inkUsed = 0; notice = "" }
    func roll() {
        guard active, started, state == .playing,!launched,mode == .drawBridge,let first = bridge.first,let last = bridge.last else { return }
        let l = leftConnector,r = rightConnector
        let forward = hypot(first.x-l.x,first.y-l.y) < 35 && hypot(last.x-r.x,last.y-r.y) < 35
        let reverse = hypot(last.x-l.x,last.y-l.y) < 35 && hypot(first.x-r.x,first.y-r.y) < 35
        guard forward || reverse else { notice = "Connect both platform edges."; Haptics.error(); return }
        // Sample the drawn surface once. A single contact per step avoids snagging
        // on overlapping endpoint circles at every joint of the drawn polyline.
        bridgeSegments = zip(bridge,bridge.dropFirst()).filter { hypot($0.1.x-$0.0.x,$0.1.y-$0.0.y) > 0.5 }.map { ToySegment(a:$0.0,b:$0.1) }
        launched = true; velocity = CGVector(dx:110,dy:0); notice = ""; SoundFX.play(.tap)
    }
    private func cut(_ from:CGPoint,_ to:CGPoint) {
        for i in anchors.indices where ropes[i] {
            if intersects(from,to,anchors[i],ball) || distance(to,anchors[i],ball) < 12 {
                ropes[i] = false; launched = true; SoundFX.play(.whoosh); Haptics.tap()
                let mid = CGPoint(x:(anchors[i].x+ball.x)/2,y:(anchors[i].y+ball.y)/2)
                burst(at:mid,colors:[.orange,.yellow],count:6,speed:70)
            }
        }
    }
    func gesture(from:CGPoint,to:CGPoint) {
        guard active,started,state == .playing,delay == 0 else { return }
        if mode == .ropeCut { cut(cutLast ?? from,to); cutLast = nil; return }
        guard !launched,mode != .drawBridge else { return }
        if mode == .plinko { launched = true; ball.x = min(300,max(20,to.x)); SoundFX.play(.tap); return }
        guard hypot(from.x-ball.x,from.y-ball.y) < 65 else { return }
        let dx = to.x-from.x,dy = to.y-from.y
        guard hypot(dx,dy) > 18 else { return }
        launched = true; trail = []; flight = 0; SoundFX.play(.whoosh)
        switch mode {
        case .bottleFlip:
            guard dy < -18 else { launched = false; return }
            let power = min(440,max(240,-dy*3))
            velocity = CGVector(dx:min(100,max(-100,dx*1.2)),dy:-power)
            // Flight time is 2*v/g; swipe strength controls the rotation independently.
            spin = 2.5 + (-dy)*0.045
        case .miniGolf: velocity = capped(CGVector(dx:-dx*3,dy:-dy*3),limit:530); strokes += 1
        case .basketShot: velocity = capped(CGVector(dx:-dx*4,dy:-dy*4),limit:580)
        default: break
        }
    }
    private func capped(_ v:CGVector,limit:CGFloat) -> CGVector {
        let scale = min(1,limit/max(1,hypot(v.dx,v.dy))); return CGVector(dx:v.dx*scale,dy:v.dy*scale)
    }

    // MARK: - Results and effects

    private func finish(_ points:Int,_ outcome:Outcome,label:String? = nil) {
        guard delay == 0 else { return }
        switch outcome {
        case .success:
            streak += 1; successes += 1
            let m = multiplier(for:streak),total = points*m
            score += total
            popup(m > 1 ? "+\(total)  ×\(m)" : "+\(total)",at:ball,color:.yellow,big:true)
            if let label { popup(L10n.text(label),at:CGPoint(x:ball.x,y:ball.y-28),color:.white,big:false) }
            notice = label ?? "Nice shot!"
            burst(at:ball,colors:[.yellow,.orange,.pink,.cyan,.green],count:26,speed:180)
            Haptics.success(); SoundFX.play(.coin)
        case .safe:
            streak = 0; score += points
            popup("+\(points)",at:ball,color:.white,big:false); notice = ""
            Haptics.tap(); SoundFX.play(.point)
        case .miss:
            streak = 0; lives -= 1; score += points
            if points > 0 { popup("+\(points)",at:ball,color:.white.opacity(0.8),big:false) }
            notice = "Missed!"
            Haptics.error(); SoundFX.play(.wrong)
        }
        delay = 1.1
    }
    private func popup(_ text:String,at p:CGPoint,color:Color,big:Bool) {
        popupID += 1
        let q = CGPoint(x:min(280,max(40,p.x)),y:min(420,max(40,p.y-16)))
        popups.append(ToyFXPopup(id:popupID,text:text,p:q,color:color,big:big))
        if popups.count > 6 { popups.removeFirst() }
    }
    private func burst(at p:CGPoint,colors:[Color],count:Int,speed:CGFloat) {
        guard !reduceMotion else { return }
        for i in 0..<count {
            let heading = CGFloat.random(in:0...(2 * .pi)),v = speed*CGFloat.random(in:0.4...1)
            particles.append(ToyFXParticle(p:p,v:CGVector(dx:cos(heading)*v,dy:sin(heading)*v-speed*0.4),
                                           life:Double.random(in:0.5...0.9),color:colors[i % colors.count],size:CGFloat.random(in:2...4)))
        }
        if particles.count > 90 { particles.removeFirst(particles.count-90) }
    }
    private func updateFX(_ d:Double) {
        let step = CGFloat(d)
        if !particles.isEmpty {
            for i in particles.indices {
                particles[i].age += d
                particles[i].p.x += particles[i].v.dx*step; particles[i].p.y += particles[i].v.dy*step
                particles[i].v.dy += 380*step
            }
            particles.removeAll { $0.age >= $0.life }
        }
        if !popups.isEmpty {
            for i in popups.indices { popups[i].age += d; if !reduceMotion { popups[i].p.y -= 34*step } }
            popups.removeAll { $0.age >= 1.1 }
        }
    }

    // MARK: - Simulation

    func advance(_ dt:Double) {
        guard active,started,state == .playing else { return }
        let d = min(0.08,max(0,dt))
        updateFX(d)
        if delay > 0 {
            delay = max(0,delay-d)
            if delay == 0 { if lives <= 0 { state = .gameOver(won:successes >= 3) } else { prepare() } }
            return
        }
        animate(d)
        guard launched || mode == .ropeCut else { return }
        var rest = d
        while rest > 0 && state == .playing && delay == 0 { let step = min(rest,1.0/120); update(step); rest -= step }
    }
    /// Moving hoops, targets and bars keep moving even before the shot.
    private func animate(_ d:Double) {
        guard movingAmplitude > 0 else { return }
        clock += d
        switch mode {
        case .basketShot: target.x = movingBaseX + CGFloat(sin(clock*1.3))*movingAmplitude
        case .ropeCut: target.x = movingBaseX + CGFloat(sin(clock*1.1))*movingAmplitude
        case .miniGolf:
            let x = movingBaseX + CGFloat(sin(clock*1.2))*movingAmplitude
            movingBar = ToySegment(a:CGPoint(x:x-35,y:340),b:CGPoint(x:x+35,y:340))
        default: break
        }
    }
    private func update(_ dt:Double) {
        let d = CGFloat(dt),previous = ball
        if launched { flight += dt }

        if mode != .miniGolf { velocity.dy += (mode == .bottleFlip ? 500 : 400)*d }
        if mode == .basketShot { velocity.dx += wind*d }

        ball.x += velocity.dx*d; ball.y += velocity.dy*d
        angle += spin*d
        trailClock += dt
        if trailClock > 0.035 { trailClock = 0; trail.append(ball); if trail.count > 30 { trail.removeFirst() } }
        switch mode {
        case .basketShot:
            if velocity.dy > 0,previous.y <= target.y,ball.y >= target.y,abs(ball.x-target.x) < 21 {
                finish(touchedRim ? 100 : 150,.success,label:touchedRim ? nil : "Swish!"); return
            }
            var hit = circleCollision(CGPoint(x:target.x-25,y:target.y),radius:4,restitution:0.6)
            hit = circleCollision(CGPoint(x:target.x+25,y:target.y),radius:4,restitution:0.6) || hit
            hit = segmentCollision(CGPoint(x:target.x+30,y:target.y-55),CGPoint(x:target.x+30,y:target.y+8),radius:8,restitution:0.7) || hit
            if hit { touchedRim = true; SoundFX.play(.bounce) }
            if ball.y > 470 || ball.x < -30 || ball.x > 350 || flight > 5 { finish(0,.miss) }
        case .bottleFlip:
            if velocity.dy > 0 && ball.y >= 370 {
                ball.y = 370
                let difference = abs(atan2(sin(angle),cos(angle)))
                let upright = difference < 0.28 && angle >= 2 * .pi - 0.28 && ball.x > 20 && ball.x < 300
                if upright {
                    let double = angle >= 4 * .pi - 0.28
                    let onPad = abs(ball.x-padX) < padWidth/2
                    angle = 0
                    let label: String? = double && onPad ? "Perfect!" : double ? "Double flip!" : onPad ? "Bullseye!" : nil
                    finish(100 + (double ? 100 : 0) + (onPad ? 75 : 0),.success,label:label)
                } else {
                    // Tip the bottle over so the miss reads clearly.
                    angle = sin(angle) >= 0 ? .pi/2 : -.pi/2; ball.y = 389
                    burst(at:CGPoint(x:ball.x,y:398),colors:[.white.opacity(0.6)],count:8,speed:60)
                    finish(0,.miss)
                }
            }
        case .miniGolf:
            walls(restitution:0.8)
            var hit = false
            for s in obstacles { hit = segmentCollision(s.a,s.b,radius:9,restitution:0.75) || hit }
            if let bar = movingBar { hit = segmentCollision(bar.a,bar.b,radius:9,restitution:0.85) || hit }
            if hit { SoundFX.play(.bounce) }
            let speed = hypot(velocity.dx,velocity.dy),factor = max(0,1-75*d/max(1,speed)); velocity.dx *= factor; velocity.dy *= factor
            if hypot(ball.x-target.x,ball.y-target.y) < 13 && speed < 185 {
                ball = target
                finish([300,150,75][min(2,max(0,strokes-1))],.success,label:strokes == 1 ? "Hole in one!" : nil)
            } else if speed < 4 || flight > 10 {
                if strokes >= 3 { finish(0,.miss) }
                else { launched = false; velocity = .zero; flight = 0; trail = []; SoundFX.play(.tick) }
            }
        case .plinko:
            if ball.x < 9 { ball.x = 9; velocity.dx = abs(velocity.dx)*0.7 }
            if ball.x > 311 { ball.x = 311; velocity.dx = -abs(velocity.dx)*0.7 }
            for (index,peg) in pegs.enumerated() where abs(peg.y-ball.y) < 14 {
                if circleCollision(peg,radius:5,restitution:0.55) {
                    if goldPegs.remove(index) != nil {
                        score += 20; popup("+20",at:peg,color:.yellow,big:false); SoundFX.play(.coin)
                        burst(at:peg,colors:[.yellow,.orange],count:8,speed:90)
                    } else { SoundFX.play(.tick) }
                    if abs(velocity.dx) < 8 { velocity.dx += Bool.random() ? 22 : -22 }
                }
            }
            if ball.y > 420 {
                let bin = min(5,max(0,Int(ball.x/(320/6)))),value = binValues[bin]
                if bin == selectedBin { finish(value,.success,label:"Jackpot!") }
                else if abs(bin-selectedBin) == 1 { finish(value,.safe) }
                else { finish(value,.miss) }
            }
            else if flight > 12 { finish(0,.miss) }
        case .ropeCut:
            for _ in 0..<4 {
                for i in anchors.indices where ropes[i] {
                    let dx = ball.x-anchors[i].x,dy = ball.y-anchors[i].y,length = max(1,hypot(dx,dy)),limit = ropeLengths[i]
                    if length > limit {
                        let nx = dx/length,ny = dy/length
                        ball = CGPoint(x:anchors[i].x+nx*limit,y:anchors[i].y+ny*limit)
                        let out = velocity.dx*nx+velocity.dy*ny
                        if out > 0 { velocity.dx -= out*nx; velocity.dy -= out*ny }
                    }
                }
            }
            collectStars()
            if ball.y > 390 && ball.y < 425 && abs(ball.x-target.x) < targetHalfWidth-2 { finish(100,.success) }
            else if ball.y > 470 || ball.x < -30 || ball.x > 350 || flight > 12 { finish(0,.miss) }
        case .drawBridge:
            segmentCollision(CGPoint(x:0,y:leftTop),CGPoint(x:leftEdge,y:leftTop),radius:10,restitution:0)
            segmentCollision(CGPoint(x:rightEdge,y:rightTop),CGPoint(x:320,y:rightTop),radius:10,restitution:0)
            var nearest: ToySegment?
            var best: CGFloat = 11
            for s in bridgeSegments {
                let a = s.a,b = s.b
                guard ball.x >= min(a.x,b.x)-11, ball.x <= max(a.x,b.x)+11,
                      ball.y >= min(a.y,b.y)-11, ball.y <= max(a.y,b.y)+11 else { continue }
                let gap = distance(ball,a,b)
                if gap < best { best = gap; nearest = s }
            }
            if let s = nearest {
                segmentCollision(s.a,s.b,radius:11,restitution:0)
                // Preserve rolling momentum over small joints, without pushing
                // through a steep wall or pulling the ball across a broken bridge.
                let dx = abs(s.b.x-s.a.x), dy = abs(s.b.y-s.a.y)
                if dx > dy, velocity.dx > 0 { velocity.dx = max(80,velocity.dx) }
            }
            collectStars()
            if hypot(ball.x-target.x,ball.y-target.y) < 23 {
                let saved = Int((1-inkUsed/max(1,inkMax))*12)*5
                finish(100+saved,.success,label:saved >= 30 ? "Perfect!" : nil)
            }
            else if ball.y > 470 || ball.x > 340 || ball.x < -20 || flight > 10 { finish(0,.miss) }
        }
    }
    private func collectStars() {
        guard !stars.isEmpty else { return }
        if let i = stars.firstIndex(where:{ hypot($0.x-ball.x,$0.y-ball.y) < 20 }) {
            let star = stars.remove(at:i)
            score += 50; popup("★ +50",at:star,color:.yellow,big:false)
            burst(at:star,colors:[.yellow,.white],count:12,speed:120)
            SoundFX.play(.point); Haptics.tap()
        }
    }
    private func walls(restitution:CGFloat) {
        if ball.x < 10 { ball.x = 10; velocity.dx = abs(velocity.dx)*restitution }
        if ball.x > 310 { ball.x = 310; velocity.dx = -abs(velocity.dx)*restitution }
        if ball.y < 30 { ball.y = 30; velocity.dy = abs(velocity.dy)*restitution }
        if ball.y > 445 { ball.y = 445; velocity.dy = -abs(velocity.dy)*restitution }
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

// MARK: - Saved round

extension ToyEngine: ResumableGame {
    private struct Session: Codable {
        let score: Int
        let successes: Int
        let lives: Int
        let streak: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, successes > 0 || score > 0 else { return nil }
        return encodeSession(Session(score: score, successes: successes, lives: lives, streak: streak))
    }

    /// Resumes at the saved level with a fresh shot.
    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), s.lives > 0 else { return false }
        restart()
        score = s.score; successes = s.successes; lives = s.lives; streak = s.streak
        prepare()
        return true
    }
}
