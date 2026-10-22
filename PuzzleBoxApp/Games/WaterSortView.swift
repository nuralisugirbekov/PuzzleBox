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

    /// A pour for the view to animate; `tubes` already hold its result.
    struct Pour: Equatable {
        let id: Int
        let from: Int
        let to: Int
        let color: Int
        let amount: Int
    }
    private(set) var lastPour: Pour?
    /// Lift, tilt, pour and return, in seconds.
    static let pourDuration = 1.0

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
        tubes[from].removeLast(amount)
        tubes[to].append(contentsOf: Array(repeating: color, count: amount))
        withAnimation(.snappy) { moves += 1 }
        let pour = Pour(id: (lastPour?.id ?? 0) + 1, from: from, to: to, color: color, amount: amount)
        lastPour = pour
        Haptics.move(); SoundFX.play(.pour)

        // A filled tube, a win or a dead end is announced once the liquid has landed.
        let filledTube = tubes[to].count == Self.capacity && Set(tubes[to]).count == 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.pourDuration * 0.8))
            guard let self, self.lastPour == pour, self.state == .playing else { return }
            if filledTube { Haptics.success(); SoundFX.play(.clear) }
            if self.isWon {
                self.state = .gameOver(won: true)
            } else if self.isStuck {
                self.state = .gameOver(won: false)
            }
        }
        return true
    }

    func undo() {
        guard state == .playing, let previous = history.popLast() else { return }
        lastPour = nil
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
    @State private var pour: ActivePour?
    @State private var tubeFrames: [Int: CGRect] = [:]

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
            .disabled(!engine.canUndo || pour != nil)
        }
        .padding(.horizontal, 4)
    }

    private var tubesGrid: some View {
        let tubeCount = engine.tubes.count
        let perRow = (tubeCount + 1) / 2
        // Tubes narrow as the level adds colours, so two rows always fit.
        let width = min(58, (340 - 10 * CGFloat(perRow - 1)) / CGFloat(perRow))
        return TimelineView(.animation(paused: pour == nil)) { timeline in
            let phase = pour.map { PourPhase(elapsed: timeline.date.timeIntervalSince($0.start)) }
            VStack(spacing: 28) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: perRow > 5 ? 10 : 18) {
                        ForEach(0..<perRow, id: \.self) { col in
                            let index = row * perRow + col
                            if index < tubeCount {
                                tube(at: index, width: width, phase: phase)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(TubeFramesKey.self) { tubeFrames = $0 }
            .overlay(alignment: .topLeading) {
                if let pour, let phase { pouringTube(pour, phase: phase, width: width) }
            }
        }
        .onChange(of: engine.lastPour) { _, new in
            guard let new else { pour = nil; return }
            pour = ActivePour(pour: new, start: .now)
            Task {
                try? await Task.sleep(for: .seconds(WaterSortEngine.pourDuration))
                if pour?.pour == new { pour = nil }
            }
        }
    }

    // MARK: Tubes

    private static let space = "waterSort"
    private static let tubeHeight: CGFloat = 150
    /// Empty glass above a full tube, so it reads as a vessel and not a block.
    private static let headroom: CGFloat = 18
    /// Height of one unit of liquid.
    private static var unit: CGFloat { (tubeHeight - headroom - 4) / CGFloat(WaterSortEngine.capacity) }

    /// The glass: square-ish mouth, round bottom.
    private static func glass(_ width: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: width / 2,
                               bottomTrailingRadius: width / 2, topTrailingRadius: 6)
    }

    /// Liquid layers bottom to top, same colours merged, with a pour in
    /// progress added back to the source or held back from the target.
    private func layers(_ index: Int, phase: PourPhase?) -> [(color: Int, amount: Double)] {
        var units = engine.tubes[index].map { (color: $0, amount: 1.0) }
        if let pour, let phase {
            let moved = Double(pour.pour.amount)
            if index == pour.pour.to {
                units.removeLast(min(units.count, pour.pour.amount))
                units.append((pour.pour.color, moved * phase.transferred))
            } else if index == pour.pour.from {
                units.append((pour.pour.color, moved * (1 - phase.transferred)))
            }
        }
        var merged: [(color: Int, amount: Double)] = []
        for unit in units where unit.amount > 0.001 {
            if let last = merged.last, last.color == unit.color {
                merged[merged.count - 1].amount += unit.amount
            } else {
                merged.append(unit)
            }
        }
        return merged
    }

    private func liquid(_ index: Int, width: CGFloat, phase: PourPhase?) -> some View {
        let unit = Self.unit
        let layers = self.layers(index, phase: phase)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(layers.enumerated().reversed()), id: \.offset) { i, layer in
                let color = Self.palette[layer.color]
                Rectangle()
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .top) {
                        // The surface of the top layer catches the light.
                        if i == layers.count - 1 { Rectangle().fill(.white.opacity(0.35)).frame(height: 2) }
                    }
                    .frame(height: unit * layer.amount)
            }
        }
        .frame(width: width - 8, height: Self.tubeHeight - 4)
        .clipShape(Self.glass(width - 8))
    }

    private func vessel(_ index: Int, width: CGFloat, phase: PourPhase?, selected: Bool) -> some View {
        liquid(index, width: width, phase: phase)
            .frame(width: width, height: Self.tubeHeight)
            .background(GameTheme.surface.opacity(0.6), in: Self.glass(width))
            .overlay {
                Self.glass(width)
                    .strokeBorder(selected ? GameTheme.accent : Color.white.opacity(0.28), lineWidth: selected ? 2 : 1.5)
            }
            .overlay(alignment: .leading) {
                // A glint down the glass.
                Capsule().fill(.white.opacity(0.18)).frame(width: 3, height: Self.tubeHeight * 0.6).padding(.leading, 6)
            }
    }

    private func tube(at index: Int, width: CGFloat, phase: PourPhase?) -> some View {
        let isSelected = engine.selected == index
        return vessel(index, width: width, phase: phase, selected: isSelected)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TubeFramesKey.self, value: [index: geo.frame(in: .named(Self.space))])
                }
            }
            // The pouring tube is drawn by `pouringTube` while it's away.
            .opacity(pour?.pour.from == index ? 0 : 1)
            .offset(y: isSelected ? -14 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
            .contentShape(Rectangle())
            .onTapGesture { if pour == nil { engine.tap(index) } }
    }

    /// The source tube lifted over the target and tipped, with the stream.
    @ViewBuilder
    private func pouringTube(_ active: ActivePour, phase: PourPhase, width: CGFloat) -> some View {
        if let from = tubeFrames[active.pour.from], let to = tubeFrames[active.pour.to] {
            // It leaves from its picked-up height and lands back in its slot.
            let home = CGPoint(x: from.midX, y: from.midY - (phase.returning ? 0 : 14))
            let toRight = to.midX >= from.midX
            let tilt = (toRight ? 1.0 : -1.0) * 72.0
            let radians = tilt * .pi / 180
            // The mouth ends just above the middle of the target's opening.
            let mouth = CGPoint(x: to.midX + (toRight ? -6 : 6), y: to.minY - 16)
            let half = Self.tubeHeight / 2
            let over = CGPoint(x: mouth.x - half * sin(radians), y: mouth.y + half * cos(radians))
            let center = CGPoint(x: home.x + (over.x - home.x) * phase.travel, y: home.y + (over.y - home.y) * phase.travel)
            let surface = to.maxY - 4 - Self.unit * CGFloat(engine.tubes[active.pour.to].count - active.pour.amount)
            ZStack(alignment: .topLeading) {
                if phase.streaming {
                    Path { p in
                        p.move(to: mouth)
                        p.addLine(to: CGPoint(x: mouth.x + (toRight ? 6 : -6), y: mouth.y + 10))
                        p.addLine(to: CGPoint(x: mouth.x + (toRight ? 6 : -6), y: surface))
                    }
                    .stroke(Self.palette[active.pour.color],
                            style: StrokeStyle(lineWidth: max(4, width * 0.14), lineCap: .round, lineJoin: .round))
                }
                vessel(active.pour.from, width: width, phase: phase, selected: false)
                    .rotationEffect(.degrees(tilt * phase.travel))
                    .position(center)
            }
            .allowsHitTesting(false)
        }
    }
}

