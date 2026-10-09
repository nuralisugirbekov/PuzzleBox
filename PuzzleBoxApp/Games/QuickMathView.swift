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
        input = input == "0" ? String(digit) : input + String(digit)
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
            score += 10
            Haptics.success()
            nextProblem()
        } else {
            // Keep the same problem, so repeated guessing cannot skip difficult questions.
            mistakes += 1
            wrongAnswer = true
            input = ""
            Haptics.error()
        }
    }

    private func nextProblem() {
        let previous = expression
        repeat {
            let a = Int.random(in: 1...20), b = Int.random(in: 1...20)
            switch Int.random(in: 0..<4) {
            case 0: expression = "\(a) + \(b)"; answer = a + b
            case 1: expression = "\(max(a, b)) − \(min(a, b))"; answer = abs(a - b)
            case 2:
                let x = Int.random(in: 2...12), y = Int.random(in: 2...12)
                expression = "\(x) × \(y)"; answer = x * y
            default:
                let divisor = Int.random(in: 2...12), quotient = Int.random(in: 1...12)
                expression = "\(divisor * quotient) ÷ \(divisor)"; answer = quotient
            }
        } while expression == previous
        input = ""
        wrongAnswer = false
    }
}

struct QuickMathView: View {
    @State private var engine = QuickMathEngine()
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
                          resultSummary: L10n.format("Solved: %d", engine.solved) + "\n" + L10n.format("%d mistakes", engine.mistakes),
                          centersContent: true) {
            VStack(spacing: 16) {
                HStack {
                    Label(String(format: "%d:%02d", engine.secondsLeft / 60, engine.secondsLeft % 60), systemImage: "timer")
                        .foregroundStyle(engine.secondsLeft <= 5 ? .red : GameTheme.accent)
                    Spacer()
                    Text(L10n.format("Solved: %d", engine.solved))
                }
                .font(.headline.monospacedDigit())
                VStack(spacing: 12) {
                    Text(verbatim: engine.expression + " = ?")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(verbatim: engine.input.isEmpty ? "…" : engine.input)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(GameTheme.accent)
                    Text(L10n.text(engine.wrongAnswer ? "Wrong answer — try again" : "Enter the answer and tap Check."))
                        .font(.footnote).multilineTextAlignment(.center)
                        .foregroundStyle(engine.wrongAnswer ? .red : GameTheme.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(20).gameCard()
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
