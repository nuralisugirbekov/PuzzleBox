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

    fileprivate struct Snapshot: Codable {
        let cascades: [[Card]]
        let freeCells: [Card?]
        let foundations: [[Card]]
    }
    fileprivate var history: [Snapshot] = []
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
        Haptics.tap(); SoundFX.play(.tap)
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

        if selection != nil, moveSelection(toCascade: col) { autoPlaySafeCards(); return }

        if case .cascade(let c, let i) = selection, c == col, i == index {
            // Tapping the same card again sends it to the best place.
            if !autoMoveSelection() { selection = nil }
            return
        }
        if let index, isValidRun(col: col, from: index) {
            selection = .cascade(col: col, index: index)
            Haptics.tap(); SoundFX.play(.tap)
        } else {
            selection = nil
        }
    }

    private func canMoveSelection(toCascade col: Int) -> Bool {
        if case .cascade(let c, _) = selection, c == col { return false }
        let cards = selectedCards()
        guard let first = cards.first,
              cards.count <= moveCapacity(excludingTarget: col) else { return false }
        if let target = cascades[col].last {
            return target.rank == first.rank + 1 && target.isRed != first.isRed
        }
        return true
    }

    private func moveSelection(toCascade col: Int) -> Bool {
        guard canMoveSelection(toCascade: col) else { return false }
        let cards = selectedCards()

        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            cascades[col].append(contentsOf: cards)
        }
        selection = nil
        Haptics.move(); SoundFX.play(.card)
        return true
    }

    func tapFreeCell(_ i: Int) {
        guard state == .playing else { return }
        if let card = freeCells[i] {
            if selection == .freeCell(i) {
                if !autoMoveSelection() { selection = nil }
            } else if selection == nil {
                selection = .freeCell(i)
                Haptics.tap(); SoundFX.play(.tap)
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
        Haptics.move(); SoundFX.play(.card)
        autoPlaySafeCards()
    }

    func tapFoundation(_ pile: Int) {
        guard state == .playing else { return }
        if selection == .foundation(pile) {
            selection = nil
            Haptics.tap(); SoundFX.play(.tap)
            return
        }
        if moveSelection(toFoundation: pile) { autoPlaySafeCards(); return }
        selection = foundations[pile].isEmpty ? nil : .foundation(pile)
        Haptics.tap(); SoundFX.play(.tap)
    }

    private func canMoveSelection(toFoundation pile: Int) -> Bool {
        // A selected foundation card can return to play, not to another foundation.
        if case .foundation = selection { return false }
        let cards = selectedCards()
        guard cards.count == 1, let card = cards.first else { return false }
        if let top = foundations[pile].last {
            return top.suit == card.suit && card.rank == top.rank + 1
        }
        return card.rank == 1
    }

    private func moveSelection(toFoundation pile: Int) -> Bool {
        guard canMoveSelection(toFoundation: pile), let card = selectedCards().first else { return false }

        saveForUndo()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            removeSelectedCards()
            foundations[pile].append(card)
        }
        selection = nil

        if foundations.reduce(0, { $0 + $1.count }) == 52 {
            state = .gameOver(won: true)
        } else {
            Haptics.move(); SoundFX.play(.card)
        }
        return true
    }

    func isSelected(col: Int, index: Int) -> Bool {
        if case .cascade(let c, let i) = selection { return c == col && index >= i }
        return false
    }

    // MARK: Drag and drop

    /// Picks up `source`; returns the cards that travel with it.
    func beginDrag(_ source: Selection) -> [Card]? {
        guard state == .playing else { return nil }
        if case .cascade(let col, let index) = source, !isValidRun(col: col, from: index) { return nil }
        selection = source
        let cards = selectedCards()
        if cards.isEmpty { selection = nil; return nil }
        return cards
    }

    /// Whether the picked-up cards may go on `pile`.
    func canDrop(on pile: CardPile) -> Bool {
        switch pile {
        case .column(let col): canMoveSelection(toCascade: col)
        case .foundation(let index): canMoveSelection(toFoundation: index)
        case .freeCell(let cell): freeCells[cell] == nil && selectedCards().count == 1
        case .table: false
        }
    }

    /// Drops the picked-up cards on `pile`; nil cancels the drag.
    func drop(on pile: CardPile?) -> Bool {
        var moved = false
        switch pile {
        case .column(let col)?: moved = moveSelection(toCascade: col)
        case .foundation(let index)?: moved = moveSelection(toFoundation: index)
        case .freeCell(let cell)? where freeCells[cell] == nil:
            // An empty cell takes a single card; tapFreeCell plays it (and the
            // safe cards after it) and clears the selection.
            tapFreeCell(cell)
            if selection == nil { return true }
        default: break
        }
        if moved { autoPlaySafeCards() } else { selection = nil }
        return moved
    }

    /// Foundation first, then a cascade with cards, then an empty cascade, then a free cell.
    @discardableResult
    func autoMoveSelection() -> Bool {
        guard selection != nil else { return false }
        for pile in 0..<4 where moveSelection(toFoundation: pile) { autoPlaySafeCards(); return true }
        let order = (0..<cascades.count).sorted { (cascades[$0].isEmpty ? 1 : 0) < (cascades[$1].isEmpty ? 1 : 0) }
        for col in order where moveSelection(toCascade: col) { autoPlaySafeCards(); return true }
        if selectedCards().count == 1, case .cascade = selection, let cell = freeCells.firstIndex(where: { $0 == nil }) {
            tapFreeCell(cell)
            return true
        }
        return false
    }

    /// A card is safe to send home when nothing could still need it as a base:
    /// aces and twos always, otherwise once both opposite-colour cards one rank lower are home.
    private func isSafeForFoundation(_ card: Card) -> Bool {
        if card.rank <= 2 { return true }
        let opposite = foundations.filter { pile in pile.first.map { $0.isRed != card.isRed } ?? false }
        return opposite.count == 2 && opposite.allSatisfy { ($0.last?.rank ?? 0) >= card.rank - 1 }
    }

    /// Plays safe cards from cascades and free cells to the foundations, one by one.
    func autoPlaySafeCards() {
        Task {
            while state == .playing {
                try? await Task.sleep(for: .milliseconds(140))
                guard state == .playing, selection == nil else { return }
                var moved = false
                let sources: [Selection] = cascades.indices.compactMap { col in
                    cascades[col].isEmpty ? nil : .cascade(col: col, index: cascades[col].count - 1)
                } + freeCells.indices.compactMap { freeCells[$0] == nil ? nil : .freeCell($0) }
                for source in sources {
                    selection = source
                    guard let card = selectedCards().first, isSafeForFoundation(card) else { selection = nil; continue }
                    if (0..<4).contains(where: { moveSelection(toFoundation: $0) }) { moved = true; break }
                    selection = nil
                }
                if !moved { return }
            }
        }
    }
}

