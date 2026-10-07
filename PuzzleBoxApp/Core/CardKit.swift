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

struct CardView: View {
    let card: Card
    var width: CGFloat = 44
    var highlighted = false

    var body: some View {
        let corner = width * 0.14
        Group {
            if card.faceUp {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.white)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: -width * 0.05) {
                            Text(card.rankLabel)
                                .font(.system(size: width * 0.34, weight: .bold))
                            Text(card.suit.symbol)
                                .font(.system(size: width * 0.3))
                        }
                        .foregroundStyle(card.isRed ? Color.red : Color.black)
                        .padding(width * 0.09)
                    }
            } else {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Theme.surfaceHigh)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner * 0.7)
                            .strokeBorder(Theme.neon.opacity(0.35), lineWidth: 1)
                            .padding(3)
                    }
            }
        }
        .frame(width: width, height: width * 1.45)
        .overlay {
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(highlighted ? Theme.neon : Color.black.opacity(0.3),
                              lineWidth: highlighted ? 2.5 : 1)
        }
    }
}

/// Shared undo control for card games with move history.
struct CardUndoButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(L10n.text("Undo"), systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Theme.neon : Theme.textSecondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .themeCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Empty pile placeholder (foundations, free cells, empty columns).
struct CardSlot: View {
    var width: CGFloat = 44
    var label: String = ""

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.14)
            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            .frame(width: width, height: width * 1.45)
            .overlay {
                Text(label)
                    .font(.system(size: width * 0.4))
                    .foregroundStyle(Color.white.opacity(0.18))
            }
            // Empty slots are outlined, but the entire card-sized area is tappable.
            .contentShape(Rectangle())
    }
}
