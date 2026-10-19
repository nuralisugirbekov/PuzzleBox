import SwiftUI
import Observation

// MARK: - Engine (vs bot)

@MainActor
@Observable
final class HangmanEngine: GameEngine {
    static let playerSeat = 0
    static let botSeat = 1

    private(set) var table = HangmanEngine.newTable()
    var state: GameState = .playing {
        didSet { if state == .playing { scheduleBot() } }
    }

    @ObservationIgnored private var botTask: Task<Void, Never>?

    /// A win is worth 100, plus 10 for every letter the player opened.
    var score: Int {
        table.outcome == .winner(Self.playerSeat) ? 100 + 10 * table.opened[Self.playerSeat] : 0
    }

    init() { scheduleBot() }

    private static func newTable() -> HangmanState {
        HangmanState.newGame(language: HangmanLanguage(app: L10n.language))
    }

    func restart() {
        botTask?.cancel()
        table = Self.newTable()
        state = .playing
        scheduleBot()
    }

    func guess(_ letter: String) {
        guard state == .playing, let next = try? table.applying(.guess(letter), by: Self.playerSeat) else { return }
        commit(next)
    }

    private func commit(_ next: HangmanState) {
        table = next
        HangmanState.playFeedback(for: next)
        if let outcome = table.outcome {
            state = .gameOver(won: outcome == .winner(Self.playerSeat))
        } else {
            scheduleBot()
        }
    }

    private func scheduleBot() {
        botTask?.cancel()
        guard state == .playing, table.currentTurn == Self.botSeat else { return }
        botTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled, self.state == .playing,
                  let action = HangmanBot.action(for: self.table),
                  let next = try? self.table.applying(action, by: Self.botSeat) else { return }
            self.commit(next)
        }
    }
}

extension HangmanEngine: ResumableGame {
    func saveSession() -> Data? {
        guard table.outcome == nil, !table.guessed.isEmpty else { return nil }
        return encodeSession(table)
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let saved = decodeSession(HangmanState.self, from: data), saved.outcome == nil else { return false }
        botTask?.cancel()
        table = saved
        state = .playing
        return true
    }
}

// MARK: - Online match

extension HangmanState: OnlineGameState {
    var isFinished: Bool { outcome != nil }

    static func playFeedback(for state: HangmanState) {
        guard let move = state.lastMove else { return }
        if move.hit {
            Haptics.tap(); SoundFX.play(.point)
        } else {
            Haptics.move(); SoundFX.play(.wrong)
        }
    }

    func result(for seat: Int, names: [String]) -> OnlineMatchResult? {
        guard let outcome else {
            // Knocked out while the others play on; the word stays hidden from them.
            return isOut(seat) ? OnlineMatchResult(title: L10n.text("Game Over"), message: L10n.text("You're out"),
                                                   won: false, score: 0) : nil
        }
        let reveal = L10n.format("The word: %@", word.joined())
        if outcome == .winner(seat) {
            return OnlineMatchResult(title: L10n.text("You Win!"), message: reveal,
                                     won: true, score: 100 + 10 * opened[seat])
        }
        return OnlineMatchResult(title: L10n.text("Game Over"), message: reveal, won: false, score: 0)
    }
}

// MARK: - Bot game view

struct HangmanView: View {
    @State private var engine = HangmanEngine()

    var body: some View {
        GameContainerView(gameID: .hangman, engine: engine,
                          resultSummary: engine.table.isFinished
                              ? L10n.format("The word: %@", engine.table.word.joined()) : nil) {
            HangmanTableView(table: engine.table,
                             seat: HangmanEngine.playerSeat,
                             names: [L10n.text("You"), L10n.text("Bot")],
                             onAction: { action in
                                 if case .guess(let letter) = action { engine.guess(letter) }
                             })
        }
    }
}

// MARK: - Table

/// The shared word from `seat`'s side: every player's opened letters, the
/// gallows, the word and the letter keyboard.
struct HangmanTableView: View {
    let table: HangmanState
    let seat: Int
    /// Every seat's name, this player's included.
    let names: [String]
    let onAction: (HangmanAction) -> Void

    private var myTurn: Bool { table.currentTurn == seat }

    private func name(_ player: Int) -> String {
        if player == seat { return L10n.text("You") }
        return names.indices.contains(player) ? names[player] : L10n.format("Player %d", player + 1)
    }

    var body: some View {
        VStack(spacing: 14) {
            players
            GallowsView(mistakes: table.mistakes, lost: table.isFinished && !table.isSolved)
                .frame(maxWidth: 220, maxHeight: 190)
                .frame(maxHeight: .infinity)
            Text(L10n.format("Mistakes: %d/%d", table.mistakes, HangmanState.maxMistakes))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            word
            status
            keyboard
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: table)
    }

    // MARK: Players

    /// This player first, then the others in seat order.
    private var players: some View {
        let order = (0..<table.playerCount).map { (seat + $0) % table.playerCount }
        return HStack(spacing: 8) {
            ForEach(order, id: \.self) { player in
                playerChip(player, compact: table.playerCount > 2)
            }
        }
    }

