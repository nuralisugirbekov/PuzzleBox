import SwiftUI
import Observation

// MARK: - Engine (vs bots)

@MainActor
@Observable
final class DurakEngine: GameEngine {
    static let playerSeat = 0
    /// How many bots sit at the table (1–5), chosen before the game.
    static let botCountKey = "durak.botCount"

    static var botCount: Int {
        let saved = UserDefaults.standard.integer(forKey: botCountKey)
        return min(max(saved, 1), DurakState.playerRange.upperBound - 1)
    }

    private(set) var table = DurakState.deal(players: 1 + DurakEngine.botCount, options: .saved)
    private(set) var moves = 0
    var state: GameState = .playing {
        didSet { if state == .playing { scheduleBot() } }
    }

    @ObservationIgnored private var botTask: Task<Void, Never>?
    /// Bluffed cards the bots have already had their one chance to notice.
    @ObservationIgnored private var judged: Set<UUID> = []

    /// Going out wins 100, plus 10 for every card the others still hold.
    var score: Int {
        if table.outcome == .draw { return 50 }
        guard table.isOut(Self.playerSeat), table.outcome != .loser(Self.playerSeat) else { return 0 }
        return 100 + 10 * table.hands.joined().count
    }

    var isDraw: Bool { table.outcome == .draw }

    /// "You", then "Bot" (or "Bot 1"… with several).
    var names: [String] {
        let bots = table.playerCount - 1
        return [L10n.text("You")] + (1...max(bots, 1)).prefix(bots).map {
            bots == 1 ? L10n.text("Bot") : L10n.format("Bot %d", $0)
        }
    }

    init() { scheduleBot() }

    func restart() {
        botTask?.cancel()
        table = DurakState.deal(players: 1 + Self.botCount, options: .saved)
        judged = []
        moves = 0
        state = .playing
        scheduleBot()
    }

    func play(_ action: DurakAction) {
        guard state == .playing, let next = try? table.applying(action, by: Self.playerSeat) else { return }
        commit(next, action: action)
    }

    private func commit(_ next: DurakState, action: DurakAction) {
        // A defence that closes the bout is held on screen before bito.
        let held = table.revealingDefense(before: next) != nil
        table = next
        moves += 1
        DurakFeedback.play(action)
        if let outcome = table.outcome {
            state = .gameOver(won: outcome != .loser(Self.playerSeat) && outcome != .draw)
        } else if table.isOut(Self.playerSeat) {
            // Out of cards with others still playing: the player can't be the durak.
            state = .gameOver(won: true)
        } else {
            if case .callBluff = action {
                scheduleBot(after: DurakTableView.callPause)
            } else {
                scheduleBot(after: held ? DurakTableView.bitoPause : .zero)
            }
        }
    }

    private func scheduleBot(after pause: Duration = .zero) {
        botTask?.cancel()
        guard state == .playing else { return }
        // A bot that spots a bluff calls it before anyone moves on.
        if let call = botCall() {
            botTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900) + pause)
                guard let self, !Task.isCancelled, self.state == .playing,
                      let next = try? self.table.applying(.callBluff(call.card), by: call.seat) else { return }
                self.commit(next, action: .callBluff(call.card))
            }
            return
        }
        guard let seat = table.turn, seat != Self.playerSeat else { return }
        botTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750) + pause)
            guard let self, !Task.isCancelled, self.state == .playing,
                  let action = DurakBot.action(for: self.table, seat: seat),
                  let next = try? self.table.applying(action, by: seat) else { return }
            self.commit(next, action: action)
        }
    }
}

extension DurakEngine {
    /// Gives each new card on the table one roll: a random bot that could
    /// call it may notice it is a bluff. The player has to spot bluffs alone.
    private func botCall() -> (seat: Int, card: Card)? {
        guard table.options.bluff else { return nil }
        var generator = SystemRandomNumberGenerator()
        let cards = table.table.flatMap { [$0.attack] + ($0.defense.map { [$0] } ?? []) }
        for card in cards where !judged.contains(card.id) {
            judged.insert(card.id)
            let bots = (1..<table.playerCount).filter { table.canCall(card, by: $0) }
            if let bot = bots.randomElement(using: &generator),
               DurakBot.notices(card, in: table, by: bot, using: &generator) {
                return (bot, card)
            }
        }
        return nil
    }
}

