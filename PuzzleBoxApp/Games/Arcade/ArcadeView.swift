import SwiftUI

struct ArcadeView: View {
    @State private var engine: ArcadeEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var isShowcase = false

    init(mode: ArcadeMode) { _engine = State(initialValue: ArcadeEngine(mode: mode)) }

    /// The scene alone, mid-round, for the Home preview.
    init(showcase engine: ArcadeEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }

    var body: some View {
        if isShowcase { showcase } else { gameBody }
    }

    /// A square window onto the scene, on the game's own sky: the window's
    /// scale and top edge (in scene points) keep each game's action in view.
    private var showcase: some View {
        let skin = ArcadeSkin(mode: engine.mode)
        let (scale, top): (CGFloat, CGFloat) = switch engine.mode {
        case .knifeSpin: (1.2, 70)
        case .helixDrop: (1.125, 96)
        case .flappyFlight: (1.3, 172)
        case .roadHop: (1.125, 128)
        case .stack: (1.125, 0)
        }
        return ZStack {
            skin.palette.backdrop
            Canvas { context, size in
                context.translateBy(x: (size.width - 320 * scale) / 2, y: -top * scale)
                context.scaleBy(x: scale, y: scale)
                switch engine.mode {
                case .stack: drawStack(&context)
                case .knifeSpin: drawKnife(&context)
                case .helixDrop: drawHelix(&context)
                case .flappyFlight: drawFlappy(&context)
                case .roadHop: drawRoad(&context)
                }
                engine.fx.draw(in: &context)
            }
        }
        .environment(\.toyStyle, skin.palette.style)
        .frame(width: 360, height: 360)
    }

    private var gameBody: some View {
        Group {
            fullScreen
        }
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false }
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

    // MARK: Full screen

