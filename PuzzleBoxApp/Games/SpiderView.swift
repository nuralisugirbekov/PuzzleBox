import SwiftUI
import Observation

// MARK: - Engine (1-suit Spider)

@MainActor
@Observable
final class SpiderEngine: GameEngine {
    static let columns = 10

    private(set) var tableau: [[Card]] = []
    private(set) var stock: [[Card]] = []      // remaining deals of 10
    private(set) var completedRuns = 0
    private(set) var message = ""
    var selection: (col: Int, index: Int)?
    var state: GameState = .playing
    /// 1 suit (spades) or 2 suits (spades and hearts); runs must match suit to move or clear.
    private(set) var suitCount = UserDefaults.standard.integer(forKey: "spiderSuits") == 2 ? 2 : 1

    var score: Int { completedRuns * (suitCount == 2 ? 160 : 100) }

    fileprivate struct Snapshot: Codable {
        let tableau: [[Card]]
        let stock: [[Card]]
        let completedRuns: Int
    }
    fileprivate var history: [Snapshot] = []
    var canUndo: Bool { state == .playing && !history.isEmpty }

    init() { deal() }

    func restart() { deal() }

    func setSuitCount(_ value: Int) {
        guard value != suitCount else { return }
        suitCount = value
        UserDefaults.standard.set(value, forKey: "spiderSuits")
        deal()
    }

    private func saveForUndo() {
        history.append(Snapshot(tableau: tableau, stock: stock, completedRuns: completedRuns))
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tableau = previous.tableau
            stock = previous.stock
            completedRuns = previous.completedRuns
            selection = nil
        }
        Haptics.tap(); SoundFX.play(.tap)
    }

    private func deal() {
        // 104 cards: eight spade suits, or four spades plus four hearts.
        var deck: [Card] = []
        for i in 0..<8 {
            let suit: Suit = suitCount == 2 && i.isMultiple(of: 2) ? .hearts : .spades
            deck.append(contentsOf: (1...13).map { Card(suit: suit, rank: $0, faceUp: false) })
        }
        deck.shuffle()
        history.removeAll()

        tableau = (0..<Self.columns).map { col in
            let count = col < 4 ? 6 : 5
            var pile: [Card] = []
            for i in 0..<count {
                var card = deck.removeLast()
                card.faceUp = (i == count - 1)
                pile.append(card)
            }
            return pile
        }
        stock = (0..<5).map { _ in
            (0..<10).map { _ in deck.removeLast() }
        }
        completedRuns = 0
        selection = nil
        message = ""
        state = .playing
    }

    /// A grabbable run is face-up and strictly descending by one.
    private func isValidRun(col: Int, from index: Int) -> Bool {
        let pile = tableau[col]
        guard pile.indices.contains(index), pile[index].faceUp else { return false }
        for i in index..<(pile.count - 1) {
            guard pile[i].rank == pile[i + 1].rank + 1, pile[i].suit == pile[i + 1].suit else { return false }
        }
        return true
    }

    /// The column a run should go to: a matching suit first, then any matching rank, then an empty column.
    private func bestTarget(for col: Int, index: Int) -> Int? {
        let first = tableau[col][index]
        let candidates = (0..<Self.columns).filter { $0 != col && (tableau[$0].last.map { $0.faceUp && $0.rank == first.rank + 1 } ?? false) }
        if let sameSuit = candidates.first(where: { tableau[$0].last?.suit == first.suit }) { return sameSuit }
        if let any = candidates.first { return any }
        // Moving a whole column into an empty one achieves nothing.
        if index > 0, let empty = (0..<Self.columns).first(where: { tableau[$0].isEmpty }) { return empty }
        return nil
    }

    /// Selects a run that has a useful move; a second tap on it plays the move.
    func hint() {
        guard state == .playing else { return }
        var fallback: (Int, Int)?
        for col in 0..<Self.columns {
            guard let start = (0..<tableau[col].count).first(where: { isValidRun(col: col, from: $0) }) else { continue }
            guard let target = bestTarget(for: col, index: start), !tableau[target].isEmpty else { continue }
            // Prefer moves that uncover a face-down card or build on the same suit.
            if start > 0 && !tableau[col][start - 1].faceUp || tableau[target].last?.suit == tableau[col][start].suit {
                selection = (col, start); Haptics.tap(); SoundFX.play(.tick); return
            }
            fallback = fallback ?? (col, start)
        }
        if let fallback { selection = fallback; Haptics.tap(); SoundFX.play(.tick) }
        else { message = L10n.text(stock.isEmpty ? "No moves left" : "Deal more cards"); Haptics.error() }
    }

    func tapColumn(_ col: Int, index: Int?) {
        guard state == .playing else { return }
        message = ""

        if let sel = selection, sel.col != col, moveSelection(to: col) { return }

        if let sel = selection, sel.col == col, sel.index == index {
            // Tapping the same run again sends it to the best column.
            if let target = bestTarget(for: col, index: sel.index), moveSelection(to: target) { return }
            selection = nil
            return
        }
        if let index, isValidRun(col: col, from: index) {
            selection = (col, index)
            Haptics.tap(); SoundFX.play(.tap)
        } else {
            selection = nil
        }
    }

    private func moveSelection(to col: Int) -> Bool {
        guard let sel = selection else { return false }
        let cards = Array(tableau[sel.col][sel.index...])
        guard let first = cards.first else { return false }
        if let target = tableau[col].last {
            guard target.faceUp, target.rank == first.rank + 1 else { return false }
        }

        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tableau[sel.col].removeSubrange(sel.index...)
            if let last = tableau[sel.col].indices.last, !tableau[sel.col][last].faceUp {
                tableau[sel.col][last].faceUp = true
            }
            tableau[col].append(contentsOf: cards)
        }
        selection = nil
        Haptics.move(); SoundFX.play(.card)
        checkCompletedRun(col)
        return true
    }

    private func checkCompletedRun(_ col: Int) {
        let pile = tableau[col]
        guard pile.count >= 13 else { return }
        let top13 = Array(pile.suffix(13))
        guard top13.first?.rank == 13, top13.allSatisfy(\.faceUp) else { return }
        for i in 0..<12 where top13[i].rank != top13[i + 1].rank + 1 || top13[i].suit != top13[i + 1].suit { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tableau[col].removeLast(13)
            if let last = tableau[col].indices.last, !tableau[col][last].faceUp {
                tableau[col][last].faceUp = true
            }
            completedRuns += 1
        }
        Haptics.success(); SoundFX.play(.clear)
        if completedRuns == 8 { state = .gameOver(won: true) }
    }

    func dealFromStock() {
        guard state == .playing, let next = stock.last else { return }
        guard !tableau.contains(where: \.isEmpty) else {
            message = L10n.text("Fill every empty column before dealing")
            Haptics.error(); SoundFX.play(.wrong)
            return
        }
        selection = nil
        saveForUndo()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            stock.removeLast()
            for (col, var card) in next.enumerated() {
                card.faceUp = true
                tableau[col].append(card)
            }
        }
        Haptics.move(); SoundFX.play(.card)
        for col in 0..<Self.columns { checkCompletedRun(col) }
    }

    func isSelected(col: Int, index: Int) -> Bool {
        guard let sel = selection else { return false }
        return sel.col == col && index >= sel.index
    }
}

