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

    var score: Int { completedRuns * 100 }

    init() { deal() }

    func restart() { deal() }

    private func deal() {
        // 8 full spade suits = 104 cards.
        var deck: [Card] = []
        for _ in 0..<8 {
            deck.append(contentsOf: (1...13).map { Card(suit: .spades, rank: $0, faceUp: false) })
        }
        deck.shuffle()

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
            guard pile[i].rank == pile[i + 1].rank + 1 else { return false }
        }
        return true
    }

    func tapColumn(_ col: Int, index: Int?) {
        guard state == .playing else { return }
        message = ""

        if let sel = selection, sel.col != col, moveSelection(to: col) { return }

        if let sel = selection, sel.col == col, sel.index == index {
            selection = nil
            return
        }
        if let index, isValidRun(col: col, from: index) {
            selection = (col, index)
            Haptics.tap()
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

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            tableau[sel.col].removeSubrange(sel.index...)
            if let last = tableau[sel.col].indices.last, !tableau[sel.col][last].faceUp {
                tableau[sel.col][last].faceUp = true
            }
            tableau[col].append(contentsOf: cards)
        }
        selection = nil
        Haptics.move()
        checkCompletedRun(col)
        return true
    }

    private func checkCompletedRun(_ col: Int) {
        let pile = tableau[col]
        guard pile.count >= 13 else { return }
        let top13 = Array(pile.suffix(13))
        guard top13.first?.rank == 13, top13.allSatisfy(\.faceUp) else { return }
        for i in 0..<12 where top13[i].rank != top13[i + 1].rank + 1 { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tableau[col].removeLast(13)
            if let last = tableau[col].indices.last, !tableau[col][last].faceUp {
                tableau[col][last].faceUp = true
            }
            completedRuns += 1
        }
        Haptics.success()
        if completedRuns == 8 { state = .gameOver(won: true) }
    }

    func dealFromStock() {
        guard state == .playing, let next = stock.last else { return }
        guard !tableau.contains(where: \.isEmpty) else {
            message = "Fill every empty column before dealing"
            Haptics.error()
            return
        }
        selection = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            stock.removeLast()
            for (col, var card) in next.enumerated() {
                card.faceUp = true
                tableau[col].append(card)
            }
        }
        Haptics.move()
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
                    statusBar
                    tableauRow(cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 560)
        }
    }

    private var statusBar: some View {
        HStack {
            Label("\(engine.completedRuns) of 8 runs", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.neon)
            if !engine.message.isEmpty {
                Text(engine.message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            Button {
                engine.dealFromStock()
            } label: {
                Label("Deal (\(engine.stock.count))", systemImage: "square.stack.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(engine.stock.isEmpty ? Theme.textSecondary : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(engine.stock.isEmpty ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Theme.neon),
                                in: Capsule())
            }
            .disabled(engine.stock.isEmpty)
        }
    }

    private func tableauRow(cardWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<SpiderEngine.columns, id: \.self) { col in
                column(col, cardWidth: cardWidth)
            }
        }
    }

    private func column(_ col: Int, cardWidth: CGFloat) -> some View {
        let cards = engine.tableau[col]
        let offsets = Self.offsets(for: cards)
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

    private static func offsets(for cards: [Card]) -> [CGFloat] {
        var out: [CGFloat] = []
        var y: CGFloat = 0
        for card in cards {
            out.append(y)
            y += card.faceUp ? 17 : 7
        }
        return out
    }
}
