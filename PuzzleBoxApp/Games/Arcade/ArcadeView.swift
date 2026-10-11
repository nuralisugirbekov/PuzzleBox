import SwiftUI

struct ArcadeView: View {
    @State private var engine: ArcadeEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let carColors: [Color] = [.cyan, .pink, .yellow, .purple, .orange, .mint]

    init(mode: ArcadeMode) { _engine = State(initialValue: ArcadeEngine(mode: mode)) }

    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                if engine.mode == .knifeSpin {
                    HStack(spacing: 8) {
                        Text(L10n.format("Level %d · Remaining: %d", engine.level, engine.remainingPins))
                        if engine.isBossLevel {
                            Text(L10n.text("Boss!"))
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.red, in: Capsule())
                        }
                    }
                    .foregroundStyle(GameTheme.accent)
                }
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 480)
                        let shake = engine.fx.shakeOffset(reduceMotion: reduceMotion)
                        context.translateBy(x: shake.width, y: shake.height)
                        draw(in: &context)
                        engine.fx.draw(in: &context)
                        engine.fx.drawFlash(in: &context, bounds: CGRect(x: -20, y: -20, width: 360, height: 520), reduceMotion: reduceMotion)
                    }
                    .arenaBackground()
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        if !engine.started {
                            VStack(spacing: 12) {
                                Image(systemName: "hand.tap.fill").font(.largeTitle)
                                Text(L10n.text("Tap to start")).font(.headline)
                            }
                            .padding(24).background(GameTheme.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                            .foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            engine.drag(x: value.location.x / geometry.size.width * 320)
                        }
                        .onEnded { value in
                            engine.endDrag()
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
                .aspectRatio(2.0 / 3, contentMode: .fit)
                .frame(maxWidth: 400, maxHeight: 480)
                Text(L10n.text(engine.mode.hint))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
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

    private func draw(in context: inout GraphicsContext) {
        switch engine.mode {
        case .stack: drawStack(&context)
        case .knifeSpin: drawKnife(&context)
        case .helixDrop: drawHelix(&context)
        case .flappyFlight: drawFlappy(&context)
        case .roadHop: drawRoad(&context)
        }
        if engine.flash > 0 {
            context.stroke(Path(roundedRect: CGRect(x: 2, y: 2, width: 316, height: 476), cornerRadius: 16),
                           with: .color(GameTheme.accent.opacity(engine.flash * 3)), lineWidth: 3)
        }
    }

    private func ball(_ context: inout GraphicsContext, _ p: CGPoint, _ r: CGFloat, _ color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    // MARK: Stack

    private func stackBlock(_ context: inout GraphicsContext, _ rect: CGRect, hue: Double) {
        let face = Color(hue: hue, saturation: 0.55, brightness: 0.92)
        let shade = Color(hue: hue, saturation: 0.7, brightness: 0.62)
        context.fill(Path(roundedRect: rect, cornerRadius: 4),
                     with: .linearGradient(Gradient(colors: [face, shade]), startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY)))
        context.fill(Path(roundedRect: CGRect(x: rect.minX + 2, y: rect.minY + 1, width: max(0, rect.width - 4), height: 4), cornerRadius: 2),
                     with: .color(.white.opacity(0.35)))
    }

    private func drawStack(_ context: inout GraphicsContext) {
        let hue = engine.stackHue
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 480)),
                     with: .linearGradient(Gradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.32), Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.5, brightness: 0.12)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 480)))
        // Faint height marker in the background.
        context.draw(Text("\(engine.placed)").font(.system(size: 120, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.07)),
                     at: CGPoint(x: 160, y: 120))
        var world = context
        world.translateBy(x: 0, y: -engine.cameraLag)
        for body in engine.bodies { stackBlock(&world, body.rect, hue: body.hue) }
        if let ripple = engine.ripple {
            let grow = ripple.t * 40
            world.stroke(Path(roundedRect: ripple.rect.insetBy(dx: -grow, dy: -grow * 0.5), cornerRadius: 6),
                         with: .color(.white.opacity(Double(1 - ripple.t * 2))), lineWidth: 2.5)
        }
        for piece in engine.debris {
            var d = world
            d.translateBy(x: piece.rect.midX, y: piece.rect.midY)
            d.rotate(by: .radians(Double(piece.phase)))
            d.opacity = 0.85
            stackBlock(&d, CGRect(x: -piece.rect.width / 2, y: -11, width: piece.rect.width, height: 22), hue: piece.hue)
        }
        if engine.state == .playing {
            let next = (0.52 + Double(engine.placed + 1) * 0.031).truncatingRemainder(dividingBy: 1)
            stackBlock(&world, engine.movingBlock, hue: next)
            if engine.perfectStreak >= 2 {
                world.stroke(Path(roundedRect: engine.movingBlock.insetBy(dx: -2, dy: -2), cornerRadius: 5),
                             with: .color(.white.opacity(0.5 + 0.3 * Double(sin(engine.time * 8)))), lineWidth: 1.5)
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
            knifeShape(&k, length: 48, handle: GameTheme.accent)
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
            knifeShape(&k, length: 54, handle: .white.opacity(0.9))
        }
        // Remaining knives indicator.
        for i in 0..<engine.totalPins {
            let used = i >= engine.remainingPins
            var k = context
            k.translateBy(x: 22, y: 452 - CGFloat(i) * 18)
            k.rotate(by: .radians(-.pi / 2))
            k.opacity = used ? 0.2 : 0.9
            k.scaleBy(x: 0.3, y: 0.3)
            knifeShape(&k, length: 54, handle: GameTheme.accent)
        }
    }

    // MARK: Helix Drop

    private func drawHelix(_ context: inout GraphicsContext) {
        context.fill(Path(roundedRect: CGRect(x: 148, y: -10, width: 24, height: 500), cornerRadius: 8),
                     with: .linearGradient(Gradient(colors: [Color(white: 0.25), Color(white: 0.5), Color(white: 0.25)]),
                                           startPoint: CGPoint(x: 148, y: 0), endPoint: CGPoint(x: 172, y: 0)))
        for body in engine.bodies {
            let safe = Color(hue: body.hue, saturation: 0.6, brightness: 0.95)
            let side = Color(hue: body.hue, saturation: 0.7, brightness: 0.55)
            // Split the solid part (gap excluded) into safe and red ranges in platform space.
            var cuts: [(Range<CGFloat>, Bool)] = []
            var cursor = body.rect.width
            for zone in engine.helixRedZones(body).sorted(by: { $0.lowerBound < $1.lowerBound }) {
                if zone.lowerBound > cursor { cuts.append((cursor..<zone.lowerBound, false)) }
                cuts.append((zone, true)); cursor = zone.upperBound
            }
            if cursor < 320 { cuts.append((cursor..<320, false)) }
            for (range, red) in cuts {
                var start = (body.rect.minX + range.lowerBound).truncatingRemainder(dividingBy: 320)
                var length = range.upperBound - range.lowerBound
                while length > 0 {
                    let piece = min(length, 320 - start)
                    let rect = CGRect(x: start, y: body.rect.minY, width: piece, height: 12)
                    context.fill(Path(CGRect(x: rect.minX, y: rect.minY + 6, width: rect.width, height: 10)), with: .color(red ? Color(red: 0.5, green: 0, blue: 0.05) : side))
                    context.fill(Path(rect), with: .color(red ? .red : safe))
                    length -= piece; start = 0
                }
            }
        }
        let p = engine.player
        if engine.fireball {
            ball(&context, p, 16, .orange.opacity(0.35))
            ball(&context, p, 11, .orange)
            ball(&context, p, 6, .yellow)
        } else {
            ball(&context, CGPoint(x: p.x, y: p.y + 2), 10, .black.opacity(0.3))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                         with: .radialGradient(Gradient(colors: [.white, GameTheme.accent]), center: CGPoint(x: p.x - 3, y: p.y - 4), startRadius: 1, endRadius: 13))
        }
        if engine.combo >= 2 && !engine.fireball {
            context.draw(Text("×\(engine.combo)").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(.yellow),
                         at: CGPoint(x: p.x + 26, y: p.y - 14))
        }
    }

    // MARK: Flappy Flight

    private func drawFlappy(_ context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 320, height: 480)),
                     with: .linearGradient(Gradient(colors: [Color(red: 0.16, green: 0.25, blue: 0.5), Color(red: 0.35, green: 0.55, blue: 0.75)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: 480)))
        // Parallax clouds and hills.
        for i in 0..<5 {
            let x = (CGFloat(i) * 90 - engine.scroll * 0.15).truncatingRemainder(dividingBy: 450)
            let cx = x < -60 ? x + 450 : x
            let y = 60 + CGFloat((i * 53) % 120)
            context.fill(Path(roundedRect: CGRect(x: cx, y: y, width: 58, height: 18), cornerRadius: 9), with: .color(.white.opacity(0.18)))
            context.fill(Path(ellipseIn: CGRect(x: cx + 12, y: y - 10, width: 28, height: 24)), with: .color(.white.opacity(0.18)))
        }
        for i in 0..<6 {
            let x = (CGFloat(i) * 80 - engine.scroll * 0.4).truncatingRemainder(dividingBy: 480)
            let hx = x < -80 ? x + 480 : x
            context.fill(Path(ellipseIn: CGRect(x: hx - 20, y: 400, width: 140, height: 120)), with: .color(Color(red: 0.2, green: 0.45, blue: 0.35).opacity(0.7)))
        }
        for body in engine.bodies {
            let r = body.rect
            let gradient = GraphicsContext.Shading.linearGradient(Gradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.35), Color(red: 0.55, green: 0.95, blue: 0.55), Color(red: 0.15, green: 0.55, blue: 0.3)]),
                                                                  startPoint: CGPoint(x: r.minX, y: 0), endPoint: CGPoint(x: r.maxX, y: 0))
            context.fill(Path(CGRect(x: r.minX + 3, y: -10, width: r.width - 6, height: max(0, r.minY + 10))), with: gradient)
            context.fill(Path(CGRect(x: r.minX + 3, y: r.maxY, width: r.width - 6, height: max(0, 480 - r.maxY))), with: gradient)
            context.fill(Path(roundedRect: CGRect(x: r.minX - 2, y: r.minY - 16, width: r.width + 4, height: 16), cornerRadius: 3), with: gradient)
            context.fill(Path(roundedRect: CGRect(x: r.minX - 2, y: r.maxY, width: r.width + 4, height: 16), cornerRadius: 3), with: gradient)
            if body.speed > 0 {
                context.stroke(Path(roundedRect: CGRect(x: r.minX - 2, y: r.minY - 16, width: r.width + 4, height: 16), cornerRadius: 3), with: .color(.yellow.opacity(0.7)), lineWidth: 1.5)
                context.stroke(Path(roundedRect: CGRect(x: r.minX - 2, y: r.maxY, width: r.width + 4, height: 16), cornerRadius: 3), with: .color(.yellow.opacity(0.7)), lineWidth: 1.5)
            }
        }
        for coin in engine.coins {
            let squash = abs(cos(engine.time * 4 + coin.y))
            context.fill(Path(ellipseIn: CGRect(x: coin.x - 9 * squash, y: coin.y - 9, width: 18 * squash, height: 18)), with: .color(.yellow))
            context.stroke(Path(ellipseIn: CGRect(x: coin.x - 6 * squash, y: coin.y - 6, width: 12 * squash, height: 12)), with: .color(.orange), lineWidth: 1.5)
        }
        // Ground strip.
        context.fill(Path(CGRect(x: 0, y: 462, width: 320, height: 18)), with: .color(Color(red: 0.55, green: 0.4, blue: 0.25)))
        for i in 0..<12 {
            let x = (CGFloat(i) * 30 - engine.scroll).truncatingRemainder(dividingBy: 360)
            context.fill(Path(CGRect(x: x < -30 ? x + 360 : x, y: 462, width: 14, height: 4)), with: .color(.green.opacity(0.8)))
        }
        // Bird tilts with its velocity and flaps its wing.
        var bird = context
        bird.translateBy(x: engine.player.x, y: engine.player.y)
        bird.rotate(by: .radians(Double(min(1.1, max(-0.5, engine.velocity.dy / 420)))))
        bird.fill(Path(ellipseIn: CGRect(x: -13, y: -10, width: 26, height: 20)),
                  with: .radialGradient(Gradient(colors: [.yellow, .orange]), center: CGPoint(x: -3, y: -4), startRadius: 1, endRadius: 16))
        let wing = engine.flap > 0 ? -6 * engine.flap : 2 * CGFloat(sin(Double(engine.time) * 12))
        bird.fill(Path(ellipseIn: CGRect(x: -11, y: -2 + wing, width: 13, height: 8)), with: .color(.white.opacity(0.9)))
        bird.fill(Path(ellipseIn: CGRect(x: 2, y: -8, width: 8, height: 8)), with: .color(.white))
        bird.fill(Path(ellipseIn: CGRect(x: 5.5, y: -6, width: 3.5, height: 4)), with: .color(.black))
        var beak = Path(); beak.move(to: CGPoint(x: 10, y: -1)); beak.addLine(to: CGPoint(x: 18, y: 2)); beak.addLine(to: CGPoint(x: 10, y: 5)); beak.closeSubpath()
        bird.fill(beak, with: .color(.orange))
    }

    // MARK: Road Hop

    private func drawRoad(_ context: inout GraphicsContext) {
        for lane in engine.visibleRoadRows where lane.y > -30 && lane.y < 510 {
            let rect = CGRect(x: 0, y: lane.y - 25, width: 320, height: 50)
            if engine.isGrassRow(lane.row) {
                context.fill(Path(rect), with: .color(Color(red: 0.2, green: lane.row.isMultiple(of: 2) ? 0.5 : 0.46, blue: 0.28)))
                for i in 0..<5 {
                    let x = CGFloat((lane.row * 37 + i * 71) % 300) + 10
                    context.fill(Path(ellipseIn: CGRect(x: x, y: lane.y - 6 + CGFloat(i % 3) * 6, width: 6, height: 4)), with: .color(.green.opacity(0.6)))
                }
            } else {
                context.fill(Path(rect), with: .color(Color(white: 0.2)))
                if !engine.isGrassRow(lane.row + 1) {
                    for x in stride(from: 6, to: 320, by: 40) {
                        context.fill(Path(CGRect(x: CGFloat(x), y: lane.y - 26, width: 20, height: 2)), with: .color(.white.opacity(0.45)))
                    }
                }
            }
        }
        for coin in engine.coins {
            let bob = CGFloat(sin(Double(engine.time) * 4 + Double(coin.x))) * 2
            ball(&context, CGPoint(x: coin.x, y: coin.y + bob), 8, .yellow)
            ball(&context, CGPoint(x: coin.x, y: coin.y + bob), 4.5, .orange)
        }
        for car in engine.bodies {
            let r = car.rect
            let color = car.value < 0 ? Color(red: 0.85, green: 0.45, blue: 0.2) : carColors[abs(car.value) % carColors.count]
            for wx in [r.minX + 10, r.maxX - 20] {
                context.fill(Path(roundedRect: CGRect(x: wx, y: r.minY - 3, width: 10, height: 5), cornerRadius: 2), with: .color(.black))
                context.fill(Path(roundedRect: CGRect(x: wx, y: r.maxY - 2, width: 10, height: 5), cornerRadius: 2), with: .color(.black))
            }
            context.fill(Path(roundedRect: r, cornerRadius: 7), with: .color(color))
            if car.value < 0 {
                let cab = car.speed > 0 ? CGRect(x: r.maxX - 24, y: r.minY + 3, width: 20, height: r.height - 6) : CGRect(x: r.minX + 4, y: r.minY + 3, width: 20, height: r.height - 6)
                context.fill(Path(roundedRect: cab, cornerRadius: 4), with: .color(.white.opacity(0.35)))
            } else {
                context.fill(Path(roundedRect: CGRect(x: r.midX - 13, y: r.minY + 5, width: 26, height: r.height - 10), cornerRadius: 5), with: .color(.black.opacity(0.35)))
            }
            let front = car.speed > 0 ? r.maxX - 3 : r.minX + 1
            context.fill(Path(ellipseIn: CGRect(x: front, y: r.minY + 4, width: 3, height: 5)), with: .color(.yellow))
            context.fill(Path(ellipseIn: CGRect(x: front, y: r.maxY - 9, width: 3, height: 5)), with: .color(.yellow))
        }
        // Hopper with a small arc and squash while jumping.
        let progress = engine.hopTimer / 0.14
        let lift = sin(progress * .pi) * 8
        let p = CGPoint(x: engine.player.x, y: engine.player.y - lift)
        ball(&context, CGPoint(x: engine.player.x, y: engine.player.y + 9), 9 - lift * 0.4, .black.opacity(0.3))
        let w: CGFloat = 22 - lift * 0.4, h: CGFloat = 22 + lift * 0.5
        context.fill(Path(roundedRect: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), cornerRadius: 7), with: .color(.white))
        context.fill(Path(roundedRect: CGRect(x: p.x - 4, y: p.y - h / 2 - 4, width: 8, height: 6), cornerRadius: 2), with: .color(.red))
        let eyeX = p.x + engine.facing * 3
        ball(&context, CGPoint(x: eyeX - 4, y: p.y - 3), 2, .black)
        ball(&context, CGPoint(x: eyeX + 4, y: p.y - 3), 2, .black)
        context.fill(Path(CGRect(x: p.x - 3, y: p.y + 1, width: 6, height: 4)), with: .color(.orange))
    }
}
