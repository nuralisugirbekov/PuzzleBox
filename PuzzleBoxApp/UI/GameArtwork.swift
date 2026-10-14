import SwiftUI

// Flat illustrations for the game catalog, one scene per game. Each scene is
// drawn on a 160×160 canvas and scaled to fit whatever frame shows it (grid
// card, shelf tile, featured hero, rating thumbnail), over a full-bleed
// two-tone background.

// MARK: - Palette

private enum Ink {
    static let night = Color(0x1B1E3C)
    static let plum = Color(0x3A1C71)
    static let cream = Color(0xFFF6E5)
    static let sand = Color(0xF4D6A0)
    static let coral = Color(0xFF6B5B)
    static let rose = Color(0xFF4D6D)
    static let peach = Color(0xFF9F68)
    static let sun = Color(0xFFC93C)
    static let leaf = Color(0x7BC950)
    static let mint = Color(0x2ED69A)
    static let teal = Color(0x14B8A6)
    static let sky = Color(0x4CC9F0)
    static let ocean = Color(0x2F6BFF)
    static let grape = Color(0x7B5CFA)
    static let berry = Color(0xF15BB5)
    static let bark = Color(0x8B5A3C)
}

private extension Color {
    init(_ hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Canvas

struct GameArtwork: View {
    let gameID: GameID

    var body: some View {
        switch gameID {
        case .arrowMaze: RocketMazeArt()
        case .arrowEscape: ArrowEscapeArt()
        case .bounce: BounceArt()
        case .findColor: FindColorArt()
        case .findPair: FindPairArt()
        case .basketShot: BasketShotArt()
        case .bottleFlip: BottleFlipArt()
        case .miniGolf: MiniGolfArt()
        case .plinko: PlinkoArt()
        case .ropeCut: RopeCutArt()
        case .drawBridge: DrawBridgeArt()
        case .rotatePuzzle: RotatePuzzleArt()
        case .matchstick: MatchstickArt()
        case .slope: SlopeArt()
        case .circlePong: CirclePongArt()
        case .spaceDodge: SpaceDodgeArt()
        case .endlessClimb: EndlessClimbArt()
        case .redGreen: RedGreenArt()
        case .perfectTiming: PerfectTimingArt()
        case .bubblePop: BubblePopArt()
        case .whackMole: WhackMoleArt()
        case .chainReaction: ChainReactionArt()
        case .lightsOut: LightsOutArt()
        case .nonogram: NonogramArt()
        case .numberConnect: NumberConnectArt()
        case .oneLine: OneLineArt()
        case .unblock: UnblockArt()
        case .fifteenPuzzle: FifteenPuzzleArt()
        case .pipeConnect: PipeConnectArt()
        case .dots: DotsArt()
        case .floodFill: FloodFillArt()
        case .laser: LaserArt()
        case .colorLines: ColorLinesArt()
        case .stack: StackArt()
        case .knifeSpin: KnifeSpinArt()
        case .helixDrop: HelixDropArt()
        case .flappyFlight: FlappyFlightArt()
        case .roadHop: RoadHopArt()
        case .reactionTap: ReactionTapArt()
        case .simon: SimonArt()
        case .mergeFruit: MergeFruitArt()
        case .game2048: Game2048Art()
        case .quickMath: QuickMathArt()
        case .sudoku: SudokuArt()
        case .snake: SnakeArt()
        case .blockBlast: BlockBlastArt()
        case .waterSort: WaterSortArt()
        case .solitaire: SolitaireArt()
        case .spiderSolitaire: SpiderArt()
        case .freecell: FreeCellArt()
        case .minesweeper: MinesweeperArt()
        case .checkmate: CheckmateArt()
        case .crossword: CrosswordArt()
        case .asyk: AsykArt()
        case .togyzkumalak: TogyzArt()
        case .altybakan: AltybakanArt()
        case .kokpar: KokparArt()
        case .baige: BaigeArt()
        }
    }
}

/// Full-bleed gradient with a 160×160 scene scaled to fit and centred.
private struct ArtCanvas<Scene: View>: View {
    let colors: [Color]
    @ViewBuilder var scene: () -> Scene

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / 160
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                ZStack(content: scene)
                    .frame(width: 160, height: 160)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}

// MARK: - Building blocks

private extension View {
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { position(x: x, y: y) }
}

private func dot(_ color: Color, _ size: CGFloat) -> some View {
    Circle().fill(color).frame(width: size, height: size)
}

private func box(_ color: Color, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 4) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color).frame(width: width, height: height)
}

private func label(_ text: String, _ size: CGFloat, _ color: Color, weight: Font.Weight = .heavy) -> some View {
    Text(text).font(.system(size: size, weight: weight, design: .rounded)).foregroundStyle(color)
}

private func stroke(_ color: Color, _ width: CGFloat, dash: [CGFloat] = [],
                    _ build: @escaping (inout Path) -> Void) -> some View {
    Path { build(&$0) }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
}

/// A grid of cells laid out from a top-left origin.
private struct Cells<Cell: View>: View {
    let rows: Int, columns: Int
    let size: CGFloat, gap: CGFloat
    let origin: CGPoint
    @ViewBuilder let cell: (Int, Int) -> Cell

    var body: some View {
        ForEach(0..<rows * columns, id: \.self) { i in
            let r = i / columns, c = i % columns
            cell(r, c).at(origin.x + CGFloat(c) * (size + gap) + size / 2,
                          origin.y + CGFloat(r) * (size + gap) + size / 2)
        }
    }
}

/// A plain playing card for the card-game scenes.
private struct PlayingCard: View {
    let rank: String
    let suit: String   // hearts, diamonds, spades, clubs
    var width: CGFloat = 34

    private var red: Bool { suit == "hearts" || suit == "diamonds" }

    var body: some View {
        let height = width * 1.4
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(Ink.cream)
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                Text(rank)
                    .font(.system(size: width * 0.3, weight: .heavy, design: .rounded))
                    .padding(.leading, width * 0.1).padding(.top, width * 0.06)
            }
            .overlay {
                Image(systemName: "suit.\(suit.dropLast()).fill")
                    .font(.system(size: width * 0.42))
                    .offset(y: width * 0.12)
            }
            .foregroundStyle(red ? Ink.rose : Ink.night)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

/// A face-down card.
private struct CardBackArt: View {
    var width: CGFloat = 34
    var color = Ink.grape

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(color)
            .frame(width: width, height: width * 1.4)
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .strokeBorder(Ink.cream.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .padding(width * 0.12)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

private func stars(_ points: [(CGFloat, CGFloat, CGFloat)]) -> some View {
    ForEach(points.indices, id: \.self) { i in
        dot(Ink.cream.opacity(0.7), points[i].2).at(points[i].0, points[i].1)
    }
}

// MARK: - Arcade & action

private struct RocketMazeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.plum, Ink.night]) {
            stars([(18, 18, 2), (142, 22, 3), (130, 140, 2), (30, 146, 2), (100, 12, 2)])
            stroke(Ink.sky.opacity(0.55), 6) { p in
                p.move(to: .init(x: 22, y: 34)); p.addLine(to: .init(x: 138, y: 34))
                p.move(to: .init(x: 22, y: 34)); p.addLine(to: .init(x: 22, y: 128))
                p.addLine(to: .init(x: 84, y: 128))
                p.move(to: .init(x: 52, y: 64)); p.addLine(to: .init(x: 110, y: 64)); p.addLine(to: .init(x: 110, y: 100))
                p.move(to: .init(x: 138, y: 34)); p.addLine(to: .init(x: 138, y: 128)); p.addLine(to: .init(x: 116, y: 128))
            }
            ZStack {
                Capsule().fill(Ink.sun).frame(width: 9, height: 14).offset(y: 22)
                Capsule().fill(Ink.cream).frame(width: 18, height: 38)
                dot(Ink.sky, 8).offset(y: -6)
                box(Ink.coral, 7, 12, 2).offset(x: -11, y: 12)
                box(Ink.coral, 7, 12, 2).offset(x: 11, y: 12)
            }
            .rotationEffect(.degrees(45))
            .at(66, 98)
        }
    }
}

private struct ArrowEscapeArt: View {
    private let arrows = ["arrow.right", "arrow.down", "arrow.left", "arrow.up",
                          "arrow.up", "arrow.right", "arrow.down", "arrow.left",
                          "arrow.left", "arrow.up", "arrow.right", "arrow.down"]