extension DurakEngine: ResumableGame {
    private struct Session: Codable {
        let table: DurakState
        let moves: Int
    }

    func saveSession() -> Data? {
        guard table.outcome == nil, moves > 0 else { return nil }
        return encodeSession(Session(table: table, moves: moves))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let session = decodeSession(Session.self, from: data), session.table.outcome == nil else { return false }
        botTask?.cancel()
        table = session.table
        moves = session.moves
        state = .playing
        return true
    }
}

enum DurakFeedback {
    @MainActor
    static func play(_ action: DurakAction) {
        switch action {
        case .attack, .defend, .transfer: Haptics.tap(); SoundFX.play(.card)
        case .take: Haptics.move(); SoundFX.play(.whoosh)
        case .done: Haptics.move(); SoundFX.play(.clear)
        case .callBluff: Haptics.heavy(); SoundFX.play(.hit)
        }
    }
}

// MARK: - Bot game view

struct DurakView: View {
    @State private var engine = DurakEngine()

    var body: some View {
        GameContainerView(gameID: .durak, engine: engine,
                          resultTitle: engine.isDraw ? L10n.text("Draw") : nil) {
            DurakTableView(table: engine.table,
                           seat: DurakEngine.playerSeat,
                           names: engine.names,
                           onAction: engine.play)
        }
    }
}

// MARK: - Online match

extension DurakState: OnlineGameState {
    var isFinished: Bool { outcome != nil }

    static func playFeedback(for state: DurakState) {
        if let move = state.lastMove { DurakFeedback.play(move.action) }
    }

    func result(for seat: Int, names: [String]) -> OnlineMatchResult? {
        func name(_ seat: Int) -> String { names.indices.contains(seat) ? names[seat] : "" }
        switch outcome {
        case .draw:
            return OnlineMatchResult(title: L10n.text("Draw"), message: nil, won: false, score: 50)
        case .loser(let loser) where loser == seat:
            return OnlineMatchResult(title: L10n.text("You're the durak!"), message: nil, won: false, score: 0)
        case .loser(let loser):
            return OnlineMatchResult(title: L10n.text("You Win!"), message: L10n.format("%@ is the durak!", name(loser)),
                                     won: true, score: 100 + 10 * hands.joined().count)
        case nil where isOut(seat):
            // Out of cards while the others play on: safe, so already a win.
            return OnlineMatchResult(title: L10n.text("You Win!"), message: L10n.text("You're out of cards first."),
                                     won: true, score: 100 + 10 * hands.joined().count)
        case nil:
            return nil
        }
    }
}

// MARK: - Table

/// The Durak table from `seat`'s side: the other players' hidden hands on top,
/// the deck, trump and bito pile, the bout in the middle, and the player's
/// hand below. Every card keeps its identity across zones, so dealing,
/// playing, taking and discarding show the card flying to its new place.
struct DurakTableView: View {
    let table: DurakState
    let seat: Int
    /// Every seat's name, this player's included.
    let names: [String]
    let onAction: (DurakAction) -> Void

    /// How long a defence that closes the bout stays on the table before bito.
    static let bitoPause: Duration = .milliseconds(1100)
    /// How long bots wait after a bluff call, so everyone can read who was caught.
    static let callPause: Duration = .milliseconds(1800)
    static let move = Animation.spring(response: 0.45, dampingFraction: 0.86)

    @State private var drag = CardDragController()
    @Namespace private var cards
    /// What is drawn: trails `table` while a closing defence is held in view.
    @State private var board: DurakState
    @State private var latest: DurakState
    @State private var holding = false
    /// The defender chose Transfer: the next card tapped passes the attack on.
    @State private var transferring = false

    init(table: DurakState, seat: Int, names: [String], onAction: @escaping (DurakAction) -> Void) {
        self.table = table
        self.seat = seat
        self.names = names
        self.onAction = onAction
        _board = State(initialValue: table)
        _latest = State(initialValue: table)
    }

    /// The other seats, clockwise from this player's left.
    private var opponents: [Int] { (1..<board.playerCount).map { (seat + $0) % board.playerCount } }

