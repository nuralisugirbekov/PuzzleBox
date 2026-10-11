import SwiftUI
import Observation

// MARK: - Engine

@MainActor
@Observable
final class WaterSortEngine: GameEngine {
    static let capacity = 4
    static let emptyTubes = 2
    static let levelCount = 60
    private static let levelKey = "waterSortLevel"

    /// Each tube stores color indices bottom-to-top.
    private(set) var tubes: [[Int]] = []
    private(set) var moves = 0
    private(set) var level = 1
    private(set) var extraTubeUsed = false
    private var history: [[[Int]]] = []
    var selected: Int?
    var state: GameState = .playing

    var colorCount: Int { min(10, 3 + (level - 1) / 3) }
    var hasNextLevel: Bool { level < Self.levelCount }

    var completedTubes: Int {
        tubes.filter { $0.count == Self.capacity && Set($0).count == 1 }.count
    }

    var canUndo: Bool { !history.isEmpty }

    var score: Int {
        completedTubes * 20 + (isWon ? 100 + level * 30 + max(0, 150 - moves * 2) : 0)
    }

    private var isWon: Bool {
        tubes.allSatisfy { $0.isEmpty || ($0.count == Self.capacity && Set($0).count == 1) }
    }

    init() {
        level = max(1, min(Self.levelCount, UserDefaults.standard.integer(forKey: Self.levelKey)))
        tubes = Self.generate(level: level, colors: colorCount)
    }

    func restart() {
        tubes = Self.generate(level: level, colors: colorCount)
        moves = 0
        history = []
        selected = nil
        extraTubeUsed = false
        state = .playing
    }

    func selectLevel(_ value: Int) {
        guard (1...Self.levelCount).contains(value) else { return }
        level = value
        UserDefaults.standard.set(level, forKey: Self.levelKey)
        restart()
    }
    func nextLevel() { selectLevel(level + 1) }

    /// One spare empty tube per level, for when you get stuck.
    func addTube() {
        guard state == .playing, !extraTubeUsed else { return }
        extraTubeUsed = true
        history.append(tubes)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { tubes.append([]) }
        Haptics.move(); SoundFX.play(.whoosh)
    }

    /// Deterministic per level, and checked by a solver so every deal can be finished.
    private static func generate(level: Int, colors: Int) -> [[Int]] {
        var random = PuzzleRandom(seed: UInt64(level) &* 104_729 &+ 17)
        while true {
            var pool: [Int] = []
            for color in 0..<colors { pool.append(contentsOf: Array(repeating: color, count: capacity)) }
            pool.shuffle(using: &random)
            var deal = (0..<colors).map { i in Array(pool[(i * capacity)..<((i + 1) * capacity)]) }
            guard !deal.contains(where: { Set($0).count == 1 }) else { continue }
            deal.append(contentsOf: Array(repeating: [], count: emptyTubes))
            if isSolvable(deal) { return deal }
        }
    }

    /// Depth-first search over pours with a visited set and a node budget.
    static func isSolvable(_ start: [[Int]], budget: Int = 40_000) -> Bool {
        var seen = Set<[[Int]]>()
        var stack = [start]
        while let tubes = stack.popLast() {
            if tubes.allSatisfy({ $0.isEmpty || ($0.count == capacity && Set($0).count == 1) }) { return true }
            guard seen.insert(tubes.sorted { $0.lexicographicallyPrecedes($1) }).inserted else { continue }
            if seen.count > budget { return false }
            for from in tubes.indices {
                guard let color = tubes[from].last else { continue }
                let fromTube = tubes[from]
                if fromTube.count == capacity && Set(fromTube).count == 1 { continue }
                let run = fromTube.reversed().prefix { $0 == color }.count
                var triedEmpty = false
                for to in tubes.indices where to != from {
                    let target = tubes[to]
                    let free = capacity - target.count
                    guard free > 0, target.isEmpty || target.last == color else { continue }
                    if target.isEmpty {
                        // Pouring a single-colour tube into an empty one changes nothing.
                        if run == fromTube.count || triedEmpty { continue }
                        triedEmpty = true
                    }
                    var next = tubes
                    let amount = min(run, free)
                    next[from].removeLast(amount)
                    next[to].append(contentsOf: Array(repeating: color, count: amount))
                    stack.append(next)
                }
            }
        }
        return false
    }

    func tap(_ index: Int) {
        guard state == .playing, tubes.indices.contains(index) else { return }
        guard let source = selected else {
            if !tubes[index].isEmpty {
                selected = index
                Haptics.tap(); SoundFX.play(.tap)
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
            Haptics.tap(); SoundFX.play(.tap)
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
        if filledTube { Haptics.success(); SoundFX.play(.clear) } else { Haptics.move(); SoundFX.play(.pour) }

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
        Haptics.tap(); SoundFX.play(.tap)
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

    private static let palette: [Color] = [.red, .blue, .green, .yellow, .purple, .cyan, .orange, .pink, .mint,
                                           Color(red: 0.55, green: 0.35, blue: 0.2)]

    var body: some View {
        GameContainerView(gameID: .waterSort, engine: engine,
                          resultSummary: L10n.format("Level %d", engine.level),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 24) {
                statusBar
                tubesGrid
                Text(L10n.text("Tap a tube to pick it up, then tap another to pour."))
                    .font(.footnote)
                    .foregroundStyle(GameTheme.textSecondary)
            }
        }
        .id(engine.level)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(1...WaterSortEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                Label(L10n.format("Level %d", engine.level), systemImage: "flask.fill")
                    .font(.subheadline.weight(.semibold))
            }
            Label(L10n.format("%d moves", engine.moves), systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
                .contentTransition(.numericText())
            Spacer()
            Button {
                engine.addTube()
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.bold())
                    .frame(width: 36, height: 34)
                    .background(GameTheme.surface, in: Capsule())
                    .foregroundStyle(engine.extraTubeUsed ? GameTheme.textSecondary : GameTheme.accent)
            }
            .disabled(engine.extraTubeUsed)
            .accessibilityLabel(L10n.text("Extra tube"))
            Button {
                engine.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
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
        // Tubes narrow as the level adds colours, so two rows always fit.
        let width = min(58, (340 - 10 * CGFloat(perRow - 1)) / CGFloat(perRow))
        return VStack(spacing: 28) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: perRow > 5 ? 10 : 18) {
                    ForEach(0..<perRow, id: \.self) { col in
                        let index = row * perRow + col
                        if index < tubeCount {
                            tube(at: index, width: width)
                        }
                    }
                }
            }
        }
    }

    private func tube(at index: Int, width: CGFloat) -> some View {
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
        .frame(width: width)
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
