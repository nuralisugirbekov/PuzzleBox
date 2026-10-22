import SwiftUI
import Observation

enum TogyzMode: Int, CaseIterable {
    case quick, classic
    var title: String { self == .quick ? "Quick" : "Classic" }
    var rules: TogyzBoard.Rules { self == .quick ? .quick : .classic }
    /// Search depth and noise of the computer opponent.
    var depth: Int { self == .quick ? 2 : 4 }
    var randomness: Int { self == .quick ? 6 : 0 }
}

@MainActor
@Observable
final class TogyzEngine: GameEngine {
    private static let modeKey = "togyzMode"

    var state: GameState = .playing
    private(set) var mode: TogyzMode
    private(set) var board: TogyzBoard
    /// What is on screen while a move is being sown pebble by pebble.
    private(set) var display: TogyzBoard
    private(set) var selected: Int?
    private(set) var hintPit: Int?
    private(set) var lastPit: Int?
    private(set) var busy = false
    private(set) var message = ""
    private(set) var hintsLeft = 0
    private(set) var tuzdykFlash = 0
    private var token = 0

    var score: Int { display.kazan[0] * (mode == .quick ? 8 : 5) + (wonBonus ? (mode == .quick ? 300 : 500) : 0) }
    private var wonBonus: Bool { if case .gameOver(won: true) = state { return true } else { return false } }
    var playerTurn: Bool { board.turn == .bottom && !busy && state == .playing }
    var showsPreview: Bool { mode == .quick }

    init() {
        let saved = TogyzMode(rawValue: UserDefaults.standard.integer(forKey: Self.modeKey)) ?? .quick
        mode = saved
        let fresh = TogyzBoard(rules: saved.rules)
        board = fresh
        display = fresh
        restart()
    }

    func restart() {
        token += 1
        state = .playing
        board = TogyzBoard(rules: mode.rules)
        display = board
        selected = nil; hintPit = nil; lastPit = nil; busy = false
        hintsLeft = mode == .quick ? 99 : 3
        message = L10n.text("Your move")
    }

    func setMode(_ value: TogyzMode) {
        guard value != mode else { return }
        mode = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.modeKey)
        restart()
    }

    /// What playing a pit would do, for the Quick mode preview.
    struct Preview { let last: Int; let captured: Int; let tuzdyk: Bool }
    func preview(_ index: Int) -> Preview? {
        var copy = board
        guard let outcome = copy.play(index) else { return nil }
        return Preview(last: outcome.last, captured: outcome.captured, tuzdyk: outcome.newTuzdyk != nil)
    }

    func tap(_ index: Int) {
        guard playerTurn, board.side(of: index) == .bottom, board.pits[index] > 0 else { return }
        hintPit = nil
        if showsPreview && selected != index {
            selected = index
            Haptics.tap(); SoundFX.play(.tap)
            if let p = preview(index) {
                message = p.tuzdyk ? L10n.text("This move makes a tuzdyk!")
                    : p.captured > 0 ? L10n.format("This move captures %d", p.captured)
                    : L10n.text("Tap again to play this pit")
            }
            return
        }
        selected = nil
        commit(index)
    }

    func hint() {
        guard playerTurn, hintsLeft > 0, let move = board.bestMove(depth: 4) else { return }
        hintsLeft -= 1
        hintPit = move
        selected = nil
        message = L10n.text("Try the highlighted pit")
        Haptics.move(); SoundFX.play(.coin)
    }

    private func commit(_ index: Int) {
        var next = board
        guard let outcome = next.play(index) else { return }
        let mover = board.turn
        let pre = board
        board = next
        busy = true
        message = ""
        lastPit = outcome.last
        let id = token
        Task { @MainActor in
            await animate(from: pre, index: index, outcome: outcome, mover: mover, id: id)
        }
    }

    private func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }

    private func animate(from pre: TogyzBoard, index: Int, outcome: TogyzBoard.Outcome, mover: TogyzBoard.Side, id: Int) async {
        var shown = pre
        shown.pits[index] = 0
        display = shown
        for drop in outcome.drops {
            while state == .paused { await pause(120) }
            guard id == token else { return }
            await pause(outcome.drops.count > 10 ? 90 : 130)
            guard id == token else { return }
            if let owner = shown.isTuzdyk(drop) { shown.kazan[owner.rawValue] += 1; SoundFX.play(.coin) }
            else { shown.pits[drop] += 1; SoundFX.play(.tick) }
            display = shown
        }
        await pause(220)
        guard id == token else { return }
        // The settled position includes captures and new tuzdyks.
        display = board
        if outcome.newTuzdyk != nil {
            tuzdykFlash += 1
            message = mover == .bottom ? L10n.text("Tuzdyk! This pit is yours now") : L10n.text("The computer made a tuzdyk")
            Haptics.success(); SoundFX.play(.clear)
        } else if outcome.captured > 0 {
            message = mover == .bottom ? L10n.format("You captured %d", outcome.captured) : L10n.format("The computer captured %d", outcome.captured)
            if mover == .bottom { Haptics.success(); SoundFX.play(.merge) } else { Haptics.move(); SoundFX.play(.hit) }
        } else {
            message = mover == .bottom ? L10n.text("Computer is thinking…") : L10n.text("Your move")
        }
        board.finishIfStuck()
        display = board
        busy = false
        if finishGameIfOver() { return }
        if board.turn == .top { await computerMove(id: id) }
        else if outcome.captured == 0 { message = L10n.text("Your move") }
    }

    private func computerMove(id: Int) async {
        busy = true
        await pause(650)
        guard id == token else { return }
        while state == .paused { await pause(120); guard id == token else { return } }
        guard let move = board.bestMove(depth: mode.depth, randomness: mode.randomness) else { busy = false; _ = finishGameIfOver(); return }
        var next = board
        guard let outcome = next.play(move) else { busy = false; return }
        let pre = board
        board = next
        lastPit = outcome.last
        await animate(from: pre, index: move, outcome: outcome, mover: .top, id: id)
    }

    /// Ends the game when someone has enough pebbles or the board is empty.
    private func finishGameIfOver() -> Bool {
        board.finishIfStuck()
        display = board
        guard board.isOver else { return false }
        let winner = board.winner
        message = winner == .bottom ? L10n.text("You won!") : winner == .top ? L10n.text("The computer won") : L10n.text("A draw")
        state = .gameOver(won: winner == .bottom)
        busy = false
        return true
    }
}

