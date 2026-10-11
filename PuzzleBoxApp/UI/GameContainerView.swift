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
    var nextLevel: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.playGame) private var playGame
    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats
    @Environment(\.scenePhase) private var scenePhase
    @State private var isNewHighScore = false
    @State private var roundAnalytics = GameRoundAnalytics()
    @State private var hasStartedRound = false
    @State private var cardClock = CardRoundClock()
    @State private var finalScore: Int?
    @State private var awardedTimeBonus = 0
    @State private var showingTutorial = false
    @State private var resumeAfterTutorial = false
    /// A won level with a successor advances by itself instead of asking.
    @State private var autoAdvancing = false
    @State private var confetti = 0
    @State private var contentShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SoundFX.enabledKey) private var soundEnabled = true
    private var tutorial: GameTutorial? { GameTutorial.forGame(gameID) }
    private var tutorialKey: String { "gameTutorial.v1." + gameID.rawValue }
    private func showTutorial() {
        resumeAfterTutorial = engine.state == .playing
        if resumeAfterTutorial { engine.state = .paused }
        showingTutorial = true
    }

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
            GameTheme.background.ignoresSafeArea()

            VStack(spacing: 16) {
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
                    .foregroundStyle(GameTheme.textSecondary)
                    .padding(12)
                    .gameCard(cornerRadius: 18)
                }
                // An optional matching lower spacer centers the play area below the header.
                Spacer(minLength: 0)
                content()
                    .foregroundStyle(GameTheme.ink)
                    .tint(GameTheme.accent)
                    // The board settles in when a game or a new level opens.
                    .scaleEffect(contentShown || reduceMotion ? 1 : 0.95)
                    .opacity(contentShown ? 1 : 0)
                    .allowsHitTesting(engine.state == .playing)
                    .accessibilityHidden(engine.state != .playing)
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
                             randomGame: { playRandomGame(source: "pause_random") },
                             exit: { dismiss() })
            }

            if autoAdvancing {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44, weight: .bold))
                        .symbolEffect(.bounce, value: autoAdvancing)
                    Text(L10n.text("Level complete!")).font(.title3.bold())
                    Text(displayedScore, format: .number)
                        .font(.headline.monospacedDigit()).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .background(LinearGradient(colors: [GameTheme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: GameTheme.accent.opacity(0.4), radius: 20, y: 8)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
            } else if case .gameOver(let won) = engine.state {
                GameOverOverlay(won: won,
                                score: displayedScore,
                                highScore: stats.highScore(for: gameID),
                                isNewHighScore: isNewHighScore,
                                resultTitle: resultTitle,
                                resultSummary: summary,
                                playAgain: restart,
                                mainMenu: { dismiss() },
                                randomGame: { playRandomGame(source: "game_over_random") })
            }
        }
        .overlay { ConfettiView(trigger: confetti).ignoresSafeArea() }
        .foregroundStyle(GameTheme.ink)
        .tint(GameTheme.accent)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: engine.state)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: autoAdvancing)
        .onAppear {
            if reduceMotion { contentShown = true }
            else { withAnimation(.spring(duration: 0.45, bounce: 0.2).delay(0.05)) { contentShown = true } }
        }
        .onAppear {
            AppAnalytics.screen("game_\(gameID.rawValue)")
            if !hasStartedRound {
                hasStartedRound = true
                if hasCardTimer { cardClock.reset(active: scenePhase == .active && engine.state == .playing) }
                roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
            }
        }
        .sheet(isPresented: $showingTutorial, onDismiss: {
            UserDefaults.standard.set(true, forKey: tutorialKey)
            if resumeAfterTutorial && engine.state == .paused { engine.state = .playing }
            resumeAfterTutorial = false
        }) {
            if let tutorial { GameTutorialView(gameID: gameID, tutorial: tutorial) }
        }
        .onAppear {
            if tutorial != nil && !UserDefaults.standard.bool(forKey: tutorialKey) { showTutorial() }
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
                // Wins and new records get a confetti shower.
                if won || isNewHighScore { confetti += 1 }
                SoundFX.play(won ? .win : .lose)
                if won, let nextLevel {
                    autoAdvancing = true
                    Task {
                        // Let the final move and the banner register before switching.
                        try? await Task.sleep(for: .milliseconds(1700))
                        guard case .gameOver(won: true) = engine.state else {
                            autoAdvancing = false
                            return
                        }
                        nextLevel()
                    }
                }
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

    private func playRandomGame(source: String) {
        if let id = GameID.allCases.filter({ $0 != gameID }).randomElement() {
            playGame(id, source: source)
        }
    }

    private func restart() {
        Haptics.tap()
        autoAdvancing = false
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
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                headerButton("xmark", label: L10n.text("Main Menu")) { dismiss() }
                Text(info.title)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                headerButton(soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             label: L10n.text(soundEnabled ? "Sound On" : "Sound Off")) {
                    Haptics.tap()
                    soundEnabled.toggle()
                }
                headerButton("pause.fill", label: L10n.text("Paused")) {
                    if engine.state == .playing {
                        Haptics.tap()
                        engine.state = .paused
                    }
                }
                .disabled(engine.state != .playing)
                headerButton("arrow.counterclockwise", label: L10n.text("Restart")) { restart() }
            }
            if tutorial != nil {
                HStack {
                    Spacer()
                    Button { showTutorial() } label: {
                        Label(L10n.text("How to play"), systemImage: "questionmark.circle")
                            .font(.subheadline).frame(minHeight: 32)
                    }
                }
            }
            HStack(spacing: 12) {
                scorePanel(title: L10n.text("Score"), value: displayedScore, symbol: "number", accent: true)
                scorePanel(title: L10n.text("Your Records"), value: stats.highScore(for: gameID), symbol: "trophy", accent: false)
            }
        }
    }

    private func scorePanel(title: String, value: Int, symbol: String, accent: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent ? GameTheme.accent : GameTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(accent ? GameTheme.accent.opacity(0.1) : GameTheme.surfaceHigh, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Group {
                    if accent { LiveScoreText(value: value) }
                    else { Text(value, format: .number).contentTransition(.numericText()) }
                }
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gameCard(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Overlay chrome

private struct OverlayCard<CardContent: View>: View {
    @ViewBuilder let content: () -> CardContent

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { } // Block taps to the paused board.
                ScrollView {
                    VStack(spacing: 24, content: content)
                        .multilineTextAlignment(.center)
                        .padding(28)
                        .frame(maxWidth: 360)
                        .background(GameTheme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 30, y: 12)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityAddTraits(.isModal)
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
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GameTheme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
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
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(GameTheme.surfaceHigh, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PauseOverlay: View {
    let resume: () -> Void
    let restart: () -> Void
    let randomGame: () -> Void
    let exit: () -> Void

    var body: some View {
        OverlayCard {
            Image(systemName: "pause.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(GameTheme.accent)
                .frame(width: 72, height: 72)
                .background(GameTheme.accent.opacity(0.1), in: Circle())
            Text(L10n.text("Paused"))
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
            VStack(spacing: 10) {
                PrimaryButton(title: L10n.text("Resume"), symbol: "play.fill", action: resume)
                SecondaryButton(title: L10n.text("Restart"), symbol: "arrow.counterclockwise", action: restart)
                SecondaryButton(title: L10n.text("Random Game"), symbol: "shuffle", action: randomGame)
                SecondaryButton(title: L10n.text("Main Menu"), symbol: "house", action: exit)
            }
        }
        .transition(.opacity)
    }
}

struct GameOverOverlay: View {
    @State private var shownScore = 0.0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let won: Bool
    let score: Int
    let highScore: Int
    let isNewHighScore: Bool
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    let playAgain: () -> Void
    let mainMenu: () -> Void
    let randomGame: () -> Void

    var body: some View {
        OverlayCard {
            Image(systemName: won ? "trophy.fill" : isNewHighScore ? "star.fill" : "flag.checkered")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(won || isNewHighScore ? Color.yellow : GameTheme.accent)
                .frame(width: 80, height: 80)
                .background((won || isNewHighScore ? Color.orange : GameTheme.accent).opacity(0.15), in: Circle())
                .symbolEffect(.bounce, value: appeared)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
            VStack(spacing: 8) {
                Text(resultTitle ?? L10n.text(won ? "You Win!" : "Game Over"))
                    .font(.largeTitle.bold()).foregroundStyle(.primary)
                if let resultSummary {
                    Text(resultSummary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                Text(L10n.text("Score")).font(.subheadline).foregroundStyle(.secondary)
                CountingText(value: shownScore)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundStyle(.primary)
                if isNewHighScore {
                    Label(L10n.text("New High Score!"), systemImage: "trophy.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing), in: Capsule())
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.3)
                        .shadow(color: .orange.opacity(0.5), radius: 8)
                } else {
                    Text(L10n.format("Best: %d", highScore)).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(GameTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 24))
            VStack(spacing: 10) {
                Button(action: playAgain) {
                    Label(L10n.text("Play Again"), systemImage: "arrow.counterclockwise")
                        .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 22)
                        .foregroundStyle(.white).background(GameTheme.accent, in: Capsule())
                }.buttonStyle(.plain)
                SecondaryButton(title: L10n.text("Random Game"), symbol: "shuffle", action: randomGame)
                Button(action: mainMenu) {
                    Label(L10n.text("Home"), systemImage: "house")
                        .font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onAppear {
            guard !reduceMotion else { shownScore = Double(score); appeared = true; return }
            withAnimation(.spring(duration: 0.5, bounce: 0.45).delay(0.15)) { appeared = true }
            // Count the score up, longer for bigger numbers.
            withAnimation(.easeOut(duration: min(1.4, 0.5 + Double(score) / 4000)).delay(0.2)) { shownScore = Double(score) }
        }
        .onChange(of: score) { _, value in shownScore = Double(value) }
    }
}
