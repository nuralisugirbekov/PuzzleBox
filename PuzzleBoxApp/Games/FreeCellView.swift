import SwiftUI
import Observation

// MARK: - Engine

@MainActor
@Observable
final class FreeCellEngine: GameEngine {
    enum Selection: Equatable {
        case foundation(Int)
        case cascade(col: Int, index: Int)
        case freeCell(Int)
    }

    private(set) var cascades: [[Card]] = []
    private(set) var freeCells: [Card?] = []
    private(set) var foundations: [[Card]] = []
    var selection: Selection?
    var state: GameState = .playing

    var score: Int { foundations.reduce(0) { $0 + $1.count } * 10 }

    private struct Snapshot {
        let cascades: [[Card]]
        let freeCells: [Card?]
        let foundations: [[Card]]
    }
    private var history: [Snapshot] = []
    var canUndo: Bool { state == .playing && !history.isEmpty }

    private func saveForUndo() {
        history.append(Snapshot(cascades: cascades, freeCells: freeCells,
                                foundations: foundations))
    }

    func undo() {
        guard canUndo, let previous = history.popLast() else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            cascades = previous.cascades
            freeCells = previous.freeCells
            foundations = previous.foundations
            selection = nil
        }
        Haptics.tap()
    }

    init() { deal() }

    func restart() { deal() }

    private func deal() {
        history.removeAll()
        var deck = Card.deck().shuffled()
        cascades = (0..<8).map { col in
            let count = col < 4 ? 7 : 6
            return (0..<count).map { _ in deck.removeLast() }
        }
        freeCells = Array(repeating: nil, count: 4)
        foundations = Array(repeating: [], count: 4)
        selection = nil
        state = .playing
    }

    /// A movable run is descending with alternating colors.
    private func isValidRun(col: Int, from index: Int) -> Bool {
        let pile = cascades[col]
        guard pile.indices.contains(index) else { return false }
        for i in index..<(pile.count - 1) {
            guard pile[i].rank == pile[i + 1].rank + 1,
                  pile[i].isRed != pile[i + 1].isRed else { return false }
        }
        return true
    }

    private func selectedCards() -> [Card] {
        switch selection {
        case .foundation(let pile):
            return foundations[pile].last.map { [$0] } ?? []
        case .cascade(let col, let index):
            return Array(cascades[col][index...])
        case .freeCell(let i):
            return freeCells[i].map { [$0] } ?? []
        case nil:
            return []
        }
    }

    private func removeSelectedCards() {
        switch selection {
        case .foundation(let pile):
            foundations[pile].removeLast()
        case .cascade(let col, let index):
            cascades[col].removeSubrange(index...)
        case .freeCell(let i):
            freeCells[i] = nil
        case nil:
            break
        }
    }

    /// Supermove capacity: (empty free cells + 1) × (empty cascades + 1).
    private func moveCapacity(excludingTarget target: Int?) -> Int {
        let free = freeCells.filter { $0 == nil }.count
        var empty = 0
        for (i, pile) in cascades.enumerated() where pile.isEmpty && i != target {
            empty += 1
        }
        return (free + 1) * (empty + 1)
    }

    func tapCascade(_ col: Int, index: Int?) {
        guard state == .playing else { return }

        if selection != nil, moveSelection(toCascade: col) { return }

        if case .cascade(let c, let i) = selection, c == col, i == index {
            selection = nil
            return
        }
        if let index, isValidRun(col: col, from: index) {
            selection = .cascade(col: col, index: index)
            Haptics.tap()
        } else {
            selection = nil
        }
    }

    private func moveSelection(toCascade col: Int) -> Bool {
        if case .cascade(let c, _) = selection, c == col { return false }
        let cards = selectedCards()
        guard let first = cards.first,
              cards.count <= moveCapacity(excludingTarget: col) else { return false }

        if let target = cascades[col].last {
            guard target.rank == first.rank + 1, target.isRed != first.isRed else { return false }
        }

        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            cascades[col].append(contentsOf: cards)
        }
        selection = nil
        Haptics.move()
        return true
    }

    func tapFreeCell(_ i: Int) {
        guard state == .playing else { return }
        if let card = freeCells[i] {
            if selection == .freeCell(i) {
                selection = nil
            } else if selection == nil {
                selection = .freeCell(i)
                Haptics.tap()
            } else {
                selection = nil
            }
            _ = card
            return
        }
        // Empty cell: drop a single selected card here.
        let cards = selectedCards()
        guard cards.count == 1, let card = cards.first else { return }
        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            freeCells[i] = card
        }
        selection = nil
        Haptics.move()
    }

    func tapFoundation(_ pile: Int) {
        guard state == .playing else { return }
        if selection == .foundation(pile) {
            selection = nil
            Haptics.tap()
            return
        }
        if moveSelection(toFoundation: pile) { return }
        selection = foundations[pile].isEmpty ? nil : .foundation(pile)
        Haptics.tap()
    }

    private func moveSelection(toFoundation pile: Int) -> Bool {
        // A selected foundation card can return to play, not to another foundation.
        if case .foundation = selection { return false }
        let cards = selectedCards()
        guard cards.count == 1, let card = cards.first else { return false }

        if let top = foundations[pile].last {
            guard top.suit == card.suit, card.rank == top.rank + 1 else { return false }
        } else {
            guard card.rank == 1 else { return false }
        }

        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            foundations[pile].append(card)
        }
        selection = nil

        if foundations.reduce(0, { $0 + $1.count }) == 52 {
            state = .gameOver(won: true)
        } else {
            Haptics.move()
        }
        return true
    }

    func isSelected(col: Int, index: Int) -> Bool {
        if case .cascade(let c, let i) = selection { return c == col && index >= i }
        return false
    }
}

// MARK: - View

struct FreeCellView: View {
    @State private var engine = FreeCellEngine()

    var body: some View {
        GameContainerView(gameID: .freecell, engine: engine) {
            GeometryReader { geo in
                let cardWidth = (geo.size.width - 7 * 5) / 8
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        CardUndoButton(isEnabled: engine.canUndo, action: engine.undo)
                    }
                    topRow(cardWidth: cardWidth)
                    cascadesRow(cardWidth: cardWidth)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 540)
        }
    }

    private func topRow(cardWidth: CGFloat) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { i in
                Group {
                    if let card = engine.freeCells[i] {
                        CardView(card: card, width: cardWidth,
                                 highlighted: engine.selection == .freeCell(i))
                    } else {
                        CardSlot(width: cardWidth)
                    }
                }
                .onTapGesture { engine.tapFreeCell(i) }
            }
            Spacer(minLength: 2)
            ForEach(0..<4, id: \.self) { pile in
                Group {
                    if let top = engine.foundations[pile].last {
                        CardView(card: top, width: cardWidth,
                                 highlighted: engine.selection == .foundation(pile))
                    } else {
                        CardSlot(width: cardWidth, label: "A")
                    }
                }
                .onTapGesture { engine.tapFoundation(pile) }
            }
        }
    }

    private func cascadesRow(cardWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 5) {
            ForEach(0..<8, id: \.self) { col in
                column(col, cardWidth: cardWidth)
            }
        }
    }

    private func column(_ col: Int, cardWidth: CGFloat) -> some View {
        let cards = engine.cascades[col]
        return ZStack(alignment: .top) {
            CardSlot(width: cardWidth)
                .onTapGesture { engine.tapCascade(col, index: nil) }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                CardView(card: card, width: cardWidth,
                         highlighted: engine.isSelected(col: col, index: i))
                    .offset(y: CGFloat(i) * 20)
                    .onTapGesture { engine.tapCascade(col, index: i) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