    /// Every arcade game fills the screen: each
    /// has its own soft sky as the backdrop with the score pressed into it,
    /// and the scene is drawn at the screen's width, centred in its height.
    private var fullScreen: some View {
        let skin = ArcadeSkin(mode: engine.mode)
        return GameContainerView(gameID: engine.mode.gameID, engine: engine,
                                 fullBleed: true,
                                 chrome: .inGame,
                                 backdrop: engine.mode == .stack ? AnyView(TowerSky(hue: engine.stackHue))
                                                                 : AnyView(skin.palette.backdrop),
                                 toyStyle: engine.mode == .stack ? TowerSky.style : skin.palette.style) {
            ZStack(alignment: .top) {
                GeometryReader { geometry in
                    let scale = geometry.size.width / 320
                    let top = (geometry.size.height - 480 * scale) / 2
                    Canvas { context, size in
                        context.translateBy(x: 0, y: top)
                        context.scaleBy(x: scale, y: scale)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        switch engine.mode {
                        case .stack: drawStack(&context)
                        case .knifeSpin: drawKnife(&context)
                        case .helixDrop: drawHelix(&context)
                        case .flappyFlight: drawFlappy(&context)
                        case .roadHop: drawRoad(&context)
                        }
                        engine.fx.draw(in: &context)
                        // The loss flash stops fading once the round is over;
                        // full screen it would tint the whole sky, so drop it then.
                        if engine.state == .playing {
                            engine.fx.drawFlash(in: &context, bounds: CGRect(x: -20, y: -400, width: 360, height: 1280),
                                                reduceMotion: reduceMotion)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if engine.mode == .helixDrop { engine.drag(x: value.location.x / scale) }
                        }
                        .onEnded { value in
                            if engine.mode == .helixDrop { engine.endDrag() }
                            let delta = value.translation
                            if engine.mode == .roadHop, engine.started, max(abs(delta.width), abs(delta.height)) > 15 {
                                if abs(delta.width) > abs(delta.height) {
                                    engine.hop(dx: delta.width > 0 ? 1 : -1, dy: 0)
                                } else { engine.hop(dx: 0, dy: delta.height > 0 ? 1 : -1) }
                            } else if !engine.started || max(abs(delta.width), abs(delta.height)) < 15 {
                                engine.tap()
                            }
                        })
                }
                // Edge to edge, so flashes and falling pieces reach the screen edges.
                .padding(.top, -16)
                .ignoresSafeArea()
                .overlay {
                    if !engine.started {
                        TapToStartCard(hint: L10n.text(engine.mode.hint))
                            .padding(.horizontal, 24)
                    }
                }
                if engine.mode == .roadHop {
                    // The road runs under the whole screen; a soft fade of the
                    // town's green keeps the score readable above the traffic.
                    LinearGradient(stops: [.init(color: skin.palette.backdropTop, location: 0),
                                           .init(color: skin.palette.backdropTop.opacity(0.92), location: 0.6),
                                           .init(color: skin.palette.backdropTop.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 190)
                        .padding(.top, -70)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
                Group {
                    if engine.mode == .stack {
                        ArcadeTopBar(ink: TowerSky.ink(engine.stackHue, dark: colorScheme == .dark),
                                     deboss: TowerSky.deboss(engine.stackHue, dark: colorScheme == .dark),
                                     rim: colorScheme == .dark ? .black.opacity(0.35) : .white) { EmptyView() }
                    } else {
                        ArcadeTopBar(ink: skin.palette.ink, deboss: skin.palette.deboss, rim: skin.palette.debossRim) {
                            if engine.mode == .knifeSpin { knifeChips(skin) }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// The level, and a boss badge, beside the score in Knife Spin.
    private func knifeChips(_ skin: ArcadeSkin) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            ToyChip(color: skin.palette.card) {
                Text(L10n.format("Level %d", engine.level)).foregroundStyle(skin.palette.ink)
            }
            if engine.isBossLevel {
                ToyChip(color: Color(red: 0.90, green: 0.42, blue: 0.40)) {
                    Text(L10n.text("Boss!")).foregroundStyle(.white)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: engine.isBossLevel)
    }

    private func ball(_ context: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    // MARK: Stack

    /// One block in isometric view: its top and the two faces toward the viewer,
    /// each shaded as if lit from the upper left.
    /// One slab of the tower, drawn with the engine's projection. Shared by the game and the Home preview.
    static func stackSlab(_ context: inout GraphicsContext, _ slab: StackSlab, alpha: Double = 1, engine: ArcadeEngine) {
        let top = CGFloat(slab.level + 1) * StackSlab.height - slab.drop
        let bottom = top - StackSlab.height
        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint { engine.stackScreen(x, y, z) }
        func face(_ points: [CGPoint], _ color: Color) {
            var path = Path(); path.addLines(points); path.closeSubpath()
            context.fill(path, with: .color(color.opacity(alpha)))
        }
        let x0 = slab.x, x1 = slab.x + slab.w, z0 = slab.z, z1 = slab.z + slab.d
        // Soft clay: a bright top, a mid front, a deeper side.
        face([p(x0, top, z1), p(x1, top, z1), p(x1, bottom, z1), p(x0, bottom, z1)],
             Color(hue: slab.hue, saturation: 0.5, brightness: 0.88))
        face([p(x1, top, z0), p(x1, top, z1), p(x1, bottom, z1), p(x1, bottom, z0)],
             Color(hue: slab.hue, saturation: 0.56, brightness: 0.72))
        face([p(x0, top, z0), p(x1, top, z0), p(x1, top, z1), p(x0, top, z1)],
             Color(hue: slab.hue, saturation: 0.38, brightness: 0.99))
        // A light rim along the front edges of the top.
        var rim = Path(); rim.addLines([p(x0, top, z1), p(x1, top, z1), p(x1, top, z0)])
        context.stroke(rim, with: .color(.white.opacity(0.35 * alpha)), lineWidth: 1)
    }

    private func drawStack(_ context: inout GraphicsContext) {
        // The sky and the score live outside the canvas (`TowerSky`, `ArcadeTopBar`).
        // Pieces falling off the far sides go behind the tower, the rest in front.
        let behind = engine.stackDebris.filter { $0.drift.dx < 0 || $0.drift.dy < 0 }
        let front = engine.stackDebris.filter { !($0.drift.dx < 0 || $0.drift.dy < 0) }
        for piece in behind { Self.stackSlab(&context, piece, alpha: 0.9, engine: engine) }
        let lowest = Int(engine.stackCamera) - 18
        for slab in engine.slabs where slab.level >= lowest { Self.stackSlab(&context, slab, engine: engine) }
        if let ripple = engine.ripple {
            let grow = ripple.t * 36, slab = ripple.slab
            let y = CGFloat(slab.level + 1) * StackSlab.height
            var outline = Path()
            outline.addLines([engine.stackScreen(slab.x - grow, y, slab.z - grow), engine.stackScreen(slab.x + slab.w + grow, y, slab.z - grow),
                              engine.stackScreen(slab.x + slab.w + grow, y, slab.z + slab.d + grow), engine.stackScreen(slab.x - grow, y, slab.z + slab.d + grow)])
            outline.closeSubpath()
            context.stroke(outline, with: .color(.white.opacity(Double(1 - ripple.t * 2))), lineWidth: 2.5)
        }
        for piece in front { Self.stackSlab(&context, piece, alpha: 0.9, engine: engine) }
        if engine.state == .playing, let moving = engine.movingSlab {
            Self.stackSlab(&context, moving, engine: engine)
            if engine.perfectStreak >= 2 {
                let y = CGFloat(moving.level + 1) * StackSlab.height
                var glow = Path()
                glow.addLines([engine.stackScreen(moving.x, y, moving.z), engine.stackScreen(moving.x + moving.w, y, moving.z),
                               engine.stackScreen(moving.x + moving.w, y, moving.z + moving.d), engine.stackScreen(moving.x, y, moving.z + moving.d)])
                glow.closeSubpath()
                context.stroke(glow, with: .color(.white.opacity(0.5 + 0.3 * Double(sin(engine.time * 8)))), lineWidth: 1.5)
            }
        }
    }

    // MARK: Knife Spin

    private func knifeShape(_ context: inout GraphicsContext, length: CGFloat, handle: Color) {
        // The origin is the blade tip; the handle extends along +y.
        var blade = Path()
        blade.move(to: .zero)
        blade.addLine(to: CGPoint(x: 4, y: length * 0.12))
        blade.addLine(to: CGPoint(x: 4, y: length * 0.55))
        blade.addLine(to: CGPoint(x: -3, y: length * 0.55))
        blade.addLine(to: CGPoint(x: -3, y: length * 0.12))
        blade.closeSubpath()
        context.fill(blade, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.65)]), startPoint: CGPoint(x: -3, y: 0), endPoint: CGPoint(x: 4, y: 0)))
        context.fill(Path(roundedRect: CGRect(x: -6, y: length * 0.53, width: 13, height: 4), cornerRadius: 2), with: .color(Color(white: 0.4)))
        context.fill(Path(roundedRect: CGRect(x: -3.5, y: length * 0.57, width: 8, height: length * 0.43), cornerRadius: 3), with: .color(handle))
    }

    private func drawKnife(_ context: inout GraphicsContext) {
        let center = CGPoint(x: 160, y: 180 - engine.targetKick * 6)
        let intro = 1 - engine.levelIntro / 0.45
        let radius = 80 * (0.6 + 0.4 * intro)
        let boss = engine.isBossLevel
        // Stuck knives (behind the target face).
        for pin in engine.pins {
            var k = context
            k.translateBy(x: center.x, y: center.y)
            k.rotate(by: .radians(Double(pin + engine.angle - .pi / 2)))
            k.translateBy(x: 0, y: radius - 10)
            knifeShape(&k, length: 48, handle: ArcadeSkin.knifeHandle)
        }
        // Target: wood rings or a steel boss shield.
        let rings: [Color] = boss
            ? [Color(red: 0.55, green: 0.1, blue: 0.12), Color(red: 0.75, green: 0.18, blue: 0.2), Color(red: 0.4, green: 0.06, blue: 0.08)]
            : [Color(red: 0.62, green: 0.38, blue: 0.2), Color(red: 0.78, green: 0.52, blue: 0.3), Color(red: 0.55, green: 0.33, blue: 0.17)]
        ball(&context, CGPoint(x: center.x, y: center.y + 4), radius + 2, .black.opacity(0.35))
        for (i, factor) in [1.0, 0.72, 0.42].enumerated() {
            ball(&context, center, radius * factor, rings[i % rings.count])
        }
        var spokes = context
        spokes.translateBy(x: center.x, y: center.y)
        spokes.rotate(by: .radians(Double(engine.angle)))
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3
            var line = Path(); line.move(to: CGPoint(x: cos(a) * 12, y: sin(a) * 12)); line.addLine(to: CGPoint(x: cos(a) * radius * 0.92, y: sin(a) * radius * 0.92))
            spokes.stroke(line, with: .color(.black.opacity(0.15)), lineWidth: 2)
        }
        ball(&context, center, 9, boss ? .black.opacity(0.6) : Color(red: 0.4, green: 0.22, blue: 0.1))
        // Apples on the rim.
        for apple in engine.apples {
            let a = apple + engine.angle
            let p = CGPoint(x: center.x + cos(a) * (radius + 9), y: center.y + sin(a) * (radius + 9))
            ball(&context, p, 9, .red)
            ball(&context, CGPoint(x: p.x - 3, y: p.y - 3), 3, .white.opacity(0.5))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 13, width: 5, height: 6)), with: .color(.green))
        }
        // Flying knife.
        if engine.state == .playing || engine.projectile != nil {
            var k = context
            k.translateBy(x: 160, y: engine.projectile ?? 425)
            knifeShape(&k, length: 54, handle: ArcadeSkin.knifeHandle.toyShade(0.12))
        }
        // Remaining knives indicator.
        for i in 0..<engine.totalPins {
            let used = i >= engine.remainingPins
            var k = context
            k.translateBy(x: 22, y: 452 - CGFloat(i) * 18)
            k.rotate(by: .radians(-.pi / 2))
            k.opacity = used ? 0.2 : 0.9
            k.scaleBy(x: 0.3, y: 0.3)
            knifeShape(&k, length: 54, handle: ArcadeSkin.knifeHandle)
        }
    }

    // MARK: Helix Drop

    /// The tower seen from slightly above: each floor is a flat ring around a central
    /// column. Platform space (0..<320, wrapping) maps to the angle around the column,
    /// with x = 160 (where the ball falls) at the front, nearest the viewer.
    private enum Helix {
        static let center: CGFloat = 160
        static let outer: CGFloat = 132
        static let inner: CGFloat = 27
        static let column: CGFloat = 26
        /// Where the ball rests on a floor, measured from the column's axis.
        static let ballRadius: CGFloat = 78
        /// Vertical squash of the circles: how far above the tower the camera is.
        static let tilt: CGFloat = 0.3
        static let thickness: CGFloat = 16
        static func angle(_ x: CGFloat) -> CGFloat { (x - center) / 320 * 2 * .pi }
        /// Screen y of a floor's centre for a platform whose front edge (under the ball) is at `top`.
        static func ringY(_ top: CGFloat) -> CGFloat { top - ballRadius * tilt }
        static func point(_ radius: CGFloat, _ angle: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center + radius * sin(angle), y: y + radius * tilt * cos(angle))
        }
        /// Splits an arc into pieces on the viewer's half (cos > 0) and the far half.
        static func halves(_ a: CGFloat, _ b: CGFloat) -> [(CGFloat, CGFloat, front: Bool)] {
            var pieces: [(CGFloat, CGFloat, front: Bool)] = []
            var t = a
            while t < b - 0.0001 {
                let k = floor((t + .pi / 2) / .pi)
                let end = min(b, (k + 1) * .pi - .pi / 2)
                pieces.append((t, end, Int(k).isMultiple(of: 2)))
                t = end
            }
            return pieces
        }
    }

    private func drawHelix(_ context: inout GraphicsContext) {
        // The sky is the screen's backdrop (`ArcadeSkin`).
        drawHelixColumn(&context, to: 900)
        let p = engine.player
        var ballDrawn = false
        // Lower floors first; higher ones are nearer the camera and overlap them.
        for body in engine.bodies.reversed() {
            if !ballDrawn, body.rect.minY < p.y - 4 {
                drawHelixBall(&context); ballDrawn = true
            }
            drawHelixRing(&context, body, front: false)
            drawHelixColumn(&context, to: Helix.ringY(body.rect.minY))
            drawHelixRing(&context, body, front: true)
            if !ballDrawn, let below = shadowFloor, below.id == body.id {
                // A soft shadow under the ball on the floor it is about to hit.
                let distance = max(0, body.rect.minY - p.y)
                let scale = max(0.35, 1 - distance / 180)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 11 * scale, y: body.rect.minY - 3.5 * scale, width: 22 * scale, height: 7 * scale)),
                             with: .color(.black.opacity(0.28 * Double(scale))))
            }
        }
        if !ballDrawn { drawHelixBall(&context) }
    }

    /// The floor straight under the ball, if the ball would land on a solid part of it.
    private var shadowFloor: ArcadeBody? {
        let p = engine.player
        guard let floor = engine.bodies.filter({ $0.rect.minY >= p.y }).min(by: { $0.rect.minY < $1.rect.minY }) else { return nil }
        let relative = (p.x - floor.rect.minX).truncatingRemainder(dividingBy: 320)
        return (relative < 0 ? relative + 320 : relative) >= floor.rect.width ? floor : nil
    }

    private func drawHelixColumn(_ context: inout GraphicsContext, to bottom: CGFloat) {
        let left = Helix.center - Helix.column, right = Helix.center + Helix.column
        // The column fades into the sky toward the top, clear of the score.
        context.drawLayer { context in
            drawHelixColumnBody(&context, left: left, right: right, bottom: bottom)
            context.blendMode = .destinationOut
            context.fill(Path(CGRect(x: left - 2, y: -400, width: right - left + 4, height: 530)),
                         with: .linearGradient(Gradient(stops: [.init(color: .black, location: 0),
                                                                .init(color: .black, location: 0.72),
                                                                .init(color: .clear, location: 1)]),
                                               startPoint: CGPoint(x: 0, y: -400), endPoint: CGPoint(x: 0, y: 130)))
        }
    }

    private func drawHelixColumnBody(_ context: inout GraphicsContext, left: CGFloat, right: CGFloat, bottom: CGFloat) {
        context.fill(Path(CGRect(x: left, y: -400, width: right - left, height: bottom + 400)),
                     with: .linearGradient(Gradient(stops: [.init(color: Color(white: 0.72 * (colorScheme == .dark ? 0.62 : 1)), location: 0),
                                                            .init(color: Color(white: 0.99 * (colorScheme == .dark ? 0.62 : 1)), location: 0.38),
                                                            .init(color: Color(white: 0.9 * (colorScheme == .dark ? 0.62 : 1)), location: 0.7),
                                                            .init(color: Color(red: 0.62, green: 0.68, blue: 0.82).opacity(colorScheme == .dark ? 0.45 : 1), location: 1)]),
                                           startPoint: CGPoint(x: left, y: 0), endPoint: CGPoint(x: right, y: 0)))
    }

    /// Draws one floor's far half (behind the column) or near half (in front of it).
    private func drawHelixRing(_ context: inout GraphicsContext, _ body: ArcadeBody, front: Bool) {
        let y = Helix.ringY(body.rect.minY)
        let h = Helix.thickness
        let zones = engine.helixRedZones(body)
        func isRed(_ u: CGFloat) -> Bool { zones.contains { $0.contains(u) } }
        // Solid ranges in platform space (the gap is 0..<width), split at the red zones.
        var cuts: [(Range<CGFloat>, Bool)] = []
        var cursor = body.rect.width
        for zone in zones.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if zone.lowerBound > cursor { cuts.append((cursor..<zone.lowerBound, false)) }
            cuts.append((zone, true)); cursor = zone.upperBound
        }
        if cursor < 320 { cuts.append((cursor..<320, false)) }

        // Soft sage-to-pistachio floors on a calm blue sky.
        let hue = 0.2 + body.hue * 0.08
        func topColor(_ red: Bool) -> Color {
            red ? Color(red: 0.86, green: 0.38, blue: 0.38) : Color(hue: hue, saturation: 0.42, brightness: colorScheme == .dark ? 0.66 : 0.88)
        }
        func sideColor(_ red: Bool, light: CGFloat) -> Color {
            red ? Color(red: 0.42 + 0.3 * light, green: 0.16 + 0.1 * light, blue: 0.18 + 0.1 * light)
                : Color(hue: hue + 0.01, saturation: 0.45, brightness: (0.45 + 0.3 * light) * (colorScheme == .dark ? 0.75 : 1))
        }
        /// Light from the upper left.
        func light(_ a: CGFloat) -> CGFloat { max(0, min(1, 0.55 - 0.45 * sin(a) + 0.15 * cos(a))) }

        for (range, red) in cuts {
            let a0 = Helix.angle(body.rect.minX + range.lowerBound)
            let a1 = Helix.angle(body.rect.minX + range.upperBound)
            for piece in Helix.halves(a0, a1) where piece.front == front {
                let steps = max(2, Int(ceil((piece.1 - piece.0) / 0.1)))
                let angles = (0...steps).map { piece.0 + (piece.1 - piece.0) * CGFloat($0) / CGFloat(steps) }
                if front {
                    // Outer wall, shaded strip by strip.
                    for i in 0..<steps {
                        var wall = Path()
                        let t0 = Helix.point(Helix.outer, angles[i], y), t1 = Helix.point(Helix.outer, angles[i + 1], y)
                        wall.addLines([t0, t1, CGPoint(x: t1.x, y: t1.y + h), CGPoint(x: t0.x, y: t0.y + h)])
                        wall.closeSubpath()
                        context.fill(wall, with: .color(sideColor(red, light: light((angles[i] + angles[i + 1]) / 2))))
                        context.stroke(wall, with: .color(sideColor(red, light: light((angles[i] + angles[i + 1]) / 2))), lineWidth: 0.6)
                    }
                }
                var top = Path()
                top.addLines(angles.map { Helix.point(Helix.outer, $0, y) } + angles.reversed().map { Helix.point(Helix.inner, $0, y) })
                top.closeSubpath()
                context.fill(top, with: .color(topColor(red)))
                // Hides the anti-aliased seam where the near and far halves meet.
                context.stroke(top, with: .color(topColor(red)), lineWidth: 0.8)
                if front {
                    var rim = Path(); rim.addLines(angles.map { Helix.point(Helix.outer, $0, y) })
                    context.stroke(rim, with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
            }
        }

        // The cut faces at the edges of the gap, wherever they face the viewer:
        // ones on the far half are drawn with it, behind the column.
        for (u, start) in [(body.rect.width, true), (CGFloat(320), false)] {
            let a = Helix.angle(body.rect.minX + u)
            guard (cos(a) >= 0) == front, start ? sin(a) > 0 : sin(a) < 0 else { continue }
            let red = isRed(start ? u : u - 0.5)
            let o = Helix.point(Helix.outer, a, y), n = Helix.point(Helix.inner, a, y)
            var cap = Path()
            cap.addLines([n, o, CGPoint(x: o.x, y: o.y + h), CGPoint(x: n.x, y: n.y + h)])
            cap.closeSubpath()
            context.fill(cap, with: .color(sideColor(red, light: 0.25)))
            // Redraw the top's edge so the cap sits under it.
            var edge = Path(); edge.move(to: n); edge.addLine(to: o)
            context.stroke(edge, with: .color(topColor(red)), lineWidth: 1)
        }
    }

    private func drawHelixBall(_ context: inout GraphicsContext) {
        let p = engine.player
        if engine.fireball {
            ball(&context, p, 16, .orange.opacity(0.35))
            ball(&context, p, 11, .orange)
            ball(&context, p, 6, .yellow)
        } else {
            ball(&context, CGPoint(x: p.x, y: p.y + 2), 10, .black.opacity(0.3))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                         with: .radialGradient(Gradient(colors: [.white, Color(red: 0.95, green: 0.55, blue: 0.62), Color(red: 0.68, green: 0.3, blue: 0.4)]), center: CGPoint(x: p.x - 3, y: p.y - 4), startRadius: 1, endRadius: 14))
        }
        if engine.combo >= 2 && !engine.fireball {
            context.draw(Text("×\(engine.combo)").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.yellow),
                         at: CGPoint(x: p.x + 26, y: p.y - 14))
        }
    }

    // MARK: Flappy Flight

    private func drawFlappy(_ context: inout GraphicsContext) {
        // The sky is the screen's backdrop (`ArcadeSkin`); clouds and hills drift past.
        let dark = colorScheme == .dark
        let cloud = Color.white.opacity(dark ? 0.12 : 0.8)
        for i in 0..<5 {
            let x = (CGFloat(i) * 90 - engine.scroll * 0.15).truncatingRemainder(dividingBy: 450)
            let cx = x < -60 ? x + 450 : x
            let y = 60 + CGFloat((i * 53) % 120)
            context.fill(Path(roundedRect: CGRect(x: cx, y: y, width: 58, height: 18), cornerRadius: 9), with: .color(cloud))
            context.fill(Path(ellipseIn: CGRect(x: cx + 12, y: y - 10, width: 28, height: 24)), with: .color(cloud))
        }
        let hill = Color.dynamic(light: (0.66, 0.84, 0.66), dark: (0.17, 0.30, 0.24))
        for i in 0..<6 {
            let x = (CGFloat(i) * 80 - engine.scroll * 0.4).truncatingRemainder(dividingBy: 480)
            let hx = x < -80 ? x + 480 : x
            context.fill(Path(ellipseIn: CGRect(x: hx - 20, y: 400, width: 140, height: 120)), with: .color(hill))
        }
        // Soft clay pipes: lit down the left, a darker lip under each cap.
        let pipe = Color.dynamic(light: (0.47, 0.80, 0.60), dark: (0.30, 0.62, 0.45))
        for body in engine.bodies {
            let r = body.rect
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [pipe.toyShade(0.06), pipe.toyShade(0.14), pipe, pipe.toyShade(-0.12)]),
                startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0))
            context.fill(Path(CGRect(x: r.minX + 3, y: -400, width: r.width - 6, height: max(0, r.minY + 400))), with: shading)
            context.fill(Path(CGRect(x: r.minX + 3, y: r.maxY, width: r.width - 6, height: max(0, 900 - r.maxY))), with: shading)
            for cap in [CGRect(x: r.minX - 3, y: r.minY - 18, width: r.width + 6, height: 18),
                        CGRect(x: r.minX - 3, y: r.maxY, width: r.width + 6, height: 18)] {
                context.fill(Path(roundedRect: cap.offsetBy(dx: 0, dy: 3), cornerRadius: 7), with: .color(pipe.toyShade(-0.22)))
                context.fill(Path(roundedRect: cap, cornerRadius: 7), with: shading)
                context.stroke(Path(roundedRect: cap.insetBy(dx: 1, dy: 1), cornerRadius: 6),
                               with: .color(.white.opacity(0.35)), lineWidth: 1)
                if body.speed > 0 {
                    context.stroke(Path(roundedRect: cap, cornerRadius: 7), with: .color(.yellow.opacity(0.8)), lineWidth: 1.5)
                }
            }
        }
        for coin in engine.coins {
            let squash = abs(cos(engine.time * 4 + coin.y))
            context.fill(Path(ellipseIn: CGRect(x: coin.x - 9 * squash, y: coin.y - 7, width: 18 * squash, height: 18)), with: .color(Color(red: 0.86, green: 0.62, blue: 0.16)))
            context.fill(Path(ellipseIn: CGRect(x: coin.x - 9 * squash, y: coin.y - 9, width: 18 * squash, height: 18)), with: .color(Color(red: 1.0, green: 0.82, blue: 0.30)))
            context.stroke(Path(ellipseIn: CGRect(x: coin.x - 5.5 * squash, y: coin.y - 5.5, width: 11 * squash, height: 11)), with: .color(Color(red: 0.95, green: 0.66, blue: 0.18)), lineWidth: 1.5)
        }
        // The ceiling: a bank of cloud the bird can't fly into.
        let bank = Color.dynamic(light: (1, 1, 1), dark: (0.20, 0.25, 0.40))
        context.fill(Path(CGRect(x: -20, y: -14, width: 360, height: 18)), with: .color(bank.opacity(dark ? 1 : 0.9)))
        for i in 0..<9 {
            let x = (CGFloat(i) * 44 - engine.scroll * 0.6).truncatingRemainder(dividingBy: 396)
            let cx = x < -40 ? x + 396 : x
            let rise = CGFloat((i * 7) % 3) * 4
            context.fill(Path(ellipseIn: CGRect(x: cx - 30, y: -26 - rise, width: 60, height: 40 + rise)),
                         with: .color(bank.opacity(dark ? 1 : 0.9)))
        }
        // The ground: grass on a sandy bank down to the bottom of the screen.
        let sand = Color.dynamic(light: (0.93, 0.80, 0.60), dark: (0.36, 0.28, 0.20))
        let grass = Color.dynamic(light: (0.52, 0.78, 0.45), dark: (0.24, 0.45, 0.26))
        context.fill(Path(CGRect(x: -20, y: 462, width: 360, height: 500)), with: .color(sand))
        context.fill(Path(roundedRect: CGRect(x: -20, y: 458, width: 360, height: 10), cornerRadius: 5), with: .color(grass))
        for i in 0..<12 {
            let x = (CGFloat(i) * 30 - engine.scroll).truncatingRemainder(dividingBy: 360)
            context.fill(Path(roundedRect: CGRect(x: x < -30 ? x + 360 : x, y: 466, width: 14, height: 4), cornerRadius: 2),
                         with: .color(sand.toyShade(-0.08)))
        }
        // Bird tilts with its velocity and flaps its wing.
        var bird = context
        bird.translateBy(x: engine.player.x, y: engine.player.y)
        bird.rotate(by: .radians(Double(min(1.1, max(-0.5, engine.velocity.dy / 420)))))
        bird.fill(Path(ellipseIn: CGRect(x: -13, y: -8, width: 26, height: 20)), with: .color(Color(red: 0.90, green: 0.55, blue: 0.20)))
        bird.fill(Path(ellipseIn: CGRect(x: -13, y: -10, width: 26, height: 20)),
                  with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.90, blue: 0.45), Color(red: 1.0, green: 0.70, blue: 0.28)]),
                                        center: CGPoint(x: -3, y: -5), startRadius: 1, endRadius: 16))
        let wing = engine.flap > 0 ? -6 * engine.flap : 2 * CGFloat(sin(Double(engine.time) * 12))
        bird.fill(Path(ellipseIn: CGRect(x: -11, y: -2 + wing, width: 13, height: 8)), with: .color(.white.opacity(0.95)))
        bird.fill(Path(ellipseIn: CGRect(x: 2, y: -8, width: 8, height: 8)), with: .color(.white))
        bird.fill(Path(ellipseIn: CGRect(x: 5.5, y: -6, width: 3.5, height: 4)), with: .color(Color(red: 0.2, green: 0.18, blue: 0.25)))
        bird.fill(Path(ellipseIn: CGRect(x: -2, y: 1, width: 6, height: 4)), with: .color(Color(red: 1.0, green: 0.55, blue: 0.55).opacity(0.6)))
        var beak = Path(); beak.move(to: CGPoint(x: 10, y: -1)); beak.addLine(to: CGPoint(x: 18, y: 2)); beak.addLine(to: CGPoint(x: 10, y: 5)); beak.closeSubpath()
        bird.fill(beak, with: .color(Color(red: 0.98, green: 0.52, blue: 0.30)))
    }

    // MARK: Road Hop

    private func drawRoad(_ context: inout GraphicsContext) {
        // A toy town: soft grass verges, slate-lilac roads, clay cars.
        let grassA = Color.dynamic(light: (0.70, 0.87, 0.62), dark: (0.20, 0.34, 0.22))
        let grassB = Color.dynamic(light: (0.64, 0.83, 0.57), dark: (0.18, 0.31, 0.20))
        let road = Color.dynamic(light: (0.60, 0.61, 0.72), dark: (0.21, 0.22, 0.29))
        for lane in engine.visibleRoadRows where lane.y > -220 && lane.y < 720 {
            let rect = CGRect(x: -20, y: lane.y - 25, width: 360, height: 50)
            if engine.isGrassRow(lane.row) {
                context.fill(Path(rect), with: .color(lane.row.isMultiple(of: 2) ? grassA : grassB))
                for i in 0..<5 {
                    let x = CGFloat((lane.row * 37 + i * 71) % 300) + 10
                    let tuft = CGRect(x: x, y: lane.y - 6 + CGFloat(i % 3) * 6, width: 8, height: 5)
                    context.fill(Path(ellipseIn: tuft), with: .color(grassA.toyShade(-0.12)))
                }
            } else {
                context.fill(Path(rect), with: .color(road))
                if !engine.isGrassRow(lane.row + 1) {
                    for x in stride(from: 6, to: 320, by: 40) {
                        context.fill(Path(roundedRect: CGRect(x: CGFloat(x), y: lane.y - 26.5, width: 20, height: 3), cornerRadius: 1.5),
                                     with: .color(.white.opacity(0.6)))
                    }
                }
                // A kerb where the road meets the grass.
                if engine.isGrassRow(lane.row - 1) {
                    context.fill(Path(CGRect(x: -20, y: lane.y + 22, width: 360, height: 3)), with: .color(.white.opacity(0.35)))
                }
            }
        }
        for coin in engine.coins {
            let bob = CGFloat(sin(Double(engine.time) * 4 + Double(coin.x))) * 2
            let c = CGPoint(x: coin.x, y: coin.y + bob)
            ball(&context, CGPoint(x: c.x, y: c.y + 2), 8, Color(red: 0.86, green: 0.62, blue: 0.16))
            ball(&context, c, 8, Color(red: 1.0, green: 0.82, blue: 0.30))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)),
                           with: .color(Color(red: 0.95, green: 0.66, blue: 0.18)), lineWidth: 1.5)
        }
        for car in engine.bodies {
            let r = car.rect
            let color = car.value < 0 ? Color(red: 0.95, green: 0.66, blue: 0.40) : ArcadeSkin.carColors[abs(car.value) % ArcadeSkin.carColors.count]
            // Wheels peek out under the body.
            for wx in [r.minX + 10, r.maxX - 20] {
                for wy in [r.minY - 3, r.maxY - 2] {
                    context.fill(Path(roundedRect: CGRect(x: wx, y: wy, width: 10, height: 5), cornerRadius: 2.5),
                                 with: .color(Color(red: 0.25, green: 0.24, blue: 0.30)))
                }
            }
            // Clay body: a darker lip under a lit face.
            context.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 3), cornerRadius: 9), with: .color(color.toyShade(-0.2)))
            context.fill(Path(roundedRect: r, cornerRadius: 9),
                         with: .linearGradient(Gradient(colors: [color.toyShade(0.08), color]),
                                               startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
            context.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 8), with: .color(.white.opacity(0.35)), lineWidth: 1)
            if car.value < 0 {
                let cab = car.speed > 0 ? CGRect(x: r.maxX - 26, y: r.minY + 4, width: 21, height: r.height - 8) : CGRect(x: r.minX + 5, y: r.minY + 4, width: 21, height: r.height - 8)
                context.fill(Path(roundedRect: cab, cornerRadius: 5), with: .color(.white.opacity(0.55)))
            } else {
                context.fill(Path(roundedRect: CGRect(x: r.midX - 13, y: r.minY + 6, width: 26, height: r.height - 12), cornerRadius: 6),
                             with: .color(Color(red: 0.80, green: 0.90, blue: 1.0).opacity(0.85)))
            }
            let front = car.speed > 0 ? r.maxX - 4 : r.minX + 1
            context.fill(Path(ellipseIn: CGRect(x: front, y: r.minY + 5, width: 3, height: 5)), with: .color(Color(red: 1, green: 0.95, blue: 0.6)))
            context.fill(Path(ellipseIn: CGRect(x: front, y: r.maxY - 10, width: 3, height: 5)), with: .color(Color(red: 1, green: 0.95, blue: 0.6)))
        }
        // Hopper with a small arc and squash while jumping.
        let progress = engine.hopTimer / 0.14
        let lift = sin(progress * .pi) * 8
        let p = CGPoint(x: engine.player.x, y: engine.player.y - lift)
        context.fill(Path(ellipseIn: CGRect(x: engine.player.x - 10 + lift * 0.3, y: engine.player.y + 6, width: 20 - lift * 0.6, height: 7)),
                     with: .color(.black.opacity(0.2)))
        let w: CGFloat = 22 - lift * 0.4, h: CGFloat = 22 + lift * 0.5
        let bodyRect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
        context.fill(Path(roundedRect: bodyRect.offsetBy(dx: 0, dy: 2.5), cornerRadius: 8), with: .color(Color(white: 0.78)))
        context.fill(Path(roundedRect: bodyRect, cornerRadius: 8), with: .color(.white))
        context.fill(Path(roundedRect: CGRect(x: p.x - 4, y: p.y - h / 2 - 4, width: 8, height: 6), cornerRadius: 3), with: .color(Color(red: 0.95, green: 0.42, blue: 0.40)))
        let eyeX = p.x + engine.facing * 3
        ball(&context, CGPoint(x: eyeX - 4, y: p.y - 3), 2, Color(red: 0.2, green: 0.18, blue: 0.25))
        ball(&context, CGPoint(x: eyeX + 4, y: p.y - 3), 2, Color(red: 0.2, green: 0.18, blue: 0.25))
        context.fill(Path(roundedRect: CGRect(x: p.x - 3, y: p.y + 1, width: 6, height: 4), cornerRadius: 1.5), with: .color(Color(red: 0.98, green: 0.62, blue: 0.28)))
    }
}


