import SwiftUI
import Observation

@MainActor
@Observable
final class Game2048Engine: GameEngine {
    private(set) var tiles = Array(repeating: 0, count: 16)
    private(set) var score = 0
    var state: GameState = .playing

    enum Direction { case up, down, left, right }

    init() { restart() }

    func restart() {
        tiles = Array(repeating: 0, count: 16)
        score = 0
        state = .playing
        spawn()
        spawn()
    }

    private func spawn() {
        guard let index = tiles.indices.filter({ tiles[$0] == 0 }).randomElement() else { return }
        tiles[index] = Int.random(in: 0..<10) == 0 ? 4 : 2
    }

    func move(_ direction: Direction) {
        guard state == .playing else { return }
        let previous = tiles
        for line in 0..<4 {
            let indices: [Int]
            switch direction {
            case .left: indices = (0..<4).map { line * 4 + $0 }
            case .right: indices = (0..<4).reversed().map { line * 4 + $0 }
            case .up: indices = (0..<4).map { $0 * 4 + line }
            case .down: indices = (0..<4).reversed().map { $0 * 4 + line }
            }
            let values = indices.map { tiles[$0] }.filter { $0 != 0 }
            var merged: [Int] = []
            var index = 0
            while index < values.count {
                if index + 1 < values.count, values[index] == values[index + 1] {
                    let value = values[index] * 2
                    merged.append(value)
                    score += value
                    index += 2 // A merged tile cannot merge again during this move.
                } else {
                    merged.append(values[index])
                    index += 1
                }
            }
            merged += Array(repeating: 0, count: 4 - merged.count)
            for (index, value) in zip(indices, merged) { tiles[index] = value }
        }
        guard previous != tiles else { return }
        spawn()
        Haptics.move()
        if tiles.contains(2048) {
            state = .gameOver(won: true)
        } else if !hasMoves {
            state = .gameOver(won: false)
        }
    }

    private var hasMoves: Bool {
        if tiles.contains(0) { return true }
        for i in tiles.indices {
            if i % 4 < 3, tiles[i] == tiles[i + 1] { return true }
            if i / 4 < 3, tiles[i] == tiles[i + 4] { return true }
        }
        return false
    }
}

struct Game2048View: View {
    @State private var engine = Game2048Engine()

    var body: some View {
        GameContainerView(gameID: .game2048, engine: engine, centersContent: true) {
            VStack(spacing: 18) {
                Text(L10n.text("Merge matching tiles to reach 2048."))
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<4, id: \.self) { col in
                                tile(engine.tiles[row * 4 + col])
                            }
                        }
                    }
                }
                .padding(10).themeCard()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 20).onEnded { value in
                    let x = value.translation.width, y = value.translation.height
                    let direction: Game2048Engine.Direction = abs(x) > abs(y)
                        ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
                    withAnimation(.easeInOut(duration: 0.15)) { engine.move(direction) }
                })
                Text(L10n.text("Swipe to slide the tiles."))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func tile(_ value: Int) -> some View {
        let level = value == 0 ? 0 : Int(log2(Double(value)))
        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(value == 0 ? Theme.surfaceHigh : Color(hue: max(0.05, 0.24 - Double(level) * 0.016),
                                                            saturation: 0.65, brightness: 0.95))
            if value > 0 {
                Text(verbatim: "\(value)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1).padding(4)
                    .foregroundStyle(Color.black.opacity(0.85))
                    .contentTransition(.numericText())
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(value == 0 ? L10n.text("Empty tile") : "\(value)")
    }
}
