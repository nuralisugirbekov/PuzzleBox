import SwiftUI

/// The Arrow Escape board in a viewport the player can pinch to zoom and
/// drag to pan. Small boards fit at a glance; the big late-game boards open
/// zoomed in to a readable size, and zooming out shows the whole board.
struct ArrowEscapeBoard: View {
    let engine: ArrowEscapePuzzleEngine
    let reduceMotion: Bool

    /// 1 shows the whole board; more zooms in.
    @State private var zoom: CGFloat?
    /// The board point (in cells) shown at the middle of the viewport.
    @State private var focus: CGPoint?
    @State private var pinchStart: (zoom: CGFloat, anchor: CGPoint, location: CGPoint)?
    @State private var panStart: CGPoint?

    /// Cells are never drawn bigger than this, however far the player zooms.
    private static let largestCell: CGFloat = 56
    /// A board opens zoomed in until its cells are at least this big.
    private static let readableCell: CGFloat = 26

    private var columns: CGFloat { CGFloat(engine.puzzle.columns) }
    private var rows: CGFloat { CGFloat(engine.puzzle.rows) }

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size
            let fit = fitCell(viewport)
            let maxZoom = max(1, Self.largestCell / fit)
            let zoom = self.zoom ?? min(maxZoom, max(1, Self.readableCell / fit))
            let cell = fit * zoom
            let focus = clamped(self.focus ?? CGPoint(x: columns / 2, y: rows / 2))
            let origin = CGPoint(x: viewport.width / 2 - focus.x * cell, y: viewport.height / 2 - focus.y * cell)
            // Read here so the canvas redraws whenever an arrow moves.
            let remaining = engine.remaining, moving = engine.moving, missed = engine.missed

