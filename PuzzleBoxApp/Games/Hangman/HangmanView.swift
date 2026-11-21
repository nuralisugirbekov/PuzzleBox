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
        let palette = ToyHangman.palette
        GameContainerView(gameID: .hangman, engine: engine,
                          resultSummary: engine.table.isFinished
                              ? L10n.format("The word: %@", engine.table.word.joined()) : nil,
                          chrome: .inGame,
                          backdrop: AnyView(palette.backdrop),
                          toyStyle: palette.style) {
            ToyGameStage(palette: palette, headline: .clock(caption: L10n.text("vs Bot"))) {
                HangmanTableView(table: engine.table,
                                 seat: HangmanEngine.playerSeat,
                                 names: [L10n.text("You"), L10n.text("Bot")],
                                 onAction: { action in
                                     if case .guess(let letter) = action { engine.guess(letter) }
                                 })
                    .padding(.top, 12)
            }
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
    /// Only the gallows and the word, for the Home preview.
    var preview = false

    private var myTurn: Bool { table.currentTurn == seat }
    private let palette = ToyHangman.palette
    static let hit = Color.dynamic(light: (0.40, 0.74, 0.52), dark: (0.34, 0.64, 0.46))
    static let miss = Color.dynamic(light: (0.88, 0.38, 0.38), dark: (0.90, 0.45, 0.45))

    private func name(_ player: Int) -> String {
        if player == seat { return L10n.text("You") }
        return names.indices.contains(player) ? names[player] : L10n.format("Player %d", player + 1)
    }

    var body: some View {
        if preview {
            VStack(spacing: 16) {
                GallowsView(mistakes: table.mistakes, lost: false, wooden: true)
                    .frame(width: 190, height: 170)
                mistakesRow
                word
            }
            .foregroundStyle(palette.ink)
        } else {
            game
        }
    }

    private var game: some View {
        VStack(spacing: 14) {
            players
            GallowsView(mistakes: table.mistakes, lost: table.isFinished && !table.isSolved, wooden: true)
                .frame(maxWidth: 220, maxHeight: 190)
                .frame(maxHeight: .infinity)
            mistakesRow
            word
            status
            keyboard
        }
        .foregroundStyle(palette.ink)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: table)
    }

    /// One bead per allowed mistake, filled red as they are used.
    private var mistakesRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<HangmanState.maxMistakes, id: \.self) { index in
                Group {
                    if index < table.mistakes {
                        ToyBlock(color: Self.miss, shape: Circle(), lip: 2, castsShadow: false)
                    } else {
                        ToySocket(color: palette.socket, shape: Circle())
                    }
                }
                .frame(width: 14, height: 14)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: table.mistakes)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Mistakes: %d/%d", table.mistakes, HangmanState.maxMistakes))
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
                .foregroundStyle(palette.ink.opacity(0.65))
        }
        .padding(.horizontal, compact ? 10 : 14)
        .frame(maxWidth: .infinity, minHeight: 40)
        .padding(.bottom, 3)
        .background { ToyBlock(color: palette.card, shape: Capsule(), lip: 3) }
        .overlay {
            Capsule().strokeBorder(palette.accent, lineWidth: 2.5).padding(.bottom, 3).opacity(active ? 1 : 0)
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
                    let tile = RoundedRectangle(cornerRadius: slot * 0.22, style: .continuous)
                    Text(letter)
                        .font(.system(size: slot * 0.62, weight: .heavy, design: .rounded))
                        .foregroundStyle(revealed ? palette.ink : Self.miss)
                        .opacity(shown ? 1 : 0)
                        .rotation3DEffect(.degrees(shown ? 0 : 90), axis: (x: 1, y: 0, z: 0))
                        .frame(width: slot, height: slot * 1.2)
                        // An empty well until the letter opens as a raised tile.
                        .background {
                            if revealed {
                                ToyBlock(color: palette.card, shape: tile, lip: 3, castsShadow: false)
                                    .padding(.bottom, -3)
                            } else {
                                ToySocket(color: palette.socket, shape: tile)
                            }
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
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(palette.ink.opacity(myTurn ? 1 : 0.6))
                .contentTransition(.opacity)
            if let move = table.lastMove {
                HStack(spacing: 4) {
                    Text("\(name(move.seat)): \(move.letter)")
                    Image(systemName: move.hit ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(move.hit ? Self.hit : Self.miss)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.ink.opacity(0.65))
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
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            onAction(.guess(letter))
        } label: {
            Text(letter)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(used ? (hit ? Color.white : palette.ink.opacity(0.35)) : palette.ink)
                .background {
                    // A used miss sinks into the board; a hit stays raised in green.
                    if used && !hit { ToySocket(color: palette.socket, shape: shape).padding(.bottom, -3) }
                }
        }
        .buttonStyle(KeyStyle(color: used ? (hit ? Self.hit : .clear) : palette.card, flat: used && !hit))
        .disabled(!enabled)
        .opacity(!used && !myTurn ? 0.55 : 1)
        .accessibilityLabel(letter)
        .accessibilityValue(used ? L10n.text(hit ? "In the word" : "Not in the word") : "")
    }
}

/// A keyboard key: raised clay, or flat once the letter missed.
private struct KeyStyle: ButtonStyle {
    let color: Color
    let flat: Bool

    func makeBody(configuration: Configuration) -> some View {
        if flat {
            configuration.label.padding(.bottom, 3)
        } else {
            ToyPressStyle(color: color, lip: 3, cornerRadius: 9).makeBody(configuration: configuration)
        }
    }
}

// MARK: - Gallows

/// The gallows, with one more part of the man for every mistake. Each part
/// draws itself in as it appears.
struct GallowsView: View {
    let mistakes: Int
    /// The man is complete: drawn in red.
    var lost = false
    /// Wooden beams and a rope, as on the game table; the catalog artwork keeps plain lines.
    var wooden = false

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let unit = size / 100
            ZStack {
                if wooden {
                    // Wooden beams: a darker edge under the wood.
                    ForEach(Array(Self.frame.enumerated()), id: \.offset) { _, part in
                        stroke(part, unit: unit, color: Self.woodEdge, width: 8)
                    }
                    ForEach(Array(Self.frame.enumerated()), id: \.offset) { _, part in
                        stroke(part, unit: unit, color: Self.wood, width: 5.5)
                    }
                    stroke(Self.rope, unit: unit, color: Self.ropeColor, width: 2.5)
                } else {
                    ForEach(Array(Self.plainFrame.enumerated()), id: \.offset) { _, part in
                        stroke(part, unit: unit, color: .primary.opacity(0.75), width: 4)
                    }
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
        .line(CGPoint(x: 25, y: 6), CGPoint(x: 72, y: 6)),
        .line(CGPoint(x: 25, y: 22), CGPoint(x: 41, y: 6)),
    ]

    /// The original line drawing, kept for the catalog artwork.
    private static let plainFrame: [Part] = [
        .line(CGPoint(x: 10, y: 95), CGPoint(x: 60, y: 95)),
        .line(CGPoint(x: 25, y: 95), CGPoint(x: 25, y: 6)),
        .line(CGPoint(x: 25, y: 6), CGPoint(x: 68, y: 6)),
        .line(CGPoint(x: 25, y: 22), CGPoint(x: 41, y: 6)),
        .line(CGPoint(x: 68, y: 6), CGPoint(x: 68, y: 18)),
    ]

    /// The rope from the beam down to the head.
    private static let rope: Part = .line(CGPoint(x: 68, y: 8), CGPoint(x: 68, y: 18))

    private static let wood = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.72, green: 0.51, blue: 0.32, alpha: 1)
        : UIColor(red: 0.62, green: 0.42, blue: 0.24, alpha: 1) })
    private static let woodEdge = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.42, green: 0.27, blue: 0.15, alpha: 1)
        : UIColor(red: 0.40, green: 0.25, blue: 0.13, alpha: 1) })
    private static let ropeColor = Color(red: 0.85, green: 0.71, blue: 0.47)

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

