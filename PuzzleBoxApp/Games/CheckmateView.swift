import SwiftUI
import Observation

// MARK: - Engine

enum PieceType {
    case pawn, knight, bishop, rook, queen, king

    init?(fenChar: Character) {
        switch fenChar {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }

    func glyph(isWhite: Bool) -> String {
        // Text presentation prevents the pawn from becoming an un-tintable emoji.
        switch self {
        case .pawn: return (isWhite ? "♙" : "♟") + "\u{FE0E}"
        case .knight: return (isWhite ? "♘" : "♞") + "\u{FE0E}"
        case .bishop: return (isWhite ? "♗" : "♝") + "\u{FE0E}"
        case .rook: return (isWhite ? "♖" : "♜") + "\u{FE0E}"
        case .queen: return (isWhite ? "♕" : "♛") + "\u{FE0E}"
        case .king: return (isWhite ? "♔" : "♚") + "\u{FE0E}"
        }
    }
}

struct ChessPiece {
    let isWhite: Bool
    let type: PieceType
}

struct ChessPuzzle {
    let title: String
    let fen: String
    /// UCI moves: user, (bot reply, user)*. A fifth character specifies promotion.
    let line: [String]
    /// All validated mating moves for a one-move puzzle, preferred promotion first.
    var solutions: [String] = []
}

@MainActor
@Observable
final class CheckmateEngine: GameEngine {
    static let durations = [30, 60, 120]
    private(set) var hasStarted = false

