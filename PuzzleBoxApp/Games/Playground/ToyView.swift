import SwiftUI

struct ToyView: View {
    @State private var engine:ToyEngine
    @State private var finger:CGPoint?
    @Environment(\.scenePhase) private var scenePhase
    init(mode:ToyMode) { _engine = State(initialValue:ToyEngine(mode:mode)) }
    var body: some View {
        GameContainerView(gameID:engine.mode.id,engine:engine,centersContent:true) {
            VStack(spacing:12) {
                HStack {
                    if engine.mode == .pinballMini {
                        Label(String(format:"0:%02d",Int(ceil(engine.timeLeft))),systemImage:"timer")
                        Spacer(); Text(L10n.format("Lives: %d",engine.lives))
                    } else { Text(L10n.format("Round %d of %d",min(5,engine.attempts+1),5)); Spacer() }
                    if engine.mode == .paperToss { Text((engine.wind < 0 ? "← " : "→ ")+String(Int(abs(engine.wind)))) }
                }.font(.headline.monospacedDigit()).foregroundStyle(Theme.neon)
                GeometryReader { geometry in
                    Canvas { context,size in
                        context.scaleBy(x:size.width/320,y:size.height/460); draw(&context)
                    }.background(Theme.surface,in:RoundedRectangle(cornerRadius:18)).clipShape(RoundedRectangle(cornerRadius:18))
                        .overlay {
                            if !engine.started {
                                Text(L10n.text("Tap to start")).font(.title2.bold()).padding(24)
                                    .background(Theme.background.opacity(0.9),in:RoundedRectangle(cornerRadius:16)).foregroundStyle(Theme.neon).allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { v in let p = normalized(v.location,geometry.size); finger = p; engine.touch(p) }
                            .onEnded { v in
                                if !engine.started { engine.start() }
                                else { engine.gesture(from:normalized(v.startLocation,geometry.size),to:normalized(v.location,geometry.size)) }
                                finger = nil
                            })
                }.aspectRatio(320.0/460,contentMode:.fit).frame(maxWidth:380,maxHeight:460)
                if engine.mode == .drawBridge {
                    HStack {
                        Button(L10n.text("Clear")) { engine.clearBridge() }
                        Button(L10n.text("Roll")) { engine.roll() }
                    }.buttonStyle(.bordered).disabled(!engine.started || engine.launched)
                }
                if !engine.notice.isEmpty { Text(L10n.text(engine.notice)).font(.subheadline).foregroundStyle(Theme.neon) }
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .onAppear { engine.active = scenePhase == .active }.onDisappear { engine.active = false; engine.release() }
        .onChange(of:scenePhase) { _,p in engine.active = p == .active; engine.release(); finger = nil }
        .onChange(of:engine.state) { _,_ in engine.release(); finger = nil }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for:.milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime; engine.advance(now-last); last = now
            }
        }
    }
    private func normalized(_ p:CGPoint,_ size:CGSize) -> CGPoint { CGPoint(x:p.x/size.width*320,y:p.y/size.height*460) }
    private func draw(_ context:inout GraphicsContext) {
        func circle(_ p:CGPoint,_ r:CGFloat,_ color:Color) { context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.color(color)) }
        func line(_ a:CGPoint,_ b:CGPoint,_ color:Color,_ width:CGFloat = 3) {
            var path = Path(); path.move(to:a); path.addLine(to:b); context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
        }
        func box(_ r:CGRect,_ color:Color) { context.fill(Path(roundedRect:r,cornerRadius:4),with:.color(color)) }
        switch engine.mode {
        case .basketShot:
            let p = engine.target
            line(CGPoint(x:p.x+30,y:p.y-55),CGPoint(x:p.x+30,y:p.y+8),.white,5)
            line(CGPoint(x:p.x-25,y:p.y),CGPoint(x:p.x+25,y:p.y),.orange,4)
            line(CGPoint(x:p.x-25,y:p.y),CGPoint(x:p.x-14,y:p.y+35),.white.opacity(0.5),2)
            line(CGPoint(x:p.x+25,y:p.y),CGPoint(x:p.x+14,y:p.y+35),.white.opacity(0.5),2)
            line(CGPoint(x:p.x-14,y:p.y+35),CGPoint(x:p.x+14,y:p.y+35),.white.opacity(0.5),2)
        case .bottleFlip: box(CGRect(x:0,y:400,width:320,height:60),Theme.surfaceHigh)
        case .paperToss:
            let p = engine.target
            box(CGRect(x:p.x-25,y:p.y,width:50,height:58),.gray)
            context.stroke(Path(ellipseIn:CGRect(x:p.x-25,y:p.y-7,width:50,height:14)),with:.color(Theme.neon),lineWidth:3)
            for i in -2...2 { line(CGPoint(x:p.x+CGFloat(i)*9,y:p.y+5),CGPoint(x:p.x+CGFloat(i)*7,y:p.y+52),Theme.surface,2) }
        case .darts:
            for (r,c) in [(CGFloat(75),Color.white),(CGFloat(58),Color.red),(CGFloat(40),Color.white),(CGFloat(25),Color.red),(CGFloat(12),Theme.neon)] { circle(engine.target,r,c) }
        case .miniGolf:
            box(CGRect(x:10,y:30,width:300,height:415),.green.opacity(0.12))
            line(CGPoint(x:100,y:240),CGPoint(x:225,y:240),.orange,8)
            circle(engine.target,13,.black)
            line(engine.target,CGPoint(x:engine.target.x,y:engine.target.y-35),.white,2)
            var flag = Path(); flag.move(to:CGPoint(x:engine.target.x,y:engine.target.y-35)); flag.addLine(to:CGPoint(x:engine.target.x+22,y:engine.target.y-25)); flag.addLine(to:CGPoint(x:engine.target.x,y:engine.target.y-18)); context.fill(flag,with:.color(.pink))
        case .pinballMini:
            for p in engine.bumpers { circle(p,23,.pink); circle(p,14,.orange) }
            line(CGPoint(x:10,y:300),CGPoint(x:70,y:375),.cyan,5); line(CGPoint(x:310,y:300),CGPoint(x:250,y:375),.cyan,5)
            line(CGPoint(x:70,y:375),CGPoint(x:145,y:engine.leftHeld ? 350 : 405),Theme.neon,12)
            line(CGPoint(x:250,y:375),CGPoint(x:175,y:engine.rightHeld ? 350 : 405),Theme.neon,12)
        case .plinko:
            for p in engine.pegs { circle(p,5,.cyan) }
            for i in 0..<6 {
                let x = CGFloat(i)*320/6
                box(CGRect(x:x+2,y:411,width:320/6-4,height:40),i == engine.selectedBin ? Theme.neon : Theme.surfaceHigh)
                context.draw(Text(i == engine.selectedBin ? "100" : "10").font(.caption.bold()).foregroundStyle(i == engine.selectedBin ? .black : .white),at:CGPoint(x:x+320/12,y:435))
            }
        case .ricochet:
            context.stroke(Path(CGRect(x:3,y:23,width:314,height:429)),with:.color(.cyan),lineWidth:3)
            circle(engine.target,19,.pink); circle(engine.target,9,Theme.surface)
        case .ropeCut:
            for i in engine.anchors.indices where engine.ropes[i] { line(engine.anchors[i],engine.ball,.orange,3); circle(engine.anchors[i],6,.white) }
            box(CGRect(x:engine.target.x-30,y:400,width:60,height:20),Theme.neon)
        case .drawBridge:
            box(CGRect(x:0,y:200,width:90,height:260),Theme.surfaceHigh); box(CGRect(x:230,y:300,width:90,height:160),Theme.surfaceHigh)
            circle(CGPoint(x:80,y:195),7,.cyan); circle(CGPoint(x:240,y:295),7,.cyan)
            for (a,b) in zip(engine.bridge,engine.bridge.dropFirst()) { line(a,b,.cyan,5) }
            circle(engine.target,20,Theme.neon.opacity(0.35))
        }
        if engine.mode != .bottleFlip {
            for (i,p) in engine.trail.enumerated() { circle(p,2,.white.opacity(Double(i)/max(1,Double(engine.trail.count))*0.3)) }
        }
        switch engine.mode {
        case .bottleFlip:
            var bottle = context; bottle.translateBy(x:engine.ball.x,y:engine.ball.y); bottle.rotate(by:.radians(Double(engine.angle)))
            bottle.fill(Path(roundedRect:CGRect(x:-11,y:-20,width:22,height:50),cornerRadius:4),with:.color(.cyan))
            bottle.fill(Path(CGRect(x:-6,y:-30,width:12,height:12)),with:.color(.white))
            bottle.fill(Path(CGRect(x:-11,y:0,width:22,height:13)),with:.color(.white.opacity(0.6)))
        case .darts:
            line(CGPoint(x:engine.ball.x-5,y:engine.ball.y+18),engine.ball,.cyan,3); circle(engine.ball,3,Theme.neon)
        case .paperToss: circle(engine.ball,9,.white); line(CGPoint(x:engine.ball.x-5,y:engine.ball.y-3),CGPoint(x:engine.ball.x+3,y:engine.ball.y+5),.gray,1)
        case .basketShot: circle(engine.ball,10,.orange)
        case .ropeCut: circle(engine.ball,10,.pink); circle(engine.ball,4,.white)
        default: circle(engine.ball,8,Theme.neon)
        }
        if let finger,!engine.launched,[.basketShot,.paperToss,.miniGolf,.ricochet,.darts].contains(engine.mode) {
            line(engine.ball,finger,.white.opacity(0.5),2)
        }
    }
}
