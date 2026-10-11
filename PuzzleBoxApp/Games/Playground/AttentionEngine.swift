import SwiftUI
import Observation

enum AttentionMode: String, CaseIterable {
    case findColor, findPair
    var id: GameID { GameID(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .findColor: "Find the Color"
        case .findPair: "Find the Pair"
        }
    }
    var hint: String {
        switch self {
        case .findColor: "Choose the ink color, not the word."
        case .findPair: "Find and tap the two identical symbols."
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
    /// Find Pair tiles: symbol index and colour index.
    private(set) var items: [(symbol: Int, color: Int)] = []
    private(set) var options: [Int] = []
    /// Misleading ink for each option label.
    private(set) var optionInks: [Int] = []
    private(set) var marked: Set<Int> = []
    private(set) var first: Int?
    private(set) var round = 0
    private(set) var prompt = 0
    private(set) var ink = 0
    /// Find Color: when true, the answer is the written word instead of the ink.
    private(set) var askWord = false
    private(set) var streak = 0
    private(set) var feedback = ""
    private(set) var lastCorrect = false
    private var answer = 0

    private var delay = 0.0
    private var roundTime = 0.0
    var active = false
    static let symbols = ["circle", "square", "diamond", "triangle", "star", "heart", "suit.spade", "suit.club", "moon", "bolt", "sun.max", "leaf", "flag", "bell", "hexagon", "pentagon"]
    static let colorNames = ["Red", "Blue", "Green", "Orange", "Purple", "Yellow"]
    static let colors: [Color] = [.red, .blue, .green, .orange, .purple, .yellow]
    static let tileColors: [Color] = [.cyan, .pink, .yellow, .mint, .orange, .purple]

    var multiplier: Int { min(4, 1 + streak / 3) }
    var colorCount: Int { round < 5 ? 4 : 6 }
    var columns: Int { items.count >= 25 ? 5 : 4 }

    init(mode: AttentionMode) { self.mode = mode; restart() }
    func restart() {
        score = 0; state = .playing; started = false; timeLeft = 30; lives = 3; round = 0; delay = 0; feedback = ""; streak = 0
        prepare()
    }
    func start() { guard active, state == .playing, !started else { return }; started = true }
    private func prepare() {
        marked = []; first = nil; roundTime = 0; feedback = ""
        switch mode {
        case .findColor:
            let count = colorCount
            prompt = Int.random(in: 0..<count); ink = (prompt + Int.random(in: 1..<count)) % count
            askWord = round >= 6 && Int.random(in: 0..<10) < 3
            answer = askWord ? prompt : ink
            options = Array(0..<count).shuffled()
            // Later rounds paint the option labels in the wrong colours too.
            optionInks = options.map { option in round >= 3 ? (option + Int.random(in: 1..<count)) % count : -1 }
        case .findPair:
            let total = round < 3 ? 12 : round < 7 ? 16 : round < 12 ? 20 : 25
            let colorVariety = round < 5 ? 1 : min(Self.tileColors.count, 2 + round / 5)
            var pool = Set<[Int]>()
            while pool.count < total - 1 {
                pool.insert([Int.random(in: 0..<Self.symbols.count), Int.random(in: 0..<colorVariety)])
            }
            var list = pool.map { (symbol: $0[0], color: $0[1]) }
            list.append(list[0]); list.shuffle()
            items = list
        }
    }
    func choose(_ index: Int) {
        guard active, started, state == .playing, delay == 0 else { return }
        switch mode {
        case .findColor: guard options.indices.contains(index) else { return }; finish(options[index] == answer)
        case .findPair:
            guard items.indices.contains(index), first != index else { return }
            if let first {
                marked.insert(index)
                finish(items[first].symbol == items[index].symbol && items[first].color == items[index].color)
            } else { first = index; marked.insert(index); SoundFX.play(.tap) }
        }
    }
    private func finish(_ correct: Bool) {
        lastCorrect = correct
        if correct {
            streak += 1
            let gained = (100 + max(0, 50 - Int(roundTime * 10))) * multiplier
            score += gained
            // Quick answers buy a little extra time.
            let bonus = roundTime < 1.5 ? 2.0 : 1.0
            timeLeft = min(60, timeLeft + bonus)
            feedback = multiplier > 1 ? L10n.format("+%d ×%d", gained, multiplier) : "+\(gained)"
            Haptics.success(); SoundFX.play(multiplier > 1 ? .coin : .point)
        } else {
            streak = 0; lives -= 1; feedback = L10n.text("Try again"); Haptics.error(); SoundFX.play(.wrong)
        }
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
        roundTime += d
    }
}