    private static var fallbackPuzzles: [ChessPuzzle] { [
        ChessPuzzle(title: L10n.text("Mate in 1"), fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w", line: ["e1e8"]),
        ChessPuzzle(title: L10n.text("Mate in 1"), fen: "6k1/5p1p/7Q/8/8/8/1B3PPP/6K1 w", line: ["h6g7"]),
        ChessPuzzle(title: L10n.text("Mate in 1"), fen: "6rk/6pp/8/6N1/8/8/8/6K1 w", line: ["g5f7"]),
        ChessPuzzle(title: L10n.text("Mate in 1"), fen: "3k4/R7/8/8/8/8/8/1R4K1 w", line: ["b1b8"]),
        ChessPuzzle(title: L10n.text("Mate in 1"),
                    fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w",
                    line: ["h5f7"]),
        // Smothered mate: Qg8+ forces ...Rxg8 (the knight guards g8), then Nf7#.
        ChessPuzzle(title: L10n.text("Mate in 2"), fen: "5r1k/6pp/4Q2N/8/8/8/8/6K1 w",
                    line: ["e6g8", "f8g8", "h6f7"]),
        ChessPuzzle(title: L10n.text("Mate in 2"), fen: "3k4/8/R7/1R6/8/8/8/6K1 w",
                    line: ["a6a7", "d8e8", "b5b8"]),
    ] }

    private(set) var puzzles: [ChessPuzzle] = []
    private var roundToken = UUID()

    /// Index 0 = a8 (top-left), row-major toward h1.
    private(set) var board: [ChessPiece?] = []
    private(set) var puzzleIndex = 0
    private(set) var attempts = 0
    private(set) var step = 0
    private(set) var message = ""
    private(set) var hasMoveError = false
    private(set) var score = 0
    private(set) var awaitingBot = false
    var selected: Int?
    private(set) var targets: Set<Int> = []
    private(set) var solvedCount = 0
    /// Mates found on the first try in a row; each adds a bonus.
    private(set) var streak = 0
    /// The piece a hint points at, for the current puzzle.
    private(set) var hintSquare: Int?
    private(set) var lastMove: (from: Int, to: Int)?
    /// Bumped on each solve so the view can show the time bonus.
    private(set) var bonusFlash = 0
    static let timeBonus: TimeInterval = 5
    private(set) var remainingTime: TimeInterval = 30
    private var clockAnchor: TimeInterval?
    private var clockActive = false
    var secondsLeft: Int { Int(ceil(remainingTime)) }

    var state: GameState = .playing {
        willSet {
            if state == .playing { consumeElapsedTime() }
        }
        didSet {
            clockAnchor = state == .playing && clockActive && hasStarted
                ? ProcessInfo.processInfo.systemUptime : nil
        }
    }

    private func consumeElapsedTime() {
        guard hasStarted, let anchor = clockAnchor else { return }
        let now = ProcessInfo.processInfo.systemUptime
        remainingTime = max(0, remainingTime - (now - anchor))
        clockAnchor = now
    }

    func setClockActive(_ active: Bool) {
        if state == .playing { consumeElapsedTime() }
        clockActive = active
        clockAnchor = active && hasStarted && state == .playing ? ProcessInfo.processInfo.systemUptime : nil
        tick()
    }

    func tick() {
        guard hasStarted, state == .playing else { return }
        consumeElapsedTime()
        if remainingTime <= 0 {
            roundToken = UUID()
            selected = nil
            targets = []
            awaitingBot = false
            state = .gameOver(won: true)
        }
    }

    var puzzle: ChessPuzzle { puzzles[puzzleIndex] }

    init() { restart() }

    func start(seconds: Int) {
        guard Self.durations.contains(seconds), !hasStarted else { return }
        remainingTime = TimeInterval(seconds)
        hasStarted = true
        clockAnchor = clockActive ? ProcessInfo.processInfo.systemUptime : nil
        AppAnalytics.log("chess_challenge_started", parameters: ["duration_seconds": seconds])
    }

    func restart() {
        hasStarted = false
        roundToken = UUID()
        let series = ChessPuzzleLibrary.randomSeries(count: Int.max)
        puzzles = series.isEmpty ? Self.fallbackPuzzles.filter { $0.line.count == 1 }.shuffled() : series
        puzzleIndex = 0
        score = 0
        solvedCount = 0
        streak = 0
        clockAnchor = nil
        remainingTime = 30
        state = .playing
        loadPuzzle()
    }

    /// A puzzle with the busiest white piece picked up, for the Home preview.
    /// The clock never starts and nothing is saved.
    func showcase() {
        restart()
        let best = board.indices
            .filter { board[$0]?.isWhite == true }
            .map { ($0, legalMoves(from: $0)) }
            .max { $0.1.count < $1.1.count }
        if let best {
            selected = best.0
            targets = best.1
        }
    }

    private func loadPuzzle() {
        hasMoveError = false
        board = Self.parseFEN(puzzle.fen)
        step = 0
        attempts = 0
        selected = nil
        targets = []
        awaitingBot = false
        hintSquare = nil
        lastMove = nil
        message = L10n.text("White to move — find the mate!")
    }

    /// Highlights the piece that starts the winning move; the mate is then worth half.
    func hint() {
        tick()
        guard hasStarted, state == .playing, !awaitingBot, hintSquare == nil,
              let move = acceptedMoves.compactMap({ Self.parseMove($0) }).first else { return }
        hintSquare = move.from
        streak = 0
        Haptics.tap(); SoundFX.play(.tick)
    }

    private static func parseFEN(_ fen: String) -> [ChessPiece?] {
        var board = [ChessPiece?](repeating: nil, count: 64)
        guard let placement = fen.split(separator: " ").first else { return board }
        var index = 0
        for ch in placement where index < 64 {
            if ch == "/" { continue }
            if let empty = ch.wholeNumberValue, (1...8).contains(empty) {
                index += empty
            } else if let type = PieceType(fenChar: Character(ch.lowercased())) {
                board[index] = ChessPiece(isWhite: ch.isUppercase, type: type)
                index += 1
            }
        }
        return board
    }

    private static func squareIndex(_ file: Character, _ rank: Character) -> Int? {
        guard let f = "abcdefgh".firstIndex(of: file), let r = rank.wholeNumberValue,
              (1...8).contains(r) else { return nil }
        let col = "abcdefgh".distance(from: "abcdefgh".startIndex, to: f)
        return (8 - r) * 8 + col
    }

    private static func parseMove(_ move: String) -> (from: Int, to: Int, promotion: PieceType?)? {
        let chars = Array(move)
        guard chars.count == 4 || chars.count == 5,
              let from = squareIndex(chars[0], chars[1]),
              let to = squareIndex(chars[2], chars[3]) else { return nil }
        let promotion: PieceType?
        if chars.count == 5 {
            guard "qrbn".contains(chars[4]), let type = PieceType(fenChar: chars[4]) else { return nil }
            promotion = type
        } else {
            promotion = nil
        }
        return (from, to, promotion)
    }

    func tap(_ square: Int) {
        tick()
        guard clockActive, hasStarted else { return }
        guard state == .playing, !awaitingBot, board.indices.contains(square) else { return }
        if let sel = selected, targets.contains(square) {
            tryMove(from: sel, to: square)
            return
        }
        if let piece = board[square], piece.isWhite {
            hasMoveError = false
            message = L10n.text("White to move — find the mate!")
            selected = square
            targets = legalMoves(from: square)
            Haptics.tap(); SoundFX.play(.tap)
        } else {
            if selected != nil {
                reportMoveError(L10n.text("Illegal move — choose a highlighted square"))
                return
            }
            selected = nil
            targets = []
        }
    }

    private func reportMoveError(_ text: String) {
        attempts += 1
        hasMoveError = true
        message = text
        Haptics.error(); SoundFX.play(.wrong)
    }

    private var acceptedMoves: [String] {
        guard puzzle.line.indices.contains(step) else { return [] }
        if step == 0, puzzle.line.count == 1 {
            return [puzzle.line[0]] + puzzle.solutions
        }
        return [puzzle.line[step]]
    }

    private func tryMove(from: Int, to: Int) {
        guard state == .playing, !awaitingBot,
              board.indices.contains(from), board.indices.contains(to),
              board[from]?.isWhite == true,
              legalMoves(from: from).contains(to),
              puzzle.line.indices.contains(step) else { return }
        selected = nil
        targets = []
        guard let solution = acceptedMoves.compactMap({ Self.parseMove($0) })
            .first(where: { $0.from == from && $0.to == to }) else {
            let previousBoard = board
            let token = roundToken
            awaitingBot = true
            // Show the attempted move, including captures and pawn promotion.
            let promotion: PieceType? = board[from]?.type == .pawn && to / 8 == 0 ? .queen : nil
            apply(from: from, to: to, promotion: promotion)
            reportMoveError(L10n.text("Not the winning move — try again"))
            Task {
                do { try await Task.sleep(for: .milliseconds(800)) }
                catch { return }
                guard token == roundToken else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    // Restore the whole position so captured pieces return too.
                    board = previousBoard
                    lastMove = nil
                }
                awaitingBot = false
            }
            return
        }

        hasMoveError = false
        apply(from: from, to: to, promotion: solution.promotion)
        step += 1
        Haptics.move(); SoundFX.play(.place)

        if step == puzzle.line.count {
            puzzleSolved()
        } else {
            // Black's stored reply, then back to the user.
            awaitingBot = true
            message = L10n.text("Black replies…")
            let token = roundToken
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                guard token == roundToken else { return }
                guard puzzle.line.indices.contains(step),
                      let reply = Self.parseMove(puzzle.line[step]),
                      board[reply.from]?.isWhite == false else { return }
                apply(from: reply.from, to: reply.to, promotion: reply.promotion)
                step += 1
                awaitingBot = false
                message = L10n.text("Now finish it — mate!")
            }
        }
    }

