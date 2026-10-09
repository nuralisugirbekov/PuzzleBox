import SwiftUI
import Observation

// MARK: - Engine
// Seats: 0 = You (South), 1 = West, 2 = North (your partner), 3 = East.
// Teams: You + North vs West + East. One full 13-trick hand per game.

@MainActor
@Observable
final class SpadesEngine: GameEngine {
    static var names: [String] { [L10n.text("You"), L10n.text("West"), L10n.text("North"), L10n.text("East")] }

    struct Seat {
        var hand: [Card] = []
        var bid = 0
        var tricks = 0
    }

    private(set) var seats: [Seat] = []
    private(set) var trick: [(seat: Int, card: Card)] = []
    private(set) var turn = 0
    private(set) var bidding = true
    private(set) var spadesBroken = false
    private(set) var message = L10n.text("Choose your bid")
    private(set) var score = 0
    private(set) var finalSummary = ""
    var userBid = 3
    var state: GameState = .playing
    private var botTask: Task<Void, Never>?

    init() { deal() }

    func restart() {
        botTask?.cancel()
        deal()
    }

    private func deal() {
        var deck = Card.deck().shuffled()
        seats = (0..<4).map { _ in Seat() }
        for i in 0..<4 {
            seats[i].hand = Array(deck[(i * 13)..<((i + 1) * 13)])
                .sorted { sortKey($0) < sortKey($1) }
        }
        for i in 1..<4 { seats[i].bid = Self.estimateBid(seats[i].hand) }
        trick = []
        turn = 0
        bidding = true
        spadesBroken = false
        userBid = 3
        score = 0
        finalSummary = ""
        message = L10n.text("Choose your bid")
        state = .playing
    }

    private func sortKey(_ card: Card) -> Int {
        // Group by suit (spades last, next to your thumb), ace high inside each suit.
        let suitOrder = [3, 0, 2, 1][card.suit.rawValue]
        return suitOrder * 20 + card.highValue
    }

    private static func estimateBid(_ hand: [Card]) -> Int {
        var estimate = 0.0
        for card in hand {
            if card.rank == 1 { estimate += 1 }
            if card.rank == 13 { estimate += 0.7 }
            if card.rank == 12 { estimate += 0.4 }
        }
        estimate += Double(max(0, hand.filter { $0.suit == .spades }.count - 3)) * 0.7
        return min(7, max(1, Int(estimate.rounded())))
    }

    func startPlaying() {
        seats[0].bid = userBid
        bidding = false
        message = L10n.text("Your lead")
        Haptics.tap()
    }

    // MARK: Rules

    func legalCards(for seat: Int) -> [Card] {
        let hand = seats[seat].hand
        if trick.isEmpty {
            if !spadesBroken {
                let nonSpades = hand.filter { $0.suit != .spades }
                if !nonSpades.isEmpty { return nonSpades }
            }
            return hand
        }
        let lead = trick[0].card.suit
        let following = hand.filter { $0.suit == lead }
        return following.isEmpty ? hand : following
    }

    private func beats(_ card: Card, _ current: Card, lead: Suit) -> Bool {
        if card.suit == .spades && current.suit != .spades { return true }
        if card.suit == current.suit { return card.highValue > current.highValue }
        return false
    }

    private func trickWinner() -> Int {
        let lead = trick[0].card.suit
        var best = trick[0]
        for entry in trick.dropFirst() where beats(entry.card, best.card, lead: lead) {
            best = entry
        }
        return best.seat
    }

    // MARK: Play

    func userPlay(_ card: Card) {
        guard state == .playing, !bidding, turn == 0, trick.count < 4,
              legalCards(for: 0).contains(card) else { return }
        playCard(seat: 0, card: card)
        botTask = Task { await runTable() }
    }

