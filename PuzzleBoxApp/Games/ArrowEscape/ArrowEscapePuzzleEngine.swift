import Foundation
import Observation

@MainActor @Observable
final class ArrowEscapePuzzleEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var levelIndex = 0
    private(set) var puzzle = ArrowEscapePuzzle.make(level: 0)
    private(set) var remaining: Set<Int> = []
    private(set) var movingID: Int?
    private(set) var progress: Double = 0
    private(set) var blockedID: Int?
    private(set) var mistakes = 0
    static let maxLives = 3
    /// Blind tapping costs a life, so the board has to be read, not brute-forced.
    var lives: Int { max(0, Self.maxLives - mistakes) }
    private(set) var animationToken = 0
    private(set) var active = true
    @ObservationIgnored private var occupancy: [EscapeCell: Int] = [:]

    init() { resetBoard() }
    var hasNextLevel: Bool { levelIndex + 1 < ArrowEscapePuzzle.levelCount }

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
    func tap(_ cell: EscapeCell) {
        guard active, state == .playing, movingID == nil, let id = occupancy[cell] else { return }
        let arrow = puzzle.arrows[id]
        if !puzzle.canRemove(arrow, occupancy: occupancy) {
            blockedID = id
            mistakes += 1
            Haptics.error()
            if lives == 0 {
                movingID = nil
                state = .gameOver(won: false)
            } else {
                SoundFX.play(.wrong)
            }
            return
        }
        blockedID = nil
        movingID = id
        progress = 0
        animationToken += 1
        Haptics.tap()
        SoundFX.play(.whoosh)
    }
    func advanceAnimation(_ dt: Double, reduceMotion: Bool) {
        guard active, state == .playing, let id = movingID else { return }
        progress = min(1, progress + min(max(dt, 0), 1.0 / 15) / (reduceMotion ? 0.2 : 0.9))
        guard progress >= 1 else { return }
        for cell in puzzle.arrows[id].cells { occupancy.removeValue(forKey: cell) }
        remaining.remove(id)
        movingID = nil
        score = (puzzle.arrows.count - remaining.count) * 10
        if remaining.isEmpty {
            score += 200 + lives * 150
            state = .gameOver(won: true)
        }
    }
    private func resetBoard() {
        animationToken += 1
        movingID = nil
        progress = 0
        blockedID = nil
        mistakes = 0
        score = 0
        state = .playing
        remaining = Set(puzzle.arrows.map(\.id))
        occupancy = Dictionary(uniqueKeysWithValues: puzzle.arrows.flatMap { arrow in arrow.cells.map { ($0, arrow.id) } })
    }
}