    private func apply(from: Int, to: Int, promotion: PieceType?) {
        guard let piece = board[from] else { return }
        lastMove = (from, to)
        withAnimation(.easeInOut(duration: 0.2)) {
            // En passant: a diagonal pawn move to an empty square removes the pawn beside it.
            if piece.type == .pawn, from % 8 != to % 8, board[to] == nil {
                board[(from / 8) * 8 + to % 8] = nil
            }
            if piece.type == .king, abs(from % 8 - to % 8) == 2 {
                let rookFrom = (from / 8) * 8 + (to > from ? 7 : 0)
                let rookTo = to > from ? to - 1 : to + 1
                board[rookTo] = board[rookFrom]
                board[rookFrom] = nil
            }
            // The dataset specifies the mating promotion, including underpromotions.
            board[to] = ChessPiece(isWhite: piece.isWhite, type: promotion ?? piece.type)
            board[from] = nil
        }
    }

    private func puzzleSolved() {
        consumeElapsedTime()
        awaitingBot = true
        solvedCount += 1
        // First-try mates build a streak; hints halve the reward.
        if attempts == 0 && hintSquare == nil { streak += 1 } else { streak = 0 }
        score += (hintSquare == nil ? 100 : 50) + max(0, streak - 1) * 25
        remainingTime += Self.timeBonus
        bonusFlash += 1
        message = L10n.text("Checkmate! 🎉")
        Haptics.success(); SoundFX.play(.clear)
        let token = roundToken
        Task {
            // Keep the final position visible before loading the next puzzle.
            do { try await Task.sleep(for: .milliseconds(1500)) }
            catch { return }
            guard token == roundToken else { return }
            consumeElapsedTime()
            puzzleIndex += 1
            if puzzleIndex >= puzzles.count {
                puzzles.shuffle()
                puzzleIndex = 0
            }
            loadPuzzle()
        }
    }