    private func playCard(seat: Int, card: Card) {
        seats[seat].hand.removeAll { $0.id == card.id }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            trick.append((seat: seat, card: card))
        }
        if card.suit == .spades { spadesBroken = true }
        turn = (turn + 1) % 4
        Haptics.tap()
    }

    /// Drives bot turns and trick resolution until it is the user's turn again
    /// (or the hand ends). Pausing simply stalls the loop.
    private func runTable() async {
        while !Task.isCancelled {
            if state == .paused {
                try? await Task.sleep(for: .milliseconds(250))
                continue
            }
            guard state == .playing, !bidding else { return }

            if trick.count == 4 {
                try? await Task.sleep(for: .milliseconds(1000))
                let winner = trickWinner()
                seats[winner].tricks += 1
                withAnimation(.easeOut(duration: 0.25)) { trick = [] }
                turn = winner
                message = winner == 0 ? L10n.text("You took the trick!") : L10n.format("%@ took the trick", Self.names[winner])
                if winner == 0 { Haptics.success() }
                if seats[0].hand.isEmpty {
                    finishHand()
                    return
                }
                if turn == 0 {
                    message += L10n.text(" — your lead")
                    return
                }
            } else if turn != 0 {
                try? await Task.sleep(for: .milliseconds(700))
                guard state == .playing else { continue }
                botPlay(turn)
            } else {
                message = L10n.text("Your turn")
                return
            }
        }
    }

    private func botPlay(_ seat: Int) {
        let legal = legalCards(for: seat)
        guard !legal.isEmpty else { return }
        let card: Card

        if trick.isEmpty {
            // Lead low.
            card = legal.min { $0.highValue < $1.highValue }!
        } else {
            let lead = trick[0].card.suit
            var winning = trick[0]
            for entry in trick.dropFirst() where beats(entry.card, winning.card, lead: lead) {
                winning = entry
            }
            let partnerWinning = winning.seat == (seat + 2) % 4
            let winners = legal.filter { beats($0, winning.card, lead: lead) }
            if partnerWinning || winners.isEmpty {
                card = legal.min { $0.highValue < $1.highValue }!   // dump lowest
            } else {
                card = winners.min { $0.highValue < $1.highValue }! // cheapest winner
            }
        }
        playCard(seat: seat, card: card)
    }

    // MARK: Scoring

    private func partnershipScore(_ s1: Int, _ s2: Int) -> Int {
        let bid = seats[s1].bid + seats[s2].bid
        let tricks = seats[s1].tricks + seats[s2].tricks
        var points = tricks >= bid ? bid * 10 + (tricks - bid) : -bid * 10
        for i in [s1, s2] where seats[i].bid == 0 {
            points += seats[i].tricks == 0 ? 100 : -100
        }
        return points
    }

    private func finishHand() {
        let mine = partnershipScore(0, 2)
        let theirs = partnershipScore(1, 3)
        score = max(0, mine)
        finalSummary = L10n.format("Your team %d — Opponents %d", mine, theirs)
        message = finalSummary
        state = .gameOver(won: mine > theirs)
    }
}

// MARK: - View

struct SpadesView: View {
    @State private var engine = SpadesEngine()

    var body: some View {
        GameContainerView(gameID: .spades, engine: engine) {
            VStack(spacing: 12) {
                opponentsBar
                trickArea
                statusBar
                if engine.bidding {
                    biddingPanel
                } else {
                    handView
                }
            }
        }
    }

    private var opponentsBar: some View {
        HStack(spacing: 8) {
            ForEach([1, 2, 3], id: \.self) { seat in
                VStack(spacing: 2) {
                    Text(SpadesEngine.names[seat] + (seat == 2 ? " ★" : ""))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(seat == 2 ? GameTheme.accent : GameTheme.ink)
                    Text(engine.bidding
                         ? L10n.format("bids %d", engine.seats[seat].bid)
                         : L10n.format("%d/%d tricks", engine.seats[seat].tricks, engine.seats[seat].bid))
                        .font(.caption2)
                        .foregroundStyle(GameTheme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .gameCard(cornerRadius: 12)
            }
        }
    }

    private var trickArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(GameTheme.surface.opacity(0.5))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(GameTheme.stroke, lineWidth: 1) }
            ForEach(engine.trick, id: \.card.id) { entry in
                CardView(card: entry.card, width: 46)
                    .offset(trickOffset(for: entry.seat))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 170)
    }

    private func trickOffset(for seat: Int) -> CGSize {
        switch seat {
        case 0: CGSize(width: 0, height: 38)
        case 1: CGSize(width: -70, height: 0)
        case 2: CGSize(width: 0, height: -38)
        default: CGSize(width: 70, height: 0)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(engine.message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(GameTheme.textSecondary)
                .lineLimit(1)
            Spacer()
            if !engine.bidding {
                Text(L10n.format("You: %d/%d", engine.seats[0].tricks, engine.seats[0].bid))
                    .font(.footnote.bold())
                    .foregroundStyle(GameTheme.accent)
            }
        }
        .padding(.horizontal, 4)
    }

    private var biddingPanel: some View {
        VStack(spacing: 14) {
            Text(L10n.text("How many tricks will you take?"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GameTheme.ink)
            HStack(spacing: 18) {
                bidButton("minus") { if engine.userBid > 0 { engine.userBid -= 1 } }
                Text("\(engine.userBid)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(GameTheme.accent)
                    .frame(width: 70)
                    .contentTransition(.numericText())
                bidButton("plus") { if engine.userBid < 13 { engine.userBid += 1 } }
            }
            Text(engine.userBid == 0 ? L10n.text("Nil bid: +100 if you take no tricks, −100 if you take any!") : " ")
                .font(.caption)
                .foregroundStyle(.yellow)
            Button {
                engine.startPlaying()
            } label: {
                Label(L10n.text("Start Hand"), systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(GameTheme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .gameElevation()
            }
            handView
        }
        .padding(16)
        .gameCard(cornerRadius: 18)
    }

    private func bidButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(GameTheme.ink)
                .frame(width: 44, height: 44)
                .background(GameTheme.surfaceHigh, in: Circle())
        }
    }

    private var handView: some View {
        let legal = engine.bidding ? [] : engine.legalCards(for: 0)
        let myTurn = !engine.bidding && engine.turn == 0 && engine.trick.count < 4
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: -14) {
                ForEach(engine.seats.isEmpty ? [] : engine.seats[0].hand) { card in
                    let playable = myTurn && legal.contains(card)
                    CardView(card: card, width: 46, highlighted: playable)
                        .opacity(engine.bidding || playable || !myTurn ? 1 : 0.4)
                        .offset(y: playable ? -6 : 0)
                        .onTapGesture { engine.userPlay(card) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
    }
}
