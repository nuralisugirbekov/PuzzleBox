import SwiftUI
import Observation

// Drag and drop for the card games. Engines stay selection-based: picking a
// card up selects it exactly like a tap would, and dropping it runs the same
// move the second tap would. Illegal drops slide back to where they started.
//
// A table view:
//   1. owns a `CardDragController` and wraps its play area in `.cardTable(drag)`;
//   2. marks piles with `.cardDropTarget(_:drag:)`;
//   3. marks movable cards with `.cardDraggable(card, drag:, begin:, drop:)`.

/// A place cards can be dropped. Games use the cases they have.
enum CardPile: Hashable {
    case column(Int)
    case foundation(Int)
    case freeCell(Int)
    /// Durak: the play area.
    case table
}

@MainActor
@Observable
final class CardDragController {
    static let space = "cardTable"

    /// The cards travelling with the finger, top card first.
    private(set) var cards: [Card] = []
    private(set) var translation: CGSize = .zero
    /// Piles that accept the cards in hand; highlighted while dragging.
    private(set) var legalPiles: Set<CardPile> = []
    /// The legal pile the cards would drop on if released now.
    private(set) var hovered: CardPile?
    /// Cards that just landed on a pile: they appear there without animating
    /// in from their old spot, since the ghost already carried them over.
    private(set) var landed: Set<UUID> = []

    @ObservationIgnored var cardFrames: [UUID: CGRect] = [:]
    @ObservationIgnored var pileFrames: [CardPile: CGRect] = [:]
    /// Finger position in the table's coordinate space.
    @ObservationIgnored private var location: CGPoint = .zero
    /// The current gesture has been offered to the game (accepted or not).
    @ObservationIgnored private var gestureStarted = false
    @ObservationIgnored private var returning = false
    @ObservationIgnored private var lastDragEnd = Date.distantPast

    /// Runs a tap handler unless a drag just ended. Removing a dropped card's
    /// view lets the tap on its parent pile fire as the finger lifts, which
    /// would select the next card.
    func tap(_ action: () -> Void) {
        guard !isDragging, Date().timeIntervalSince(lastDragEnd) > 0.35 else { return }
        action()
    }

    var isDragging: Bool { !cards.isEmpty }

    func isDragging(_ id: UUID) -> Bool { cards.contains { $0.id == id } }

    fileprivate func changed(_ value: DragGesture.Value, begin: () -> [Card]?,
                             canDrop: (CardPile) -> Bool) {
        if !gestureStarted {
            gestureStarted = true
            guard !returning, let moving = begin(), !moving.isEmpty else { return }
            cards = moving
            // The table doesn't change mid-drag, so legality is worked out once.
            legalPiles = Set(pileFrames.keys.filter(canDrop))
            Haptics.tap()
        }
        guard isDragging else { return }
        translation = value.translation
        location = value.location
        let target = dropTarget()
        if target != hovered {
            hovered = target
            if target != nil { Haptics.tap() }
        }
    }

    fileprivate func ended(drop: (CardPile?) -> Bool) {
        gestureStarted = false
        guard isDragging else { return }
        lastDragEnd = Date()
        let target = dropTarget()
        hovered = nil
        legalPiles = []
        if let target, drop(target) {
            landed = Set(cards.map(\.id))
            cards = []
            translation = .zero
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                self.landed = []
            }
        } else {
            _ = drop(nil)
            returning = true
            withAnimation(.spring(duration: 0.25)) {
                translation = .zero
            } completion: {
                self.cards = []
                self.returning = false
            }
        }
    }

    /// Where a release would land: the legal pile under the finger, else the
    /// legal pile the dragged top card overlaps most. Only legal piles count,
    /// so hovering a neighbour never falls back to the pile the cards came from.
    private func dropTarget() -> CardPile? {
        let zones = pileFrames.compactMap { pile, rect in
            legalPiles.contains(pile) ? (pile, Self.zone(for: pile, rect)) : nil
        }
        if let underFinger = zones.first(where: { $0.1.contains(location) }) {
            return underFinger.0
        }
        guard let first = cards.first, let frame = cardFrames[first.id] else { return nil }
        let moved = frame.offsetBy(dx: translation.width, dy: translation.height)
        var best: CardPile?
        var bestArea: CGFloat = 0
        for (pile, zone) in zones {
            let overlap = zone.intersection(moved)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                best = pile
                bestArea = area
            }
        }
        return best
    }

    /// The area that accepts a drop. A column takes it anywhere from its top
    /// edge down, over every card in it and the space below its last card;
    /// other piles get a little slack around their edges.
    private static func zone(for pile: CardPile, _ rect: CGRect) -> CGRect {
        switch pile {
        case .column:
            CGRect(x: rect.minX - 2, y: rect.minY - 12, width: rect.width + 4, height: 10_000)
        case .foundation, .freeCell:
            rect.insetBy(dx: -2, dy: -12)
        case .table:
            rect
        }
    }
}

