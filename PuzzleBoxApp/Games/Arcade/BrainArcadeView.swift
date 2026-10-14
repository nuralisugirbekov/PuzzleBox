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
    var body: some View {
        GameContainerView(gameID: engine.gameID, engine: engine, resultSummary: summary, centersContent: true) {
            VStack(spacing: 18) {
                switch engine.mode {
                case .reaction: reaction
                case .simon: simon
                }
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
                engine.advance(min(0.1, now - last)); last = now
            }
        }
    }

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

    private var simon: some View {
        VStack(spacing: 18) {
            HStack {
                Text(L10n.text(engine.feedback.isEmpty ? engine.message : engine.feedback))
                    .font(.title3.bold())
                    .foregroundStyle(engine.feedback.isEmpty ? GameTheme.ink : Color.orange)
                Spacer()
                Image(systemName: engine.secondChance ? "heart.fill" : "heart")
                    .foregroundStyle(engine.secondChance ? Color.pink : GameTheme.textSecondary)
                    .accessibilityLabel(L10n.text("Second chance"))
            }
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    Circle().fill(Color(white: 0.12))
                    ForEach(0..<4, id: \.self) { index in
                        let lit = engine.highlighted == index
                        Button { engine.tapColor(index) } label: {
                            SimonSegment(index: index)
                                .fill(colors[index].opacity(lit ? 1 : 0.38).gradient)
                                .shadow(color: lit ? colors[index] : .clear, radius: lit ? 18 : 0)
                                .scaleEffect(lit && !reduceMotion ? 1.03 : 1)
                        }
                        .buttonStyle(.plain)
                        .contentShape(SimonSegment(index: index))
                        .disabled(!engine.started || engine.showingSequence)
                        .accessibilityLabel(Text(verbatim: ["●", "◆", "▲", "■"][index]))
                    }
                    Circle().fill(GameTheme.background).frame(width: side * 0.36, height: side * 0.36)
                        .overlay {
                            VStack(spacing: 0) {
                                Text(verbatim: "\(engine.sequence.count)").font(.system(size: side * 0.12, weight: .black, design: .rounded))
                                Text(L10n.text("steps")).font(.caption).foregroundStyle(GameTheme.textSecondary)
                            }
                        }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeOut(duration: 0.12), value: engine.highlighted)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 360)
            if !engine.started { startButton }
            Text(L10n.text("Repeat the growing sequence. It speeds up as it gets longer. One mistake is forgiven."))
                .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
        }
    }

    private var startButton: some View {
        Button { engine.start() } label: {
            Text(L10n.text("Tap to start")).font(.headline).frame(maxWidth: .infinity).padding(18)
                .foregroundStyle(.white).background(GameTheme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
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
