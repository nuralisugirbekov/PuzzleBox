import SwiftUI

/// Shared wrapper for every mini-game: header with close/pause/restart and
/// score display, plus the pause and game-over overlays. Records finished
/// rounds into `StatsStore` automatically.
struct GameContainerView<Engine: GameEngine, Content: View>: View {
    let gameID: GameID
    let engine: Engine
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    var centersContent = false
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats
    @Environment(\.scenePhase) private var scenePhase
    @State private var isNewHighScore = false
    @State private var roundAnalytics = GameRoundAnalytics()
    @State private var hasStartedRound = false
    @State private var cardClock = CardRoundClock()
    @State private var finalScore: Int?
    @State private var awardedTimeBonus = 0

    private var hasCardTimer: Bool {
        switch gameID {
        case .solitaire, .spiderSolitaire, .freecell: true
        default: false
        }
    }

    private var displayedScore: Int { finalScore ?? engine.score }

    private var summary: String? {
        guard hasCardTimer else { return resultSummary }
        return L10n.format("Time: %@ · Bonus: +%d", cardClock.formattedTime, awardedTimeBonus)
    }

    private var info: GameInfo { gameID.info }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 12) {
                header
                if hasCardTimer {
                    HStack {
                        Label(cardClock.formattedTime, systemImage: "timer")
                            .monospacedDigit()
                        Spacer()
                        Text(L10n.format("Win bonus: +%d", cardClock.victoryBonus))
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.neon)
                }
                // An optional matching lower spacer centers the play area below the header.
                Spacer(minLength: 0)
                content()
                if centersContent {
                    Spacer(minLength: 0)
                }
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
                                score: displayedScore,
                                highScore: stats.highScore(for: gameID),
                                isNewHighScore: isNewHighScore,
                                resultTitle: resultTitle,
                                resultSummary: summary,
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
                if hasCardTimer { cardClock.reset(active: scenePhase == .active && engine.state == .playing) }
                roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
            }
        }
        .onDisappear {
            cardClock.setActive(false)
            roundAnalytics.finish(score: displayedScore, reason: "exit")
        }
        .onChange(of: scenePhase) { _, phase in
            if hasCardTimer { cardClock.setActive(phase == .active && engine.state == .playing) }
            roundAnalytics.setActive(phase == .active && engine.state == .playing)
        }
        .onChange(of: engine.state) { _, newState in
            if hasCardTimer { cardClock.setActive(scenePhase == .active && newState == .playing) }
            roundAnalytics.setActive(scenePhase == .active && newState == .playing)
            if newState == .paused {
                roundAnalytics.event("game_pause", score: engine.score)
            }
            if case .gameOver(let won) = newState {
                awardedTimeBonus = hasCardTimer && won ? cardClock.victoryBonus : 0
                let total = engine.score + awardedTimeBonus
                finalScore = total
                isNewHighScore = stats.record(gameID, score: total)
                roundAnalytics.finish(score: total, reason: "completed",
                                      won: won, newRecord: isNewHighScore,
                                      timeBonus: hasCardTimer ? awardedTimeBonus : nil)
                if won { Haptics.success() } else { Haptics.error() }
            }
        }
        .task {
            guard hasCardTimer else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
                cardClock.tick()
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
        roundAnalytics.finish(score: displayedScore, reason: "restart")
        isNewHighScore = false
        finalScore = nil
        awardedTimeBonus = 0
        if hasCardTimer { cardClock.reset(active: scenePhase == .active) }
        engine.restart()
        // Timed challenges return to setup; their new container starts the next round.
        if gameID != .checkmate && gameID != .quickMath {
            roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
        }
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

            Text("\(displayedScore)")
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
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    let playAgain: () -> Void
    let mainMenu: () -> Void

    var body: some View {
        OverlayCard {
            Text(won ? "🏆" : "💥")
                .font(.system(size: 56))
            Text(resultTitle ?? (won ? L10n.text("You Win!") : L10n.text("Game Over")))
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            VStack(spacing: 6) {
                if let resultSummary {
                    Text(resultSummary)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
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
