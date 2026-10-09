import SwiftUI

struct ActionCollectionView: View {
    @State private var engine: ActionCollectionEngine
    @Environment(\.scenePhase) private var scenePhase
    init(mode: ActionMode) { _engine = State(initialValue: ActionCollectionEngine(mode: mode)) }

    var body: some View {
        GameContainerView(gameID: engine.mode.id, engine: engine,
                          resultSummary: engine.mode == .chainReaction ? L10n.format("Destroyed: %d / %d", engine.progress, 20) : nil,
                          centersContent: true) {
            VStack(spacing: 12) {
                HStack {
                    if engine.timed {
                        Label(String(format: "0:%02d", Int(ceil(engine.timeLeft))), systemImage: "timer")
                    }
                    Spacer()
                    if [.bubblePop, .whackMole].contains(engine.mode) { Text(L10n.format("Lives: %d", engine.lives)) }
                    if engine.mode == .chainReaction { Text(L10n.format("Destroyed: %d / %d", engine.progress, 20)) }
                    if engine.mode == .redGreen { Text(verbatim: "\(engine.progress) / 30") }
                    if engine.mode == .perfectTiming { Text(verbatim: "\(engine.progress) / 10") }
                }
                .font(.headline.monospacedDigit()).foregroundStyle(GameTheme.accent)
                GeometryReader { geometry in
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 460)
                        draw(&context)
                    }
                    .background(GameTheme.arena, in: RoundedRectangle(cornerRadius: 24))
                    .environment(\.colorScheme, .dark)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        if !engine.started {
                            Text(L10n.text("Tap to start")).font(.title2.bold())
                                .padding(24).background(GameTheme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                                .foregroundStyle(GameTheme.accent).allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            engine.drag(CGPoint(x: value.location.x / geometry.size.width * 320, y: value.location.y / geometry.size.height * 460))
                        }
                        .onEnded { value in
                            if !engine.started || max(abs(value.translation.width), abs(value.translation.height)) < 20 {
                                engine.tap(CGPoint(x: value.location.x / geometry.size.width * 320, y: value.location.y / geometry.size.height * 460))
                            }
                        })
                }
                .aspectRatio(320.0 / 460, contentMode: .fit).frame(maxWidth: 380, maxHeight: 460)
                Text(L10n.text(engine.mode.hint)).font(.footnote).multilineTextAlignment(.center)
                    .foregroundStyle(GameTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
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
                engine.advance(now - last); last = now
            }
        }
    }

    private func draw(_ context: inout GraphicsContext) {
        func circle(_ p: CGPoint, _ r: CGFloat, _ color: Color, stroke: Bool = false) {
            let path = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            if stroke { context.stroke(path, with: .color(color), lineWidth: 3) }
            else { context.fill(path, with: .color(color)) }
        }
        func box(_ rect: CGRect, _ color: Color) {
            context.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(color))
        }
        switch engine.mode {
        case .circleJump:
            circle(CGPoint(x: 160, y: 215), 105, GameTheme.textSecondary, stroke: true)
            for p in engine.particles {
                let a = CGFloat(p.kind) / 1000
                circle(CGPoint(x: 160 + cos(a) * 105, y: 215 + sin(a) * 105), 11, .red)
            }
            circle(engine.jumpPosition, 9, GameTheme.accent)
        case .dash:
            box(CGRect(x: 0, y: 390, width: 320, height: 4), .gray)
            for p in engine.particles {
                var path = Path(); path.move(to: CGPoint(x: p.p.x - p.radius, y: 390))
                path.addLine(to: CGPoint(x: p.p.x, y: 390 - 2 * p.radius)); path.addLine(to: CGPoint(x: p.p.x + p.radius, y: 390)); path.closeSubpath()
                context.fill(path, with: .color(.pink))
            }
            box(CGRect(x: engine.player.x - 12, y: 366 - engine.altitude, width: 24, height: 24), GameTheme.accent)
        case .darkTiles:
            for row in 0..<4 {
                for col in 0..<4 {
                    box(CGRect(x: CGFloat(col * 80 + 2), y: CGFloat(row * 100 + 22), width: 76, height: 96), engine.tiles[row] == col ? .indigo : Color.white.opacity(0.9))
                }
            }
            context.stroke(Path(CGRect(x: 1, y: 320, width: 318, height: 102)), with: .color(GameTheme.accent), lineWidth: 3)
        case .redGreen:
            let color: Color = engine.signal == 1 ? .green : engine.signal == 2 ? .yellow : .red
            circle(CGPoint(x: 160, y: 95), 55, color)
            context.draw(Text(L10n.text(engine.signal == 1 ? "Go!" : "Stop!" )).font(.title.bold()).foregroundStyle(.white), at: CGPoint(x: 160, y: 185))
            box(CGRect(x: 140, y: 230, width: 40, height: 195), GameTheme.surfaceHigh)
            box(CGRect(x: 135, y: 230, width: 50, height: 6), .white)
            circle(CGPoint(x: 160, y: 420 - CGFloat(engine.progress) / 30 * 180), 13, GameTheme.accent)
        case .perfectTiming:
            box(CGRect(x: 20, y: 195, width: 280, height: 70), GameTheme.surfaceHigh)
            let half = max(12, 30 - CGFloat(engine.progress))
            box(CGRect(x: engine.zone - half, y: 195, width: half * 2, height: 70), GameTheme.accent.opacity(0.6))
            box(CGRect(x: engine.marker - 3, y: 183, width: 6, height: 94), .white)
        case .bubblePop:
            for p in engine.particles {
                circle(p.p, p.radius, Color.cyan.opacity(max(0.15, 1 - p.age / p.life)))
                circle(p.p, p.radius * 0.7, .white.opacity(0.5), stroke: true)
            }
        case .whackMole:
            for i in 0..<9 {
                let p = CGPoint(x: CGFloat(i % 3) * 106.66 + 53.33, y: CGFloat(i / 3) * 110 + 115)
                circle(p, 38, GameTheme.surfaceHigh)
                if engine.mole == i {
                    circle(p, 28, .orange)
                    circle(CGPoint(x: p.x - 9, y: p.y - 4), 3, .black)
                    circle(CGPoint(x: p.x + 9, y: p.y - 4), 3, .black)
                }
            }
        case .avoid:
            for p in engine.particles { circle(p.p, p.radius, .pink) }
            circle(engine.player, 8, GameTheme.accent)
        case .zigZag:
            var path = Path()
            if let first = engine.path.first { path.move(to: first) }
            for point in engine.path.dropFirst() { path.addLine(to: point) }
            context.stroke(path, with: .color(.cyan.opacity(0.5)), style: StrokeStyle(lineWidth: 40, lineCap: .round, lineJoin: .round))
            box(CGRect(x: engine.player.x - 7, y: engine.player.y - 7, width: 14, height: 14), GameTheme.accent)
        case .chainReaction:
            for p in engine.particles { circle(p.p, p.radius, .cyan) }
            for p in engine.blasts { circle(p.p, p.radius, GameTheme.accent.opacity(0.35)); circle(p.p, p.radius, GameTheme.accent, stroke: true) }
        case .orbit:
            circle(CGPoint(x: 160, y: 220), 75, GameTheme.textSecondary, stroke: true)
            circle(CGPoint(x: 160, y: 220), 125, GameTheme.textSecondary, stroke: true)
            for p in engine.particles {
                let radius: CGFloat = p.kind == 0 ? 75 : 125
                circle(CGPoint(x: 160 + cos(CGFloat(p.age)) * radius, y: 220 + sin(CGFloat(p.age)) * radius), 11, .pink)
            }
            circle(engine.orbitPosition, 8, GameTheme.accent)
        }
    }
}
