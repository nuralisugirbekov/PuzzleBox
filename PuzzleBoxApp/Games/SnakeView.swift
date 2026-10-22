import SwiftUI
import Observation

// MARK: - Engine

enum SnakeDirection: Codable {
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
    /// Ticks the golden apple stays on the board.
    static let goldenLifetime = 32
    /// Eating again within this many ticks keeps the combo alive.
    static let comboWindow = 14

    private(set) var snake: [GridPos] = []  // head first
    private(set) var food = GridPos(r: 0, c: 0)
    private(set) var golden: GridPos?
    private(set) var goldenTicksLeft = 0
    private(set) var rocks: Set<GridPos> = []
    private(set) var score = 0
    private(set) var eaten = 0
    private(set) var combo = 0
    private(set) var level = 1
    private(set) var direction: SnakeDirection = .right
    /// Bumped on every bite so the view can pulse the head.
    private(set) var bite = 0
    var state: GameState = .playing
    let popups = ClassicFXPopupFeed()

    /// Up to two buffered turns, so quick swipes (e.g. a U-turn) are not lost.
    private var queued: [SnakeDirection] = []
    private var ticksSinceFood = 0
    private var loopTask: Task<Void, Never>?

    /// Tick interval shrinks as more food is eaten, down to a floor.
    private var tickMilliseconds: Int { max(85, 210 - eaten * 4) }

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
        queued = []
        score = 0; eaten = 0; combo = 0; level = 1; bite = 0
        golden = nil; goldenTicksLeft = 0; rocks = []; ticksSinceFood = 0
        popups.clear()
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
        guard state == .playing else { return }
        let last = queued.last ?? direction
        guard new != last, new != last.opposite, queued.count < 2 else { return }
        queued.append(new)
    }

    private func tick() {
        if !queued.isEmpty { direction = queued.removeFirst() }
        guard let head = snake.first else { return }
        let next = GridPos(r: head.r + direction.dr, c: head.c + direction.dc)

        guard (0..<Self.rows).contains(next.r), (0..<Self.cols).contains(next.c), !rocks.contains(next) else {
            return die()
        }

        let eatsFood = next == food
        let eatsGolden = next == golden
        var body = snake
        if !eatsFood && !eatsGolden { body.removeLast() }  // tail vacates the cell this tick
        guard !body.contains(next) else { return die() }

        body.insert(next, at: 0)
        snake = body
        ticksSinceFood += 1

        if goldenTicksLeft > 0 {
            goldenTicksLeft -= 1
            if goldenTicksLeft == 0 { golden = nil }
        }

        if eatsFood || eatsGolden {
            combo = ticksSinceFood <= Self.comboWindow ? combo + 1 : 1
            ticksSinceFood = 0
            let multiplier = min(combo, 4)
            let base = eatsGolden ? 50 : 10
            let gained = base * multiplier
            score += gained
            bite += 1
            let anchor = UnitPoint(x: (Double(next.c) + 0.5) / Double(Self.cols), y: (Double(next.r) + 0.5) / Double(Self.rows))
            popups.show(multiplier > 1 ? "+\(gained) ×\(multiplier)" : "+\(gained)",
                        color: eatsGolden ? .yellow : .white, at: anchor, large: eatsGolden)
            if eatsGolden {
                golden = nil; goldenTicksLeft = 0
                Haptics.success(); SoundFX.play(.win)
            } else {
                eaten += 1
                Haptics.move(); SoundFX.play(multiplier > 1 ? .merge : .coin)
                spawnFood()
                if eaten.isMultiple(of: 5) { levelUp() }
                if golden == nil, eaten.isMultiple(of: 4) { spawnGolden() }
            }
        }
    }

    /// Every five apples the board gets a little harder: a new rock appears.
    private func levelUp() {
        level += 1
        guard let head = snake.first else { return }
        let candidates = freeCells().filter { abs($0.r - head.r) + abs($0.c - head.c) > 4 && $0 != food }
        if let rock = candidates.randomElement() {
            rocks.insert(rock)
            popups.show(L10n.format("Level %d", level), color: .orange,
                        at: UnitPoint(x: 0.5, y: 0.2), large: true)
            SoundFX.play(.clear)
        }
    }

    private func spawnGolden() {
        guard let spot = freeCells().filter({ $0 != food }).randomElement() else { return }
        golden = spot
        goldenTicksLeft = Self.goldenLifetime
    }

    private func die() {
        stop()
        state = .gameOver(won: false)
    }

    private func freeCells() -> [GridPos] {
        let occupied = Set(snake).union(rocks).union(golden.map { [$0] } ?? [])
        var free: [GridPos] = []
        for r in 0..<Self.rows {
            for c in 0..<Self.cols {
                let p = GridPos(r: r, c: c)
                if !occupied.contains(p) { free.append(p) }
            }
        }
        return free
    }

    private func spawnFood() {
        if let spot = freeCells().randomElement() {
            food = spot
        } else {
            stop()
            state = .gameOver(won: true)  // board completely filled
        }
    }
}

