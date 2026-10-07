import SwiftUI
import Observation

enum BrainArcadeMode { case reaction, simon, higherLower }

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
    private(set) var number = 50
    private(set) var previousNumber = 50
    private(set) var lives = 3
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
        switch mode { case .reaction: .reactionTap; case .simon: .simon; case .higherLower: .higherLower }
    }
    func restart() {
        score = 0; state = .playing; started = false; message = "Tap to start"; ready = false
        highlighted = nil; sequence = []; showingSequence = false; round = 0
        reactionTimes = []; falseStarts = 0; number = Int.random(in: 10...90); previousNumber = number
        lives = 3; feedback = ""; remaining = 0; readySince = nil; feedbackRemaining = 0
        sequenceStep = -1; inputIndex = 0
    }
    func start() {
        guard state == .playing, active, !started else { return }
        started = true
        switch mode {
        case .reaction: prepareReaction()
        case .simon: addSequence()
        case .higherLower: message = "Will the next number be higher or lower?"
        }
    }
    private func prepareReaction() {
        ready = false; readySince = nil; message = "Wait for green…"
        remaining = Double.random(in: 1.5...4.5)
    }
    func tapReaction() {
        guard active, state == .playing else { return }
        if !started { start(); return }
        guard feedbackRemaining <= 0 else { return }
        if !ready {
            falseStarts += 1; Haptics.error(); feedback = "Too soon!"; feedbackRemaining = 1
            if falseStarts >= 3 { state = .gameOver(won: false) }
        } else {
            let now = ProcessInfo.processInfo.systemUptime
            let milliseconds = max(1, Int((now - (readySince ?? now)) * 1000))
            reactionTimes.append(milliseconds); score += max(0, 1000 - milliseconds)
            round += 1; ready = false; feedback = ""; feedbackRemaining = 1
            message = "Reaction recorded"
            Haptics.success()
            if round == 5 { state = .gameOver(won: true) }
        }
    }
    private func addSequence() {
        sequence.append(Int.random(in: 0..<4)); showingSequence = true
        sequenceStep = -1; inputIndex = 0; remaining = 0.7; highlighted = nil; message = "Watch the sequence"
    }
    func tapColor(_ index: Int) {
        guard active, state == .playing, started, !showingSequence, feedbackRemaining <= 0 else { return }
        guard sequence[inputIndex] == index else { state = .gameOver(won: false); Haptics.error(); return }
        highlighted = index; remaining = 0.16; inputIndex += 1; Haptics.tap()
        if inputIndex == sequence.count {
            score += sequence.count * 10; round += 1; showingSequence = true
            feedbackRemaining = 0.6
        }
    }
    func guess(higher: Bool) {
        guard active, state == .playing, started, feedbackRemaining <= 0 else { return }
        previousNumber = number
        repeat { number = Int.random(in: 1...100) } while number == previousNumber
        if (number > previousNumber) == higher {
            score += 10; feedback = "Correct!"; Haptics.success()
        } else {
            lives -= 1; feedback = "Wrong guess"; Haptics.error()
        }
        round += 1; feedbackRemaining = 0.8
        if lives == 0 { state = .gameOver(won: false) }
        else if round == 10 { state = .gameOver(won: true) }
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
                case .higherLower: break
                }
            }
            return
        }
        switch mode {
        case .reaction:
            if !ready {
                remaining -= dt
                if remaining <= 0 { ready = true; readySince = ProcessInfo.processInfo.systemUptime; message = "Tap now!" }
            }
        case .simon:
            remaining -= dt
            if showingSequence, remaining <= 0 {
                sequenceStep += 1
                if sequenceStep >= sequence.count * 2 {
                    showingSequence = false; highlighted = nil; message = "Repeat the sequence"
                } else {
                    highlighted = sequenceStep.isMultiple(of: 2) ? sequence[sequenceStep / 2] : nil
                    remaining = sequenceStep.isMultiple(of: 2) ? 0.45 : 0.22
                }
            } else if !showingSequence, remaining <= 0 { highlighted = nil }
        case .higherLower: break
        }
    }
}

