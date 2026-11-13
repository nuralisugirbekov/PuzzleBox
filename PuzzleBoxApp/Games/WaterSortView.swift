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
        lastPour = nil
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

    /// `pickable` is false for a tube that is still being poured into: it can
    /// take more liquid but can't be picked up until its pour has landed.
    func tap(_ index: Int, pickable: Bool = true) {
        guard state == .playing, tubes.indices.contains(index) else { return }
        guard let source = selected else {
            if pickable, !tubes[index].isEmpty {
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
            selected = tubes[index].isEmpty || !pickable ? nil : index
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
        Haptics.move()
        // The view plays the pour's sounds as the liquid runs, and calls
        // `settle()` once every pour has landed.
        return true
    }

    /// True when `index` holds one colour to the brim.
    func isComplete(_ index: Int) -> Bool {
        tubes.indices.contains(index) && tubes[index].count == Self.capacity && Set(tubes[index]).count == 1
    }

    /// Ends the round on a win or a dead end; called once no pour is running,
    /// so the result never shows over liquid still in the air.
    func settle() {
        guard state == .playing else { return }
        if isWon {
            state = .gameOver(won: true)
        } else if isStuck {
            state = .gameOver(won: false)
        }
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
    @State private var pours: [ActivePour] = []
    @State private var tubeFrames: [Int: CGRect] = [:]
    /// The board's distance from the screen's left edge, to keep tipped tubes on screen.
    @State private var boardOrigin: CGFloat = 16

    /// Red, blue, green, yellow, purple, cyan, orange, pink, mint and brown,
    /// spread apart so neighbouring layers never blur together.
    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.27, blue: 0.24), Color(red: 0.18, green: 0.49, blue: 0.96),
        Color(red: 0.20, green: 0.77, blue: 0.42), Color(red: 1.00, green: 0.82, blue: 0.25),
        Color(red: 0.61, green: 0.36, blue: 0.96), Color(red: 0.13, green: 0.76, blue: 0.90),
        Color(red: 1.00, green: 0.54, blue: 0.16), Color(red: 1.00, green: 0.37, blue: 0.66),
        Color(red: 0.37, green: 0.88, blue: 0.72), Color(red: 0.60, green: 0.38, blue: 0.20),
    ]

    var body: some View {
        GameContainerView(gameID: .waterSort, engine: engine,
                          resultSummary: L10n.format("Level %d", engine.level),
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil,
                          chrome: .inGame,
                          backdrop: AnyView(ToyWaterSort.palette.backdrop),
                          toyStyle: ToyWaterSort.palette.style) {
            ToyGameStage(palette: ToyWaterSort.palette) {
                ToyIconButton(symbol: "arrow.uturn.backward", label: L10n.text("Undo"), ink: ToyWaterSort.palette.ink) {
                    engine.undo()
                }
                .disabled(!engine.canUndo)
                .opacity(engine.canUndo ? 1 : 0.55)
            } content: {
                VStack(spacing: 0) {
                    statusBar
                        .padding(.top, 14)
                    Spacer(minLength: 16)
                    tubesGrid
                    Spacer(minLength: 16)
                    // Only until the first pour.
                    Text(L10n.text("Tap a tube to pick it up, then tap another to pour."))
                        .font(.system(.footnote, design: .rounded))
                        .opacity(engine.moves == 0 ? 0.6 : 0)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(!(engine.moves == 0))
                    Spacer(minLength: 4).frame(maxHeight: 16)
                }
                .animation(.easeOut(duration: 0.3), value: engine.moves == 0)
            }
        }
        .id(engine.level)
    }

    /// Level picker, moves, and the one extra tube.
    private var statusBar: some View {
        let palette = ToyWaterSort.palette
        return HStack(spacing: 10) {
            Menu {
                ForEach(1...WaterSortEngine.levelCount, id: \.self) { level in
                    Button(L10n.format("Level %d", level)) { engine.selectLevel(level) }
                }
            } label: {
                ToyChip(color: palette.card) {
                    Label(L10n.format("Level %d", engine.level), systemImage: "flask.fill")
                }
            }
            .buttonStyle(.plain)
            ToyChip(color: palette.card) {
                Label(L10n.format("%d moves", engine.moves), systemImage: "arrow.left.arrow.right")
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Button {
                engine.addTube()
            } label: {
                Image(systemName: "plus")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(engine.extraTubeUsed ? palette.ink.opacity(0.4) : palette.accent)
                    .frame(width: 44, height: 34)
                    .contentShape(Capsule())
            }
            .buttonStyle(ToyPressStyle(color: palette.card, lip: 3))
            .disabled(engine.extraTubeUsed)
            .accessibilityLabel(L10n.text("Extra tube"))
        }
        .foregroundStyle(palette.ink)
    }

    private var tubesGrid: some View {
        let tubeCount = engine.tubes.count
        let perRow = (tubeCount + 1) / 2
        // Tubes narrow as the level adds colours, so two rows always fit.
        let width = min(58, (340 - 10 * CGFloat(perRow - 1)) / CGFloat(perRow))
        return TimelineView(.animation(paused: pours.isEmpty)) { timeline in
            let date = timeline.date
            VStack(spacing: 44) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: perRow > 5 ? 10 : 18) {
                        ForEach(0..<perRow, id: \.self) { col in
                            let index = row * perRow + col
                            if index < tubeCount {
                                tube(at: index, width: width, date: date)
                            }
                        }
                    }
                    // A clay shelf the tubes stand in.
                    .background(alignment: .bottom) {
                        ToyBlock(color: ToyWaterSort.palette.tray,
                                 shape: RoundedRectangle(cornerRadius: 12, style: .continuous), lip: 6)
                            .frame(height: 30)
                            .padding(.horizontal, -18)
                            .offset(y: 20)
                    }
                }
            }
            .coordinateSpace(name: Self.space)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { boardOrigin = $0 }
            .onPreferenceChange(TubeFramesKey.self) { tubeFrames = $0 }
            .overlay {
                if !pours.isEmpty { pourLayer(width: width, date: date) }
            }
        }
        .onChange(of: engine.lastPour) { _, new in
            guard let new else { pours = []; return }
            startPour(new, width: width)
        }
    }

    // MARK: Pour scheduling

    /// Where the lip of a tube pouring into `to` rests.
    private static func mouthPoint(to: CGRect, dir: CGFloat, width: CGFloat) -> CGPoint {
        CGPoint(x: to.midX - dir * width * 0.28, y: to.minY - 10)
    }

    /// The centre of a tube tipped by `angle` with its lip at `mouth`.
    private static func pivot(_ angle: Double, mouth: CGPoint, dir: CGFloat, width: CGFloat) -> CGPoint {
        let r = TubeGeometry.rotate(CGPoint(x: dir * width / 2, y: -tubeHeight / 2), by: angle)
        return CGPoint(x: mouth.x - r.x, y: mouth.y - r.y)
    }

    /// Which way a tube tips to pour into its target: its body lies on the
    /// outer side, unless it would hang off the screen there.
    private func side(for pour: WaterSortEngine.Pour, width: CGFloat) -> CGFloat {
        guard let from = tubeFrames[pour.from], let to = tubeFrames[pour.to] else { return 1 }
        let frames = tubeFrames.values
        let boardMid = ((frames.map(\.minX).min() ?? 0) + (frames.map(\.maxX).max() ?? 0)) / 2
        let screen = (min: -boardOrigin + 4, max: boardMid * 2 + boardOrigin - 4)
        func fits(_ dir: CGFloat) -> Bool {
            // Lying flat is as far out as the glass reaches.
            let angle = Double(dir) * .pi / 2
            let c = Self.pivot(angle, mouth: Self.mouthPoint(to: to, dir: dir, width: width), dir: dir, width: width)
            let x = c.x + TubeGeometry.rotate(CGPoint(x: 0, y: Self.tubeHeight / 2), by: angle).x
            return x - width / 2 >= screen.min && x + width / 2 <= screen.max
        }
        var dir: CGFloat = abs(to.midX - boardMid) < 1 ? (to.midX >= from.midX ? 1 : -1) : (to.midX < boardMid ? 1 : -1)
        if !fits(dir) { dir = -dir }
        return dir
    }

    /// The stretch of the board a tipped tube covers, side to side.
    private func sweep(_ pour: WaterSortEngine.Pour, dir: CGFloat, width: CGFloat) -> ClosedRange<CGFloat> {
        guard let to = tubeFrames[pour.to] else { return 0...0 }
        let mouth = Self.mouthPoint(to: to, dir: dir, width: width).x
        let far = mouth - dir * (Self.tubeHeight + width / 2)
        return (min(mouth, far) - 4)...(max(mouth, far) + 4)
    }

    private func startPour(_ pour: WaterSortEngine.Pour, width: CGFloat) {
        var dir = side(for: pour, width: width)
        // A second tube pouring into the same one comes in from the other side.
        if let other = pours.last(where: { $0.pour.to == pour.to }), other.dir == dir { dir = -dir }
        // A tube that would swing through one still pouring waits, lifted,
        // until that one tips back.
        var start = Date.now
        let span = sweep(pour, dir: dir, width: width)
        for other in pours.sorted(by: { $0.start < $1.start })
        where span.overlaps(sweep(other.pour, dir: other.dir, width: width)) {
            let clear = other.start.addingTimeInterval(WaterSortEngine.pourDuration * PourPhase.flowEnd + 0.05)
            start = max(start, clear)
        }
        let active = ActivePour(pour: pour, start: start, dir: dir)
        pours.append(active)
        Task { await run(active) }
    }

    private func isRunning(_ active: ActivePour) -> Bool { pours.contains { $0.pour == active.pour } }

    /// The pour's sounds and feel, in step with the picture: a soft bump when
    /// the stream meets the liquid, bubbles rising in pitch as the tube
    /// fills, a chime when it's one colour to the brim. The round ends once
    /// the last pour is done.
    private func run(_ active: ActivePour) async {
        let duration = WaterSortEngine.pourDuration
        let landing = active.start.addingTimeInterval(duration * PourPhase.reachEnd + 0.09)
        try? await Task.sleep(for: .seconds(max(0, landing.timeIntervalSinceNow)))
        guard isRunning(active) else { return }
        Haptics.soft()
        let to = active.pour.to, amount = active.pour.amount
        let before = max(0, (engine.tubes.indices.contains(to) ? engine.tubes[to].count : amount) - amount)
        let bubbles = 2 + amount
        let flow = duration * (PourPhase.flowEnd - PourPhase.reachEnd)
        for i in 0..<bubbles {
            guard isRunning(active) else { return }
            SoundFX.play(.bubble(before + amount * i / bubbles))
            try? await Task.sleep(for: .seconds(flow / Double(bubbles)))
        }
        guard isRunning(active) else { return }
        let laterInto = pours.contains { $0.pour.to == to && $0.start > active.start }
        if engine.isComplete(to), !laterInto {
            Haptics.success(); SoundFX.play(.clear)
        }
        let end = active.start.addingTimeInterval(duration)
        try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
        guard isRunning(active) else { return }
        pours.removeAll { $0.pour == active.pour }
        if pours.isEmpty { engine.settle() }
    }

    // MARK: Tubes

    private static let space = "waterSort"
    private static let tubeHeight: CGFloat = 150
    /// Empty glass above a full tube, so it reads as a vessel and not a block.
    private static let headroom: CGFloat = 18
    /// Height of one unit of liquid.
    private static var unit: CGFloat { (tubeHeight - headroom - 4) / CGFloat(WaterSortEngine.capacity) }

    /// Clear glass: milky on the light table, a faint sheen on the dark one.
    private static let glassTint = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 1, alpha: 0.09) : UIColor(white: 1, alpha: 0.55) })
    private static let lipTint = Color.dynamic(light: (1.0, 0.99, 0.99), dark: (0.42, 0.33, 0.34))

    /// The glass: square-ish mouth, round bottom.
    private static func glass(_ width: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: width / 2,
                               bottomTrailingRadius: width / 2, topTrailingRadius: 6)
    }

    /// Liquid layers bottom to top, same colours merged, with pours in
    /// progress added back to their source or held back from their target.
    private func layers(_ index: Int, at date: Date) -> [(color: Int, amount: Double)] {
        var units = engine.tubes[index].map { (color: $0, amount: 1.0) }
        let incoming = pours.filter { $0.pour.to == index }
        let pending = incoming.reduce(0) { $0 + $1.pour.amount }
        if pending > 0, let color = incoming.first?.pour.color {
            units.removeLast(min(units.count, pending))
            let landed = incoming.reduce(0.0) {
                $0 + Double($1.pour.amount) * PourPhase($1, at: date).transferred
            }
            units.append((color, landed))
        }
        if let out = pours.first(where: { $0.pour.from == index }) {
            units.append((out.pour.color, Double(out.pour.amount) * (1 - PourPhase(out, at: date).transferred)))
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

    /// How far the surface of a tube being poured into bobs, in points: it
    /// churns while the stream lands and settles once it stops.
    private func slosh(_ index: Int, at date: Date) -> CGFloat {
        var total = 0.0
        for active in pours where active.pour.to == index {
            let phase = PourPhase(active, at: date)
            let s = phase.elapsed
            if phase.flow > 0.12 && phase.flow < 1 {
                total += 1.6 * sin(s * 38)
            } else if phase.flow >= 1 {
                let settle = s - WaterSortEngine.pourDuration * PourPhase.flowEnd
                total += 2.4 * exp(-settle * 9) * sin(settle * 32)
            }
        }
        return CGFloat(total)
    }

    private func liquid(_ index: Int, width: CGFloat, date: Date) -> some View {
        let unit = Self.unit
        let layers = self.layers(index, at: date)
        let slosh = self.slosh(index, at: date)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(layers.enumerated().reversed()), id: \.offset) { i, layer in
                let color = Self.palette[layer.color]
                Rectangle()
                    .fill(color)
                    .overlay(alignment: .top) {
                        // The top layer's surface: a lighter meniscus that bobs while filling.
                        if i == layers.count - 1 {
                            Ellipse().fill(color).brightness(0.18)
                                .frame(height: 6 + abs(slosh) * 1.5)
                                .offset(y: -3 - slosh)
                        }
                    }
                    .frame(height: unit * layer.amount)
            }
        }
        .frame(width: width - 8, height: Self.tubeHeight - 4)
        // Shaded like a cylinder: darker at the walls, a highlight left of centre.
        .overlay {
            LinearGradient(stops: [.init(color: .black.opacity(0.22), location: 0),
                                   .init(color: .white.opacity(0.18), location: 0.3),
                                   .init(color: .clear, location: 0.55),
                                   .init(color: .black.opacity(0.25), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .blendMode(.overlay)
        }
        .clipShape(Self.glass(width - 8))
    }

    private func vessel(_ index: Int, width: CGFloat, date: Date, selected: Bool) -> some View {
        liquid(index, width: width, date: date)
            .frame(width: width, height: Self.tubeHeight)
            .background(Self.glassTint, in: Self.glass(width))
            .overlay {
                Self.glass(width)
                    .strokeBorder(selected ? GameTheme.accent : Color.primary.opacity(0.2), lineWidth: selected ? 2 : 1.5)
            }
            .overlay(alignment: .top) {
                // The lip at the mouth, a little wider than the tube.
                Capsule()
                    .fill(Self.lipTint)
                    .overlay { Capsule().strokeBorder(selected ? GameTheme.accent : Color.primary.opacity(0.2),
                                                      lineWidth: selected ? 2 : 1.5) }
                    .frame(width: width + 6, height: 7)
                    .offset(y: -3)
            }
            .overlay(alignment: .leading) {
                // A glint down the glass.
                Capsule().fill(.white.opacity(0.45)).frame(width: 3, height: Self.tubeHeight * 0.55)
                    .padding(.leading, 7).offset(y: 6)
            }
    }

    private func tube(at index: Int, width: CGFloat, date: Date) -> some View {
        let isSelected = engine.selected == index
        let away = pours.contains { $0.pour.from == index }
        let receiving = pours.contains { $0.pour.to == index }
        return vessel(index, width: width, date: date, selected: isSelected)
            .background {
                GeometryReader { geo in
                    Color.clear.preference(key: TubeFramesKey.self, value: [index: geo.frame(in: .named(Self.space))])
                }
            }
            // The pouring tube is drawn by `pourLayer` while it's away.
            .opacity(away ? 0 : 1)
            .offset(y: isSelected ? -14 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: isSelected)
            .contentShape(Rectangle())
            .onTapGesture {
                // Pours run on their own; the next move can start at once.
                guard !away else { return }
                engine.tap(index, pickable: !receiving)
            }
    }

    // MARK: Pouring

    /// Every tube in flight, its stream and the splash where it lands, drawn
    /// in the board's space. The liquid inside a tipped tube keeps a level
    /// surface, and the tube tips just far enough for that surface to reach
    /// the lip, more and more as it empties.
    private func pourLayer(width: CGFloat, date: Date) -> some View {
        let margin: CGFloat = 220
        return Canvas { context, _ in
            context.translateBy(x: margin, y: margin)
            let geometry = TubeGeometry(width: width, height: Self.tubeHeight, unit: Self.unit)
            for active in pours {
                guard let from = tubeFrames[active.pour.from], let to = tubeFrames[active.pour.to] else { continue }
                drawPour(active, from: from, to: to, geometry: geometry, date: date, in: context)
            }
        }
        .padding(-margin)
        .allowsHitTesting(false)
    }

    private func drawPour(_ active: ActivePour, from: CGRect, to: CGRect, geometry g: TubeGeometry,
                          date: Date, in context: GraphicsContext) {
        let phase = PourPhase(active, at: date)
        let width = g.width
        let dir = active.dir
        let color = Self.palette[active.pour.color]
        let mouth = Self.mouthPoint(to: to, dir: dir, width: width)
        func pivotCenter(_ angle: Double) -> CGPoint { Self.pivot(angle, mouth: mouth, dir: dir, width: width) }

        let layers = self.layers(active.pour.from, at: date)
        let remaining = layers.reduce(0) { $0 + $1.amount }
        let initial = remaining + Double(active.pour.amount) * phase.transferred
        let startAngle = g.pourAngle(area: g.uprightArea(units: initial), dir: dir)
        let endAngle = g.pourAngle(area: g.uprightArea(units: initial - Double(active.pour.amount)), dir: dir)

        let angle: Double
        let center: CGPoint
        switch phase.stage {
        case .reach(let e):
            angle = startAngle * e
            let home = CGPoint(x: from.midX, y: from.midY - 14)
            center = home.lerp(to: pivotCenter(startAngle), e)
        case .flow:
            angle = g.pourAngle(area: g.uprightArea(units: remaining), dir: dir)
            center = pivotCenter(angle)
        case .back(let e):
            angle = endAngle * (1 - e)
            center = pivotCenter(endAngle).lerp(to: CGPoint(x: from.midX, y: from.midY), e)
        }

        // The stream: it leaves the lip, curls out a little and falls; when
        // the pour ends it thins and its tail drops after the head.
        let targetUnits = self.layers(active.pour.to, at: date).reduce(0) { $0 + $1.amount }
        let surface = to.maxY - 2 - Self.unit * CGFloat(targetUnits)
        let head = phase.flow > 0 ? mouth.y + PourPhase.fall(phase.sinceFlow) : mouth.y
        let tail = phase.flow >= 1 ? mouth.y + PourPhase.fall(phase.sinceFlowEnd) : mouth.y
        let bottom = min(head, surface)
        let landX = mouth.x + dir * width * 0.16
        if phase.flow > 0, bottom > tail + 1 {
            var stream = Path()
            var y = tail
            stream.move(to: CGPoint(x: mouth.x + dir * width * 0.16 * (1 - exp(-(y - mouth.y) / 10)), y: y))
            while y < bottom {
                y = min(bottom, y + 4)
                stream.addLine(to: CGPoint(x: mouth.x + dir * width * 0.16 * (1 - exp(-(y - mouth.y) / 10)), y: y))
            }
            let thickness = max(2.5, min(9, width * 0.2) * (0.35 + 0.65 * min(1, phase.rate)))
            context.stroke(stream, with: .color(color),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
            context.stroke(stream, with: .color(.white.opacity(0.25)),
                           style: StrokeStyle(lineWidth: max(1, thickness * 0.25), lineCap: .round))
        }

        // Splash: droplets kicked up where the stream lands, and a ring.
        let landing = head >= surface && tail < surface
        let afterLanding = phase.flow >= 1 && tail >= surface && phase.sinceFlowEnd < 0.35
        if landing || afterLanding {
            let fade = afterLanding ? max(0, 1 - phase.sinceFlowEnd / 0.2) : 1
            let kicks: [(CGFloat, CGFloat)] = [(-34, -95), (26, -120), (-14, -80), (38, -105), (-4, -135)]
            for (i, kick) in kicks.enumerated() {
                let period = 0.24
                let local = (phase.elapsed + Double(i) * period / Double(kicks.count))
                    .truncatingRemainder(dividingBy: period)
                let u = CGFloat(local)
                let p = CGPoint(x: landX + kick.0 * u, y: surface + kick.1 * u + 0.5 * 1400 * u * u)
                guard p.y <= surface else { continue }
                let r = 2.6 * (1 - u / CGFloat(period)) + 0.8
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(color.opacity(fade)))
            }
            let ring = (width - 12) * (0.55 + 0.45 * abs(sin(phase.elapsed * 30)))
            context.stroke(Path(ellipseIn: CGRect(x: to.midX - ring / 2, y: surface - 2.5, width: ring, height: 5)),
                           with: .color(.white.opacity(0.55 * fade)), lineWidth: 1.2)
        }

        // The tube itself, drawn in its own rotated frame.
        var tube = context
        tube.translateBy(x: center.x, y: center.y)
        tube.rotate(by: .radians(angle))
        let outer = CGRect(x: -width / 2, y: -Self.tubeHeight / 2, width: width, height: Self.tubeHeight)
        let innerRect = outer.insetBy(dx: 4, dy: 2)
        let glassPath = Self.glass(width).path(in: outer)
        let innerPath = Self.glass(width - 8).path(in: innerRect)
        tube.fill(glassPath, with: .color(Self.glassTint))

        // Liquid: each layer fills the glass up to a level line, top layer first.
        let down = CGVector(dx: sin(angle), dy: cos(angle))
        var cumulative = layers.reduce(0) { $0 + $1.amount }
        for (i, layer) in layers.enumerated().reversed() {
            let level = g.level(area: g.uprightArea(units: cumulative), down: down)
            let cut = TubeGeometry.clip(g.inner, down: down, level: level)
            if cut.polygon.count > 2 {
                tube.fill(Path { $0.addLines(cut.polygon); $0.closeSubpath() }, with: .color(Self.palette[layer.color]))
                if i == layers.count - 1, cut.chord.count == 2 {
                    // The surface: a bright line that stays level as the glass turns.
                    tube.stroke(Path { $0.addLines(cut.chord) }, with: .color(.white.opacity(0.4)), lineWidth: 2.5)
                }
            }
            cumulative -= layer.amount
        }
        tube.drawLayer { shade in
            shade.clip(to: innerPath)
            shade.fill(Path(innerRect), with: .linearGradient(
                Gradient(stops: [.init(color: .black.opacity(0.12), location: 0),
                                 .init(color: .white.opacity(0.14), location: 0.3),
                                 .init(color: .clear, location: 0.55),
                                 .init(color: .black.opacity(0.14), location: 1)]),
                startPoint: CGPoint(x: innerRect.minX, y: 0), endPoint: CGPoint(x: innerRect.maxX, y: 0)))
        }
        tube.stroke(glassPath, with: .color(.primary.opacity(0.2)), lineWidth: 1.5)
        let lipRect = CGRect(x: -width / 2 - 3, y: -Self.tubeHeight / 2 - 3, width: width + 6, height: 7)
        tube.fill(Capsule().path(in: lipRect), with: .color(Self.lipTint))
        tube.stroke(Capsule().path(in: lipRect.insetBy(dx: 0.75, dy: 0.75)), with: .color(.primary.opacity(0.2)), lineWidth: 1.5)
        let glint = CGRect(x: -width / 2 + 7, y: -Self.tubeHeight * 0.275 + 6, width: 3, height: Self.tubeHeight * 0.55)
        tube.fill(Capsule().path(in: glint), with: .color(.white.opacity(0.45)))
    }
}

/// One pour being animated.
private struct ActivePour {
    let pour: WaterSortEngine.Pour
    let start: Date
    /// 1 when the tube tips to the right (its body to the left of the lip), -1 to the left.
    let dir: CGFloat
}

/// Where a pour is: reach and tip (0…0.25), flow (0.25…0.75), return (0.75…1)
/// of `pourDuration`.
private struct PourPhase {
    static let reachEnd = 0.25
    static let flowEnd = 0.75

    enum Stage { case reach(Double), flow, back(Double) }

    /// Seconds since the pour began.
    let elapsed: Double
    let t: Double

    init(_ active: ActivePour, at date: Date) {
        elapsed = max(0, date.timeIntervalSince(active.start))
        t = min(1, elapsed / WaterSortEngine.pourDuration)
    }

    static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// How far the liquid has run, 0…1.
    var flow: Double { min(1, max(0, (t - Self.reachEnd) / (Self.flowEnd - Self.reachEnd))) }
    /// How much of the run has left the source (0…1).
    var transferred: Double { Self.ease(flow) }
    /// The flow rate, 1 at its peak.
    var rate: Double { flow > 0 && flow < 1 ? 4 * flow * (1 - flow) : 0 }
    var sinceFlow: Double { max(0, elapsed - Self.reachEnd * WaterSortEngine.pourDuration) }
    var sinceFlowEnd: Double { max(0, elapsed - Self.flowEnd * WaterSortEngine.pourDuration) }

    var stage: Stage {
        if t < Self.reachEnd { return .reach(Self.ease(t / Self.reachEnd)) }
        if t < Self.flowEnd { return .flow }
        return .back(Self.ease((t - Self.flowEnd) / (1 - Self.flowEnd)))
    }

    /// How far liquid has fallen after `seconds`, in points.
    static func fall(_ seconds: Double) -> CGFloat {
        CGFloat(260 * seconds + 0.5 * 4200 * seconds * seconds)
    }
}

/// The inside of a tube as a polygon, centred on the tube, so a tipped tube
/// can be filled to a level line holding the same amount as upright.
private struct TubeGeometry {
    let width: CGFloat
    let height: CGFloat
    let unit: CGFloat
    let inner: [CGPoint]

    init(width: CGFloat, height: CGFloat, unit: CGFloat) {
        self.width = width
        self.height = height
        self.unit = unit
        let w = width - 8, h = height - 4, r = w / 2, cy = h / 2 - r
        var points = [CGPoint(x: -w / 2, y: -h / 2), CGPoint(x: w / 2, y: -h / 2)]
        for i in 0...16 {
            let a = Double(i) / 16 * .pi
            points.append(CGPoint(x: r * cos(a), y: cy + r * sin(a)))
        }
        inner = points
    }

    /// Rotates clockwise on screen (y points down), like `rotationEffect`.
    static func rotate(_ p: CGPoint, by angle: Double) -> CGPoint {
        CGPoint(x: p.x * cos(angle) - p.y * sin(angle), y: p.x * sin(angle) + p.y * cos(angle))
    }

    /// The part of `polygon` on the far side of the line `down · p = level`
    /// (below it on screen), and where the line crosses the polygon.
    static func clip(_ polygon: [CGPoint], down: CGVector, level: CGFloat) -> (polygon: [CGPoint], chord: [CGPoint]) {
        var out: [CGPoint] = [], chord: [CGPoint] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let da = a.x * down.dx + a.y * down.dy - level
            let db = b.x * down.dx + b.y * down.dy - level
            if da >= 0 { out.append(a) }
            if (da >= 0) != (db >= 0) {
                let t = da / (da - db)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                out.append(p); chord.append(p)
            }
        }
        return (out, chord)
    }

    static func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    func area(below level: CGFloat, down: CGVector) -> CGFloat {
        Self.area(Self.clip(inner, down: down, level: level).polygon)
    }

    /// The area `units` of liquid cover in the upright tube.
    func uprightArea(units: Double) -> CGFloat {
        area(below: (height - 4) / 2 - unit * CGFloat(units), down: CGVector(dx: 0, dy: 1))
    }

    /// The level line that holds `area` in a tube tipped so `down` points down.
    func level(area target: CGFloat, down: CGVector) -> CGFloat {
        let dots = inner.map { $0.x * down.dx + $0.y * down.dy }
        var lo = dots.min() ?? 0, hi = dots.max() ?? 0
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            if area(below: mid, down: down) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// How far to tip (signed, radians) so `area` of liquid just reaches the lip.
    func pourAngle(area target: CGFloat, dir: CGFloat) -> Double {
        let corner = CGPoint(x: dir * (width - 8) / 2, y: -(height - 4) / 2)
        var lo = 0.0, hi = 2.1
        for _ in 0..<22 {
            let mid = (lo + hi) / 2
            let angle = Double(dir) * mid
            let down = CGVector(dx: sin(angle), dy: cos(angle))
            let level = corner.x * down.dx + corner.y * down.dy
            if area(below: level, down: down) > target { lo = mid } else { hi = mid }
        }
        return Double(dir) * (lo + hi) / 2
    }
}

private extension CGPoint {
    func lerp(to other: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: x + (other.x - x) * t, y: y + (other.y - y) * t)
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


/// The blush toy world of Water Sort: glass tubes on a soft pink table.
enum ToyWaterSort {
    static let palette = ToyPalette(
        backdropTop: .dynamic(light: (1.0, 0.95, 0.94), dark: (0.18, 0.11, 0.12)),
        backdropBottom: .dynamic(light: (0.97, 0.86, 0.86), dark: (0.10, 0.06, 0.07)),
        tray: .dynamic(light: (0.90, 0.72, 0.72), dark: (0.40, 0.26, 0.27)),
        socket: .dynamic(light: (0.84, 0.64, 0.65), dark: (0.30, 0.19, 0.20)),
        ink: .dynamic(light: (0.44, 0.22, 0.25), dark: (0.99, 0.92, 0.92)),
        deboss: .dynamic(light: (0.95, 0.82, 0.82), dark: (0.47, 0.31, 0.32)),
        debossRim: .dynamic(light: (1.0, 1.0, 1.0), dark: (0.07, 0.04, 0.04)),
        card: .dynamic(light: (1.0, 0.98, 0.98), dark: (0.26, 0.18, 0.19)),
        accent: .dynamic(light: (0.90, 0.45, 0.50), dark: (0.98, 0.56, 0.60)))
}