    /// Move hints exclude captures of the king and moves exposing our own king.
    private func legalMoves(from square: Int) -> Set<Int> {
        guard board.indices.contains(square), let piece = board[square], piece.isWhite else { return [] }
        return Set(pseudoMoves(from: square).filter { destination in
            guard board[destination]?.type != .king else { return false }
            var position = board
            if piece.type == .pawn, square % 8 != destination % 8, position[destination] == nil {
                position[(square / 8) * 8 + destination % 8] = nil
            }
            if piece.type == .king, abs(square % 8 - destination % 8) == 2 {
                let intermediate = square + (destination > square ? 1 : -1)
                guard !Self.isAttacked(square, byWhite: false, in: position) else { return false }
                position[square] = nil
                position[intermediate] = piece
                guard !Self.isAttacked(intermediate, byWhite: false, in: position) else { return false }
                position[intermediate] = nil
                let rookFrom = (square / 8) * 8 + (destination > square ? 7 : 0)
                let rookTo = destination > square ? destination - 1 : destination + 1
                position[rookTo] = position[rookFrom]
                position[rookFrom] = nil
            }
            position[destination] = piece
            position[square] = nil
            guard let king = position.firstIndex(where: { $0?.isWhite == true && $0?.type == .king }) else {
                return false
            }
            return !Self.isAttacked(king, byWhite: false, in: position)
        })
    }

    /// Attack maps intentionally include pinned pieces and pawn attacks on empty squares.
    private static func isAttacked(_ square: Int, byWhite: Bool, in position: [ChessPiece?]) -> Bool {
        let targetRow = square / 8, targetCol = square % 8
        for (source, occupant) in position.enumerated() {
            guard let piece = occupant, piece.isWhite == byWhite else { continue }
            let row = source / 8, col = source % 8
            let dr = targetRow - row, dc = targetCol - col
            switch piece.type {
            case .pawn:
                if dr == (byWhite ? -1 : 1) && abs(dc) == 1 { return true }
            case .knight:
                if (abs(dr) == 2 && abs(dc) == 1) || (abs(dr) == 1 && abs(dc) == 2) { return true }
            case .king:
                if max(abs(dr), abs(dc)) == 1 { return true }
            case .bishop, .rook, .queen:
                let diagonal = abs(dr) == abs(dc) && dr != 0
                let straight = (dr == 0) != (dc == 0)
                guard (piece.type != .rook && diagonal) || (piece.type != .bishop && straight) else { continue }
                let rowStep = dr == 0 ? 0 : (dr > 0 ? 1 : -1)
                let colStep = dc == 0 ? 0 : (dc > 0 ? 1 : -1)
                var r = row + rowStep, c = col + colStep
                var blocked = false
                while r != targetRow || c != targetCol {
                    if position[r * 8 + c] != nil { blocked = true; break }
                    r += rowStep
                    c += colStep
                }
                if !blocked { return true }
            }
        }
        return false
    }

