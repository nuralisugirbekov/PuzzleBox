import SwiftUI
import Observation
import FirebaseAuth
import FirebaseFirestore

// Online two-player matches shared by every game with `supportsFriends`.
// The table lives in `matches/{id}` as JSON; each move is applied with the
// game's own rules on the mover's device and written in a transaction
// guarded by `version` (see docs/friends.md).

/// How a finished online match ended, from one player's side.
struct OnlineMatchResult: Equatable {
    let title: String
    let message: String?
    let won: Bool
    let score: Int
}

/// A turn-based table for several seats that can be played online.
protocol OnlineGameState: Codable, Equatable {
    associatedtype Action: Codable
    func applying(_ action: Action, by seat: Int) throws -> Self
    var isFinished: Bool { get }
    /// `seat` has left the game (out of cards, knocked out) while others play on.
    func isOut(_ seat: Int) -> Bool
    /// Sound and haptics for the move that produced `state`.
    @MainActor static func playFeedback(for state: Self)
    /// The result for `seat`, once it is decided; `names` holds every seat's name.
    func result(for seat: Int, names: [String]) -> OnlineMatchResult?
    /// Whether the table waits for this player's move to be written before
    /// taking the next one. Turn-based games do; a race, where each player
    /// keeps playing their own board, doesn't.
    static var locksWhileSending: Bool { get }
}

extension OnlineGameState {
    static var locksWhileSending: Bool { true }
}