// MARK: - Saved round

extension SnakeEngine: ResumableGame {
    private struct Session: Codable {
        let snake: [GridPos]
        let food: GridPos
        let golden: GridPos?
        let goldenTicksLeft: Int
        let rocks: Set<GridPos>
        let score: Int
        let eaten: Int
        let combo: Int
        let level: Int
        let direction: SnakeDirection
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, eaten > 0 else { return nil }
        return encodeSession(Session(snake: snake, food: food, golden: golden, goldenTicksLeft: goldenTicksLeft,
                                     rocks: rocks, score: score, eaten: eaten, combo: combo, level: level,
                                     direction: direction))
    }

    /// Restores the board exactly; the snake moves once the player continues.
    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), !s.snake.isEmpty else { return false }
        snake = s.snake; food = s.food; golden = s.golden; goldenTicksLeft = s.goldenTicksLeft
        rocks = s.rocks; score = s.score; eaten = s.eaten; combo = s.combo; level = s.level
        direction = s.direction; queued = []; ticksSinceFood = 0
        popups.clear()
        return true
    }
}

// MARK: - View

struct SnakeView: View {
    @State private var engine = SnakeEngine()

    var body: some View {
        GameContainerView(gameID: .snake, engine: engine) {
            VStack(spacing: 16) {
                hud
                board
                Text(L10n.text("Swipe on the board to steer the snake. Eat apples quickly for a combo and grab golden apples before they vanish."))
                    .font(.footnote)
                    .foregroundStyle(GameTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
            func center(_ p: GridPos) -> CGPoint { CGPoint(x: (CGFloat(p.c) + 0.5) * cell, y: (CGFloat(p.r) + 0.5) * cell) }

            // Grass checkerboard
            for r in 0..<SnakeEngine.rows {
                for c in 0..<SnakeEngine.cols {
                    let light = (r + c).isMultiple(of: 2)
                    context.fill(Path(rect(GridPos(r: r, c: c), inset: 0)),
                                 with: .color(light ? Color(red: 0.55, green: 0.8, blue: 0.35) : Color(red: 0.5, green: 0.74, blue: 0.31)))
                }
            }

            // Rocks
            for rock in engine.rocks {
                let r = rect(rock, inset: cell * 0.08)
                context.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: cell * 0.06), cornerRadius: cell * 0.3), with: .color(.black.opacity(0.25)))
                context.fill(Path(roundedRect: r, cornerRadius: cell * 0.3),
                             with: .linearGradient(Gradient(colors: [Color(white: 0.7), Color(white: 0.42)]), startPoint: CGPoint(x: r.minX, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                context.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.2, width: r.width * 0.25, height: r.height * 0.18)), with: .color(.white.opacity(0.35)))
            }

            func apple(_ p: GridPos, top: Color, bottom: Color, scale: CGFloat = 1) {
                let r = rect(p, inset: cell * (0.5 - 0.36 * scale))
                context.fill(Path(ellipseIn: r.offsetBy(dx: 0, dy: cell * 0.05)), with: .color(.black.opacity(0.2)))
                context.fill(Path(ellipseIn: r), with: .radialGradient(Gradient(colors: [top, bottom]), center: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.3), startRadius: 0, endRadius: r.width))
                context.fill(Path(ellipseIn: CGRect(x: r.midX, y: r.minY - cell * 0.12, width: cell * 0.22, height: cell * 0.14)), with: .color(Color(red: 0.2, green: 0.6, blue: 0.2)))
                context.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.22, y: r.minY + r.height * 0.18, width: r.width * 0.2, height: r.height * 0.14)), with: .color(.white.opacity(0.6)))
            }
            apple(food, top: Color(red: 1, green: 0.45, blue: 0.4), bottom: Color(red: 0.8, green: 0.08, blue: 0.1))
            if let golden = engine.golden {
                // A ring drains to show how long the golden apple stays.
                let c = center(golden)
                let fraction = Double(engine.goldenTicksLeft) / Double(SnakeEngine.goldenLifetime)
                context.fill(Path(ellipseIn: CGRect(x: c.x - cell * 0.7, y: c.y - cell * 0.7, width: cell * 1.4, height: cell * 1.4)), with: .color(.yellow.opacity(0.25)))
                var ring = Path()
                ring.addArc(center: c, radius: cell * 0.62, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
                context.stroke(ring, with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                apple(golden, top: Color(red: 1, green: 0.95, blue: 0.55), bottom: Color(red: 0.95, green: 0.65, blue: 0.05), scale: 1.05)
            }

            // Snake: one rounded stroke through the segment centres, fading toward the tail.
            let count = snake.count
            for (i, segment) in snake.enumerated().reversed() {
                let t = Double(i) / Double(max(1, count - 1))
                let color = Color(hue: 0.58 - t * 0.08, saturation: 0.75, brightness: 0.95 - t * 0.3)
                let width = cell * (0.86 - CGFloat(t) * 0.22)
                if i + 1 < count {
                    var link = Path(); link.move(to: center(segment)); link.addLine(to: center(snake[i + 1]))
                    context.stroke(link, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
                let c = center(segment)
                context.fill(Path(ellipseIn: CGRect(x: c.x - width / 2, y: c.y - width / 2, width: width, height: width)), with: .color(color))
            }
            if let head = snake.first {
                let c = center(head)
                let d = engine.direction
                let forward = CGPoint(x: CGFloat(d.dc), y: CGFloat(d.dr))
                let side = CGPoint(x: -forward.y, y: forward.x)
                for s in [-1.0, 1.0] {
                    let eye = CGPoint(x: c.x + forward.x * cell * 0.14 + side.x * cell * 0.2 * s, y: c.y + forward.y * cell * 0.14 + side.y * cell * 0.2 * s)
                    context.fill(Path(ellipseIn: CGRect(x: eye.x - cell * 0.13, y: eye.y - cell * 0.13, width: cell * 0.26, height: cell * 0.26)), with: .color(.white))
                    context.fill(Path(ellipseIn: CGRect(x: eye.x + forward.x * cell * 0.04 - cell * 0.065, y: eye.y + forward.y * cell * 0.04 - cell * 0.065, width: cell * 0.13, height: cell * 0.13)), with: .color(.black))
                }
            }
        }
        .aspectRatio(CGFloat(SnakeEngine.cols) / CGFloat(SnakeEngine.rows), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(red: 0.3, green: 0.5, blue: 0.2), lineWidth: 3)
        }
        .overlay { ClassicFXPopupLayer(feed: engine.popups) }
        .gesture(swipe)
    }

    private var hud: some View {
        HStack {
            Label(L10n.format("Level %d", engine.level), systemImage: "flag.fill")
            Spacer()
            if engine.combo > 1 {
                Label { Text(verbatim: "×\(min(engine.combo, 4))") } icon: { Image(systemName: "flame.fill") }
                    .foregroundStyle(.orange)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(GameTheme.accent)
        .animation(.snappy, value: engine.combo)
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
                .background(GameTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(GameTheme.stroke, lineWidth: 1)
                }
                .foregroundStyle(GameTheme.accent)
        }
    }
}
