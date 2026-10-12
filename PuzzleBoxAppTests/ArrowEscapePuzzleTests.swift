import Testing
@testable import PuzzleBoxApp

@MainActor
struct ArrowEscapePuzzleTests {
    @Test func everyLevelIsPackedConnectedAndSolvable() {
        for index in 0..<ArrowEscapePuzzle.levelCount {
            let puzzle = ArrowEscapePuzzle.make(level: index)
            var occupancy: [EscapeCell: Int] = [:]
            for arrow in puzzle.arrows {
                for cell in arrow.cells {
                    #expect(puzzle.contains(cell))
                    #expect(occupancy.updateValue(arrow.id, forKey: cell) == nil)
                }
                for (a, b) in zip(arrow.cells, arrow.cells.dropFirst()) {
                    #expect(abs(a.x - b.x) + abs(a.y - b.y) == 1)
                }
                if arrow.cells.count > 1 {
                    #expect(arrow.cells[arrow.cells.count - 2].offset(arrow.direction) == arrow.head)
                }
            }
            #expect(occupancy.count == puzzle.columns * puzzle.rows)
            for id in puzzle.solution {
                let arrow = puzzle.arrows[id]
                #expect(puzzle.canRemove(arrow, occupancy: occupancy))
                for cell in arrow.cells { occupancy.removeValue(forKey: cell) }
            }
            #expect(occupancy.isEmpty)
        }
    }

    @Test func blockingRayIncludesDistantArrowsButNotSideNeighbors() {
        let arrow = EscapeArrow(id: 0, cells: [.init(x: 1, y: 1), .init(x: 2, y: 1)], direction: .right)
        let puzzle = ArrowEscapePuzzle(columns: 6, rows: 4, arrows: [arrow], solution: [0])
        #expect(!puzzle.canRemove(arrow, occupancy: [.init(x: 5, y: 1): 1]))
        #expect(puzzle.canRemove(arrow, occupancy: [.init(x: 5, y: 2): 1]))
    }

    @Test func pauseAndRestartCannotCompleteAnOldRemoval() {
        let engine = ArrowEscapePuzzleEngine()
        engine.tap(engine.puzzle.arrows[0].head)
        #expect(engine.moving[0] == 0)
        engine.state = .paused
        engine.advanceAnimation(1, reduceMotion: false)
        #expect(engine.moving[0] == 0)
        let token = engine.animationToken
        engine.restart()
        #expect(engine.animationToken != token)
        engine.advanceAnimation(1, reduceMotion: false)
        #expect(engine.remaining.count == engine.puzzle.arrows.count)
        #expect(engine.score == 0)
    }

    @Test func severalArrowsCanFlyAtOnceAndUnblockTheBoard() {
        let engine = ArrowEscapePuzzleEngine()
        let order = engine.puzzle.solution
        // Launch the first two solution arrows back to back, without waiting.
        engine.tap(engine.puzzle.arrows[order[0]].head)
        engine.tap(engine.puzzle.arrows[order[1]].head)
        #expect(engine.moving.count == 2)
        #expect(engine.mistakes == 0)
        // A flying arrow is no longer on the board, so tapping its cell again does nothing.
        engine.tap(engine.puzzle.arrows[order[0]].head)
        #expect(engine.moving.count == 2)
        // Both stay drawn until their flight ends.
        for _ in 0..<40 { engine.advanceAnimation(1.0 / 15, reduceMotion: false) }
        #expect(engine.moving.isEmpty)
        #expect(engine.remaining.count == engine.puzzle.arrows.count - 2)
    }
}
