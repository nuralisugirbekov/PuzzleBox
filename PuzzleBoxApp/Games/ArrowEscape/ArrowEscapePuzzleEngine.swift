import Foundation
import Observation

@MainActor @Observable
final class ArrowEscapePuzzleEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var levelIndex = 0
    private(set) var puzzle = ArrowEscapePuzzle.make(level: 0)
    /// Arrows still drawn: those on the board plus those flying off it.
    private(set) var remaining: Set<Int> = []
    /// Arrows flying off, with the seconds since each was launched. Several
    /// can be in flight at once; each frees its cells the moment it launches.
    private(set) var moving: [Int: Double] = [:]
    /// Arrows tapped while their path was blocked. They stay red for the rest
    /// of the level, and tapping one again costs nothing.
    private(set) var missed: Set<Int> = []
    private(set) var mistakes = 0
    static let maxLives = 3
    /// How long a launched arrow is kept for the view to fly it off screen.
    static let flightDuration: Double = 1.4
    static let reducedMotionDuration: Double = 0.2
    /// Blind tapping costs a life, so the board has to be read, not brute-forced.
    var lives: Int { max(0, Self.maxLives - mistakes) }
    private(set) var animationToken = 0
    private(set) var active = true
    @ObservationIgnored private var occupancy: [EscapeCell: Int] = [:]

    /// The level to open on next time, so leaving never loses progress.
    static let levelKey = "arrowEscapeLevel"

    init() {
        levelIndex = max(0, min(ArrowEscapePuzzle.levelCount - 1, UserDefaults.standard.integer(forKey: Self.levelKey)))
        puzzle = ArrowEscapePuzzle.make(level: levelIndex)
        resetBoard()
    }
    var hasNextLevel: Bool { levelIndex + 1 < ArrowEscapePuzzle.levelCount }
    /// Arrows not yet launched.
    var onBoardCount: Int { remaining.count - moving.count }

    func restart() { resetBoard() }
    func selectLevel(_ index: Int) {
        guard (0..<ArrowEscapePuzzle.levelCount).contains(index), index != levelIndex else { return }
        levelIndex = index
        UserDefaults.standard.set(index, forKey: Self.levelKey)
        puzzle = ArrowEscapePuzzle.make(level: index)
        resetBoard()
    }
    func nextLevel() { selectLevel(levelIndex + 1) }
    func setActive(_ value: Bool) {
        active = value
        if !value && state == .playing { state = .paused }
    }

    /// Launches the arrow in `cell`. Arrows already flying don't block, so
    /// the player can keep tapping without waiting for them to leave.
    func tap(_ cell: EscapeCell) {
        guard active, state == .playing, let id = occupancy[cell] else { return }
        let arrow = puzzle.arrows[id]
        if !puzzle.canRemove(arrow, occupancy: occupancy) {
            Haptics.error()
            // Already marked: the player has been told, no second life lost.
            guard missed.insert(id).inserted else { return }
            mistakes += 1
            if lives == 0 {
                state = .gameOver(won: false)
            } else {
                SoundFX.play(.wrong)
            }
            return
        }
        for cell in arrow.cells { occupancy.removeValue(forKey: cell) }
        moving[id] = 0
        score = (puzzle.arrows.count - onBoardCount) * 10
        animationToken += 1
        Haptics.tap()
        SoundFX.play(.whoosh)
    }

    func advanceAnimation(_ dt: Double, reduceMotion: Bool) {
        guard active, state == .playing, !moving.isEmpty else { return }
        let step = min(max(dt, 0), 1.0 / 15)
        let duration = reduceMotion ? Self.reducedMotionDuration : Self.flightDuration
        for (id, elapsed) in moving {
            let next = elapsed + step
            if next >= duration {
                moving.removeValue(forKey: id)
                remaining.remove(id)
            } else {
                moving[id] = next
            }
        }
        if remaining.isEmpty {
            score += 200 + lives * 150
            UserDefaults.standard.set(min(ArrowEscapePuzzle.levelCount - 1, levelIndex + 1), forKey: Self.levelKey)
            state = .gameOver(won: true)
        }
    }

    private func resetBoard() {
        animationToken += 1
        moving = [:]
        missed = []
        mistakes = 0
        score = 0
        state = .playing
        remaining = Set(puzzle.arrows.map(\.id))
        occupancy = Dictionary(uniqueKeysWithValues: puzzle.arrows.flatMap { arrow in arrow.cells.map { ($0, arrow.id) } })
    }
}

// MARK: - Saved round

extension ArrowEscapePuzzleEngine: ResumableGame {
    private struct Session: Codable {
        let levelIndex: Int
        /// Arrows still on the board; ones in flight count as gone.
        let onBoard: [Int]
        let mistakes: Int
        /// Missing in rounds saved before misses were remembered.
        var missed: [Int]? = nil
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused else { return nil }
        let onBoard = remaining.subtracting(moving.keys)
        guard onBoard.count < puzzle.arrows.count || mistakes > 0, !onBoard.isEmpty else { return nil }
        return encodeSession(Session(levelIndex: levelIndex, onBoard: onBoard.sorted(), mistakes: mistakes,
                                     missed: missed.intersection(onBoard).sorted()))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data),
              (0..<ArrowEscapePuzzle.levelCount).contains(session.levelIndex) else { return false }
        let puzzle = ArrowEscapePuzzle.make(level: session.levelIndex)
        guard session.onBoard.allSatisfy(puzzle.arrows.indices.contains) else { return false }
        levelIndex = session.levelIndex
        self.puzzle = puzzle
        resetBoard()
        remaining = Set(session.onBoard)
        occupancy = Dictionary(uniqueKeysWithValues: puzzle.arrows.filter { remaining.contains($0.id) }
            .flatMap { arrow in arrow.cells.map { ($0, arrow.id) } })
        mistakes = session.mistakes
        missed = Set(session.missed ?? []).intersection(remaining)
        score = (puzzle.arrows.count - remaining.count) * 10
        return true
    }
}
