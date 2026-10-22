import SwiftUI
import Observation

enum Match3Mode: String, Codable {
    /// Play for score until the board runs out of moves.
    case casual
    /// Levels on boards of every shape: collect the crystals within the moves.
    case arcade
    /// Collect crystals against the clock, level after level.
    case blitz

    var gameID: GameID {
        switch self {
        case .casual: .gems
        case .arcade: .gemsArcade
        case .blitz: .gemsBlitz
        }
    }
}

/// A short-lived effect drawn over the board.
struct Match3Effect: Identifiable, Equatable {
    enum Kind: Equatable {
        case burst(GemColor?)
        case blast(GemPower, big: Bool, color: GemColor?)
        case crack
    }

    let id = UUID()
    let kind: Kind
    let at: GridPos
}

struct Match3Piece: Identifiable {
    let gem: Gem
    let at: GridPos
    var id: Int { gem.id }
}

@MainActor
@Observable
final class Match3Engine: GameEngine {
    /// The arcade level the player has reached, kept between sessions.
    static let arcadeLevelKey = "gems.arcadeLevel"

    let mode: Match3Mode
    /// Set for a race against friends: every player's boards come from it.
    let seed: UInt64?
    /// The board on screen. It trails `core` while a turn is being animated.
    private(set) var board: Match3Board
    private(set) var score = 0
    var state: GameState = .playing
    private(set) var level = Match3Level(number: 1)
    private(set) var arcade: Match3ArcadeLevel
    private(set) var timeLeft = Match3Level.time
    private(set) var movesLeft = 0
    private(set) var crystals = 0
    private(set) var bestCascade = 0
    /// A turn is playing out; input waits.
    private(set) var isBusy = false
    /// The round is over and the last powers are going off.
    private(set) var isEnding = false
    private(set) var selected: GridPos?
    private(set) var hint: [GridPos] = []
    private(set) var effects: [Match3Effect] = []
    /// Bumped by blasts to shake the board.
    private(set) var shake = 0
    let popups = ClassicFXPopupFeed()

    /// The rules' state, already settled after the latest move.
    private var core: Match3State
    private var idle: Double = 0
    /// Bumped on restart so animations from the old round stop.
    private var run = 0

    var pieces: [Match3Piece] {
        board.positions.compactMap { p in board[p].map { Match3Piece(gem: $0, at: p) } }
    }

    var crystalsNeeded: Int { mode == .arcade ? arcade.crystalsNeeded : level.crystalsNeeded }
    /// The level shown in the header and the result, in the modes that have levels.
    var levelNumber: Int { mode == .arcade ? arcade.number : level.number }

    init(mode: Match3Mode, seed: UInt64? = nil) {
        self.mode = mode
        self.seed = seed
        let arcade = Match3ArcadeLevel(number: max(1, UserDefaults.standard.integer(forKey: Self.arcadeLevelKey)))
        self.arcade = arcade
        let core = Self.makeCore(mode: mode, level: Match3Level(number: 1), arcade: arcade, seed: seed)
        self.core = core
        board = core.board
        movesLeft = arcade.moves
    }

    private static func makeCore(mode: Match3Mode, level: Match3Level, arcade: Match3ArcadeLevel,
                                 seed: UInt64?) -> Match3State {
        switch mode {
        case .casual: Match3Casual.newGame()
        case .arcade: arcade.newGame()
        case .blitz: seed.map { level.newGame(seed: $0 &+ UInt64(level.number)) } ?? level.newGame()
        }
    }

    /// Starts over: Casual and Blitz from scratch, Arcade on the same level.
    func restart() {
        run += 1
        level = Match3Level(number: 1)
        core = Self.makeCore(mode: mode, level: level, arcade: arcade, seed: seed)
        board = core.board
        score = 0
        timeLeft = Match3Level.time
        movesLeft = arcade.moves
        crystals = 0
        bestCascade = 0
        isBusy = false
        isEnding = false
        selected = nil
        hint = []
        effects = []
        idle = 0
        popups.clear()
        state = .playing
    }

    var hasNextLevel: Bool { mode == .arcade }

    /// Arcade: moves on to the next board after a won level.
    func nextLevel() {
        arcade = Match3ArcadeLevel(number: arcade.number + 1)
        restart()
    }

    // MARK: Input

    func tap(_ p: GridPos) {
        guard state == .playing, !isBusy, !isEnding else { return }
        if let current = selected {
            if current == p {
                selected = nil
                return
            }
            if Match3Board.adjacent(current, p) {
                swap(current, p)
                return
            }
        }
        selected = board[p]?.ice == 0 ? p : nil
        if selected != nil { Haptics.tap() }
    }

