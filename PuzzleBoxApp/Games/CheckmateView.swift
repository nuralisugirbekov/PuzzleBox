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

    var glyph: String {
        switch self {
        case .pawn: "♟"
        case .knight: "♞"
        case .bishop: "♝"
        case .rook: "♜"
        case .queen: "♛"
        case .king: "♚"
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
    /// Coordinate moves: user, (bot reply, user)*. E.g. ["d4f6", "h8g8", "f6g7"].
    let line: [String]
}

@MainActor
@Observable
final class CheckmateEngine: GameEngine {
    static let puzzles: [ChessPuzzle] = [
        ChessPuzzle(title: "Mate in 1", fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w", line: ["e1e8"]),
        ChessPuzzle(title: "Mate in 1", fen: "6k1/5p1p/8/8/8/6Q1/1B3PPP/6K1 w", line: ["g3g7"]),
        ChessPuzzle(title: "Mate in 1", fen: "6rk/6pp/8/6N1/8/8/8/6K1 w", line: ["g5f7"]),
        ChessPuzzle(title: "Mate in 1", fen: "3k4/R7/8/8/8/8/8/1R4K1 w", line: ["b1b8"]),
        ChessPuzzle(title: "Mate in 1",
                    fen: "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w",
                    line: ["h5f7"]),
        ChessPuzzle(title: "Mate in 2", fen: "7k/7p/7P/8/3Q4/8/5PP1/6K1 w",
                    line: ["d4f6", "h8g8", "f6g7"]),
        ChessPuzzle(title: "Mate in 2", fen: "3k4/8/R7/1R6/8/8/8/6K1 w",
                    line: ["a6a7", "d8e8", "b5b8"]),
    ]

    /// Index 0 = a8 (top-left), row-major toward h1.
    private(set) var board: [ChessPiece?] = []
    private(set) var puzzleIndex = 0
    private(set) var attempts = 0
    private(set) var step = 0
    private(set) var message = ""
    private(set) var score = 0
    private(set) var awaitingBot = false
    var selected: Int?
    private(set) var targets: Set<Int> = []
    var state: GameState = .playing

    var puzzle: ChessPuzzle { Self.puzzles[puzzleIndex] }

    init() { loadPuzzle() }

    func restart() {
        puzzleIndex = 0
        score = 0
        state = .playing
        loadPuzzle()
    }

    private func loadPuzzle() {
        board = Self.parseFEN(puzzle.fen)
        step = 0
        attempts = 0
        selected = nil
        targets = []
        awaitingBot = false
        message = "White to move — find the mate!"
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

    private static func parseMove(_ move: String) -> (from: Int, to: Int)? {
        let chars = Array(move)
        guard chars.count == 4,
              let from = squareIndex(chars[0], chars[1]),
              let to = squareIndex(chars[2], chars[3]) else { return nil }
        return (from, to)
    }

    func tap(_ square: Int) {
        guard state == .playing, !awaitingBot else { return }
        if let sel = selected, targets.contains(square) {
            tryMove(from: sel, to: square)
            return
        }
        if let piece = board[square], piece.isWhite {
            selected = square
            targets = pseudoMoves(from: square)
            Haptics.tap()
        } else {
            selected = nil
            targets = []
        }
    }

    private func tryMove(from: Int, to: Int) {
        selected = nil
        targets = []
        guard let solution = Self.parseMove(puzzle.line[step]),
              solution.from == from, solution.to == to else {
            attempts += 1
            message = "Not the winning move — try again"
            Haptics.error()
            return
        }

        apply(from: from, to: to)
        step += 1
        Haptics.move()

        if step == puzzle.line.count {
            puzzleSolved()
        } else {
            // Black's stored reply, then back to the user.
            awaitingBot = true
            message = "Black replies…"
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                if let reply = Self.parseMove(puzzle.line[step]) {
                    apply(from: reply.from, to: reply.to)
                }
                step += 1
                awaitingBot = false
                message = "Now finish it — mate!"
            }
        }
    }

    private func apply(from: Int, to: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            board[to] = board[from]
            board[from] = nil
        }
    }

    private func puzzleSolved() {
        score += max(20, 100 - attempts * 20)
        message = "Checkmate! 🎉"
        Haptics.success()
        if puzzleIndex + 1 >= Self.puzzles.count {
            state = .gameOver(won: true)
        } else {
            awaitingBot = true
            Task {
                try? await Task.sleep(for: .milliseconds(1000))
                puzzleIndex += 1
                loadPuzzle()
            }
        }
    }

    /// Pseudo-legal destinations (no check validation — the solution check
    /// is what decides correctness; this just powers the move UI).
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
        return out
    }
}

// MARK: - View

struct CheckmateView: View {
    @State private var engine = CheckmateEngine()

    var body: some View {
        GameContainerView(gameID: .checkmate, engine: engine) {
            VStack(spacing: 14) {
                statusBar
                boardView
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 4) {
            Text("\(engine.puzzle.title) — Puzzle \(engine.puzzleIndex + 1) of \(CheckmateEngine.puzzles.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.neon)
            Text(engine.message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.opacity)
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func square(row: Int, col: Int) -> some View {
        let index = row * 8 + col
        let isLight = (row + col) % 2 == 0
        let piece = engine.board[index]

        ZStack {
            Rectangle()
                .fill(isLight ? Theme.surfaceHigh : Theme.surface)
            if engine.selected == index {
                Rectangle().fill(Theme.neon.opacity(0.35))
            }
            if let piece {
                Text(piece.type.glyph)
                    .font(.system(size: 30))
                    .foregroundStyle(piece.isWhite ? Color.white : Color(white: 0.13))
                    .shadow(color: piece.isWhite ? .black.opacity(0.6) : .white.opacity(0.35), radius: 1)
            }
            if engine.targets.contains(index) {
                if piece != nil {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.neon, lineWidth: 2.5)
                        .padding(2)
                } else {
                    Circle()
                        .fill(Theme.neon.opacity(0.6))
                        .frame(width: 10, height: 10)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { engine.tap(index) }
    }
}
