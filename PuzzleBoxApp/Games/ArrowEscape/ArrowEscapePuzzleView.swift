import SwiftUI

struct ArrowEscapePuzzleView: View {
    @State private var engine = ArrowEscapePuzzleEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GameContainerView(gameID: .arrowEscape, engine: engine, centersContent: true,
                          nextLevel: engine.hasNextLevel ? { engine.nextLevel() } : nil) {
            VStack(spacing: 12) {
                HStack {
                    Menu {
                        ForEach(0..<ArrowEscapePuzzle.levelCount, id: \.self) { index in
                            Button(L10n.format("Level %d", index + 1)) { engine.selectLevel(index) }
                        }
                    } label: {
                        Label(L10n.format("Level %d of %d", engine.levelIndex + 1, ArrowEscapePuzzle.levelCount), systemImage: "square.grid.3x3")
                    }
                    Spacer()
                    Text("\(engine.remaining.count)/\(engine.puzzle.arrows.count)")
                        .monospacedDigit()
                        .accessibilityLabel(L10n.format("Arrows remaining: %d", engine.remaining.count))
                }.font(.subheadline.weight(.semibold))
                GeometryReader { geometry in
                    let size = fittedCellSize(in: geometry.size)
                    board(cellSize: size)
                        .frame(width: CGFloat(engine.puzzle.columns) * size,
                               height: CGFloat(engine.puzzle.rows) * size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
                .background(GameTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<ArrowEscapePuzzleEngine.maxLives, id: \.self) { index in
                            Image(systemName: index < engine.lives ? "heart.fill" : "heart")
                                .foregroundStyle(index < engine.lives ? Color.red : GameTheme.textSecondary)
                                .symbolEffect(.bounce, value: engine.lives)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.format("Lives: %d", engine.lives))
                    Spacer()
                }
                Text(L10n.text(engine.blockedID == nil
                               ? "Tap an arrow with a clear path."
                               : "The path is blocked. Remove the arrow in front first."))
                    .font(.footnote).foregroundStyle(engine.blockedID == nil ? GameTheme.textSecondary : Color.red)
                    .multilineTextAlignment(.center).frame(minHeight: 36)
            }
            .layoutPriority(1)
        }
        .id(engine.levelIndex)
        .onAppear { engine.setActive(scenePhase == .active) }
        .onDisappear { engine.setActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setActive(phase == .active) }
        .task(id: engine.animationToken) {
            // Only keep a clock while an arrow is leaving. Cancellation on restart,
            // level change or dismissal cannot remove an arrow from a new board.
            // Step by real elapsed time: sleep overshoots, and a fixed 16 ms step stutters.
            let clock = ContinuousClock()
            var last = clock.now
            while engine.movingID != nil && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
                guard !Task.isCancelled else { return }
                let now = clock.now
                let elapsed = last.duration(to: now)
                last = now
                engine.advanceAnimation(Double(elapsed.components.attoseconds) / 1e18 + Double(elapsed.components.seconds),
                                        reduceMotion: reduceMotion)
            }
        }
    }

    /// Gentle start that speeds up as the arrow leaves; the end is off-board anyway.
    private static func easeIn(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t * t * (0.35 + 0.65 * t) + 0.35 * t * (1 - t) * (1 - t)
    }

    private func fittedCellSize(in size: CGSize) -> CGFloat {
        floor(min(size.width / CGFloat(engine.puzzle.columns),
                  size.height / CGFloat(engine.puzzle.rows)))
    }

    private func board(cellSize: CGFloat) -> some View {
        Canvas { context, _ in
            let palette: [Color] = [.primary, .blue, .indigo, .teal]
            for arrow in engine.puzzle.arrows where engine.remaining.contains(arrow.id) {
                let moving = engine.movingID == arrow.id
                let fraction = moving && !reduceMotion ? Self.easeIn(engine.progress) : 0
                let points = visiblePoints(for: arrow, progress: fraction, cellSize: cellSize)
                guard let head = points.last, let first = points.first else { continue }
                var path = Path()
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                let color = engine.blockedID == arrow.id ? Color.red : palette[arrow.id % palette.count]
                var layer = context
                if moving && reduceMotion { layer.opacity = 1 - engine.progress }
                layer.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(2.5, cellSize * 0.22), lineCap: .round, lineJoin: .round))
                let dx = CGFloat(arrow.direction.dx), dy = CGFloat(arrow.direction.dy)
                let size = cellSize * 0.34
                var tip = Path()
                tip.move(to: CGPoint(x: head.x - dx * size - dy * size * 0.7,
                                     y: head.y - dy * size + dx * size * 0.7))
                tip.addLine(to: head)
                tip.addLine(to: CGPoint(x: head.x - dx * size + dy * size * 0.7,
                                       y: head.y - dy * size - dx * size * 0.7))
                layer.stroke(tip, with: .color(color), style: StrokeStyle(lineWidth: max(2.5, cellSize * 0.22), lineCap: .round, lineJoin: .round))
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { location in
            engine.tap(EscapeCell(x: Int(floor(location.x / cellSize)), y: Int(floor(location.y / cellSize))))
        }
        .accessibilityLabel(L10n.text("Arrow Escape"))
    }

    /// The tail follows the original winding path while the head extends along
    /// its exit ray. Translating the entire bent shape would cross other arrows.
    private func visiblePoints(for arrow: EscapeArrow, progress: Double, cellSize: CGFloat) -> [CGPoint] {
        var points = arrow.cells.map { CGPoint(x: CGFloat($0.x) + 0.5, y: CGFloat($0.y) + 0.5) }
        let dx = CGFloat(arrow.direction.dx), dy = CGFloat(arrow.direction.dy)
        if points.count == 1 {
            points.insert(CGPoint(x: points[0].x - dx * 0.6, y: points[0].y - dy * 0.6), at: 0)
        }
        let length = arrow.cells.count == 1 ? CGFloat(0.6) : CGFloat(arrow.cells.count - 1)
        let head = points[points.count - 1]
        let extensionLength = CGFloat(max(engine.puzzle.columns, engine.puzzle.rows) + 2)
        points.append(CGPoint(x: head.x + dx * extensionLength, y: head.y + dy * extensionLength))
        let start = CGFloat(progress) * (length + extensionLength)
        let end = start + length
        var distance: CGFloat = 0
        var result: [CGPoint] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = hypot(b.x - a.x, b.y - a.y)
            let low = max(start, distance), high = min(end, distance + segment)
            if high >= low, segment > 0 {
                for value in [low, high] {
                    let t = (value - distance) / segment
                    result.append(CGPoint(x: (a.x + (b.x - a.x) * t) * cellSize,
                                          y: (a.y + (b.y - a.y) * t) * cellSize))
                }
            }
            distance += segment
        }
        return result
    }
}
