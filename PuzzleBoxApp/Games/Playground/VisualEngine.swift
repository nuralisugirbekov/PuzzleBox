import SwiftUI
import Observation

enum VisualMode:String,CaseIterable {
    case spotDifference,hiddenObject,shadowMatch,rotatePuzzle,symmetry,patternMatch,tangram,pixelPuzzle,foldIt,matchstick
    var id:GameID { GameID(rawValue:rawValue)! }
    var title:String {
        switch self {
        case .spotDifference:"Spot the Difference"
        case .hiddenObject:"Find Hidden Object"
        case .shadowMatch:"Shadow Match"
        case .rotatePuzzle:"Rotate Puzzle"
        case .symmetry:"Symmetry"
        case .patternMatch:"Pattern Match"
        case .tangram:"Tangram"
        case .pixelPuzzle:"Pixel Puzzle"
        case .foldIt:"Fold It"
        case .matchstick:"Matchstick Puzzle"
        }
    }
    var hint:String {
        switch self {
        case .spotDifference:"Find three differences. Tap them in the lower picture."
        case .hiddenObject:"Find the pictured object among the other objects."
        case .shadowMatch:"Choose the silhouette that matches the colored shape."
        case .rotatePuzzle:"Tap each tile to rotate it and restore the picture."
        case .symmetry:"Tap the right half to mirror the left half."
        case .patternMatch:"Choose the symbol that continues the pattern."
        case .tangram:"Select a piece, rotate it and drag it into the square silhouette."
        case .pixelPuzzle:"Choose a color and paint the grid to match the small picture."
        case .foldIt:"The shaded paper is folded and punched. Choose the unfolded hole pattern."
        case .matchstick:"Move exactly one match: tap a lit segment, then an empty segment. Fix the equation."
        }
    }
}

