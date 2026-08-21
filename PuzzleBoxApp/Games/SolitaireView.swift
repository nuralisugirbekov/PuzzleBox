import SwiftUI
import Observation

// MARK: - Engine (Klondike, tap-to-move)

@MainActor
@Observable
final class SolitaireEngine: GameEngine {
    enum Selection: Equatable {
        case waste
        case tableau(col: Int, index: Int)
    }

    private(set) var stock: [Card] = []
    private(set) var waste: [Card] = []
    private(set) var foundations: [[Card]] = []
    private(set) var tableau: [[Card]] = []
    private(set) var score = 0
    var selection: Selection?
    var state: GameState = .playing

    init() { deal() }

    func restart() { deal() }

    private func deal() {
        var deck = Card.deck().shuffled()
        tableau = (0..<7).map { col in
            var pile: [Card] = []
            for i in 0...col {
                var card = deck.removeLast()
                card.faceUp = (i == col)
                pile.append(card)
            }
            return pile
        }
        for i in deck.indices { deck[i].faceUp = false }
        stock = deck
        waste = []
        foundations = Array(repeating: [], count: 4)
        score = 0
        selection = nil
        state = .playing
    }

    // MARK: Stock

    func tapStock() {
        guard state == .playing else { return }
        selection = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            if var card = stock.popLast() {
                card.faceUp = true
                waste.append(card)
            } else if !waste.isEmpty {
                stock = waste.reversed().map { var c = $0; c.faceUp = false; return c }
                waste = []
            }
        }
        Haptics.tap()
    }

    func tapWaste() {
        guard state == .playing, !waste.isEmpty else { return }
        selection = selection == .waste ? nil : .waste
        Haptics.tap()
    }

    // MARK: Moves

    private func selectedCards() -> [Card] {
        switch selection {
        case .waste:
            return waste.last.map { [$0] } ?? []
        case .tableau(let col, let index):
            guard tableau.indices.contains(col), tableau[col].indices.contains(index) else { return [] }
            return Array(tableau[col][index...])
        case nil:
            return []
        }
    }

    private func removeSelectedCards() {
        switch selection {
        case .waste:
            waste.removeLast()
            score += 5
        case .tableau(let col, let index):
            tableau[col].removeSubrange(index...)
            if let last = tableau[col].indices.last, !tableau[col][last].faceUp {
                tableau[col][last].faceUp = true
                score += 5
            }
        case nil:
            break
        }
    }

    func tapColumn(_ col: Int, index: Int?) {
        guard state == .playing else { return }

        if selection != nil, moveSelection(toColumn: col) { return }

        if case .tableau(let c, let i) = selection, c == col, i == index {
            selection = nil
            return
        }
        if let index, tableau[col][index].faceUp {
            selection = .tableau(col: col, index: index)
            Haptics.tap()
        } else {
            selection = nil
        }
    }

    private func moveSelection(toColumn col: Int) -> Bool {
        if case .tableau(let c, _) = selection, c == col { return false }
        let cards = selectedCards()
        guard let first = cards.first else { return false }

        if let target = tableau[col].last {
            guard target.faceUp, target.isRed != first.isRed, target.rank == first.rank + 1 else { return false }
        } else {
            guard first.rank == 13 else { return false }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            tableau[col].append(contentsOf: cards)
        }
        selection = nil
        Haptics.move()
        return true
    }

    func tapFoundation(_ pile: Int) {
        guard state == .playing else { return }
        let cards = selectedCards()
        // Only single cards go to foundations.
        guard cards.count == 1, let card = cards.first else { return }
        if case .tableau(let col, let index) = selection, index != tableau[col].count - 1 { return }

        if let top = foundations[pile].last {
            guard top.suit == card.suit, card.rank == top.rank + 1 else { return }
        } else {
            guard card.rank == 1 else { return }
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            foundations[pile].append(card)
            score += 10
        }
        selection = nil

        if foundations.reduce(0, { $0 + $1.count }) == 52 {
            state = .gameOver(won: true)
        } else {
            Haptics.move()
        }
    }

    func isSelected(col: Int, index: Int) -> Bool {
        if case .tableau(let c, let i) = selection { return c == col && index >= i }
        return false
    }
}

// MARK: - View

struct SolitaireView: View {
    @State private var engine = SolitaireEngine()

    var body: some View {
        GameContainerView(gameID: .solitaire, engine: engine) {
            GeometryReader { geo in
                let cardWidth = (geo.size.width - 36) / 7
                VStack(spacing: 16) {
                    topRow(cardWidth: cardWidth)
                    tableauRow(cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 540)
        }
    }

    private func topRow(cardWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            // Stock
            Group {
                if let top = engine.stock.last {
                    CardView(card: top, width: cardWidth)
                } else {
                    CardSlot(width: cardWidth, label: "↻")
                }
            }
            .onTapGesture { engine.tapStock() }

            // Waste
            Group {
                if let top = engine.waste.last {
                    CardView(card: top, width: cardWidth, highlighted: engine.selection == .waste)
                } else {
                    CardSlot(width: cardWidth)
                }
            }
            .onTapGesture { engine.tapWaste() }

            Spacer(minLength: 4)

            ForEach(0..<4, id: \.self) { pile in
                Group {
                    if let top = engine.foundations[pile].last {
                        CardView(card: top, width: cardWidth)
                    } else {
                        CardSlot(width: cardWidth, label: "A")
                    }
                }
                .onTapGesture { engine.tapFoundation(pile) }
            }
        }
    }

    private func tableauRow(cardWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<7, id: \.self) { col in
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
            y += card.faceUp ? 22 : 10
        }
        return out
    }
}
