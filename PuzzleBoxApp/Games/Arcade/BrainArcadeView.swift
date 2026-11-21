import SwiftUI
import Observation

enum BrainArcadeMode { case reaction, simon }

@MainActor
@Observable
final class BrainArcadeEngine: GameEngine {
    let mode: BrainArcadeMode
    var state: GameState = .playing {
        didSet {
            // A paused reaction cue must not be used to prepare a zero-time answer.
            if state == .paused, mode == .reaction, started, feedbackRemaining <= 0 {
                prepareReaction()
            }
        }
    }
    private(set) var score = 0
    private(set) var started = false
    private(set) var message = "Tap to start"
    private(set) var ready = false
    private(set) var highlighted: Int?
    private(set) var sequence: [Int] = []
    private(set) var showingSequence = false
    private(set) var round = 0
    private(set) var reactionTimes: [Int] = []
    private(set) var falseStarts = 0
    /// Reaction: a yellow decoy flash that must not be tapped.
    private(set) var decoy = false
    private(set) var bestTime: Int?
    /// Simon: one replay of the sequence after a mistake.
    private(set) var secondChance = true
    private var decoyIn: Double?
    private var decoyLeft = 0.0

    private(set) var feedback = ""
    private var remaining: Double = 0
    private var readySince: TimeInterval?
    private var sequenceStep = -1
    private var inputIndex = 0
    private var feedbackRemaining = 0.0
    var active = false {
        didSet {
            if !active, mode == .reaction, started, state == .playing, feedbackRemaining <= 0 {
                prepareReaction()
            }
        }
    }

    init(mode: BrainArcadeMode) { self.mode = mode; restart() }
    var gameID: GameID {
        switch mode { case .reaction: .reactionTap; case .simon: .simon; }
    }
    func restart() {
        score = 0; state = .playing; started = false; message = "Tap to start"; ready = false
        highlighted = nil; sequence = []; showingSequence = false; round = 0
        reactionTimes = []; falseStarts = 0; decoy = false; decoyIn = nil; bestTime = nil; secondChance = true
        feedback = ""; remaining = 0; readySince = nil; feedbackRemaining = 0
        sequenceStep = -1; inputIndex = 0
    }
    func start() {
        guard state == .playing, active, !started else { return }
        started = true
        switch mode {
        case .reaction: prepareReaction()
        case .simon: addSequence()
        }
    }
    private func prepareReaction() {
        ready = false; readySince = nil; message = "Wait for green…"; decoy = false
        remaining = Double.random(in: 1.5...4.5)
        // From the third round on, a yellow decoy may flash before green.
        decoyIn = round >= 2 && Double.random(in: 0..<1) < 0.45 ? remaining * Double.random(in: 0.3...0.7) : nil
    }
    func tapReaction() {
        guard active, state == .playing else { return }
        if !started { start(); return }
        guard feedbackRemaining <= 0 else { return }
        if !ready {
            falseStarts += 1; Haptics.error(); SoundFX.play(.wrong); feedback = "Too soon!"; feedbackRemaining = 1
            if falseStarts >= 3 { state = .gameOver(won: false) }
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            let milliseconds = max(1, Int((now - (readySince ?? now)) * 1000))
            reactionTimes.append(milliseconds)
            bestTime = min(bestTime ?? milliseconds, milliseconds)
            let (rating, bonus) = Self.rating(milliseconds)
            score += max(0, 1000 - milliseconds) + bonus
            round += 1; ready = false; feedback = rating; feedbackRemaining = 1.1
            message = "Reaction recorded"
            Haptics.success(); SoundFX.play(bonus >= 200 ? .coin : .point)
            if round == 5 { state = .gameOver(won: true) }
        }
    }
    static func rating(_ ms: Int) -> (String, Int) {
        switch ms {
        case ..<230: ("Lightning!", 300)
        case ..<300: ("Super fast!", 200)
        case ..<380: ("Fast", 100)
        case ..<500: ("Good", 50)
        default: ("Slow", 0)
        }
    }
    private func addSequence() {
        sequence.append(Int.random(in: 0..<4)); showingSequence = true
        sequenceStep = -1; inputIndex = 0; remaining = 0.7; highlighted = nil; message = "Watch the sequence"
    }
    func tapColor(_ index: Int) {
        guard active, state == .playing, started, !showingSequence, feedbackRemaining <= 0 else { return }
        guard sequence[inputIndex] == index else {
            Haptics.error(); SoundFX.play(.wrong)
            if secondChance {
                // Replay the same sequence once instead of ending the game.
                secondChance = false; feedback = "Second chance!"
                showingSequence = true; sequenceStep = -1; inputIndex = 0; remaining = 1.0; highlighted = nil
                message = "Watch the sequence"
            } else {
                state = .gameOver(won: false)
            }
            return
        }
        highlighted = index; remaining = 0.16; inputIndex += 1; Haptics.tap(); SoundFX.play(.simon(index))
        if inputIndex == sequence.count {
            score += sequence.count * 10; round += 1; showingSequence = true
            feedbackRemaining = 0.6
        }
    }

