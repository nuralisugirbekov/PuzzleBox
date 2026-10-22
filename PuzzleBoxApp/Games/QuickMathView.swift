import SwiftUI
import Observation

@MainActor
@Observable
final class QuickMathEngine: GameEngine {
    static let durations = [30, 60, 120]
    private(set) var hasStarted = false
    private(set) var score = 0
    private(set) var solved = 0
    private(set) var mistakes = 0
    private(set) var expression = ""
    private(set) var input = ""
    private(set) var wrongAnswer = false
    private(set) var remaining: TimeInterval = 60
    /// Correct answers in a row without a mistake.
    private(set) var streak = 0
    private(set) var lastGain = 0
    /// Bumped on every correct answer so the view can flash.
    private(set) var flash = 0
    private var answer = 0
    private var active = false
    private var anchor: TimeInterval?
    var secondsLeft: Int { Int(ceil(remaining)) }

    var state: GameState = .playing {
        willSet { consumeTime() }
        didSet { anchor = hasStarted && active && state == .playing ? ProcessInfo.processInfo.systemUptime : nil }
    }

    func restart() {
        anchor = nil
        hasStarted = false
        score = 0
        solved = 0
        mistakes = 0
        streak = 0
        lastGain = 0
        input = ""
        wrongAnswer = false
        remaining = 60
        state = .playing
    }

    func start(seconds: Int) {
        guard !hasStarted, Self.durations.contains(seconds) else { return }
        remaining = TimeInterval(seconds)
        hasStarted = true
        nextProblem()
        anchor = active ? ProcessInfo.processInfo.systemUptime : nil
        AppAnalytics.log("quick_math_started", parameters: ["duration_seconds": seconds])
    }

    func setActive(_ value: Bool) {
        consumeTime()
        active = value
        anchor = value && hasStarted && state == .playing ? ProcessInfo.processInfo.systemUptime : nil
        tick()
    }

    private func consumeTime() {
        guard let anchor else { return }
        let now = ProcessInfo.processInfo.systemUptime
        remaining = max(0, remaining - (now - anchor))
        self.anchor = now
    }

    func tick() {
        guard hasStarted, state == .playing else { return }
        consumeTime()
        if remaining <= 0 { state = .gameOver(won: true) }
    }

    func enter(_ digit: Int) {
        tick()
        guard hasStarted, active, state == .playing, (0...9).contains(digit) else { return }
        if wrongAnswer { input = ""; wrongAnswer = false }
        guard input.count < 3 else { return }
        SoundFX.play(.tap)
        input = input == "0" ? String(digit) : input + String(digit)
        // Answers check themselves once enough digits are typed.
        if input.count >= String(answer).count { submit() }
    }

    func erase() {
        guard hasStarted, active, state == .playing else { return }
        if !input.isEmpty { input.removeLast() }
        wrongAnswer = false
    }

    func submit() {
        tick()
        guard hasStarted, active, state == .playing, let value = Int(input) else { return }
        if value == answer {
            solved += 1
            streak += 1
            lastGain = 10 * multiplier
            score += lastGain
            flash += 1
            Haptics.success(); SoundFX.play(multiplier > 1 ? .coin : .point)
            nextProblem()
        } else {
            // Keep the same problem, so repeated guessing cannot skip difficult questions.
            mistakes += 1
            streak = 0
            wrongAnswer = true
            input = ""
            Haptics.error(); SoundFX.play(.wrong)
        }
    }

    /// Every five correct answers bumps the multiplier, up to ×4.
    var multiplier: Int { min(4, 1 + streak / 5) }
    /// Problems grow as you solve more of them.
    var tier: Int { min(4, solved / 6) }

    private func nextProblem() {
        let previous = expression
        let top = 10 + tier * 12
        repeat {
            let a = Int.random(in: 1...top), b = Int.random(in: 1...top)
            switch Int.random(in: 0..<(tier >= 3 ? 5 : 4)) {
            case 0: expression = "\(a) + \(b)"; answer = a + b
            case 1: expression = "\(max(a, b)) − \(min(a, b))"; answer = abs(a - b)
            case 2:
                let x = Int.random(in: 2...(6 + tier * 2)), y = Int.random(in: 2...(6 + tier * 2))
                expression = "\(x) × \(y)"; answer = x * y
            case 3:
                let divisor = Int.random(in: 2...(6 + tier * 2)), quotient = Int.random(in: 1...(6 + tier * 2))
                expression = "\(divisor * quotient) ÷ \(divisor)"; answer = quotient
            default:
                // Two-step problems for the top tiers.
                let x = Int.random(in: 2...9), y = Int.random(in: 2...9), z = Int.random(in: 1...20)
                expression = "\(x) × \(y) + \(z)"; answer = x * y + z
            }
        } while expression == previous || answer > 999
        input = ""
        wrongAnswer = false
    }
}

