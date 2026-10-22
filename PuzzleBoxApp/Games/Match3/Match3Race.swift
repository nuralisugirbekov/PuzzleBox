import SwiftUI

// Gems Blitz against friends: a race for points. Every player gets the same
// starting boards (one shared seed) and plays their own Blitz run until
// their clock runs out. Scores travel as reports in the shared table, so
// everyone sees the standings live; once every run is over, the highest
// score takes first place.

struct Match3RaceState: OnlineGameState {
    static let playerRange = 2...4

    enum Action: Codable, Equatable {
        /// A player's running score and level; `finished` once their clock ran out.
        case report(score: Int, level: Int, finished: Bool)
    }

    enum RuleError: Error, Equatable {
        case noSuchSeat, alreadyFinished
    }

    let seed: UInt64
    var scores: [Int]
    var levels: [Int]
    var finished: [Bool]

    static func newGame(players: Int, seed: UInt64 = .random(in: 0...UInt64.max)) -> Match3RaceState {
        Match3RaceState(seed: seed, scores: Array(repeating: 0, count: players),
                        levels: Array(repeating: 1, count: players),
                        finished: Array(repeating: false, count: players))
    }

    func applying(_ action: Action, by seat: Int) throws -> Match3RaceState {
        guard scores.indices.contains(seat) else { throw RuleError.noSuchSeat }
        guard !finished[seat] else { throw RuleError.alreadyFinished }
        var next = self
        switch action {
        case .report(let score, let level, let done):
            // Reports can arrive out of order; a run's score and level only grow.
            next.scores[seat] = max(scores[seat], score)
            next.levels[seat] = max(levels[seat], level)
            next.finished[seat] = done
        }
        return next
    }

    var isFinished: Bool { finished.allSatisfy { $0 } }

    /// A finished run may leave without conceding: its score stands.
    func isOut(_ seat: Int) -> Bool { finished.indices.contains(seat) && finished[seat] }

    /// Reports carry no news worth a sound; each player hears their own board.
    static func playFeedback(for state: Match3RaceState) {}

    /// 1 for the best score; equal scores share a place.
    func place(of seat: Int) -> Int {
        1 + scores.filter { $0 > scores[seat] }.count
    }

    /// Seats from first place to last.
    var standings: [Int] {
        scores.indices.sorted { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
    }

    func result(for seat: Int, names: [String]) -> OnlineMatchResult? {
        guard isFinished, scores.indices.contains(seat) else { return nil }
        let place = place(of: seat)
        let leader = standings[0]
        let leaderName = names.indices.contains(leader) ? names[leader] : ""
        let title = place == 1 ? L10n.text("You Win!") : L10n.format("Place %d", place)
        let message = place == 1
            ? L10n.format("Your score: %d", scores[seat])
            : L10n.format("%@ won with %d", leaderName, scores[leader])
        return OnlineMatchResult(title: title, message: message, won: place == 1, score: scores[seat])
    }
}

// MARK: - Screen

/// One player's run in a race: their own Blitz board, with everyone's
/// standing above it.
struct Match3RaceView: View {
    let table: Match3RaceState
    let seat: Int
    let names: [String]
    let onAction: (Match3RaceState.Action) -> Void

    @State private var engine: Match3Engine

    init(table: Match3RaceState, seat: Int, names: [String], onAction: @escaping (Match3RaceState.Action) -> Void) {
        self.table = table
        self.seat = seat
        self.names = names
        self.onAction = onAction
        _engine = State(initialValue: Match3Engine(mode: .blitz, seed: table.seed))
    }

    private var runOver: Bool {
        if case .gameOver = engine.state { true } else { false }
    }

    /// What the shared table should say about this run.
    private var report: Match3RaceState.Action {
        .report(score: engine.score, level: engine.level.number, finished: runOver)
    }

    /// The table is behind this run, so a report is due.
    private var reportDue: Bool {
        guard table.scores.indices.contains(seat), !table.finished[seat] else { return false }
        return table.scores[seat] < engine.score || table.levels[seat] < engine.level.number || runOver
    }

    var body: some View {
        VStack(spacing: 14) {
            standings
            Match3GoalBar(engine: engine)
            ZStack {
                Match3BoardView(engine: engine)
                    .allowsHitTesting(engine.state == .playing)
                if runOver && !table.isFinished {
                    waitingCard
                }
            }
        }
        .task { await engine.runClock() }
        // Reports go out as the score changes and the run ends, and are
        // retried every couple of seconds in case one was lost to a clash.
        .task {
            while !Task.isCancelled {
                if reportDue { onAction(report) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .onChange(of: engine.score) { if reportDue { onAction(report) } }
        .onChange(of: runOver) { if reportDue { onAction(report) } }
    }

    private var standings: some View {
        VStack(spacing: 6) {
            ForEach(table.standings, id: \.self) { player in
                let isMe = player == seat
                let score = isMe ? max(engine.score, table.scores[player]) : table.scores[player]
                HStack(spacing: 10) {
                    Text(verbatim: "\(table.place(of: player))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 22)
                    Text(names.indices.contains(player) ? names[player] : "")
                        .font(.subheadline.weight(isMe ? .bold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if table.finished[player] {
                        Image(systemName: "flag.checkered").foregroundStyle(.secondary)
                    } else {
                        Text(L10n.format("Level %d", table.levels[player]))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(score, format: .number)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isMe ? AnyShapeStyle(GameTheme.accent.opacity(0.15)) : AnyShapeStyle(GameTheme.surface),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.snappy, value: table.standings)
    }

    private var waitingCard: some View {
        VStack(spacing: 8) {
            Text(L10n.format("Your score: %d", engine.score)).font(.headline)
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.text("Waiting for the others to finish…")).font(.subheadline)
            }
        }
        .padding(20)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .transition(.scale.combined(with: .opacity))
    }
}
