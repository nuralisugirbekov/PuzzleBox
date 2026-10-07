import SwiftUI
import Observation

enum AttentionMode: String, CaseIterable {
    case oddOneOut, findColor, biggestNumber, missingNumber, whichSide, memoryFlash, findPair, ascending, dontTap, fastSort
    var id: GameID { GameID(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .oddOneOut: "Odd One Out"
        case .findColor: "Find the Color"
        case .biggestNumber: "Biggest Number"
        case .missingNumber: "Missing Number"
        case .whichSide: "Which Side?"
        case .memoryFlash: "Memory Flash"
        case .findPair: "Find the Pair"
        case .ascending: "Ascending"
        case .dontTap: "Don’t Tap"
        case .fastSort: "Fast Sort"
        }
    }
    var hint: String {
        switch self {
        case .oddOneOut: "Find the symbol that is different."
        case .findColor: "Choose the ink color, not the word."
        case .biggestNumber: "Tap the largest number."
        case .missingNumber: "Choose the missing number in the sequence."
        case .whichSide: "Tap the side with more dots."
        case .memoryFlash: "Remember the lit cells, then tap them after they disappear."
        case .findPair: "Find and tap the two identical symbols."
        case .ascending: "Tap all numbers in ascending order."
        case .dontTap: "Tap every circle. Never tap a triangle."
        case .fastSort: "Swipe even numbers left and odd numbers right."
        }
    }
}

@MainActor @Observable
final class AttentionEngine: GameEngine {
    let mode: AttentionMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var started = false
    private(set) var timeLeft = 30.0
    private(set) var lives = 3
    private(set) var items: [Int] = []
    private(set) var options: [Int] = []
    private(set) var marked: Set<Int> = []
    private(set) var targets: Set<Int> = []
    private(set) var first: Int?
    private(set) var nextNumber = 1
    private(set) var round = 0
    private(set) var prompt = 0
    private(set) var ink = 0
    private(set) var showing = false
    private(set) var feedback = ""
    private var answer = 0
    private var reveal = 0.0
    private var delay = 0.0
    private var roundTime = 0.0
    var active = false
    static let symbols = ["circle", "square", "diamond", "triangle", "star", "heart", "suit.spade", "suit.club", "moon", "bolt", "sun.max", "leaf", "flag", "bell", "hexagon", "pentagon"]
    static let colorNames = ["Red", "Blue", "Green", "Orange"]
    static let colors: [Color] = [.red, .blue, .green, .orange]
    init(mode: AttentionMode) { self.mode = mode; restart() }
    func restart() {
        score = 0; state = .playing; started = false; timeLeft = 30; lives = 3; round = 0; delay = 0; feedback = ""
        prepare()
    }
    func start() { guard active, state == .playing, !started else { return }; started = true }
    private func prepare() {
        marked = []; targets = []; first = nil; nextNumber = 1; showing = false; roundTime = 0; feedback = ""
        switch mode {
        case .oddOneOut:
            let pair = [[0,1],[2,3],[4,10],[14,15],[5,6]].randomElement()!
            items = Array(repeating: pair[0], count: 16); answer = Int.random(in: 0..<16); items[answer] = pair[1]
        case .findColor:
            prompt = Int.random(in: 0..<4); ink = (prompt + Int.random(in: 1...3)) % 4; options = Array(0..<4).shuffled(); answer = ink
        case .biggestNumber:
            items = Array(10...99).shuffled().prefix(6).map { $0 }; answer = items.max()!
        case .missingNumber:
            let start = Int.random(in: 1...15), step = Int.random(in: 2...7)
            items = (0..<5).map { start + $0 * step }; prompt = Int.random(in: 1...3); answer = items[prompt]
            options = [answer, answer+1, answer+step, answer-1].shuffled()
        case .whichSide:
            let a = Int.random(in: 5...17), b = Int.random(in: 1...4)
            items = Bool.random() ? [a,a+b] : [a+b,a]; answer = items[0] > items[1] ? 0 : 1
        case .memoryFlash:
            items = Array(repeating: 0, count: 16); targets = Set(Array(0..<16).shuffled().prefix(min(6,3+round/3))); showing = true; reveal = 1.0
        case .findPair:
            items = Array(0..<16).shuffled().prefix(11).map { $0 }; items.append(items[0]); items.shuffle()
        case .ascending: items = Array(1...9).shuffled()
        case .dontTap:
            items = Array(repeating: 0, count: 9) + Array(repeating: 1, count: 3); items.shuffle()
        case .fastSort: prompt = Int.random(in: 1...99); answer = prompt.isMultiple(of: 2) ? 0 : 1
        }
    }
    func choose(_ index: Int) {
        guard active, started, state == .playing, delay == 0, !showing else { return }
        switch mode {
        case .oddOneOut: finish(index == answer)
        case .findColor: guard options.indices.contains(index) else { return }; finish(options[index] == answer)
        case .biggestNumber: guard items.indices.contains(index) else { return }; finish(items[index] == answer)
        case .missingNumber: guard options.indices.contains(index) else { return }; finish(options[index] == answer)
        case .whichSide, .fastSort: finish(index == answer)
        case .memoryFlash:
            guard items.indices.contains(index), !marked.contains(index) else { return }
            if targets.contains(index) { marked.insert(index); if marked == targets { finish(true) } }
            else { finish(false) }
        case .findPair:
            guard items.indices.contains(index), first != index else { return }
            if let first { marked.insert(index); finish(items[first] == items[index]) }
            else { first = index; marked.insert(index) }
        case .ascending:
            guard items.indices.contains(index), !marked.contains(index) else { return }
            if items[index] == nextNumber { marked.insert(index); nextNumber += 1; if nextNumber > 9 { finish(true) } }
            else { finish(false) }
        case .dontTap:
            guard items.indices.contains(index), !marked.contains(index) else { return }
            if items[index] == 0 { marked.insert(index); if marked.count == 9 { finish(true) } }
            else { finish(false) }
        }
    }
    private func finish(_ correct: Bool) {
        if correct { score += 100 + max(0, 50 - Int(roundTime * 10)); feedback = "Correct!"; Haptics.success() }
        else { lives -= 1; feedback = "Try again"; Haptics.error() }
        delay = 0.55
        if lives == 0 { state = .gameOver(won: false) }
    }
    func advance(_ dt: Double) {
        guard active, started, state == .playing else { return }
        let d = min(0.1,max(0,dt))
        if delay > 0 {
            delay = max(0,delay-d)
            if delay == 0 { round += 1; prepare() }
            return
        }
        timeLeft = max(0,timeLeft-d)
        if timeLeft == 0 { state = .gameOver(won: true); return }
        if showing { reveal -= d; if reveal <= 0 { showing = false } }
        else { roundTime += d }
    }
}