/// Where a pour animation is.
private struct ActivePour {
    let pour: WaterSortEngine.Pour
    let start: Date
}

/// Lift and tilt (0…0.3), pour (0.3…0.75), return (0.75…1) of `pourDuration`.
private struct PourPhase {
    /// How far the tube is from home toward its pouring spot (0…1).
    let travel: Double
    /// How much of the run has left the source (0…1).
    let transferred: Double
    let streaming: Bool
    let returning: Bool

    init(elapsed: TimeInterval) {
        let t = min(1, max(0, elapsed / WaterSortEngine.pourDuration))
        returning = t >= 0.75
        func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
        if t < 0.3 {
            travel = ease(t / 0.3); transferred = 0; streaming = false
        } else if t < 0.75 {
            travel = 1; transferred = ease((t - 0.3) / 0.45); streaming = true
        } else {
            travel = 1 - ease((t - 0.75) / 0.25); transferred = 1; streaming = false
        }
    }
}

private struct TubeFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Saved round

extension WaterSortEngine: ResumableGame {
    private struct Session: Codable {
        let level: Int
        let tubes: [[Int]]
        let moves: Int
        let extraTubeUsed: Bool
        let history: [[[Int]]]
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, moves > 0 || extraTubeUsed else { return nil }
        return encodeSession(Session(level: level, tubes: tubes, moves: moves,
                                     extraTubeUsed: extraTubeUsed, history: history))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data),
              (1...Self.levelCount).contains(session.level) else { return false }
        level = session.level
        tubes = session.tubes
        moves = session.moves
        extraTubeUsed = session.extraTubeUsed
        history = session.history
        selected = nil
        state = .playing
        return true
    }
}