    var body: some View {
        ArtCanvas(colors: [Ink.sun, Ink.peach]) {
            Cells(rows: 3, columns: 4, size: 28, gap: 6, origin: .init(x: 19, y: 34)) { r, c in
                box(Ink.cream.opacity(r == 1 && c == 3 ? 0.25 : 0.9), 28, 28, 8)
                    .overlay {
                        if !(r == 1 && c == 3) {
                            Image(systemName: arrows[r * 4 + c])
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Ink.night)
                        }
                    }
            }
            // The freed arrow leaving the board.
            box(Ink.coral, 28, 28, 8)
                .overlay {
                    Image(systemName: "arrow.right").font(.system(size: 14, weight: .black)).foregroundStyle(Ink.cream)
                }
                .shadow(color: Ink.coral.opacity(0.5), radius: 6)
                .at(150, 82)
        }
    }
}

private struct BounceArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.ocean]) {
            Capsule().fill(Ink.cream).frame(width: 46, height: 10).at(40, 128)
            Capsule().fill(Ink.cream).frame(width: 40, height: 10).at(116, 102)
            Capsule().fill(Ink.cream.opacity(0.6)).frame(width: 34, height: 10).at(78, 62)
            ForEach(0..<6, id: \.self) { i in
                let t = CGFloat(i) / 6
                dot(Ink.cream.opacity(0.15 + 0.1 * Double(i)), 6 + 4 * t)
                    .at(40 + 60 * t, 118 - 120 * t + 90 * t * t)
            }
            dot(Ink.coral, 24).shadow(color: .black.opacity(0.25), radius: 4, y: 3).at(104, 72)
        }
    }
}

private struct FindColorArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.grape, Ink.berry]) {
            Cells(rows: 4, columns: 4, size: 26, gap: 8, origin: .init(x: 16, y: 16)) { r, c in
                let odd = r == 2 && c == 1
                dot(odd ? Ink.mint.opacity(0.72) : Ink.mint, 26)
                    .overlay { if odd { Circle().stroke(Ink.cream, lineWidth: 3).padding(-5) } }
            }
        }
    }
}

private struct FindPairArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.teal, Ink.ocean]) {
            Cells(rows: 3, columns: 3, size: 38, gap: 8, origin: .init(x: 17, y: 17)) { r, c in
                let open = (r == 0 && c == 1) || (r == 2 && c == 2)
                box(open ? Ink.cream : Ink.night.opacity(0.55), 38, 38, 9)
                    .overlay {
                        if open {
                            Image(systemName: "star.fill").font(.system(size: 18)).foregroundStyle(Ink.sun)
                        } else {
                            dot(Ink.cream.opacity(0.25), 8)
                        }
                    }
            }
        }
    }
}

private struct BasketShotArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.peach, Ink.coral]) {
            box(Ink.cream, 56, 40, 4).overlay { box(.clear, 22, 16, 2).overlay(RoundedRectangle(cornerRadius: 2).stroke(Ink.coral, lineWidth: 2)) }
                .at(112, 36)
            stroke(Ink.cream.opacity(0.8), 1.5) { p in
                for i in 0..<5 {
                    let x = 98 + CGFloat(i) * 7
                    p.move(to: .init(x: x, y: 64)); p.addLine(to: .init(x: 104 + CGFloat(i) * 4, y: 82))
                }
            }
            Capsule().stroke(Ink.rose, lineWidth: 4).frame(width: 36, height: 8).at(112, 62)
            stroke(Ink.cream.opacity(0.7), 2.5, dash: [2, 7]) { p in
                p.move(to: .init(x: 40, y: 108)); p.addQuadCurve(to: .init(x: 106, y: 52), control: .init(x: 50, y: 4))
            }
            ZStack {
                dot(Color(0xF77F00), 30)
                stroke(Ink.night.opacity(0.6), 1.5) { p in
                    p.move(to: .init(x: 0, y: 15)); p.addLine(to: .init(x: 30, y: 15))
                    p.move(to: .init(x: 15, y: 0)); p.addLine(to: .init(x: 15, y: 30))
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            }
            .at(40, 108)
        }
    }
}

private struct BottleFlipArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.mint, Ink.teal]) {
            box(Ink.bark, 140, 10, 3).at(80, 140)
            Circle().trim(from: 0.55, to: 0.95)
                .stroke(Ink.cream.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6]))
                .frame(width: 100, height: 100).at(80, 92)
            ZStack {
                box(Ink.sky.opacity(0.9), 26, 50, 9)
                box(Ink.ocean, 26, 18, 6).offset(y: 16)
                box(Ink.sky.opacity(0.9), 12, 14, 3).offset(y: -30)
                box(Ink.coral, 14, 6, 2).offset(y: -38)
            }
            .rotationEffect(.degrees(-35))
            .at(84, 70)
        }
    }
}

private struct MiniGolfArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.leaf, Ink.mint]) {
            Ellipse().fill(Color(0x5FA83A)).frame(width: 140, height: 100).at(80, 88)
            Ellipse().fill(Ink.night).frame(width: 16, height: 9).at(112, 66)
            box(Ink.cream, 3, 46, 1).at(113, 44)
            stroke(Ink.coral, 1) { p in
                p.move(to: .init(x: 114, y: 22)); p.addLine(to: .init(x: 136, y: 29)); p.addLine(to: .init(x: 114, y: 36)); p.closeSubpath()
            }
            Path { p in
                p.move(to: .init(x: 114, y: 22)); p.addLine(to: .init(x: 136, y: 29)); p.addLine(to: .init(x: 114, y: 36)); p.closeSubpath()
            }.fill(Ink.coral)
            stroke(Ink.cream.opacity(0.7), 2.5, dash: [3, 6]) { p in
                p.move(to: .init(x: 44, y: 116)); p.addQuadCurve(to: .init(x: 108, y: 70), control: .init(x: 96, y: 124))
            }
            dot(Ink.cream, 12).shadow(color: .black.opacity(0.3), radius: 2, y: 2).at(44, 116)
        }
    }
}

private struct PlinkoArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.plum, Ink.grape]) {
            ForEach(0..<5, id: \.self) { row in
                ForEach(0...row + 1, id: \.self) { i in
                    dot(Ink.cream.opacity(0.8), 6)
                        .at(80 + (CGFloat(i) - CGFloat(row + 1) / 2) * 22, 28 + CGFloat(row) * 20)
                }
            }
            HStack(spacing: 4) {
                ForEach([Ink.coral, Ink.sun, Ink.mint, Ink.sun, Ink.coral], id: \.self) {
                    box($0, 22, 16, 4)
                }
            }
            .at(80, 130)
            dot(Ink.sun, 13).shadow(color: Ink.sun.opacity(0.7), radius: 6).at(91, 77)
        }
    }
}

private struct RopeCutArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Color(0xA0E7FF)]) {
            stroke(Ink.bark, 3) { p in
                p.move(to: .init(x: 28, y: 18)); p.addLine(to: .init(x: 78, y: 82))
                p.move(to: .init(x: 132, y: 18)); p.addLine(to: .init(x: 82, y: 82))
            }
            dot(Ink.night, 10).at(28, 18)
            dot(Ink.night, 10).at(132, 18)
            stroke(Ink.cream, 2.5, dash: [5, 4]) { p in
                p.move(to: .init(x: 96, y: 30)); p.addLine(to: .init(x: 124, y: 52))
            }
            Image(systemName: "scissors").font(.system(size: 18, weight: .bold)).foregroundStyle(Ink.night)
                .rotationEffect(.degrees(40)).at(130, 58)
            ZStack {
                box(Ink.berry, 12, 12, 2).rotationEffect(.degrees(45)).offset(x: -14)
                box(Ink.berry, 12, 12, 2).rotationEffect(.degrees(45)).offset(x: 14)
                dot(Ink.berry, 22)
                dot(Ink.cream.opacity(0.6), 6).offset(x: -4, y: -4)
            }
            .at(80, 88)
            ZStack {
                Ellipse().fill(Ink.leaf).frame(width: 46, height: 36)
                dot(Ink.cream, 10).offset(x: -9, y: -10)
                dot(Ink.cream, 10).offset(x: 9, y: -10)
                dot(Ink.night, 5).offset(x: -9, y: -10)
                dot(Ink.night, 5).offset(x: 9, y: -10)
                Capsule().fill(Ink.night).frame(width: 16, height: 6).offset(y: 6)
            }
            .at(80, 136)
        }
    }
}

