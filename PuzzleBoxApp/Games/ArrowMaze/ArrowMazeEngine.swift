import Foundation
import Observation

/// Publishes HUD changes only. Per-frame positions stay outside Observation so
/// moving the arrow does not rebuild the surrounding SwiftUI hierarchy at 120 Hz.
@MainActor @Observable
final class ArrowMazeEngine: GameEngine {
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    private(set) var levelIndex = 0
    private(set) var collectedCount = 0
    private(set) var speedMultiplier = 1.0
    private(set) var active = false
    private(set) var revision = 0
    @ObservationIgnored private(set) var simulation = ArrowMazeSimulation(level: ArrowMazeLevel.all[0])

    var level: ArrowMazeLevel { ArrowMazeLevel.all[levelIndex] }
    var canAdvance: Bool { active && started && state == .playing }
    var hasNextLevel: Bool { levelIndex + 1 < ArrowMazeLevel.all.count }

    func setActive(_ value: Bool) {
        active = value
        if !value && started && state == .playing { state = .paused }
    }
    func start() {
        guard active, state == .playing else { return }
        started = true
    }
    func restart() {
        simulation = ArrowMazeSimulation(level: level)
        score = 0
        collectedCount = 0
        speedMultiplier = 1
        started = false
        state = .playing
        revision += 1
    }
    func selectLevel(_ index: Int) {
        guard ArrowMazeLevel.all.indices.contains(index), index != levelIndex else { return }
        levelIndex = index
        restart()
    }
    func nextLevel() { selectLevel(levelIndex + 1) }

    func turn(_ direction: ArrowMazeTurn) {
        guard canAdvance else { return }
        if simulation.turn(direction) { Haptics.tap(); SoundFX.play(.tap) }
        publishResult()
    }
    func advance(_ dt: TimeInterval) {
        guard canAdvance else { return }
        simulation.step(dt)
        publishResult()
    }
    func receiveContacts(wall: Bool, gems: Set<Int>, exit: Bool) {
        guard canAdvance else { return }
        // Failure has deterministic priority over rewards when callbacks coincide.
        if wall { simulation.contactWall() }
        for index in gems.sorted() { simulation.contactGem(index) }
        if exit { simulation.contactExit() }
        publishResult()
    }
    private func publishResult() {
        if collectedCount != simulation.collected.count {
            collectedCount = simulation.collected.count
            speedMultiplier = Double(simulation.speedMultiplier)
            Haptics.move()
            SoundFX.play(.coin)
        }
        if score != simulation.score { score = simulation.score }
        guard state == .playing else { return }
        switch simulation.outcome {
        case .moving: break
        case .crashed: state = .gameOver(won: false)
        case .escaped: state = .gameOver(won: true)
        }
    }
}
