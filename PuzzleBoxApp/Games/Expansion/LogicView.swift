import SwiftUI

struct LogicView: View {
    @State private var engine: LogicEngine
    init(mode: LogicMode) { _engine = State(initialValue: LogicEngine(mode: mode)) }
    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                HStack {
                    Text(L10n.format("%d moves", engine.moves)).font(.subheadline.monospacedDigit())
                    Spacer()
                    Button { engine.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!engine.canUndo)
                        .accessibilityLabel(L10n.text("Undo"))
                    Button(L10n.text("Check solution")) { engine.check() }
                }.foregroundStyle(Theme.neon)
                GeometryReader { geometry in
                    Canvas { context, size in draw(&context, size: size) }
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                        .onTapGesture { point in interact(point, size: geometry.size) }
                }.aspectRatio(1, contentMode: .fit).frame(maxWidth: 420)
                if engine.numeric {
                    HStack(spacing: 4) {
                        ForEach(0...(engine.mode == .kakuro ? 9 : 4), id: \.self) { value in
                            Button { engine.enter(value) } label: {
                                Text(value == 0 ? "×" : String(value)).font(.headline)
                                    .frame(maxWidth: .infinity).frame(height: 40)
                                    .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 7))
                            }.disabled(engine.selected == nil)
                        }
                    }.foregroundStyle(Theme.neon)
                }
                if !engine.feedback.isEmpty { Text(L10n.text(engine.feedback)).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center) }
                if engine.loopMode { Text(L10n.text("Tap between dots to toggle a line.")).font(.caption).foregroundStyle(Theme.neon) }
                Text(L10n.text(engine.mode.hint)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func layout(_ size: CGSize) -> (CGFloat, CGFloat) {
        let margin: CGFloat = engine.mode == .tents ? 30 : 18
        return (margin, (min(size.width, size.height) - 2 * margin) / CGFloat(engine.n))
    }
    private func node(_ index: Int, margin: CGFloat, cell: CGFloat) -> CGPoint {
        let side = engine.nodeSide, offset: CGFloat = engine.mode == .slitherlink ? 0 : 0.5
        return CGPoint(x: margin + (CGFloat(index % side) + offset) * cell, y: margin + (CGFloat(index / side) + offset) * cell)
    }
    private var possibleEdges: [LogicEdge] {
        let n = engine.nodeSide
        return (0..<(n*n)).flatMap { i -> [LogicEdge] in
            var edges: [LogicEdge] = []
            if i % n < n-1 { edges.append(LogicEdge(i,i+1)) }
            if i / n < n-1 { edges.append(LogicEdge(i,i+n)) }
            return edges
        }
    }
    private func interact(_ p: CGPoint, size: CGSize) {
        let (margin, cell) = layout(size)
        if engine.loopMode {
            let nearby = possibleEdges.min { a, b in
                func distance(_ e: LogicEdge) -> CGFloat {
                    let x = node(e.a,margin:margin,cell:cell), y = node(e.b,margin:margin,cell:cell)
                    return hypot(p.x - (x.x+y.x)/2, p.y - (x.y+y.y)/2)
                }
                return distance(a) < distance(b)
            }
            if let edge = nearby {
                let a = node(edge.a,margin:margin,cell:cell), b = node(edge.b,margin:margin,cell:cell)
                if hypot(p.x-(a.x+b.x)/2,p.y-(a.y+b.y)/2) < cell * 0.43 { engine.edge(edge) }
            }
        } else {
            let x = p.x-margin, y = p.y-margin
            guard x >= 0, y >= 0, x < cell*CGFloat(engine.n), y < cell*CGFloat(engine.n) else { return }
            engine.tap(Int(y/cell)*engine.n+Int(x/cell))
        }
    }
    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let (margin, cell) = layout(size), n = engine.n
        func center(_ i: Int) -> CGPoint { CGPoint(x: margin + (CGFloat(i%n)+0.5)*cell,y: margin+(CGFloat(i/n)+0.5)*cell) }
        func label(_ s: String, _ p: CGPoint, _ color: Color = .white, _ font: CGFloat = 20) {
            context.draw(Text(verbatim:s).font(.system(size:font,weight:.semibold)).foregroundStyle(color),at:p)
        }
        func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat = 3) {
            var path = Path(); path.move(to:a); path.addLine(to:b)
            context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:width,lineCap:.round))
        }
        func circle(_ p: CGPoint, _ radius: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn:CGRect(x:p.x-radius,y:p.y-radius,width:2*radius,height:2*radius)),with:.color(color))
        }
        if engine.loopMode {
            for edge in possibleEdges {
                line(node(edge.a,margin:margin,cell:cell),node(edge.b,margin:margin,cell:cell),Theme.textSecondary.opacity(0.15),1)
            }
            for edge in engine.lines {
                line(node(edge.a,margin:margin,cell:cell),node(edge.b,margin:margin,cell:cell),Theme.neon,5)
            }
            for i in 0..<(engine.nodeSide * engine.nodeSide) { circle(node(i,margin:margin,cell:cell),3,Theme.textSecondary) }
            for (i,value) in engine.clues {
                if engine.mode == .slitherlink { label(String(value),center(i)) }
                else {
                    circle(center(i),cell*0.17,.white)
                    if value == 2 { circle(center(i),cell*0.13,.black) }
                }
            }
            return
        }
        if engine.mode == .hashi {
            for (edge,count) in engine.bridges where count > 0 {
                let a = center(edge.a), b = center(edge.b)
                for index in 0..<count {
                    let offset: CGFloat = count == 2 ? (index == 0 ? -3 : 3) : 0
                    let dx: CGFloat = a.x == b.x ? offset : 0, dy: CGFloat = a.y == b.y ? offset : 0
                    line(CGPoint(x:a.x+dx,y:a.y+dy),CGPoint(x:b.x+dx,y:b.y+dy),Theme.neon,3)
                }
            }
            for (i,count) in engine.clues {
                circle(center(i),cell*0.3,engine.selected == i ? Theme.neon : .cyan)
                label(String(count),center(i),.black)
            }
            return
        }
        for i in engine.cells.indices {
            let p = center(i), value = engine.cells[i]
            let inset: CGFloat = engine.mode == .futoshiki ? 9 : 2
            let rect = CGRect(x:p.x-cell/2+inset,y:p.y-cell/2+inset,width:cell-2*inset,height:cell-2*inset)
            var color = Theme.surfaceHigh
            if [.hitori,.nurikabe].contains(engine.mode) && value == 1 { color = .black }
            if engine.mode == .kakuro && !engine.playable.contains(i) { color = Theme.background }
            if engine.mode == .takuzu && value > 0 { color = value == 1 ? .cyan.opacity(0.25) : .pink.opacity(0.25) }
            context.fill(Path(roundedRect:rect,cornerRadius:4),with:.color(color))
            if engine.selected == i { context.stroke(Path(roundedRect:rect,cornerRadius:4),with:.color(Theme.neon),lineWidth:2) }
            switch engine.mode {
            case .kakuro:
                if engine.playable.contains(i) { if value > 0 { label(String(value),p,Theme.neon) } }
                else {
                    for run in engine.runs where run.clue == i {
                        label((run.vertical ? "↓" : "→") + String(run.sum),CGPoint(x:p.x,y:p.y+(run.vertical ? -cell*0.19 : cell*0.19)),.white,min(14,cell*0.25))
                    }
                }
            case .futoshiki: if value > 0 { label(String(value),p,engine.fixed.contains(i) ? .white : Theme.neon) }
            case .hitori:
                label(String(engine.clues[i] ?? 0),p,value == 1 ? .gray.opacity(0.4) : .white)
                if value == 1 { line(CGPoint(x:rect.minX+5,y:rect.minY+5),CGPoint(x:rect.maxX-5,y:rect.maxY-5),.gray,1) }
            case .nurikabe: if let number = engine.clues[i] { label(String(number),p,Theme.neon) }
            case .takuzu:
                if value > 0 { label(String(value-1),p,engine.fixed.contains(i) ? .white : Theme.neon) }
                if engine.fixed.contains(i) { circle(CGPoint(x:rect.maxX-5,y:rect.minY+5),2,.white) }
            case .tents:
                if engine.fixed.contains(i) {
                    var tree = Path(); tree.move(to:CGPoint(x:p.x,y:rect.minY+4)); tree.addLine(to:CGPoint(x:rect.maxX-5,y:rect.maxY-9)); tree.addLine(to:CGPoint(x:rect.minX+5,y:rect.maxY-9)); tree.closeSubpath()
                    context.fill(tree,with:.color(.green)); line(CGPoint(x:p.x,y:p.y),CGPoint(x:p.x,y:rect.maxY-4),.green,3)
                } else if value == 1 {
                    var tent = Path(); tent.move(to:CGPoint(x:p.x,y:rect.minY+5)); tent.addLine(to:CGPoint(x:rect.maxX-5,y:rect.maxY-5)); tent.addLine(to:CGPoint(x:rect.minX+5,y:rect.maxY-5)); tent.closeSubpath()
                    context.fill(tent,with:.color(.orange)); line(CGPoint(x:p.x,y:p.y),CGPoint(x:p.x,y:rect.maxY-5),.black,2)
                }
            default: break
            }
        }
        for inequality in engine.inequalities {
            let a = center(inequality.a), b = center(inequality.b), p = CGPoint(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
            if inequality.a/n == inequality.b/n { label(inequality.less ? "<" : ">",p,.orange,16) }
            else {
                // The point of the chevron always faces the smaller value.
                let sign: CGFloat = inequality.less ? -1 : 1
                line(CGPoint(x:p.x-4,y:p.y-sign*3),CGPoint(x:p.x,y:p.y+sign*3),.orange,2)
                line(CGPoint(x:p.x+4,y:p.y-sign*3),CGPoint(x:p.x,y:p.y+sign*3),.orange,2)
            }
        }
        if engine.mode == .tents {
            for i in 0..<n {
                label(String(engine.rowTotals[i]),CGPoint(x:margin/2,y:center(i*n).y),Theme.neon,15)
                label(String(engine.columnTotals[i]),CGPoint(x:center(i).x,y:margin/2),Theme.neon,15)
            }
        }
    }
}