// MARK: - View

struct SpiderView: View {
    @State private var engine = SpiderEngine()

    var body: some View {
        GameContainerView(gameID: .spiderSolitaire, engine: engine) {
            GeometryReader { geo in
                let cardWidth = (geo.size.width - CGFloat(SpiderEngine.columns - 1) * 4) / CGFloat(SpiderEngine.columns)
                VStack(spacing: 12) {
                    Picker("", selection: Binding(get: { engine.suitCount }, set: { engine.setSuitCount($0) })) {
                        Text(L10n.text("1 suit")).tag(1)
                        Text(L10n.text("2 suits")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    statusBar
                    // Leave room for the 50pt controls pinned to the bottom.
                    tableauRow(cardWidth: cardWidth,
                               maxHeight: geo.size.height - 32 - 12 - 36 - 12 - 50 - CardGameControls.bottomInset - 16)
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .bottom) {
                    CardGameControls(hint: engine.hint, canUndo: engine.canUndo, undo: engine.undo)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Label(L10n.format("%d of 8 runs", engine.completedRuns), systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.accent)
            if !engine.message.isEmpty {
                Text(engine.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                engine.dealFromStock()
            } label: {
                Label(L10n.format("Deal (%d)", engine.stock.count), systemImage: "square.stack.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.stock.isEmpty ? GameTheme.textSecondary : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(engine.stock.isEmpty ? AnyShapeStyle(GameTheme.surface) : AnyShapeStyle(GameTheme.accent),
                                in: Capsule())
            }
            .disabled(engine.stock.isEmpty)
        }
    }

    private func tableauRow(cardWidth: CGFloat, maxHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<SpiderEngine.columns, id: \.self) { col in
                column(col, cardWidth: cardWidth, maxHeight: maxHeight)
            }
        }
    }

    private func column(_ col: Int, cardWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let cards = engine.tableau[col]
        let offsets = CardFan.offsets(for: cards, cardHeight: cardWidth * CardView.aspectRatio,
                                      maxHeight: maxHeight)
        return ZStack(alignment: .top) {
            CardSlot(width: cardWidth)
                .onTapGesture { engine.tapColumn(col, index: nil) }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                CardView(card: card, width: cardWidth,
                         highlighted: engine.isSelected(col: col, index: i))
                    .offset(y: offsets[i])
                    .onTapGesture { engine.tapColumn(col, index: i) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Saved round

extension SpiderEngine: ResumableGame {
    private struct Session: Codable {
        let board: Snapshot
        let history: [Snapshot]
        let suitCount: Int
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, !history.isEmpty else { return nil }
        return encodeSession(Session(board: Snapshot(tableau: tableau, stock: stock, completedRuns: completedRuns),
                                     history: history, suitCount: suitCount))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        suitCount = session.suitCount
        tableau = session.board.tableau
        stock = session.board.stock
        completedRuns = session.board.completedRuns
        history = session.history
        message = ""
        selection = nil
        state = .playing
        return true
    }
}