    func swap(_ a: GridPos, _ b: GridPos) {
        guard state == .playing, !isBusy, !isEnding, board.contains(a), board.contains(b) else { return }
        selected = nil
        hint = []
        idle = 0
        var next = core
        guard let turn = next.swap(a, b) else {
            refuse(a, b)
            return
        }
        core = next
        if mode == .arcade { movesLeft -= 1 }
        Haptics.tap()
        play(turn.steps) { [weak self] in self?.afterTurn() }
    }

    func showHint() {
        guard state == .playing, !isBusy, !isEnding, let move = core.hint else { return }
        Haptics.tap()
        hint = [move.0, move.1]
    }

    /// Called ten times a second by the view: runs the Blitz clock and
    /// offers a hint after a few idle seconds. The clock waits while a turn
    /// plays out, so long cascades don't eat the player's time.
    func tick(_ dt: Double) {
        guard state == .playing, !isBusy, !isEnding else { return }
        idle += dt
        if idle >= 5, hint.isEmpty, let move = core.hint { hint = [move.0, move.1] }
        guard mode == .blitz else { return }
        timeLeft = max(0, timeLeft - dt)
        if timeLeft == 0 {
            popups.show(L10n.text("Time's up!"), color: .white, at: UnitPoint(x: 0.5, y: 0.42), large: true)
            finish(won: false)
        }
    }

