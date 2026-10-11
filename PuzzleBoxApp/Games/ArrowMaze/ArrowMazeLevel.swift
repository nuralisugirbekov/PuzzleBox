import Foundation
import CoreGraphics

struct ArrowMazeCell: Hashable {
    let column: Int
    let row: Int
}

enum ArrowMazeHeading: Int, CaseIterable {
    case east, north, west, south

    var angle: CGFloat { CGFloat(rawValue) * .pi / 2 }
    var unit: CGVector {
        switch self {
        case .east: CGVector(dx: 1, dy: 0)
        case .north: CGVector(dx: 0, dy: 1)
        case .west: CGVector(dx: -1, dy: 0)
        case .south: CGVector(dx: 0, dy: -1)
        }
    }
    func turned(_ turn: ArrowMazeTurn) -> Self {
        Self(rawValue: (rawValue + (turn == .left ? 1 : 3)) % 4)!
    }
}

enum ArrowMazeTurn { case left, right }

/// Coordinates use SpriteKit's convention: origin at bottom-left, positive y up.
struct ArrowMazeLevel {
    static let tileSize: CGFloat = 72
    let columns: Int
    let rows: Int
    let route: [ArrowMazeCell]
    let floors: Set<ArrowMazeCell>
    let speed: CGFloat
    let initialHeading: ArrowMazeHeading
    let gemCells: [ArrowMazeCell]

    var bounds: CGRect {
        CGRect(x: 0, y: 0, width: CGFloat(columns) * Self.tileSize, height: CGFloat(rows) * Self.tileSize)
    }
    var spawn: CGPoint { center(of: route[0]) }
    var exit: CGPoint { center(of: route[route.count - 1]) }
    var gems: [CGPoint] { gemCells.map(center) }
    var walls: [CGRect] {
        (0..<rows).flatMap { row in
            (0..<columns).compactMap { column in
                let cell = ArrowMazeCell(column: column, row: row)
                return floors.contains(cell) ? nil : rect(of: cell)
            }
        }
    }
    func center(of cell: ArrowMazeCell) -> CGPoint {
        CGPoint(x: (CGFloat(cell.column) + 0.5) * Self.tileSize,
                y: (CGFloat(cell.row) + 0.5) * Self.tileSize)
    }
    func cell(at point: CGPoint) -> ArrowMazeCell {
        ArrowMazeCell(column: Int(floor(point.x / Self.tileSize)), row: Int(floor(point.y / Self.tileSize)))
    }
    func rect(of cell: ArrowMazeCell) -> CGRect {
        CGRect(x: CGFloat(cell.column) * Self.tileSize, y: CGFloat(cell.row) * Self.tileSize,
               width: Self.tileSize, height: Self.tileSize)
    }

    /// Closed outer border, a guaranteed route, and optional connected dead ends.
    private init(columns: Int, rows: Int, speed: CGFloat,
                 waypoints: [(Int, Int)], branches: [[(Int, Int)]]) {
        func expand(_ points: [(Int, Int)]) -> [ArrowMazeCell] {
            precondition(points.count >= 2)
            var cells = [ArrowMazeCell(column: points[0].0, row: points[0].1)]
            for (a, b) in zip(points, points.dropFirst()) {
                precondition((a.0 == b.0) != (a.1 == b.1), "Route segments must be nonzero and axis-aligned")
                let dx = (b.0 - a.0).signum(), dy = (b.1 - a.1).signum()
                for step in 1...max(abs(b.0 - a.0), abs(b.1 - a.1)) {
                    cells.append(ArrowMazeCell(column: a.0 + dx * step, row: a.1 + dy * step))
                }
            }
            return cells
        }
        let path = expand(waypoints)
        var walkable = Set(path)
        for branch in branches {
            let cells = expand(branch)
            precondition(walkable.contains(cells[0]), "Dead ends must connect to the maze")
            walkable.formUnion(cells)
        }
        precondition(walkable.allSatisfy { (1..<(columns - 1)).contains($0.column) && (1..<(rows - 1)).contains($0.row) })
        self.columns = columns
        self.rows = rows
        self.speed = speed
        route = path
        floors = walkable
        let first = path[0], second = path[1]
        initialHeading = second.column > first.column ? .east : second.column < first.column ? .west : second.row > first.row ? .north : .south
        // Keep gems away from corners: every collectible is on the guaranteed route.
        gemCells = path.indices.filter { index in
            guard index >= 2, index < path.count - 2, index % 5 == 2 else { return false }
            return path[index - 1].column == path[index + 1].column || path[index - 1].row == path[index + 1].row
        }.map { path[$0] }
    }

