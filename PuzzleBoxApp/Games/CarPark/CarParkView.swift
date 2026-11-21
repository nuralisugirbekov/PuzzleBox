import SwiftUI

struct CarParkView: View {
    @State private var engine = CarParkEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let palette = ToyCarPark.palette

    var body: some View {
        GameContainerView(gameID: .unblock, engine: engine,
                          resultSummary: summary,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette,
                         headline: .clock(caption: L10n.text("Bumps"), time: { "\(engine.bumps)" })) {
                ToyIconButton(symbol: "arrow.counterclockwise", label: L10n.text("Restart level"),
                              color: palette.card, ink: palette.ink) {
                    engine.restart()
                }
                .disabled(engine.moves == 0 || engine.cleared)
                .opacity(engine.moves == 0 || engine.cleared ? 0.45 : 1)
            } content: {
                VStack(spacing: 12) {
                    hud
                    CarParkBoard(engine: engine)
                        .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                    Text(L10n.text(engine.notice.isEmpty ? ToyCarPark.hint : engine.notice))
                        .font(.system(engine.notice.isEmpty ? .footnote : .subheadline, design: .rounded)
                            .weight(engine.notice.isEmpty ? .regular : .bold))
                        .foregroundStyle(engine.notice.isEmpty ? palette.ink.opacity(0.6) : palette.accent)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 36)
                        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: engine.notice)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
        .id(engine.level)
        .onAppear { engine.active = scenePhase == .active; engine.reduceMotion = reduceMotion }
        .onDisappear { engine.active = false }
        .onChange(of: reduceMotion) { _, value in engine.reduceMotion = value }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(now - last)
                last = now
            }
        }
    }

    private var summary: String {
        let title = L10n.format("Level %d", engine.level)
        guard engine.cleared else { return title }
        return title + "  " + String(repeating: "★", count: engine.stars) + String(repeating: "☆", count: 3 - engine.stars)
    }

    private var hud: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(1...CarParkEngine.levelCount, id: \.self) { level in
                    let best = engine.bestStars[level] ?? 0
                    Button(L10n.format("Level %d", level) + (best > 0 ? "  " + String(repeating: "★", count: best) : "")) {
                        engine.selectLevel(level)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(L10n.format("Level %d", engine.level))
                    Image(systemName: "chevron.down").font(.caption2.weight(.heavy)).opacity(0.6)
                }
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .padding(.bottom, 3)
                .background { ToyBlock(color: palette.card, shape: Capsule(), lip: 3) }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
            ToyChip(color: palette.card) {
                Label { Text(verbatim: "\(engine.vehiclesLeft)/\(engine.vehicleCount)").monospacedDigit() }
                    icon: { Image(systemName: "car.fill").foregroundStyle(palette.accent) }
                    .foregroundStyle(palette.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.format("Vehicles left: %d", engine.vehiclesLeft))
            ToyChip(color: palette.card) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: "star.fill")
                            .foregroundStyle(i < engine.stars ? ToyCarPark.starGold : palette.ink.opacity(0.18))
                    }
                }
            }
            .accessibilityElement()
            .accessibilityLabel(L10n.format("%d stars", engine.stars))
        }
    }
}

// MARK: - Board

/// Where the lot sits on the board, in points.
struct CarParkLayout {
    let unit: CGFloat
    let origin: CGPoint

    init(size: CGSize, columns: Int, rows: Int) {
        let m = CarParkRoad.margin
        let w = CGFloat(columns) + 2 * m, h = CGFloat(rows) + 2 * m
        unit = min(size.width / w, size.height / h)
        origin = CGPoint(x: (size.width - CGFloat(columns) * unit) / 2, y: (size.height - CGFloat(rows) * unit) / 2)
    }

    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * unit, y: origin.y + p.y * unit) }
    func rect(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + r.minX * unit, y: origin.y + r.minY * unit, width: r.width * unit, height: r.height * unit)
    }
    func cell(at p: CGPoint) -> GridPos {
        GridPos(r: Int(floor((p.y - origin.y) / unit)), c: Int(floor((p.x - origin.x) / unit)))
    }
}

/// The lot seen from above, with the road around it. Swipe a vehicle along
/// its length to drive it; tap to drive it nose first.
struct CarParkBoard: View {
    let engine: CarParkEngine
    @State private var grabbed: Int?
    @State private var handled = false