// MARK: - Tower sky

/// The sky behind the tower; its hue follows the tower's colour as it grows.
struct TowerSky: View {
    let hue: Double
    @Environment(\.colorScheme) private var scheme

    static let style = ToyStyle(card: .dynamic(light: (0.99, 0.99, 1.0), dark: (0.18, 0.20, 0.26)),
                                accent: Color(red: 0.40, green: 0.62, blue: 0.96),
                                ink: .dynamic(light: (0.20, 0.27, 0.40), dark: (0.92, 0.94, 0.98)),
                                tray: .dynamic(light: (0.80, 0.86, 0.96), dark: (0.26, 0.30, 0.40)),
                                haze: .dynamic(light: (0.70, 0.80, 0.95), dark: (0.08, 0.10, 0.18)))

    /// Text and the pressed-in score, tinted with the tower.
    static func ink(_ hue: Double, dark: Bool) -> Color {
        Color(hue: hue, saturation: dark ? 0.15 : 0.55, brightness: dark ? 0.95 : 0.35)
    }
    static func deboss(_ hue: Double, dark: Bool) -> Color {
        Color(hue: hue, saturation: dark ? 0.35 : 0.30, brightness: dark ? 0.50 : 0.84)
    }

    var body: some View {
        let dark = scheme == .dark
        LinearGradient(colors: [Color(hue: hue, saturation: dark ? 0.45 : 0.20, brightness: dark ? 0.30 : 0.99),
                                Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1),
                                      saturation: dark ? 0.50 : 0.34, brightness: dark ? 0.13 : 0.92)],
                       startPoint: .top, endPoint: .bottom)
            .animation(.easeInOut(duration: 0.8), value: hue)
    }
}

