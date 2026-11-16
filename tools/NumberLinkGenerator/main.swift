// Offline Number Link level generator.
// Builds a full-cover solution from a random Hamiltonian path cut into "taut" segments
// (no path touches itself), then proves uniqueness with a solver that does NOT require
// filling the board. Unique + full-cover candidate => the only solution covers every cell.
//
// Proof sketch: any solution with a self-touching path can be shortcut into another,
// strictly smaller solution, so if a second solution exists, a taut second solution exists.
// Hence counting taut solutions (stop at 2) is enough.
import Foundation

struct RNG: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

func neighbors(_ i: Int, _ n: Int) -> [Int] {
    var r: [Int] = []; let y = i / n, x = i % n
    if y > 0 { r.append(i - n) }; if y < n - 1 { r.append(i + n) }
    if x > 0 { r.append(i - 1) }; if x < n - 1 { r.append(i + 1) }
    return r
}

/// Random Hamiltonian path via backbite moves from a serpentine.
func hamiltonian(_ n: Int, _ rng: inout RNG) -> [Int] {
    var path = (0..<n).flatMap { r in (0..<n).map { r * n + (r % 2 == 0 ? $0 : n - 1 - $0) } }
    for _ in 0..<(n * n * 60) {
        if Bool.random(using: &rng) { path.reverse() }
        let end = path[path.count - 1]
        let cand = neighbors(end, n).filter { $0 != path[path.count - 2] }
        guard let pick = cand.randomElement(using: &rng) else { continue }
        let k = path.firstIndex(of: pick)!
        path = Array(path[0...k]) + path[(k + 1)...].reversed()
    }
    return path
}

/// Cuts the Hamiltonian path into taut segments of length >= 3.
func cut(_ path: [Int], _ n: Int, maxLen: Int, _ rng: inout RNG) -> [[Int]]? {
    var segs: [[Int]] = []; var cur: [Int] = []
    for cell in path {
        let touches = cur.dropLast().contains { neighbors(cell, n).contains($0) }
        if touches || cur.count >= maxLen || (cur.count >= 3 && Int.random(in: 0..<100, using: &rng) < 8) {
            if cur.count < 3 { return nil }
            segs.append(cur); cur = []
        }
        cur.append(cell)
    }
    if cur.count < 3 { return nil }
    segs.append(cur)
    return segs
}

final class Solver {
    let n: Int; let N: Int
    var owner: [Int]          // -1 free, else color
    var ends: [(Int, Int)]
    var solutions = 0; var nodes = 0; let nodeLimit: Int
    init(n: Int, ends: [(Int, Int)], nodeLimit: Int) {
        self.n = n; N = n * n; self.ends = ends; self.nodeLimit = nodeLimit
        owner = Array(repeating: -1, count: n * n)
        for (c, e) in ends.enumerated() { owner[e.0] = c; owner[e.1] = c }
    }
    lazy var nb: [[Int]] = (0..<N).map { neighbors($0, n) }

    /// Can head reach target through free cells?
    func reachable(_ from: Int, _ to: Int) -> Bool {
        var seen = [Bool](repeating: false, count: N); var stack = [from]; seen[from] = true
        while let x = stack.popLast() {
            for y in nb[x] where !seen[y] {
                if y == to { return true }
                if owner[y] == -1 { seen[y] = true; stack.append(y) }
            }
        }
        return false
    }
    func feasible(_ done: Int, head: Int, color: Int) -> Bool {
        if !reachable(head, ends[color].1) { return false }
        for c in (color + 1)..<ends.count where !reachable(ends[c].0, ends[c].1) { return false }
        return true
    }
    func solve() { if feasibleStart() { extend(color: 0, head: ends[0].0, prev: -1) } }
    func feasibleStart() -> Bool { (0..<ends.count).allSatisfy { reachable(ends[$0].0, ends[$0].1) || nb[ends[$0].0].contains(ends[$0].1) } }