    /// Simon a few steps in, with one pad lit, for the Home preview. Nothing is saved.
    func showcase() {
        restart()
        started = true
        sequence = [0, 2, 1, 3, 2, 0]
        highlighted = 2
        showingSequence = true
        round = 5
    }

    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        if feedbackRemaining > 0 {
            feedbackRemaining -= dt
            if feedbackRemaining <= 0 {
                feedback = ""
                switch mode {
                case .reaction: prepareReaction()
                case .simon: addSequence()
                }
            }
            return
        }
        switch mode {
        case .reaction:
            if !ready {
                remaining -= dt
                if let left = decoyIn {
                    decoyIn = left - dt
                    if left - dt <= 0 { decoyIn = nil; decoy = true; decoyLeft = 0.35; SoundFX.play(.tick) }
                }
                if decoy { decoyLeft -= dt; if decoyLeft <= 0 { decoy = false } }
                if remaining <= 0 { ready = true; decoy = false; readySince = ProcessInfo.processInfo.systemUptime; message = "Tap now!"; SoundFX.play(.tap) }
            }
        case .simon:
            remaining -= dt
            if showingSequence, remaining <= 0 {
                sequenceStep += 1
                if sequenceStep >= sequence.count * 2 {
                    showingSequence = false; highlighted = nil; message = "Repeat the sequence"; feedback = ""
                } else {
                    highlighted = sequenceStep.isMultiple(of: 2) ? sequence[sequenceStep / 2] : nil
                    if let highlighted { SoundFX.play(.simon(highlighted)) }
                    // Playback speeds up as the sequence grows.
                    let count = Double(sequence.count)
                    remaining = sequenceStep.isMultiple(of: 2) ? max(0.22, 0.45 - count * 0.015) : max(0.1, 0.22 - count * 0.008)
                }
            } else if !showingSequence, remaining <= 0 { highlighted = nil }
        }
    }
}

// MARK: - Saved round

extension BrainArcadeEngine: ResumableGame {
    private struct Session: Codable {
        let score: Int
        let round: Int
        let sequence: [Int]
        let reactionTimes: [Int]
        let falseStarts: Int
        let bestTime: Int?
        let secondChance: Bool
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, started, round > 0 else { return nil }
        return encodeSession(Session(score: score, round: round, sequence: sequence, reactionTimes: reactionTimes,
                                     falseStarts: falseStarts, bestTime: bestTime, secondChance: secondChance))
    }

    /// Picks up after the last finished round; the player taps to start again.
    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data) else { return false }
        restart()
        score = s.score; round = s.round; reactionTimes = s.reactionTimes; falseStarts = s.falseStarts
        bestTime = s.bestTime; secondChance = s.secondChance
        // Simon keeps the rounds already passed; starting adds the next step
        // and shows the whole sequence. A half-entered round is dropped.
        sequence = Array(s.sequence.prefix(s.round))
        return true
    }
}

struct BrainArcadeView: View {
    @State private var engine: BrainArcadeEngine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [.green, .red, .yellow, .blue]
    init(mode: BrainArcadeMode) { _engine = State(initialValue: BrainArcadeEngine(mode: mode)) }

    private var summary: String {
        if engine.mode == .reaction, !engine.reactionTimes.isEmpty {
            return L10n.format("Average: %d ms", engine.reactionTimes.reduce(0, +) / engine.reactionTimes.count)
        }
        return L10n.format("Rounds: %d", engine.round)
    }
    static let simonPalette = ToyPuzzles.world(top: (0.97, 0.92, 0.99), bottom: (0.88, 0.80, 0.97),
                                               darkTop: (0.14, 0.10, 0.20), darkBottom: (0.07, 0.05, 0.12),
                                               tray: (0.32, 0.28, 0.46), darkTray: (0.22, 0.19, 0.33),
                                               ink: (0.33, 0.20, 0.50), accent: (0.62, 0.36, 0.95), darkAccent: (0.72, 0.5, 1.0))
    private let simonColors: [Color] = [Color(red: 0.30, green: 0.80, blue: 0.42), Color(red: 0.96, green: 0.34, blue: 0.38),
                                        Color(red: 1.0, green: 0.80, blue: 0.22), Color(red: 0.30, green: 0.56, blue: 0.98)]