    var body: some View {
        let lot = engine.lot
        let m = CarParkRoad.margin
        GeometryReader { geometry in
            Canvas { context, size in
                let layout = CarParkLayout(size: size, columns: lot.columns, rows: lot.rows)
                CarParkPainter(engine: engine, layout: layout, size: size).draw(&context)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let layout = CarParkLayout(size: geometry.size, columns: lot.columns, rows: lot.rows)
                        if grabbed == nil, !handled {
                            grabbed = engine.vehicle(at: layout.cell(at: value.startLocation))?.id ?? -1
                        }
                        guard let id = grabbed, id >= 0, !handled,
                              let vehicle = engine.lot.vehicles.first(where: { $0.id == id }) else { return }
                        let along = vehicle.horizontal ? value.translation.width : value.translation.height
                        let across = vehicle.horizontal ? value.translation.height : value.translation.width
                        if abs(along) > 14, abs(along) > abs(across) * 0.6 {
                            handled = true
                            engine.drive(id, dir: along > 0 ? 1 : -1)
                        }
                    }
                    .onEnded { value in
                        // A tap drives the vehicle nose first.
                        if !handled, let id = grabbed, id >= 0, hypot(value.translation.width, value.translation.height) < 10,
                           let vehicle = engine.lot.vehicles.first(where: { $0.id == id }) {
                            engine.drive(id, dir: vehicle.facesForward ? 1 : -1)
                        }
                        grabbed = nil
                        handled = false
                    }
            )
        }
        .aspectRatio((CGFloat(lot.columns) + 2 * m) / (CGFloat(lot.rows) + 2 * m), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Vehicles left: %d", engine.vehiclesLeft))
    }
}

// MARK: - Painter

private struct CarParkPainter {
    let engine: CarParkEngine
    let layout: CarParkLayout
    let size: CGSize

    private var lot: CarParkLot { engine.lot }
    private var u: CGFloat { layout.unit }
    private var time: Double { engine.time }