struct QuickMathView: View {
    @State private var engine = QuickMathEngine.resumable()
    @State private var duration = 60
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if engine.hasStarted { round } else { setup }
        }
        .background(GameTheme.background.ignoresSafeArea())
    }

    private var setup: some View {
        VStack(spacing: 24) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44).glassCircle()
                }
                .accessibilityLabel(L10n.text("Main Menu"))
                Spacer()
            }
            Spacer()
            Image(systemName: "plus.forwardslash.minus").font(.system(size: 48)).foregroundStyle(GameTheme.accent)
            Text(L10n.text("Quick Math")).font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.text("Solve as many sums as you can before time runs out."))
                    .foregroundStyle(GameTheme.textSecondary)
                Picker(L10n.text("Choose challenge time"), selection: $duration) {
                    ForEach(QuickMathEngine.durations, id: \.self) { seconds in
                        Text(L10n.text(seconds == 30 ? "30 seconds" : seconds == 60 ? "1 minute" : "2 minutes")).tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                Text(L10n.text("10 points per correct answer"))
                    .font(.caption).foregroundStyle(GameTheme.textSecondary)
                Button { engine.start(seconds: duration) } label: {
                    Text(L10n.text("Start challenge")).font(.headline)
                        .frame(maxWidth: .infinity).padding(16)
                        .foregroundStyle(.white)
                        .background(GameTheme.accent, in: Capsule())
                }
            }
            .padding(20).gameCard()
            Spacer()
        }
        .padding().foregroundStyle(GameTheme.ink)
    }

    private var round: some View {
        GameContainerView(gameID: .quickMath, engine: engine,
                          resultTitle: L10n.text("Time's up!"),
                          resultSummary: L10n.format("Solved: %d", engine.solved) + "\n" + L10n.format("%d mistakes", engine.mistakes)) {
            VStack(spacing: 16) {
                HStack {
                    Label(String(format: "%d:%02d", engine.secondsLeft / 60, engine.secondsLeft % 60), systemImage: "timer")
                        .foregroundStyle(engine.secondsLeft <= 5 ? .red : GameTheme.accent)
                    if engine.multiplier > 1 {
                        Label { Text(verbatim: "×\(engine.multiplier)") } icon: { Image(systemName: "flame.fill") }
                            .foregroundStyle(.orange)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    Text(L10n.format("Solved: %d", engine.solved))
                }
                .animation(.snappy, value: engine.multiplier)
                .font(.headline.monospacedDigit())
                VStack(spacing: 12) {
                    Text(verbatim: engine.expression + " = ?")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .id(engine.expression)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                        .animation(.snappy(duration: 0.2), value: engine.expression)
                        .overlay(alignment: .topTrailing) {
                            if engine.lastGain > 0 {
                                Text(verbatim: "+\(engine.lastGain)")
                                    .font(.headline.bold()).foregroundStyle(.green)
                                    .id(engine.flash)
                                    .transition(.asymmetric(insertion: .scale, removal: .move(edge: .top).combined(with: .opacity)))
                                    .offset(y: -18)
                            }
                        }
                    Text(verbatim: engine.input.isEmpty ? "…" : engine.input)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(GameTheme.accent)
                    Text(L10n.text(engine.wrongAnswer ? "Wrong answer — try again" : "Type the answer — it checks itself. Answer in a row to build a multiplier."))
                        .font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(engine.wrongAnswer ? .red : GameTheme.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(20).gameCard()
                .overlay {
                    RoundedRectangle(cornerRadius: 24).strokeBorder(engine.wrongAnswer ? Color.red : Color.clear, lineWidth: 2)
                }
                .keyframeAnimator(initialValue: CGFloat(0), trigger: engine.mistakes) { content, x in
                    content.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(8, duration: 0.05); LinearKeyframe(-8, duration: 0.05)
                        LinearKeyframe(5, duration: 0.05); LinearKeyframe(0, duration: 0.05)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(1...3, id: \.self) { col in
                                key(String(row * 3 + col)) { engine.enter(row * 3 + col) }
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        key("⌫", accessibility: L10n.text("Erase")) { engine.erase() }
                        key("0") { engine.enter(0) }
                        key("✓", accessibility: L10n.text("Check answer"), highlighted: true) { engine.submit() }
                    }
                }
            }
        }
        .onAppear { engine.setActive(scenePhase == .active) }
        .onDisappear { engine.setActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setActive(phase == .active) }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                engine.tick()
            }
        }
    }

    private func key(_ title: String, accessibility: String? = nil, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title).font(.title2.bold())
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(highlighted ? Color.white : GameTheme.ink)
                .background(highlighted ? GameTheme.accent : GameTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel(accessibility ?? title)
    }
}

extension QuickMathEngine: ResumableGame {
    private struct Session: Codable {
        var remaining: TimeInterval
        var score, solved, mistakes, streak, answer: Int
        var expression: String
    }

    func saveSession() -> Data? {
        tick()
        guard hasStarted, state == .playing || state == .paused, remaining > 0 else { return nil }
        return encodeSession(Session(remaining: remaining, score: score, solved: solved, mistakes: mistakes,
                                     streak: streak, answer: answer, expression: expression))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), s.remaining > 0 else { return false }
        anchor = nil
        remaining = s.remaining
        score = s.score; solved = s.solved; mistakes = s.mistakes; streak = s.streak
        expression = s.expression; answer = s.answer
        input = ""; wrongAnswer = false; lastGain = 0
        hasStarted = true
        return true
    }

    /// An engine already holding a saved round, so the view opens on the board
    /// (where the container asks to continue) instead of the setup screen.
    static func resumable() -> QuickMathEngine {
        let engine = QuickMathEngine()
        if let session = GameSessionStore.load(.quickMath) { _ = engine.restoreSession(session.payload) }
        return engine
    }
}
