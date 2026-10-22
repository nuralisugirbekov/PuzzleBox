import Testing
@testable import PuzzleBoxApp

@MainActor
struct ArrowEscapePuzzleTests {
    @Test func everyLevelIsPackedConnectedAndSolvable() {
        for index in 0..<ArrowEscapePuzzle.levelCount {
            let puzzle = ArrowEscapePuzzle.make(level: index)
            var occupancy: [EscapeCell: Int] = [:]
            for arrow in puzzle.arrows {
                #expect(arrow.cells.count >= 2, "level \(index + 1) has a one-cell arrow")
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
            #expect(occupancy.count == puzzle.cellCount)
            #expect(Set(occupancy.keys) == puzzle.playable)
            for id in puzzle.solution {
                let arrow = puzzle.arrows[id]
                #expect(puzzle.canRemove(arrow, occupancy: occupancy))
                for cell in arrow.cells { occupancy.removeValue(forKey: cell) }
            }
            #expect(occupancy.isEmpty)
        }
    }

    @Test func boardGrowsEveryFewLevels() {
        let first = ArrowEscapePuzzle.size(level: 0)
        #expect(first.columns == 8 && first.rows == 11)
        // Same size within a step, bigger at the next one, never smaller.
        #expect(ArrowEscapePuzzle.size(level: ArrowEscapePuzzle.growthEvery - 1) == first)
        var previous = first
        for level in stride(from: 0, to: ArrowEscapePuzzle.levelCount, by: ArrowEscapePuzzle.growthEvery) {
            let size = ArrowEscapePuzzle.size(level: level)
            #expect(size.columns >= previous.columns && size.rows >= previous.rows)
            previous = size
        }
        #expect(previous.columns * previous.rows > 20 * first.columns * first.rows / 2)
    }

    @Test func boardsTakeManyShapes() {
        let shapes = Set((0..<ArrowEscapePuzzle.levelCount).map { EscapeShape.forLevel($0) })
        #expect(shapes == Set(EscapeShape.allCases))
        #expect(EscapeShape.forLevel(0) == .rectangle)
        for shape in EscapeShape.allCases {
            let (columns, rows, cells) = shape.cells(fitting: (12, 17))
            #expect(cells.count >= 60, "\(shape) is too small")
            #expect(cells.allSatisfy { (0..<columns).contains($0.x) && (0..<rows).contains($0.y) })
            // Trimmed: the outline touches every edge of its board.
            #expect(cells.contains { $0.x == 0 } && cells.contains { $0.x == columns - 1 })
            #expect(cells.contains { $0.y == 0 } && cells.contains { $0.y == rows - 1 })
        }
    }

    @Test func aMissedArrowCostsOneLifeOnce() {
        let engine = ArrowEscapePuzzleEngine()
        engine.setActive(true)
        let blocked = engine.puzzle.arrows.first { !engine.puzzle.canRemove($0, occupancy: Dictionary(
            uniqueKeysWithValues: engine.puzzle.arrows.flatMap { a in a.cells.map { ($0, a.id) } })) }!
        engine.tap(blocked.head)
        engine.tap(blocked.head)
        engine.tap(blocked.cells[0])
        #expect(engine.mistakes == 1)
        #expect(engine.missed == [blocked.id])
        engine.restart()
        #expect(engine.missed.isEmpty)
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
