import SwiftUI

struct BounceView: View {
    @State private var engine = BounceEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GameContainerView(gameID:.bounce,engine:engine) {
            VStack(spacing:12) {
                HStack {
                    Text(L10n.format("Level %d of %d",engine.levelIndex+1,BounceLevel.levels.count))
                    Spacer()
                    Label("\(engine.collected.count)/\(engine.level.rings.count)",systemImage:"circle")
                    Label(String(engine.lives),systemImage:"heart.fill").foregroundStyle(.pink)
                }.font(.caption.bold().monospacedDigit()).foregroundStyle(GameTheme.accent)
                GeometryReader { geometry in
                    Canvas { context,size in
                        context.scaleBy(x:size.width/360,y:size.height/420)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        draw(&context)
                    }
                    .arenaBackground()
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius:24))
                    .overlay {
                        if !engine.started {
                            Button(L10n.text("Tap to start")) { engine.start() }
                                .font(.title2.bold()).foregroundStyle(GameTheme.accent).padding(24)
                                .background(GameTheme.background.opacity(0.95),in:RoundedRectangle(cornerRadius:16))
                        } else if !engine.message.isEmpty {
                            Text(L10n.text(engine.message)).font(.title2.bold()).foregroundStyle(GameTheme.ink).padding(20)
                                .background(GameTheme.background.opacity(0.9),in:RoundedRectangle(cornerRadius:16))
                        }
                    }
                }.arenaFit(360.0/420)
                HStack(spacing:12) {
                    BounceControl(symbol:"arrow.left",label:L10n.text("Left"),set:engine.holdLeft)
                    BounceControl(symbol:"arrow.right",label:L10n.text("Right"),set:engine.holdRight)
                    Spacer(minLength:12)
                    BounceControl(symbol:"arrow.up",label:L10n.text("Jump"),set:engine.holdJump)
                }.disabled(!engine.started || engine.state != .playing || engine.transition > 0)
                Text(L10n.text(engine.gateOpen ? "All rings collected! Reach the green exit." : "Hold arrows to roll. Tap Jump to leap. Collect every ring, stomp the critters and reach the exit."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false }
        .onChange(of:scenePhase) { _,phase in engine.active = phase == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for:.milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime; engine.advance(now-last); last = now
            }
        }
    }
    private func draw(_ context:inout GraphicsContext) {
        let offset = engine.cameraX
        context.fill(Path(CGRect(x:-20,y:-20,width:400,height:460)),
                     with:.linearGradient(Gradient(colors:[Color(red:0.08,green:0.07,blue:0.2),Color(red:0.16,green:0.1,blue:0.25)]),startPoint:.zero,endPoint:CGPoint(x:0,y:420)))
        context.fill(Path(ellipseIn:CGRect(x:250-offset*0.05,y:40,width:56,height:56)),with:.color(Color(red:1,green:0.9,blue:0.7).opacity(0.85)))
        // Distant scenery scrolls more slowly than the foreground.
        for i in 0..<12 {
            let x = CGFloat(i)*130-offset*0.3
            var mountain = Path(); mountain.move(to:CGPoint(x:x-80,y:365)); mountain.addLine(to:CGPoint(x:x,y:150+CGFloat(i%3)*30)); mountain.addLine(to:CGPoint(x:x+110,y:365)); mountain.closeSubpath()
            context.fill(mountain,with:.color(.indigo.opacity(0.13)))
        }
        context.translateBy(x:-offset,y:0)
        for p in engine.level.platforms {
            context.fill(Path(roundedRect:p,cornerRadius:3),with:.color(GameTheme.surfaceHigh))
            context.fill(Path(CGRect(x:p.minX,y:p.minY,width:p.width,height:4)),with:.color(.cyan.opacity(0.85)))
            for x in stride(from:p.minX+8,to:p.maxX,by:24) {
                context.fill(Path(CGRect(x:x,y:p.minY+9,width:12,height:3)),with:.color(.white.opacity(0.08)))
            }
        }
        for spike in engine.level.spikes {
            let count = max(1,Int(spike.width/12)),width = spike.width/CGFloat(count)
            for i in 0..<count {
                let x = spike.minX+CGFloat(i)*width
                var triangle = Path(); triangle.move(to:CGPoint(x:x,y:spike.maxY)); triangle.addLine(to:CGPoint(x:x+width/2,y:spike.minY)); triangle.addLine(to:CGPoint(x:x+width,y:spike.maxY)); triangle.closeSubpath()
                context.fill(triangle,with:.color(.pink))
            }
        }
        for (i,p) in engine.level.rings.enumerated() where !engine.collected.contains(i) {
            // Rings slowly spin around their vertical axis.
            let w = 24*max(0.25,abs(cos(engine.clock*2.2+CGFloat(i))))
            let ring = Path(ellipseIn:CGRect(x:p.x-w/2,y:p.y-16,width:w,height:32))
            context.stroke(ring,with:.color(.yellow.opacity(0.15)),lineWidth:10)
            context.stroke(ring,with:.color(.yellow),lineWidth:4)
        }
        let gate = engine.level.exit
        context.fill(Path(roundedRect:gate,cornerRadius:10),with:.color(engine.gateOpen ? .green.opacity(0.3) : .white.opacity(0.05)))
        context.stroke(Path(roundedRect:gate,cornerRadius:10),with:.color(engine.gateOpen ? GameTheme.accent : GameTheme.textSecondary),lineWidth:3)
        var glyph = context.resolve(Image(systemName:engine.gateOpen ? "arrow.right" : "lock.fill"))
        glyph.shading = .color(engine.gateOpen ? GameTheme.accent : GameTheme.textSecondary)
        context.draw(glyph,in:CGRect(x:gate.midX-9,y:gate.midY-10,width:18,height:20))
        for enemy in engine.enemies where enemy.alive {
            let r = BounceEnemy.radius
            let bob = sin(engine.clock*10+enemy.x*0.05)*1.5
            let c = CGPoint(x:enemy.x,y:enemy.y+bob)
            var spikes = Path()
            for k in 0..<12 {
                let a = CGFloat(k)/12 * .pi*2 + engine.clock*1.5
                let len = k.isMultiple(of:2) ? r+5 : r-1
                let q = CGPoint(x:c.x+cos(a)*len,y:c.y+sin(a)*len)
                if k == 0 { spikes.move(to:q) } else { spikes.addLine(to:q) }
            }
            spikes.closeSubpath()
            context.fill(spikes,with:.color(Color(red:0.55,green:0.25,blue:0.85)))
            context.fill(Path(ellipseIn:CGRect(x:c.x-r,y:c.y-r,width:r*2,height:r*2)),with:.radialGradient(Gradient(colors:[Color(red:0.85,green:0.6,blue:1),Color(red:0.45,green:0.15,blue:0.7)]),center:CGPoint(x:c.x-3,y:c.y-4),startRadius:0,endRadius:r*1.4))
            let look: CGFloat = enemy.speed > 0 ? 2 : -2
            for s in [-4.0,4.0] {
                context.fill(Path(ellipseIn:CGRect(x:c.x+s-3,y:c.y-5,width:6,height:7)),with:.color(.white))
                context.fill(Path(ellipseIn:CGRect(x:c.x+s-1.5+look*0.6,y:c.y-3,width:3,height:4)),with:.color(.black))
            }
        }
        var ball = context
        ball.translateBy(x:engine.ball.x,y:engine.ball.y); ball.rotate(by:.radians(Double(engine.rotation)))
        ball.opacity = engine.invulnerable > 0 && Int(engine.invulnerable*12).isMultiple(of:2) ? 0.55 : 1
        ball.fill(Path(ellipseIn:CGRect(x:-12,y:-12,width:24,height:24)),with:.radialGradient(Gradient(colors:[Color(red:1,green:0.5,blue:0.45),.red,Color(red:0.6,green:0,blue:0.05)]),center:CGPoint(x:-4,y:-5),startRadius:0,endRadius:18))
        ball.fill(Path(ellipseIn:CGRect(x:-7,y:-8,width:8,height:6)),with:.color(.white.opacity(0.8)))
        ball.stroke(Path(ellipseIn:CGRect(x:-11,y:-11,width:22,height:22)),with:.color(.pink),lineWidth:1.5)
        engine.fx.draw(in:&context)
    }
}

private struct BounceControl: View {
    let symbol:String
    let label:String
    let set:(Bool)->Void
    @GestureState private var pressed = false
    var body: some View {
        Image(systemName:symbol).font(.title2.bold()).foregroundStyle(pressed ? .white : GameTheme.accent)
            .frame(width:70,height:58)
            .background(pressed ? GameTheme.accent : GameTheme.surfaceHigh,in:RoundedRectangle(cornerRadius:16))
            .contentShape(RoundedRectangle(cornerRadius:16))
            .gesture(DragGesture(minimumDistance:0)
                .updating($pressed) { _,value,_ in value = true }
                .onChanged { _ in set(true) }
                .onEnded { _ in set(false) })
            .onChange(of:pressed) { _,value in if !value { set(false) } }
            .onDisappear { set(false) }
            .accessibilityLabel(label)
    }
}