    private var isShowcase = false

    /// Just the Simon console mid-sequence, for the Home preview.
    init(showcase engine: BrainArcadeEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }

    var body: some View {
        if isShowcase {
            ZStack {
                Self.simonPalette.backdrop
                console.padding(28)
            }
            .environment(\.toyStyle, Self.simonPalette.style)
            .frame(width: 360, height: 360)
        } else if engine.mode == .simon {
            let palette = Self.simonPalette
            GameContainerView(gameID: engine.gameID, engine: engine, resultSummary: summary,
                              chrome: .inGame, backdrop: AnyView(palette.backdrop), toyStyle: palette.style) {
                ToyGameStage(palette: palette, headline: .score, trailing: { secondChance }) {
                    simon.padding(.top, 12)
                }
            }
            .modifier(BrainLoop(engine: engine, scenePhase: scenePhase))
        } else {
            GameContainerView(gameID: engine.gameID, engine: engine, resultSummary: summary) {
                VStack(spacing: 18) { reaction }
            }
            .modifier(BrainLoop(engine: engine, scenePhase: scenePhase))
        }
    }
}

/// The game clock and activity tracking shared by both modes.
private struct BrainLoop: ViewModifier {
    let engine: BrainArcadeEngine
    let scenePhase: ScenePhase
    func body(content: Content) -> some View {
        content
        .onAppear { engine.active = scenePhase == .active }
        .onDisappear { engine.active = false }
        .onChange(of: scenePhase) { _, phase in engine.active = phase == .active }
        .task {
            var last = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                let now = ProcessInfo.processInfo.systemUptime
                engine.advance(min(0.1, now - last)); last = now
            }
        }
    }
}

extension BrainArcadeView {

    // MARK: Reaction

    private var padColor: Color {
        if engine.ready { return .green }
        if engine.decoy { return .yellow }
        if engine.feedback == "Too soon!" { return .red }
        return GameTheme.surfaceHigh
    }

