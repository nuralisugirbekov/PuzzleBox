import SwiftUI
import Observation

// MARK: - Engine (vs bot)

@MainActor
@Observable
final class BattleshipEngine: GameEngine {
    static let playerSeat = 0
    static let botSeat = 1

    private(set) var table = BattleshipEngine.newTable()
    var state: GameState = .playing {
        didSet { if state == .playing { scheduleBot() } }
    }

    @ObservationIgnored private var botTask: Task<Void, Never>?

    /// A win is worth 100, plus 5 for every deck of the player's fleet still afloat.
    var score: Int {
        table.outcome == .winner(Self.playerSeat) ? 100 + 5 * table.cellsAfloat(of: Self.playerSeat) : 0
    }

    private static func newTable() -> BattleshipState {
        var table = BattleshipState.newGame()
        // The bot's fleet is set from the start; the player sets up theirs.
        table.ready[botSeat] = true
        return table
    }

    func restart() {
        botTask?.cancel()
        table = Self.newTable()
        state = .playing
    }

    func play(_ action: BattleshipAction) {
        guard state == .playing, let next = try? table.applying(action, by: Self.playerSeat) else { return }
        commit(next)
    }

    private func commit(_ next: BattleshipState) {
        let before = table
        table = next
        if before.lastShot != next.lastShot || before.fleets != next.fleets || before.ready != next.ready {
            BattleshipState.playFeedback(for: next)
        }
        if let outcome = table.outcome {
            state = .gameOver(won: outcome == .winner(Self.playerSeat))
        } else {
            scheduleBot()
        }
    }

    private func scheduleBot() {
        botTask?.cancel()
        guard state == .playing, table.currentTurn == Self.botSeat else { return }
        botTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard let self, !Task.isCancelled, self.state == .playing,
                  let action = BattleshipBot.action(for: self.table, seat: Self.botSeat),
                  let next = try? self.table.applying(action, by: Self.botSeat) else { return }
            self.commit(next)
        }
    }
}

extension BattleshipEngine: ResumableGame {
    func saveSession() -> Data? {
        guard table.outcome == nil, !table.isPlacing, !table.shots.allSatisfy(\.isEmpty) else { return nil }
        return encodeSession(table)
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let saved = decodeSession(BattleshipState.self, from: data), saved.outcome == nil else { return false }
        botTask?.cancel()
        table = saved
        state = .playing
        return true
    }
}

// MARK: - Online match

extension BattleshipState: OnlineGameState {
    var isFinished: Bool { outcome != nil }

    func isOut(_ seat: Int) -> Bool { false }

    static func playFeedback(for state: BattleshipState) {
        guard !state.isPlacing, let shot = state.lastShot else {
            Haptics.tap(); SoundFX.play(.place)
            return
        }
        if shot.sunk {
            Haptics.heavy(); SoundFX.play(.clear)
        } else if shot.hit {
            Haptics.move(); SoundFX.play(.hit)
        } else {
            Haptics.tap(); SoundFX.play(.pop)
        }
    }

    func result(for seat: Int, names: [String]) -> OnlineMatchResult? {
        guard let outcome else { return nil }
        if outcome == .winner(seat) {
            return OnlineMatchResult(title: L10n.text("You Win!"), message: L10n.text("The enemy fleet is sunk."),
                                     won: true, score: 100 + 5 * cellsAfloat(of: seat))
        }
        return OnlineMatchResult(title: L10n.text("Game Over"), message: L10n.text("Your fleet is sunk."),
                                 won: false, score: 0)
    }
}

// MARK: - Bot game view

struct BattleshipView: View {
    @State private var engine = BattleshipEngine()

    var body: some View {
        GameContainerView(gameID: .battleship, engine: engine) {
            BattleshipTableView(table: engine.table,
                                seat: BattleshipEngine.playerSeat,
                                names: [L10n.text("You"), L10n.text("Bot")],
                                onAction: engine.play)
        }
    }
}

// MARK: - Table

/// Both boards from `seat`'s side: setting up the fleet first, then firing
/// at the enemy board with this player's own fleet underneath.
struct BattleshipTableView: View {
    let table: BattleshipState
    let seat: Int
    /// Every seat's name, this player's included.
    let names: [String]
    let onAction: (BattleshipAction) -> Void

    private var enemy: Int { table.opponent(of: seat) }
    private var myTurn: Bool { table.currentTurn == seat }

    private func name(_ player: Int) -> String {
        if player == seat { return L10n.text("You") }
        return names.indices.contains(player) ? names[player] : L10n.format("Player %d", player + 1)
    }

    var body: some View {
        Group {
            if table.isPlacing { setup } else { battle }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: table)
    }

