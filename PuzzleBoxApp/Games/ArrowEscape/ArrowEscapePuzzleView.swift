import SwiftUI

struct ArrowEscapePuzzleView: View {
    @State private var engine = ArrowEscapePuzzleEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let palette = ToyPuzzles.world(top: (0.94, 0.97, 0.86), bottom: (0.82, 0.92, 0.70),
                                          darkTop: (0.11, 0.16, 0.09), darkBottom: (0.05, 0.09, 0.05),
                                          tray: (1.0, 0.98, 0.93), darkTray: (0.20, 0.24, 0.18),
                                          ink: (0.22, 0.34, 0.16), accent: (0.95, 0.42, 0.36), darkAccent: (1.0, 0.5, 0.42))

    var body: some View {
        let palette = Self.palette
        GameContainerView(gameID: .arrowEscape, engine: engine,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          showsClock: false,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
          ToyGameStage(palette: palette, headline: .score, trailing: { lives }) {
            VStack(spacing: 10) {
                HStack {
                    Menu {
                        ForEach(0..<ArrowEscapePuzzle.levelCount, id: \.self) { index in
                            Button(L10n.format("Level %d", index + 1)) { engine.selectLevel(index) }
                        }
                    } label: {
                        ToyMenuChip(color: palette.card, ink: palette.ink) {
                            Text(L10n.format("Level %d of %d", engine.levelIndex + 1, ArrowEscapePuzzle.levelCount))
                        }
                    }
                    Spacer()
                    ToyChip(color: palette.card) {
                        Label { Text(verbatim: "\(engine.onBoardCount)/\(engine.puzzle.arrows.count)").monospacedDigit() }
                            icon: { Image(systemName: "arrow.up.right").foregroundStyle(palette.accent) }
                            .foregroundStyle(palette.ink)
                    }
                    .accessibilityLabel(L10n.format("Arrows remaining: %d", engine.onBoardCount))
                }
                // A blocked arrow turns red on the board.
                ArrowEscapeBoard(engine: engine, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toyTray(palette.tray, cornerRadius: 26, padding: 6)
            }
            .padding(.top, 12)
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
        HStack(spacing: 3) {
            ForEach(0..<ArrowEscapePuzzleEngine.maxLives, id: \.self) { index in
                Image(systemName: "heart.fill")
                    .foregroundStyle(index < engine.lives ? Self.palette.accent : Self.palette.ink.opacity(0.18))
                    .symbolEffect(.bounce, value: engine.lives)
            }
        }
        .font(.subheadline.weight(.bold))
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
    }
}

/// The board as it looks in play, for the Home preview.
struct ArrowEscapeShowcase: View {
    let engine: ArrowEscapePuzzleEngine

    var body: some View {
        let palette = ArrowEscapePuzzleView.palette
        ZStack {
            palette.backdrop
            ArrowEscapeBoard(engine: engine, reduceMotion: true, showsZoomControls: false)
                .toyTray(palette.tray, cornerRadius: 24, padding: 6)
                .padding(24)
        }
        .environment(\.toyStyle, palette.style)
        .frame(width: 360, height: 360)
    }
}
