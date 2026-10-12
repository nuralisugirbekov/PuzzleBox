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
    private(set) var blockedID: Int?
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

    init() { resetBoard() }
    var hasNextLevel: Bool { levelIndex + 1 < ArrowEscapePuzzle.levelCount }
    /// Arrows not yet launched.
    var onBoardCount: Int { remaining.count - moving.count }

    func restart() { resetBoard() }
    func selectLevel(_ index: Int) {
        guard (0..<ArrowEscapePuzzle.levelCount).contains(index), index != levelIndex else { return }
        levelIndex = index
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
            blockedID = id
            mistakes += 1
            Haptics.error()
            if lives == 0 {
                state = .gameOver(won: false)
            } else {
                SoundFX.play(.wrong)
            }
            return
        }
        if blockedID == id { blockedID = nil }
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
            state = .gameOver(won: true)
        }
    }

    private func resetBoard() {
        animationToken += 1
        moving = [:]
        blockedID = nil
        mistakes = 0
        score = 0
        state = .playing
        remaining = Set(puzzle.arrows.map(\.id))
        occupancy = Dictionary(uniqueKeysWithValues: puzzle.arrows.flatMap { arrow in arrow.cells.map { ($0, arrow.id) } })
    }
}