struct TogyzView: View {
    @State private var engine = TogyzEngine()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let wood = LinearGradient(colors: [Color(red: 0.62, green: 0.40, blue: 0.22), Color(red: 0.45, green: 0.27, blue: 0.14)],
                                             startPoint: .top, endPoint: .bottom)
    private static let you = Color(red: 0.2, green: 0.7, blue: 0.95)
    private static let them = Color(red: 1.0, green: 0.55, blue: 0.3)

    var body: some View {
        GameContainerView(gameID: .togyzkumalak, engine: engine,
                          resultTitle: nil, resultSummary: L10n.text(engine.mode.title)) {
            VStack(spacing: 12) {
                Picker("", selection: Binding(get: { engine.mode }, set: { engine.setMode($0) })) {
                    ForEach(TogyzMode.allCases, id: \.self) { Text(L10n.text($0.title)).tag($0) }
                }
                .pickerStyle(.segmented)
                board
                HStack {
                    Text(engine.message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(engine.board.turn == .bottom ? GameTheme.accent : Color.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.snappy, value: engine.message)
                    Button { engine.hint() } label: {
                        Label(engine.mode == .quick ? L10n.text("Hint") : L10n.format("Hint (%d)", engine.hintsLeft), systemImage: "lightbulb.fill")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(GameTheme.surfaceHigh, in: Capsule())
                    }
                    .disabled(!engine.playerTurn || engine.hintsLeft == 0)
                }
                Text(L10n.text(engine.mode == .quick
                               ? "Pick a pit to see what it does, then tap it again to play. Collect 31 pebbles to win."
                               : "Sow counter-clockwise. End on the opponent's side with an even count to capture it; make exactly 3 to claim a tuzdyk. Collect 82 to win."))
                    .font(.footnote).foregroundStyle(GameTheme.textSecondary).multilineTextAlignment(.center)
            }
        }
        .id(engine.mode)
    }

    // MARK: Board

    private var board: some View {
        let b = engine.display
        let n = b.n
        return VStack(spacing: 10) {
            kazan(side: .top)
            VStack(spacing: 6) {
                // The top player's pits are drawn right to left: sowing runs counter-clockwise.
                row(indices: Array(((n)..<(2 * n)).reversed()), top: true)
                row(indices: Array(0..<n), top: false)
            }
            .padding(10)
            .background(Self.wood, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1.5) }
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            kazan(side: .bottom)
        }
    }

    private func row(indices: [Int], top: Bool) -> some View {
        HStack(spacing: indices.count > 6 ? 4 : 8) {
            ForEach(indices, id: \.self) { index in pit(index, top: top) }
        }
    }