    func draw(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ToyCarPark.pavement))
        drawRoads(&context)
        drawLot(&context)
        drawEdges(&context)
        for prop in lot.props { drawProp(&context, prop) }
        for vehicle in lot.vehicles {
            let (center, angle) = placed(vehicle)
            drawVehicle(&context, vehicle, at: center, angle: angle)
        }
        for car in engine.leaving {
            let (p, angle) = CarParkGeometry.place(car)
            drawVehicle(&context, car.vehicle, at: layout.point(p), angle: angle)
            if car.waiting { drawHonk(&context, at: layout.point(p)) }
        }
        for walker in engine.walkers { drawWalker(&context, walker) }
        for puff in engine.puffs where time >= puff.time { drawPuff(&context, puff) }
    }

    // MARK: Ground

    private func drawRoads(_ context: inout GraphicsContext) {
        let cols = CGFloat(lot.columns), rows = CGFloat(lot.rows)
        let k = CarParkRoad.kerb, w = CarParkRoad.width, lane = CarParkRoad.lane
        let far: CGFloat = 40
        let strips = [CGRect(x: -far, y: -k - w, width: 2 * far, height: w),
                      CGRect(x: -far, y: rows + k, width: 2 * far, height: w),
                      CGRect(x: -k - w, y: -far, width: w, height: 2 * far),
                      CGRect(x: cols + k, y: -far, width: w, height: 2 * far)]
        for strip in strips { context.fill(Path(layout.rect(strip)), with: .color(ToyCarPark.asphalt)) }
        // Dashed middle lines, kept out of the crossings.
        let dash = StrokeStyle(lineWidth: max(1, u * 0.05), lineCap: .round, dash: [u * 0.22, u * 0.2])
        var lines = Path()
        for y in [-lane, rows + lane] {
            lines.move(to: layout.point(CGPoint(x: -k, y: y))); lines.addLine(to: layout.point(CGPoint(x: cols + k, y: y)))
        }
        for x in [-lane, cols + lane] {
            lines.move(to: layout.point(CGPoint(x: x, y: -k))); lines.addLine(to: layout.point(CGPoint(x: x, y: rows + k)))
        }
        context.stroke(lines, with: .color(ToyCarPark.roadLine.opacity(0.7)), style: dash)
    }

    private func drawLot(_ context: inout GraphicsContext) {
        let k = CarParkRoad.kerb
        let cols = CGFloat(lot.columns), rows = CGFloat(lot.rows)
        let kerb = layout.rect(CGRect(x: -k, y: -k, width: cols + 2 * k, height: rows + 2 * k))
        context.fill(Path(roundedRect: kerb.offsetBy(dx: 0, dy: u * 0.05), cornerRadius: u * 0.22),
                     with: .color(ToyCarPark.kerb.toyShade(-0.18)))
        context.fill(Path(roundedRect: kerb, cornerRadius: u * 0.22), with: .color(ToyCarPark.kerb))
        let surface = layout.rect(CGRect(x: 0, y: 0, width: cols, height: rows))
        context.fill(Path(roundedRect: surface, cornerRadius: u * 0.12), with: .color(ToyCarPark.lot))
        // Bay markings: a short line between neighbouring cells.
        var marks = Path()
        for r in 0..<lot.rows {
            for c in 0..<lot.columns {
                let x = CGFloat(c), y = CGFloat(r)
                if c > 0 {
                    marks.move(to: layout.point(CGPoint(x: x, y: y + 0.22)))
                    marks.addLine(to: layout.point(CGPoint(x: x, y: y + 0.78)))
                }
                if r > 0 {
                    marks.move(to: layout.point(CGPoint(x: x + 0.22, y: y)))
                    marks.addLine(to: layout.point(CGPoint(x: x + 0.78, y: y)))
                }
            }
        }
        context.stroke(marks, with: .color(ToyCarPark.roadLine.opacity(0.35)),
                       style: StrokeStyle(lineWidth: max(1, u * 0.04), lineCap: .round))
    }

    /// Fences on closed stretches, barrier arms on the gates through them.
    private func drawEdges(_ context: inout GraphicsContext) {
        let k = CarParkRoad.kerb
        for edge in lot.fence {
            let (a, b) = segment(edge, inset: k / 2)
            var rail = Path(); rail.move(to: a); rail.addLine(to: b)
            context.stroke(rail, with: .color(ToyCarPark.fence.toyShade(-0.2)),
                           style: StrokeStyle(lineWidth: u * 0.14, lineCap: .round))
            context.stroke(rail.offsetBy(dx: 0, dy: -u * 0.03), with: .color(ToyCarPark.fence),
                           style: StrokeStyle(lineWidth: u * 0.1, lineCap: .round))
            for p in [a, b] {
                context.fill(Path(ellipseIn: CGRect(x: p.x - u * 0.09, y: p.y - u * 0.11, width: u * 0.18, height: u * 0.18)),
                             with: .color(ToyCarPark.fence.toyShade(-0.28)))
            }
        }
        for gate in lot.gates {
            let (a, b) = segment(gate, inset: k / 2)
            let open = engine.leaving.contains { $0.gate == gate && $0.travelled < ($0.lengths.first ?? 0) + 0.8 }
            let end = open ? CGPoint(x: a.x + (b.x - a.x) * 0.22, y: a.y + (b.y - a.y) * 0.22) : b
            var arm = Path(); arm.move(to: a); arm.addLine(to: end)
            context.stroke(arm, with: .color(.white), style: StrokeStyle(lineWidth: u * 0.09, lineCap: .round))
            context.stroke(arm, with: .color(ToyCarPark.barrier),
                           style: StrokeStyle(lineWidth: u * 0.09, lineCap: .butt, dash: [u * 0.14, u * 0.14]))
            context.fill(Path(ellipseIn: CGRect(x: a.x - u * 0.12, y: a.y - u * 0.12, width: u * 0.24, height: u * 0.24)),
                         with: .color(ToyCarPark.barrier.toyShade(-0.15)))
        }
    }

    private func segment(_ edge: CarParkEdge, inset: CGFloat) -> (CGPoint, CGPoint) {
        let i = CGFloat(edge.index), cols = CGFloat(lot.columns), rows = CGFloat(lot.rows)
        switch edge.side {
        case .top: return (layout.point(CGPoint(x: i, y: -inset)), layout.point(CGPoint(x: i + 1, y: -inset)))
        case .bottom: return (layout.point(CGPoint(x: i, y: rows + inset)), layout.point(CGPoint(x: i + 1, y: rows + inset)))
        case .left: return (layout.point(CGPoint(x: -inset, y: i)), layout.point(CGPoint(x: -inset, y: i + 1)))
        case .right: return (layout.point(CGPoint(x: cols + inset, y: i)), layout.point(CGPoint(x: cols + inset, y: i + 1)))
        }
    }

    // MARK: Props

    private func drawProp(_ context: inout GraphicsContext, _ prop: CarParkProp) {
        let c = layout.point(CGPoint(x: CGFloat(prop.cell.c) + 0.5, y: CGFloat(prop.cell.r) + 0.5))
        func circle(_ p: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }
        let shadow = CGPoint(x: c.x + u * 0.04, y: c.y + u * 0.08)
        switch prop.kind {
        case .cone:
            context.fill(circle(shadow, u * 0.24), with: .color(.black.opacity(0.18)))
            let base = CGRect(x: c.x - u * 0.24, y: c.y - u * 0.24, width: u * 0.48, height: u * 0.48)
            context.fill(Path(roundedRect: base, cornerRadius: u * 0.08), with: .color(ToyCarPark.cone.toyShade(-0.2)))
            context.fill(circle(c, u * 0.19), with: .color(ToyCarPark.cone))
            context.stroke(circle(c, u * 0.12), with: .color(.white), lineWidth: u * 0.05)
            context.fill(circle(c, u * 0.05), with: .color(ToyCarPark.cone.toyShade(0.2)))
        case .flowers:
            let bed = CGRect(x: c.x - u * 0.4, y: c.y - u * 0.4, width: u * 0.8, height: u * 0.8)
            context.fill(Path(roundedRect: bed.offsetBy(dx: 0, dy: u * 0.06), cornerRadius: u * 0.16), with: .color(ToyCarPark.planter.toyShade(-0.2)))
            context.fill(Path(roundedRect: bed, cornerRadius: u * 0.16), with: .color(ToyCarPark.planter))
            context.fill(Path(roundedRect: bed.insetBy(dx: u * 0.08, dy: u * 0.08), cornerRadius: u * 0.1), with: .color(ToyCarPark.leaf))
            let blooms: [(CGFloat, CGFloat, Color)] = [(-0.16, -0.14, ToyCarPark.bloomA), (0.14, -0.1, ToyCarPark.bloomB),
                                                       (-0.08, 0.15, ToyCarPark.bloomB), (0.16, 0.16, ToyCarPark.bloomA), (0.0, 0.0, .white)]
            for (dx, dy, color) in blooms { context.fill(circle(CGPoint(x: c.x + dx * u, y: c.y + dy * u), u * 0.07), with: .color(color)) }
        case .booth:
            let body = CGRect(x: c.x - u * 0.36, y: c.y - u * 0.36, width: u * 0.72, height: u * 0.72)
            context.fill(Path(roundedRect: body.offsetBy(dx: u * 0.04, dy: u * 0.08), cornerRadius: u * 0.1), with: .color(.black.opacity(0.18)))
            context.fill(Path(roundedRect: body.offsetBy(dx: 0, dy: u * 0.05), cornerRadius: u * 0.1), with: .color(ToyCarPark.booth.toyShade(-0.22)))
            context.fill(Path(roundedRect: body, cornerRadius: u * 0.1), with: .color(ToyCarPark.booth))
            let roof = body.insetBy(dx: u * 0.08, dy: u * 0.08)
            context.fill(Path(roundedRect: roof, cornerRadius: u * 0.06), with: .color(ToyCarPark.barrier))
            context.fill(Path(roundedRect: CGRect(x: roof.minX, y: roof.midY - u * 0.03, width: roof.width, height: u * 0.06), cornerRadius: u * 0.03),
                         with: .color(ToyCarPark.barrier.toyShade(-0.2)))
        case .tree:
            context.fill(circle(shadow, u * 0.38), with: .color(.black.opacity(0.18)))
            context.fill(circle(c, u * 0.38), with: .color(ToyCarPark.leaf.toyShade(-0.18)))
            context.fill(circle(CGPoint(x: c.x - u * 0.06, y: c.y - u * 0.06), u * 0.3), with: .color(ToyCarPark.leaf))
            context.fill(circle(CGPoint(x: c.x - u * 0.12, y: c.y - u * 0.14), u * 0.12), with: .color(ToyCarPark.leaf.toyShade(0.18)))
        }
    }

    // MARK: Vehicles

    /// Screen centre and nose angle of a parked vehicle, with its slide and shakes.
    private func placed(_ v: CarParkVehicle) -> (CGPoint, Double) {
        var p = v.center
        if let slide = engine.slides[v.id] {
            let t = slide.duration > 0 ? min(1, max(0, (time - slide.start) / slide.duration)) : 1
            let eased = 1 - (1 - t) * (1 - t)
            p.x += slide.from.dx * CGFloat(1 - eased)
            p.y += slide.from.dy * CGFloat(1 - eased)
            let after = time - slide.start - slide.duration
            if slide.bumps, after >= 0, after < 0.3 {
                let shake = CGFloat(sin(after * 60) * (0.3 - after) * 0.3)
                p.x -= slide.heading.dx * shake
                p.y -= slide.heading.dy * shake
            }
        }
        var angle = CarParkGeometry.noseAngle(v)
        if let at = engine.jolts[v.id], time >= at, time < at + 0.4 {
            angle += sin((time - at) * 45) * (0.4 - (time - at)) * 0.25
        }
        return (layout.point(p), angle)
    }

    private func drawVehicle(_ context: inout GraphicsContext, _ v: CarParkVehicle, at center: CGPoint, angle: Double) {
        let length = (CGFloat(v.length) - 0.16) * u
        let width = (v.kind == .bus || v.kind == .truck ? 0.78 : 0.72) * u
        let body = CGRect(x: -length / 2, y: -width / 2, width: length, height: width)
        let radius = width * (v.kind == .bus ? 0.22 : 0.32)
        let color = v.kind == .taxi ? ToyCarPark.taxi : ToyCarPark.paint[v.color % ToyCarPark.paint.count]

        func frame(_ offset: CGVector) -> GraphicsContext {
            var c = context
            c.translateBy(x: center.x + offset.dx, y: center.y + offset.dy)
            c.rotate(by: .radians(angle))
            return c
        }
        frame(CGVector(dx: u * 0.04, dy: u * 0.1)).fill(Path(roundedRect: body, cornerRadius: radius), with: .color(.black.opacity(0.2)))
        frame(CGVector(dx: 0, dy: u * 0.05)).fill(Path(roundedRect: body, cornerRadius: radius), with: .color(color.toyShade(-0.22)))
        var c = frame(.zero)
        c.fill(Path(roundedRect: body, cornerRadius: radius), with: .color(color))

        let glass = ToyCarPark.glass
        let half = length / 2, w = width / 2
        func box(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x0, y: -y, width: x1 - x0, height: 2 * y), cornerRadius: r)
        }
        switch v.kind {
        case .car, .taxi:
            c.fill(box(half * 0.12, half * 0.5, w * 0.72, u * 0.06), with: .color(glass))
            c.fill(box(-half * 0.72, -half * 0.46, w * 0.66, u * 0.05), with: .color(glass))
            c.fill(box(-half * 0.42, half * 0.08, w * 0.66, u * 0.08), with: .color(color.toyShade(0.14)))
            if v.kind == .taxi {
                c.fill(box(-half * 0.22, -half * 0.04, w * 0.34, u * 0.03), with: .color(.white))
                c.fill(box(-half * 0.17, -half * 0.09, w * 0.14, u * 0.01), with: .color(ToyCarPark.ink))
            }
        case .van:
            c.fill(box(half * 0.34, half * 0.66, w * 0.74, u * 0.06), with: .color(glass))
            c.fill(box(-half * 0.86, half * 0.28, w * 0.72, u * 0.08), with: .color(color.toyShade(0.14)))
        case .truck:
            // A cab up front and a cargo box behind it.
            c.fill(box(half * 0.5, half * 0.78, w * 0.74, u * 0.05), with: .color(glass))
            let cargo = CGRect(x: -half + u * 0.02, y: -w + u * 0.02, width: length * 0.68, height: width - u * 0.04)
            c.fill(Path(roundedRect: cargo, cornerRadius: radius * 0.6), with: .color(ToyCarPark.cargo.toyShade(-0.12)))
            c.fill(Path(roundedRect: cargo.insetBy(dx: u * 0.04, dy: u * 0.04), cornerRadius: radius * 0.5), with: .color(ToyCarPark.cargo))
            var ribs = Path()
            for i in 1..<5 {
                let x = cargo.minX + cargo.width * CGFloat(i) / 5
                ribs.move(to: CGPoint(x: x, y: cargo.minY + u * 0.1)); ribs.addLine(to: CGPoint(x: x, y: cargo.maxY - u * 0.1))
            }
            c.stroke(ribs, with: .color(ToyCarPark.cargo.toyShade(-0.16)), lineWidth: max(1, u * 0.03))
        case .bus:
            c.fill(box(half * 0.82, half * 0.94, w * 0.76, u * 0.04), with: .color(glass))
            c.fill(box(-half * 0.9, half * 0.76, w * 0.5, u * 0.08), with: .color(color.toyShade(0.16)))
            for i in 0..<6 {
                let x = -half * 0.86 + CGFloat(i) * length * 0.135
                for side: CGFloat in [-1, 1] {
                    c.fill(Path(roundedRect: CGRect(x: x, y: side < 0 ? -w + u * 0.05 : w - u * 0.13, width: length * 0.1, height: u * 0.08),
                                cornerRadius: u * 0.03), with: .color(glass))
                }
            }
        }
        // Headlights at the nose, tail lights behind.
        for side: CGFloat in [-1, 1] {
            c.fill(Path(ellipseIn: CGRect(x: half - u * 0.1, y: side * w * 0.62 - u * 0.05, width: u * 0.08, height: u * 0.1)),
                   with: .color(ToyCarPark.headlight))
            c.fill(Path(ellipseIn: CGRect(x: -half + u * 0.02, y: side * w * 0.62 - u * 0.045, width: u * 0.06, height: u * 0.09)),
                   with: .color(ToyCarPark.taillight))
        }
    }

    private func drawHonk(_ context: inout GraphicsContext, at p: CGPoint) {
        let bubble = CGRect(x: p.x + u * 0.2, y: p.y - u * 0.75, width: u * 0.42, height: u * 0.42)
        context.fill(Path(ellipseIn: bubble.offsetBy(dx: 0, dy: u * 0.03)), with: .color(ToyCarPark.ink.opacity(0.25)))
        context.fill(Path(ellipseIn: bubble), with: .color(.white))
        context.draw(Text("!").font(.system(size: u * 0.32, weight: .black, design: .rounded)).foregroundStyle(ToyCarPark.barrier),
                     at: CGPoint(x: bubble.midX, y: bubble.midY))
    }

    private func drawWalker(_ context: inout GraphicsContext, _ walker: CarParkWalker) {
        let p = layout.point(engine.position(of: walker))
        let step = CGFloat(sin(time * 10 + Double(walker.color)))
        let r = u * 0.14
        let horizontal = walker.side == .top || walker.side == .bottom
        context.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.1 + u * 0.03, y: p.y - r + u * 0.07, width: r * 2.2, height: r * 2.2)),
                     with: .color(.black.opacity(0.18)))
        // Feet stepping along the walk.
        for side: CGFloat in [-1, 1] {
            let swing = side * step * u * 0.07
            let foot = horizontal ? CGPoint(x: p.x + swing, y: p.y + side * r * 0.5) : CGPoint(x: p.x + side * r * 0.5, y: p.y + swing)
            context.fill(Path(ellipseIn: CGRect(x: foot.x - u * 0.05, y: foot.y - u * 0.05, width: u * 0.1, height: u * 0.1)),
                         with: .color(ToyCarPark.ink.opacity(0.7)))
        }
        let shirt = ToyCarPark.paint[(walker.color + 3) % ToyCarPark.paint.count]
        context.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.15, y: p.y - r, width: r * 2.3, height: r * 2)), with: .color(shirt))
        context.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.62, y: p.y - r * 0.62, width: r * 1.24, height: r * 1.24)),
                     with: .color(ToyCarPark.skin))
    }

    private func drawPuff(_ context: inout GraphicsContext, _ puff: CarParkPuff) {
        let age = time - puff.time
        let p = layout.point(puff.at)
        let fade = max(0, 1 - age / 0.6)
        for i in 0..<7 {
            let a = Double(i) / 7 * 2 * .pi + 0.4
            let d = u * CGFloat(0.12 + age * 0.9)
            let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d)
            let r = u * CGFloat(0.07 * fade + 0.02)
            context.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)),
                         with: .color((i.isMultiple(of: 2) ? ToyCarPark.starGold : Color.white).opacity(fade)))
        }
    }
}

