import SwiftUI

struct ToyView: View {
    @State private var engine:ToyEngine
    @State private var finger:CGPoint?
    @State private var dragStart:CGPoint?
    @State private var blade:[CGPoint] = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(mode:ToyMode) { _engine = State(initialValue:ToyEngine(mode:mode)) }
    var body: some View {
        GameContainerView(gameID:engine.mode.id,engine:engine,resultSummary:L10n.format("Level %d",engine.level)) {
            VStack(spacing:12) {
                hud
                GeometryReader { geometry in
                    Canvas { context,size in
                        context.scaleBy(x:size.width/320,y:size.height/460); draw(&context)
                    }.arenaBackground()
                    .environment(\.colorScheme, .dark).clipShape(RoundedRectangle(cornerRadius:24))
                        .overlay {
                            if !engine.started {
                                Text(L10n.text("Tap to start")).font(.title2.bold()).padding(24)
                                    .background(GameTheme.background.opacity(0.9),in:RoundedRectangle(cornerRadius:16)).foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { v in
                                let p = normalized(v.location,geometry.size); dragStart = normalized(v.startLocation,geometry.size); finger = p; engine.touch(p)
                                if engine.mode == .ropeCut && engine.started { blade.append(p); if blade.count > 10 { blade.removeFirst() } }
                            }
                            .onEnded { v in
                                if !engine.started { engine.start() }
                                else { engine.gesture(from:normalized(v.startLocation,geometry.size),to:normalized(v.location,geometry.size)) }
                                engine.endTouch(); finger = nil; dragStart = nil; blade = []
                            })
                }.arenaFit(320.0/460)

                if engine.mode == .drawBridge {
                    HStack {
                        Button(L10n.text("Clear")) { engine.clearBridge() }
                        Button(L10n.text("Roll")) { engine.roll() }.buttonStyle(.borderedProminent)
                    }.buttonStyle(.bordered).disabled(!engine.started || engine.launched)
                }
                Text(L10n.text(engine.notice.isEmpty ? engine.mode.hint : engine.notice))
                    .font(engine.notice.isEmpty ? .footnote : .subheadline.bold())
                    .foregroundStyle(engine.notice.isEmpty ? GameTheme.textSecondary : GameTheme.accent)
                    .multilineTextAlignment(.center).frame(minHeight:36)
                    .animation(reduceMotion ? nil : .spring(duration:0.3),value:engine.notice)
            }
        }
        .onAppear { engine.active = scenePhase == .active; engine.reduceMotion = reduceMotion }.onDisappear { engine.active = false }
        .onChange(of:reduceMotion) { _,value in engine.reduceMotion = value }
        .onChange(of:scenePhase) { _,p in engine.active = p == .active; finger = nil; dragStart = nil; blade = []; engine.endTouch() }
        .onChange(of:engine.state) { _,_ in finger = nil; dragStart = nil; blade = []; engine.endTouch() }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for:.milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime; engine.advance(now-last); last = now
            }
        }
    }

    private var hud: some View {
        HStack(spacing:10) {
            Text(L10n.format("Level %d",engine.level))
            if engine.streak >= 2 {
                Label { Text(verbatim:"×\(engine.nextMultiplier)") } icon: { Image(systemName:"flame.fill") }
                    .foregroundStyle(.orange)
                    .transition(.scale.combined(with:.opacity))
            }
            Spacer()
            if engine.mode == .basketShot && engine.wind != 0 {
                Label(String(format:"%@ %d",engine.wind > 0 ? "→" : "←",Int(abs(engine.wind))),systemImage:"wind")
                    .foregroundStyle(GameTheme.textSecondary)
            }
            HStack(spacing:3) {
                ForEach(0..<engine.maxLives,id:\.self) { i in
                    Image(systemName:i < engine.lives ? "heart.fill" : "heart")
                        .foregroundStyle(i < engine.lives ? Color.pink : GameTheme.textSecondary)
                }
            }
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(L10n.format("Lives: %d",engine.lives))
        }
        .font(.headline.monospacedDigit()).foregroundStyle(GameTheme.accent)
        .animation(reduceMotion ? nil : .spring(duration:0.3),value:engine.streak)
    }

    private func normalized(_ p:CGPoint,_ size:CGSize) -> CGPoint { CGPoint(x:p.x/size.width*320,y:p.y/size.height*460) }

    private func draw(_ context:inout GraphicsContext) {
        func circle(_ p:CGPoint,_ r:CGFloat,_ color:Color) { context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),with:.color(color)) }
        func ball(_ p:CGPoint,_ r:CGFloat,_ light:Color,_ dark:Color) {
            circle(CGPoint(x:p.x+2,y:p.y+3),r,.black.opacity(0.3))
            context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)),
                         with:.radialGradient(Gradient(colors:[light,dark]),center:CGPoint(x:p.x-r*0.35,y:p.y-r*0.4),startRadius:0,endRadius:r*1.5))
        }
        func line(_ a:CGPoint,_ b:CGPoint,_ color:Color,_ width:CGFloat = 3) {
            var path = Path(); path.move(to:a); path.addLine(to:b); context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
        }
        func box(_ r:CGRect,_ color:Color) { context.fill(Path(roundedRect:r,cornerRadius:4),with:.color(color)) }
        func gradientBox(_ r:CGRect,_ top:Color,_ bottom:Color,_ radius:CGFloat = 6) {
            context.fill(Path(roundedRect:r,cornerRadius:radius),with:.linearGradient(Gradient(colors:[top,bottom]),startPoint:CGPoint(x:r.midX,y:r.minY),endPoint:CGPoint(x:r.midX,y:r.maxY)))
        }
        func star(_ p:CGPoint,_ r:CGFloat) {
            var path = Path()
            for i in 0..<10 {
                let a = CGFloat(i) * .pi/5 - .pi/2,len = i.isMultiple(of:2) ? r : r*0.45
                let q = CGPoint(x:p.x+cos(a)*len,y:p.y+sin(a)*len)
                if i == 0 { path.move(to:q) } else { path.addLine(to:q) }
            }
            path.closeSubpath()
            circle(p,r*1.3,.yellow.opacity(0.15))
            context.fill(path,with:.color(.yellow))
        }

        switch engine.mode {
        case .basketShot:
            gradientBox(CGRect(x:0,y:0,width:320,height:460),Color(red:0.10,green:0.13,blue:0.28),Color(red:0.05,green:0.06,blue:0.12),0)
            box(CGRect(x:0,y:430,width:320,height:30),Color(red:0.35,green:0.22,blue:0.14))
            let p = engine.target
            box(CGRect(x:p.x+27,y:p.y-60,width:8,height:72),.white.opacity(0.9))
            box(CGRect(x:p.x+29,y:p.y-38,width:4,height:24),.red.opacity(0.7))
            line(CGPoint(x:p.x+34,y:p.y+12),CGPoint(x:p.x+34,y:460),.gray.opacity(0.5),4)
            for i in 0...4 {
                let t = CGFloat(i)/4
                line(CGPoint(x:p.x-25+50*t,y:p.y),CGPoint(x:p.x-14+28*t,y:p.y+35),.white.opacity(0.45),1.5)
            }
            line(CGPoint(x:p.x-20,y:p.y+17),CGPoint(x:p.x+20,y:p.y+17),.white.opacity(0.35),1.5)
            line(CGPoint(x:p.x-14,y:p.y+35),CGPoint(x:p.x+14,y:p.y+35),.white.opacity(0.45),1.5)
            line(CGPoint(x:p.x-25,y:p.y),CGPoint(x:p.x+25,y:p.y),.orange,4)
            if engine.wind != 0 {
                // Drifting streaks show wind direction and strength.
                let w = engine.wind,len = min(40,abs(w)*0.45)
                for row in 0..<3 {
                    let y = 70+CGFloat(row)*45,x = 40+CGFloat(row)*30
                    line(CGPoint(x:x,y:y),CGPoint(x:x+(w > 0 ? len : -len),y:y),.white.opacity(0.18),2)
                }
            }
        case .bottleFlip:
            gradientBox(CGRect(x:0,y:0,width:320,height:400),Color(red:0.16,green:0.12,blue:0.25),Color(red:0.06,green:0.06,blue:0.10),0)
            gradientBox(CGRect(x:0,y:400,width:320,height:60),Color(red:0.45,green:0.30,blue:0.18),Color(red:0.25,green:0.16,blue:0.10),0)
            let pad = CGRect(x:engine.padX-engine.padWidth/2,y:396,width:engine.padWidth,height:6)
            circle(CGPoint(x:engine.padX,y:399),engine.padWidth*0.6,.yellow.opacity(0.12))
            box(pad,.yellow)
        case .miniGolf:
            gradientBox(CGRect(x:0,y:0,width:320,height:460),Color(red:0.10,green:0.33,blue:0.16),Color(red:0.05,green:0.20,blue:0.09),0)
            for i in 0..<9 where i.isMultiple(of:2) { box(CGRect(x:10,y:30+CGFloat(i)*46,width:300,height:46),.white.opacity(0.03)) }
            context.stroke(Path(roundedRect:CGRect(x:6,y:26,width:308,height:423),cornerRadius:8),with:.color(Color(red:0.45,green:0.30,blue:0.18)),lineWidth:6)
            for s in engine.obstacles { line(s.a,s.b,Color(red:0.85,green:0.55,blue:0.25),12); line(s.a,s.b,Color(red:1,green:0.75,blue:0.4),4) }
            if let bar = engine.movingBar { line(bar.a,bar.b,.pink,12); line(bar.a,bar.b,.white.opacity(0.6),3) }
            circle(engine.target,15,.black.opacity(0.25)); circle(engine.target,13,.black)
            line(engine.target,CGPoint(x:engine.target.x,y:engine.target.y-38),.white,2)
            var flag = Path(); flag.move(to:CGPoint(x:engine.target.x,y:engine.target.y-38)); flag.addLine(to:CGPoint(x:engine.target.x+22,y:engine.target.y-28)); flag.addLine(to:CGPoint(x:engine.target.x,y:engine.target.y-20)); context.fill(flag,with:.color(.pink))
            for i in 0..<3 { circle(CGPoint(x:24+CGFloat(i)*14,y:14),4.5,i < 3-engine.strokes ? .white : .white.opacity(0.2)) }
        case .plinko:
            gradientBox(CGRect(x:0,y:0,width:320,height:460),Color(red:0.12,green:0.08,blue:0.22),Color(red:0.04,green:0.05,blue:0.12),0)
            for (i,p) in engine.pegs.enumerated() {
                if engine.goldPegs.contains(i) { circle(p,10,.yellow.opacity(0.2)); ball(p,6,.white,.yellow) }
                else { circle(p,5,.cyan.opacity(0.8)) }
            }
            let values = engine.binValues
            for i in 0..<6 {
                let x = CGFloat(i)*320/6, jackpot = i == engine.selectedBin
                let near = abs(i-engine.selectedBin) == 1
                if jackpot { circle(CGPoint(x:x+320/12,y:431),34,GameTheme.accent.opacity(0.2)) }
                gradientBox(CGRect(x:x+2,y:411,width:320/6-4,height:40),jackpot ? .cyan : near ? Color(white:0.35) : Color(white:0.2),jackpot ? GameTheme.accent : Color(white:0.12))
                context.draw(Text(verbatim:"\(values[i])").font(.caption.bold()).foregroundStyle(jackpot ? .black : .white),at:CGPoint(x:x+320/12,y:431))
            }
            if !engine.launched && engine.started { line(CGPoint(x:engine.ball.x,y:50),CGPoint(x:engine.ball.x,y:80),.white.opacity(0.25),2) }
        case .ropeCut:
            gradientBox(CGRect(x:0,y:0,width:320,height:460),Color(red:0.18,green:0.10,blue:0.20),Color(red:0.06,green:0.05,blue:0.10),0)
            for s in engine.stars { star(s,11) }
            for i in engine.anchors.indices {
                if engine.ropes[i] {
                    line(engine.anchors[i],engine.ball,Color(red:0.6,green:0.4,blue:0.2),4)
                    line(engine.anchors[i],engine.ball,Color(red:0.95,green:0.75,blue:0.45),1.5)
                }
                circle(engine.anchors[i],7,.white); circle(engine.anchors[i],3,.gray)
            }
            let half = engine.targetHalfWidth
            var bowl = Path()
            bowl.move(to:CGPoint(x:engine.target.x-half,y:398))
            bowl.addQuadCurve(to:CGPoint(x:engine.target.x+half,y:398),control:CGPoint(x:engine.target.x,y:440))
            bowl.closeSubpath()
            context.fill(bowl,with:.linearGradient(Gradient(colors:[.green,Color(red:0.1,green:0.5,blue:0.2)]),startPoint:CGPoint(x:engine.target.x,y:398),endPoint:CGPoint(x:engine.target.x,y:430)))
            circle(CGPoint(x:engine.target.x-9,y:408),2.5,.black); circle(CGPoint(x:engine.target.x+9,y:408),2.5,.black)
            if blade.count > 1 {
                var path = Path(); path.addLines(blade)
                context.stroke(path,with:.color(.white.opacity(0.7)),style:StrokeStyle(lineWidth:3,lineCap:.round,lineJoin:.round))
            }
        case .drawBridge:
            gradientBox(CGRect(x:0,y:0,width:320,height:460),Color(red:0.08,green:0.16,blue:0.26),Color(red:0.04,green:0.06,blue:0.12),0)
            box(CGRect(x:0,y:440,width:320,height:20),Color(red:0.1,green:0.3,blue:0.5).opacity(0.6))
            gradientBox(CGRect(x:0,y:engine.leftTop,width:engine.leftEdge,height:460-engine.leftTop),Color(white:0.45),Color(white:0.2))
            gradientBox(CGRect(x:engine.rightEdge,y:engine.rightTop,width:320-engine.rightEdge,height:460-engine.rightTop),Color(white:0.45),Color(white:0.2))
            circle(engine.leftConnector,7,.cyan); circle(engine.rightConnector,7,.cyan)
            for s in engine.stars { star(s,11) }
            context.stroke(engine.bridgePath,with:.color(.cyan.opacity(0.25)),style:StrokeStyle(lineWidth:11,lineCap:.round,lineJoin:.round))
            context.stroke(engine.bridgePath,with:.color(.cyan),style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round))
            circle(engine.target,22,.green.opacity(0.25)); circle(engine.target,10,.green.opacity(0.6))
            // Ink meter
            let left = max(0,1-engine.inkUsed/max(1,engine.inkMax))
            box(CGRect(x:14,y:14,width:100,height:8),.white.opacity(0.15))
            box(CGRect(x:14,y:14,width:100*left,height:8),left < 0.2 ? .red : .cyan)
        }
        if engine.mode != .bottleFlip {
            for (i,p) in engine.trail.enumerated() { circle(p,2,.white.opacity(Double(i)/max(1,Double(engine.trail.count))*0.3)) }
        }
        switch engine.mode {
        case .bottleFlip:
            var shadow = context
            shadow.opacity = 0.35
            let lift = max(0,370-engine.ball.y)
            shadow.fill(Path(ellipseIn:CGRect(x:engine.ball.x-14+lift*0.02,y:398,width:28-lift*0.04,height:5)),with:.color(.black))
            var bottle = context; bottle.translateBy(x:engine.ball.x,y:engine.ball.y); bottle.rotate(by:.radians(Double(engine.angle)))
            bottle.fill(Path(roundedRect:CGRect(x:-11,y:-20,width:22,height:50),cornerRadius:6),
                        with:.linearGradient(Gradient(colors:[.cyan.opacity(0.7),.cyan,.cyan.opacity(0.55)]),startPoint:CGPoint(x:-11,y:0),endPoint:CGPoint(x:11,y:0)))
            bottle.fill(Path(roundedRect:CGRect(x:-6,y:-31,width:12,height:13),cornerRadius:2),with:.color(.white))
            bottle.fill(Path(CGRect(x:-11,y:2,width:22,height:12)),with:.color(.white.opacity(0.6)))
            bottle.fill(Path(roundedRect:CGRect(x:-7,y:-16,width:3,height:40),cornerRadius:1.5),with:.color(.white.opacity(0.35)))
        case .basketShot:
            ball(engine.ball,10,Color(red:1,green:0.65,blue:0.3),Color(red:0.8,green:0.3,blue:0.05))
            var seams = context; seams.translateBy(x:engine.ball.x,y:engine.ball.y); seams.rotate(by:.radians(Double(engine.ball.x)/10))
            seams.stroke(Path { $0.move(to:CGPoint(x:-10,y:0)); $0.addLine(to:CGPoint(x:10,y:0)) },with:.color(.black.opacity(0.4)),lineWidth:1)
            seams.stroke(Path { $0.move(to:CGPoint(x:0,y:-10)); $0.addLine(to:CGPoint(x:0,y:10)) },with:.color(.black.opacity(0.4)),lineWidth:1)
        case .ropeCut: ball(engine.ball,11,.pink,Color(red:0.7,green:0.1,blue:0.4)); circle(CGPoint(x:engine.ball.x-3,y:engine.ball.y-3),3.5,.white.opacity(0.85))
        case .miniGolf: ball(engine.ball,8,.white,Color(white:0.7))
        case .plinko: ball(engine.ball,8,.white,GameTheme.accent)
        case .drawBridge: ball(engine.ball,10,.orange,.red)
        }
        if let finger,!engine.launched,[.basketShot,.miniGolf].contains(engine.mode) {
            let start = dragStart ?? engine.ball
            let dx = start.x-finger.x, dy = start.y-finger.y
            let power = min(1,hypot(dx,dy)/(engine.mode == .basketShot ? 145 : 175))
            let scale = min(1,90/max(1,hypot(dx,dy)))
            let aim = CGPoint(x:engine.ball.x+dx*scale,y:engine.ball.y+dy*scale)
            let tint = Color(hue:0.33*(1-power),saturation:0.85,brightness:1)
            line(engine.ball,finger,.white.opacity(0.2),2)
            // Dotted aim line, colored from green (soft) to red (full power).
            for i in 1...6 {
                let t = CGFloat(i)/6
                circle(CGPoint(x:engine.ball.x+(aim.x-engine.ball.x)*t,y:engine.ball.y+(aim.y-engine.ball.y)*t),2+t*1.5,tint.opacity(0.4+0.6*Double(t)))
            }
        }
        for p in engine.particles {
            circle(p.p,p.size,p.color.opacity(max(0,1-p.age/p.life)))
        }
        for p in engine.popups {
            let fade = p.age < 0.7 ? 1 : max(0,1-(p.age-0.7)/0.4)
            context.drawLayer { layer in
                layer.opacity = fade
                layer.addFilter(.shadow(color:.black.opacity(0.6),radius:2,y:1))
                layer.draw(Text(verbatim:p.text).font(p.big ? .title3.weight(.heavy) : .subheadline.weight(.bold)).foregroundStyle(p.color),at:p.p)
            }
        }
    }
}
