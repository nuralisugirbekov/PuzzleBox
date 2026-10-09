import SwiftUI

struct VisualView:View {
    @State private var engine:VisualEngine
    @State private var dragOrigin:CGPoint?
    init(mode:VisualMode) { _engine = State(initialValue:VisualEngine(mode:mode)) }
    private let pieceColors:[Color] = [.cyan,.pink,.orange,.green,.purple,.yellow,.mint]
    var body:some View {
        GameContainerView(gameID:engine.mode.id,engine:engine,centersContent:true,nextLevel:engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing:12) {
                Menu {
                    ForEach(0..<engine.levelCount,id: \.self) { level in
                        Button(L10n.format("Level %d",level+1)) { engine.loadLevel(level) }
                    }
                } label: {
                    Label(L10n.format("Level %d",engine.levelIndex+1),systemImage:"square.grid.2x2")
                }

                HStack { Text(L10n.format("%d moves",engine.moves)); Spacer(); if engine.mode == .spotDifference { Text("\(engine.marks.count) / \(engine.targets.count)") } }.font(.subheadline.monospacedDigit()).foregroundStyle(GameTheme.accent)
                GeometryReader { geometry in
                    Canvas { context,size in context.scaleBy(x:size.width/320,y:size.height/460); draw(&context) }
                        .background(GameTheme.arena, in: RoundedRectangle(cornerRadius: 24))
                    .environment(\.colorScheme, .dark).clipShape(RoundedRectangle(cornerRadius:24))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { v in
                                if engine.mode == .tangram {
                                    if dragOrigin == nil { dragOrigin = engine.piecePosition }
                                    if let origin = dragOrigin { engine.movePiece(CGPoint(x:origin.x+v.translation.width/geometry.size.width*320,y:origin.y+v.translation.height/geometry.size.height*460)) }
                                }
                            }
                            .onEnded { v in
                                if engine.mode == .tangram { engine.dropPiece(); dragOrigin = nil }
                                else { interact(CGPoint(x:v.location.x/geometry.size.width*320,y:v.location.y/geometry.size.height*460)) }
                            })
                }.aspectRatio(320.0/460,contentMode:.fit).frame(maxWidth:380,maxHeight:460)
                if engine.mode == .tangram {
                    HStack(spacing:5) {
                        ForEach(0..<7,id:\.self) { i in
                            Button { engine.selectPiece(i) } label: {
                                Text(engine.marks.contains(i) ? "✓" : String(i+1)).font(.subheadline.bold()).frame(width:28,height:34)
                                    .background(pieceColors[i].opacity(engine.selected == i ? 0.8 : 0.25),in:RoundedRectangle(cornerRadius:6))
                            }.disabled(engine.marks.contains(i))
                        }
                        Button { engine.rotatePiece() } label: { Image(systemName:"rotate.right").frame(width:32,height:34) }.accessibilityLabel(L10n.text("Rotate"))
                    }.foregroundStyle(GameTheme.ink)
                }
                if engine.mode == .pixelPuzzle {
                    HStack {
                        ForEach(0...4,id:\.self) { i in
                            Button { engine.color(i) } label: {
                                Circle().fill(VisualEngine.palette[i]).frame(width:40,height:40)
                                    .overlay { if engine.paint == i { Image(systemName:"checkmark").foregroundStyle(i == 0 ? GameTheme.ink : .white) } }
                            }
                        }
                    }
                }
                if !engine.feedback.isEmpty { Text(L10n.text(engine.feedback)).font(.caption).foregroundStyle(.orange) }
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .id(engine.levelIndex)
    }
    private func index(_ p:CGPoint,x:CGFloat,y:CGFloat,cell:CGFloat,n:Int) -> Int? {
        let dx = p.x-x,dy = p.y-y
        guard dx >= 0,dy >= 0,dx < CGFloat(n)*cell,dy < CGFloat(n)*cell else { return nil }
        return Int(dy/cell)*n+Int(dx/cell)
    }
    private func interact(_ p:CGPoint) {
        switch engine.mode {
        case .spotDifference: if let i = index(p,x:74,y:250,cell:43,n:4) { engine.tap(i) }
        case .hiddenObject: if let i = index(p,x:4,y:100,cell:52,n:6) { engine.tap(i) }
        case .rotatePuzzle: if let i = index(p,x:25,y:150,cell:90,n:3) { engine.tap(i) }
        case .symmetry: if let i = index(p,x:25,y:75,cell:45,n:6) { engine.tap(i) }
        case .pixelPuzzle: if let i = index(p,x:40,y:165,cell:48,n:5) { engine.tap(i) }
        case .shadowMatch,.patternMatch,.foldIt:
            for i in 0..<4 where optionRect(i).contains(p) { engine.tap(i); break }
        case .matchstick:
            let segments = matchSegments()
            let candidates = segments.indices.filter { engine.selectedMatch != nil || engine.cells[$0] == 1 }
            if let i = candidates.min(by: { distance(p,segments[$0]) < distance(p,segments[$1]) }),distance(p,segments[i]) < 13 { engine.tap(i) }
        case .tangram: break
        }
    }
    private func optionRect(_ i:Int) -> CGRect { CGRect(x:i%2 == 0 ? 25 : 175,y:i/2 == 0 ? 180 : 320,width:120,height:120) }
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
        func icon(_ id:Int,_ rect:CGRect,_ color:Color = .cyan) {
            var image = context.resolve(Image(systemName:AttentionEngine.symbols[id%AttentionEngine.symbols.count])); image.shading = .color(color); context.draw(image,in:rect)
        }
        func box(_ rect:CGRect,_ color:Color) { context.fill(Path(roundedRect:rect,cornerRadius:6),with:.color(color)) }
        func line(_ a:CGPoint,_ b:CGPoint,_ color:Color,_ width:CGFloat = 2) {
            var path = Path(); path.move(to:a); path.addLine(to:b); context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
        }
        func grid(_ values:[Int],n:Int,origin:CGPoint,cell:CGFloat,pixels:Bool = false) {
            for i in values.indices {
                let rect = CGRect(x:origin.x+CGFloat(i%n)*cell+1,y:origin.y+CGFloat(i/n)*cell+1,width:cell-2,height:cell-2)
                box(rect,pixels ? VisualEngine.palette[values[i]] : (values[i] == 1 ? .cyan : GameTheme.surfaceHigh))
            }
        }
        switch engine.mode {
        case .spotDifference:
            for (values,y) in [(engine.reference,CGFloat(20)),(engine.cells,CGFloat(250))] {
                for i in values.indices {
                    let rect = CGRect(x:74+CGFloat(i%4)*43,y:y+CGFloat(i/4)*43,width:43,height:43)
                    icon(values[i],rect.insetBy(dx:8,dy:8))
                    if y == 250 && engine.marks.contains(i) { context.stroke(Path(roundedRect:rect.insetBy(dx:1,dy:1),cornerRadius:5),with:.color(GameTheme.accent),lineWidth:2) }
                }
            }
            line(CGPoint(x:30,y:225),CGPoint(x:290,y:225),GameTheme.stroke)
        case .hiddenObject:
            icon(engine.reference[0],CGRect(x:140,y:20,width:40,height:40),GameTheme.accent)
            for i in engine.cells.indices { icon(engine.cells[i],CGRect(x:12+CGFloat(i%6)*52,y:108+CGFloat(i/6)*52,width:35,height:35),pieceColors[i%pieceColors.count]) }
        case .shadowMatch:
            shape(engine.reference[0],rect:CGRect(x:110,y:25,width:100,height:115),color:.cyan,context:&context)
            for i in engine.options.indices { let rect = optionRect(i); box(rect,.white.opacity(0.9)); shape(engine.options[i],rect:rect.insetBy(dx:17,dy:17),color:.black,context:&context) }
        case .rotatePuzzle:
            picture(rect:CGRect(x:110,y:15,width:100,height:100),context:&context)
            for i in engine.cells.indices {
                let rect = CGRect(x:25+CGFloat(i%3)*90,y:150+CGFloat(i/3)*90,width:90,height:90)
                var tile = context; tile.clip(to:Path(rect.insetBy(dx:1,dy:1)))
                tile.translateBy(x:rect.midX,y:rect.midY); tile.rotate(by:.degrees(Double(engine.cells[i]*90))); tile.translateBy(x:-rect.midX,y:-rect.midY)
                picture(rect:CGRect(x:25,y:150,width:270,height:270),context:&tile)
            }
        case .symmetry:
            grid(engine.cells,n:6,origin:CGPoint(x:25,y:75),cell:45)
            line(CGPoint(x:160,y:65),CGPoint(x:160,y:355),GameTheme.accent,3)
        case .patternMatch:
            for i in engine.reference.indices { icon(engine.reference[i],CGRect(x:30+CGFloat(i%4)*70,y:30+CGFloat(i/4)*55,width:30,height:30)) }
            context.draw(Text("?").font(.title.bold()).foregroundStyle(GameTheme.accent),at:CGPoint(x:160,y:145))
            for i in engine.options.indices { let rect = optionRect(i); box(rect,GameTheme.surfaceHigh); icon(engine.options[i],rect.insetBy(dx:38,dy:38)) }
        case .tangram:
            for piece in 0..<7 {
                var guide = Path()
                for (i,q) in engine.targetPoints(piece).enumerated() {
                    if i == 0 { guide.move(to:q) } else { guide.addLine(to:q) }
                }
                guide.closeSubpath()
                context.fill(guide,with:.color(.white.opacity(0.13)))
                context.stroke(guide,with:.color(.white.opacity(0.25)),lineWidth:1)
            }
            for i in engine.marks.sorted() { drawPiece(i,at:engine.targetCenter(i),turn:engine.targetTurn,context:&context) }
            if !engine.marks.contains(engine.selected) { drawPiece(engine.selected,at:engine.piecePosition,turn:engine.turns[engine.selected],context:&context) }
        case .pixelPuzzle:
            grid(engine.reference,n:5,origin:CGPoint(x:110,y:15),cell:20,pixels:true)
            grid(engine.cells,n:5,origin:CGPoint(x:40,y:165),cell:48,pixels:true)
        case .foldIt:
            for r in 0..<4 { for c in 0..<4 {
                let active = (engine.foldAxis == 1 || c >= 2) && (engine.foldAxis == 0 || r >= 2)
                box(CGRect(x:110+CGFloat(c)*25,y:15+CGFloat(r)*25,width:24,height:24),active ? .cyan : GameTheme.surfaceHigh)
            } }
            let hole = CGPoint(x:122.5+CGFloat(engine.hole%4)*25,y:27.5+CGFloat(engine.hole/4)*25)
            context.fill(Path(ellipseIn:CGRect(x:hole.x-5,y:hole.y-5,width:10,height:10)),with:.color(.black))
            context.draw(Text(engine.foldAxis == 0 ? "→" : engine.foldAxis == 1 ? "↓" : "→ ↓").font(.title).foregroundStyle(GameTheme.accent),at:CGPoint(x:160,y:140))
            for i in engine.patterns.indices {
                let rect = optionRect(i); box(rect,.white.opacity(0.9))
                for j in 0..<16 where engine.patterns[i][j] == 1 {
                    let p = CGPoint(x:rect.minX+(CGFloat(j%4)+0.5)*30,y:rect.minY+(CGFloat(j/4)+0.5)*30)
                    context.fill(Path(ellipseIn:CGRect(x:p.x-5,y:p.y-5,width:10,height:10)),with:.color(.black))
                }
            }
        case .matchstick:
            for (i,segment) in matchSegments().enumerated() {
                line(segment.0,segment.1,engine.cells[i] == 1 ? (engine.selectedMatch == i ? GameTheme.accent : .orange) : .white.opacity(engine.selectedMatch == nil ? 0.12 : 0.32),5)
                if engine.cells[i] == 1 { context.fill(Path(ellipseIn:CGRect(x:segment.0.x-3,y:segment.0.y-3,width:6,height:6)),with:.color(.red)) }
            }
            line(CGPoint(x:197,y:204),CGPoint(x:229,y:204),.white,4)
            line(CGPoint(x:197,y:223),CGPoint(x:229,y:223),.white,4)
        }
    }
    private func drawPiece(_ index:Int,at p:CGPoint,turn:Int,context:inout GraphicsContext) {
        let center = VisualEngine.centroid(index),angle = CGFloat(turn)*CGFloat.pi/2
        var path = Path()
        for (i,point) in VisualEngine.pieces[index].enumerated() {
            let x = (point.x-center.x)*engine.pieceScale,y = (point.y-center.y)*engine.pieceScale
            let q = CGPoint(x:p.x+x*cos(angle)-y*sin(angle),y:p.y+x*sin(angle)+y*cos(angle))
            if i == 0 { path.move(to:q) } else { path.addLine(to:q) }
        }
        path.closeSubpath(); context.fill(path,with:.color(pieceColors[index])); context.stroke(path,with:.color(GameTheme.background),lineWidth:2)
    }
    private func shape(_ id:Int,rect:CGRect,color:Color,context:inout GraphicsContext) {
        let outlines:[[(CGFloat,CGFloat)]] = [
            [(0.1,1),(0.1,0.4),(0.5,0),(0.9,0.4),(0.9,1),(0.6,1),(0.6,0.65),(0.4,0.65),(0.4,1)],
            [(0.5,0),(0.7,0.3),(0.7,0.6),(1,0.9),(0.6,0.85),(0.5,1),(0.4,0.85),(0,0.9),(0.3,0.6),(0.3,0.3)],
            [(0,0.65),(0.4,0.65),(0.4,0.2),(0.65,0),(0.85,0.1),(0.85,0.25),(1,0.3),(0.8,0.4),(0.8,0.8),(0.5,1),(0.15,0.9)],
            [(0.1,0.3),(0.3,0.3),(0.3,0),(0.6,0),(0.6,0.3),(0.9,0.3),(0.9,0.6),(0.65,0.6),(0.65,1),(0.35,1),(0.35,0.6),(0.1,0.6)],
            [(0,0.1),(0.4,0.25),(0.9,0),(1,0.4),(0.7,0.7),(0.5,1),(0.15,0.8),(0.3,0.5)],
            [(0.1,0.1),(0.45,0.1),(0.45,0.45),(0.9,0.45),(0.9,0.8),(0.6,0.8),(0.6,1),(0.1,1)]
        ]
        var path = Path()
        for (i,point) in outlines[id].enumerated() { let p = CGPoint(x:rect.minX+point.0*rect.width,y:rect.minY+point.1*rect.height); if i == 0 { path.move(to:p) } else { path.addLine(to:p) } }
        path.closeSubpath(); context.fill(path,with:.color(color))
    }
    private func picture(rect:CGRect,context:inout GraphicsContext) {
        var c = context; c.translateBy(x:rect.minX,y:rect.minY); c.scaleBy(x:rect.width/300,y:rect.height/300)
        if engine.levelIndex > 0 {
            let backgrounds: [Color] = [.indigo,.teal,.purple,.blue,.orange,.pink]
            c.fill(Path(CGRect(x:0,y:0,width:300,height:300)),with:.color(backgrounds[engine.levelIndex % backgrounds.count].opacity(0.5)))
            for i in 0..<9 {
                let x = CGFloat(i%3)*100, y = CGFloat(i/3)*100
                let symbol = AttentionEngine.symbols[(i+engine.levelIndex*3)%AttentionEngine.symbols.count]
                var image = c.resolve(Image(systemName:symbol)); image.shading = .color(pieceColors[(i+engine.levelIndex)%pieceColors.count])
                c.draw(image,in:CGRect(x:x+22,y:y+15,width:56,height:56))
                var marker = Path(); marker.move(to:CGPoint(x:x+12,y:y+70)); marker.addLine(to:CGPoint(x:x+12,y:y+87)); marker.addLine(to:CGPoint(x:x+40,y:y+87))
                c.stroke(marker,with:.color(.white.opacity(0.7)),lineWidth:3)
            }
            return
        }
        c.fill(Path(CGRect(x:0,y:0,width:300,height:300)),with:.color(.cyan.opacity(0.45)))
        c.fill(Path(ellipseIn:CGRect(x:205,y:22,width:65,height:65)),with:.color(.yellow))
        var mountains = Path(); mountains.move(to:CGPoint(x:0,y:240)); mountains.addLine(to:CGPoint(x:90,y:65)); mountains.addLine(to:CGPoint(x:190,y:240)); mountains.addLine(to:CGPoint(x:235,y:145)); mountains.addLine(to:CGPoint(x:300,y:220)); mountains.addLine(to:CGPoint(x:300,y:300)); mountains.addLine(to:CGPoint(x:0,y:300)); mountains.closeSubpath()
        c.fill(mountains,with:.color(.indigo))
        var river = Path(); river.move(to:CGPoint(x:160,y:170)); river.addCurve(to:CGPoint(x:90,y:300),control1:CGPoint(x:250,y:230),control2:CGPoint(x:55,y:240)); c.stroke(river,with:.color(.mint),lineWidth:23)
        c.fill(Path(CGRect(x:28,y:213,width:43,height:42)),with:.color(.orange))
        var roof = Path(); roof.move(to:CGPoint(x:20,y:214)); roof.addLine(to:CGPoint(x:50,y:189)); roof.addLine(to:CGPoint(x:80,y:214)); roof.closeSubpath(); c.fill(roof,with:.color(.pink))
        // Asymmetric motifs make every tile's orientation visually distinguishable.
        for r in 0..<3 { for col in 0..<3 {
            let x = CGFloat(col * 100 + 18), y = CGFloat(r * 100 + 30)
            var motif = Path(); motif.move(to:CGPoint(x:x,y:y+18))
            motif.addLine(to:CGPoint(x:x+6,y:y)); motif.addLine(to:CGPoint(x:x+20,y:y+9))
            c.stroke(motif,with:.color(r == 0 ? .white : .green),style:StrokeStyle(lineWidth:3,lineCap:.round))
            c.fill(Path(ellipseIn:CGRect(x:x+15,y:y+4,width:8,height:8)),with:.color(r == 0 ? .white : .pink))
        } }
        for (x,y) in [(30,35),(100,15),(5,125),(255,265)] { c.fill(Path(ellipseIn:CGRect(x:CGFloat(x),y:CGFloat(y),width:28,height:12)),with:.color(.white.opacity(0.7))) }
    }
}