private struct DrawBridgeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.ocean]) {
            box(Ink.sand, 46, 70, 8).at(20, 130)
            box(Ink.sand, 46, 70, 8).at(140, 130)
            stroke(Ink.night, 5) { p in
                p.move(to: .init(x: 42, y: 96)); p.addQuadCurve(to: .init(x: 118, y: 96), control: .init(x: 80, y: 124))
            }
            Image(systemName: "pencil").font(.system(size: 22, weight: .bold)).foregroundStyle(Ink.cream)
                .rotationEffect(.degrees(10)).at(124, 78)
            ZStack {
                box(Ink.coral, 30, 14, 5)
                box(Ink.coral, 16, 10, 3).offset(x: -2, y: -9)
                dot(Ink.night, 9).offset(x: -9, y: 8)
                dot(Ink.night, 9).offset(x: 9, y: 8)
            }
            .at(34, 80)
        }
    }
}

private struct SlopeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.ocean]) {
            stroke(Ink.mint.opacity(0.35), 18) { p in
                p.move(to: .init(x: 20, y: 20)); p.addLine(to: .init(x: 70, y: 60))
                p.addLine(to: .init(x: 40, y: 100)); p.addLine(to: .init(x: 110, y: 140))
            }
            stroke(Ink.mint, 4) { p in
                p.move(to: .init(x: 20, y: 20)); p.addLine(to: .init(x: 70, y: 60))
                p.addLine(to: .init(x: 40, y: 100)); p.addLine(to: .init(x: 110, y: 140))
            }
            dot(Ink.coral, 18).shadow(color: Ink.coral.opacity(0.8), radius: 8).at(58, 52)
        }
    }
}

private struct CirclePongArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.grape]) {
            Circle().stroke(Ink.cream.opacity(0.25), lineWidth: 3).frame(width: 128, height: 128).at(80, 80)
            Circle().trim(from: 0.66, to: 0.8)
                .stroke(Ink.sun, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: 128, height: 128).at(80, 80)
            ForEach(0..<4, id: \.self) { i in
                dot(Ink.coral.opacity(0.2 + 0.2 * Double(i)), 6 + CGFloat(i) * 2)
                    .at(60 + CGFloat(i) * 12, 70 + CGFloat(i) * 8)
            }
            dot(Ink.cream, 8).at(80, 80)
        }
    }
}

private struct SpaceDodgeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            stars([(20, 20, 2), (60, 14, 3), (140, 30, 2), (120, 70, 2), (24, 90, 3), (148, 120, 2)])
            Circle().fill(Ink.bark).frame(width: 34, height: 30).overlay { dot(Ink.night.opacity(0.3), 8).offset(x: -6, y: -4) }.at(42, 50)
            Circle().fill(Ink.peach).frame(width: 22, height: 20).at(122, 54)
            Circle().fill(Ink.bark).frame(width: 18, height: 18).at(108, 104)
            ZStack {
                Capsule().fill(Ink.sun).frame(width: 8, height: 16).offset(y: 22)
                Path { p in
                    p.move(to: .init(x: 16, y: 0)); p.addLine(to: .init(x: 32, y: 40))
                    p.addLine(to: .init(x: 16, y: 31)); p.addLine(to: .init(x: 0, y: 40)); p.closeSubpath()
                }
                .fill(Ink.mint)
                .frame(width: 32, height: 40)
                .offset(y: -4)
                dot(Ink.cream, 7).offset(y: -2)
            }
            .at(72, 112)
        }
    }
}

private struct EndlessClimbArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.mint]) {
            Capsule().fill(Ink.cream).frame(width: 40, height: 9).at(40, 140)
            Capsule().fill(Ink.cream).frame(width: 40, height: 9).at(110, 108)
            Capsule().fill(Ink.cream).frame(width: 40, height: 9).at(56, 72)
            Capsule().fill(Ink.cream.opacity(0.6)).frame(width: 40, height: 9).at(118, 36)
            ZStack {
                box(Ink.coral, 24, 24, 7)
                dot(Ink.cream, 7).offset(x: -4, y: -3)
                dot(Ink.cream, 7).offset(x: 5, y: -3)
                dot(Ink.night, 3.5).offset(x: -3, y: -3)
                dot(Ink.night, 3.5).offset(x: 6, y: -3)
            }
            .at(92, 82)
        }
    }
}

private struct RedGreenArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.rose, Ink.coral]) {
            box(Ink.night, 40, 76, 12).at(46, 70)
            dot(Ink.rose.opacity(0.35), 26).at(46, 50)
            dot(Ink.mint, 26).shadow(color: Ink.mint, radius: 10).at(46, 90)
            box(Ink.night, 6, 30, 2).at(46, 124)
            Image(systemName: "figure.run").font(.system(size: 54, weight: .bold)).foregroundStyle(Ink.cream)
                .at(112, 96)
            box(Ink.cream.opacity(0.5), 140, 4, 2).at(80, 140)
        }
    }
}

private struct PerfectTimingArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.grape, Ink.ocean]) {
            Capsule().fill(Ink.cream.opacity(0.25)).frame(width: 132, height: 22).at(80, 70)
            Capsule().fill(Ink.mint).frame(width: 30, height: 22).at(100, 70)
            Capsule().fill(Ink.sun).frame(width: 8, height: 38).shadow(color: Ink.sun, radius: 6).at(96, 70)
            Circle().stroke(Ink.cream.opacity(0.4), lineWidth: 3).frame(width: 44, height: 44).at(80, 122)
            dot(Ink.cream, 26).at(80, 122)
        }
    }
}

private struct BubblePopArt: View {
    private let bubbles: [(CGFloat, CGFloat, CGFloat)] = [(46, 50, 40), (108, 44, 30), (76, 104, 52), (130, 112, 24), (28, 120, 20)]

    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.berry]) {
            ForEach(bubbles.indices, id: \.self) { i in
                let b = bubbles[i]
                Circle().fill(Ink.cream.opacity(0.18))
                    .overlay(Circle().stroke(Ink.cream.opacity(0.8), lineWidth: 2))
                    .overlay(alignment: .topLeading) { dot(Ink.cream, b.2 * 0.18).padding(b.2 * 0.18) }
                    .frame(width: b.2, height: b.2)
                    .at(b.0, b.1)
            }
            stroke(Ink.cream, 3) { p in
                for a in stride(from: 0.0, to: 360.0, by: 45.0) {
                    let r = a * .pi / 180
                    p.move(to: .init(x: 132 + 10 * cos(r), y: 74 + 10 * sin(r)))
                    p.addLine(to: .init(x: 132 + 17 * cos(r), y: 74 + 17 * sin(r)))
                }
            }
        }
    }
}

private struct WhackMoleArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.leaf, Ink.teal]) {
            Ellipse().fill(Ink.night.opacity(0.6)).frame(width: 44, height: 16).at(36, 124)
            Ellipse().fill(Ink.night.opacity(0.6)).frame(width: 44, height: 16).at(124, 124)
            Ellipse().fill(Ink.night.opacity(0.6)).frame(width: 50, height: 18).at(80, 112)
            ZStack {
                box(Ink.bark, 38, 44, 18)
                dot(Ink.night, 6).offset(x: -8, y: -6)
                dot(Ink.night, 6).offset(x: 8, y: -6)
                Ellipse().fill(Ink.berry).frame(width: 12, height: 8).offset(y: 4)
            }
            .mask(Rectangle().frame(height: 44).offset(y: -4))
            .at(80, 92)
            ZStack {
                box(Ink.sand, 6, 46, 3).offset(y: 18)
                box(Ink.coral, 34, 20, 6)
            }
            .rotationEffect(.degrees(-30))
            .at(122, 48)
        }
    }
}

