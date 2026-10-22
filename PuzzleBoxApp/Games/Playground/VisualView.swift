import SwiftUI

struct VisualView:View {
    @State private var engine:VisualEngine
    init(mode:VisualMode) { _engine = State(initialValue:VisualEngine(mode:mode)) }
    private let pictureColors:[Color] = [.cyan,.pink,.orange,.green,.purple,.yellow,.mint]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        GameContainerView(gameID:engine.mode.id,engine:engine,resultSummary:L10n.format("Level %d",engine.levelIndex+1),nextLevel:engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing:12) {
                HStack(spacing:10) {
                    Menu {
                        ForEach(0..<engine.levelCount,id: \.self) { level in
                            Button(levelTitle(level)) { engine.loadLevel(level) }
                        }
                    } label: {
                        Label(levelTitle(engine.levelIndex),systemImage:"square.grid.2x2")
                    }
                    Text(L10n.format("%d moves",engine.moves))
                    Spacer()
                    HStack(spacing:1) {
                        ForEach(0..<3,id:\.self) { i in
                            Image(systemName:i < engine.stars ? "star.fill" : "star").foregroundStyle(i < engine.stars ? Color.yellow : GameTheme.textSecondary)
                        }
                    }.font(.caption)
                    if engine.mode == .matchstick {
                        Button { engine.resetMatches() } label: { Image(systemName:"arrow.counterclockwise.circle") }
                            .accessibilityLabel(L10n.text("Reset"))
                    }
                }
                .font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.accent)
                switch engine.mode {
                case .rotatePuzzle: rotateBoard
                case .matchstick:
                    Text(L10n.format(engine.matchesToMove == 1 ? "Move %d match" : "Move %d matches", engine.matchesToMove - engine.matchesMoved))
                        .font(.headline).foregroundStyle(.orange)
                    GeometryReader { geometry in
                        Canvas { context,size in context.scaleBy(x:size.width/320,y:size.height/460); draw(&context) }
                            .arenaBackground()
                            .environment(\.colorScheme, .dark).clipShape(RoundedRectangle(cornerRadius:24))
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance:0)
                                .onEnded { v in
                                    interact(CGPoint(x:v.location.x/geometry.size.width*320,y:v.location.y/geometry.size.height*460))
                                })
                    }.arenaFit(320.0/460)
                }
                if !engine.feedback.isEmpty { Text(L10n.text(engine.feedback)).font(.caption).foregroundStyle(.orange) }
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .id(engine.levelIndex)
    }

    /// "Level 12 · 4×4" for Rotate Puzzle, just "Level 12" for Matchstick.
    private func levelTitle(_ level:Int) -> String {
        let title = L10n.format("Level %d",level+1)
        guard engine.mode == .rotatePuzzle else { return title }
        let side = VisualEngine.rotateSide(level).side
        return "\(title) · \(side)×\(side)"
    }

    /// Each tile is its own view so a tap animates a smooth quarter turn.
    private var rotateBoard: some View {
        VStack(spacing:14) {
            Canvas { context,size in picture(rect:CGRect(origin:.zero,size:size),context:&context) }
                .frame(width:90,height:90).clipShape(RoundedRectangle(cornerRadius:12))
                .overlay { RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.4),lineWidth:2) }
                .accessibilityLabel(L10n.text("Target picture"))
            GeometryReader { geo in
                let side = min(geo.size.width,geo.size.height)
                let n = engine.size
                let tile = side/CGFloat(n)
                // Rows of tiles rather than offsets in a ZStack: an offset
                // doesn't move a view's frame, which pushed the grid off the board.
                VStack(spacing:0) {
                    ForEach(0..<n,id:\.self) { r in
                        HStack(spacing:0) {
                            ForEach(0..<n,id:\.self) { c in
                                rotateTile(r*n+c,row:r,column:c,tile:tile,side:side)
                            }
                        }
                    }
                }
                .frame(width:side,height:side)
                .clipShape(RoundedRectangle(cornerRadius:16))
                .frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            .aspectRatio(1,contentMode:.fit)
        }
    }

    private func rotateTile(_ i:Int,row r:Int,column c:Int,tile:CGFloat,side:CGFloat) -> some View {
        let turns = engine.turns.indices.contains(i) ? engine.turns[i] : 0
        return Canvas { context,_ in
            picture(rect:CGRect(x:-CGFloat(c)*tile,y:-CGFloat(r)*tile,width:side,height:side),context:&context)
        }
        .frame(width:tile,height:tile)
        .rotationEffect(.degrees(Double(turns)*90))
        .animation(reduceMotion ? nil : .spring(duration:0.3,bounce:0.25),value:turns)
        .clipShape(Rectangle())
        .overlay {
            // Tiles already in place lose their seam, a gentle hint of progress.
            Rectangle().strokeBorder(engine.isCorrect(i) ? Color.clear : Color.black.opacity(0.35),lineWidth:1)
        }
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(i) }
    }

    private func interact(_ p:CGPoint) {
        switch engine.mode {
        case .rotatePuzzle: break
        case .matchstick:
            let segments = matchSegments()
            let candidates = segments.indices.filter { engine.selectedMatch != nil || engine.cells[$0] == 1 }
            if let i = candidates.min(by: { distance(p,segments[$0]) < distance(p,segments[$1]) }),distance(p,segments[i]) < 13 { engine.tap(i) }
        }
    }

    private func distance(_ p:CGPoint,_ line:(CGPoint,CGPoint)) -> CGFloat {
        let (a,b) = line,dx = b.x-a.x,dy = b.y-a.y
        let t = min(1,max(0,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(1,dx*dx+dy*dy)))
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    private func matchSegments() -> [(CGPoint,CGPoint)] {
        func digit(_ x:CGFloat) -> [(CGPoint,CGPoint)] {
            let y:CGFloat = 175,w:CGFloat = 38,h:CGFloat = 76
            return [(CGPoint(x:x+3,y:y),CGPoint(x:x+w-3,y:y)),(CGPoint(x:x+w,y:y+3),CGPoint(x:x+w,y:y+h/2-3)),(CGPoint(x:x+w,y:y+h/2+3),CGPoint(x:x+w,y:y+h-3)),(CGPoint(x:x+3,y:y+h),CGPoint(x:x+w-3,y:y+h)),(CGPoint(x:x,y:y+h/2+3),CGPoint(x:x,y:y+h-3)),(CGPoint(x:x,y:y+3),CGPoint(x:x,y:y+h/2-3)),(CGPoint(x:x+3,y:y+h/2),CGPoint(x:x+w-3,y:y+h/2))]
        }
        return digit(16)+[(CGPoint(x:78,y:213),CGPoint(x:108,y:213)),(CGPoint(x:93,y:198),CGPoint(x:93,y:228))]+digit(130)+digit(262)
    }
    private func draw(_ context:inout GraphicsContext) {

        func line(_ a:CGPoint,_ b:CGPoint,_ color:Color,_ width:CGFloat = 2) {
            var path = Path(); path.move(to:a); path.addLine(to:b); context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
        }

        switch engine.mode {
        case .rotatePuzzle: break // Drawn by `rotateBoard` as individual tiles.
        case .matchstick:
            for (i,segment) in matchSegments().enumerated() {
                if engine.cells[i] == 1 {
                    line(segment.0,segment.1,engine.selectedMatch == i ? GameTheme.accent.opacity(0.4) : .black.opacity(0.4),11)
                    line(segment.0,segment.1,engine.selectedMatch == i ? GameTheme.accent : Color(red:0.95,green:0.75,blue:0.45),6)
                } else {
                    line(segment.0,segment.1,.white.opacity(engine.selectedMatch == nil ? 0.1 : 0.3),5)
                }
                if engine.cells[i] == 1 { context.fill(Path(ellipseIn:CGRect(x:segment.0.x-3,y:segment.0.y-3,width:6,height:6)),with:.color(.red)) }
            }
            line(CGPoint(x:197,y:204),CGPoint(x:229,y:204),.white,4)
            line(CGPoint(x:197,y:223),CGPoint(x:229,y:223),.white,4)
        }
    }

    /// Five painted scenes cycle through the levels; a small corner tick on every
    /// tile region keeps each tile's orientation readable even on plain areas.
    private func picture(rect:CGRect,context:inout GraphicsContext) {
        var c = context; c.translateBy(x:rect.minX,y:rect.minY); c.scaleBy(x:rect.width/300,y:rect.height/300)
        func fill(_ path:Path,_ color:Color) { c.fill(path,with:.color(color)) }
        func gradient(_ r:CGRect,_ top:Color,_ bottom:Color) {
            c.fill(Path(r),with:.linearGradient(Gradient(colors:[top,bottom]),startPoint:CGPoint(x:r.midX,y:r.minY),endPoint:CGPoint(x:r.midX,y:r.maxY)))
        }
        func circle(_ x:CGFloat,_ y:CGFloat,_ r:CGFloat,_ color:Color) { fill(Path(ellipseIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2)),color) }
        let full = CGRect(x:0,y:0,width:300,height:300)
        switch engine.levelIndex % 5 {
        case 0: // Mountain valley
            gradient(full,Color(red:0.45,green:0.8,blue:1),Color(red:0.75,green:0.92,blue:1))
            circle(238,55,32,.yellow)
            var mountains = Path(); mountains.move(to:CGPoint(x:0,y:240)); mountains.addLine(to:CGPoint(x:90,y:65)); mountains.addLine(to:CGPoint(x:190,y:240)); mountains.addLine(to:CGPoint(x:235,y:145)); mountains.addLine(to:CGPoint(x:300,y:220)); mountains.addLine(to:CGPoint(x:300,y:300)); mountains.addLine(to:CGPoint(x:0,y:300)); mountains.closeSubpath()
            fill(mountains,.indigo)
            var snow = Path(); snow.move(to:CGPoint(x:72,y:100)); snow.addLine(to:CGPoint(x:90,y:65)); snow.addLine(to:CGPoint(x:108,y:100)); snow.closeSubpath(); fill(snow,.white)
            var river = Path(); river.move(to:CGPoint(x:160,y:170)); river.addCurve(to:CGPoint(x:90,y:300),control1:CGPoint(x:250,y:230),control2:CGPoint(x:55,y:240)); c.stroke(river,with:.color(.mint),lineWidth:23)
            fill(Path(CGRect(x:28,y:213,width:43,height:42)),.orange)
            var roof = Path(); roof.move(to:CGPoint(x:20,y:214)); roof.addLine(to:CGPoint(x:50,y:189)); roof.addLine(to:CGPoint(x:80,y:214)); roof.closeSubpath(); fill(roof,.pink)
            for (x,y) in [(30,35),(100,15),(5,125),(255,265)] { fill(Path(ellipseIn:CGRect(x:CGFloat(x),y:CGFloat(y),width:28,height:12)),.white.opacity(0.8)) }
        case 1: // Night city
            gradient(full,Color(red:0.05,green:0.05,blue:0.2),Color(red:0.3,green:0.15,blue:0.45))
            circle(70,60,26,Color(red:1,green:0.95,blue:0.75)); circle(82,52,24,Color(red:0.08,green:0.07,blue:0.25))
            for k in 0..<25 { circle(CGFloat((k*67)%300),CGFloat((k*41)%150),1.6,.white.opacity(0.8)) }
            let heights:[CGFloat] = [120,180,95,210,140,165,105]
            for (k,h) in heights.enumerated() {
                let x = CGFloat(k)*43
                fill(Path(CGRect(x:x,y:300-h,width:40,height:h)),Color(red:0.12,green:0.12,blue:0.25))
                for wy in stride(from:300-h+12,to:290,by:20) { for wx in [x+8,x+24] where (Int(wy)+Int(wx)+k).isMultiple(of:3) { fill(Path(CGRect(x:wx,y:wy,width:8,height:10)),.yellow.opacity(0.85)) } }
            }
        case 2: // Sunset sea
            gradient(CGRect(x:0,y:0,width:300,height:170),Color(red:0.98,green:0.45,blue:0.35),Color(red:1,green:0.8,blue:0.45))
            circle(150,165,48,Color(red:1,green:0.9,blue:0.4))
            gradient(CGRect(x:0,y:165,width:300,height:135),Color(red:0.15,green:0.35,blue:0.65),Color(red:0.05,green:0.15,blue:0.35))
            for k in 0..<6 { fill(Path(roundedRect:CGRect(x:CGFloat(60+k*12),y:CGFloat(185+k*16),width:CGFloat(180-k*24),height:4),cornerRadius:2),.yellow.opacity(0.5)) }
            var boat = Path(); boat.move(to:CGPoint(x:40,y:230)); boat.addLine(to:CGPoint(x:100,y:230)); boat.addLine(to:CGPoint(x:90,y:245)); boat.addLine(to:CGPoint(x:50,y:245)); boat.closeSubpath(); fill(boat,Color(red:0.3,green:0.15,blue:0.1))
            var sail = Path(); sail.move(to:CGPoint(x:70,y:228)); sail.addLine(to:CGPoint(x:70,y:180)); sail.addLine(to:CGPoint(x:98,y:228)); sail.closeSubpath(); fill(sail,.white)
            for (x,y) in [(210,60),(240,75),(225,95)] { var bird = Path(); bird.move(to:CGPoint(x:x-8,y:y)); bird.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x:x-4,y:y-6)); bird.addQuadCurve(to:CGPoint(x:x+8,y:y),control:CGPoint(x:x+4,y:y-6)); c.stroke(bird,with:.color(.black.opacity(0.6)),lineWidth:2) }
        case 3: // Flower meadow
            gradient(full,Color(red:0.6,green:0.88,blue:1),Color(red:0.85,green:0.95,blue:1))
            fill(Path(ellipseIn:CGRect(x:-60,y:150,width:260,height:200)),Color(red:0.35,green:0.7,blue:0.3))
            fill(Path(ellipseIn:CGRect(x:120,y:170,width:260,height:200)),Color(red:0.3,green:0.62,blue:0.25))
            let petals:[Color] = [.pink,.yellow,.purple,.orange,.red,.white]
            for k in 0..<14 {
                let x = CGFloat(20+(k*53)%270), y = CGFloat(200+(k*29)%90)
                c.stroke(Path { $0.move(to:CGPoint(x:x,y:y)); $0.addLine(to:CGPoint(x:x,y:y+22)) },with:.color(.green),lineWidth:2)
                for a in 0..<5 { let t = CGFloat(a)/5 * .pi*2; circle(x+cos(t)*6,y+sin(t)*6,4.5,petals[k%petals.count]) }
                circle(x,y,3.5,.yellow)
            }
            circle(60,60,30,.yellow)
            fill(Path(ellipseIn:CGRect(x:170,y:40,width:70,height:24)),.white); fill(Path(ellipseIn:CGRect(x:190,y:28,width:40,height:30)),.white)
        default: // Space
            gradient(full,Color(red:0.03,green:0.02,blue:0.12),Color(red:0.12,green:0.05,blue:0.25))
            for k in 0..<40 { circle(CGFloat((k*73)%300),CGFloat((k*131)%300),k%5 == 0 ? 2 : 1,.white.opacity(0.85)) }
            circle(110,170,70,Color(red:0.95,green:0.55,blue:0.3))
            c.stroke(Path(ellipseIn:CGRect(x:20,y:150,width:180,height:40)),with:.color(Color(red:1,green:0.85,blue:0.6)),lineWidth:6)
            circle(85,150,12,Color(red:0.8,green:0.4,blue:0.2)); circle(130,195,8,Color(red:0.8,green:0.4,blue:0.2))
            circle(240,70,22,Color(red:0.6,green:0.8,blue:1)); circle(234,64,6,.white.opacity(0.6))
            var rocket = Path(); rocket.move(to:CGPoint(x:240,y:220)); rocket.addLine(to:CGPoint(x:255,y:250)); rocket.addLine(to:CGPoint(x:225,y:250)); rocket.closeSubpath(); fill(rocket,.white)
            fill(Path(ellipseIn:CGRect(x:233,y:250,width:14,height:20)),.orange)
        }
        // Corner ticks: one per tile region, always at the region's top-left.
        let n = engine.size, step = 300/CGFloat(n)
        for r in 0..<n { for col in 0..<n {
            let x = CGFloat(col)*step+step*0.1, y = CGFloat(r)*step+step*0.1, len = step*0.18
            var tick = Path(); tick.move(to:CGPoint(x:x,y:y+len)); tick.addLine(to:CGPoint(x:x,y:y)); tick.addLine(to:CGPoint(x:x+len,y:y))
            c.stroke(tick,with:.color(.white.opacity(0.75)),style:StrokeStyle(lineWidth:max(2,step*0.035),lineCap:.round,lineJoin:.round))
        } }
    }
}
