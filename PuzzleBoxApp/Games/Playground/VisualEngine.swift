import SwiftUI
import Observation

enum VisualMode:String,CaseIterable {
    case rotatePuzzle, matchstick
    var id:GameID { GameID(rawValue:rawValue)! }
    var title:String {
        switch self {
        case .rotatePuzzle:"Rotate Puzzle"
        case .matchstick:"Matchstick Puzzle"
        }
    }
    var hint:String {
        switch self {
        case .rotatePuzzle:"Tap each tile to rotate it and restore the picture."
        case .matchstick:"Move exactly one match: tap a lit segment, then an empty segment. Fix the equation."
        }
    }
}

@MainActor @Observable
final class VisualEngine:GameEngine {
    let mode:VisualMode
    private(set) var levelIndex = 0
    /// Rotate grows from 3×3 to 7×7 over its levels; see `rotateSide`.
    var levelCount: Int { mode == .rotatePuzzle ? 50 : 20 }
    private var random = LevelRandom(seed: 1)
    /// The level to open on next time, so leaving never loses progress.
    private var levelKey: String { "visualLevel." + mode.rawValue }
    func loadLevel(_ index: Int) {
        guard (0..<levelCount).contains(index) else { return }
        levelIndex = index
        UserDefaults.standard.set(index, forKey: levelKey)
        restart()
    }
    func nextLevel() { loadLevel(levelIndex + 1) }
    var hasNextLevel: Bool { levelIndex + 1 < levelCount }
    private func pick(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &random) }
    private func shuffled(_ values: [Int]) -> [Int] { values.shuffled(using: &random) }

    var state:GameState = .playing
    private(set) var score = 0
    /// Rotate: quarter turns still needed per tile. Matchstick: lit segments.
    private(set) var cells:[Int] = []
    /// Rotate: total quarter turns applied per tile, so the view can animate forward.
    private(set) var turns:[Int] = []
    private(set) var moves = 0
    private(set) var feedback = ""
    private(set) var selectedMatch:Int?
    /// Rotate grid side (3…7).
    private(set) var size = 3
    private(set) var par = 0
    /// Matchstick: matches that must be moved, and how many have been moved so far.
    private(set) var matchesToMove = 1
    private(set) var matchesMoved = 0
    private var startCells:[Int] = []

    var stars: Int { par == 0 ? 3 : moves <= par ? 3 : Double(moves) <= Double(par) * 1.5 ? 2 : 1 }

    static let digitMasks = [63,6,91,79,102,109,125,7,127,111]
    init(mode:VisualMode) {
        self.mode = mode
        levelIndex = max(0, min(levelCount - 1, UserDefaults.standard.integer(forKey: "visualLevel." + mode.rawValue)))
        restart()
    }
    func restart() {
        random = LevelRandom(seed: UInt64((mode == .rotatePuzzle ? 4 : 10)*1000 + levelIndex + 1))
        state = .playing; score = 0; moves = 0; cells = []; turns = []; feedback = ""; selectedMatch = nil; matchesMoved = 0
        switch mode {
        case .rotatePuzzle:
            let (side, progress) = Self.rotateSide(levelIndex)
            size = side
            // Within a size, levels start with half the tiles turned and end
            // with every tile turned.
            let tileCount = size * size
            let turned = max(2, Int((Double(tileCount) * (0.5 + 0.5 * progress)).rounded()))
            let scrambled = Set(shuffled(Array(0..<tileCount)).prefix(turned))
            cells = (0..<tileCount).map { scrambled.contains($0) ? pick(1...3) : 0 }
            turns = cells
            par = cells.reduce(0) { $0 + (4 - $1) % 4 }
        case .matchstick:
            matchesToMove = levelIndex < 8 ? 1 : 2
            makeMatches()
            startCells = cells
            par = matchesToMove
        }
    }
    /// Rotate levels by grid side: 8 at 3×3, 10 at 4×4, 12 at 5×5, 12 at
    /// 6×6 and 8 at 7×7. Returns the side and how far through that size the
    /// level is (0…1).
    private static let rotateSides: [(side: Int, levels: Int)] = [(3, 8), (4, 10), (5, 12), (6, 12), (7, 8)]

    static func rotateSide(_ level: Int) -> (side: Int, progress: Double) {
        var first = 0
        for (side, levels) in rotateSides {
            if level < first + levels || side == rotateSides.last!.side {
                return (side, Double(min(level - first, levels - 1)) / Double(max(1, levels - 1)))
            }
            first += levels
        }
        return (3, 0)
    }

    private func win() {
        score = 100 + levelIndex * 50 + stars * 100
        UserDefaults.standard.set(min(levelCount - 1, levelIndex + 1), forKey: levelKey)
        state = .gameOver(won:true); Haptics.success()
    }
    func tap(_ i:Int) {
        guard state == .playing else { return }; feedback = ""
        switch mode {
        case .rotatePuzzle:
            guard cells.indices.contains(i) else { return }
            moves += 1; cells[i] = (cells[i]+1)%4; turns[i] += 1
            if cells[i] == 0 { SoundFX.play(.place); Haptics.move() } else { SoundFX.play(.tap) }
            if cells.allSatisfy({ $0 == 0 }) { win() }
        case .matchstick: match(i)
        }
    }
    func isCorrect(_ i:Int) -> Bool { cells.indices.contains(i) && cells[i] == 0 }
    private func equation(_ bits:[Int]) -> (Int,Int,Int,Bool)? {
        func digit(_ offset:Int) -> Int? { let mask = (0..<7).reduce(0) { $0 | (bits[offset+$1] << $1) }; return Self.digitMasks.firstIndex(of:mask) }
        guard bits.count == 23,bits[7] == 1,let a = digit(0),let b = digit(9),let c = digit(16) else { return nil }
        return (a,b,c,bits[8] == 1)
    }
    private func correct(_ bits:[Int]) -> Bool { guard let (a,b,c,plus) = equation(bits) else { return false }; return (plus ? a+b : a-b) == c }
    private func encoded(_ a:Int,_ b:Int,_ c:Int,_ plus:Bool) -> [Int] {
        func bits(_ n:Int) -> [Int] { (0..<7).map { (Self.digitMasks[n] >> $0)&1 } }
        return bits(a)+[1,plus ? 1 : 0]+bits(b)+bits(c)
    }
    /// Starts from a true equation and moves `matchesToMove` matches away from it,
    /// so the puzzle is solvable in exactly that many moves.
    private func makeMatches() {
        for _ in 0..<400 {
            let a = pick(0...9),b = pick(0...9),plus = pick(0...1) == 1,c = plus ? a+b : a-b
            guard (0...9).contains(c) else { continue }
            var candidate = encoded(a,b,c,plus)
            for _ in 0..<matchesToMove {
                let lit = shuffled(candidate.indices.filter { candidate[$0] == 1 && $0 != 7 })
                let empty = shuffled(candidate.indices.filter { candidate[$0] == 0 })
                guard let from = lit.first, let to = empty.first else { break }
                candidate[from] = 0; candidate[to] = 1
            }
            if equation(candidate) != nil && !correct(candidate) && candidate != encoded(a,b,c,plus) { cells = candidate; return }
        }
        cells = encoded(6,4,4,true) // Move the vertical match of '+' to make 8 − 4 = 4.
    }
    func resetMatches() {
        guard mode == .matchstick, state == .playing else { return }
        cells = startCells; matchesMoved = 0; selectedMatch = nil; feedback = ""
        SoundFX.play(.whoosh)
    }
    private func match(_ i:Int) {
        guard cells.indices.contains(i), i != 7 else { return } // the equals sign's anchor stays put
        if cells[i] == 1 { selectedMatch = selectedMatch == i ? nil : i; SoundFX.play(.tap); return }
        guard let from = selectedMatch else { return }
        moves += 1; matchesMoved += 1
        cells[from] = 0; cells[i] = 1; selectedMatch = nil
        SoundFX.play(.place)
        if correct(cells) { win(); return }
        if matchesMoved >= matchesToMove {
            // Out of moves: put the matches back for another try.
            feedback = "Try again"; Haptics.error(); SoundFX.play(.wrong)
            cells = startCells; matchesMoved = 0
        }
    }
}