    /// Candidate destinations, filtered for king safety by legalMoves(from:).
    private func pseudoMoves(from square: Int) -> Set<Int> {
        guard let piece = board[square] else { return [] }
        let row = square / 8, col = square % 8
        var out = Set<Int>()

        // Adds one square; returns true when a sliding ray may continue.
        func add(_ r: Int, _ c: Int) -> Bool {
            guard (0..<8).contains(r), (0..<8).contains(c) else { return false }
            let target = r * 8 + c
            if let occupant = board[target] {
                if occupant.isWhite != piece.isWhite { out.insert(target) }
                return false
            }
            out.insert(target)
            return true
        }

        func ray(_ dr: Int, _ dc: Int) {
            var r = row + dr, c = col + dc
            while add(r, c) { r += dr; c += dc }
        }

        switch piece.type {
        case .knight:
            for (dr, dc) in [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)] {
                _ = add(row + dr, col + dc)
            }
        case .king:
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 { _ = add(row + dr, col + dc) }
            }
        case .rook:
            ray(1, 0); ray(-1, 0); ray(0, 1); ray(0, -1)
        case .bishop:
            ray(1, 1); ray(1, -1); ray(-1, 1); ray(-1, -1)
        case .queen:
            ray(1, 0); ray(-1, 0); ray(0, 1); ray(0, -1)
            ray(1, 1); ray(1, -1); ray(-1, 1); ray(-1, -1)
        case .pawn:
            let dir = piece.isWhite ? -1 : 1
            let startRow = piece.isWhite ? 6 : 1
            let oneAhead = (row + dir) * 8 + col
            if (0..<8).contains(row + dir), board[oneAhead] == nil {
                out.insert(oneAhead)
                let twoAhead = (row + 2 * dir) * 8 + col
                if row == startRow, board[twoAhead] == nil { out.insert(twoAhead) }
            }
            for dc in [-1, 1] {
                let r = row + dir, c = col + dc
                guard (0..<8).contains(r), (0..<8).contains(c) else { continue }
                if let occupant = board[r * 8 + c], occupant.isWhite != piece.isWhite {
                    out.insert(r * 8 + c)
                }
            }
        }
        for solution in acceptedMoves.compactMap({ Self.parseMove($0) }) where solution.from == square {
            // Castling and en passant are not covered by the basic move hints above.
            out.insert(solution.to)
        }
        return out
    }
}

// MARK: - View

struct CheckmateView: View {
    @State private var engine = CheckmateEngine.resumable()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDuration = 60
    private var isShowcase = false

    init() {}

    /// Just the board, in a fixed position, for the Home preview.
    init(showcase engine: CheckmateEngine) {
        _engine = State(initialValue: engine)
        isShowcase = true
    }

    var body: some View {
        if isShowcase {
            ZStack {
                Self.palette.backdrop
                boardView.padding(24)
            }
            .environment(\.toyStyle, Self.palette.style)
            .frame(width: 360, height: 360)
        } else {
            gameBody
        }
    }

    @ViewBuilder
    private var gameBody: some View {
        Group {
            if engine.hasStarted {
                challenge
            } else {
                setup
            }
        }
        .background(Self.palette.backdrop.ignoresSafeArea())
    }

    static let palette = ToyPuzzles.world(top: (0.88, 0.96, 0.97), bottom: (0.72, 0.88, 0.90),
                                          darkTop: (0.07, 0.15, 0.17), darkBottom: (0.03, 0.08, 0.10),
                                          tray: (0.52, 0.34, 0.21), darkTray: (0.34, 0.21, 0.13),
                                          ink: (0.10, 0.30, 0.36), accent: (0.98, 0.55, 0.25), darkAccent: (1.0, 0.62, 0.32))

