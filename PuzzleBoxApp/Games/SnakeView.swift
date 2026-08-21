import SwiftUI
import Observation

// MARK: - Engine

enum SnakeDirection {
    case up, down, left, right

    var dr: Int {
        switch self {
        case .up: -1
        case .down: 1
        case .left, .right: 0
        }
    }

    var dc: Int {
        switch self {
        case .left: -1
        case .right: 1
        case .up, .down: 0
        }
    }

    var opposite: SnakeDirection {
        switch self {
        case .up: .down
        case .down: .up
        case .left: .right
        case .right: .left
        }
    }
}

@MainActor
@Observable
final class SnakeEngine: GameEngine {
    static let cols = 14
    static let rows = 14

    private(set) var snake: [GridPos] = []  // head first
    private(set) var food = GridPos(r: 0, c: 0)
    private(set) var score = 0
    var state: GameState = .playing

    private var direction: SnakeDirection = .right
    private var pending: SnakeDirection = .right
    private var loopTask: Task<Void, Never>?

    /// Tick interval shrinks as the score grows, down to a floor.
    private var tickMilliseconds: Int { max(90, 220 - score) }

    init() {
        reset()
    }

    func restart() {
        reset()
        state = .playing
        start()
    }

    private func reset() {
        let midRow = Self.rows / 2
        snake = [GridPos(r: midRow, c: 6), GridPos(r: midRow, c: 5), GridPos(r: midRow, c: 4)]
        direction = .right
        pending = .right
        score = 0
        spawnFood()
    }

    func start() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.tickMilliseconds
                try? await Task.sleep(for: .milliseconds(interval))
                if Task.isCancelled { return }
                if self.state == .playing { self.tick() }
                if case .gameOver = self.state { return }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func changeDirection(_ new: SnakeDirection) {
        guard state == .playing, new != direction.opposite else { return }
        pending = new
    }

    private func tick() {
        direction = pending
        guard let head = snake.first else { return }
        let next = GridPos(r: head.r + direction.dr, c: head.c + direction.dc)

        guard (0..<Self.rows).contains(next.r), (0..<Self.cols).contains(next.c) else {
            return die()
        }

        let willGrow = next == food
        var body = snake
        if !willGrow { body.removeLast() }  // tail vacates the cell this tick
        guard !body.contains(next) else { return die() }

        body.insert(next, at: 0)
        snake = body

        if willGrow {
            score += 10
            Haptics.move()
            spawnFood()
        }
    }

    private func die() {
        stop()
        state = .gameOver(won: false)
    }

    private func spawnFood() {
        let occupied = Set(snake)
        var free: [GridPos] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let p = GridPos(r: r, c: c)
                if !occupied.contains(p) { free.append(p) }
            }
        }
        if let spot = free.randomElement() {
            food = spot
        } else {
            stop()
            state = .gameOver(won: true)  // board completely filled
        }
    }
}

// MARK: - View

struct SnakeView: View {
    @State private var engine = SnakeEngine()

    var body: some View {
        GameContainerView(gameID: .snake, engine: engine) {
            VStack(spacing: 20) {
                board
                controls
            }
        }
        .onAppear { engine.start() }
        .onDisappear { engine.stop() }
    }

    private var board: some View {
        let snake = engine.snake
        let food = engine.food
        return Canvas { context, size in
            let cell = min(size.width / CGFloat(SnakeEngine.cols),
                           size.height / CGFloat(SnakeEngine.rows))

            func rect(_ p: GridPos, inset: CGFloat = 1) -> CGRect {
                CGRect(x: CGFloat(p.c) * cell, y: CGFloat(p.r) * cell, width: cell, height: cell)
                    .insetBy(dx: inset, dy: inset)
            }

            // Checkerboard backdrop
            for r in 0..<SnakeEngine.rows {
                for c in 0..<SnakeEngine.cols where (r + c).isMultiple(of: 2) {
                    context.fill(Path(rect(GridPos(r: r, c: c), inset: 0)),
                                 with: .color(Theme.neon.opacity(0.05)))
                }
            }

            // Food
            context.fill(Path(ellipseIn: rect(food, inset: cell * 0.15)),
                         with: .color(.red))

            // Snake body, head drawn brighter
            for (i, segment) in snake.enumerated() {
                let path = Path(roundedRect: rect(segment), cornerRadius: cell * 0.25)
                context.fill(path, with: .color(i == 0 ? Theme.neon : Theme.neon.opacity(0.65)))
            }
        }
        .aspectRatio(CGFloat(SnakeEngine.cols) / CGFloat(SnakeEngine.rows), contentMode: .fit)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .gesture(swipe)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let direction: SnakeDirection = abs(dx) > abs(dy)
                    ? (dx > 0 ? .right : .left)
                    : (dy > 0 ? .down : .up)
                engine.changeDirection(direction)
                Haptics.tap()
            }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            directionButton(.up, symbol: "arrowtriangle.up.fill")
            HStack(spacing: 36) {
                directionButton(.left, symbol: "arrowtriangle.left.fill")
                directionButton(.down, symbol: "arrowtriangle.down.fill")
                directionButton(.right, symbol: "arrowtriangle.right.fill")
            }
        }
    }

    private func directionButton(_ direction: SnakeDirection, symbol: String) -> some View {
        Button {
            engine.changeDirection(direction)
            Haptics.tap()
        } label: {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 56, height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
                .foregroundStyle(Theme.neon)
        }
    }
}