    /// Ticks the engine ten times a second while the screen is up.
    func runClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            tick(0.1)
        }
    }

    /// A swap that lines nothing up slides over and back.
    private func refuse(_ a: GridPos, _ b: GridPos) {
        Haptics.error()
        SoundFX.play(.wrong)
        guard Match3Board.adjacent(a, b), board[a]?.ice == 0, board[b]?.ice == 0 else { return }
        isBusy = true
        let run = self.run
        var swapped = board
        swapped.swap(a, b)
        withAnimation(.snappy(duration: 0.14)) { board = swapped }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(170))
            guard let self, run == self.run else { return }
            withAnimation(.snappy(duration: 0.16)) { self.board = self.core.board }
            self.isBusy = false
        }
    }

    // MARK: Playing a turn

    private func play(_ steps: [Match3Step], then done: @escaping @MainActor () -> Void) {
        isBusy = true
        let run = self.run
        Task { @MainActor [weak self] in
            for step in steps {
                guard let self, run == self.run else { return }
                let pause = self.show(step)
                try? await Task.sleep(for: .milliseconds(pause))
            }
            guard let self, run == self.run else { return }
            self.isBusy = false
            done()
        }
    }

    /// Shows one step and returns how long to hold it, in milliseconds.
    private func show(_ step: Match3Step) -> Int {
        switch step.kind {
        case .swap:
            withAnimation(.snappy(duration: 0.18)) { board = step.board }
            SoundFX.play(.whoosh)
            return 190
        case .charge:
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { board = step.board }
            Haptics.move()
            SoundFX.play(.tick)
            return 420
        case .clear:
            addEffects(for: step)
            withAnimation(.easeOut(duration: 0.16)) { board = step.board }
            score += step.points
            if mode != .casual && !isEnding { crystals += step.crystals }
            bestCascade = max(bestCascade, step.cascade)
            showPoints(for: step)
            return step.blasts.isEmpty ? 200 : 340
        case .fall:
            withAnimation(.spring(duration: 0.34, bounce: 0.22)) { board = step.board }
            return 300
        case .shuffle:
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { board = step.board }
            SoundFX.play(.whoosh)
            return 520
        }
    }

    private func addEffects(for step: Match3Step) {
        var added = step.bursts.map { Match3Effect(kind: .burst($0.color), at: $0.at) }
        added += step.blasts.map { Match3Effect(kind: .blast($0.power, big: $0.big, color: $0.color), at: $0.at) }
        added += step.cracked.map { Match3Effect(kind: .crack, at: $0) }
        effects.append(contentsOf: added)
        let ids = Set(added.map(\.id))
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            self?.effects.removeAll { ids.contains($0.id) }
        }

        if !step.blasts.isEmpty {
            shake += 1
            Haptics.heavy()
            SoundFX.play(.hit)
        } else {
            Haptics.move()
            SoundFX.play(step.cascade >= 2 ? .merge : .pop)
        }
        if step.crystals > 0 { SoundFX.play(.coin) }
    }

    /// Where `cells` sit on the board, in unit coordinates for the popup layer.
    private func anchor(of cells: [GridPos]) -> UnitPoint {
        let x = cells.map { CGFloat($0.c) + 0.5 }.reduce(0, +) / CGFloat(cells.count) / CGFloat(board.cols)
        let y = cells.map { CGFloat($0.r) + 0.5 }.reduce(0, +) / CGFloat(cells.count) / CGFloat(board.rows)
        return UnitPoint(x: x, y: y)
    }

    private func showPoints(for step: Match3Step) {
        let cells = step.bursts.map(\.at) + step.cracked + step.created
        guard step.points > 0, !cells.isEmpty else { return }
        popups.show("+\(step.points)", color: .yellow, at: anchor(of: cells), large: step.points >= 200)
        if step.cascade >= 2 {
            popups.show(L10n.format("Combo ×%d", min(step.cascade, Match3State.maxMultiplier)),
                        color: .white, at: UnitPoint(x: 0.5, y: 0.2), large: true)
        }
    }

    private func afterTurn() {
        guard !isEnding else { return }
        switch mode {
        case .blitz where crystals >= level.crystalsNeeded:
            levelUp()
            return
        case .arcade where crystals >= arcade.crystalsNeeded:
            completeArcadeLevel()
            return
        case .arcade where movesLeft <= 0:
            popups.show(L10n.text("Out of moves"), color: .white, at: UnitPoint(x: 0.5, y: 0.42), large: true)
            finish(won: false)
            return
        case .casual:
            core.assist = Match3Casual.assist(forScore: score)
            core.iceChance = Match3Casual.iceChance(forScore: score)
        default:
            break
        }
        guard !core.hasMoves else { return }
        if mode == .casual {
            finish(won: false)
        } else {
            popups.show(L10n.text("No moves — shuffling"), color: .white, at: UnitPoint(x: 0.5, y: 0.42), large: true)
            var next = core
            let step = next.shuffle()
            core = next
            play([step]) { [weak self] in self?.afterTurn() }
        }
    }

    private func levelUp() {
        let bonus = Int(timeLeft.rounded()) * 20
        score += bonus
        level = Match3Level(number: level.number + 1)
        crystals = 0
        timeLeft = Match3Level.time
        hint = []
        idle = 0
        Haptics.success()
        SoundFX.play(.win)
        popups.show(L10n.format("Level %d", level.number), color: .white, at: UnitPoint(x: 0.5, y: 0.42), large: true)
        if bonus > 0 {
            popups.show(L10n.format("Time bonus +%d", bonus), color: .yellow, at: UnitPoint(x: 0.5, y: 0.56))
        }
        core = Self.makeCore(mode: mode, level: level, arcade: arcade, seed: seed)
        isBusy = true
        let run = self.run
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, run == self.run else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { self.board = self.core.board }
            try? await Task.sleep(for: .milliseconds(550))
            guard run == self.run else { return }
            self.isBusy = false
        }
    }

    /// Arcade goal reached: unused moves score a bonus, the next level is
    /// unlocked, and the last chord plays before the win.
    private func completeArcadeLevel() {
        let bonus = movesLeft * 100
        score += bonus
        if bonus > 0 {
            popups.show(L10n.format("Moves bonus +%d", bonus), color: .yellow, at: UnitPoint(x: 0.5, y: 0.56))
        }
        let reached = arcade.number + 1
        if reached > UserDefaults.standard.integer(forKey: Self.arcadeLevelKey) {
            UserDefaults.standard.set(reached, forKey: Self.arcadeLevelKey)
        }
        finish(won: true)
    }

    /// Ends the round with the "last chord": every power left goes off for
    /// its points, then the result comes up.
    private func finish(won: Bool) {
        guard !isEnding else { return }
        isEnding = true
        selected = nil
        hint = []
        var next = core
        let turn = next.finale()
        core = next
        if !turn.steps.isEmpty {
            popups.show(L10n.text("Last chord!"), color: .white, at: UnitPoint(x: 0.5, y: 0.3), large: true)
        }
        let run = self.run
        play(turn.steps) { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, run == self.run else { return }
                self.state = .gameOver(won: won)
            }
        }
    }
}

// MARK: - Saved round

extension Match3Engine: ResumableGame {
    private struct Session: Codable {
        let core: Match3State
        let score: Int
        let level: Int
        let arcadeLevel: Int
        let timeLeft: Double
        let movesLeft: Int
        let crystals: Int
        let bestCascade: Int
    }

    func saveSession() -> Data? {
        guard seed == nil, state == .playing || state == .paused, score > 0, !isEnding else { return nil }
        return encodeSession(Session(core: core, score: score, level: level.number, arcadeLevel: arcade.number,
                                     timeLeft: timeLeft, movesLeft: movesLeft, crystals: crystals,
                                     bestCascade: bestCascade))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard seed == nil, let session = decodeSession(Session.self, from: data) else { return false }
        run += 1
        core = session.core
        board = core.board
        score = session.score
        level = Match3Level(number: session.level)
        arcade = Match3ArcadeLevel(number: session.arcadeLevel)
        timeLeft = session.timeLeft
        movesLeft = session.movesLeft
        crystals = session.crystals
        bestCascade = session.bestCascade
        isBusy = false
        isEnding = false
        selected = nil
        hint = []
        effects = []
        popups.clear()
        state = .playing
        return true
    }
}