struct BrainArcadeView: View {
    @State private var engine: BrainArcadeEngine
    @Environment(\.scenePhase) private var scenePhase
    private let colors: [Color] = [.cyan, .pink, .yellow, .purple]
    init(mode: BrainArcadeMode) { _engine = State(initialValue: BrainArcadeEngine(mode: mode)) }

    private var summary: String {
        if engine.mode == .reaction, !engine.reactionTimes.isEmpty {
            return L10n.format("Average: %d ms", engine.reactionTimes.reduce(0, +) / engine.reactionTimes.count)
        }
        return L10n.format("Rounds: %d", engine.round)
    }
    var body: some View {
        GameContainerView(gameID: engine.gameID, engine: engine, resultSummary: summary, centersContent: true) {
            VStack(spacing: 20) {
                Text(L10n.text(engine.message)).font(.title3.bold()).multilineTextAlignment(.center)
                switch engine.mode {
                case .reaction:
                    Text(L10n.format("Round %d of %d", min(5, engine.round + 1), 5)).foregroundStyle(Theme.textSecondary)
                    Button { engine.tapReaction() } label: {
                        VStack(spacing: 14) {
                            Image(systemName: engine.ready ? "bolt.fill" : "hand.tap.fill").font(.system(size: 48))
                            Text(L10n.text(engine.feedback.isEmpty ? engine.message : engine.feedback)).font(.title2.bold())
                        }
                        .frame(maxWidth: .infinity).frame(height: 250)
                        .foregroundStyle(engine.ready ? .black : .white)
                        .background(engine.ready ? Theme.neon : Theme.surfaceHigh, in: RoundedRectangle(cornerRadius: 24))
                    }
                    if let last = engine.reactionTimes.last { Text(L10n.format("Reaction: %d ms", last)).foregroundStyle(Theme.neon) }
                    Text(L10n.format("False starts: %d/3", engine.falseStarts)).font(.footnote)
                case .simon:
                    Text(L10n.format("Sequence: %d", engine.sequence.count)).foregroundStyle(Theme.neon)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(0..<4, id: \.self) { index in
                            Button { engine.tapColor(index) } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20).fill(colors[index].opacity(engine.highlighted == index ? 1 : 0.28))
                                    Text(verbatim: ["●", "◆", "▲", "■"][index]).font(.system(size: 36)).foregroundStyle(.white)
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(engine.highlighted == index ? .white : .clear, lineWidth: 4) }
                            }
                            .disabled(!engine.started || engine.showingSequence)
                        }
                    }
                    if !engine.started { startButton }
                case .higherLower:
                    Text(L10n.format("Lives: %d", engine.lives)).foregroundStyle(Theme.neon)
                    Text(verbatim: "\(engine.number)")
                        .font(.system(size: 90, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).padding(24).themeCard()
                    if !engine.feedback.isEmpty {
                        Text(verbatim: "\(engine.previousNumber) → \(engine.number)").foregroundStyle(Theme.textSecondary)
                        Text(L10n.text(engine.feedback)).font(.headline)
                    }
                    if engine.started {
                        HStack(spacing: 16) {
                            guessButton("Lower", higher: false)
                            guessButton("Higher", higher: true)
                        }
                        Text(L10n.format("Round %d of %d", min(10, engine.round + 1), 10)).font(.footnote)
                    } else { startButton }
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
    private var startButton: some View {
        Button { engine.start() } label: {
            Text(L10n.text("Tap to start")).font(.headline).frame(maxWidth: .infinity).padding(18)
                .foregroundStyle(.black).background(Theme.neon, in: RoundedRectangle(cornerRadius: 14))
        }
    }
    private func guessButton(_ text: String, higher: Bool) -> some View {
        Button { engine.guess(higher: higher) } label: {
            Label(L10n.text(text), systemImage: higher ? "arrow.up" : "arrow.down")
                .font(.headline).frame(maxWidth: .infinity).padding(18)
                .foregroundStyle(.black).background(Theme.neon, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