    private func name(_ player: Int) -> String {
        names.indices.contains(player) ? names[player] : L10n.format("Player %d", player + 1)
    }

    private var turn: Int? { holding ? nil : board.turn }
    private var myTurn: Bool { turn == seat }
    private var hand: [Card] {
        board.hands[seat].sorted {
            let lhs = board.isTrump($0), rhs = board.isTrump($1)
            if lhs != rhs { return !lhs }
            if $0.suit != $1.suit { return $0.suit.rawValue < $1.suit.rawValue }
            return $0.highValue < $1.highValue
        }
    }

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(64, (geo.size.width - 16) / 5.2)
            VStack(spacing: 14) {
                opponentsRow(width: geo.size.width, cardWidth: cardWidth)
                    .zIndex(1)
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 18) {
                        deck(cardWidth: cardWidth)
                        discardPile(cardWidth: cardWidth)
                    }
                    // Three pairs (each a card plus the overlap) must fit beside the deck.
                    let boutWidth = geo.size.width - cardWidth * 1.8 - 16
                    bout(cardWidth: min(cardWidth, (boutWidth - 20) / 3 - 14))
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
                // Dropping a hand card anywhere on the table plays it.
                .cardDropTarget(.table, drag: drag)
                statusLine
                actionButton
                handRow(width: geo.size.width, cardWidth: cardWidth * 1.1)
            }
            .cardTable(drag)
        }
        .allowsHitTesting(!holding)
        .onChange(of: table) { _, next in receive(next) }
        .onChange(of: board) { transferring = false }
    }

    /// Shows `next`, first holding a bout-closing defence on the table.
    private func receive(_ next: DurakState) {
        latest = next
        guard !holding else { return }
        if let reveal = board.revealingDefense(before: next) {
            holding = true
            withAnimation(Self.move) { board = reveal }
            Task {
                try? await Task.sleep(for: Self.bitoPause)
                holding = false
                withAnimation(Self.move) { board = latest }
            }
        } else {
            withAnimation(Self.move) { board = next }
        }
    }

    /// A card that flies between zones. Cards dropped by drag skip the flight,
    /// since the drag ghost already carried them over.
    private func flying(_ card: Card, faceUp: Bool = true, width: CGFloat, highlighted: Bool = false) -> some View {
        var shown = card
        shown.faceUp = faceUp
        return CardView(card: shown, width: width, highlighted: highlighted)
            .matchedGeometryEffect(id: card.id, in: cards)
            .transaction { if drag.landed.contains(card.id) { $0.animation = nil } }
    }

    // MARK: Opponents

    /// One hidden hand per other player. A single opponent gets large cards;
    /// with more, each gets an equal share of the width.
    private func opponentsRow(width: CGFloat, cardWidth: CGFloat) -> some View {
        let count = CGFloat(opponents.count)
        let share = (width - (count - 1) * 8) / count
        let small = min(cardWidth * 0.7, share / 2.9)
        return HStack(alignment: .top, spacing: 8) {
            ForEach(opponents, id: \.self) { player in
                opponentView(player, width: share, cardWidth: small)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func opponentView(_ player: Int, width: CGFloat, cardWidth: CGFloat) -> some View {
        let held = board.hands[player]
        let onTurn = turn == player
        // Fanned cards fit the share however many are held.
        let step = held.count > 1 ? min(cardWidth * 0.38, (width - cardWidth) / CGFloat(held.count - 1)) : 0
        return VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(name(player))
                    .font(opponents.count > 2 ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(onTurn ? GameTheme.accent : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if opponents.count <= 2 { roleBadge(for: player) }
            }
            if opponents.count > 2 { roleBadge(for: player) }
            HStack(spacing: step - cardWidth) {
                ForEach(held) { card in
                    flying(card, faceUp: false, width: cardWidth)
                }
            }
            .frame(height: cardWidth * CardView.aspectRatio)
            .opacity(board.isOut(player) ? 0.4 : 1)
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("%@ has %d cards", name(player), held.count))
    }

    /// The player's role; with many opponents only its symbol fits.
    @ViewBuilder
    private func roleBadge(for player: Int) -> some View {
        let role: (String, String, Color)? = {
            if board.isOut(player) { return (L10n.text("Out"), "checkmark", .green) }
            if board.attacker == player { return (L10n.text("Attacking"), "bolt.fill", .orange) }
            if board.defender == player { return (L10n.text("Defending"), "shield.fill", .teal) }
            return nil
        }()
        if let role {
            Group {
                if opponents.count > 2 {
                    Image(systemName: role.1).accessibilityLabel(role.0)
                } else {
                    Text(role.0)
                }
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(role.2)
            .background(role.2.opacity(0.15), in: Capsule())
        } else {
            // Keeps every opponent's cards on the same line.
            Text(" ").font(.caption2).padding(.vertical, 3)
        }
    }

    // MARK: Deck, trump and bito

    private func deck(cardWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            // The trump is the bottom card, turned face up across the stack.
            if let trump = board.deck.first {
                flying(trump, width: cardWidth)
                    .rotationEffect(.degrees(90))
                    .offset(x: cardWidth * 0.35)
            }
            ForEach(board.deck.dropFirst()) { card in
                flying(card, faceUp: false, width: cardWidth)
            }
            // Once the deck is gone (or fully dealt to six), only the trump suit is left to show.
            if board.deck.isEmpty {
                Text(board.trumpSuit.symbol)
                    .font(.system(size: cardWidth * 0.6))
                    .foregroundStyle(board.trumpSuit.isRed ? CardView.red : .primary)
                    .frame(width: cardWidth, height: cardWidth * CardView.aspectRatio)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(width: cardWidth * 1.8, height: cardWidth * CardView.aspectRatio, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Trump %@, %d cards in the deck", board.trumpSuit.symbol, board.deck.count))
    }

    /// Face-down bito pile, each card at a slight angle. Only the top cards are
    /// drawn; the rest are hidden under them anyway.
    private func discardPile(cardWidth: CGFloat) -> some View {
        let pile = Array((board.discardPile ?? []).suffix(12))
        let angles: [Double] = [-14, 9, -4, 16, -10, 5, -18, 12, -7, 3, -12, 8]
        return ZStack {
            ForEach(Array(pile.enumerated()), id: \.element.id) { index, card in
                flying(card, faceUp: false, width: cardWidth)
                    .rotationEffect(.degrees(angles[index % angles.count]))
            }
        }
        .frame(width: cardWidth * 1.8, height: cardWidth * CardView.aspectRatio)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Discarded: %d", board.discarded))
    }

    // MARK: Bout

    private func bout(cardWidth: CGFloat) -> some View {
        // Up to three pairs per row, centred in the space right of the deck.
        let columns = Array(repeating: GridItem(.fixed(cardWidth + 14), spacing: 10),
                            count: max(1, min(3, board.table.count)))
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(board.table, id: \.attack.id) { pair in
                ZStack(alignment: .topLeading) {
                    flying(pair.attack, width: cardWidth,
                           highlighted: pair.defense == nil && myTurn && board.defender == seat)
                        .onTapGesture { call(pair.attack) }
                    if let defense = pair.defense {
                        flying(defense, width: cardWidth)
                            .rotationEffect(.degrees(8))
                            .offset(x: 12, y: 14)
                            .onTapGesture { call(defense) }
                    }
                }
                .frame(width: cardWidth + 14, height: cardWidth * CardView.aspectRatio + 16, alignment: .topLeading)
            }
        }
    }

    // MARK: Status and actions

    /// Tapping someone else's card on the table calls it a bluff. Nothing
    /// shows which cards are bluffs: spotting them is up to the player.
    private func call(_ card: Card) {
        guard !holding, board.canCall(card, by: seat) else { return }
        onAction(.callBluff(card))
    }

    private var statusLine: some View {
        VStack(spacing: 4) {
            if let notice = callNotice {
                Text(notice.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(notice.caught ? Color.red : Color.orange, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            Text(status)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(myTurn ? .primary : .secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 20)
                .contentTransition(.opacity)
        }
    }

    /// How the last bluff call went, until the next move.
    private var callNotice: (text: String, caught: Bool)? {
        guard let move = board.lastMove, case .callBluff = move.action, let target = move.target else { return nil }
        if move.caught == true {
            if move.seat == seat { return (L10n.format("You caught %@ bluffing!", name(target)), true) }
            if target == seat { return (L10n.format("%@ caught you bluffing!", name(move.seat)), true) }
            return (L10n.format("%@ caught %@ bluffing!", name(move.seat), name(target)), true)
        }
        if move.seat == seat { return (L10n.text("Not a bluff: you take the table."), false) }
        return (L10n.format("Not a bluff: %@ takes the table.", name(move.seat)), false)
    }

    private var status: String {
        guard let turn else { return " " }
        if turn != seat { return L10n.format("%@ is thinking…", name(turn)) }
        if transferring { return L10n.text("Pick a card of the same rank to pass the attack on") }
        if board.defender == seat { return L10n.text("Beat the card or take") }
        if board.table.isEmpty { return L10n.text("Your move: attack") }
        return board.attacker == seat ? L10n.text("Throw in a card or press Done") : L10n.text("Throw in a card or pass")
    }

    private var canTransferNow: Bool {
        myTurn && board.defender == seat && board.hands[seat].contains(where: board.canTransfer)
    }

    @ViewBuilder
    private var actionButton: some View {
        let action: (String, DurakAction)? = {
            guard myTurn else { return nil }
            if board.defender == seat { return (L10n.text("Take"), .take) }
            if board.table.isEmpty { return nil }
            return (L10n.text(board.attacker == seat ? "Bito" : "Pass"), .done)
        }()
        HStack(spacing: 10) {
            if canTransferNow {
                Button {
                    Haptics.tap()
                    transferring.toggle()
                } label: {
                    Text(L10n.text(transferring ? "Cancel" : "Transfer"))
                        .font(.headline)
                        .foregroundStyle(transferring ? Color.primary : Color.white)
                        .frame(minWidth: 120, minHeight: 44)
                        .background(transferring ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.purple),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                if let action { onAction(action.1) }
            } label: {
                Text(action?.0 ?? " ")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(minWidth: canTransferNow ? 120 : 140, minHeight: 44)
                    .background(GameTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(action == nil || transferring ? 0 : 1)
            .disabled(action == nil || transferring)
        }
    }

    // MARK: Hand

    private func handRow(width: CGFloat, cardWidth: CGFloat) -> some View {
        let cards = hand
        let step = cards.count > 1 ? min(cardWidth + 6, (width - cardWidth) / CGFloat(cards.count - 1)) : 0
        return HStack(spacing: step - cardWidth) {
            ForEach(cards) { card in
                // Fair moves glow and rise; with bluffing on, any other card can still be played.
                let fair = myTurn && isFair(card)
                let usable = myTurn && isUsable(card)
                flying(card, width: cardWidth, highlighted: fair)
                    .cardDraggable(card, drag: drag, enabled: usable,
                                   begin: { usable ? [card] : nil },
                                   canDrop: { $0 == .table },
                                   drop: { pile in
                                       guard pile == .table, myTurn, isUsable(card) else { return false }
                                       play(card)
                                       return true
                                   })
                    .offset(y: fair ? -10 : 0)
                    .opacity(myTurn && !usable ? 0.6 : 1)
                    .onTapGesture { drag.tap { play(card) } }
                    .accessibilityAddTraits(usable ? .isButton : [])
            }
        }
        .frame(width: width, height: cardWidth * CardView.aspectRatio + 14, alignment: .bottom)
    }

    private var defending: Bool { board.defender == seat && !board.table.isEmpty }

    /// Within the rules.
    private func isFair(_ card: Card) -> Bool {
        if transferring { return board.canTransfer(with: card) }
        return defending ? board.canDefend(with: card) : board.canAttack(with: card)
    }

    /// Fair, or a bluff when bluffing is on.
    private func isUsable(_ card: Card) -> Bool {
        transferring ? board.canTransfer(with: card) : board.canPlay(card)
    }

    private func play(_ card: Card) {
        guard myTurn, isUsable(card) else {
            if myTurn { Haptics.error(); SoundFX.play(.wrong) }
            return
        }
        if transferring {
            transferring = false
            onAction(.transfer(card))
        } else {
            onAction(defending ? .defend(card) : .attack(card))
        }
    }
}
