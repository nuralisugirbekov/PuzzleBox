import SwiftUI

/// Shared wrapper for every mini-game: the Solitaire header (back, pause,
/// restart, score, best and the round clock), plus the pause and game-over overlays. Records finished
/// rounds into `StatsStore` automatically.
struct GameContainerView<Engine: GameEngine, Content: View>: View {
    let gameID: GameID
    let engine: Engine
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    var nextLevel: (() -> Void)? = nil
    /// Shows the round clock under the score.
    var showsClock = true
    /// Drawn between the score and the best score (e.g. lives).
    var headerAccessory: AnyView? = nil
    /// The play area runs to the screen's side and bottom edges.
    var fullBleed = false
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
    /// The game-over alert was closed with its ✕ to look at the final board.
    @State private var gameOverHidden = false
    @State private var contentShown = false
    @Environment(\.resumeOffer) private var resumeOffer
    /// A saved round was restored; the "Continue previous game?" alert is up.
    private var offeringResume: Bool { resumeOffer.awaiting.contains(gameID) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tutorial: GameTutorial? { GameTutorial.forGame(gameID) }
    private var tutorialKey: String { "gameTutorial.v1." + gameID.rawValue }
    private func showTutorial() {
        resumeAfterTutorial = engine.state == .playing
        if resumeAfterTutorial { engine.state = .paused }
        showingTutorial = true
    }

    /// Table games laid out from the top of the screen; the rest centre the
    /// play area on the screen (see `ScreenCenteredLayout`).
    private var fillsFromTop: Bool {
        fullBleed || hasCardTimer || gameID == .blockBlast || gameID == .durak || gameID == .hangman
            || gameID == .battleship
    }

    private var isGameOver: Bool {
        if case .gameOver = engine.state { true } else { false }
    }

    /// Card games turn a quick win into a time bonus. Every game shows its round time.
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

    private var playArea: some View {
        content()
            // The play area takes all the room it can.
            .layoutPriority(1)
            // Undo the side padding the header keeps.
            .padding(.horizontal, fullBleed ? -16 : 0)
            .foregroundStyle(GameTheme.ink)
            .tint(GameTheme.accent)
            // The board settles in when a game or a new level opens.
            .scaleEffect(contentShown || reduceMotion ? 1 : 0.95)
            .opacity(contentShown ? 1 : 0)
            // Only a live round takes input. After game over the board stays
            // visible (and readable by VoiceOver once the result alert is
            // closed) so the player can review it, but it can't be played.
            .allowsHitTesting(engine.state == .playing)
            .accessibilityHidden(engine.state == .paused || (isGameOver && !gameOverHidden))
    }

    var body: some View {
        ZStack {
            GameTheme.background.ignoresSafeArea()

            Group {
                if fillsFromTop {
                    VStack(spacing: 16) {
                        cardHeader
                        playArea
                    }
                } else {
                    ScreenCenteredLayout(spacing: 16) {
                        cardHeader
                        playArea
                    }
                }
            }
            .padding(fullBleed ? [.top, .horizontal] : .all)
            .ignoresSafeArea(edges: fullBleed ? .bottom : [])

            if engine.state == .paused && offeringResume {
                ResumeAlert(continueGame: {
                                resumeOffer.answer(gameID)
                                engine.state = .playing
                                AppAnalytics.log("game_resumed_session", parameters: ["game_id": gameID.rawValue])
                            },
                            startOver: {
                                resumeOffer.answer(gameID)
                                restart()
                            },
                            exit: {
                                resumeOffer.answer(gameID)
                                dismiss()
                            })
            } else if engine.state == .paused {
                PauseAlert(resume: {
                               roundAnalytics.event("game_resume", score: engine.score)
                               engine.state = .playing
                           },
                           restart: restart,
                           exit: { dismiss() },
                           howToPlay: tutorial == nil ? nil : { showTutorial() })
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
            } else if case .gameOver(let won) = engine.state, !gameOverHidden {
                GameOverOverlay(won: won,
                                score: displayedScore,
                                highScore: stats.highScore(for: gameID),
                                isNewHighScore: isNewHighScore,
                                resultTitle: resultTitle,
                                resultSummary: summary,
                                playAgain: restart,
                                home: { dismiss() },
                                close: { gameOverHidden = true })
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
                cardClock.reset(active: scenePhase == .active && engine.state == .playing)
                restoreSavedRound()
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
            if tutorial != nil && !offeringResume && !UserDefaults.standard.bool(forKey: tutorialKey) { showTutorial() }
        }
        .onDisappear {
            saveRound()
            cardClock.setActive(false)
            roundAnalytics.finish(score: displayedScore, reason: "exit")
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounded apps may be killed without warning, so save now.
            if phase != .active { saveRound() }
            cardClock.setActive(phase == .active && engine.state == .playing)
            roundAnalytics.setActive(phase == .active && engine.state == .playing)
        }
        .onChange(of: engine.state) { _, newState in
            cardClock.setActive(scenePhase == .active && newState == .playing)
            roundAnalytics.setActive(scenePhase == .active && newState == .playing)
            if newState == .paused {
                roundAnalytics.event("game_pause", score: engine.score)
            }
            if case .gameOver(let won) = newState {
                GameSessionStore.delete(gameID)
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
    }

    // MARK: Saved rounds

    /// When the game was just opened from the catalog, picks up a round the
    /// player left unfinished and asks whether to continue it.
    private func restoreSavedRound() {
        guard resumeOffer.claim(gameID),
              let resumable = engine as? any ResumableGame,
              let session = GameSessionStore.load(gameID) else { return }
        guard resumable.restoreSession(session.payload) else {
            GameSessionStore.delete(gameID)
            return
        }
        cardClock.resume(from: session.elapsed, active: false)
        resumeOffer.markAwaiting(gameID)
        engine.state = .paused
    }

    /// Writes the unfinished round to disk, or clears it when there is
    /// nothing to resume.
    private func saveRound() {
        guard let resumable = engine as? any ResumableGame else { return }
        cardClock.tick()
        if let payload = resumable.saveSession() {
            GameSessionStore.save(payload, for: gameID, elapsed: cardClock.elapsed)
        } else {
            GameSessionStore.delete(gameID)
        }
    }

    private func restart() {
        Haptics.tap()
        autoAdvancing = false
        gameOverHidden = false
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
        cardClock.reset(active: scenePhase == .active)
        GameSessionStore.delete(gameID)
        engine.restart()
        // Timed challenges return to setup; their new container starts the next round.
        if gameID != .checkmate && gameID != .quickMath {
            roundAnalytics.start(gameID, active: scenePhase == .active && engine.state == .playing)
        }
    }

    // MARK: Game chrome (Figma "Solitare"), shared by every game

    /// Back, centred title, pause and a prominent restart; then score,
    /// best score and the round timer.
    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                headerButton("chevron.left", label: L10n.text("Back")) { dismiss() }
                Spacer(minLength: 0)
                headerButton("pause", label: L10n.text("Paused")) {
                    if engine.state == .playing {
                        Haptics.tap()
                        engine.state = .paused
                    }
                }
                .disabled(engine.state != .playing)
                Button(action: restart) {
                    Image(systemName: Self.restartSymbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .prominentGlassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Restart"))
            }
            .overlay {
                Text(info.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 112)
            }
            .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("Score")).font(.caption)
                    LiveScoreText(value: displayedScore)
                        .font(.title2.bold().monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let headerAccessory {
                    // Level with the numbers below the captions.
                    headerAccessory.padding(.top, 22)
                }
                VStack(alignment: .trailing, spacing: 4) {
                    Text(L10n.text("Your best")).font(.caption)
                    Text(stats.highScore(for: gameID), format: .number)
                        .font(.title2.bold().monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .foregroundStyle(.primary)
            .accessibilityElement(children: .combine)

            if showsClock {
            HStack(spacing: 8) {
                // Only the clock redraws each second, not the game below it.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(cardClock.formattedTime)
                        .font(.title2.bold().monospacedDigit())
                }
                Image(systemName: "timer")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.top, 20)
            .padding(.bottom, 22)
            .accessibilityElement(children: .combine)
            }
        }
    }

    /// The design's restart glyph (SF Symbols 6), with an older fallback.
    private static var restartSymbol: String {
        let preferred = "arrow.trianglehead.counterclockwise.rotate.90"
        return UIImage(systemName: preferred) == nil ? "arrow.counterclockwise" : preferred
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



/// Figma "Solitare. Rejoined": offered when a game opens on a round the
/// player left unfinished.
struct ResumeAlert: View {
    let continueGame: () -> Void
    let startOver: () -> Void
    let exit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { } // Block taps to the restored board.
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 41, weight: .semibold))
                        .foregroundStyle(GameTheme.accent)
                        .frame(height: 49)
                        .accessibilityHidden(true)
                    Text(L10n.text("Continue previous game?"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(L10n.text("If you restart, you’ll lose your progress"))
                        .font(.title2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(16)
                VStack(spacing: 8) {
                    AlertActionButton(title: L10n.text("Continue"), symbol: "play.fill",
                                      prominent: true, action: continueGame)
                    AlertActionButton(title: L10n.text("Start over"), symbol: "arrow.counterclockwise",
                                      action: startOver)
                    AlertActionButton(title: L10n.text("Home"), symbol: "house.fill", action: exit)
                }
            }
            .padding(14)
            .frame(width: 300)
            .alertSurface(cornerRadius: 34)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

/// Figma "Solitare. Paused": an iOS alert with a title and three stacked
/// actions over a dimmed board. Shared by every game.
struct PauseAlert: View {
    let resume: () -> Void
    let restart: () -> Void
    let exit: () -> Void
    /// Opens the game's rules, for games that have them.
    var howToPlay: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { } // Block taps to the paused board.
            VStack(spacing: 0) {
                // Figma "Game Paused": a 41pt blue pause glyph over a Title 2 heading.
                VStack(spacing: 0) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 41, weight: .semibold))
                        .foregroundStyle(GameTheme.accent)
                        .frame(height: 49)
                        .accessibilityHidden(true)
                    Text(L10n.text("Game Paused"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                VStack(spacing: 8) {
                    AlertActionButton(title: L10n.text("Resume"), symbol: "play.fill",
                                      prominent: true, action: resume)
                    AlertActionButton(title: L10n.text("Restart"), symbol: "arrow.counterclockwise",
                                      action: restart)
                    if let howToPlay {
                        AlertActionButton(title: L10n.text("How to play"), symbol: "questionmark.circle",
                                          action: howToPlay)
                    }
                    AlertActionButton(title: L10n.text("Home"), symbol: "house.fill",
                                      action: exit)
                }
            }
            .padding(14)
            .frame(width: 300)
            .alertSurface(cornerRadius: 34)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}

private struct AlertActionButton: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(prominent ? AnyShapeStyle(GameTheme.accent)
                                      : AnyShapeStyle(Color(.tertiarySystemFill)),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Liquid Glass alert background on iOS 26, a thick material before.
    @ViewBuilder
    func alertSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.thickMaterial, in: shape)
        }
    }
}

private extension View {

    /// Accent-tinted glass circle for the prominent toolbar action; the
    /// whole circle is tappable.
    func prominentGlassCircle() -> some View {
        contentShape(.circle).prominentGlassSurface()
    }

    @ViewBuilder
    private func prominentGlassSurface() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(GameTheme.accent).interactive(), in: .circle)
        } else {
            background(GameTheme.accent, in: Circle())
        }
    }
}

/// Figma "Game over" / "New best": the pause alert's glass card with a
/// checkered flag, the score and best, Play again / Home, and a ✕ that
/// closes the alert to show the final board.
struct GameOverOverlay: View {
    @State private var shownScore = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let won: Bool
    let score: Int
    let highScore: Int
    let isNewHighScore: Bool
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    let playAgain: () -> Void
    let home: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { } // Block taps to the finished board.
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Image(systemName: "flag.pattern.checkered")
                        .font(.system(size: 41, weight: .semibold))
                        .foregroundStyle(GameTheme.accent)
                        .frame(height: 49)
                    Text(resultTitle ?? L10n.text(won ? "You Win!" : "Game Over"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)

                VStack(spacing: 0) {
                    Text(L10n.text("Score"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    CountingText(value: shownScore)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(isNewHighScore ? L10n.text("New best!") : L10n.format("Best: %d", highScore))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let resultSummary {
                        Text(resultSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)

                VStack(spacing: 8) {
                    AlertActionButton(title: L10n.text("Play Again"), symbol: "arrow.counterclockwise",
                                      prominent: true, action: playAgain)
                    AlertActionButton(title: L10n.text("Home"), symbol: "house.fill", action: home)
                }
            }
            .padding(14)
            .frame(width: 300)
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .padding(14)
                .accessibilityLabel(L10n.text("Close"))
            }
            .alertSurface(cornerRadius: 34)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .onAppear {
            guard !reduceMotion else { shownScore = Double(score); return }
            // Count the score up, longer for bigger numbers.
            withAnimation(.easeOut(duration: min(1.4, 0.5 + Double(score) / 4000)).delay(0.2)) { shownScore = Double(score) }
        }
        .onChange(of: score) { _, value in shownScore = Double(value) }
    }
}

/// The header at the top and the play area centred on the screen, nudged
/// down only as far as it takes to clear the header. A play area that wants
/// all the room left (a `GeometryReader` board) simply fills it.
private struct ScreenCenteredLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let header = subviews[0], play = subviews[1]
        let headerHeight = header.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
        header.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top,
                     proposal: ProposedViewSize(width: bounds.width, height: headerHeight))
        let top = bounds.minY + headerHeight + spacing
        let room = max(0, bounds.maxY - top)
        let height = min(play.sizeThatFits(ProposedViewSize(width: bounds.width, height: room)).height, room)
        let y = min(max(bounds.midY - height / 2, top), bounds.maxY - height)
        play.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top,
                   proposal: ProposedViewSize(width: bounds.width, height: height))
    }
}