    static let all: [Self] = [
        Self(columns: 9, rows: 11, speed: 100,
             waypoints: [(1,1),(7,1),(7,5),(3,5),(3,9),(7,9)],
             branches: [[(4,1),(4,3)],[(3,7),(1,7)]]),
        Self(columns: 11, rows: 13, speed: 105,
             waypoints: [(1,1),(1,5),(5,5),(5,1),(9,1),(9,9),(3,9),(3,11),(9,11)],
             branches: [[(1,3),(3,3)],[(9,7),(7,7)]]),
        Self(columns: 11, rows: 15, speed: 110,
             waypoints: [(1,1),(9,1),(9,5),(3,5),(3,9),(7,9),(7,13),(1,13)],
             branches: [[(5,1),(5,3)],[(3,7),(1,7)],[(7,11),(9,11)]]),
        Self(columns: 13, rows: 15, speed: 115,
             waypoints: [(1,1),(1,11),(5,11),(5,3),(9,3),(9,7),(11,7),(11,13),(3,13)],
             branches: [[(1,5),(3,5)],[(5,7),(7,7)],[(9,5),(11,5)]]),
        Self(columns: 13, rows: 17, speed: 120,
             waypoints: [(1,1),(11,1),(11,5),(5,5),(5,9),(9,9),(9,13),(3,13),(3,15),(11,15)],
             branches: [[(3,1),(3,3)],[(7,5),(7,7)],[(5,9),(1,9)],[(9,11),(11,11)]]),
        Self(columns: 15, rows: 17, speed: 125,
             waypoints: [(1,1),(1,7),(5,7),(5,3),(9,3),(9,9),(3,9),(3,13),(7,13),(7,15),(13,15),(13,5)],
             branches: [[(1,3),(3,3)],[(9,5),(11,5)],[(3,11),(5,11)],[(13,11),(11,11)]]),
        Self(columns: 15, rows: 19, speed: 130,
             waypoints: [(1,1),(13,1),(13,5),(9,5),(9,3),(5,3),(5,7),(1,7),(1,11),(7,11),(7,9),(13,9),
                         (13,17),(9,17),(9,13),(3,13),(3,17)],
             branches: [[(13,3),(11,3)],[(1,9),(3,9)],[(13,13),(11,13)]]),
        Self(columns: 17, rows: 21, speed: 135,
             waypoints: [(1,1),(15,1),(15,5),(1,5),(1,9),(15,9),(15,13),(1,13),(1,17),(15,17),(15,19)],
             branches: [[(7,1),(7,3)],[(9,5),(9,7)],[(5,9),(5,11)],[(11,13),(11,15)],[(3,17),(3,19)]]),
        Self(columns: 17, rows: 19, speed: 140,
             waypoints: [(1,1),(15,1),(15,17),(1,17),(1,3),(13,3),(13,15),(3,15),(3,5),(11,5),(11,13),
                         (5,13),(5,7),(9,7),(9,11),(7,11)],
             branches: []),
        Self(columns: 19, rows: 21, speed: 145,
             waypoints: [(9,1),(17,1),(17,7),(11,7),(11,3),(1,3),(1,11),(7,11),(7,15),(1,15),(1,19),
                         (11,19),(11,11),(17,11),(17,19)],
             branches: [[(13,1),(13,5)],[(1,7),(5,7)],[(7,13),(9,13)],[(17,15),(13,15)]])
    ]
}
