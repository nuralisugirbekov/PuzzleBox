import SwiftUI

/// Shared wrapper for every mini-game: header with close/pause/restart and
/// score display, plus the pause and game-over overlays. Records finished
/// rounds into `StatsStore` automatically.
struct GameContainerView<Engine: GameEngine, Content: View>: View {
    let gameID: GameID
    let engine: Engine
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats
    @Environment(\.scenePhase) private var scenePhase
    @State private var isNewHighScore = false
    @State private var roundAnalytics = GameRoundAnalytics()
    @State private var hasStartedRound = false

    private var info: GameInfo { gameID.info }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                // Games sit at the bottom of the screen, within thumb reach;
                // the flexible space stays between the header and the play area.
                Spacer(minLength: 0)
                content()
            }
            .padding()

            if engine.state == .paused {
                PauseOverlay(resume: {
                                 roundAnalytics.event("game_resume", score: engine.score)
                                 engine.state = .playing
                             },
                             restart: restart,
                             exit: { dismiss() })
            }

            if case .gameOver(let won) = engine.state {
                GameOverOverlay(won: won,
                                score: engine.score,
                                highScore: stats.highScore(for: gameID),
                                isNewHighScore: isNewHighScore,
                                playAgain: restart,
                                mainMenu: { dismiss() })
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: engine.state)
        .onAppear {
            AppAnalytics.screen("game_\(gameID.rawValue)")
            if !hasStartedRound {
                hasStartedRound = true
                roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
            }
        }
        .onDisappear {
            roundAnalytics.finish(score: engine.score, reason: "exit")
        }
        .onChange(of: scenePhase) { _, phase in
            roundAnalytics.setActive(phase == .active && engine.state == .playing)
        }
        .onChange(of: engine.state) { _, newState in
            roundAnalytics.setActive(scenePhase == .active && newState == .playing)
            if newState == .paused {
                roundAnalytics.event("game_pause", score: engine.score)
            }
            if case .gameOver(let won) = newState {
                isNewHighScore = stats.record(gameID, score: engine.score)
                roundAnalytics.finish(score: engine.score, reason: "completed",
                                      won: won, newRecord: isNewHighScore)
                if won { Haptics.success() } else { Haptics.error() }
            }
        }
    }

    private func restart() {
        Haptics.tap()
        let wasPaused = engine.state == .paused
        let wasCompleted: Bool
        if case .gameOver = engine.state { wasCompleted = true } else { wasCompleted = false }
        AppAnalytics.log("game_restart", parameters: [
            "game_id": gameID.rawValue,
            "restart_source": wasCompleted ? "game_over" : (wasPaused ? "pause" : "header")
        ])
        roundAnalytics.finish(score: engine.score, reason: "restart")
        isNewHighScore = false
        engine.restart()
        roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
    }

    private var header: some View {
        HStack(spacing: 12) {
            headerButton("xmark") { dismiss() }

            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Label("\(stats.highScore(for: gameID))", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.yellow)
            }

            Spacer()

            Text("\(engine.score)")
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Theme.neon.opacity(0.15), in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.neon.opacity(0.35), lineWidth: 1) }
                .foregroundStyle(Theme.neon)

            headerButton("pause.fill") {
                if engine.state == .playing {
                    Haptics.tap()
                    engine.state = .paused
                }
            }
            .disabled(engine.state != .playing)

            headerButton("arrow.counterclockwise") { restart() }
        }
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
                .overlay { Circle().strokeBorder(Theme.stroke, lineWidth: 1) }
        }
    }
}

// MARK: - Overlay chrome

private struct OverlayCard<CardContent: View>: View {
    @ViewBuilder let content: () -> CardContent

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18, content: content)
                .padding(28)
                .frame(maxWidth: 320)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
                .padding(32)
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.neon, in: RoundedRectangle(cornerRadius: 14))
                .neonGlow()
        }
    }
}

private struct SecondaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
        }
    }
}

// MARK: - Pause overlay

struct PauseOverlay: View {
    let resume: () -> Void
    let restart: () -> Void
    let exit: () -> Void

    var body: some View {
        OverlayCard {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.neon)
            Text(L10n.text("Paused"))
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                PrimaryButton(title: L10n.text("Resume"), symbol: "play.fill", action: resume)
                SecondaryButton(title: L10n.text("Restart"), symbol: "arrow.counterclockwise", action: restart)
                SecondaryButton(title: L10n.text("Main Menu"), symbol: "house.fill", action: exit)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Victory / game over overlay

struct GameOverOverlay: View {
    let won: Bool
    let score: Int
    let highScore: Int
    let isNewHighScore: Bool
    let playAgain: () -> Void
    let mainMenu: () -> Void

    var body: some View {
        OverlayCard {
            Text(won ? "🏆" : "💥")
                .font(.system(size: 56))
            Text(won ? L10n.text("You Win!") : L10n.text("Game Over"))
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                Text(L10n.text("Score"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.neon)
                if isNewHighScore {
                    Label(L10n.text("New High Score!"), systemImage: "trophy.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.yellow)
                } else {
                    Text(L10n.format("Best: %d", highScore))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(spacing: 10) {
                PrimaryButton(title: L10n.text("Play Again"), symbol: "arrow.counterclockwise", action: playAgain)
                SecondaryButton(title: L10n.text("Main Menu"), symbol: "house.fill", action: mainMenu)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
