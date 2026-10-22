import SwiftUI

struct ArrowEscapePuzzleView: View {
    @State private var engine = ArrowEscapePuzzleEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .arrowEscape, engine: engine,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          showsClock: false, headerAccessory: AnyView(lives), fullBleed: true) {
            VStack(spacing: 8) {
                HStack {
                    Menu {
                        ForEach(0..<ArrowEscapePuzzle.levelCount, id: \.self) { index in
                            Button(L10n.format("Level %d", index + 1)) { engine.selectLevel(index) }
                        }
                    } label: {
                        Label(L10n.format("Level %d of %d", engine.levelIndex + 1, ArrowEscapePuzzle.levelCount), systemImage: "square.grid.3x3")
                    }
                    Spacer()
                    Text("\(engine.onBoardCount)/\(engine.puzzle.arrows.count)")
                        .monospacedDigit()
                        .accessibilityLabel(L10n.format("Arrows remaining: %d", engine.onBoardCount))
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                // The board runs to the screen's edges; a blocked arrow turns red on it.
                ArrowEscapeBoard(engine: engine, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .id(engine.levelIndex)
        .onAppear { engine.setActive(scenePhase == .active) }
        .onDisappear { engine.setActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setActive(phase == .active) }
        .task(id: engine.animationToken) {
            // Only keep a clock while arrows are leaving. Cancellation on restart,
            // level change or dismissal cannot remove an arrow from a new board.
            // Step by real elapsed time: sleep overshoots, and a fixed 16 ms step stutters.
            let clock = ContinuousClock()
            var last = clock.now
            while !engine.moving.isEmpty && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
                guard !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                engine.advanceAnimation(Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds),
                                        reduceMotion: reduceMotion)
            }
        }
    }

    /// Lives, shown in the header between the score and the best score.
    private var lives: some View {
        HStack(spacing: 6) {
            ForEach(0..<ArrowEscapePuzzleEngine.maxLives, id: \.self) { index in
                Image(systemName: index < engine.lives ? "heart.fill" : "heart")
                    .foregroundStyle(index < engine.lives ? Color.red : GameTheme.textSecondary)
                    .symbolEffect(.bounce, value: engine.lives)
            }
        }
        .font(.title3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
    }
}