    private func pit(_ index: Int, top: Bool) -> some View {
        let b = engine.display
        let count = b.pits[index]
        let tuzdykOwner = b.isTuzdyk(index)
        let playable = !top && engine.playerTurn && count > 0
        let selected = engine.selected == index
        let preview = engine.selected.flatMap { engine.preview($0) }
        let isEnd = preview?.last == index
        let hinted = engine.hintPit == index
        let last = engine.lastPit == index && !engine.busy
        let ring: Color = selected ? .white : hinted ? .yellow : isEnd ? .green : last ? .white.opacity(0.7) : .clear
        return GeometryReader { geo in
            let side = geo.size.width
            ZStack {
                Circle().fill(Color.black.opacity(0.42))
                Circle().fill(RadialGradient(colors: [Color(red: 0.25, green: 0.14, blue: 0.07), Color(red: 0.12, green: 0.06, blue: 0.03)],
                                             center: .center, startRadius: 1, endRadius: side * 0.55)).padding(side * 0.04)
                if let owner = tuzdykOwner {
                    Circle().strokeBorder(owner == .bottom ? Self.you : Self.them, lineWidth: 3).padding(side * 0.04)
                    Image(systemName: "star.fill").font(.system(size: side * 0.4)).foregroundStyle((owner == .bottom ? Self.you : Self.them).opacity(0.9))
                }
                stones(count: count, side: side)
                if count > 0 && tuzdykOwner == nil {
                    Text("\(count)")
                        .font(.system(size: max(11, side * 0.36), weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .contentTransition(.numericText())
                }
                Circle().strokeBorder(ring, lineWidth: selected || hinted || isEnd ? 3 : 2).padding(1)
                if isEnd, let p = preview, p.captured > 0 {
                    Text("+\(p.captured)").font(.caption2.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 4).background(.green, in: Capsule()).offset(y: -side * 0.55)
                }
            }
            .scaleEffect(hinted && !reduceMotion ? 1.06 : 1)
            .animation(.snappy(duration: 0.15), value: count)
            .animation(.snappy, value: selected)
            .contentShape(Circle())
            .onTapGesture { engine.tap(index) }
            .opacity(!top && !playable && engine.board.turn == .bottom && !engine.busy && count == 0 ? 0.7 : 1)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(alignment: top ? .top : .bottom) {
            Text("\(b.number(of: index))").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                .offset(y: top ? -11 : 11)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Pit %d: %d", b.number(of: index), count))
        .accessibilityAddTraits(playable ? .isButton : [])
    }

    /// Up to a dozen small pebbles around the pit's centre.
    private func stones(count: Int, side: CGFloat) -> some View {
        Canvas { context, size in
            let shown = min(count, 12)
            for k in 0..<shown {
                let ring = k < 5 ? 0 : 1
                let inRing = ring == 0 ? 5 : 7
                let a = (CGFloat(ring == 0 ? k : k - 5) / CGFloat(inRing)) * .pi * 2 + CGFloat(ring) * 0.5
                let r = size.width * (ring == 0 ? 0.17 : 0.3)
                let c = CGPoint(x: size.width / 2 + cos(a) * r, y: size.height / 2 + sin(a) * r)
                let d = size.width * 0.15
                let tones: [Color] = [Color(red: 0.93, green: 0.88, blue: 0.78), Color(red: 0.85, green: 0.78, blue: 0.66), Color(red: 0.96, green: 0.93, blue: 0.86)]
                context.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(tones[k % 3].opacity(0.55)))
            }
        }
        .allowsHitTesting(false)
    }

    private func kazan(side: TogyzBoard.Side) -> some View {
        let b = engine.display
        let value = b.kazan[side.rawValue]
        let color = side == .bottom ? Self.you : Self.them
        let goal = b.rules.winning
        return HStack(spacing: 12) {
            Image(systemName: side == .bottom ? "person.fill" : "desktopcomputer")
                .foregroundStyle(color).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.text(side == .bottom ? "Your kazan" : "Computer's kazan")).font(.caption.weight(.semibold)).foregroundStyle(GameTheme.textSecondary)
                    Spacer()
                    Text("\(value)").font(.title3.bold().monospacedDigit()).contentTransition(.numericText())
                        .foregroundStyle(color)
                    Text("/ \(goal)").font(.caption).foregroundStyle(GameTheme.textSecondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GameTheme.surfaceHigh)
                        Capsule().fill(color.gradient).frame(width: geo.size.width * min(1, CGFloat(value) / CGFloat(goal)))
                    }
                }
                .frame(height: 8)
                .animation(.spring(duration: 0.4), value: value)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(GameTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(engine.board.turn == side && engine.state == .playing ? color.opacity(0.8) : .clear, lineWidth: 2)
        }
    }
}