    private var challenge: some View {
        let palette = Self.palette
        return GameContainerView(gameID: .checkmate, engine: engine,
                          resultTitle: L10n.text("Time's up!"),
                          resultSummary: L10n.format("Solved: %d", engine.solvedCount),
                          chrome: .inGame, backdrop: AnyView(palette.backdrop), toyStyle: palette.style) {
            ToyGameStage(palette: palette,
                         headline: .clock(caption: L10n.format("Solved: %d", engine.solvedCount),
                                          time: { String(format: "%d:%02d", engine.secondsLeft / 60, engine.secondsLeft % 60) }),
                         trailing: {
                ToyIconButton(symbol: "lightbulb.fill", label: L10n.text("Hint"), ink: palette.ink) { engine.hint() }
                    .disabled(engine.hintSquare != nil || engine.awaitingBot)
                    .opacity(engine.hintSquare != nil || engine.awaitingBot ? 0.5 : 1)
            }) {
                VStack(spacing: 12) {
                    statusBar
                    boardView
                    // The rules keep their place and fade after the first mate.
                    Text(L10n.text("Mate on the first try to build a streak. Each mate adds 5 seconds."))
                        .font(.system(.footnote, design: .rounded))
                        .opacity(engine.solvedCount == 0 ? 0.6 : 0)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
        .onAppear { engine.setClockActive(scenePhase == .active) }
        .onDisappear { engine.setClockActive(false) }
        .onChange(of: scenePhase) { _, phase in engine.setClockActive(phase == .active) }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
                engine.tick()
            }
        }
    }

    private func durationTitle(_ seconds: Int) -> String {
        L10n.text(seconds == 30 ? "30 seconds" : seconds == 60 ? "1 minute" : "2 minutes")
    }

    private var setup: some View {
        let palette = Self.palette
        return VStack(spacing: 24) {
            HStack {
                ToyIconButton(symbol: "xmark", label: L10n.text("Main Menu"), ink: palette.ink) { dismiss() }
                Spacer()
            }
            Spacer()
            Image(systemName: "crown.fill")
                .font(.system(size: 48)).foregroundStyle(palette.accent)
                .shadow(color: palette.accent.toyShade(-0.3), radius: 0, y: 3)
            Text(L10n.text("Checkmate")).font(.system(.largeTitle, design: .rounded).weight(.heavy))
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Choose challenge time")).font(.system(.title2, design: .rounded).weight(.bold))
                Text(L10n.text("Solve as many mates as you can")).opacity(0.7)
                Menu {
                    Picker(L10n.text("Choose challenge time"), selection: $selectedDuration) {
                        ForEach(CheckmateEngine.durations, id: \.self) { seconds in
                            Text(durationTitle(seconds)).tag(seconds)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "timer").foregroundStyle(palette.accent)
                        Text(durationTitle(selectedDuration))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").opacity(0.5)
                    }
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.ink)
                    .padding(18)
                    .background(palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text(L10n.text("100 points per mate")).font(.caption).opacity(0.6)
                ToyCapsuleButton(title: L10n.text("Start challenge"), symbol: "play.fill", color: palette.accent, ink: .white) {
                    engine.start(seconds: selectedDuration)
                }
            }
            .padding(24)
            .toyTray(palette.card, cornerRadius: 28, padding: 0)
            Spacer()
        }
        .foregroundStyle(palette.ink)
        .padding()
    }

    private var statusBar: some View {
        let palette = Self.palette
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                ToyChip(color: palette.card) {
                    Text(engine.puzzle.title).foregroundStyle(palette.ink).lineLimit(1)
                }
                if engine.streak > 1 {
                    ToyChip(color: Color(red: 1, green: 0.62, blue: 0.25)) {
                        Label { Text(verbatim: "×\(engine.streak)") } icon: { Image(systemName: "flame.fill") }
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if engine.bonusFlash > 0 {
                    ToyChip(color: Color(red: 0.36, green: 0.78, blue: 0.45)) {
                        Text(verbatim: "+\(Int(CheckmateEngine.timeBonus))s").foregroundStyle(.white)
                    }
                    .id(engine.bonusFlash)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(.snappy, value: engine.bonusFlash)
            .animation(.snappy, value: engine.streak)
            HStack(spacing: 6) {
                if engine.hasMoveError {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                Text(engine.message)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
            }
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(engine.hasMoveError ? Color(red: 0.9, green: 0.25, blue: 0.25) : palette.ink)
            .lineLimit(2).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 40)
        }
    }

    private var boardView: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        square(row: row, col: col)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .aspectRatio(1, contentMode: .fit)
        // A walnut clay frame around the squares.
        .toyTray(Self.palette.tray, cornerRadius: 18, padding: 9)
    }

    private static let lightSquare = Color(red: 0.94, green: 0.86, blue: 0.71)
    private static let darkSquare = Color(red: 0.71, green: 0.53, blue: 0.38)
    private static let lastMoveTint = Color(red: 0.80, green: 0.82, blue: 0.28)
    private static let ivory = Color(red: 0.99, green: 0.97, blue: 0.92)
    private static let ebony = Color(red: 0.13, green: 0.11, blue: 0.10)

    /// A solid piece: the filled glyph in the piece's colour, the outlined
    /// glyph on top to draw its edges.
    private func pieceView(_ piece: ChessPiece) -> some View {
        ZStack {
            Text(verbatim: piece.type.glyph(isWhite: false))
                .foregroundStyle(piece.isWhite ? Self.ivory : Self.ebony)
            if piece.isWhite {
                Text(verbatim: piece.type.glyph(isWhite: true))
                    .foregroundStyle(Self.ebony)
            }
        }
        .font(.system(size: 40))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1.5)
    }

    @ViewBuilder
    private func square(row: Int, col: Int) -> some View {
        let index = row * 8 + col
        let isLight = (row + col) % 2 == 0
        let piece = engine.board[index]

        ZStack {
            Rectangle()
                .fill(isLight ? Self.lightSquare : Self.darkSquare)
            if let last = engine.lastMove, last.from == index || last.to == index {
                Rectangle().fill(Self.lastMoveTint.opacity(0.55))
            }
            if engine.selected == index {
                Rectangle().fill(Self.palette.accent.opacity(0.45))
            }
            if engine.hintSquare == index {
                Rectangle().strokeBorder(Color(red: 1, green: 0.8, blue: 0.2), lineWidth: 3)
            }
            if let piece {
                pieceView(piece)
                    .allowsHitTesting(false)
            }
            if engine.targets.contains(index) {
                if piece != nil {
                    // A capture: a ring around the piece.
                    Circle()
                        .strokeBorder(Color.black.opacity(0.28), lineWidth: 4)
                        .padding(1)
                } else {
                    Circle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if col == 0 {
                Text(verbatim: String(8 - row))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isLight ? Self.darkSquare : Self.lightSquare)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if row == 7 {
                Text(verbatim: String(Array("abcdefgh")[col]))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isLight ? Self.darkSquare : Self.lightSquare)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(index) }
    }
}

/// The clock, score and streak carry over; play continues on a fresh puzzle.
extension CheckmateEngine: ResumableGame {
    private struct Session: Codable {
        var remainingTime: TimeInterval
        var score, solvedCount, streak: Int
    }

    func saveSession() -> Data? {
        tick()
        guard hasStarted, state == .playing || state == .paused, remainingTime > 0 else { return nil }
        return encodeSession(Session(remainingTime: remainingTime, score: score,
                                     solvedCount: solvedCount, streak: streak))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), s.remainingTime > 0 else { return false }
        if hasStarted { restart() }
        remainingTime = s.remainingTime
        score = s.score; solvedCount = s.solvedCount; streak = s.streak
        hasStarted = true
        clockAnchor = nil
        return true
    }

    static func resumable() -> CheckmateEngine {
        let engine = CheckmateEngine()
        if let session = GameSessionStore.load(.checkmate) { _ = engine.restoreSession(session.payload) }
        return engine
    }
}
