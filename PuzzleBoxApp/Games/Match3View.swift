import SwiftUI
import Observation

// MARK: - Engine

struct Gem: Identifiable, Equatable {
    let id = UUID()
    var kind: Int
}

@MainActor
@Observable
final class Match3Engine: GameEngine {
    static let size = 6
    static let kinds = 5
    static let totalMoves = 20

    private(set) var grid: [[Gem?]]
    private(set) var movesLeft = Match3Engine.totalMoves
    private(set) var score = 0
    var state: GameState = .playing
    var selected: GridPos?
    private var resolving = false

    init() {
        grid = Self.freshGrid()
    }

    func restart() {
        grid = Self.freshGrid()
        movesLeft = Self.totalMoves
        score = 0
        selected = nil
        resolving = false
        state = .playing
    }

    /// Fills the board with random gems, avoiding pre-made 3-in-a-rows.
    private static func freshGrid() -> [[Gem?]] {
        var g: [[Gem?]] = Array(repeating: Array(repeating: nil, count: size), count: size)
        for r in 0..<size {
            for c in 0..<size {
                var kind: Int
                repeat {
                    kind = Int.random(in: 0..<kinds)
                } while (c >= 2 && g[r][c - 1]?.kind == kind && g[r][c - 2]?.kind == kind)
                     || (r >= 2 && g[r - 1][c]?.kind == kind && g[r - 2][c]?.kind == kind)
                g[r][c] = Gem(kind: kind)
            }
        }
        return g
    }

    /// Swaps the gem at `pos` with its neighbor one cell away in the swipe direction.
    func swipe(from pos: GridPos, dr: Int, dc: Int) {
        guard state == .playing else { return }
        let target = GridPos(r: pos.r + dr, c: pos.c + dc)
        guard (0..<Self.size).contains(target.r), (0..<Self.size).contains(target.c) else { return }
        selected = nil
        attemptSwap(pos, target)
    }

    /// Tap-select fallback: tap a gem, then an adjacent one.
    func tap(_ pos: GridPos) {
        guard state == .playing else { return }
        guard let sel = selected else {
            selected = pos
            Haptics.tap()
            return
        }
        if sel == pos {
            selected = nil
            return
        }
        if abs(sel.r - pos.r) + abs(sel.c - pos.c) == 1 {
            selected = nil
            attemptSwap(sel, pos)
        } else {
            selected = pos
            Haptics.tap()
        }
    }

    private func swapGems(_ a: GridPos, _ b: GridPos) {
        let tmp = grid[a.r][a.c]
        grid[a.r][a.c] = grid[b.r][b.c]
        grid[b.r][b.c] = tmp
    }

    /// Non-blocking: the board never locks. The swap is validated against the
    /// current model immediately; animations play out while further input is
    /// accepted, so other pairs can be swapped mid-cascade.
    private func attemptSwap(_ a: GridPos, _ b: GridPos) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { swapGems(a, b) }

        let matched = findMatches()
        if matched.contains(a) || matched.contains(b) {
            Haptics.move()
            movesLeft -= 1
            // Let the swap slide finish before the break pops.
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                startResolver()
            }
        } else {
            // Not a valid move — slide back once the out-animation lands.
            Haptics.error()
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { swapGems(a, b) }
            }
        }
    }

    /// Only one resolver loop runs at a time; matches created by additional
    /// swaps while it is running are picked up on its next iteration.
    private func startResolver() {
        guard !resolving else { return }
        resolving = true
        Task { await resolveCascades() }
    }

    private func resolveCascades() async {
        var matched = findMatches()
        while !matched.isEmpty {
            score += matched.count * 10
            Haptics.success()
            withAnimation(.easeIn(duration: 0.22)) {
                for p in matched { grid[p.r][p.c] = nil }
            }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                collapseAndRefill()
            }
            try? await Task.sleep(for: .milliseconds(420))
            matched = findMatches()
        }
        resolving = false
        if movesLeft <= 0, state == .playing {
            state = .gameOver(won: false)
        }
    }

    private func findMatches() -> Set<GridPos> {
        var matched = Set<GridPos>()
        let n = Self.size
        // Horizontal runs
        for r in 0..<n {
            var run = 1
            for c in 1...n {
                if c < n, let a = grid[r][c], let b = grid[r][c - 1], a.kind == b.kind {
                    run += 1
                } else {
                    if run >= 3 {
                        for k in (c - run)..<c { matched.insert(GridPos(r: r, c: k)) }
                    }
                    run = 1
                }
            }
        }
        // Vertical runs
        for c in 0..<n {
            var run = 1
            for r in 1...n {
                if r < n, let a = grid[r][c], let b = grid[r - 1][c], a.kind == b.kind {
                    run += 1
                } else {
                    if run >= 3 {
                        for k in (r - run)..<r { matched.insert(GridPos(r: k, c: c)) }
                    }
                    run = 1
                }
            }
        }
        return matched
    }

    /// Drops surviving gems to the bottom of each column and spawns new ones on top.
    private func collapseAndRefill() {
        let n = Self.size
        for c in 0..<n {
            var column: [Gem] = []
            for r in (0..<n).reversed() {
                if let gem = grid[r][c] { column.append(gem) }
            }
            for r in 0..<n {
                let fromBottom = n - 1 - r
                grid[r][c] = fromBottom < column.count ? column[fromBottom] : Gem(kind: Int.random(in: 0..<Self.kinds))
            }
        }
    }
}