/// Hangman's toy world: a slate board with mustard accents.
enum ToyHangman {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (0.91, 0.93, 0.96), dark: (0.13, 0.15, 0.20)),
        backdropBottom: .dynamic(light: (0.78, 0.83, 0.90), dark: (0.06, 0.07, 0.11)),
        tray: .dynamic(light: (0.62, 0.68, 0.78), dark: (0.28, 0.32, 0.40)),
        socket: .dynamic(light: (0.78, 0.82, 0.89), dark: (0.08, 0.10, 0.14)),
        ink: .dynamic(light: (0.20, 0.25, 0.34), dark: (0.92, 0.94, 0.98)),
        deboss: .dynamic(light: (0.82, 0.86, 0.92), dark: (0.22, 0.25, 0.32)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.02, 0.03, 0.04)),
        card: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.23, 0.26, 0.33)),
        accent: .dynamic(light: (0.95, 0.68, 0.22), dark: (1.0, 0.76, 0.34)))
}

/// A word part guessed with two misses on the gallows, for the Home preview.
struct HangmanShowcase: View {
    let table: HangmanState

    init() {
        var table = HangmanState.newGame(language: HangmanLanguage(app: L10n.language))
        let letters = Array(Set(table.word)).sorted()
        let misses = table.language.alphabet.filter { !table.word.contains($0) }
        table.guessed = Array(letters.prefix(max(1, letters.count / 3))) + Array(misses.shuffled().prefix(2))
        table.mistakes = 2
        self.table = table
    }

    var body: some View {
        ZStack {
            ToyHangman.palette.backdrop
            HangmanTableView(table: table, seat: 0, names: [], onAction: { _ in }, preview: true)
                .padding(28)
        }
        .environment(\.toyStyle, ToyHangman.palette.style)
        .frame(width: 360, height: 360)
    }
}