    func extend(color: Int, head: Int, prev: Int) {
        if solutions >= 2 || nodes > nodeLimit { return }
        nodes += 1
        let target = ends[color].1
        for x in nb[head] where x != prev {
            if x == target {
                // Tautness: target must touch no own cell other than head.
                if nb[x].contains(where: { $0 != head && owner[$0] == color }) { continue }
                if color + 1 == ends.count { solutions += 1; return }
                let next = color + 1
                if feasible(0, head: ends[next].0, color: next) || nb[ends[next].0].contains(ends[next].1) {
                    extend(color: next, head: ends[next].0, prev: -1)
                }
                if solutions >= 2 { return }
                continue
            }
            guard owner[x] == -1 else { continue }
            if nb[x].contains(where: { $0 != head && $0 != target && owner[$0] == color }) { continue }
            owner[x] = color
            if feasible(0, head: x, color: color) { extend(color: color, head: x, prev: head) }
            owner[x] = -1
            if solutions >= 2 { return }
        }
    }
}

struct Level { let n: Int; let segs: [[Int]]; let nodes: Int }

func encode(_ l: Level) -> (String, String) {
    let letters = Array("abcdefghijkl")
    var puzzle = Array(repeating: Character("."), count: l.n * l.n)
    var sol = puzzle
    for (c, s) in l.segs.enumerated() {
        puzzle[s.first!] = letters[c]; puzzle[s.last!] = letters[c]
        for x in s { sol[x] = letters[c] }
    }
    return (String(puzzle), String(sol))
}

let sizes: [(n: Int, pairs: ClosedRange<Int>, count: Int)] = [
    (5, 4...5, 12), (6, 5...6, 12), (7, 6...7, 12), (8, 7...8, 12), (9, 8...9, 12),
]
var rng = RNG(s: 20261115)
var out = "// Generated by the offline Number Link generator. Every level has exactly one\n// solution, and that solution covers every cell.\n// puzzle: '.' empty, letters = pair endpoints; solution: owner letter per cell.\nenum NumberLinkLevels {\n    static let all: [(size: Int, puzzle: String, solution: String)] = [\n"
for spec in sizes {
    var found: [Level] = []; var seen = Set<String>()
    var tries = 0
    while found.count < spec.count * 3 && tries < 400000 {
        tries += 1
        let path = hamiltonian(spec.n, &rng)
        guard let segs = cut(path, spec.n, maxLen: spec.n * 3, &rng), spec.pairs.contains(segs.count) else { continue }
        // Endpoints should not be adjacent (a trivial pair).
        if segs.contains(where: { neighbors($0.first!, spec.n).contains($0.last!) }) { continue }
        let ends = segs.map { ($0.first!, $0.last!) }.sorted { a, b in
            abs(a.0 / spec.n - a.1 / spec.n) + abs(a.0 % spec.n - a.1 % spec.n) < abs(b.0 / spec.n - b.1 / spec.n) + abs(b.0 % spec.n - b.1 % spec.n)
        }
        let solver = Solver(n: spec.n, ends: ends, nodeLimit: 3_000_000)
        solver.solve()
        guard solver.solutions == 1, solver.nodes <= 3_000_000 else { continue }
        let level = Level(n: spec.n, segs: segs, nodes: solver.nodes)
        let key = encode(level).0
        if seen.insert(key).inserted { found.append(level) }
    }
    FileHandle.standardError.write("n=\(spec.n): \(found.count) unique levels from \(tries) tries\n".data(using: .utf8)!)
    // Pick an even spread of difficulty, ordered easy -> hard by solver effort.
    let sorted = found.sorted { $0.nodes < $1.nodes }
    let picks = (0..<spec.count).map { sorted[min(sorted.count - 1, $0 * sorted.count / spec.count + sorted.count / (spec.count * 2))] }
    for l in picks {
        let (p, s) = encode(l)
        out += "        (\(l.n), \"\(p)\", \"\(s)\"), // pairs \(l.segs.count), effort \(l.nodes)\n"
    }
}
out += "    ]\n}\n"
print(out, terminator: "")