/// Pause, the score pressed into the sky, and the game's own chips on the right.
private struct ArcadeTopBar<Trailing: View>: View {
    let ink: Color
    let deboss: Color
    let rim: Color
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.gameHUD) private var hud
    @State private var bump = 0

    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                ToyIconButton(symbol: "pause.fill", label: L10n.text("Paused"), ink: ink) { hud.pause() }
                Spacer()
                trailing()
            }
            ToyPressedScore(score: hud.score, best: hud.best, deboss: deboss, rim: rim, ink: ink, bump: bump)
                .padding(.horizontal, 56)
                .allowsHitTesting(false)
        }
        .onChange(of: hud.score) { old, new in
            if new > old { bump += 1 }
        }
    }
}

/// The soft toy world of each full-screen arcade game.
struct ArcadeSkin {
    let palette: ToyPalette

    init(mode: ArcadeMode) {
        switch mode {
        case .knifeSpin:
            // Warm apricot: a wooden target on a sunny wall.
            palette = ToyPalette(
                backdropTop: .dynamic(light: (1.0, 0.95, 0.89), dark: (0.21, 0.15, 0.12)),
                backdropBottom: .dynamic(light: (0.98, 0.83, 0.72), dark: (0.11, 0.07, 0.06)),
                tray: .dynamic(light: (0.93, 0.74, 0.60), dark: (0.40, 0.28, 0.22)),
                socket: .dynamic(light: (0.88, 0.67, 0.53), dark: (0.30, 0.21, 0.17)),
                ink: .dynamic(light: (0.47, 0.27, 0.18), dark: (1.0, 0.92, 0.86)),
                deboss: .dynamic(light: (0.97, 0.83, 0.72), dark: (0.46, 0.33, 0.27)),
                debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.06, 0.04, 0.03)),
                card: .dynamic(light: (1.0, 0.98, 0.96), dark: (0.27, 0.20, 0.17)),
                accent: .dynamic(light: (0.93, 0.47, 0.40), dark: (0.98, 0.58, 0.50)))
        case .flappyFlight:
            // A clear day sky over green hills.
            palette = ToyPalette(
                backdropTop: .dynamic(light: (0.74, 0.88, 0.99), dark: (0.10, 0.14, 0.27)),
                backdropBottom: .dynamic(light: (0.93, 0.97, 0.99), dark: (0.17, 0.22, 0.34)),
                tray: .dynamic(light: (0.76, 0.86, 0.96), dark: (0.24, 0.30, 0.42)),
                socket: .dynamic(light: (0.68, 0.79, 0.91), dark: (0.18, 0.23, 0.33)),
                ink: .dynamic(light: (0.18, 0.31, 0.46), dark: (0.92, 0.95, 1.0)),
                deboss: .dynamic(light: (0.66, 0.81, 0.95), dark: (0.30, 0.38, 0.55)),
                debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.04, 0.05, 0.10)),
                card: .dynamic(light: (0.99, 1.0, 1.0), dark: (0.18, 0.22, 0.32)),
                accent: .dynamic(light: (0.98, 0.62, 0.26), dark: (1.0, 0.70, 0.36)))
        case .roadHop:
            // A toy town in spring greens.
            palette = ToyPalette(
                backdropTop: .dynamic(light: (0.84, 0.93, 0.80), dark: (0.12, 0.18, 0.13)),
                backdropBottom: .dynamic(light: (0.70, 0.86, 0.64), dark: (0.08, 0.12, 0.09)),
                tray: .dynamic(light: (0.72, 0.85, 0.66), dark: (0.24, 0.33, 0.25)),
                socket: .dynamic(light: (0.64, 0.79, 0.58), dark: (0.18, 0.26, 0.19)),
                ink: .dynamic(light: (0.20, 0.36, 0.22), dark: (0.92, 0.97, 0.90)),
                deboss: .dynamic(light: (0.56, 0.74, 0.52), dark: (0.30, 0.42, 0.32)),
                debossRim: .dynamic(light: (0.86, 0.95, 0.82), dark: (0.04, 0.06, 0.04)),
                card: .dynamic(light: (0.99, 1.0, 0.98), dark: (0.19, 0.25, 0.20)),
                accent: .dynamic(light: (0.95, 0.55, 0.42), dark: (0.98, 0.64, 0.52)))
        default:
            // Helix Drop: a soft periwinkle sky.
            palette = ToyPalette(
                backdropTop: .dynamic(light: (0.86, 0.88, 0.99), dark: (0.15, 0.16, 0.30)),
                backdropBottom: .dynamic(light: (0.70, 0.75, 0.95), dark: (0.07, 0.08, 0.16)),
                tray: .dynamic(light: (0.76, 0.79, 0.95), dark: (0.26, 0.28, 0.44)),
                socket: .dynamic(light: (0.68, 0.71, 0.90), dark: (0.19, 0.21, 0.34)),
                ink: .dynamic(light: (0.26, 0.28, 0.52), dark: (0.93, 0.93, 1.0)),
                deboss: .dynamic(light: (0.78, 0.81, 0.97), dark: (0.32, 0.34, 0.55)),
                debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.04, 0.04, 0.09)),
                card: .dynamic(light: (0.99, 0.99, 1.0), dark: (0.20, 0.21, 0.33)),
                accent: .dynamic(light: (0.93, 0.50, 0.62), dark: (0.98, 0.62, 0.72)))
        }
    }

    /// Road Hop cars: candy clay.
    static let carColors: [Color] = [
        Color(red: 0.96, green: 0.55, blue: 0.52), Color(red: 0.50, green: 0.70, blue: 0.96),
        Color(red: 1.00, green: 0.80, blue: 0.36), Color(red: 0.70, green: 0.58, blue: 0.94),
        Color(red: 0.46, green: 0.82, blue: 0.70), Color(red: 0.98, green: 0.62, blue: 0.80),
    ]

    /// Knife handles: a soft coral.
    static let knifeHandle = Color(red: 0.92, green: 0.48, blue: 0.42)
}

