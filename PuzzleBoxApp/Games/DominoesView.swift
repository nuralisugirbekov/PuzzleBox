import SwiftUI
import Observation

// MARK: - Engine

struct Domino: Identifiable, Equatable {
    let id = UUID()
    let a: Int
    let b: Int

    var pips: Int { a + b }
}

struct PlacedTile: Identifiable, Equatable {
    let id = UUID()
    let left: Int
    let right: Int
}

@MainActor
@Observable
final class DominoesEngine: GameEngine {
    private(set) var chain: [PlacedTile] = []
    private(set) var hand: [Domino] = []
    private(set) var botHand: [Domino] = []
    private(set) var boneyard: [Domino] = []
    private(set) var isUserTurn = true
    private(set) var message = L10n.text("Your move — play a tile")
    private(set) var score = 0
    var pendingChoice: Domino?
    var state: GameState = .playing
    private var consecutivePasses = 0
    private var botTask: Task<Void, Never>?

    var leftEnd: Int? { chain.first?.left }
    var rightEnd: Int? { chain.last?.right }

    init() { deal() }

    func restart() {
        botTask?.cancel()
        deal()
    }

    private func deal() {
        var set: [Domino] = []
        for a in 0...6 {
            for b in a...6 { set.append(Domino(a: a, b: b)) }
        }
        set.shuffle()
        hand = Array(set[0..<7])
        botHand = Array(set[7..<14])
        boneyard = Array(set[14...])
        chain = []
        isUserTurn = true
        consecutivePasses = 0
        pendingChoice = nil
        score = 0
        message = L10n.text("Your move — play a tile")
        state = .playing
    }

    func canPlay(_ d: Domino) -> Bool {
        guard let left = leftEnd, let right = rightEnd else { return true }
        return d.a == left || d.b == left || d.a == right || d.b == right
    }

    var userHasPlayableTile: Bool { hand.contains(where: canPlay) }

    func userTap(_ d: Domino) {
        guard state == .playing, isUserTurn, canPlay(d) else { return }
        guard let left = leftEnd, let right = rightEnd else {
            play(d, onLeft: false, mine: true)
            return
        }
        let fitsLeft = d.a == left || d.b == left
        let fitsRight = d.a == right || d.b == right
        if fitsLeft && fitsRight && left != right {
            pendingChoice = d          // both ends work — let the player pick
            Haptics.tap()
        } else {
            play(d, onLeft: fitsLeft, mine: true)
        }
    }

    func chooseEnd(left: Bool) {
        guard let d = pendingChoice else { return }
        pendingChoice = nil
        play(d, onLeft: left, mine: true)
    }

    private func play(_ d: Domino, onLeft: Bool, mine: Bool) {
        let placed: PlacedTile
        if chain.isEmpty {
            placed = PlacedTile(left: d.a, right: d.b)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { chain = [placed] }
        } else if onLeft {
            let end = leftEnd!
            placed = d.b == end ? PlacedTile(left: d.a, right: d.b)
                                : PlacedTile(left: d.b, right: d.a)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { chain.insert(placed, at: 0) }
        } else {
            let end = rightEnd!
            placed = d.a == end ? PlacedTile(left: d.a, right: d.b)
                                : PlacedTile(left: d.b, right: d.a)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { chain.append(placed) }
        }

        consecutivePasses = 0
        if mine {
            hand.removeAll { $0.id == d.id }
            Haptics.move()
            if hand.isEmpty { return finish(userWon: true, reason: L10n.text("You played every tile!")) }
            passTurnToBot()
        } else {
            botHand.removeAll { $0.id == d.id }
            if botHand.isEmpty { return finish(userWon: false, reason: L10n.text("Bot played every tile.")) }
            isUserTurn = true
            message = userHasPlayableTile ? L10n.text("Your move") : L10n.text("No playable tile — draw")
        }
    }

    func userDraw() {
        guard state == .playing, isUserTurn, !userHasPlayableTile else { return }
        if let tile = boneyard.popLast() {
            withAnimation { hand.append(tile) }
            Haptics.tap()
            message = userHasPlayableTile ? L10n.text("Drawn — you can play!") : L10n.text("Still stuck — draw again")
        } else {
            // Boneyard empty: pass.
            consecutivePasses += 1
            message = L10n.text("You passed")
            if consecutivePasses >= 2 { return resolveBlocked() }
            passTurnToBot()
        }
    }

    private func passTurnToBot() {
        isUserTurn = false
        if state == .playing { message = L10n.text("Bot is thinking…") }
        botTask = Task { await botMove() }
    }

