import Foundation
import Testing
@testable import PuzzleBoxApp

/// Games with levels reopen on the level the player reached.
@MainActor
struct LevelProgressTests {
    /// Runs `body` and puts the saved value under `key` back afterwards.
    private func preserving(_ key: String, _ body: () -> Void) {
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        body()
    }

    @Test func arrowEscapeReopensOnTheChosenLevel() {
        preserving(ArrowEscapePuzzleEngine.levelKey) {
            ArrowEscapePuzzleEngine().selectLevel(4)
            #expect(ArrowEscapePuzzleEngine().levelIndex == 4)
        }
    }

    @Test func rocketMazeReopensOnTheChosenLevel() {
        preserving(ArrowMazeEngine.levelKey) {
            ArrowMazeEngine().selectLevel(2)
            let reopened = ArrowMazeEngine()
            #expect(reopened.levelIndex == 2)
            #expect(reopened.simulation.position == reopened.level.spawn)
        }
    }

    @Test func visualPuzzlesReopenOnTheChosenLevel() {
        preserving("visualLevel." + VisualMode.matchstick.rawValue) {
            VisualEngine(mode: .matchstick).loadLevel(5)
            #expect(VisualEngine(mode: .matchstick).levelIndex == 5)
        }
    }

    @Test func bounceStartsANewRunOnTheLevelReached() {
        preserving(BounceEngine.levelKey) {
            UserDefaults.standard.set(1, forKey: BounceEngine.levelKey)
            let engine = BounceEngine()
            #expect(engine.levelIndex == 1)
            engine.restart()
            #expect(engine.levelIndex == 1 && engine.lives == 3 && engine.score == 0)
        }
    }

    /// The difficulty is picked before the game opens, and the game opens on it.
    @Test func minesweeperOpensOnTheChosenDifficulty() {
        preserving("minesweeperDifficulty") {
            MinesweeperEngine.choose(.hard)
            #expect(MinesweeperEngine().rows == MinesweeperDifficulty.hard.size)
            MinesweeperEngine.choose(.easy)
            let engine = MinesweeperEngine()
            #expect(engine.grid.count == engine.rows && engine.rows == MinesweeperDifficulty.easy.size)
            // A tap outside the board does nothing.
            engine.tap(GridPos(r: 13, c: 13))
            engine.toggleFlag(GridPos(r: 12, c: 0))
            #expect(engine.revealedCount == 0 && engine.flagsUsed == 0)
        }
    }
}