private struct ChainReactionArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.grape]) {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(Ink.sun.opacity(0.8 - 0.25 * Double(i)), lineWidth: 3)
                    .frame(width: 30 + CGFloat(i) * 22, height: 30 + CGFloat(i) * 22).at(60, 74)
            }
            Circle().stroke(Ink.coral, lineWidth: 3).frame(width: 34, height: 34).at(118, 52)
            Circle().stroke(Ink.mint, lineWidth: 3).frame(width: 24, height: 24).at(112, 122)
            dot(Ink.sun, 14).at(60, 74)
            dot(Ink.coral, 10).at(118, 52)
            dot(Ink.mint, 8).at(112, 122)
            dot(Ink.sky, 8).at(30, 130)
            dot(Ink.berry, 8).at(140, 90)
        }
    }
}

private struct StackArt: View {
    private let colors = [Ink.grape, Ink.ocean, Ink.sky, Ink.mint, Ink.sun]

    var body: some View {
        ArtCanvas(colors: [Ink.peach, Ink.berry]) {
            ForEach(0..<5, id: \.self) { i in
                box(colors[i], 90 - CGFloat(i) * 6, 16, 4)
                    .at(80 + (i == 4 ? 18 : CGFloat(i % 2) * 4), 140 - CGFloat(i) * 18)
            }
            stroke(Ink.cream.opacity(0.8), 2.5) { p in
                p.move(to: .init(x: 144, y: 60)); p.addLine(to: .init(x: 156, y: 60))
                p.move(to: .init(x: 146, y: 72)); p.addLine(to: .init(x: 156, y: 72))
            }
        }
    }
}

private struct KnifeSpinArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.plum, Ink.night]) {
            ZStack {
                ForEach([0.0, 120, 230], id: \.self) { angle in
                    ZStack {
                        Capsule().fill(Ink.cream).frame(width: 6, height: 24).offset(y: -50)
                        box(Ink.night, 8, 14, 2).offset(y: -66)
                    }
                    .rotationEffect(.degrees(angle))
                }
                Circle().fill(Ink.sand).frame(width: 76, height: 76)
                Circle().stroke(Ink.peach, lineWidth: 3).frame(width: 52, height: 52)
                Circle().stroke(Ink.peach, lineWidth: 3).frame(width: 26, height: 26)
            }
            .at(80, 66)
            ZStack {
                Capsule().fill(Ink.cream).frame(width: 6, height: 24)
                box(Ink.coral, 8, 14, 2).offset(y: 18)
            }
            .at(80, 136)
        }
    }
}

private struct HelixDropArt: View {
    private let colors = [Ink.coral, Ink.sun, Ink.mint, Ink.berry]
    /// Where each disc's gap sits, as an x offset from the pole.
    private let gaps: [CGFloat] = [28, -30, 14, -16]

    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.grape]) {
            box(Ink.cream.opacity(0.9), 16, 160, 8).at(80, 80)
            ForEach(0..<4, id: \.self) { i in
                disc(colors[i], gap: gaps[i]).at(80, 40 + CGFloat(i) * 32)
            }
            dot(Ink.cream, 14).shadow(color: .black.opacity(0.2), radius: 3, y: 2).at(108, 22)
            stroke(Ink.cream.opacity(0.6), 2.5, dash: [2, 5]) { p in
                p.move(to: .init(x: 108, y: 30)); p.addLine(to: .init(x: 108, y: 34))
            }
        }
    }

    private func disc(_ color: Color, gap: CGFloat) -> some View {
        Capsule().fill(color).frame(width: 120, height: 14)
            .mask {
                Rectangle().overlay { Capsule().frame(width: 22, height: 20).offset(x: gap).blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}

private struct FlappyFlightArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Ink.mint]) {
            box(Ink.leaf, 30, 56, 4).at(118, 26)
            box(Ink.leaf, 30, 50, 4).at(118, 138)
            box(Color(0x5FA83A), 38, 10, 3).at(118, 58)
            box(Color(0x5FA83A), 38, 10, 3).at(118, 110)
            ZStack {
                Ellipse().fill(Ink.sun).frame(width: 34, height: 28)
                Ellipse().fill(Ink.cream).frame(width: 16, height: 10).offset(x: -6, y: 4).rotationEffect(.degrees(-20))
                dot(Ink.cream, 11).offset(x: 8, y: -5)
                dot(Ink.night, 5).offset(x: 10, y: -5)
                Path { p in
                    p.move(to: .init(x: 14, y: 0)); p.addLine(to: .init(x: 26, y: 4)); p.addLine(to: .init(x: 14, y: 8)); p.closeSubpath()
                }
                .fill(Ink.peach).frame(width: 0, height: 0).offset(x: 0, y: 0)
            }
            .rotationEffect(.degrees(-12))
            .at(56, 84)
        }
    }
}

private struct RoadHopArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.leaf, Color(0x5FA83A)]) {
            box(Ink.night.opacity(0.85), 220, 40, 0).at(80, 62)
            box(Ink.night.opacity(0.85), 220, 40, 0).at(80, 120)
            stroke(Ink.cream.opacity(0.7), 3, dash: [10, 8]) { p in
                p.move(to: .init(x: 0, y: 62)); p.addLine(to: .init(x: 160, y: 62))
                p.move(to: .init(x: 0, y: 120)); p.addLine(to: .init(x: 160, y: 120))
            }
            box(Ink.coral, 40, 22, 6).overlay { box(Ink.sky.opacity(0.7), 12, 14, 2).offset(x: 8) }.at(46, 52)
            box(Ink.sky, 44, 22, 6).at(126, 128)
            ZStack {
                box(Ink.cream, 22, 22, 6)
                box(Ink.rose, 8, 6, 2).offset(y: -13)
                Path { p in
                    p.move(to: .init(x: 11, y: -2)); p.addLine(to: .init(x: 18, y: 1)); p.addLine(to: .init(x: 11, y: 4)); p.closeSubpath()
                }.fill(Ink.sun).frame(width: 0, height: 0)
                dot(Ink.night, 4).offset(x: 4, y: -3)
            }
            .at(96, 92)
        }
    }
}

private struct ReactionTapArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.rose, Ink.coral]) {
            Circle().stroke(Ink.cream.opacity(0.25), lineWidth: 4).frame(width: 136, height: 136).at(80, 80)
            Circle().stroke(Ink.cream.opacity(0.45), lineWidth: 4).frame(width: 106, height: 106).at(80, 80)
            dot(Ink.cream, 76).at(80, 80)
            Image(systemName: "bolt.fill").font(.system(size: 40, weight: .black)).foregroundStyle(Ink.sun).at(80, 80)
        }
    }
}

private struct SimonArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            ZStack {
                quadrant(Ink.mint, start: 180, lit: false)
                quadrant(Ink.rose, start: 270, lit: true)
                quadrant(Ink.ocean, start: 0, lit: false)
                quadrant(Ink.sun, start: 90, lit: false)
                dot(Ink.night, 40)
            }
            .at(80, 80)
        }
    }

    private func quadrant(_ color: Color, start: Double, lit: Bool) -> some View {
        Path { p in
            p.addArc(center: .init(x: 65, y: 65), radius: 64, startAngle: .degrees(start + 3),
                     endAngle: .degrees(start + 87), clockwise: false)
            p.addArc(center: .init(x: 65, y: 65), radius: 26, startAngle: .degrees(start + 87),
                     endAngle: .degrees(start + 3), clockwise: true)
            p.closeSubpath()
        }
        .fill(lit ? color : color.opacity(0.55))
        .shadow(color: lit ? color : .clear, radius: 10)
        .frame(width: 130, height: 130)
    }
}

private struct MergeFruitArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.peach, Ink.sand]) {
            stroke(Ink.cream, 5) { p in
                p.move(to: .init(x: 26, y: 44)); p.addLine(to: .init(x: 26, y: 146))
                p.addLine(to: .init(x: 134, y: 146)); p.addLine(to: .init(x: 134, y: 44))
            }
            dot(Ink.leaf, 52).at(60, 118)
            dot(Ink.sun, 34).at(108, 126)
            dot(Ink.berry, 26).at(102, 98)
            dot(Ink.grape, 18).at(48, 84)
            dot(Ink.coral, 22).at(80, 26)
            box(Ink.bark, 3, 8, 1).at(80, 12)
        }
    }
}

// MARK: - Puzzles

/// A picture (sun over a hill) cut into 2×2 tiles, one of them turned.
private struct RotatePuzzleArt: View {
    private let tile: CGFloat = 60, gap: CGFloat = 6