// MARK: - View

struct Match3View: View {
    @State private var engine = Match3Engine()

    private static let gemColors: [Color] = [.red, .blue, .green, .orange, .purple]
    private static let gemSymbols = ["heart.fill", "drop.fill", "leaf.fill", "star.fill", "moon.fill"]

    /// Gems flattened with their board coordinates; identity follows the gem,
    /// so position changes animate as movement.
    private struct GemItem: Identifiable {
        let id: UUID
        let kind: Int
        let pos: GridPos
    }

    private var gemItems: [GemItem] {
        var items: [GemItem] = []
        for r in 0..<Match3Engine.size {
            for c in 0..<Match3Engine.size {
                if let gem = engine.grid[r][c] {
                    items.append(GemItem(id: gem.id, kind: gem.kind, pos: GridPos(r: r, c: c)))
                }
            }
        }
        return items
    }

    var body: some View {
        GameContainerView(gameID: .match3, engine: engine) {
            VStack(spacing: 16) {
                movesBar
                board
                Text(L10n.text("Swipe a gem toward a neighbor to swap them."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var movesBar: some View {
        HStack {
            Label(L10n.format("%d moves left", engine.movesLeft), systemImage: "hand.draw.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.neon)
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var board: some View {
        GeometryReader { geo in
            let n = Match3Engine.size
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(n)

            ZStack {
                // Static cell backdrops
                ForEach(0..<(n * n), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.background)
                        .frame(width: cell - 5, height: cell - 5)
                        .position(x: CGFloat(i % n) * cell + cell / 2,
                                  y: CGFloat(i / n) * cell + cell / 2)
                }

                // Gems, positioned by coordinates so moves animate
                ForEach(gemItems) { item in
                    gemView(item, cellSize: cell)
                        .position(x: CGFloat(item.pos.c) * cell + cell / 2,
                                  y: CGFloat(item.pos.r) * cell + cell / 2)
                        .transition(.asymmetric(
                            insertion: .offset(y: -cell * 1.6).combined(with: .opacity),
                            removal: .scale(scale: 0.2).combined(with: .opacity)))
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .themeCard(cornerRadius: 16)
        .aspectRatio(1, contentMode: .fit)
    }

    private func gemView(_ item: GemItem, cellSize: CGFloat) -> some View {
        let isSelected = engine.selected == item.pos
        return RoundedRectangle(cornerRadius: 8)
            .fill(Self.gemColors[item.kind].gradient)
            .overlay {
                Image(systemName: Self.gemSymbols[item.kind])
                    .font(.system(size: cellSize * 0.32, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.neon, lineWidth: 3)
                }
            }
            .frame(width: cellSize - 5, height: cellSize - 5)
            .scaleEffect(isSelected ? 1.12 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
            .contentShape(Rectangle())
            .onTapGesture { engine.tap(item.pos) }
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            engine.swipe(from: item.pos, dr: 0, dc: dx > 0 ? 1 : -1)
                        } else {
                            engine.swipe(from: item.pos, dr: dy > 0 ? 1 : -1, dc: 0)
                        }
                    }
            )
    }
}