// MARK: - Modifiers

extension View {
    /// The play area: defines the drag coordinate space and draws the
    /// cards being dragged above everything else.
    func cardTable(_ drag: CardDragController) -> some View {
        coordinateSpace(.named(CardDragController.space))
            .overlay(alignment: .topLeading) { CardDragLayer(drag: drag) }
    }

    /// Marks a pile. While cards are in hand it lights up if it accepts them,
    /// and more strongly when a release would land on it. Fanned columns pass
    /// `highlights: false` and put `cardDropHighlight` on their top card instead,
    /// since their own frame only covers the deepest card.
    func cardDropTarget(_ pile: CardPile, drag: CardDragController, highlights: Bool = true) -> some View {
        onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(CardDragController.space))
        } action: { frame in
            drag.pileFrames[pile] = frame
        }
        .overlay {
            if highlights { DropHighlight(pile: pile, drag: drag) }
        }
    }

    /// Draws `pile`'s drop highlight around this view: the card on top of a
    /// fanned column, or its empty slot.
    func cardDropHighlight(_ pile: CardPile, drag: CardDragController, when active: Bool = true) -> some View {
        overlay {
            if active { DropHighlight(pile: pile, drag: drag) }
        }
    }

    /// Lets `card` be picked up. `begin` selects it in the engine and returns
    /// every card that moves with it, or nil when it can't move. `drop` plays
    /// the move onto a pile and returns whether it was legal; it is called
    /// with nil when the drag is cancelled so the engine can clear its selection.
    func cardDraggable(_ card: Card, drag: CardDragController, enabled: Bool = true,
                       begin: @escaping () -> [Card]?,
                       canDrop: @escaping (CardPile) -> Bool,
                       drop: @escaping (CardPile?) -> Bool) -> some View {
        modifier(CardDraggable(card: card, drag: drag, enabled: enabled,
                               begin: begin, canDrop: canDrop, drop: drop))
    }
}

private struct CardDraggable: ViewModifier {
    let card: Card
    let drag: CardDragController
    let enabled: Bool
    let begin: () -> [Card]?
    let canDrop: (CardPile) -> Bool
    let drop: (CardPile?) -> Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(CardDragController.space))
            } action: { frame in
                drag.cardFrames[card.id] = frame
            }
            // The ghost in `CardDragLayer` stands in while the card is in the air.
            .opacity(drag.isDragging(card.id) ? 0 : 1)
            .transaction { transaction in
                if drag.landed.contains(card.id) { transaction.animation = nil }
            }
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(CardDragController.space))
                    .onChanged { value in drag.changed(value, begin: begin, canDrop: canDrop) }
                    .onEnded { _ in drag.ended(drop: drop) },
                including: enabled ? .all : .subviews
            )
    }
}

/// The glow on a pile that accepts the cards in hand.
private struct DropHighlight: View {
    let pile: CardPile
    let drag: CardDragController

    var body: some View {
        let legal = drag.isDragging && drag.legalPiles.contains(pile)
        let hovered = legal && drag.hovered == pile
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        shape
            .fill(CardView.glow.opacity(hovered ? 0.16 : 0.06))
            .overlay { shape.strokeBorder(CardView.glow, lineWidth: hovered ? 3 : 2) }
            .padding(-3)
            .opacity(legal ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: legal)
            .animation(.easeOut(duration: 0.12), value: hovered)
            .allowsHitTesting(false)
    }
}

/// The dragged cards, drawn where the finger has taken them.
private struct CardDragLayer: View {
    let drag: CardDragController

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(drag.cards) { card in
                if let frame = drag.cardFrames[card.id] {
                    CardView(card: card, width: frame.width, highlighted: true)
                        .position(x: frame.midX + drag.translation.width,
                                  y: frame.midY + drag.translation.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shadow(color: .black.opacity(drag.isDragging ? 0.3 : 0), radius: 10, y: 6)
        .allowsHitTesting(false)
    }
}