    var body: some View {
        ArtCanvas(colors: [Ink.berry, Ink.grape]) {
            ForEach(0..<4, id: \.self) { i in
                let r = i / 2, c = i % 2
                picture
                    .offset(x: (0.5 - CGFloat(c)) * (tile + gap), y: (0.5 - CGFloat(r)) * (tile + gap))
                    .frame(width: tile, height: tile)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .rotationEffect(.degrees(i == 1 ? 90 : 0))
                    .shadow(color: .black.opacity(i == 1 ? 0.3 : 0), radius: 6, y: 3)
                    .at(80 + (CGFloat(c) - 0.5) * (tile + gap), 80 + (CGFloat(r) - 0.5) * (tile + gap))
            }
            dot(Ink.cream, 26)
                .overlay { Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .black)).foregroundStyle(Ink.grape) }
                .at(113 + 26, 47 - 26)
        }
    }

    /// The whole picture, centred on the 2×2 grid.
    private var picture: some View {
        ZStack {
            Rectangle().fill(Ink.sky)
            dot(Ink.sun, 52).offset(x: 14, y: -16)
            Ellipse().fill(Ink.leaf).frame(width: 190, height: 110).offset(y: 50)
        }
        .frame(width: tile * 2 + gap, height: tile * 2 + gap)
    }
}

/// Seven-segment matchstick digits.
private struct MatchstickArt: View {
    // Segments a b c d e f g for the digits used below.
    private static let digits: [Character: [Bool]] = [
        "4": [false, true, true, false, false, true, true],
        "3": [true, true, true, true, false, false, true],
        "7": [true, true, true, false, false, false, false],
    ]

    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            digit("4").at(26, 80)
            match(horizontal: true).at(55, 80)
            match(horizontal: false, length: 18).at(55, 80)
            digit("3").at(84, 80)
            match(horizontal: true, length: 18).at(110, 74)
            match(horizontal: true, length: 18).at(110, 86)
            digit("7").at(138, 80)
            // The match being moved.
            match(horizontal: false).rotationEffect(.degrees(30)).shadow(color: Ink.sun, radius: 6).at(110, 128)
        }
    }

    private func match(horizontal: Bool, length: CGFloat = 22) -> some View {
        ZStack(alignment: horizontal ? .trailing : .top) {
            Capsule().fill(Ink.sand).frame(width: horizontal ? length : 4, height: horizontal ? 4 : length)
            dot(Ink.coral, 6)
        }
    }

    private func digit(_ d: Character) -> some View {
        let s = Self.digits[d] ?? []
        let w: CGFloat = 20, h: CGFloat = 22
        let positions: [(CGFloat, CGFloat, Bool)] = [
            (0, -h, true), (w / 2, -h / 2, false), (w / 2, h / 2, false), (0, h, true),
            (-w / 2, h / 2, false), (-w / 2, -h / 2, false), (0, 0, true),
        ]
        return ZStack {
            ForEach(0..<7, id: \.self) { i in
                if s[i] {
                    match(horizontal: positions[i].2, length: 20).offset(x: positions[i].0, y: positions[i].1)
                }
            }
        }
    }
}

private struct LightsOutArt: View {
    private let lit: Set<Int> = [1, 5, 6, 7, 11, 13, 17, 18, 19, 23]

    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.ocean]) {
            Cells(rows: 5, columns: 5, size: 22, gap: 6, origin: .init(x: 13, y: 13)) { r, c in
                let on = lit.contains(r * 5 + c)
                box(on ? Ink.sun : Ink.cream.opacity(0.12), 22, 22, 6)
                    .shadow(color: on ? Ink.sun.opacity(0.8) : .clear, radius: 6)
            }
        }
    }
}

private struct NonogramArt: View {
    private let heart = ["011011", "111111", "111111", "011110", "001100", "000000"]

    var body: some View {
        ArtCanvas(colors: [Ink.cream, Ink.sand]) {
            Cells(rows: 6, columns: 6, size: 17, gap: 2, origin: .init(x: 40, y: 40)) { r, c in
                let filled = Array(heart[r])[c] == "1"
                box(filled ? Ink.night : Ink.cream, 17, 17, 3)
                    .overlay {
                        if !filled && r == 5 && c == 0 { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.coral) }
                    }
            }
            ForEach(Array(["2 2", "6", "6", "4", "2", "0"].enumerated()), id: \.offset) { i, clue in
                label(clue, 9, Ink.grape).at(22, 48.5 + CGFloat(i) * 19)
            }
            ForEach(Array(["2", "4", "5", "5", "4", "2"].enumerated()), id: \.offset) { i, clue in
                label(clue, 9, Ink.grape).at(48.5 + CGFloat(i) * 19, 26)
            }
        }
    }
}

private struct NumberConnectArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.cream, Color(0xDDF3FF)]) {
            Cells(rows: 5, columns: 5, size: 24, gap: 3, origin: .init(x: 13, y: 13)) { _, _ in
                box(Ink.night.opacity(0.06), 24, 24, 5)
            }
            stroke(Ink.coral, 10) { p in
                p.move(to: .init(x: 25, y: 25)); p.addLine(to: .init(x: 106, y: 25)); p.addLine(to: .init(x: 106, y: 52))
            }
            stroke(Ink.ocean, 10) { p in
                p.move(to: .init(x: 25, y: 52)); p.addLine(to: .init(x: 25, y: 133)); p.addLine(to: .init(x: 79, y: 133))
            }
            stroke(Ink.mint, 10) { p in
                p.move(to: .init(x: 52, y: 79)); p.addLine(to: .init(x: 133, y: 79)); p.addLine(to: .init(x: 133, y: 133))
            }
            ForEach(Array([(25.0, 25.0, Ink.coral, "1"), (106, 52, Ink.coral, "1"), (25, 52, Ink.ocean, "2"),
                           (79, 133, Ink.ocean, "2"), (52, 79, Ink.mint, "3"), (133, 133, Ink.mint, "3")].enumerated()),
                    id: \.offset) { _, p in
                dot(p.2, 20).overlay { label(p.3, 11, Ink.cream) }.at(p.0, p.1)
            }
        }
    }
}

private struct OneLineArt: View {
    private let points: [CGPoint] = [.init(x: 80, y: 22), .init(x: 132, y: 66), .init(x: 132, y: 136),
                                     .init(x: 28, y: 136), .init(x: 28, y: 66), .init(x: 132, y: 136)]

    var body: some View {
        ArtCanvas(colors: [Ink.ocean, Ink.grape]) {
            stroke(Ink.sun, 6) { p in
                p.move(to: points[0])
                for point in points.dropFirst().dropLast() { p.addLine(to: point) }
                p.addLine(to: points[0])
            }
            stroke(Ink.cream.opacity(0.6), 4, dash: [4, 6]) { p in
                p.move(to: points[4]); p.addLine(to: points[5])
            }
            ForEach(points.indices.dropLast(), id: \.self) { i in
                dot(Ink.cream, 14).overlay(Circle().stroke(Ink.night, lineWidth: 3)).at(points[i].x, points[i].y)
            }
            dot(Ink.coral, 16).shadow(color: Ink.coral, radius: 6).at(28, 66)
        }
    }
}

private struct UnblockArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sand, Ink.peach]) {
            box(Ink.night.opacity(0.18), 132, 132, 14).at(80, 80)
            box(Ink.night.opacity(0.18), 10, 22, 2).at(149, 66)
            box(Ink.grape, 20, 62, 6).at(36, 52)
            box(Ink.ocean, 62, 20, 6).at(96, 36)
            box(Ink.cream, 20, 62, 6).at(122, 110)
            box(Ink.teal, 62, 20, 6).at(58, 124)
            box(Ink.rose, 52, 20, 6).overlay {
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .black)).foregroundStyle(Ink.cream)
            }
            .shadow(color: Ink.rose.opacity(0.5), radius: 5)
            .at(84, 66)
        }
    }
}