@MainActor @Observable
final class VisualEngine:GameEngine {
    let mode:VisualMode
    var state:GameState = .playing
    private(set) var score = 0
    private(set) var cells:[Int] = []
    private(set) var reference:[Int] = []
    private(set) var options:[Int] = []
    private(set) var patterns:[[Int]] = []
    private(set) var marks:Set<Int> = []
    private(set) var targets:Set<Int> = []
    private(set) var moves = 0
    private(set) var feedback = ""
    private(set) var selected = 0
    private(set) var piecePosition = CGPoint(x:160,y:365)
    private(set) var turns:[Int] = []
    private(set) var paint = 1
    private(set) var foldAxis = 0
    private(set) var hole = 10
    private(set) var selectedMatch:Int?
    private var answer = 0
    static let palette:[Color] = [Theme.surfaceHigh,.pink,.cyan,.orange,.green]
    static let pieces:[[CGPoint]] = [
        [CGPoint(x:0,y:0),CGPoint(x:4,y:0),CGPoint(x:2,y:2)],
        [CGPoint(x:0,y:0),CGPoint(x:2,y:2),CGPoint(x:0,y:4)],
        [CGPoint(x:4,y:2),CGPoint(x:4,y:4),CGPoint(x:2,y:4)],
        [CGPoint(x:4,y:0),CGPoint(x:4,y:2),CGPoint(x:3,y:1)],
        [CGPoint(x:2,y:2),CGPoint(x:3,y:1),CGPoint(x:4,y:2),CGPoint(x:3,y:3)],
        [CGPoint(x:2,y:2),CGPoint(x:1,y:3),CGPoint(x:3,y:3)],
        [CGPoint(x:0,y:4),CGPoint(x:1,y:3),CGPoint(x:3,y:3),CGPoint(x:2,y:4)]
    ]
    static let digitMasks = [63,6,91,79,102,109,125,7,127,111]
    init(mode:VisualMode) { self.mode = mode; restart() }
    func restart() {
        state = .playing; score = 0; moves = 0; cells = []; reference = []; options = []; patterns = []; marks = []; targets = []; feedback = ""; selected = 0; paint = 1; selectedMatch = nil
        switch mode {
        case .spotDifference:
            reference = (0..<16).map { _ in Int.random(in:0..<8) }; cells = reference
            targets = Set(Array(0..<16).shuffled().prefix(3)); for i in targets { cells[i] = (cells[i]+Int.random(in:1...7))%8 }
        case .hiddenObject:
            answer = Int.random(in:0..<36); let symbol = Int.random(in:0..<12); reference = [symbol]
            cells = (0..<36).map { _ in (symbol+Int.random(in:1...11))%12 }; cells[answer] = symbol
        case .shadowMatch:
            options = Array(0..<6).shuffled().prefix(4).map { $0 }; answer = Int.random(in:0..<4); reference = [options[answer]]
        case .rotatePuzzle:
            cells = (0..<9).map { _ in Int.random(in:0..<4) }; if cells.allSatisfy({ $0 == 0 }) { cells[0] = 1 }
        case .symmetry:
            reference = Array(repeating:0,count:36)
            for r in 0..<6 { for c in 0..<3 { let value = Int.random(in:0...1); reference[r*6+c] = value; reference[r*6+5-c] = value } }
            reference[0] = 1; reference[5] = 1
            cells = reference.enumerated().map { $0.offset%6 < 3 ? $0.element : 0 }
        case .patternMatch:
            let cycle = Array(0..<8).shuffled().prefix(Int.random(in:2...3)).map { $0 }
            reference = (0..<5).map { cycle[$0%cycle.count] }; let expected = cycle[5%cycle.count]
            options = ([expected]+Array(Array(0..<8).filter { $0 != expected }.shuffled().prefix(3))).shuffled(); answer = options.firstIndex(of:expected)!
        case .tangram:
            turns = (0..<7).map { _ in Int.random(in:0..<4) }; piecePosition = CGPoint(x:160,y:365)
        case .pixelPuzzle:
            let templates = [
                [0,1,0,1,0,1,1,1,1,1,1,1,1,1,1,0,1,1,1,0,0,0,1,0,0],
                [0,0,1,0,0,0,1,1,1,0,1,1,1,1,1,0,0,2,0,0,0,0,2,0,0],
                [0,1,1,1,0,1,2,1,2,1,1,1,1,1,1,0,1,2,1,0,0,1,0,1,0]
            ]
            let colors = Array(1...4).shuffled(); reference = templates.randomElement()!.map { $0 == 0 ? 0 : colors[$0-1] }; cells = Array(repeating:0,count:25)
        case .foldIt:
            foldAxis = Int.random(in:0..<3); hole = Int.random(in:2...3)*4+Int.random(in:2...3)
            let r = hole/4,c = hole%4
            var holes:Set<Int> = [hole]
            if foldAxis != 1 { holes.insert(r*4+3-c) }
            if foldAxis != 0 { for i in Array(holes) { holes.insert((3-i/4)*4+i%4) } }
            let right = (0..<16).map { holes.contains($0) ? 1 : 0 }
            patterns = [right]
            for shift in 1...3 { patterns.append((0..<16).map { right[(($0/4+shift)%4)*4+($0%4+1)%4] }) }
            // Distinct alternatives; an impossible extra hole is preferable to duplicate answers.
            for i in 1..<4 { if patterns.prefix(i).contains(patterns[i]) { patterns[i] = right; patterns[i][i-1] = 1-patterns[i][i-1] } }
            let order = Array(0..<4).shuffled(); patterns = order.map { patterns[$0] }; answer = order.firstIndex(of:0)!
        case .matchstick: makeMatches()
        }
    }
    private func win() { score = max(100,1000-moves*10); state = .gameOver(won:true); Haptics.success() }
    func tap(_ i:Int) {
        guard state == .playing else { return }; feedback = ""
        switch mode {
        case .spotDifference:
            guard cells.indices.contains(i),!marks.contains(i) else { return }; moves += 1
            if targets.contains(i) { marks.insert(i); if marks == targets { win() } } else { feedback = "Try again" }
        case .hiddenObject,.shadowMatch,.patternMatch,.foldIt:
            moves += 1; if i == answer { win() } else { feedback = "Try again" }
        case .rotatePuzzle:
            guard cells.indices.contains(i) else { return }; moves += 1; cells[i] = (cells[i]+1)%4
            if cells.allSatisfy({ $0 == 0 }) { win() }
        case .symmetry:
            guard cells.indices.contains(i),i%6 >= 3 else { return }; moves += 1; cells[i] = 1-cells[i]; if cells == reference { win() }
        case .pixelPuzzle:
            guard cells.indices.contains(i) else { return }; moves += 1; cells[i] = paint; if cells == reference { win() }
        case .matchstick: match(i)
        case .tangram: break
        }
    }
    func color(_ value:Int) { guard (0...4).contains(value) else { return }; paint = value }
    func selectPiece(_ i:Int) { guard state == .playing,(0..<7).contains(i),!marks.contains(i) else { return }; selected = i; piecePosition = CGPoint(x:160,y:365) }
    func rotatePiece() { guard state == .playing else { return }; turns[selected] = (turns[selected]+1)%4; moves += 1 }
    static func centroid(_ i:Int) -> CGPoint { let points = pieces[i]; return CGPoint(x:points.map(\.x).reduce(0,+)/CGFloat(points.count),y:points.map(\.y).reduce(0,+)/CGFloat(points.count)) }
    static func targetCenter(_ i:Int) -> CGPoint { let p = centroid(i); return CGPoint(x:40+p.x*60,y:30+p.y*60) }
    func movePiece(_ p:CGPoint) { guard state == .playing,!marks.contains(selected) else { return }; piecePosition = CGPoint(x:min(310,max(10,p.x)),y:min(430,max(10,p.y))) }
    func dropPiece() {
        guard state == .playing,!marks.contains(selected) else { return }; moves += 1
        let center = Self.targetCenter(selected)
        let orientation = turns[selected] == 0 || selected == 4 || (selected == 6 && turns[selected] == 2)
        if orientation && hypot(piecePosition.x-center.x,piecePosition.y-center.y) < 22 {
            marks.insert(selected); Haptics.tap()
            if marks.count == 7 { win() }
            else { selected = (0..<7).first { !marks.contains($0) }!; piecePosition = CGPoint(x:160,y:365) }
        }
    }
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
    private func makeMatches() {
        for _ in 0..<100 {
            let a = Int.random(in:0...9),b = Int.random(in:0...9),plus = Bool.random(),c = plus ? a+b : a-b
            guard (0...9).contains(c) else { continue }
            let solved = encoded(a,b,c,plus)
            for from in solved.indices.filter({ solved[$0] == 1 }).shuffled() {
                for to in solved.indices.filter({ solved[$0] == 0 }).shuffled() {
                    var candidate = solved; candidate[from] = 0; candidate[to] = 1
                    if equation(candidate) != nil && !correct(candidate) { cells = candidate; return }
                }
            }
        }
        cells = encoded(6,4,4,true) // Move the vertical match of '+' to make 8 − 4 = 4.
    }
    private func match(_ i:Int) {
        guard cells.indices.contains(i) else { return }
        if cells[i] == 1 { selectedMatch = selectedMatch == i ? nil : i; return }
        guard let from = selectedMatch else { return }; moves += 1
        var proposed = cells; proposed[from] = 0; proposed[i] = 1; selectedMatch = nil
        if correct(proposed) { cells = proposed; win() } else { feedback = "Try again"; Haptics.error() }
    }
}
