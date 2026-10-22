import SwiftUI
import SpriteKit

struct ArrowMazeView: View {
    @State private var engine = ArrowMazeEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .arrowMaze, engine: engine,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 12) {
                HStack {
                    Menu {
                        ForEach(ArrowMazeLevel.all.indices, id: \.self) { index in
                            Button(L10n.format("Level %d", index + 1)) { engine.selectLevel(index) }
                        }
                    } label: {
                        Label(L10n.format("Level %d of %d", engine.levelIndex + 1, ArrowMazeLevel.all.count), systemImage: "square.grid.2x2")
                    }
                    Spacer()
                    Label(String(format: "×%.1f", engine.speedMultiplier), systemImage: "speedometer")
                        .monospacedDigit()
                        .foregroundStyle(engine.speedMultiplier > 1.01 ? Color.orange : GameTheme.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: engine.speedMultiplier)
                    Label("\(engine.collectedCount)/\(engine.level.gemCells.count)", systemImage: "star.fill")
                        .monospacedDigit().foregroundStyle(Color.yellow)
                }.font(.subheadline.weight(.semibold))
                ArrowMazeSurface(engine: engine, reduceMotion: reduceMotion)
                    .arenaFit(360.0 / 460, stretch: 0.3)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay {
                        if !engine.started {
                            Button { engine.start() } label: {
                                Label(L10n.text("Tap to start"), systemImage: "play.fill")
                                    .font(.headline).padding(20)
                                    .background(.regularMaterial, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    .accessibilityLabel(L10n.text("Rocket Maze"))
                HStack(spacing: 12) {
                    turnButton(.left, title: "Turn left", symbol: "arrow.turn.up.left")
                    turnButton(.right, title: "Turn right", symbol: "arrow.turn.up.right")
                }
                Text(L10n.text(engine.collectedCount == engine.level.gemCells.count ? "Portal open! Fly into it." : "Collect every star. Each one speeds up the rocket."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .id(engine.levelIndex)
        .onAppear { engine.setActive(scenePhase == .active) }
        .onDisappear { engine.setActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setActive(phase == .active) }
    }

    private func turnButton(_ turn: ArrowMazeTurn, title: String, symbol: String) -> some View {
        Button { engine.turn(turn) } label: {
            Label(L10n.text(title), systemImage: symbol)
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                .background(GameTheme.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!engine.canAdvance)
    }
}

/// UIKit bridge gives explicit control over render-loop suspension and teardown.
private struct ArrowMazeSurface: UIViewRepresentable {
    let engine: ArrowMazeEngine
    let reduceMotion: Bool

    final class Coordinator {
        let scene: ArrowMazeScene
        init(engine: ArrowMazeEngine) { scene = ArrowMazeScene(engine: engine) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(engine: engine) }
    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.isOpaque = true
        view.backgroundColor = .black
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.isMultipleTouchEnabled = false
        context.coordinator.scene.reduceMotion = reduceMotion
        view.presentScene(context.coordinator.scene)
        view.isPaused = !Self.isRunning(engine)
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        let scene = context.coordinator.scene
        scene.reduceMotion = reduceMotion
        scene.synchronizeLevel()
        let paused = !Self.isRunning(engine)
        if view.isPaused != paused { scene.resetFrameClock() }
        view.isPaused = paused
    }
    /// Keeps rendering after a crash so the explosion plays under the overlay.
    private static func isRunning(_ engine: ArrowMazeEngine) -> Bool {
        engine.active && engine.state != .paused
    }
    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        view.isPaused = true
        coordinator.scene.detach()
        view.presentScene(nil)
    }
}