    private var reaction: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.format("Round %d of %d", min(5, engine.round + 1), 5))
                Spacer()
                if let best = engine.bestTime {
                    Label(L10n.format("Best: %d ms", best), systemImage: "trophy.fill").foregroundStyle(.orange)
                }
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.textSecondary)
            Button { engine.tapReaction() } label: {
                VStack(spacing: 14) {
                    Image(systemName: engine.ready ? "bolt.fill" : engine.decoy ? "exclamationmark.triangle.fill" : "hand.tap.fill")
                        .font(.system(size: 52, weight: .bold))
                        .symbolEffect(.pulse, isActive: !engine.ready && engine.started && !reduceMotion)
                    Text(L10n.text(engine.feedback.isEmpty ? engine.message : engine.feedback)).font(.title.bold())
                    if let last = engine.reactionTimes.last, !engine.feedback.isEmpty, engine.feedback != "Too soon!" {
                        Text(L10n.format("Reaction: %d ms", last)).font(.headline.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 280)
                .foregroundStyle(engine.ready || engine.decoy ? Color.black : GameTheme.ink)
                .background(padColor.gradient, in: RoundedRectangle(cornerRadius: 28))
                .animation(.easeOut(duration: 0.08), value: engine.ready)
            }
            .buttonStyle(.plain)
            // One bar per round: shorter is faster.
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<5, id: \.self) { i in
                    let time = i < engine.reactionTimes.count ? engine.reactionTimes[i] : nil
                    VStack(spacing: 4) {
                        if let time { Text(verbatim: "\(time)").font(.caption2.monospacedDigit()).foregroundStyle(GameTheme.textSecondary) }
                        RoundedRectangle(cornerRadius: 6)
                            .fill(time.map { barColor($0) } ?? GameTheme.surfaceHigh)
                            .frame(height: time.map { CGFloat(max(10, min(70, $0 / 8))) } ?? 10)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
            .animation(.spring(duration: 0.35), value: engine.reactionTimes.count)
            Text(L10n.format("False starts: %d/3", engine.falseStarts)).font(.footnote)
                .foregroundStyle(engine.falseStarts > 0 ? .red : GameTheme.textSecondary)
            Text(L10n.text("Tap the moment the pad turns green. Yellow is a trick!"))
                .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
        }
    }

    private func barColor(_ ms: Int) -> Color {
        ms < 300 ? .green : ms < 450 ? .yellow : .orange
    }

    // MARK: Simon

    private var secondChance: some View {
        Image(systemName: "heart.fill")
            .font(.title3.weight(.bold))
            .foregroundStyle(engine.secondChance ? Self.simonPalette.accent : Self.simonPalette.ink.opacity(0.18))
            .frame(width: 44, height: 44)
            .accessibilityLabel(L10n.text("Second chance"))
    }

    /// The round console with its four pads and the step counter.
    private var console: some View {
        let palette = Self.simonPalette
        return GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                // The console: a raised clay disc the four pads sit in.
                Circle().fill(palette.tray.toyShade(-0.18)).offset(y: 6)
                Circle().fill(LinearGradient(colors: [palette.tray.toyShade(0.06), palette.tray],
                                             startPoint: .top, endPoint: .bottom))
                ForEach(0..<4, id: \.self) { index in
                    let lit = engine.highlighted == index
                    let color = simonColors[index]
                    Button { engine.tapColor(index) } label: {
                        ZStack {
                            // Lip, then the face; a lit pad presses down onto its lip and glows.
                            SimonSegment(index: index).fill(color.toyShade(-0.32)).offset(y: 5)
                            SimonSegment(index: index)
                                .fill(LinearGradient(colors: lit ? [color.toyShade(0.22), color.toyShade(0.08)]
                                                                 : [color.toyShade(-0.04), color.toyShade(-0.16)],
                                                     startPoint: .top, endPoint: .bottom))
                                .overlay {
                                    SimonSegment(index: index)
                                        .stroke(.white.opacity(lit ? 0.6 : 0.25), lineWidth: 1.5)
                                }
                                .saturation(lit ? 1.1 : 0.8)
                                .offset(y: lit && !reduceMotion ? 3 : 0)
                                .shadow(color: lit ? color.opacity(0.9) : .clear, radius: lit ? 16 : 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(SimonSegment(index: index))
                    .disabled(!engine.started || engine.showingSequence)
                    .accessibilityLabel(Text(verbatim: ["●", "◆", "▲", "■"][index]))
                }
                // The step counter is pressed into the middle of the console.
                Circle().fill(palette.socket).frame(width: side * 0.34, height: side * 0.34)
                    .overlay {
                        Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.25), .white.opacity(0.2)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 3)
                    }
                    .overlay {
                        VStack(spacing: 0) {
                            Text(verbatim: "\(engine.sequence.count)")
                                .font(.system(size: side * 0.12, weight: .black, design: .rounded))
                                .contentTransition(.numericText())
                            Text(L10n.text("steps")).font(.system(.caption, design: .rounded).weight(.bold)).opacity(0.6)
                        }
                        .foregroundStyle(palette.ink)
                    }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.12), value: engine.highlighted)
        }
    }

    private var simon: some View {
        let palette = Self.simonPalette
        return VStack(spacing: 16) {
            // Before the first round the button below says "Start".
            Text(L10n.text(!engine.started ? "Watch, remember, repeat"
                           : engine.feedback.isEmpty ? engine.message : engine.feedback))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(engine.feedback.isEmpty ? palette.ink : Color(red: 0.95, green: 0.45, blue: 0.2))
                .lineLimit(1).minimumScaleFactor(0.6)
            console
            .aspectRatio(1, contentMode: .fit)
            // The start button and the rules keep their place once the game runs.
            ToyCapsuleButton(title: L10n.text("Start"), symbol: "play.fill", color: palette.accent, ink: .white) { engine.start() }
                .frame(maxWidth: 240)
                .opacity(engine.started ? 0 : 1)
                .disabled(engine.started)
            Text(L10n.text("Repeat the growing sequence. It speeds up as it gets longer. One mistake is forgiven."))
                .font(.system(.footnote, design: .rounded)).foregroundStyle(palette.ink)
                .opacity(engine.started ? 0 : 0.6)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.3), value: engine.started)
    }
}

/// One quarter of the classic round Simon board, with a small gap between pads.
private struct SimonSegment: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2 - 6
        let inner = outer * 0.42
        let gap = 4.0
        let start = Double(index) * 90 + 180 + gap, end = start + 90 - gap * 2
        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}
