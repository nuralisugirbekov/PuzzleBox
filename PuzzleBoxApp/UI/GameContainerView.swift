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
    /// `.inGame`: no header; the game draws its own HUD from `\.gameHUD`.
    var chrome: GameChrome = .header
    /// Drawn edge to edge behind everything instead of the plain background.
    var backdrop: AnyView? = nil
    /// Toy colours for the pause and result windows of an `.inGame` game.
    var toyStyle: ToyStyle? = nil
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
    /// A saved round was picked up on open; the bottom note offers to start over.
    @State private var resumeNote = false
    /// The first open of a game: one line of its rules along the bottom edge.
    @State private var ruleHint: String?
    @State private var confetti = 0
    /// The game-over alert was closed with its ✕ to look at the final board.
    @State private var gameOverHidden = false
    @State private var contentShown = false
    @Environment(\.resumeOffer) private var resumeOffer
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
            if let backdrop {
                backdrop.ignoresSafeArea()
            } else {
                GameTheme.background.ignoresSafeArea()
            }

            Group {
                if chrome == .inGame {
                    playArea
                        .environment(\.gameHUD, hud)
                } else if fillsFromTop {
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

            if engine.state == .playing, resumeNote || ruleHint != nil {
                edgeNote
            }

            if engine.state == .paused {
                PauseAlert(resume: {
                               roundAnalytics.event("game_resume", score: engine.score)
                               engine.state = .playing
                           },
                           restart: restart,
                           exit: { dismiss() },
                           howToPlay: tutorial == nil ? nil : { showTutorial() })
            }

            if case .gameOver(let won) = engine.state, !gameOverHidden {
                GameOverOverlay(won: won,
                                score: displayedScore,
                                highScore: stats.highScore(for: gameID),
                                isNewHighScore: isNewHighScore,
                                resultTitle: resultTitle,
                                resultSummary: summary,
                                playAgain: restart,
                                next: won ? nextLevel : nil,
                                isLevel: nextLevel != nil,
                                home: { dismiss() },
                                close: { gameOverHidden = true })
            }

            // An in-game HUD can't be used once the round is over, so after the
            // result window is closed these take over its corners: leave the
            // game, or bring the results back.
            if chrome == .inGame, isGameOver, gameOverHidden {
                let ink = toyStyle?.ink ?? GameTheme.ink
                HStack(alignment: .top) {
                    ToyIconButton(symbol: "chevron.backward", label: L10n.text("Back"), ink: ink) { dismiss() }
                    Spacer()
                    ToyIconButton(symbol: "flag.pattern.checkered", label: L10n.text("Game Over"), ink: ink) {
                        gameOverHidden = false
                    }
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }
        }
        .environment(\.toyStyle, chrome == .inGame ? toyStyle : nil)
        .overlay { ConfettiView(trigger: confetti).ignoresSafeArea() }
        .foregroundStyle(GameTheme.ink)
        .tint(GameTheme.accent)
        .animation(.spring(duration: 0.35, bounce: 0.25), value: engine.state)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: resumeNote)
        .animation(.spring(duration: 0.4, bounce: 0.3), value: ruleHint)
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
            if let tutorial { GameTutorialView(gameID: gameID, tutorial: tutorial).closesWhenRoomOpens() }
        }
        .onAppear {
            // The first open shows one line of the rules at the bottom edge
            // instead of a sheet; the full rules live under Pause › How to play.
            if let tutorial, !resumeNote, !UserDefaults.standard.bool(forKey: tutorialKey) {
                UserDefaults.standard.set(true, forKey: tutorialKey)
                ruleHint = Self.firstSentence(of: L10n.text(tutorial.rules))
            }
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
            }
        }
    }

    /// Score, best and the pause and restart actions, for a game's own HUD.
    private var hud: GameHUD {
        GameHUD(score: displayedScore,
                best: stats.highScore(for: gameID),
                canPause: engine.state == .playing,
                clock: { cardClock.formattedTime },
                pause: {
                    guard engine.state == .playing else { return }
                    Haptics.tap()
                    engine.state = .paused
                },
                restart: restart)
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
        // Straight back into the round; a note at the bottom offers a fresh start.
        cardClock.resume(from: session.elapsed, active: scenePhase == .active)
        engine.state = .playing
        resumeNote = true
        AppAnalytics.log("game_resumed_session", parameters: ["game_id": gameID.rawValue])
    }

    /// The bottom-edge note: the restored round, or the first line of the rules.
    /// It never covers the board's middle and goes away by itself.
    private var edgeNote: some View {
        EdgeNote(symbol: resumeNote ? "clock.arrow.circlepath" : "hand.point.up.left.fill",
                 text: resumeNote ? L10n.text("Picked up where you left off") : (ruleHint ?? ""),
                 actionTitle: resumeNote ? L10n.text("Start over") : (tutorial == nil ? nil : L10n.text("Rules")),
                 action: {
                     if resumeNote { resumeNote = false; restart() }
                     else { ruleHint = nil; showTutorial() }
                 },
                 close: { resumeNote = false; ruleHint = nil })
            .id(resumeNote)
            .task(id: resumeNote) {
                try? await Task.sleep(for: .seconds(resumeNote ? 4 : 7))
                guard !Task.isCancelled else { return }
                resumeNote = false
                ruleHint = nil
            }
    }

    static func firstSentence(of text: String) -> String {
        var first = text
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sub, _, _, stop in
            if let sub { first = sub.trimmingCharacters(in: .whitespaces) }
            stop = true
        }
        return first
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
        resumeNote = false
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
            .padding(.bottom, 8)

            // One row of stats: score, the round clock (or the game's own
            // accessory, e.g. lives) in the middle, and the best score.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                stat(L10n.text("Score"), alignment: .leading) {
                    LiveScoreText(value: displayedScore)
                }
                if let headerAccessory {
                    VStack(spacing: 2) {
                        Text(verbatim: " ").font(.caption)
                        headerAccessory
                    }
                } else if showsClock {
                    stat(L10n.text("Time"), alignment: .center) {
                        // Only the clock redraws each second, not the game below it.
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(cardClock.formattedTime)
                        }
                    }
                }
                stat(L10n.text("Your best"), alignment: .trailing) {
                    Text(stats.highScore(for: gameID), format: .number)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        }
    }

    /// A caption over a figure, one column of the stats row.
    private func stat<Value: View>(_ caption: String, alignment: HorizontalAlignment,
                                   @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(caption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            value()
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
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



/// A short note along the bottom edge, over the board's margin: a symbol,
/// one line, an optional action and a close button. Used for the restored
/// round and for the first line of a game's rules.
private struct EdgeNote: View {
    let symbol: String
    let text: String
    var actionTitle: String? = nil
    var action: () -> Void = {}
    let close: () -> Void
    @Environment(\.toyStyle) private var toy

    var body: some View {
        let ink = toy?.ink ?? Color.primary
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(toy?.accent ?? GameTheme.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(ink)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(toy?.accent ?? GameTheme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(ink.opacity(0.6))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Close"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background { surface }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if let toy {
            ToyBlock(color: toy.card, shape: shape, lip: 4)
                .padding(.bottom, -4)
        } else if #available(iOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.thickMaterial)
        }
    }
}

/// Figma "Solitare. Paused": an iOS alert with a title and three stacked
/// actions over a dimmed board. Shared by every game.
struct PauseAlert: View {
    @Environment(\.toyStyle) private var toy
    let resume: () -> Void
    let restart: () -> Void
    let exit: () -> Void
    /// Opens the game's rules, for games that have them.
    var howToPlay: (() -> Void)? = nil

    var body: some View {
        ZStack {
            AlertDim()
                .onTapGesture { } // Block taps to the paused board.
            VStack(spacing: 0) {
                // Figma "Game Paused": a 41pt blue pause glyph over a Title 2 heading.
                VStack(spacing: 0) {
                    AlertGlyph(symbol: "pause.fill")
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
    @Environment(\.toyStyle) private var toy

    var body: some View {
        if let toy {
            Button(action: action) {
                Label(title, systemImage: symbol)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(prominent ? Color.white : toy.ink)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .contentShape(Capsule())
            }
            .buttonStyle(ToyPressStyle(color: prominent ? toy.accent : toy.clay.toyShade(0.1), lip: 4))
        } else {
            glassButton
        }
    }

    private var glassButton: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(prominent ? AnyShapeStyle(GameTheme.accent)
                                      : AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The dimmed board behind a window: black, or the game's own colour in a toy world.
private struct AlertDim: View {
    @Environment(\.toyStyle) private var toy

    var body: some View {
        Group {
            if let toy {
                ZStack {
                    Color.black.opacity(0.22)
                    (toy.haze ?? toy.clay).opacity(0.55)
                }
            } else {
                Color.black.opacity(0.5)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
    }
}

/// A window's symbol: a raised medallion in the game's accent in a toy world.
private struct AlertGlyph: View {
    let symbol: String
    @Environment(\.toyStyle) private var toy

    var body: some View {
        Group {
            if let toy {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 5)
                    .background { ToyBlock(color: toy.accent, shape: Circle(), lip: 5) }
                    .padding(.bottom, 10)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 41, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)
                    .frame(height: 49)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Liquid Glass alert background on iOS 26, a thick material before; a
    /// raised toy card when the game sets a `ToyStyle`.
    func alertSurface(cornerRadius: CGFloat) -> some View {
        modifier(AlertSurface(cornerRadius: cornerRadius))
    }
}

private struct AlertSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.toyStyle) private var toy

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if let toy {
            content
                .fontDesign(.rounded)
                .foregroundStyle(toy.ink)
                .padding(.bottom, 8)
                .background { ToyBlock(color: toy.card, shape: shape, lip: 8) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.thickMaterial, in: shape)
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
    @Environment(\.toyStyle) private var toy
    @State private var shownScore = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let won: Bool
    let score: Int
    let highScore: Int
    let isNewHighScore: Bool
    var resultTitle: String? = nil
    var resultSummary: String? = nil
    let playAgain: () -> Void
    /// A won level with a successor: the card leads with "Next level".
    var next: (() -> Void)? = nil
    /// A levelled game: a loss reads as "So close!" with Try again first.
    var isLevel = false
    let home: () -> Void
    let close: () -> Void

    private var glyph: String {
        if won { return next != nil ? "star.fill" : "trophy.fill" }
        if isNewHighScore { return "crown.fill" }
        return isLevel ? "arrow.counterclockwise" : "flag.pattern.checkered"
    }

    private var title: String {
        if let resultTitle { return resultTitle }
        if won { return L10n.text(isLevel ? "Level complete!" : "You Win!") }
        if isNewHighScore { return L10n.text("New best!") }
        return L10n.text(isLevel ? "So close!" : "Game Over")
    }

    var body: some View {
        ZStack {
            AlertDim()
                .onTapGesture { } // Block taps to the finished board.
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    AlertGlyph(symbol: glyph)
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(16)

                VStack(spacing: 0) {
                    Text(L10n.text("Score"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let toy {
                        // The score pressed into a well of the game's own clay.
                        CountingText(value: shownScore)
                            .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(toy.ink)
                            .lineLimit(1).minimumScaleFactor(0.5)
                            .padding(.horizontal, 22)
                            .frame(minWidth: 150, minHeight: 64)
                            .background {
                                ToySocket(color: toy.clay.toyShade(0.06),
                                          shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .padding(.vertical, 6)
                    } else {
                        CountingText(value: shownScore)
                            .font(.title2.bold().monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    if isNewHighScore {
                        Label(L10n.text("New best!"), systemImage: "crown.fill")
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(toy?.accent ?? GameTheme.accent)
                    } else if highScore > 0 {
                        Label(L10n.format("Best: %d", highScore), systemImage: "crown.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
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
                    if let next {
                        AlertActionButton(title: L10n.text("Next level"), symbol: "arrow.forward",
                                          prominent: true, action: next)
                        HStack(spacing: 8) {
                            AlertActionButton(title: L10n.text("Replay"), symbol: "arrow.counterclockwise",
                                              action: playAgain)
                            AlertActionButton(title: L10n.text("Home"), symbol: "house.fill", action: home)
                        }
                    } else {
                        AlertActionButton(title: L10n.text(isLevel ? "Try again" : "Play Again"),
                                          symbol: "arrow.counterclockwise",
                                          prominent: true, action: playAgain)
                        AlertActionButton(title: L10n.text("Home"), symbol: "house.fill", action: home)
                    }
                }
            }
            .padding(14)
            .frame(width: 300)
            .overlay(alignment: .topTrailing) {
                Group {
                    if let toy {
                        ToyIconButton(symbol: "xmark", label: L10n.text("Close"), color: toy.clay.toyShade(0.1),
                                      ink: toy.ink, size: 44, action: close)
                    } else {
                        Button(action: close) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .glassCircle()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.text("Close"))
                    }
                }
                .padding(14)
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