    private func playerChip(_ player: Int, compact: Bool) -> some View {
        let active = table.currentTurn == player
        let out = table.isOut(player)
        return HStack(spacing: 6) {
            Text(name(player))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .strikethrough(out)
            Spacer(minLength: 2)
            Label("\(table.opened[player])", systemImage: "textformat.abc")
                .labelStyle(.titleAndIcon)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay {
            Capsule().strokeBorder(GameTheme.accent, lineWidth: 2).opacity(active ? 1 : 0)
        }
        .opacity(out ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: Word

    private var word: some View {
        GeometryReader { geo in
            let count = CGFloat(table.word.count)
            let slot = min(36, (geo.size.width - (count - 1) * 6) / count)
            HStack(spacing: 6) {
                ForEach(Array(table.word.enumerated()), id: \.offset) { index, letter in
                    let revealed = table.isRevealed(index)
                    // Once the game is over, the letters nobody found show in red.
                    let shown = revealed || table.isFinished
                    // The letter flips into its empty slot when it opens.
                    Text(letter)
                        .font(.system(size: slot * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(revealed ? Color.primary : Color.red)
                        .opacity(shown ? 1 : 0)
                        .rotation3DEffect(.degrees(shown ? 0 : 90), axis: (x: 1, y: 0, z: 0))
                        .frame(width: slot, height: slot * 1.2)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(height: 2)
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(table.word.indices.map { table.isRevealed($0) ? table.word[$0] : "_" }.joined(separator: " "))
    }

    // MARK: Status

    private var status: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(myTurn ? .primary : .secondary)
                .contentTransition(.opacity)
            if let move = table.lastMove {
                HStack(spacing: 4) {
                    Text("\(name(move.seat)): \(move.letter)")
                    Image(systemName: move.hit ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(move.hit ? .green : .red)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .id(table.guessed.count)
                .transition(.opacity)
            }
        }
        .frame(minHeight: 40)
    }

    private var statusText: String {
        if table.isOut(seat) && table.outcome == nil { return L10n.text("You're out") }
        guard let turn = table.currentTurn else { return " " }
        return turn == seat ? L10n.text("Your turn: pick a letter") : L10n.format("%@ is thinking…", name(turn))
    }

    // MARK: Keyboard

    private var keyboard: some View {
        let letters = table.language.alphabet
        let rows = letters.count > 33 ? 5 : 4
        let columnCount = Int((Double(letters.count) / Double(rows)).rounded(.up))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: columnCount)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(letters, id: \.self) { letter in
                key(letter)
            }
        }
    }

    private func key(_ letter: String) -> some View {
        let used = table.guessed.contains(letter)
        let hit = used && table.word.contains(letter)
        let enabled = myTurn && table.canGuess(letter)
        return Button {
            onAction(.guess(letter))
        } label: {
            Text(letter)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(used ? Color.white : Color.primary)
                .background(used ? (hit ? Color.green : Color.gray.opacity(0.45)) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if used && !hit {
                        Rectangle().fill(Color.white.opacity(0.8)).frame(height: 1.5).rotationEffect(.degrees(-20))
                            .padding(.horizontal, 8)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(!used && !myTurn ? 0.55 : 1)
        .accessibilityLabel(letter)
        .accessibilityValue(used ? L10n.text(hit ? "In the word" : "Not in the word") : "")
    }
}

// MARK: - Gallows

/// The gallows, with one more part of the man for every mistake. Each part
/// draws itself in as it appears.
struct GallowsView: View {
    let mistakes: Int
    /// The man is complete: drawn in red.
    var lost = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let unit = size / 100
            ZStack {
                ForEach(Array(Self.frame.enumerated()), id: \.offset) { _, part in
                    stroke(part, unit: unit, color: .primary.opacity(0.75), width: 4)
                }
                ForEach(Array(Self.man.enumerated()), id: \.offset) { index, part in
                    stroke(part, unit: unit, color: lost ? .red : .primary, width: 3.5)
                        .opacity(index < mistakes ? 1 : 0)
                        .animation(.easeOut(duration: 0.45), value: mistakes)
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Mistakes: %d/%d", mistakes, HangmanState.maxMistakes))
    }

    private func stroke(_ part: Part, unit: CGFloat, color: Color, width: CGFloat) -> some View {
        part.shape(unit)
            .trim(from: 0, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// A part drawn in a 100×100 box.
    private enum Part {
        case line(CGPoint, CGPoint)
        case circle(center: CGPoint, radius: CGFloat)

        func shape(_ unit: CGFloat) -> Path {
            var path = Path()
            switch self {
            case .line(let from, let to):
                path.move(to: CGPoint(x: from.x * unit, y: from.y * unit))
                path.addLine(to: CGPoint(x: to.x * unit, y: to.y * unit))
            case .circle(let center, let radius):
                path.addEllipse(in: CGRect(x: (center.x - radius) * unit, y: (center.y - radius) * unit,
                                           width: radius * 2 * unit, height: radius * 2 * unit))
            }
            return path
        }
    }

    private static let frame: [Part] = [
        .line(CGPoint(x: 10, y: 95), CGPoint(x: 60, y: 95)),
        .line(CGPoint(x: 25, y: 95), CGPoint(x: 25, y: 6)),
        .line(CGPoint(x: 25, y: 6), CGPoint(x: 68, y: 6)),
        .line(CGPoint(x: 25, y: 22), CGPoint(x: 41, y: 6)),
        .line(CGPoint(x: 68, y: 6), CGPoint(x: 68, y: 18)),
    ]

    /// Head, body, arms, legs: one per mistake, in order.
    private static let man: [Part] = [
        .circle(center: CGPoint(x: 68, y: 27), radius: 9),
        .line(CGPoint(x: 68, y: 36), CGPoint(x: 68, y: 62)),
        .line(CGPoint(x: 68, y: 42), CGPoint(x: 56, y: 54)),
        .line(CGPoint(x: 68, y: 42), CGPoint(x: 80, y: 54)),
        .line(CGPoint(x: 68, y: 62), CGPoint(x: 58, y: 80)),
        .line(CGPoint(x: 68, y: 62), CGPoint(x: 78, y: 80)),
    ]
}