private struct FifteenPuzzleArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.ocean, Ink.sky]) {
            box(Ink.night.opacity(0.25), 140, 140, 14).at(80, 80)
            Cells(rows: 4, columns: 4, size: 30, gap: 4, origin: .init(x: 13, y: 13)) { r, c in
                let n = r * 4 + c + 1
                if n < 15 {
                    box(Ink.cream, 30, 30, 7).overlay { label("\(n)", 13, Ink.ocean) }
                }
            }
            box(Ink.sun, 30, 30, 7).overlay { label("15", 13, Ink.night) }
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .at(13 + 2 * 34 + 15 + 17, 13 + 3 * 34 + 15)
        }
    }
}

private struct PipeConnectArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.teal, Ink.night]) {
            Cells(rows: 4, columns: 4, size: 32, gap: 4, origin: .init(x: 10, y: 10)) { _, _ in
                box(Ink.cream.opacity(0.12), 32, 32, 6)
            }
            stroke(Ink.cream.opacity(0.35), 10) { p in
                p.move(to: .init(x: 98, y: 26)); p.addLine(to: .init(x: 134, y: 26))
                p.move(to: .init(x: 62, y: 134)); p.addLine(to: .init(x: 62, y: 98))
            }
            stroke(Ink.sky, 10) { p in
                p.move(to: .init(x: 4, y: 26)); p.addLine(to: .init(x: 62, y: 26)); p.addLine(to: .init(x: 62, y: 62))
                p.addLine(to: .init(x: 98, y: 62)); p.addLine(to: .init(x: 98, y: 98)); p.addLine(to: .init(x: 134, y: 98))
                p.addLine(to: .init(x: 134, y: 134)); p.addLine(to: .init(x: 156, y: 134))
            }
            dot(Ink.sun, 14).at(8, 26)
        }
    }
}

private struct DotsArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.cream, Ink.sand]) {
            box(Ink.coral.opacity(0.35), 36, 36, 2).at(52, 52)
            box(Ink.ocean.opacity(0.35), 36, 36, 2).at(88, 88)
            stroke(Ink.coral, 5) { p in
                p.move(to: .init(x: 34, y: 34)); p.addLine(to: .init(x: 70, y: 34)); p.addLine(to: .init(x: 70, y: 70))
                p.addLine(to: .init(x: 34, y: 70)); p.closeSubpath()
            }
            stroke(Ink.ocean, 5) { p in
                p.move(to: .init(x: 70, y: 70)); p.addLine(to: .init(x: 106, y: 70)); p.addLine(to: .init(x: 106, y: 106))
                p.addLine(to: .init(x: 70, y: 106)); p.addLine(to: .init(x: 70, y: 70))
                p.move(to: .init(x: 106, y: 34)); p.addLine(to: .init(x: 142, y: 34))
            }
            stroke(Ink.night.opacity(0.3), 4, dash: [3, 5]) { p in
                p.move(to: .init(x: 106, y: 106)); p.addLine(to: .init(x: 142, y: 106))
            }
            Cells(rows: 4, columns: 4, size: 10, gap: 26, origin: .init(x: 29, y: 29)) { _, _ in dot(Ink.night, 10) }
            label("A", 16, Ink.coral).at(52, 52)
            label("B", 16, Ink.ocean).at(88, 88)
        }
    }
}

private struct FloodFillArt: View {
    private let colors = [Ink.coral, Ink.sun, Ink.mint, Ink.ocean]
    private let board = ["000112", "001132", "021233", "221033", "122003", "211300"]

    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            Cells(rows: 6, columns: 6, size: 20, gap: 0, origin: .init(x: 20, y: 12)) { r, c in
                let v = Int(String(Array(board[r])[c])) ?? 0
                Rectangle().fill(colors[v]).frame(width: 20, height: 20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    dot(colors[i], 20).overlay(Circle().stroke(Ink.cream, lineWidth: i == 0 ? 3 : 0))
                }
            }
            .at(80, 145)
        }
    }
}

private struct LaserArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            stroke(Ink.rose, 4) { p in
                p.move(to: .init(x: 26, y: 40)); p.addLine(to: .init(x: 110, y: 40))
                p.addLine(to: .init(x: 110, y: 104)); p.addLine(to: .init(x: 52, y: 104)); p.addLine(to: .init(x: 52, y: 134))
            }
            .shadow(color: Ink.rose, radius: 6)
            box(Ink.grape, 20, 20, 5).overlay { dot(Ink.rose, 8) }.at(18, 40)
            Capsule().fill(Ink.cream).frame(width: 30, height: 6).rotationEffect(.degrees(45)).at(110, 40)
            Capsule().fill(Ink.cream).frame(width: 30, height: 6).rotationEffect(.degrees(45)).at(110, 104)
            Capsule().fill(Ink.cream).frame(width: 30, height: 6).rotationEffect(.degrees(-45)).at(52, 104)
            Circle().stroke(Ink.mint, lineWidth: 4).frame(width: 22, height: 22).overlay { dot(Ink.mint, 10) }.at(52, 140)
        }
    }
}

private struct ColorLinesArt: View {
    private let balls: [Int: Color] = [7: Ink.grape, 9: Ink.sun, 14: Ink.ocean, 21: Ink.coral, 28: Ink.coral,
                                       30: Ink.mint, 33: Ink.sun]

    var body: some View {
        ArtCanvas(colors: [Ink.sand, Ink.cream]) {
            Cells(rows: 6, columns: 6, size: 22, gap: 2, origin: .init(x: 8, y: 8)) { r, c in
                let i = r * 6 + c
                box(Ink.night.opacity(r == 2 ? 0.16 : 0.07), 22, 22, 4)
                    .overlay {
                        if r == 2 && c >= 1 {
                            dot(Ink.berry, 16).shadow(color: Ink.berry.opacity(0.6), radius: 4)
                        } else if let color = balls[i] {
                            dot(color, 16)
                        }
                    }
            }
        }
    }
}

private struct Game2048Art: View {
    private let tiles: [(String, Color, Color)] = [
        ("2", Ink.cream, Ink.night), ("4", Ink.sand, Ink.night), ("8", Ink.peach, Ink.cream), ("16", Ink.coral, Ink.cream),
        ("", .clear, .clear), ("32", Ink.rose, Ink.cream), ("64", Ink.berry, Ink.cream), ("4", Ink.sand, Ink.night),
        ("2", Ink.cream, Ink.night), ("128", Ink.grape, Ink.cream), ("", .clear, .clear), ("2", Ink.cream, Ink.night),
        ("", .clear, .clear), ("8", Ink.peach, Ink.cream), ("2048", Ink.sun, Ink.night), ("", .clear, .clear),
    ]

    var body: some View {
        ArtCanvas(colors: [Ink.sand, Ink.peach]) {
            box(Ink.bark.opacity(0.35), 146, 146, 14).at(80, 80)
            Cells(rows: 4, columns: 4, size: 31, gap: 4, origin: .init(x: 13, y: 13)) { r, c in
                let t = tiles[r * 4 + c]
                box(t.0.isEmpty ? Ink.cream.opacity(0.25) : t.1, 31, 31, 6)
                    .overlay { label(t.0, t.0.count > 3 ? 9 : 13, t.2).minimumScaleFactor(0.5) }
                    .shadow(color: t.0 == "2048" ? Ink.sun : .clear, radius: 6)
            }
        }
    }
}

private struct QuickMathArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.grape, Ink.ocean]) {
            box(Ink.cream, 120, 54, 14).overlay { label("7 × 6", 26, Ink.night) }.at(80, 48)
            HStack(spacing: 8) {
                box(Ink.cream.opacity(0.25), 36, 34, 10).overlay { label("36", 14, Ink.cream) }
                box(Ink.mint, 36, 34, 10).overlay { label("42", 14, Ink.night) }
                box(Ink.cream.opacity(0.25), 36, 34, 10).overlay { label("48", 14, Ink.cream) }
            }
            .at(80, 106)
            Capsule().fill(Ink.cream.opacity(0.25)).frame(width: 120, height: 8).at(80, 142)
            Capsule().fill(Ink.sun).frame(width: 74, height: 8).at(57, 142)
        }
    }
}

private struct SudokuArt: View {
    private let digits: [Int: String] = [0: "5", 2: "1", 4: "8", 7: "3", 9: "2", 13: "6", 15: "7", 17: "4",
                                         19: "9", 22: "5", 25: "1", 30: "4", 33: "2", 36: "6", 38: "3", 42: "9",
                                         46: "8", 49: "7", 53: "1", 56: "6", 58: "2", 61: "5", 65: "9", 70: "3", 72: "4", 76: "8", 78: "2", 80: "7"]

