import SwiftUI
import Observation

enum LogicMode: String, CaseIterable {
    case hashi, kakuro, nurikabe, slitherlink, futoshiki, hitori, takuzu, tents, masyu
    var gameID: GameID { GameID(rawValue: rawValue)! }
    var title: String {
        switch self {
        case .hashi: "Hashi"
        case .kakuro: "Kakuro"
        case .nurikabe: "Nurikabe"
        case .slitherlink: "Slitherlink"
        case .futoshiki: "Futoshiki"
        case .hitori: "Hitori"
        case .takuzu: "Takuzu"
        case .tents: "Tents"
        case .masyu: "Masyu"
        }
    }
    var hint: String {
        switch self {
        case .hashi: "Tap two aligned islands to cycle 0, 1, 2 bridges. Match every number, avoid crossings and connect all islands."
        case .kakuro: "Fill 1–9. Each arrow gives the sum of its run; digits cannot repeat within a run."
        case .nurikabe: "Shade the sea. Each white island has one clue and that many cells. The sea must connect with no 2×2 black squares."
        case .slitherlink: "Tap edges to draw one loop. Each number counts its surrounding lines. No branches or crossings."
        case .futoshiki: "Fill 1–4 once per row and column. Respect every inequality."
        case .hitori: "Shade duplicates. Remaining numbers must be unique in each row and column. Black cells cannot touch by a side; white cells must connect."
        case .takuzu: "Fill 0 and 1 equally in each row and column. No three alike in a row. All rows and columns must be distinct."
        case .tents: "Place one tent beside each tree. Tents cannot touch, even diagonally. Match row and column totals."
        case .masyu: "Draw one loop through all pearls. White: straight, turning next to it. Black: turn, then straight on both sides."
        }
    }
}

struct LogicEdge: Hashable {
    let a: Int
    let b: Int
    init(_ a: Int, _ b: Int) { self.a = min(a, b); self.b = max(a, b) }
}
struct KakuroRun {
    let clue: Int
    let vertical: Bool
    let cells: [Int]
    let sum: Int
}
struct LogicInequality { let a: Int; let b: Int; let less: Bool }
private struct LogicSnapshot {
    let cells: [Int]
    let bridges: [LogicEdge: Int]
    let lines: Set<LogicEdge>
}

