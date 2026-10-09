import SwiftUI
import Observation

// MARK: - Engine

@MainActor
@Observable
final class WaterSortEngine: GameEngine {
    static let capacity = 4
    static let colorCount = 6
    static let emptyTubes = 2

    /// Each tube stores color indices bottom-to-top.
    private(set) var tubes: [[Int]] = []
    private(set) var moves = 0
    private var history: [[[Int]]] = []
    var selected: Int?
    var state: GameState = .playing

    var completedTubes: Int {
        tubes.filter { $0.count == Self.capacity && Set($0).count == 1 }.count
    }

    var canUndo: Bool { !history.isEmpty }

    var score: Int {
        completedTubes * 50 + (isWon ? max(0, 200 - moves * 3) : 0)
    }

    private var isWon: Bool {
        tubes.allSatisfy { $0.isEmpty || ($0.count == Self.capacity && Set($0).count == 1) }
    }

    init() {
        tubes = Self.generate()
    }

    func restart() {
        tubes = Self.generate()
        moves = 0
        history = []
        selected = nil
        state = .playing
    }

    /// Shuffles 4 segments of each color across the filled tubes,
    /// rejecting deals that start with an already-solved tube.
    private static func generate() -> [[Int]] {
        var deal: [[Int]]
        repeat {
            var pool: [Int] = []
            for color in 0..<colorCount { pool.append(contentsOf: Array(repeating: color, count: capacity)) }
            pool.shuffle()
            deal = (0..<colorCount).map { i in
                Array(pool[(i * capacity)..<((i + 1) * capacity)])
            }
        } while deal.contains { Set($0).count == 1 }
        deal.append(contentsOf: Array(repeating: [], count: emptyTubes))
        return deal
    }

    func tap(_ index: Int) {
        guard state == .playing, tubes.indices.contains(index) else { return }
        guard let source = selected else {
            if !tubes[index].isEmpty {
                selected = index
                Haptics.tap()
            }
            return
        }
        if source == index {
            selected = nil
            return
        }
        if pour(from: source, to: index) {
            selected = nil
        } else {
            // Invalid pour — treat the tap as picking a new tube.
            selected = tubes[index].isEmpty ? nil : index
            Haptics.tap()
        }
    }

    /// Pours the top same-color run of `from` into `to` when the colors
    /// match (or `to` is empty) and there is room. Returns false when illegal.
    private func pour(from: Int, to: Int) -> Bool {
        guard let color = tubes[from].last else { return false }
        let free = Self.capacity - tubes[to].count
        guard free > 0, tubes[to].isEmpty || tubes[to].last == color else { return false }

        var run = 0
        for value in tubes[from].reversed() {
            if value == color { run += 1 } else { break }
        }
        let amount = min(run, free)

        history.append(tubes)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            tubes[from].removeLast(amount)
            tubes[to].append(contentsOf: Array(repeating: color, count: amount))
            moves += 1
        }

        let filledTube = tubes[to].count == Self.capacity && Set(tubes[to]).count == 1
        if filledTube { Haptics.success() } else { Haptics.move() }

        if isWon {
            state = .gameOver(won: true)
        } else if isStuck {
            state = .gameOver(won: false)
        }
        return true
    }

    func undo() {
        guard state == .playing, let previous = history.popLast() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            tubes = previous
        }
        selected = nil
        Haptics.tap()
    }

    /// True when no legal pour exists anywhere.
    private var isStuck: Bool {
        for from in tubes.indices {
            guard let color = tubes[from].last else { continue }
            for to in tubes.indices where to != from {
                let free = Self.capacity - tubes[to].count
                if free > 0, tubes[to].isEmpty || tubes[to].last == color {
                    return false
                }
            }
        }
        return true
    }
}

// MARK: - View

struct WaterSortView: View {
    @State private var engine = WaterSortEngine()

    private static let palette: [Color] = [.red, .blue, .green, .yellow, .purple, .cyan]

    var body: some View {
        GameContainerView(gameID: .waterSort, engine: engine) {
            VStack(spacing: 24) {
                statusBar
                tubesGrid
                Text(L10n.text("Tap a tube to pick it up, then tap another to pour."))
                    .font(.footnote)
                    .foregroundStyle(GameTheme.textSecondary)
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Label(L10n.format("%d moves", engine.moves), systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
                .contentTransition(.numericText())
            Spacer()
            Button {
                engine.undo()
            } label: {
                Label(L10n.text("Undo"), systemImage: "arrow.uturn.backward")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.canUndo ? GameTheme.accent : GameTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(GameTheme.surface, in: Capsule())
                    .overlay { Capsule().strokeBorder(GameTheme.stroke, lineWidth: 1) }
            }
            .disabled(!engine.canUndo)
        }
        .padding(.horizontal, 4)
    }

    private var tubesGrid: some View {
        let tubeCount = engine.tubes.count
        let perRow = (tubeCount + 1) / 2
        return VStack(spacing: 28) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(0..<perRow, id: \.self) { col in
                        let index = row * perRow + col
                        if index < tubeCount {
                            tube(at: index)
                        }
                    }
                }
            }
        }
    }

    private func tube(at index: Int) -> some View {
        let contents = engine.tubes[index]
        let isSelected = engine.selected == index
        let capacity = WaterSortEngine.capacity

        return VStack(spacing: 3) {
            ForEach((0..<capacity).reversed(), id: \.self) { slot in
                RoundedRectangle(cornerRadius: 6)
                    .fill(slot < contents.count
                          ? AnyShapeStyle(Self.palette[contents[slot]].gradient)
                          : AnyShapeStyle(Color.clear))
                    .frame(height: 30)
            }
        }
        .padding(5)
        .frame(width: 58)
        .background(
            GameTheme.surface,
            in: UnevenRoundedRectangle(topLeadingRadius: 6,
                                       bottomLeadingRadius: 18,
                                       bottomTrailingRadius: 18,
                                       topTrailingRadius: 6)
        )
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 6,
                                   bottomLeadingRadius: 18,
                                   bottomTrailingRadius: 18,
                                   topTrailingRadius: 6)
                .strokeBorder(isSelected ? GameTheme.accent : GameTheme.stroke, lineWidth: isSelected ? 2 : 1)
        }
        .offset(y: isSelected ? -14 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(index) }
    }
}