/// The opening table of a new match for `players` seats, written by the host.
func onlineInitialState(for game: GameID, players: Int, options: DurakOptions = DurakOptions()) -> String {
    func encode(_ state: some Encodable) -> String {
        (try? JSONEncoder().encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    switch game {
    case .durak: return encode(DurakState.deal(players: players, options: options))
    case .hangman: return encode(HangmanState.newGame(language: HangmanLanguage(app: L10n.language), players: players))
    case .battleship: return encode(BattleshipState.newGame())
    case .gemsBlitz: return encode(Match3RaceState.newGame(players: players))
    default: return ""
    }
}

/// How a match's table travels between the players: Firestore for online
/// matches, a direct Bluetooth / Wi-Fi link for nearby ones. Tables are the
/// game state as JSON; the game's own rules are applied by the screen.
@MainActor
protocol MatchTransport: AnyObject, Observable {
    var game: GameID { get }
    var stateJSON: String? { get }
    /// This player's seat, once known.
    var seat: Int? { get }
    /// Every seat's name, in seat order.
    var names: [String] { get }
    /// The other players' names before the table arrives.
    var fallbackOpponents: String { get }
    /// Another player who left mid-game, which ends it for everyone.
    var leaverName: String? { get }
    var isSending: Bool { get }
    func start()
    func stop()
    /// Shares the table after this player's move, already checked by the rules.
    func send(_ encoded: String)
    /// Leaving an unfinished match concedes it.
    func forfeit()
}

/// The screen for an online match of `match.game`.
@MainActor
@ViewBuilder
func onlineGameView(for match: MatchRef) -> some View {
    matchView(for: match.game, transport: OnlineMatchSession(ref: match))
}

/// The match screen for `game`, whichever way the table travels.
@MainActor
@ViewBuilder
func matchView(for game: GameID, transport: any MatchTransport) -> some View {
    switch game {
    case .gemsBlitz:
        OnlineMatchScreen<Match3RaceState, Match3RaceView>(transport: transport) { table, seat, names, act in
            Match3RaceView(table: table, seat: seat, names: names, onAction: act)
        }
    case .battleship:
        OnlineMatchScreen<BattleshipState, BattleshipTableView>(transport: transport) { table, seat, names, act in
            BattleshipTableView(table: table, seat: seat, names: names, onAction: act)
        }
    case .hangman:
        OnlineMatchScreen<HangmanState, HangmanTableView>(transport: transport) { table, seat, names, act in
            HangmanTableView(table: table, seat: seat, names: names, onAction: act)
        }
    default:
        OnlineMatchScreen<DurakState, DurakTableView>(transport: transport) { table, seat, names, act in
            DurakTableView(table: table, seat: seat, names: names, onAction: act)
        }
    }
}

// MARK: - Session

/// Live state of one online match, as the JSON stored in Firestore; the
/// screen decodes it with the game's own type. A stale client can never
/// overwrite a newer table: its transaction fails and the listener puts the
/// real one back.
///
/// Deliberately not generic: the Swift 6.3 optimizer crashes on the deinit of
/// a generic main-actor class (Release builds only).
@MainActor
@Observable
final class OnlineMatchSession: MatchTransport {
    let ref: MatchRef

    var game: GameID { ref.game }
    var fallbackOpponents: String { ref.opponentName }
    private(set) var stateJSON: String?
    private(set) var seat: Int?
    /// Every seat's uid and name, in seat order.
    private(set) var players: [String] = []
    private(set) var names: [String] = []
    /// The uid that left the match early, if any.
    private(set) var forfeitedBy: String?
    private(set) var error: String?
    private(set) var isSending = false

    @ObservationIgnored private var version = 0
    @ObservationIgnored private var listener: ListenerRegistration?
    @ObservationIgnored private lazy var doc = Firestore.firestore().collection("matches").document(ref.id)

    init(ref: MatchRef) {
        self.ref = ref
    }

    /// The name of another player who left mid-game, which ends it for everyone.
    var leaverName: String? {
        guard let forfeitedBy, let uid = Auth.auth().currentUser?.uid, forfeitedBy != uid,
              let index = players.firstIndex(of: forfeitedBy) else { return nil }
        return names.indices.contains(index) ? names[index] : ""
    }

    func start() {
        guard listener == nil else { return }
        listener = doc.addSnapshotListener { [weak self] snapshot, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error { self.error = error.localizedDescription; return }
                guard let data = snapshot?.data() else { return }
                let uid = Auth.auth().currentUser?.uid
                self.players = data["players"] as? [String] ?? []
                self.seat = self.players.firstIndex { $0 == uid }
                self.names = data["names"] as? [String] ?? []
                self.forfeitedBy = data["forfeit"] as? String
                self.version = data["version"] as? Int ?? 0
                if let state = data["state"] as? String, state != self.stateJSON {
                    self.stateJSON = state
                }
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    /// Writes the table after this player's move, already checked by the rules.
    func send(_ encoded: String) {
        guard !isSending else { return }
        // Show the move at once; the listener confirms or corrects it.
        stateJSON = encoded
        isSending = true
        let expected = version
        let doc = doc
        Task {
            do {
                _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
                    do {
                        let snapshot = try transaction.getDocument(doc)
                        guard snapshot.data()?["version"] as? Int == expected else {
                            errorPointer?.pointee = NSError(domain: "OnlineMatch", code: 409)
                            return nil
                        }
                        transaction.updateData(["state": encoded, "version": expected + 1,
                                                "updatedAt": FieldValue.serverTimestamp()], forDocument: doc)
                    } catch let error as NSError {
                        errorPointer?.pointee = error
                    }
                    return nil
                }
            } catch {
                // The listener's snapshot puts the real table back.
                self.error = error.localizedDescription
            }
            self.isSending = false
        }
    }

    /// Leaving an unfinished match concedes it.
    func forfeit() {
        guard forfeitedBy == nil, let uid = Auth.auth().currentUser?.uid else { return }
        doc.updateData(["forfeit": uid])
    }
}

// MARK: - Screen

/// A match against a friend: the shared table, without pause or restart.
struct OnlineMatchScreen<Match: OnlineGameState, Table: View>: View {
    /// Builds the table from the state, this player's seat and every seat's name.
    let table: (Match, Int, [String], @escaping (Match.Action) -> Void) -> Table

    @State private var session: any MatchTransport
    @State private var confirmingLeave = false
    @State private var recorded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(StatsStore.self) private var stats

    init(transport: any MatchTransport, table: @escaping (Match, Int, [String], @escaping (Match.Action) -> Void) -> Table) {
        self.table = table
        _session = State(initialValue: transport)
    }

    private var game: GameID { session.game }

    private var current: Match? {
        session.stateJSON?.data(using: .utf8).flatMap { try? JSONDecoder().decode(Match.self, from: $0) }
    }

    /// Applies this player's move with the game's rules, then sends the new table.
    private func play(_ action: Match.Action) {
        guard let seat = session.seat, let state = current,
              let next = try? state.applying(action, by: seat),
              let encoded = (try? JSONEncoder().encode(next)).flatMap({ String(data: $0, encoding: .utf8) })
        else { return }
        session.send(encoded)
    }

    /// The other players' names, for the header.
    private var opponentNames: String {
        guard let seat = session.seat, session.names.count > 1 else { return session.fallbackOpponents }
        return session.names.enumerated().filter { $0.offset != seat }.map(\.element).joined(separator: ", ")
    }

    private var result: OnlineMatchResult? {
        guard let state = current, let seat = session.seat else { return nil }
        if let decided = state.result(for: seat, names: session.names) { return decided }
        // Someone still in the game left: it can't go on, and the rest win.
        if let leaver = session.leaverName {
            return OnlineMatchResult(title: L10n.text("You Win!"), message: L10n.format("%@ left the game.", leaver),
                                     won: true, score: 100)
        }
        return nil
    }

    /// The game's toy world, when it has one.
    private var palette: ToyPalette? {
        switch game {
        case .durak: ToyDurak.palette
        case .hangman: ToyHangman.palette
        case .battleship: ToyBattleship.palette
        default: nil
        }
    }

    var body: some View {
        ZStack {
            if let palette {
                palette.backdrop.ignoresSafeArea()
            } else {
                GameTheme.background.ignoresSafeArea()
            }
            VStack(spacing: 16) {
                header
                if let state = current, let seat = session.seat {
                    table(state, seat, session.names, play)
                        .allowsHitTesting((!Match.locksWhileSending || !session.isSending) && result == nil)
                } else {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            .padding()

            if let result {
                OnlineResultCard(title: result.title, message: result.message) { dismiss() }
            }
        }
        .foregroundStyle(palette?.ink ?? GameTheme.ink)
        .tint(palette?.accent ?? GameTheme.accent)
        .environment(\.toyStyle, palette?.style)
        .animation(.spring(duration: 0.35), value: result)
        .onAppear {
            session.start()
            AppAnalytics.screen("game_\(game.rawValue)_online")
        }
        .onDisappear { session.stop() }
        .onChange(of: current) { old, new in
            // Every move after the first snapshot, ours and the opponent's.
            if old != nil, let new { Match.playFeedback(for: new) }
        }
        .onChange(of: result) { _, result in
            guard let result, !recorded else { return }
            recorded = true
            stats.record(game, score: result.score)
            if result.won { Haptics.success(); SoundFX.play(.win) } else { Haptics.error(); SoundFX.play(.lose) }
            AppAnalytics.log("online_match_finished", parameters: ["game_id": game.rawValue, "won": result.won])
        }
        .alert(L10n.text("Leave the game?"), isPresented: $confirmingLeave) {
            Button(L10n.text("Leave"), role: .destructive) {
                if let state = current, let seat = session.seat, !state.isFinished, !state.isOut(seat) {
                    session.forfeit()
                }
                dismiss()
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("Leaving now counts as a loss."))
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let palette {
                ToyIconButton(symbol: "chevron.left", label: L10n.text("Back"), color: palette.card, ink: palette.ink) {
                    leave()
                }
            } else {
                Button(action: leave) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Back"))
            }
            Spacer(minLength: 0)
        }
        .overlay {
            VStack(spacing: 0) {
                Text(game.info.title).font(.system(.headline, design: .rounded).weight(.heavy))
                Text(L10n.format("vs %@", opponentNames))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .opacity(0.65)
            }
            .lineLimit(1)
            .padding(.horizontal, 60)
        }
    }

    private func leave() {
        if result == nil && current != nil { confirmingLeave = true } else { dismiss() }
    }
}

private struct OnlineResultCard: View {
    let title: String
    let message: String?
    let home: () -> Void
    @Environment(\.toyStyle) private var toy

    var body: some View {
        if let toy { toyCard(toy) } else { plainCard }
    }

    /// The result in the game's own clay, like the solo games' windows.
    private func toyCard(_ toy: ToyStyle) -> some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea()
            (toy.haze ?? .clear).opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "flag.pattern.checkered")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .padding(.bottom, 4)
                    .background { ToyBlock(color: toy.accent, shape: Circle(), lip: 4) }
                Text(title).font(.system(.title2, design: .rounded).weight(.heavy))
                if let message {
                    Text(message).font(.system(.subheadline, design: .rounded)).opacity(0.7)
                }
                Button(action: home) {
                    Label(L10n.text("Home"), systemImage: "house.fill")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ToyPressStyle(color: toy.accent, lip: 4))
                .padding(.top, 4)
            }
            .foregroundStyle(toy.ink)
            .multilineTextAlignment(.center)
            .padding(20)
            .padding(.bottom, 8)
            .frame(width: 300)
            .background { ToyBlock(color: toy.card, shape: RoundedRectangle(cornerRadius: 34, style: .continuous), lip: 8) }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }

    private var plainCard: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "flag.pattern.checkered")
                    .font(.system(size: 41, weight: .semibold))
                    .foregroundStyle(GameTheme.accent)
                Text(title).font(.title2.weight(.semibold))
                if let message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                }
                Button(action: home) {
                    Label(L10n.text("Home"), systemImage: "house.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(GameTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .multilineTextAlignment(.center)
            .padding(20)
            .frame(width: 300)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
    }
}
