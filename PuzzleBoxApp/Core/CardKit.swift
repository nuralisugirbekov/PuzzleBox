import SwiftUI

// Shared playing-card model and rendering used by the card mini-games.

enum Suit: Int, CaseIterable {
    case spades, hearts, diamonds, clubs

    var symbol: String { ["♠", "♥", "♦", "♣"][rawValue] }
    var isRed: Bool { self == .hearts || self == .diamonds }
}

struct Card: Identifiable, Equatable {
    let id = UUID()
    let suit: Suit
    let rank: Int  // 1 = ace ... 13 = king
    var faceUp = true

    var rankLabel: String {
        switch rank {
        case 1: "A"
        case 11: "J"
        case 12: "Q"
        case 13: "K"
        default: "\(rank)"
        }
    }

    var isRed: Bool { suit.isRed }

    /// Ace-high value for trick-taking games.
    var highValue: Int { rank == 1 ? 14 : rank }

    static func deck() -> [Card] {
        Suit.allCases.flatMap { suit in (1...13).map { Card(suit: suit, rank: $0) } }
    }
}

/// Figma `_card`: a 50×72 white card with a black hairline, the rank and a
/// small pip in the top corners and a large pip below the centre. All
/// metrics are taken from the 50pt design and scale with `width`.
struct CardView: View {
    let card: Card
    var width: CGFloat = 44
    var highlighted = false

    static let aspectRatio: CGFloat = 72 / 50
    static func cornerRadius(for width: CGFloat) -> CGFloat { width * 4 / 50 }

    private var scale: CGFloat { width / 50 }
    private var height: CGFloat { width * Self.aspectRatio }
    private var ink: Color { card.isRed ? Self.red : Self.black }

    static let red = Color(red: 0xDB / 255, green: 0x0A / 255, blue: 0x17 / 255)
    static let black = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x17 / 255)
    static let glow = Color(red: 0.86, green: 0.62, blue: 0.24)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius(for: width))
        Group {
            if card.faceUp {
                shape.fill(Color.white)
                    .overlay(alignment: .topLeading) { corner }
                    .overlay { centerPip }
            } else {
                CardBack(width: width)
            }
        }
        .frame(width: width, height: height)
        .overlay { shape.strokeBorder(Color.black, lineWidth: 1) }
        .overlay {
            // Figma "glow": a softened 2pt ring at the edge. The rendered design
            // reads as amber over the hairline, so it is drawn in that colour.
            if highlighted {
                shape.stroke(Self.glow, lineWidth: 3)
                    .blur(radius: 1.5)
                shape.strokeBorder(Self.glow, lineWidth: 1.5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(card.faceUp ? "\(card.rankLabel) \(card.suit.symbol)" : L10n.text("Card"))
    }

    private static let rankSize: CGFloat = 16
    private static let cornerPipScale: CGFloat = 1.2

    private var corner: some View {
        HStack(alignment: .top, spacing: 0) {
            // Enlarged from the design's 12pt so ranks read at a glance; it still
            // fits the 16pt strip left visible in a fanned column.
            Text(card.rankLabel)
                .font(.system(size: Self.rankSize * scale, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(ink)
                .frame(height: 13 * scale)
                .padding(.top, 1.5 * scale)
            Spacer(minLength: 0)
            Image(card.suit.assetName(small: true))
                .resizable()
                .frame(width: card.suit.smallSize.width * Self.cornerPipScale * scale,
                       height: card.suit.smallSize.height * Self.cornerPipScale * scale)
                .padding(.top, 3 * scale)
        }
        .padding(.leading, 3 * scale)
        .padding(.trailing, 5.25 * scale)
    }

    private var centerPip: some View {
        Image(card.suit.assetName(small: false))
            .resizable()
            .frame(width: card.suit.largeSize.width * scale,
                   height: card.suit.largeSize.height * scale)
            .offset(y: card.suit.largeCenterOffset * scale)
    }
}

/// Face-down card. The design has no back, so it uses the app accent.
private struct CardBack: View {
    let width: CGFloat

    var body: some View {
        let corner = CardView.cornerRadius(for: width)
        RoundedRectangle(cornerRadius: corner)
            .fill(GameTheme.accent.gradient)
            .overlay {
                RoundedRectangle(cornerRadius: corner * 0.6)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    .padding(width * 0.08)
            }
    }
}

extension Suit {
    fileprivate var name: String { ["spades", "hearts", "diamonds", "clubs"][rawValue] }

    fileprivate func assetName(small: Bool) -> String {
        "Suit-\(name)" + (small ? "-small" : "")
    }

    /// Figma pip sizes at a 50pt card width.
    fileprivate var largeSize: CGSize {
        switch self {
        case .hearts: CGSize(width: 26, height: 24)
        case .diamonds: CGSize(width: 26, height: 34)
        case .spades, .clubs: CGSize(width: 26, height: 26)
        }
    }

    fileprivate var smallSize: CGSize {
        switch self {
        case .hearts: CGSize(width: 9.75, height: 9)
        case .diamonds: CGSize(width: 7, height: 9)
        case .spades, .clubs: CGSize(width: 9.75, height: 9.75)
        }
    }

    /// Vertical offset of the large pip's centre from the card centre.
    fileprivate var largeCenterOffset: CGFloat {
        switch self {
        case .hearts: 8
        case .diamonds: 7
        case .spades, .clubs: 9
        }
    }
}

/// Figma hint and undo controls: 50pt Liquid Glass circles under the table.
/// Pass `nil` for `hint` in games without hints.
struct CardGameControls: View {
    var hint: (() -> Void)?
    let canUndo: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 64) {
            if let hint {
                control("lightbulb", label: L10n.text("Hint"), action: hint)
            }
            control("arrow.uturn.backward", label: L10n.text("Undo"), action: undo)
                .disabled(!canUndo)
                .opacity(canUndo ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity)
        // Sits where the design's hidden tab bar would end, not at the very bottom.
        .padding(.bottom, Self.bottomInset)
    }

    static let bottomInset: CGFloat = 40

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Empty pile placeholder (foundations, free cells, empty columns).
struct CardSlot: View {
    var width: CGFloat = 44
    var label: String = ""

    var body: some View {
        RoundedRectangle(cornerRadius: CardView.cornerRadius(for: width))
            .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            .frame(width: width, height: width * CardView.aspectRatio)
            .overlay {
                Text(label)
                    .font(.system(size: width * 0.4))
                    .foregroundStyle(Color.primary.opacity(0.18))
            }
            // Empty slots are outlined, but the entire card-sized area is tappable.
            .contentShape(Rectangle())
    }
}

/// Vertical offsets for a fanned tableau column. Face-up cards step by the
/// design's 16.25pt per 72pt card; the fan tightens when it would run past
/// `maxHeight`.
enum CardFan {
    static func offsets(for cards: [Card], cardHeight: CGFloat, maxHeight: CGFloat) -> [CGFloat] {
        let faceUp = cardHeight * 16.25 / 72
        let faceDown = cardHeight * 0.12
        let steps = cards.dropLast().map { $0.faceUp ? faceUp : faceDown }
        let natural = steps.reduce(0, +)
        let room = max(0, maxHeight - cardHeight)
        let squeeze = natural > room && natural > 0 ? room / natural : 1
        var y: CGFloat = 0
        var out: [CGFloat] = []
        for (i, _) in cards.enumerated() {
            out.append(y)
            if i < steps.count { y += steps[i] * squeeze }
        }
        return out
    }
}
