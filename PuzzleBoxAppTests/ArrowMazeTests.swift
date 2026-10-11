import CoreGraphics
import Testing
@testable import PuzzleBoxApp

@MainActor
struct ArrowMazeTests {
    @Test func authoredRoutesCanCollectEveryGemAndEscape() {
        for level in ArrowMazeLevel.all {
            var simulation = ArrowMazeSimulation(level: level)
            for (current, next) in zip(level.route, level.route.dropFirst()) {
                guard simulation.outcome == .moving else { break }
                let desired: ArrowMazeHeading = next.column > current.column ? .east
                    : next.column < current.column ? .west : next.row > current.row ? .north : .south
                if simulation.heading != desired {
                    let turn: ArrowMazeTurn = simulation.heading.turned(.left) == desired ? .left : .right
                    #expect(simulation.turn(turn))
                }
                let target = level.center(of: next)
                let unit = desired.unit
                var budget = 200
                while simulation.outcome == .moving && budget > 0 {
                    let remaining = (target.x - simulation.position.x) * unit.dx
                        + (target.y - simulation.position.y) * unit.dy
                    if remaining <= 0 { break }
                    simulation.step(1.0 / 120)
                    budget -= 1
                }
                #expect(budget > 0)
            }
            #expect(simulation.outcome == .escaped)
            #expect(simulation.collected.count == level.gemCells.count)
        }
    }

    @Test func sweptIntersectionCatchesCrossingAndRejectsParallelMiss() {
        let wall = CGRect(x: 10, y: 10, width: 10, height: 10)
        #expect(ArrowMazeSimulation.intersectsSegment(from: .init(x: 0, y: 15), to: .init(x: 30, y: 15), rect: wall))
        #expect(!ArrowMazeSimulation.intersectsSegment(from: .init(x: 0, y: 5), to: .init(x: 30, y: 5), rect: wall))
        #expect(ArrowMazeSimulation.intersectsSegment(from: .init(x: 15, y: 15), to: .init(x: 15, y: 15), rect: wall))
    }

    @Test func duplicateContactsDoNotRewardTwiceAndCrashIsTerminal() {
        var simulation = ArrowMazeSimulation(level: ArrowMazeLevel.all[0])
        for _ in 0..<300 { simulation.step(1.0 / 120) }
        #expect(simulation.collected.contains(0))
        let score = simulation.score
        simulation.contactGem(0)
        simulation.contactGem(0)
        #expect(simulation.score == score)
        for _ in 0..<1000 { simulation.step(1.0 / 120) }
        #expect(simulation.outcome == .crashed)
        let position = simulation.position
        simulation.step(1)
        #expect(!simulation.turn(.left))
        #expect(simulation.position == position)
    }

    @Test func pauseBackgroundAndRestartGateMovement() {
        let engine = ArrowMazeEngine()
        engine.setActive(true)
        engine.start()
        engine.advance(1.0 / 120)
        engine.state = .paused
        let position = engine.simulation.position
        engine.advance(1)
        #expect(engine.simulation.position == position)
        engine.state = .playing
        engine.setActive(false)
        #expect(engine.state == .paused)
        engine.setActive(true)
        #expect(!engine.canAdvance)
        engine.restart()
        #expect(engine.simulation.position == engine.level.spawn)
        #expect(engine.score == 0)
        #expect(engine.simulation.elapsed == 0)
        #expect(!engine.started)
    }
}