    private func botMove() async {
        try? await Task.sleep(for: .milliseconds(800))
        guard state == .playing, !Task.isCancelled else { return }

        var playable = botHand.filter(canPlay)
        while playable.isEmpty, let drawn = boneyard.popLast() {
            botHand.append(drawn)
            try? await Task.sleep(for: .milliseconds(250))
            playable = botHand.filter(canPlay)
        }

        guard let choice = playable.max(by: { $0.pips < $1.pips }) else {
            consecutivePasses += 1
            message = L10n.text("Bot passed")
            if consecutivePasses >= 2 { return resolveBlocked() }
            isUserTurn = true
            if !userHasPlayableTile && boneyard.isEmpty {
                // Both stuck with an empty boneyard.
                consecutivePasses += 1
                return resolveBlocked()
            }
            return
        }

        let left = leftEnd
        let onLeft: Bool
        if chain.isEmpty {
            onLeft = false
        } else if let left, choice.a == left || choice.b == left {
            onLeft = true
        } else {
            onLeft = false
        }
        play(choice, onLeft: onLeft, mine: false)
    }

    private func resolveBlocked() {
        let myPips = hand.reduce(0) { $0 + $1.pips }
        let botPips = botHand.reduce(0) { $0 + $1.pips }
        if myPips <= botPips {
            finish(userWon: true, reason: L10n.format("Blocked — you have fewer pips (%d vs %d).", myPips, botPips))
        } else {
            finish(userWon: false, reason: L10n.format("Blocked — bot has fewer pips (%d vs %d).", botPips, myPips))
        }
    }

    private func finish(userWon: Bool, reason: String) {
        message = reason
        if userWon {
            score = 100 + botHand.reduce(0) { $0 + $1.pips }
        } else {
            score = 0
        }
        state = .gameOver(won: userWon)
    }
}

// MARK: - View

struct DominoesView: View {
    @State private var engine = DominoesEngine()

    var body: some View {
        GameContainerView(gameID: .dominoes, engine: engine) {
            VStack(spacing: 14) {
                botBar
                chainView
                statusBar
                if engine.pendingChoice != nil {
                    choiceBar
                }
                handView
            }
        }
    }

    private var botBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .foregroundStyle(GameTheme.accent)
            Text(L10n.text("Bot"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.ink)
            ForEach(0..<min(engine.botHand.count, 10), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(GameTheme.surfaceHigh)
                    .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(GameTheme.stroke, lineWidth: 1) }
                    .frame(width: 14, height: 26)
            }
            Text("\(engine.botHand.count)")
                .font(.caption.bold())
                .foregroundStyle(GameTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var chainView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                if engine.chain.isEmpty {
                    Text(L10n.text("Play the first tile"))
                        .font(.footnote)
                        .foregroundStyle(GameTheme.textSecondary)
                        .padding(.horizontal, 16)
                }
                ForEach(engine.chain) { tile in
                    HStack(spacing: 0) {
                        DominoFace(pips: tile.left, size: 30)
                        DominoFace(pips: tile.right, size: 30)
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 5))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(10)
            .frame(minHeight: 56)
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .gameCard(cornerRadius: 14)
    }

    private var statusBar: some View {
        HStack {
            Text(engine.message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(GameTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            Button {
                engine.userDraw()
            } label: {
                Label(engine.boneyard.isEmpty ? L10n.text("Pass") : L10n.format("Draw (%d)", engine.boneyard.count),
                      systemImage: engine.boneyard.isEmpty ? "hand.raised.fill" : "plus.rectangle.on.rectangle")
                    .font(.subheadline.bold())
                    .foregroundStyle(drawEnabled ? .white : GameTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(drawEnabled ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(GameTheme.surface),
                                in: Capsule())
            }
            .disabled(!drawEnabled)
        }
        .padding(.horizontal, 4)
    }

    private var drawEnabled: Bool {
        engine.isUserTurn && !engine.userHasPlayableTile && engine.state == .playing
    }

    private var choiceBar: some View {
        HStack(spacing: 10) {
            Text(L10n.text("Play on which end?"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(GameTheme.ink)
            Button { engine.chooseEnd(left: true) } label: {
                Label(L10n.text("Left"), systemImage: "arrow.left")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(GameTheme.accent, in: Capsule())
            }
            Button { engine.chooseEnd(left: false) } label: {
                Label(L10n.text("Right"), systemImage: "arrow.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(GameTheme.accent, in: Capsule())
            }
        }
    }

    private var handView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(engine.hand) { tile in
                    let playable = engine.isUserTurn && engine.canPlay(tile) && engine.state == .playing
                    VStack(spacing: 0) {
                        DominoFace(pips: tile.a, size: 34)
                        DominoFace(pips: tile.b, size: 34)
                    }
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(playable ? GameTheme.accent : Color.black.opacity(0.3),
                                          lineWidth: playable ? 2.5 : 1)
                    }
                    .opacity(playable || !engine.isUserTurn ? 1 : 0.45)
                    .onTapGesture { engine.userTap(tile) }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }
}

/// One half of a domino tile, drawn with die-face pip symbols.
struct DominoFace: View {
    let pips: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
            if pips > 0 {
                Image(systemName: "die.face.\(pips).fill")
                    .font(.system(size: size * 0.82))
                    .foregroundStyle(Color.black, Color.white)
            }
        }
        .frame(width: size, height: size)
    }
}