            Canvas { context, _ in
                draw(&context, origin: origin, cell: cell, remaining: remaining, moving: moving, missed: missed)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                engine.tap(EscapeCell(x: Int(floor((location.x - origin.x) / cell)),
                                      y: Int(floor((location.y - origin.y) / cell))))
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? (zoom, CGPoint(x: (value.startLocation.x - origin.x) / cell,
                                                                 y: (value.startLocation.y - origin.y) / cell),
                                                   value.startLocation)
                        pinchStart = start
                        let newZoom = min(maxZoom, max(1, start.zoom * value.magnification))
                        let newCell = fit * newZoom
                        // Keep the board point under the fingers where it was.
                        self.zoom = newZoom
                        self.focus = CGPoint(x: start.anchor.x + (viewport.width / 2 - start.location.x) / newCell,
                                             y: start.anchor.y + (viewport.height / 2 - start.location.y) / newCell)
                    }
                    .onEnded { _ in
                        pinchStart = nil
                        self.focus = clamped(self.focus ?? focus)
                    }
                    .simultaneously(with:
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard pinchStart == nil else { return }
                                let start = panStart ?? focus
                                panStart = start
                                self.focus = CGPoint(x: start.x - value.translation.width / cell,
                                                     y: start.y - value.translation.height / cell)
                            }
                            .onEnded { _ in
                                panStart = nil
                                self.focus = clamped(self.focus ?? focus)
                            })
            )
            .overlay(alignment: .bottomTrailing) {
                if maxZoom > 1.01 {
                    zoomButtons(current: zoom, maxZoom: maxZoom)
                }
            }
            .clipped()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("Arrow Escape"))
    }

    // MARK: Zoom

    private func fitCell(_ viewport: CGSize) -> CGFloat {
        max(1, min(viewport.width / columns, viewport.height / rows))
    }

    /// Keeps some of the board on screen while letting the player pan past
    /// its edges: any board point, edges and corners included, can be brought
    /// to the middle of the viewport, so the edges zoom like the centre does.
    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), columns), y: min(max(point.y, 0), rows))
    }

    private func zoomButtons(current: CGFloat, maxZoom: CGFloat) -> some View {
        VStack(spacing: 8) {
            zoomButton("plus.magnifyingglass", label: "Zoom in", enabled: current < maxZoom - 0.01) {
                zoom = min(maxZoom, current * 1.6)
            }
            zoomButton("minus.magnifyingglass", label: "Zoom out", enabled: current > 1.01) {
                zoom = max(1, current / 1.6)
            }
        }
        .padding(8)
        // The board runs under the home indicator; keep the buttons above it.
        .padding(.bottom, 24)
    }

    private func zoomButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.snappy(duration: 0.25)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? GameTheme.accent : GameTheme.textSecondary)
        .disabled(!enabled)
        .accessibilityLabel(L10n.text(label))
    }

    // MARK: Drawing

    /// Flight distance in points after `t` seconds: a quick start that keeps
    /// accelerating, so even a long arrow clears the screen within
    /// `ArrowEscapePuzzleEngine.flightDuration`.
    private static func flightDistance(_ t: Double) -> CGFloat {
        CGFloat(450 * t + 900 * t * t)
    }

    private func draw(_ context: inout GraphicsContext, origin: CGPoint, cell: CGFloat,
                      remaining: Set<Int>, moving: [Int: Double], missed: Set<Int>) {
        // The board's outline, so heart, house and flower boards read as such.
        var tiles = Path()
        for p in engine.puzzle.playable {
            tiles.addRoundedRect(in: CGRect(x: origin.x + CGFloat(p.x) * cell + 1, y: origin.y + CGFloat(p.y) * cell + 1,
                                            width: cell - 2, height: cell - 2),
                                 cornerSize: CGSize(width: cell * 0.2, height: cell * 0.2))
        }
        context.fill(tiles, with: .color(GameTheme.accent.opacity(0.07)))

        let palette: [Color] = [.primary, .blue, .indigo, .teal]
        let lineWidth = max(2.5, cell * 0.22)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        for arrow in engine.puzzle.arrows where remaining.contains(arrow.id) {
            let elapsed = moving[arrow.id]
            let travel = elapsed.map { reduceMotion ? 0 : Self.flightDistance($0) / cell } ?? 0
            let color = missed.contains(arrow.id) ? Color.red : palette[arrow.id % palette.count]
            var layer = context
            if reduceMotion, let elapsed {
                layer.opacity = max(0, 1 - elapsed / ArrowEscapePuzzleEngine.reducedMotionDuration)
            }
            layer.stroke(arrowShape(arrow, travel: travel, origin: origin, cell: cell), with: .color(color), style: style)
        }
    }

    /// Body and tip of one arrow, `travel` cells along its exit route.
    private func arrowShape(_ arrow: EscapeArrow, travel: CGFloat, origin: CGPoint, cell: CGFloat) -> Path {
        let points = visiblePoints(for: arrow, travel: travel, cell: cell)
            .map { CGPoint(x: origin.x + $0.x * cell, y: origin.y + $0.y * cell) }
        var path = Path()
        guard let first = points.first, let head = points.last else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        let dx = CGFloat(arrow.direction.dx), dy = CGFloat(arrow.direction.dy)
        let size = cell * 0.34
        path.move(to: CGPoint(x: head.x - dx * size - dy * size * 0.7,
                              y: head.y - dy * size + dx * size * 0.7))
        path.addLine(to: head)
        path.addLine(to: CGPoint(x: head.x - dx * size + dy * size * 0.7,
                                 y: head.y - dy * size - dx * size * 0.7))
        return path
    }

    /// The tail follows the original winding path while the head extends along
    /// its exit ray, in cell units. Translating the entire bent shape would
    /// cross other arrows.
    private func visiblePoints(for arrow: EscapeArrow, travel: CGFloat, cell: CGFloat) -> [CGPoint] {
        var points = arrow.cells.map { CGPoint(x: CGFloat($0.x) + 0.5, y: CGFloat($0.y) + 0.5) }
        let dx = CGFloat(arrow.direction.dx), dy = CGFloat(arrow.direction.dy)
        if points.count == 1 {
            points.insert(CGPoint(x: points[0].x - dx * 0.6, y: points[0].y - dy * 0.6), at: 0)
        }
        let length = arrow.cells.count == 1 ? CGFloat(0.6) : CGFloat(arrow.cells.count - 1)
        let head = points[points.count - 1]
        // Long enough that the whole arrow can travel past any edge of the viewport.
        let extensionLength = length + Self.flightDistance(ArrowEscapePuzzleEngine.flightDuration) / cell
            + max(columns, rows)
        points.append(CGPoint(x: head.x + dx * extensionLength, y: head.y + dy * extensionLength))
        let start = travel
        let end = start + length
        var distance: CGFloat = 0
        var result: [CGPoint] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = hypot(b.x - a.x, b.y - a.y)
            let low = max(start, distance), high = min(end, distance + segment)
            if high >= low, segment > 0 {
                for value in [low, high] {
                    let t = (value - distance) / segment
                    result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                }
            }
            distance += segment
        }
        return result
    }
}