/// Stable levels across launches, independent of Swift's randomized hash seed.
private struct LevelRandom: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

// MARK: - Saved round

extension VisualEngine: ResumableGame {
    private struct Session: Codable {
        let levelIndex: Int
        let cells: [Int]
        let turns: [Int]
        let moves: Int
        let size: Int
        let par: Int
        let matchesToMove: Int
        let matchesMoved: Int
        let startCells: [Int]
    }

    func saveSession() -> Data? {
        // Later levels are worth keeping even before the first move.
        guard state == .playing || state == .paused, moves > 0 || levelIndex > 0 else { return nil }
        return encodeSession(Session(levelIndex: levelIndex, cells: cells, turns: turns, moves: moves,
                                     size: size, par: par, matchesToMove: matchesToMove,
                                     matchesMoved: matchesMoved, startCells: startCells))
    }

    func restoreSession(_ data: Data) -> Bool {
        guard let s = decodeSession(Session.self, from: data), (0..<levelCount).contains(s.levelIndex) else { return false }
        levelIndex = s.levelIndex
        restart()  // Re-seeds the level, then the saved board replaces the fresh one.
        cells = s.cells; turns = s.turns; moves = s.moves; size = s.size; par = s.par
        matchesToMove = s.matchesToMove; matchesMoved = s.matchesMoved; startCells = s.startCells
        return true
    }
}