    // MARK: Setting up

    private var setup: some View {
        let ready = table.ready[seat]
        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(L10n.text("Set up your fleet"))
                    .font(.title3.weight(.semibold))
                Text(L10n.text("Ships can't touch, not even at the corners. Drag a ship to move it, tap it to turn it, or shuffle."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            BattleshipBoardView(ships: table.fleets[seat], wrecked: [], hits: [], misses: [],
                                onRearrange: ready ? nil : { onAction(.place($0)) })
                .frame(maxWidth: 420)
                .frame(maxHeight: .infinity)
            HStack(spacing: 12) {
                Button {
                    onAction(.place(BattleshipState.randomFleet()))
                } label: {
                    Label(L10n.text("Shuffle"), systemImage: "shuffle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(ready)
                .opacity(ready ? 0.45 : 1)
                Button {
                    onAction(.ready)
                } label: {
                    Label(L10n.text("Ready"), systemImage: "checkmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(ready ? Color.gray : GameTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(ready)
            }
            HStack(spacing: 8) {
                if ready && !table.ready[enemy] { ProgressView() }
                Text(setupStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 24)
        }
    }

    private var setupStatus: String {
        if !table.ready[seat] { return table.ready[enemy] ? L10n.format("%@ is ready.", name(enemy)) : " " }
        return L10n.format("Waiting for %@…", name(enemy))
    }

    // MARK: Battle

    private var battle: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                playerChip(seat)
                playerChip(enemy)
            }
            board(of: enemy, revealAll: table.isFinished)
                .frame(maxWidth: 420)
                .frame(maxHeight: .infinity)
            status
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("Your fleet"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    board(of: seat, revealAll: true)
                        .frame(width: 132, height: 132)
                }
                fleetLeft
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// `owner`'s board as this player sees it: their own ships always, the
    /// enemy's only once sunk (or all of them when the battle is over).
    private func board(of owner: Int, revealAll: Bool) -> some View {
        let shooter = table.opponent(of: owner)
        let fired = Set(table.shots[shooter])
        let shipCells = Set(table.fleets[owner].flatMap(\.cells))
        let wrecked = Set(table.fleets[owner].filter { table.isSunk($0, of: owner) })
        let shown = revealAll || owner == seat ? table.fleets[owner] : Array(wrecked)
        let last = table.lastShot.flatMap { $0.seat == shooter ? $0.target : nil }
        return BattleshipBoardView(ships: shown, wrecked: wrecked,
                                   hits: fired.intersection(shipCells), misses: fired.subtracting(shipCells),
                                   highlight: last,
                                   onTap: owner == enemy && myTurn ? { cell in
                                       if table.canFire(at: cell, by: seat) { onAction(.fire(cell)) }
                                   } : nil)
    }

    private func playerChip(_ player: Int) -> some View {
        let active = table.currentTurn == player
        return HStack(spacing: 6) {
            Text(name(player))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Label("\(table.shipsAfloat(of: player).count)", systemImage: "ferry.fill")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay {
            Capsule().strokeBorder(GameTheme.accent, lineWidth: 2).opacity(active ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(L10n.format("Ships afloat: %d", table.shipsAfloat(of: player).count))
    }

    private var status: some View {
        VStack(spacing: 4) {
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(myTurn ? .primary : .secondary)
                .contentTransition(.opacity)
            if let shot = table.lastShot {
                HStack(spacing: 4) {
                    Text("\(name(shot.seat)): \(BattleshipBoardView.label(for: shot.target)) · \(shotText(shot))")
                    Image(systemName: shot.hit ? "flame.fill" : "drop.fill")
                        .foregroundStyle(shot.hit ? .red : .blue)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .id(table.shots.map(\.count))
                .transition(.opacity)
            }
        }
        .frame(minHeight: 40)
    }

    private var statusText: String {
        guard let turn = table.currentTurn else { return " " }
        return turn == seat ? L10n.text("Your turn: fire at the enemy board") : L10n.format("%@ is aiming…", name(turn))
    }

    private func shotText(_ shot: BattleshipState.LastShot) -> String {
        if shot.sunk { return L10n.text("Sunk!") }
        return L10n.text(shot.hit ? "Hit!" : "Miss")
    }

    /// The enemy ships still afloat, by size.
    private var fleetLeft: some View {
        let afloat = table.shipsAfloat(of: enemy).map(\.length)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("Enemy ships left"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(Set(BattleshipState.fleetLengths)).sorted(by: >), id: \.self) { length in
                let total = BattleshipState.fleetLengths.filter { $0 == length }.count
                let left = afloat.filter { $0 == length }.count
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        ForEach(0..<length, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(left > 0 ? Color.primary.opacity(0.7) : Color.red.opacity(0.6))
                                .frame(width: 10, height: 10)
                        }
                    }
                    Text("\(left)/\(total)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(left > 0 ? .primary : .secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.format("%d-deck ships: %d of %d", length, left, total))
            }
        }
    }
}

// MARK: - Board

/// One 10×10 board: ships, hits (red crosses) and misses (dots). Tapping a
/// cell calls `onTap` when set.
struct BattleshipBoardView: View {
    let ships: [BattleshipShip]
    /// Sunk ships, drawn in red.
    let wrecked: Set<BattleshipShip>
    let hits: Set<GridPos>
    let misses: Set<GridPos>
    var highlight: GridPos? = nil
    var onTap: ((GridPos) -> Void)? = nil
    /// When set, the ships can be rearranged: drag one to move it, tap it to
    /// turn it. Called with the new fleet after each change that keeps it valid.
    var onRearrange: (([BattleshipShip]) -> Void)? = nil

    /// The ship being dragged: which one, where it would land now, and the
    /// deck the finger grabbed it by.
    private struct Lifted {
        let index: Int
        let grab: GridPos
        var ship: BattleshipShip
    }

    @State private var lifted: Lifted?

    private static let columns = Array("ABCDEFGHIJ").map(String.init)

    /// "B7": column letter, then row number.
    static func label(for cell: GridPos) -> String {
        columns[cell.c] + "\(cell.r + 1)"
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(BattleshipState.size)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: max(4, cell * 0.3), style: .continuous)
                    .fill(LinearGradient(colors: [Self.seaTop, Self.seaBottom], startPoint: .top, endPoint: .bottom))
                grid(cell: cell, side: side)
                ForEach(Array(ships.enumerated()), id: \.element) { index, ship in
                    if lifted?.index != index { shipShape(ship, cell: cell) }
                }
                if let lifted {
                    let fits = BattleshipState.fleet(ships, replacing: lifted.index, with: lifted.ship) != nil
                    shipShape(lifted.ship, cell: cell, tint: fits ? GameTheme.accent : .red)
                }
                ForEach(Array(misses), id: \.self) { pos in
                    // A splash: a ripple ring around a drop.
                    ZStack {
                        Circle().strokeBorder(Self.splash, lineWidth: max(1, cell * 0.06))
                            .frame(width: cell * 0.5, height: cell * 0.5)
                        Circle().fill(Self.splash)
                            .frame(width: cell * 0.16, height: cell * 0.16)
                    }
                    .position(center(pos, cell: cell))
                    .transition(.scale)
                }
                ForEach(Array(hits), id: \.self) { pos in
                    // A flash under the cross.
                    Circle()
                        .fill(RadialGradient(colors: [Color.orange.opacity(0.75), Color.orange.opacity(0)],
                                             center: .center, startRadius: 0, endRadius: cell * 0.5))
                        .frame(width: cell, height: cell)
                        .position(center(pos, cell: cell))
                        .transition(.opacity)
                    Image(systemName: "xmark")
                        .font(.system(size: cell * 0.55, weight: .black))
                        .foregroundStyle(.red)
                        .position(center(pos, cell: cell))
                        .transition(.scale.combined(with: .opacity))
                }
                if let highlight {
                    RoundedRectangle(cornerRadius: cell * 0.2)
                        .strokeBorder(GameTheme.accent, lineWidth: 2)
                        .frame(width: cell, height: cell)
                        .position(center(highlight, cell: cell))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                let pos = position(at: value.location, cell: cell)
                if let onTap, BattleshipState.contains(pos) { onTap(pos) }
            }, including: onTap == nil ? .none : .all)
            .gesture(rearrangeGesture(cell: cell), including: onRearrange == nil ? .none : .all)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(L10n.format("Hits: %d, misses: %d", hits.count, misses.count))
    }

    private func position(at location: CGPoint, cell: CGFloat) -> GridPos {
        GridPos(r: Int((location.y / cell).rounded(.down)), c: Int((location.x / cell).rounded(.down)))
    }

    /// Drag a ship to move it; a touch that barely moves turns it instead.
    private func rearrangeGesture(cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if lifted == nil {
                    let start = position(at: value.startLocation, cell: cell)
                    guard let index = ships.firstIndex(where: { $0.cells.contains(start) }) else { return }
                    let ship = ships[index]
                    lifted = Lifted(index: index, grab: GridPos(r: start.r - ship.origin.r, c: start.c - ship.origin.c),
                                    ship: ship)
                }
                guard var dragged = lifted else { return }
                let at = position(at: value.location, cell: cell)
                let origin = GridPos(r: at.r - dragged.grab.r, c: at.c - dragged.grab.c)
                guard origin != dragged.ship.origin else { return }
                dragged.ship = BattleshipShip(origin: origin, length: dragged.ship.length, horizontal: dragged.ship.horizontal)
                lifted = dragged
                Haptics.tap()
            }
            .onEnded { value in
                guard let dragged = lifted, let onRearrange else { return }
                lifted = nil
                let moved = hypot(value.translation.width, value.translation.height) > cell * 0.4
                if !moved && dragged.ship.length == 1 { return }
                let next = moved ? BattleshipState.fleet(ships, replacing: dragged.index, with: dragged.ship)
                                 : BattleshipState.fleet(ships, turning: dragged.index)
                if let next { onRearrange(next) } else { Haptics.error() }
            }
    }

    private static let seaTop = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.09, green: 0.20, blue: 0.36, alpha: 1)
        : UIColor(red: 0.86, green: 0.93, blue: 1.00, alpha: 1) })
    private static let seaBottom = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.05, green: 0.12, blue: 0.25, alpha: 1)
        : UIColor(red: 0.72, green: 0.85, blue: 0.97, alpha: 1) })
    private static let splash = Color(red: 0.35, green: 0.55, blue: 0.80).opacity(0.8)
    private static let steel = Color(red: 0.42, green: 0.48, blue: 0.55)
    private static let steelEdge = Color(red: 0.24, green: 0.28, blue: 0.33)

    private func center(_ pos: GridPos, cell: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(pos.c) + 0.5) * cell, y: (CGFloat(pos.r) + 0.5) * cell)
    }

    private func grid(cell: CGFloat, side: CGFloat) -> some View {
        Path { path in
            for i in 1..<BattleshipState.size {
                let offset = CGFloat(i) * cell
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset, y: side))
                path.move(to: CGPoint(x: 0, y: offset))
                path.addLine(to: CGPoint(x: side, y: offset))
            }
        }
        .stroke(Color.blue.opacity(0.25), lineWidth: 0.5)
    }

    /// A ship; `tint` draws one being dragged, in the accent while it fits and red while it doesn't.
    private func shipShape(_ ship: BattleshipShip, cell: CGFloat, tint: Color? = nil) -> some View {
        let long = CGFloat(ship.length) * cell - cell * 0.16
        let short = cell * 0.84
        let sunk = wrecked.contains(ship)
        let first = center(ship.origin, cell: cell)
        let offset = CGFloat(ship.length - 1) * cell / 2
        let fill = tint.map { $0.opacity(0.35) } ?? (sunk ? Color.red.opacity(0.3) : Self.steel)
        let stroke = tint ?? (sunk ? Color.red : Self.steelEdge)
        let hull = HullShape(vertical: !ship.horizontal)
        return hull
            .fill(fill)
            .overlay {
                // One hatch per deck, along the middle of the hull.
                let hatch = cell * 0.2
                let layout = ship.horizontal ? AnyLayout(HStackLayout(spacing: cell - hatch))
                                             : AnyLayout(VStackLayout(spacing: cell - hatch))
                layout {
                    ForEach(0..<ship.length, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(sunk || tint != nil ? 0.25 : 0.55))
                            .frame(width: hatch, height: hatch)
                    }
                }
            }
            .overlay { hull.stroke(stroke, lineWidth: max(1, cell * 0.05)) }
            .frame(width: ship.horizontal ? long : short, height: ship.horizontal ? short : long)
            .position(x: first.x + (ship.horizontal ? offset : 0), y: first.y + (ship.horizontal ? 0 : offset))
    }
}

/// A hull seen from above: a rounded stern and a pointed bow, pointing right
/// (or down when vertical).
private struct HullShape: Shape {
    let vertical: Bool

    func path(in rect: CGRect) -> Path {
        // Drawn pointing right in a horizontal box, then turned for vertical ships.
        let w = vertical ? rect.height : rect.width
        let h = vertical ? rect.width : rect.height
        let bow = min(w * 0.5, h * 1.1)
        let stern = h * 0.35
        var path = Path()
        path.move(to: CGPoint(x: stern, y: 0))
        path.addLine(to: CGPoint(x: w - bow, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w - bow * 0.45, y: 0))
        path.addQuadCurve(to: CGPoint(x: w - bow, y: h), control: CGPoint(x: w - bow * 0.45, y: h))
        path.addLine(to: CGPoint(x: stern, y: h))
        path.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: 0), radius: stern)
        path.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: stern, y: 0), radius: stern)
        path.closeSubpath()
        guard vertical else { return path.offsetBy(dx: rect.minX, dy: rect.minY) }
        // Swap the axes: the bow points down.
        return path.applying(CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: rect.minX, ty: rect.minY))
    }
}
