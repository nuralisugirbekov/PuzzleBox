import SwiftUI

struct ArcadeView: View {
    @State private var engine: ArcadeEngine
    @Environment(\.scenePhase) private var scenePhase
    private let colors: [Color] = [.cyan, .pink, .yellow, .purple, .orange, .mint]

    init(mode: ArcadeMode) { _engine = State(initialValue: ArcadeEngine(mode: mode)) }

    var body: some View {
        GameContainerView(gameID: engine.mode.gameID, engine: engine, centersContent: true) {
            VStack(spacing: 12) {
                if engine.mode == .pong {
                    Text(L10n.format("You %d — Bot %d", engine.score, engine.opponentScore))
                        .font(.headline).foregroundStyle(GameTheme.accent)
                } else if engine.mode == .brickBreaker {
                    Text(L10n.format("Lives: %d", engine.lives)).foregroundStyle(GameTheme.accent)
                } else if engine.mode == .knifeSpin {
                    Text(L10n.format("Level %d · Remaining: %d", engine.level, engine.remainingPins))
                        .foregroundStyle(GameTheme.accent)
                }
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 480)
                        draw(in: &context)
                    }
                    .background(GameTheme.arena, in: RoundedRectangle(cornerRadius: 24))
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
        func box(_ rect: CGRect, _ color: Color) {
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color))
        }
        func ball(_ p: CGPoint, radius: CGFloat = 10, color: Color = GameTheme.accent) {
            context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }
        switch engine.mode {
        case .stack:
            for body in engine.bodies { box(body.rect, colors[body.value % colors.count]) }
            for body in engine.debris { box(body.rect, .red.opacity(0.7)) }
            box(engine.movingBlock, GameTheme.accent)
        case .colorJump:
            let shift = (engine.angle * 70).truncatingRemainder(dividingBy: 320)
            for i in -4..<9 {
                let x = CGFloat(i) * 80 - shift
                box(CGRect(x: x, y: engine.gateY - 5, width: 80, height: 10), colors[(i % 4 + 4) % 4])
            }
            ball(engine.player, color: colors[engine.colorIndex])
            box(CGRect(x: 0, y: 462, width: 320, height: 4), GameTheme.surfaceHigh)
        case .knifeSpin:
            ball(CGPoint(x: 160, y: 180), radius: 80, color: .orange)
            ball(CGPoint(x: 160, y: 180), radius: 64, color: GameTheme.surfaceHigh)
            for pin in engine.pins {
                let a = pin + engine.angle
                var line = Path()
                line.move(to: CGPoint(x: 160 + cos(a) * 74, y: 180 + sin(a) * 74))
                line.addLine(to: CGPoint(x: 160 + cos(a) * 112, y: 180 + sin(a) * 112))
                context.stroke(line, with: .color(GameTheme.accent), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            box(CGRect(x: 157, y: engine.projectile ?? 425, width: 6, height: 30), .white)
        case .helixDrop:
            box(CGRect(x: 155, y: 0, width: 10, height: 480), GameTheme.surfaceHigh)
            for body in engine.bodies {
                // Unwrapped circular platforms: the gap wraps seamlessly across the edges.
                for x in stride(from: CGFloat(0), to: 320, by: 4) {
                    let relative = (x - body.rect.minX + 320).truncatingRemainder(dividingBy: 320)
                    if relative >= body.rect.width {
                        box(CGRect(x: x, y: body.rect.minY, width: 5, height: 12), relative > 200 && relative < 265 ? .red : .cyan)
                    }
                }
            }
            ball(engine.player)
        case .skyJump:
            for body in engine.bodies { box(body.rect, .mint) }
            ball(engine.player, radius: 11)
        case .flappyFlight:
            for body in engine.bodies {
                box(CGRect(x: body.rect.minX, y: 0, width: body.rect.width, height: max(0, body.rect.midY - 72.5)), .mint)
                box(CGRect(x: body.rect.minX, y: body.rect.midY + 72.5, width: body.rect.width, height: max(0, 480 - body.rect.midY - 72.5)), .mint)
            }
            ball(engine.player, radius: 10, color: .yellow)
            ball(CGPoint(x: engine.player.x + 4, y: engine.player.y - 3), radius: 2, color: .black)
        case .brickBreaker, .pong:
            if engine.mode == .brickBreaker {
                for body in engine.bodies { box(body.rect, colors[body.value % colors.count]) }
            } else {
                box(CGRect(x: engine.opponent - 40, y: 32, width: 80, height: 8), .pink)
                for x in stride(from: 0, to: 320, by: 20) { box(CGRect(x: CGFloat(x), y: 239, width: 9, height: 2), GameTheme.textSecondary.opacity(0.4)) }
            }
            box(CGRect(x: engine.paddle - 40, y: 440, width: 80, height: 8), GameTheme.accent)
            ball(engine.player, radius: 7, color: .white)
        case .roadHop:
            let lanes = Set(engine.bodies.map { Int($0.rect.midY) })
            for y in lanes {
                box(CGRect(x: 0, y: CGFloat(y - 23), width: 320, height: 46), GameTheme.surfaceHigh)
                for x in stride(from: 0, to: 320, by: 40) { box(CGRect(x: CGFloat(x), y: CGFloat(y), width: 14, height: 1), GameTheme.textSecondary.opacity(0.3)) }
            }
            for car in engine.bodies {
                box(car.rect, colors[car.value % colors.count])
                box(CGRect(x: car.rect.midX - 10, y: car.rect.minY + 4, width: 20, height: 24), GameTheme.background.opacity(0.5))
            }
            box(CGRect(x: engine.player.x - 11, y: engine.player.y - 11, width: 22, height: 22), GameTheme.accent)
        }
        if engine.flash > 0 {
            context.stroke(Path(roundedRect: CGRect(x: 2, y: 2, width: 316, height: 476), cornerRadius: 16),
                           with: .color(GameTheme.accent.opacity(engine.flash * 3)), lineWidth: 3)
        }
    }
}