    var body: some View {
        ArtCanvas(colors: [Ink.cream, Color(0xDDF3FF)]) {
            Cells(rows: 9, columns: 9, size: 15, gap: 1, origin: .init(x: 8, y: 8)) { r, c in
                let i = r * 9 + c
                box(i == 40 ? Ink.sky : Ink.cream, 15, 15, 1)
                    .overlay { label(digits[i] ?? "", 10, i == 40 ? Ink.cream : Ink.night, weight: .bold) }
            }
            stroke(Ink.night, 2.5) { p in
                for k in 0...3 {
                    let v = 7.5 + CGFloat(k) * 48
                    p.move(to: .init(x: v, y: 7.5)); p.addLine(to: .init(x: v, y: 151.5))
                    p.move(to: .init(x: 7.5, y: v)); p.addLine(to: .init(x: 151.5, y: v))
                }
            }
        }
    }
}

private struct SnakeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.teal]) {
            Cells(rows: 8, columns: 8, size: 18, gap: 2, origin: .init(x: 1, y: 1)) { r, c in
                box(Ink.cream.opacity((r + c).isMultiple(of: 2) ? 0.05 : 0.1), 18, 18, 3)
            }
            stroke(Ink.mint, 15) { p in
                p.move(to: .init(x: 30, y: 130)); p.addLine(to: .init(x: 30, y: 90)); p.addLine(to: .init(x: 90, y: 90))
                p.addLine(to: .init(x: 90, y: 50)); p.addLine(to: .init(x: 116, y: 50))
            }
            dot(Ink.cream, 6).at(118, 45)
            dot(Ink.cream, 6).at(118, 55)
            dot(Ink.night, 3).at(119, 45)
            dot(Ink.night, 3).at(119, 55)
            ZStack {
                dot(Ink.rose, 18)
                Ellipse().fill(Ink.leaf).frame(width: 9, height: 5).rotationEffect(.degrees(-30)).offset(x: 4, y: -10)
            }
            .at(130, 110)
        }
    }
}

private struct BlockBlastArt: View {
    private let board = ["..GG....", "..G..BB.", "RRR..BB.", "......Y.", ".PP...Y.", ".PP..YY.", "........"]

    var body: some View {
        ArtCanvas(colors: [Ink.ocean, Ink.grape]) {
            box(Ink.night.opacity(0.45), 146, 128, 12).at(80, 66)
            Cells(rows: 7, columns: 8, size: 15, gap: 2, origin: .init(x: 13, y: 9)) { r, c in
                box(color(Array(board[r])[c]), 15, 15, 3)
            }
            HStack(spacing: 2) {
                box(Ink.coral, 15, 15, 3)
                box(Ink.coral, 15, 15, 3)
            }
            .overlay(alignment: .topLeading) { box(Ink.coral, 15, 15, 3).offset(y: -17) }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
            .at(46, 146)
        }
    }

    private func color(_ code: Character) -> Color {
        switch code {
        case "G": Ink.mint
        case "B": Ink.sky
        case "R": Ink.rose
        case "Y": Ink.sun
        case "P": Ink.berry
        default: Ink.cream.opacity(0.1)
        }
    }
}

private struct WaterSortArt: View {
    private let tubes: [[Color]] = [[Ink.coral, Ink.sky, Ink.sun], [Ink.mint, Ink.mint, Ink.coral],
                                    [Ink.sky, Ink.sun, Ink.mint, Ink.sky]]

    var body: some View {
        ArtCanvas(colors: [Ink.teal, Ink.ocean]) {
            ForEach(tubes.indices, id: \.self) { i in
                tube(tubes[i]).at(34 + CGFloat(i) * 40, 96)
            }
            tube([Ink.coral]).rotationEffect(.degrees(-55)).at(134, 54)
            stroke(Ink.coral, 5) { p in
                p.move(to: .init(x: 118, y: 66)); p.addQuadCurve(to: .init(x: 112, y: 90), control: .init(x: 110, y: 74))
            }
        }
    }

    private func tube(_ layers: [Color]) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(layers.indices.reversed(), id: \.self) { i in
                Rectangle().fill(layers[i]).frame(height: 16)
            }
        }
        .frame(width: 26, height: 80)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 13, bottomTrailingRadius: 13))
        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 13, bottomTrailingRadius: 13).stroke(Ink.cream, lineWidth: 3))
    }
}

private struct MinesweeperArt: View {
    private let cells: [Int: (String, Color)] = [6: ("1", Ink.ocean), 7: ("1", Ink.ocean), 8: ("2", Ink.mint),
                                                 11: ("1", Ink.ocean), 13: ("3", Ink.coral), 16: ("2", Ink.mint), 18: ("1", Ink.ocean)]
    private let open: Set<Int> = [5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18, 20, 21, 22]

    var body: some View {
        ArtCanvas(colors: [Ink.sand, Ink.peach]) {
            Cells(rows: 5, columns: 5, size: 26, gap: 3, origin: .init(x: 8, y: 8)) { r, c in
                let i = r * 5 + c
                box(open.contains(i) ? Ink.cream : Ink.leaf, 26, 26, 5)
                    .overlay {
                        if let n = cells[i] {
                            label(n.0, 14, n.1)
                        } else if i == 3 || i == 24 {
                            ZStack {
                                box(Ink.night, 2, 16, 1).offset(x: -4)
                                Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 10, y: 4)); p.addLine(to: .init(x: 0, y: 8)) }
                                    .fill(Ink.rose).frame(width: 10, height: 8).offset(x: 1, y: -4)
                            }
                        }
                    }
            }
            ZStack {
                stroke(Ink.night, 3) { p in
                    for a in stride(from: 0.0, to: 180.0, by: 45.0) {
                        let r = a * .pi / 180
                        p.move(to: .init(x: 13 - 11 * cos(r), y: 13 - 11 * sin(r)))
                        p.addLine(to: .init(x: 13 + 11 * cos(r), y: 13 + 11 * sin(r)))
                    }
                }
                .frame(width: 26, height: 26)
                dot(Ink.night, 14)
                dot(Ink.cream, 4).offset(x: -3, y: -3)
            }
            .at(50, 21)
        }
    }
}

private struct CheckmateArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.cream, Ink.sand]) {
            Cells(rows: 4, columns: 4, size: 36, gap: 0, origin: .init(x: 8, y: 8)) { r, c in
                Rectangle().fill((r + c).isMultiple(of: 2) ? Ink.sand : Ink.bark.opacity(0.75)).frame(width: 36, height: 36)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("♚").font(.system(size: 64)).foregroundStyle(Ink.night).at(98, 70)
            Text("♛").font(.system(size: 48)).foregroundStyle(Ink.rose).at(44, 60)
            Circle().stroke(Ink.rose, lineWidth: 4).frame(width: 60, height: 60).at(98, 76)
        }
    }
}

private struct CrosswordArt: View {
    // "PUZZLE" across, "PLAY" down from the P, "ZEN" down from the second Z.
    private let letters: [String: String] = ["1,0": "P", "1,1": "U", "1,2": "Z", "1,3": "Z", "1,4": "L", "1,5": "E",
                                             "2,0": "L", "3,0": "A", "4,0": "Y", "2,3": "E", "3,3": "N"]
    var body: some View {
        ArtCanvas(colors: [Ink.grape, Ink.ocean]) {
            Cells(rows: 6, columns: 6, size: 22, gap: 3, origin: .init(x: 7, y: 10)) { r, c in
                if let letter = letters["\(r),\(c)"] {
                    box(r == 1 ? Ink.sun : Ink.cream, 22, 22, 4)
                        .overlay { label(letter, 13, Ink.night) }
                } else {
                    box(Ink.cream.opacity(0.08), 22, 22, 4)
                }
            }
            label("1", 7, Ink.night, weight: .bold).at(12, 41)
        }
    }
}