// MARK: - View

struct FreeCellView: View {
    @State private var engine = FreeCellEngine()
    @State private var drag = CardDragController()

    var body: some View {
        GameContainerView(gameID: .freecell, engine: engine) {
            GeometryReader { geo in
                let cardWidth = (geo.size.width - 7 * 4) / 8
                let cardHeight = cardWidth * CardView.aspectRatio
                VStack(spacing: 32) {
                    topRow(cardWidth: cardWidth)
                    cascadesRow(cardWidth: cardWidth,
                                maxHeight: geo.size.height - cardHeight - 32 - 50 - CardGameControls.bottomInset - 16)
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .bottom) {
                    CardGameControls(canUndo: engine.canUndo, undo: engine.undo)
                }
                .cardTable(drag)
            }
        }
    }

    private func topRow(cardWidth: CGFloat) -> some View {
        // Two groups of four with the same 4pt gaps as the cascades below.
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { i in
                Group {
                    if let card = engine.freeCells[i] {
                        CardView(card: card, width: cardWidth,
                                 highlighted: engine.selection == .freeCell(i))
                            .cardDraggable(card, drag: drag,
                                           begin: { engine.beginDrag(.freeCell(i)) },
                                           canDrop: engine.canDrop, drop: engine.drop)
                    } else {
                        CardSlot(width: cardWidth)
                    }
                }
                .onTapGesture { drag.tap { engine.tapFreeCell(i) } }
                .cardDropTarget(.freeCell(i), drag: drag)
            }
            ForEach(0..<4, id: \.self) { pile in
                Group {
                    if let top = engine.foundations[pile].last {
                        CardView(card: top, width: cardWidth,
                                 highlighted: engine.selection == .foundation(pile))
                            .cardDraggable(top, drag: drag,
                                           begin: { engine.beginDrag(.foundation(pile)) },
                                           canDrop: engine.canDrop, drop: engine.drop)
                    } else {
                        CardSlot(width: cardWidth, label: "A")
                    }
                }
                .onTapGesture { drag.tap { engine.tapFoundation(pile) } }
                .cardDropTarget(.foundation(pile), drag: drag)
            }
        }
    }

    private func cascadesRow(cardWidth: CGFloat, maxHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<8, id: \.self) { col in
                column(col, cardWidth: cardWidth, maxHeight: maxHeight)
            }
        }
    }

    private func column(_ col: Int, cardWidth: CGFloat, maxHeight: CGFloat) -> some View {
        let cards = engine.cascades[col]
        let offsets = CardFan.offsets(for: cards, cardHeight: cardWidth * CardView.aspectRatio,
                                      maxHeight: maxHeight)
        return ZStack(alignment: .top) {
            CardSlot(width: cardWidth)
                .cardDropHighlight(.column(col), drag: drag, when: cards.isEmpty)
                .onTapGesture { drag.tap { engine.tapCascade(col, index: nil) } }
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, card in
                CardView(card: card, width: cardWidth,
                         highlighted: engine.isSelected(col: col, index: i))
                    .cardDraggable(card, drag: drag,
                                   begin: { engine.beginDrag(.cascade(col: col, index: i)) },
                                   canDrop: engine.canDrop, drop: engine.drop)
                    .cardDropHighlight(.column(col), drag: drag, when: i == cards.count - 1)
                    .offset(y: offsets[i])
                    .onTapGesture { drag.tap { engine.tapCascade(col, index: i) } }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .cardDropTarget(.column(col), drag: drag, highlights: false)
    }
}

// MARK: - Saved round

extension FreeCellEngine: ResumableGame {
    private struct Session: Codable {
        let board: Snapshot
        let history: [Snapshot]
    }

    func saveSession() -> Data? {
        guard state == .playing || state == .paused, !history.isEmpty else { return nil }
        return encodeSession(Session(board: Snapshot(cascades: cascades, freeCells: freeCells, foundations: foundations),
                                     history: history))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data) else { return false }
        cascades = session.board.cascades
        freeCells = session.board.freeCells
        foundations = session.board.foundations
        history = session.history
        selection = nil
        state = .playing
        return true
    }
}