// MARK: - Palette

enum ToyCarPark {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.90, 0.95, 0.99), dark: (0.10, 0.12, 0.17)),
        backdropBottom: .dynamic(light: (0.80, 0.88, 0.95), dark: (0.05, 0.06, 0.09)),
        tray: .dynamic(light: (0.70, 0.78, 0.86), dark: (0.22, 0.26, 0.32)),
        socket: .dynamic(light: (0.84, 0.90, 0.95), dark: (0.14, 0.17, 0.21)),
        ink: .dynamic(light: (0.18, 0.25, 0.36), dark: (0.93, 0.95, 0.98)),
        deboss: .dynamic(light: (0.84, 0.90, 0.95), dark: (0.14, 0.17, 0.21)),
        debossRim: .dynamic(light: (1, 1, 1), dark: (0.02, 0.03, 0.04)),
        card: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.27, 0.30, 0.36)),
        accent: .dynamic(light: (0.94, 0.42, 0.40), dark: (1.0, 0.52, 0.48)))

    static let hint = "Swipe a car along its length to drive it out. Clear the lot without a bump."
    static let starGold = Color(red: 0.98, green: 0.76, blue: 0.22)
    static let ink = palette.ink

    static let pavement = Color.dynamic(light: (0.86, 0.84, 0.78), dark: (0.25, 0.25, 0.24))
    static let asphalt = Color.dynamic(light: (0.42, 0.44, 0.49), dark: (0.17, 0.18, 0.21))
    static let lot = Color.dynamic(light: (0.56, 0.58, 0.63), dark: (0.24, 0.25, 0.29))
    static let kerb = Color.dynamic(light: (0.94, 0.93, 0.90), dark: (0.46, 0.46, 0.45))
    static let roadLine = Color.dynamic(light: (1, 1, 1), dark: (0.85, 0.85, 0.82))
    static let fence = Color.dynamic(light: (0.80, 0.58, 0.36), dark: (0.62, 0.44, 0.28))
    static let barrier = Color.dynamic(light: (0.92, 0.30, 0.30), dark: (0.88, 0.34, 0.34))
    static let cone = Color.dynamic(light: (0.99, 0.55, 0.20), dark: (0.94, 0.50, 0.20))
    static let planter = Color.dynamic(light: (0.72, 0.50, 0.34), dark: (0.50, 0.34, 0.24))
    static let leaf = Color.dynamic(light: (0.42, 0.72, 0.38), dark: (0.28, 0.52, 0.28))
    static let bloomA = Color(red: 1.0, green: 0.55, blue: 0.70)
    static let bloomB = Color(red: 1.0, green: 0.85, blue: 0.30)
    static let booth = Color.dynamic(light: (0.97, 0.95, 0.90), dark: (0.80, 0.78, 0.74))
    static let glass = Color.dynamic(light: (0.28, 0.38, 0.52), dark: (0.16, 0.22, 0.32))
    static let cargo = Color.dynamic(light: (0.97, 0.96, 0.93), dark: (0.80, 0.80, 0.78))
    static let headlight = Color(red: 1.0, green: 0.97, blue: 0.80)
    static let taillight = Color(red: 0.92, green: 0.22, blue: 0.24)
    static let skin = Color(red: 0.98, green: 0.82, blue: 0.68)
    static let taxi = Color.dynamic(light: (0.99, 0.80, 0.22), dark: (0.92, 0.72, 0.20))
    /// Clay paint for the vehicles.
    static let paint: [Color] = [
        .dynamic(light: (0.93, 0.36, 0.36), dark: (0.86, 0.34, 0.34)),
        .dynamic(light: (0.32, 0.56, 0.93), dark: (0.32, 0.52, 0.86)),
        .dynamic(light: (0.38, 0.76, 0.48), dark: (0.32, 0.66, 0.42)),
        .dynamic(light: (0.98, 0.62, 0.28), dark: (0.90, 0.56, 0.26)),
        .dynamic(light: (0.62, 0.46, 0.90), dark: (0.56, 0.42, 0.84)),
        .dynamic(light: (0.26, 0.74, 0.76), dark: (0.24, 0.64, 0.66)),
        .dynamic(light: (0.96, 0.50, 0.70), dark: (0.88, 0.46, 0.64)),
        .dynamic(light: (0.96, 0.96, 0.94), dark: (0.84, 0.84, 0.82)),
    ]
}

/// A busy lot part way cleared, for the Home preview.
struct CarParkShowcase: View {
    let engine: CarParkEngine

    var body: some View {
        let palette = ToyCarPark.palette
        ZStack {
            palette.backdrop
            CarParkBoard(engine: engine)
                .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                .padding(20)
        }
        .environment(\.toyStyle, palette.style)
        .frame(width: 360, height: 360)
    }
}