private struct TogyzArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(0xC98A4B), Ink.bark]) {
            box(Color(0x6E4220).opacity(0.55), 144, 98, 18).at(80, 80)
            // Two rows of five pits with pebbles; the top row is the opponent's.
            ForEach(0..<10, id: \.self) { i in
                let row = i / 5, col = i % 5
                let center = CGPoint(x: 28 + CGFloat(col) * 26, y: 56 + CGFloat(row) * 50)
                dot(Color(0x2A1608), 22).at(center.x, center.y)
                ForEach(0..<[5, 3, 6, 2, 4, 7, 3, 5, 4, 6][i], id: \.self) { k in
                    let a = CGFloat(k) / CGFloat([5, 3, 6, 2, 4, 7, 3, 5, 4, 6][i]) * .pi * 2
                    dot(Ink.cream.opacity(0.9), 5).at(center.x + cos(a) * 6.5, center.y + sin(a) * 6.5)
                }
            }
            // The tuzdyk star.
            label("★", 14, Ink.sun).at(80 + 26, 56)
            box(Ink.sun, 40, 8, 4).at(48, 128)
            box(Ink.sky, 40, 8, 4).at(112, 128)
        }
    }
}

private struct AltybakanArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Color(0xFFD9A0)]) {
            dot(Ink.sun, 26).at(124, 36)
            // A-frame and the swing.
            stroke(Ink.bark, 7) { p in
                p.move(to: .init(x: 80, y: 26)); p.addLine(to: .init(x: 34, y: 140))
                p.move(to: .init(x: 80, y: 26)); p.addLine(to: .init(x: 126, y: 140))
            }
            stroke(Ink.cream, 2.5) { p in
                p.move(to: .init(x: 76, y: 28)); p.addLine(to: .init(x: 52, y: 110))
                p.move(to: .init(x: 84, y: 28)); p.addLine(to: .init(x: 70, y: 110))
            }
            box(Ink.bark, 34, 7, 3).rotationEffect(.degrees(-18)).at(61, 113)
            dot(Ink.rose, 12).at(56, 98); dot(Ink.ocean, 12).at(68, 98)
            // Bells on the arc.
            ForEach(0..<3, id: \.self) { i in
                label("🔔", 15, Ink.sun).at(118 - CGFloat(i) * 6, 70 + CGFloat(i) * 22)
            }
            Rectangle().fill(Ink.leaf).frame(width: 160, height: 22).at(80, 150)
        }
    }
}

private struct KokparArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(0x4FA33A), Color(0x2F7A2B)]) {
            ForEach(0..<4, id: \.self) { i in
                Rectangle().fill(Color.white.opacity(i.isMultiple(of: 2) ? 0.07 : 0)).frame(width: 160, height: 40).at(80, 20 + CGFloat(i) * 40)
            }
            // The kazan at the top.
            dot(Color.white.opacity(0.4), 70).at(80, 34)
            dot(Ink.night, 40).at(80, 34)
            Circle().stroke(Ink.sun, lineWidth: 5).frame(width: 40, height: 40).at(80, 34)
            // A rival rider and the player carrying the serke.
            Capsule().fill(Color(0x5C5C66)).frame(width: 18, height: 42).at(44, 76)
            dot(Ink.ocean, 14).at(44, 76)
            Capsule().fill(Ink.bark).frame(width: 20, height: 46).at(96, 118)
            dot(Ink.rose, 16).at(96, 120)
            dot(Ink.sun, 11).at(96, 114)
            Capsule().fill(Color(0xA8743A)).frame(width: 12, height: 26).rotationEffect(.degrees(70)).at(112, 118)
        }
    }
}

private struct BaigeArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sky, Color(0xFFDCA8)]) {
            dot(Ink.sun, 28).at(122, 34)
            Rectangle().fill(Ink.leaf).frame(width: 160, height: 40).at(80, 142)
            // Fence and coins.
            box(Ink.bark, 5, 28, 2).at(104, 112); box(Ink.bark, 5, 28, 2).at(124, 112); box(Ink.bark, 26, 5, 2).at(114, 104)
            ForEach(0..<3, id: \.self) { i in dot(Ink.sun, 9).at(70 + CGFloat(i) * 18, 62 + (i == 1 ? -8 : 0)) }
            // Horse and rider mid-jump.
            Capsule().fill(Ink.bark).frame(width: 54, height: 22).rotationEffect(.degrees(-14)).at(54, 100)
            Capsule().fill(Ink.bark).frame(width: 12, height: 26).rotationEffect(.degrees(40)).at(80, 84)
            Capsule().fill(Ink.bark).frame(width: 22, height: 10).rotationEffect(.degrees(20)).at(90, 74)
            Capsule().fill(Ink.night).frame(width: 30, height: 4).rotationEffect(.degrees(-30)).at(28, 100)
            dot(Ink.ocean, 14).at(52, 82); dot(Ink.sun, 9).at(60, 72)
            Capsule().fill(Ink.night).frame(width: 4, height: 18).rotationEffect(.degrees(-20)).at(38, 118)
            Capsule().fill(Ink.night).frame(width: 4, height: 18).rotationEffect(.degrees(25)).at(70, 116)
        }
    }
}

private struct AsykArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.sand, Ink.peach]) {
            Circle().stroke(Ink.bark, lineWidth: 4).frame(width: 128, height: 128).at(80, 72)
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill([Ink.cream, Ink.rose, Ink.sky, Ink.mint, Ink.grape][i]).frame(width: 18, height: 12)
                    .overlay { Capsule().stroke(Ink.night.opacity(0.25), lineWidth: 1) }
                    .rotationEffect(.degrees(90))
                    .at(44 + CGFloat(i) * 18, 72)
            }
            Capsule().fill(Ink.coral).frame(width: 28, height: 18)
                .overlay { Capsule().stroke(Ink.sun, lineWidth: 2) }
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .at(40, 136)
            stroke(Ink.cream, 3, dash: [5, 5]) { p in p.move(to: .init(x: 46, y: 124)); p.addLine(to: .init(x: 62, y: 86)) }
        }
    }
}

// MARK: - Cards

private struct SolitaireArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(0x1F7A4D), Ink.teal]) {
            PlayingCard(rank: "A", suit: "hearts").at(30, 36)
            PlayingCard(rank: "A", suit: "spades").at(70, 36)
            CardBackArt().at(130, 36)
            ForEach(Array([("K", "spades"), ("Q", "hearts"), ("J", "clubs"), ("10", "diamonds")].enumerated()), id: \.offset) { i, card in
                PlayingCard(rank: card.0, suit: card.1, width: 38).at(80, 86 + CGFloat(i) * 14)
            }
        }
    }
}

private struct SpiderArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.night, Ink.plum]) {
            ForEach(0..<4, id: \.self) { i in
                PlayingCard(rank: ["K", "Q", "J", "10"][i], suit: "spades", width: 34)
                    .rotationEffect(.degrees(Double(i - 2) * 9))
                    .at(60 + CGFloat(i) * 16, 104)
            }
            stroke(Ink.cream, 2.5) { p in
                for side in [-1.0, 1.0] {
                    for k in 0..<4 {
                        let y = 34 + CGFloat(k) * 6
                        p.move(to: .init(x: 80 + side * 8, y: y))
                        p.addQuadCurve(to: .init(x: 80 + side * 30, y: y + 14), control: .init(x: 80 + side * 26, y: y - 10))
                    }
                }
                p.move(to: .init(x: 80, y: 8)); p.addLine(to: .init(x: 80, y: 30))
            }
            dot(Ink.night, 24).overlay(Circle().stroke(Ink.cream, lineWidth: 2.5)).at(80, 52)
            dot(Ink.night, 16).overlay(Circle().stroke(Ink.cream, lineWidth: 2.5)).at(80, 36)
            dot(Ink.rose, 4).at(77, 34)
            dot(Ink.rose, 4).at(83, 34)
        }
    }
}

private struct FreeCellArt: View {
    var body: some View {
        ArtCanvas(colors: [Ink.ocean, Ink.night]) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.cream.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 30, height: 42).at(26 + CGFloat(i) * 36, 32)
            }
            PlayingCard(rank: "7", suit: "diamonds", width: 30).at(62, 32)
            ForEach(0..<3, id: \.self) { col in
                ForEach(0..<3, id: \.self) { row in
                    PlayingCard(rank: ["9", "5", "Q", "8", "J", "3", "6", "K", "2"][col * 3 + row],
                                suit: ["clubs", "hearts", "spades"][(col + row) % 3], width: 34)
                        .at(40 + CGFloat(col) * 40, 90 + CGFloat(row) * 16)
                }
            }
        }
    }
}