@MainActor @Observable
final class LogicEngine: GameEngine {
    let mode: LogicMode
    var state: GameState = .playing
    private(set) var score = 0
    private(set) var n = 5
    private(set) var cells: [Int] = [] // binary shading or numeric input (0 = blank, Takuzu uses 1/2)
    private(set) var clues: [Int: Int] = [:]
    private(set) var fixed: Set<Int> = []
    private(set) var playable: Set<Int> = []
    private(set) var bridges: [LogicEdge: Int] = [:]
    private(set) var lines: Set<LogicEdge> = []
    private(set) var runs: [KakuroRun] = []
    private(set) var inequalities: [LogicInequality] = []
    private(set) var rowTotals: [Int] = []
    private(set) var columnTotals: [Int] = []
    private(set) var selected: Int?
    private(set) var moves = 0
    private(set) var feedback = ""
    private var history: [LogicSnapshot] = []
    init(mode: LogicMode) { self.mode = mode; restart() }
    var canUndo: Bool { !history.isEmpty && state == .playing }
    var numeric: Bool { mode == .kakuro || mode == .futoshiki }
    var loopMode: Bool { mode == .slitherlink || mode == .masyu }
    var nodeSide: Int { mode == .slitherlink ? n + 1 : n }
    private func neighbors(_ i: Int, side: Int? = nil) -> [Int] {
        let width = side ?? n
        return [i - width, i + width, i - 1, i + 1].filter { (0..<(width * width)).contains($0) && abs(i / width - $0 / width) + abs(i % width - $0 % width) == 1 }
    }
    private func save() { history.append(LogicSnapshot(cells: cells, bridges: bridges, lines: lines)); feedback = ""; moves += 1 }
    func undo() {
        guard state == .playing, let old = history.popLast() else { return }
        cells = old.cells; bridges = old.bridges; lines = old.lines; selected = nil; feedback = ""; moves += 1
    }
    func restart() {
        state = .playing; score = 0; n = 5; cells = Array(repeating: 0, count: 25)
        clues = [:]; fixed = []; playable = []; bridges = [:]; lines = []; runs = []; inequalities = []
        rowTotals = []; columnTotals = []; selected = nil; moves = 0; feedback = ""; history = []
        switch mode {
        case .hashi:
            // A connected, noncrossing generated solution supplies the island degrees.
            let islands = [0, 2, 4, 10, 12, 14, 20, 22, 24]
            let tree = [(0,2), (2,4), (0,10), (10,12), (12,14), (10,20), (20,22), (22,24)]
            for i in islands { clues[i] = 0 }
            for (a,b) in tree { let count = Int.random(in: 1...2); clues[a, default: 0] += count; clues[b, default: 0] += count }
        case .kakuro:
            playable = Set([6,7,11,12,13,14,18,19,23,24])
            let digits = Array(1...9).shuffled()
            var solution = Array(repeating: 0, count: 25)
            for i in playable { solution[i] = digits[(i / n + i % n) % 9] }
            for i in playable.sorted() {
                for vertical in [false, true] {
                    let step = vertical ? n : 1, before = i - step
                    guard !playable.contains(before) else { continue }
                    var group: [Int] = [], cell = i
                    while playable.contains(cell), vertical || cell / n == i / n { group.append(cell); cell += step }
                    runs.append(KakuroRun(clue: before, vertical: vertical, cells: group, sum: group.reduce(0) { $0 + solution[$1] }))
                }
            }
        case .nurikabe:
            // White pairs separated by a connected sea; transformations preserve all rules.
            let groups = [[0,1], [3,4], [10,11], [13,14], [20,21], [23,24]]
            let rotation = Int.random(in: 0..<4)
            for group in groups { clues[transformed(group.randomElement()!, n: n, rotation: rotation)] = group.count }
        case .slitherlink:
            n = 4; cells = Array(repeating: 0, count: 16)
            // Boundary of a connected polyomino, without holes, provides a valid single loop.
            let shapes: [[Int]] = [[0,1,4,5,6,9,10], [1,2,5,6,9,10,13], [0,1,2,4,8,9,10]]
            let rotation = Int.random(in: 0..<4)
            let region = Set(shapes.randomElement()!.map { transformed($0, n: n, rotation: rotation) })
            var boundary: Set<LogicEdge> = []
            for i in region {
                let r = i / n, c = i % n, a = r * (n + 1) + c
                for edge in [LogicEdge(a,a+1), LogicEdge(a,a+n+1), LogicEdge(a+1,a+n+2), LogicEdge(a+n+1,a+n+2)] {
                    if !boundary.insert(edge).inserted { boundary.remove(edge) }
                }
            }
            for i in cells.indices { clues[i] = cellEdges(i).filter { boundary.contains($0) }.count }
        case .futoshiki:
            n = 4; cells = Array(repeating: 0, count: 16)
            let rows = Array(0..<4).shuffled(), cols = Array(0..<4).shuffled(), digits = Array(1...4).shuffled()
            let solution = (0..<16).map { digits[(rows[$0 / 4] + cols[$0 % 4]) % 4] }
            fixed = Set(Array(0..<16).shuffled().prefix(5))
            for i in fixed { cells[i] = solution[i] }
            let pairs = (0..<16).flatMap { i in neighbors(i).filter { $0 > i }.map { LogicEdge(i,$0) } }.shuffled()
            inequalities = pairs.prefix(10).map { LogicInequality(a: $0.a, b: $0.b, less: solution[$0.a] < solution[$0.b]) }
        case .hitori:
            n = 4; cells = Array(repeating: 0, count: 16)
            let digits = Array(1...4).shuffled(), rotation = Int.random(in: 0..<4)
            var source = (0..<16).map { digits[($0 / 4 + $0 % 4) % 4] }
            for i in [1,7,12] { source[i] = source[i / 4 * 4 + (i % 4 + 1) % 4] }
            for i in 0..<16 { clues[transformed(i, n: 4, rotation: rotation)] = source[i] }
        case .takuzu:
            n = 4; cells = Array(repeating: 0, count: 16)
            let original = [1,1,2,2, 1,2,1,2, 2,1,2,1, 2,2,1,1]
            let rotation = Int.random(in: 0..<4), invert = Bool.random()
            let solution = (0..<16).map { i in let value = original[transformed(i, n: 4, rotation: rotation)]; return invert ? 3 - value : value }
            fixed = Set(Array(0..<16).shuffled().prefix(6)); for i in fixed { cells[i] = solution[i] }
        case .tents:
            n = 6; cells = Array(repeating: 0, count: 36)
            let rotation = Int.random(in: 0..<4)
            let tents = [1,4,12,15,25,28].map { transformed($0, n: 6, rotation: rotation) }
            fixed = Set([7,10,18,21,31,34].map { transformed($0, n: 6, rotation: rotation) })
            rowTotals = (0..<n).map { r in tents.filter { $0 / n == r }.count }
            columnTotals = (0..<n).map { c in tents.filter { $0 % n == c }.count }
        case .masyu:
            // A rectangle with black corners and white pearls beside each corner.
            let rotation = Int.random(in: 0..<4)
            let seed: [Int: Int] = [0:2,4:2,20:2,24:2,1:1,9:1,23:1,15:1]
            for (i, type) in seed { clues[transformed(i,n:n,rotation:rotation)] = type }
        }
    }
    private func transformed(_ i: Int, n: Int, rotation: Int) -> Int {
        var r = i / n, c = i % n
        for _ in 0..<rotation { let old = r; r = c; c = n - old - 1 }
        return r * n + c
    }
    func tap(_ i: Int) {
        guard state == .playing, cells.indices.contains(i) else { return }
        if mode == .hashi { island(i); return }
        if numeric {
            if !fixed.contains(i) && (mode != .kakuro || playable.contains(i)) { selected = i }
            return
        }
        guard !loopMode, !fixed.contains(i), !(mode == .nurikabe && clues[i] != nil) else { return }
        save()
        if mode == .takuzu { cells[i] = (cells[i] + 1) % 3 }
        else { cells[i] = 1 - cells[i] }
        Haptics.tap(); check(announce: false)
    }
    func enter(_ number: Int) {
        guard state == .playing, let i = selected, numeric, !fixed.contains(i), (0...(mode == .kakuro ? 9 : 4)).contains(number) else { return }
        save(); cells[i] = number; check(announce: false)
    }
    private func island(_ i: Int) {
        guard clues[i] != nil else { return }
        guard let a = selected, a != i else { selected = i; return }
        selected = i
        guard a / n == i / n || a % n == i % n else { return }
        let edge = LogicEdge(a,i), inner = bridgeInterior(edge)
        guard inner.allSatisfy({ clues[$0] == nil }) else { return }
        let count = (bridges[edge, default: 0] + 1) % 3
        guard count == 0 || !bridges.contains(where: { other, value in value > 0 && other != edge && !Set(bridgeInterior(other)).isDisjoint(with: inner) }) else {
            feedback = "Bridges cannot cross."; return
        }
        save(); bridges[edge] = count; selected = nil; check(announce: false)
    }
    private func bridgeInterior(_ e: LogicEdge) -> [Int] {
        let step = e.a / n == e.b / n ? 1 : n
        return Array(stride(from: e.a + step, to: e.b, by: step))
    }
    func edge(_ edge: LogicEdge) {
        guard state == .playing, loopMode, neighbors(edge.a, side: nodeSide).contains(edge.b) else { return }
        save(); if !lines.insert(edge).inserted { lines.remove(edge) }; check(announce: false)
    }
    func cellEdges(_ i: Int) -> [LogicEdge] {
        let a = i / n * (n + 1) + i % n
        return [LogicEdge(a,a+1), LogicEdge(a,a+n+1), LogicEdge(a+1,a+n+2), LogicEdge(a+n+1,a+n+2)]
    }
    func check(announce: Bool = true) {
        guard state == .playing else { return }
        let valid: Bool
        switch mode {
        case .hashi: valid = validHashi()
        case .kakuro: valid = runs.allSatisfy { run in let values = run.cells.map { cells[$0] }; return values.allSatisfy { (1...9).contains($0) } && Set(values).count == values.count && values.reduce(0,+) == run.sum }
        case .nurikabe: valid = validNurikabe()
        case .slitherlink: valid = validLoop() && cells.indices.allSatisfy { cellEdges($0).filter { lines.contains($0) }.count == clues[$0] }
        case .futoshiki: valid = validLatin() && inequalities.allSatisfy { $0.less ? cells[$0.a] < cells[$0.b] : cells[$0.a] > cells[$0.b] }
        case .hitori: valid = validHitori()
        case .takuzu: valid = validTakuzu()
        case .tents: valid = validTents()
        case .masyu: valid = validMasyu()
        }
        if valid { score = max(100, 1500 - moves * 5); state = .gameOver(won: true) }
        else if announce { feedback = "Not solved yet. Check the rules and clues."; Haptics.error() }
    }
    private func connected(_ members: Set<Int>) -> Bool {
        guard let first = members.first else { return false }
        var seen: Set<Int> = [first], queue = [first]
        while let i = queue.popLast() { for next in neighbors(i) where members.contains(next) && seen.insert(next).inserted { queue.append(next) } }
        return seen == members
    }
    private func validLatin() -> Bool {
        guard cells.allSatisfy({ (1...n).contains($0) }) else { return false }
        return (0..<n).allSatisfy { i in Set((0..<n).map { cells[i*n+$0] }).count == n && Set((0..<n).map { cells[$0*n+i] }).count == n }
    }
    private func validHashi() -> Bool {
        let active = bridges.filter { $0.value > 0 }
        let edges = Array(active.keys)
        for edge in edges {
            guard (1...2).contains(active[edge]!), clues[edge.a] != nil, clues[edge.b] != nil,
                  edge.a / n == edge.b / n || edge.a % n == edge.b % n,
                  bridgeInterior(edge).allSatisfy({ clues[$0] == nil }) else { return false }
        }
        for i in edges.indices {
            for j in edges.indices where j > i {
                if !Set(bridgeInterior(edges[i])).isDisjoint(with: bridgeInterior(edges[j])) { return false }
            }
        }
        guard clues.allSatisfy({ island, degree in active.reduce(0) { sum, entry in sum + ((entry.key.a == island || entry.key.b == island) ? entry.value : 0) } == degree }), let first = clues.keys.first else { return false }
        var seen: Set<Int> = [first], queue = [first]
        while let i = queue.popLast() {
            for e in active.keys {
                let next = e.a == i ? e.b : e.b == i ? e.a : -1
                if next >= 0 && seen.insert(next).inserted { queue.append(next) }
            }
        }
        return seen.count == clues.count
    }
    private func validNurikabe() -> Bool {
        let black = Set(cells.indices.filter { cells[$0] == 1 })
        guard connected(black) else { return false }
        for r in 0..<(n-1) { for c in 0..<(n-1) { let i = r*n+c; if [i,i+1,i+n,i+n+1].allSatisfy({ black.contains($0) }) { return false } } }
        var remaining = Set(cells.indices).subtracting(black)
        while let first = remaining.first {
            var island: Set<Int> = [first], queue = [first]; remaining.remove(first)
            while let i = queue.popLast() { for next in neighbors(i) where remaining.remove(next) != nil { island.insert(next); queue.append(next) } }
            let numbered = island.compactMap { clues[$0] }
            if numbered.count != 1 || numbered[0] != island.count { return false }
        }
        return true
    }
    private func validHitori() -> Bool {
        let white = Set(cells.indices.filter { cells[$0] == 0 })
        guard connected(white) else { return false }
        for i in cells.indices where cells[i] == 1 { if neighbors(i).contains(where: { cells[$0] == 1 }) { return false } }
        for i in 0..<n {
            let row = (0..<n).map { i*n+$0 }.filter { white.contains($0) }.compactMap { clues[$0] }
            let col = (0..<n).map { $0*n+i }.filter { white.contains($0) }.compactMap { clues[$0] }
            if Set(row).count != row.count || Set(col).count != col.count { return false }
        }
        return true
    }
    private func validTakuzu() -> Bool {
        guard !cells.contains(0) else { return false }
        let rows = (0..<n).map { r in (0..<n).map { cells[r*n+$0] } }
        let columns = (0..<n).map { c in (0..<n).map { cells[$0*n+c] } }
        for line in rows + columns {
            if line.filter({ $0 == 1 }).count != n/2 { return false }
            for i in 0..<(n-2) { if line[i] == line[i+1] && line[i] == line[i+2] { return false } }
        }
        return Set(rows).count == n && Set(columns).count == n
    }
    private func validTents() -> Bool {
        let tents = Set(cells.indices.filter { cells[$0] == 1 })
        guard tents.count == fixed.count else { return false }
        for i in tents {
            if tents.contains(where: { j in j != i && abs(i/n-j/n) <= 1 && abs(i%n-j%n) <= 1 }) { return false }
        }
        for i in 0..<n {
            if tents.filter({ $0/n == i }).count != rowTotals[i] || tents.filter({ $0%n == i }).count != columnTotals[i] { return false }
        }
        // A bijection is required: adjacency alone would allow two tents for one tree.
        let trees = fixed.sorted()
        func match(_ index: Int, _ available: Set<Int>) -> Bool {
            if index == trees.count { return available.isEmpty }
            for tent in neighbors(trees[index]) where available.contains(tent) {
                if match(index + 1, available.subtracting([tent])) { return true }
            }
            return false
        }
        return match(0, tents)
    }
    private var graph: [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        for edge in lines { result[edge.a, default: []].append(edge.b); result[edge.b, default: []].append(edge.a) }
        return result
    }
    private func validLoop() -> Bool {
        guard lines.allSatisfy({ (0..<(nodeSide*nodeSide)).contains($0.a) && neighbors($0.a, side:nodeSide).contains($0.b) }) else { return false }
        let graph = self.graph
        guard lines.count >= 4, graph.values.allSatisfy({ $0.count == 2 }), let first = graph.keys.first else { return false }
        var seen: Set<Int> = [first], queue = [first]
        while let i = queue.popLast() { for next in graph[i, default: []] where seen.insert(next).inserted { queue.append(next) } }
        return seen.count == graph.count
    }
    private func validMasyu() -> Bool {
        guard validLoop() else { return false }
        let graph = self.graph
        func straight(_ i: Int) -> Bool {
            let adj = graph[i, default: []]
            return adj.count == 2 && (adj[0] / n == adj[1] / n || adj[0] % n == adj[1] % n)
        }
        for (i, pearl) in clues {
            let adj = graph[i, default: []]
            guard adj.count == 2 else { return false }
            if pearl == 1 {
                if !straight(i) || !adj.contains(where: { !straight($0) }) { return false }
            } else if straight(i) || !adj.allSatisfy({ straight($0) }) { return false }
        }
        return true
    }
}