/// The Tower as it stands mid-game, drawn with the game's own slabs and sky,
/// for the Home preview.
struct TowerShowcase: View {
    let engine: ArcadeEngine

    var body: some View {
        ZStack {
            TowerSky(hue: engine.stackHue)
            Canvas { context, size in
                // Centre the stack itself, not the full-screen scene.
                let scale = size.width / 320
                let top = size.height / 2 - 230 * scale
                context.translateBy(x: 0, y: top)
                context.scaleBy(x: scale, y: scale)
                let lowest = Int(engine.stackCamera) - 18
                for slab in engine.slabs where slab.level >= lowest {
                    ArcadeView.stackSlab(&context, slab, engine: engine)
                }
                // The next block, the same size as the top, still sliding in
                // along the next axis before the tap that drops it.
                if let peak = engine.slabs.last {
                    let alongX = engine.placed % 2 == 0
                    let moving = StackSlab(x: peak.x + (alongX ? 40 : 0), z: peak.z + (alongX ? 0 : 40),
                                           w: peak.w, d: peak.d, level: peak.level + 1,
                                           hue: ArcadeEngine.stackHue(peak.level + 1))
                    ArcadeView.stackSlab(&context, moving, engine: engine)
                }
            }
        }
        .frame(width: 360, height: 360)
    }
}
