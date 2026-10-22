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

/// Colours taken from the games themselves, so a preview looks like the
/// screen it opens.
private enum Arena {
    /// `arenaBackground()`: the dark play-field most games sit on.
    static let top = Color(red: 0.12, green: 0.13, blue: 0.19)
    static let bottom = Color(red: 0.065, green: 0.075, blue: 0.105)
    static let colors = [top, bottom]
    /// Empty board cells (`tertiarySystemFill` on a dark board).
    static let cell = Color(white: 0.2)
    /// Board panels (`secondarySystemBackground`, dark).
    static let panel = Color(white: 0.11)
    static let cardRed = Color(red: 0xDB / 255, green: 0x0A / 255, blue: 0x17 / 255)
    static let cardBlack = Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x17 / 255)
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
        case .mazePaint: MazePaintArt()
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
        case .durak: DurakArt()
        case .hangman: HangmanArt()
        case .battleship: BattleshipArt()
        case .minesweeper: MinesweeperArt()
        case .checkmate: CheckmateArt()
        case .gems: GemsArt()
        case .gemsArcade: GemsArcadeArt()
        case .gemsBlitz: GemsArt(blitz: true)
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

/// A playing card as the card games draw it (`CardKit`): white face, thin
/// black rim, the games' red and black inks.
private struct PlayingCard: View {
    let rank: String
    let suit: String   // hearts, diamonds, spades, clubs
    var width: CGFloat = 34

    private var red: Bool { suit == "hearts" || suit == "diamonds" }

    var body: some View {
        let height = width * 1.4
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(Color.white)
            .overlay { RoundedRectangle(cornerRadius: width * 0.14, style: .continuous).strokeBorder(Color.black, lineWidth: 0.5) }
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
            .foregroundStyle(red ? Arena.cardRed : Arena.cardBlack)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

/// A face-down card: the games' blue back with a light inner rim.
private struct CardBackArt: View {
    var width: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
            .fill(Color.blue.gradient)
            .frame(width: width, height: width * 1.4)
            .overlay {
                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                    .padding(width * 0.1)
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

// MARK: - Cards


// MARK: - Shared game pieces

/// The glossy ball the puzzle collection draws (`PuzzleCollectionView.ball`).
private func shinyBall(_ color: Color, _ size: CGFloat) -> some View {
    Circle()
        .fill(RadialGradient(colors: [.white.opacity(0.9), color, color.opacity(0.75)],
                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
        .frame(width: size, height: size)
}

/// A bent Arrow Escape arrow through `points`, its head on the last one.
private func escapeArrow(_ points: [CGPoint], _ color: Color, width: CGFloat = 6) -> some View {
    Path { p in
        p.move(to: points[0])
        for q in points.dropFirst() { p.addLine(to: q) }
        let a = points[points.count - 2], b = points[points.count - 1]
        let length = max(1, hypot(b.x - a.x, b.y - a.y))
        let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length, size = width * 1.4
        p.move(to: CGPoint(x: b.x - dx * size - dy * size * 0.75, y: b.y - dy * size + dx * size * 0.75))
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x - dx * size + dy * size * 0.75, y: b.y - dy * size - dx * size * 0.75))
    }
    .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

/// A gradient tile like the puzzle boards' `tile(_:_:_:)`.
private func gradientTile(_ top: Color, _ bottom: Color, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
        .frame(width: width, height: height)
}

// MARK: - Puzzle boards

private struct ArrowEscapeArt: View {
    private func c(_ i: Int) -> CGFloat { 17.5 + 25 * CGFloat(i) }

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 6, columns: 6, size: 22, gap: 3, origin: .init(x: 6.5, y: 6.5)) { _, _ in
                box(Color.blue.opacity(0.1), 22, 22, 5)
            }
            // The game's palette: primary, blue, indigo, teal.
            escapeArrow([.init(x: c(0), y: c(0)), .init(x: c(0), y: c(2)), .init(x: c(2), y: c(2))], .white)
            escapeArrow([.init(x: c(1), y: c(0)), .init(x: c(4), y: c(0))], .blue)
            escapeArrow([.init(x: c(5), y: c(0)), .init(x: c(5), y: c(3)), .init(x: c(3), y: c(3))], .indigo)
            escapeArrow([.init(x: c(3), y: c(1)), .init(x: c(4), y: c(1)), .init(x: c(4), y: c(2))], .teal)
            escapeArrow([.init(x: c(0), y: c(5)), .init(x: c(0), y: c(3))], .blue)
            escapeArrow([.init(x: c(1), y: c(3)), .init(x: c(1), y: c(4)), .init(x: c(4), y: c(4))], .teal)
            escapeArrow([.init(x: c(2), y: c(5)), .init(x: c(4), y: c(5))], .white)
            escapeArrow([.init(x: c(5), y: c(4)), .init(x: c(5), y: c(5))], .indigo)
        }
    }
}

private struct LightsOutArt: View {
    private let lit: Set<Int> = [1, 3, 5, 7, 8]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 3, columns: 3, size: 44, gap: 4, origin: .init(x: 10, y: 10)) { r, c in
                if lit.contains(r * 3 + c) {
                    gradientTile(Color(red: 1, green: 0.95, blue: 0.6), .orange, 44, 44, 8)
                        .shadow(color: .yellow.opacity(0.45), radius: 6)
                } else {
                    gradientTile(Color(white: 0.24), Color(white: 0.16), 44, 44, 8)
                }
            }
        }
    }
}

private struct NumberConnectArt: View {
    private func c(_ i: Int) -> CGFloat { 20 + 30 * CGFloat(i) }
    // Board colours: cyan, pink, orange, green (`PuzzleCollectionView.colors`).
    private let balls: [(Int, Int, Int, Color)] = [(0, 0, 1, .cyan), (0, 3, 1, .cyan), (1, 0, 2, .pink), (4, 2, 2, .pink),
                                                   (1, 1, 3, .orange), (3, 2, 3, .orange), (0, 4, 4, .green), (4, 4, 4, .green)]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 5, columns: 5, size: 28, gap: 2, origin: .init(x: 6, y: 6)) { _, _ in box(Arena.cell, 28, 28, 5) }
            stroke(Color.cyan.opacity(0.7), 10) { p in p.move(to: .init(x: c(0), y: c(0))); p.addLine(to: .init(x: c(3), y: c(0))) }
            stroke(Color.pink.opacity(0.7), 10) { p in
                p.move(to: .init(x: c(0), y: c(1))); p.addLine(to: .init(x: c(0), y: c(4))); p.addLine(to: .init(x: c(2), y: c(4)))
            }
            stroke(Color.orange.opacity(0.7), 10) { p in
                p.move(to: .init(x: c(1), y: c(1))); p.addLine(to: .init(x: c(1), y: c(3))); p.addLine(to: .init(x: c(2), y: c(3)))
            }
            stroke(Color.green.opacity(0.7), 10) { p in p.move(to: .init(x: c(4), y: c(0))); p.addLine(to: .init(x: c(4), y: c(2))) }
            ForEach(balls.indices, id: \.self) { i in
                let b = balls[i]
                shinyBall(b.3, 21).overlay { label("\(b.2)", 11, .black, weight: .bold) }.at(c(b.1), c(b.0))
            }
        }
    }
}

private struct OneLineArt: View {
    private let roof = CGPoint(x: 80, y: 24), left = CGPoint(x: 36, y: 66), right = CGPoint(x: 124, y: 66)
    private let bottomLeft = CGPoint(x: 36, y: 136), bottomRight = CGPoint(x: 124, y: 136)

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            stroke(Color.gray.opacity(0.45), 4) { p in
                p.move(to: left); p.addLine(to: right)
                p.move(to: right); p.addLine(to: bottomRight); p.addLine(to: bottomLeft)
                p.move(to: left); p.addLine(to: bottomRight)
            }
            // The path traced so far: accent with a soft glow.
            stroke(Color.blue.opacity(0.35), 13) { p in
                p.move(to: bottomLeft); p.addLine(to: left); p.addLine(to: roof); p.addLine(to: right)
            }
            stroke(Color.blue, 6) { p in
                p.move(to: bottomLeft); p.addLine(to: left); p.addLine(to: roof); p.addLine(to: right)
            }
            shinyBall(.blue, 22).at(bottomLeft.x, bottomLeft.y)
            shinyBall(.blue, 22).at(left.x, left.y)
            shinyBall(.blue, 22).at(roof.x, roof.y)
            shinyBall(.orange, 22).at(right.x, right.y)
            shinyBall(.cyan, 22).at(bottomRight.x, bottomRight.y)
        }
    }
}

private struct UnblockArt: View {
    private let cell: CGFloat = 24, origin: CGFloat = 8
    // (row, column, length, horizontal, colour); the red block is the one to free.
    private let pieces: [(Int, Int, Int, Bool, Color)] = [
        (2, 0, 2, true, .red), (0, 3, 2, true, .green), (1, 2, 3, true, .purple), (1, 0, 2, true, .pink),
        (2, 4, 2, false, .yellow), (3, 5, 2, false, .orange), (4, 1, 2, true, .cyan),
    ]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 6, columns: 6, size: cell - 4, gap: 4, origin: .init(x: origin + 2, y: origin + 2)) { _, _ in
                box(Arena.cell, cell - 4, cell - 4, 5)
            }
            box(.green, 4, cell - 10, 2).at(origin + cell * 6 + 2, origin + cell * 2.5)
            ForEach(pieces.indices, id: \.self) { i in
                let piece = pieces[i]
                let w = (piece.3 ? CGFloat(piece.2) : 1) * cell - 5, h = (piece.3 ? 1 : CGFloat(piece.2)) * cell - 5
                gradientTile(piece.4, piece.4.opacity(0.7), w, h, 7)
                    .overlay { RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.15)).padding(4) }
                    .overlay { label(piece.3 ? "↔" : "↕", 10, .black.opacity(0.6), weight: .bold) }
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 2)
                    .at(origin + CGFloat(piece.1) * cell + w / 2 + 2.5, origin + CGFloat(piece.0) * cell + h / 2 + 2.5)
            }
        }
    }
}

private struct FifteenPuzzleArt: View {
    private let values = [3, 1, 2, 4, 0, 6, 8, 7, 5]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 3, columns: 3, size: 44, gap: 4, origin: .init(x: 10, y: 10)) { r, c in
                let i = r * 3 + c, value = values[i]
                if value == 0 {
                    box(Arena.panel.opacity(0.6), 44, 44, 10)
                } else {
                    // Tiles already home turn green, as on the board.
                    let home = value == i + 1
                    gradientTile(home ? Color(red: 0.45, green: 0.8, blue: 0.55) : Color(red: 0.5, green: 0.45, blue: 0.95),
                                 home ? Color(red: 0.2, green: 0.55, blue: 0.35) : Color(red: 0.3, green: 0.25, blue: 0.7), 44, 44, 10)
                        .overlay { label("\(value)", 20, .white, weight: .bold) }
                }
            }
        }
    }
}

private struct FloodFillArt: View {
    private static let palette: [Color] = [.cyan, .pink, .orange, .green, .purple]
    // The orange region spreading from the top-left corner.
    private static let board = ["22222410", "22224103", "22241034", "21410340", "14103401",
                                "41033012", "10330124", "03301241"]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 8, columns: 8, size: 16, gap: 0, origin: .init(x: 16, y: 6)) { r, c in
                let digit = Array(Self.board[r])[c].wholeNumberValue ?? 0
                Rectangle().fill(Self.palette[digit]).frame(width: 16.5, height: 16.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            ForEach(Self.palette.indices, id: \.self) { i in
                Circle().fill(Self.palette[i].gradient).frame(width: 18, height: 18)
                    .overlay { if i == 2 { Image(systemName: "checkmark").font(.system(size: 9, weight: .black)).foregroundStyle(.white) } }
                    .at(32 + CGFloat(i) * 24, 147)
            }
        }
    }
}

private struct LaserArt: View {
    private func cx(_ i: Int) -> CGFloat { 27.5 + 29 * CGFloat(i) }
    private func cy(_ i: Int) -> CGFloat { 22.5 + 29 * CGFloat(i) }
    private let mirrors: [(Int, Int, Bool)] = [(1, 4, true), (1, 1, true), (3, 1, true), (4, 3, false), (2, 3, false)]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 5, columns: 5, size: 27, gap: 2, origin: .init(x: 14, y: 9)) { _, _ in box(Arena.cell.opacity(0.6), 27, 27, 5) }
            // The beam: a red glow under a bright core, as in the game.
            let beam: [CGPoint] = [.init(x: 10, y: cy(4)), .init(x: cx(1), y: cy(4)), .init(x: cx(1), y: cy(1)),
                                   .init(x: cx(3), y: cy(1)), .init(x: cx(3), y: cy(0))]
            stroke(Color.red.opacity(0.3), 8) { p in p.addLines(beam) }
            stroke(Color(red: 1, green: 0.4, blue: 0.4), 3) { p in p.addLines(beam) }
            box(.red, 9, 16, 3).at(8, cy(4))
            ForEach(mirrors.indices, id: \.self) { i in
                let m = mirrors[i], d: CGFloat = 9
                stroke(Color(white: 0.85), 4) { p in
                    p.move(to: .init(x: cx(m.0) - d, y: cy(m.1) + (m.2 ? d : -d)))
                    p.addLine(to: .init(x: cx(m.0) + d, y: cy(m.1) - (m.2 ? d : -d)))
                }
            }
            dot(.yellow.opacity(0.45), 22).at(cx(3), cy(0))
            label("★", 15, .yellow).at(cx(3), cy(0))
        }
    }
}

private struct MatchstickArt: View {
    // Segments a b c d e f g; "6 + 4 = 4" is one match away from 8 − 4 = 4.
    private static let digits: [Character: [Bool]] = [
        "6": [true, false, true, true, true, true, true],
        "4": [false, true, true, false, false, true, true],
    ]
    private static let wood = Color(red: 0.95, green: 0.75, blue: 0.45)

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            label("Move 1", 13, .orange).at(80, 30)
            digit("6").at(24, 86)
            match(horizontal: true, length: 16).at(54, 86)
            match(horizontal: false, length: 16).at(54, 86)
            digit("4").at(84, 86)
            box(.white, 14, 3, 1.5).at(112, 81)
            box(.white, 14, 3, 1.5).at(112, 91)
            digit("4").at(140, 86)
        }
    }

    private func match(horizontal: Bool, length: CGFloat = 20) -> some View {
        ZStack(alignment: horizontal ? .leading : .top) {
            Capsule().fill(Self.wood).frame(width: horizontal ? length : 4, height: horizontal ? 4 : length)
            dot(.red, 5)
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
                match(horizontal: positions[i].2, length: 18)
                    .opacity(s[i] ? 1 : 0.08)
                    .offset(x: positions[i].0, y: positions[i].1)
            }
        }
    }
}

private struct Game2048Art: View {
    private let values = [2, 4, 8, 16, 0, 32, 64, 4, 2, 128, 0, 2, 0, 8, 256, 1024]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            box(Color(red: 0.62, green: 0.56, blue: 0.50).opacity(0.85), 148, 148, 14).at(80, 80)
            Cells(rows: 4, columns: 4, size: 32, gap: 4, origin: .init(x: 10, y: 10)) { r, c in
                let value = values[r * 4 + c]
                if value == 0 {
                    box(.white.opacity(0.22), 32, 32, 7)
                } else {
                    box(Game2048View.color(for: value), 32, 32, 7)
                        .overlay {
                            label("\(value)", value >= 1000 ? 10 : value >= 100 ? 12 : 15,
                                  value <= 4 ? Color(red: 0.47, green: 0.43, blue: 0.40) : .white)
                        }
                }
            }
        }
    }
}

private struct SudokuArt: View {
    // A 6×6 board as the game opens it: givens in ink, entries in blue.
    private let givens: [Int: Int] = [1: 4, 3: 6, 5: 5, 11: 2, 12: 6, 13: 3, 15: 5, 18: 2, 19: 5, 20: 4, 24: 3, 32: 6, 33: 3, 34: 5]
    private let entries: [Int: Int] = [6: 5, 7: 1, 30: 1]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 6, columns: 6, size: 23, gap: 1, origin: .init(x: 9, y: 9)) { r, c in
                let i = r * 6 + c
                let selected = i == 7, unit = r == 1 || c == 1
                Rectangle()
                    .fill(selected ? Color.blue.opacity(0.3) : unit ? Color.blue.opacity(0.12) : Arena.panel)
                    .frame(width: 23, height: 23)
                    .overlay {
                        if let g = givens[i] { label("\(g)", 13, .white, weight: .bold) }
                        else if let e = entries[i] { label("\(e)", 13, .blue, weight: .medium) }
                    }
            }
            stroke(.white.opacity(0.6), 2) { p in
                p.move(to: .init(x: 80.5, y: 9)); p.addLine(to: .init(x: 80.5, y: 152))
                for y in [56.5, 104.5] { p.move(to: .init(x: 9, y: y)); p.addLine(to: .init(x: 152, y: y)) }
            }
            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.6), lineWidth: 2)
                .frame(width: 145, height: 145).at(80.5, 80.5)
        }
    }
}

private struct MinesweeperArt: View {
    private let open: Set<Int> = [8, 9, 10, 11, 15, 16, 17, 18, 19, 22, 23, 24, 25, 26, 29, 30, 31, 32, 37, 38, 39]
    private let numbers: [Int: Int] = [8: 1, 9: 1, 10: 2, 11: 1, 15: 1, 19: 2, 22: 2, 26: 1, 29: 1, 32: 3, 37: 1, 39: 1]
    private let flags: Set<Int> = [3, 33]
    private static let ink: [Color] = [.clear, .blue, .green, .orange, .red]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            box(Arena.panel, 152, 152, 12).at(80, 80)
            Cells(rows: 7, columns: 7, size: 19, gap: 2, origin: .init(x: 9.5, y: 9.5)) { r, c in
                let i = r * 7 + c
                if open.contains(i) {
                    box(.black, 19, 19, 4)
                        .overlay { if let n = numbers[i] { label("\(n)", 12, Self.ink[n], weight: .bold) } }
                } else {
                    gradientTile(Color(white: 0.3), Color(white: 0.22), 19, 19, 4)
                        .overlay { if flags.contains(i) { Text("🚩").font(.system(size: 10)) } }
                }
            }
        }
    }
}

private struct CheckmateArt: View {
    private static let light = Color(red: 0.65, green: 0.69, blue: 0.61)
    private static let dark = Color(red: 0.32, green: 0.39, blue: 0.29)

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 5, columns: 5, size: 28, gap: 0, origin: .init(x: 10, y: 10)) { r, c in
                Rectangle().fill((r + c).isMultiple(of: 2) ? Self.light : Self.dark).frame(width: 28.5, height: 28.5)
                    .overlay { if r == 3 && c == 1 { Rectangle().fill(Color.blue.opacity(0.35)) } }
                    .overlay { if (r == 4 && c == 1) || (r == 3 && c == 1) { Rectangle().strokeBorder(Color.yellow.opacity(0.7), lineWidth: 2) } }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            piece("♚", white: false).at(122, 38)
            piece("♟", white: false).at(94, 38)
            piece("♕", white: true).at(38, 108)
            piece("♖", white: true).at(150 - 28, 136)
            ForEach([(66.0, 80.0), (94.0, 52.0)], id: \.0) { p in
                dot(Color.blue.opacity(0.6), 9).at(p.0, p.1)
            }
        }
    }

    private func piece(_ glyph: String, white: Bool) -> some View {
        Text(verbatim: glyph + "\u{FE0E}").font(.system(size: 32))
            .foregroundStyle(white ? Color.white : Color.black)
            .shadow(color: white ? .black.opacity(0.9) : .white.opacity(0.45), radius: 1)
    }
}

private struct GemsArt: View {
    var blitz = false
    private static let colors: [GemColor] = [.blue, .red, .green, .purple, .orange,
                                             .orange, .purple, .yellow, .blue, .green,
                                             .red, .yellow, .red, .yellow, .yellow,
                                             .green, .blue, .orange, .purple, .red,
                                             .purple, .green, .blue, .orange, .blue]
    static let tileLight = Color(red: 0.22, green: 0.17, blue: 0.42)
    static let tileDark = Color(red: 0.17, green: 0.13, blue: 0.34)

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 5, columns: 5, size: 28, gap: 2, origin: .init(x: 6, y: 6)) { r, c in
                let i = r * 5 + c
                box((r + c).isMultiple(of: 2) ? Self.tileLight : Self.tileDark, 28, 28, 6)
                    .overlay {
                        Match3GemView(gem: Gem(id: i, color: Self.colors[i],
                                               ice: blitz && i == 18 ? 2 : 0,
                                               crystal: blitz && [1, 7, 13, 21].contains(i)),
                                      size: 28)
                    }
            }
        }
    }
}

/// A diamond-shaped board, for the levels that change shape.
private struct GemsArcadeArt: View {
    private static let colors: [GemColor] = [.blue, .red, .green, .purple, .orange, .yellow]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Cells(rows: 5, columns: 5, size: 28, gap: 2, origin: .init(x: 6, y: 6)) { r, c in
                if abs(r - 2) + abs(c - 2) <= 2 {
                    box((r + c).isMultiple(of: 2) ? GemsArt.tileLight : GemsArt.tileDark, 28, 28, 6)
                        .overlay {
                            Match3GemView(gem: Gem(id: r * 5 + c, color: Self.colors[(r * 2 + c) % 6],
                                                   crystal: (r == 1 && c == 2) || (r == 3 && c == 1)),
                                          size: 28)
                        }
                }
            }
        }
    }
}

// MARK: - Arcade boards

private struct SnakeArt: View {
    private let cell: CGFloat = 15
    // Head first, as the game stores it.
    private let segments: [(Int, Int)] = [(3, 7), (3, 6), (3, 5), (4, 5), (5, 5), (5, 4), (5, 3), (5, 2), (6, 2)]

    private func center(_ p: (Int, Int)) -> CGPoint { CGPoint(x: 5 + (CGFloat(p.1) + 0.5) * cell, y: 5 + (CGFloat(p.0) + 0.5) * cell) }

    var body: some View {
        ArtCanvas(colors: [Color(red: 0.3, green: 0.5, blue: 0.2), Color(red: 0.3, green: 0.5, blue: 0.2)]) {
            Cells(rows: 10, columns: 10, size: cell, gap: 0, origin: .init(x: 5, y: 5)) { r, c in
                Rectangle()
                    .fill((r + c).isMultiple(of: 2) ? Color(red: 0.55, green: 0.8, blue: 0.35) : Color(red: 0.5, green: 0.74, blue: 0.31))
                    .frame(width: cell + 0.5, height: cell + 0.5)
            }
            // Blue body fading toward the tail, as `SnakeView` strokes it.
            ForEach(Array(segments.indices.reversed()), id: \.self) { i in
                let t = Double(i) / Double(segments.count - 1)
                let color = Color(hue: 0.58 - t * 0.08, saturation: 0.75, brightness: 0.95 - t * 0.3)
                let width = cell * (0.86 - CGFloat(t) * 0.22)
                ZStack {
                    if i + 1 < segments.count {
                        Path { p in p.move(to: center(segments[i])); p.addLine(to: center(segments[i + 1])) }
                            .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                    dot(color, width).at(center(segments[i]).x, center(segments[i]).y)
                }
            }
            dot(.white, 5).at(center(segments[0]).x + 2, center(segments[0]).y - 3)
            dot(.white, 5).at(center(segments[0]).x + 2, center(segments[0]).y + 3)
            dot(.black, 2.5).at(center(segments[0]).x + 3, center(segments[0]).y - 3)
            dot(.black, 2.5).at(center(segments[0]).x + 3, center(segments[0]).y + 3)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.8, green: 0.08, blue: 0.1)],
                                             startPoint: .top, endPoint: .bottom)).frame(width: 13, height: 13)
                Ellipse().fill(Color(red: 0.2, green: 0.6, blue: 0.2)).frame(width: 4, height: 3).offset(x: 1, y: -7)
            }
            .at(5 + 7.5 * cell, 5 + 6.5 * cell)
        }
    }
}

private struct BlockBlastArt: View {
    private let board = ["..GG....", "..G..II.", "PPP..II.", "......Y.", ".KK...Y.", ".KK..YY.", "........", "....GG.."]
    private static let colors: [Character: Color] = ["I": Color(.systemIndigo), "G": Color(.systemGreen), "P": Color(.systemPurple),
                                                     "K": Color(.systemPink), "Y": Color(.systemYellow)]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            box(Arena.panel, 124, 124, 6).at(80, 66)
            Cells(rows: 8, columns: 8, size: 13, gap: 2, origin: .init(x: 21, y: 7)) { r, c in
                box(Self.colors[Array(board[r])[c]] ?? Color(white: 0.17), 13, 13, 2.5)
            }
            // The tray of three pieces under the board.
            ForEach(0..<3, id: \.self) { i in
                box(Arena.panel, 38, 24, 6).at(36 + CGFloat(i) * 44, 145)
            }
            Cells(rows: 2, columns: 3, size: 6, gap: 1, origin: .init(x: 26, y: 138)) { r, c in
                box(r == 0 || c == 2 ? Color(.systemYellow) : .clear, 6, 6, 1.5)
            }
            Cells(rows: 2, columns: 2, size: 6, gap: 1, origin: .init(x: 73.5, y: 138)) { _, _ in box(Color(.systemPink), 6, 6, 1.5) }
            Cells(rows: 1, columns: 4, size: 6, gap: 1, origin: .init(x: 110, y: 142)) { _, _ in box(Color(.systemIndigo), 6, 6, 1.5) }
        }
    }
}

private struct WaterSortArt: View {
    // `WaterSortView.palette`: liquid bottom to top, in units of a quarter tube.
    private let tubes: [[(Color, CGFloat)]] = [[(.red, 1), (.green, 1), (.red, 2)], [(.green, 1), (.blue, 3)],
                                               [(.blue, 1), (.red, 1), (.green, 2)], [(.yellow, 2)]]
    private static let height: CGFloat = 112, width: CGFloat = 28, headroom: CGFloat = 14

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            ForEach(tubes.indices, id: \.self) { i in
                tube(tubes[i]).at(26 + CGFloat(i) * 36, i == 1 ? 74 : 86)
            }
        }
    }

    /// Glass with a rounded bottom and stacked liquid, as the game draws it.
    private func tube(_ layers: [(Color, CGFloat)]) -> some View {
        let glass = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: Self.width / 2,
                                           bottomTrailingRadius: Self.width / 2, topTrailingRadius: 4)
        let unit = (Self.height - Self.headroom - 3) / 4
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(layers.indices.reversed()), id: \.self) { i in
                Rectangle()
                    .fill(LinearGradient(colors: [layers[i].0.opacity(0.85), layers[i].0], startPoint: .leading, endPoint: .trailing))
                    .overlay(alignment: .top) { if i == layers.count - 1 { Rectangle().fill(.white.opacity(0.35)).frame(height: 1.5) } }
                    .frame(height: unit * layers[i].1)
            }
        }
        .frame(width: Self.width - 5, height: Self.height - 3)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: (Self.width - 5) / 2,
                                          bottomTrailingRadius: (Self.width - 5) / 2, topTrailingRadius: 3))
        .frame(width: Self.width, height: Self.height)
        .background(Color(white: 0.11).opacity(0.6), in: glass)
        .overlay { glass.strokeBorder(Color.white.opacity(0.28), lineWidth: 1.2) }
        .overlay(alignment: .leading) {
            Capsule().fill(.white.opacity(0.18)).frame(width: 2, height: Self.height * 0.6).padding(.leading, 4)
        }
    }
}

private struct SimonArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            // Green, red, yellow, blue clockwise from the top left; red is lit.
            quadrant(.green, start: 180, lit: false)
            quadrant(.red, start: 270, lit: true)
            quadrant(.yellow, start: 0, lit: false)
            quadrant(.blue, start: 90, lit: false)
            dot(.black, 54).at(80, 80)
            label("3", 24, .white).at(80, 76)
            label("steps", 8, .gray, weight: .semibold).at(80, 94)
        }
    }

    private func quadrant(_ color: Color, start: Double, lit: Bool) -> some View {
        Path { p in
            p.addArc(center: .init(x: 80, y: 80), radius: 70, startAngle: .degrees(start + 2), endAngle: .degrees(start + 88), clockwise: false)
            p.addArc(center: .init(x: 80, y: 80), radius: 30, startAngle: .degrees(start + 88), endAngle: .degrees(start + 2), clockwise: true)
            p.closeSubpath()
        }
        .fill(color.opacity(lit ? 1 : 0.38).gradient)
        .shadow(color: lit ? color : .clear, radius: lit ? 12 : 0)
    }
}

private struct RedGreenArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            box(Color(white: 0.12), 40, 92, 12).at(80, 52)
            dot(.red.opacity(0.15), 22).at(80, 23)
            dot(.yellow.opacity(0.15), 22).at(80, 51)
            dot(.green.opacity(0.3), 34).at(80, 79)
            dot(.green, 22).at(80, 79)
            // The track with its finish line and the runner.
            box(Color(red: 0.45, green: 0.25, blue: 0.2), 38, 52, 5).at(80, 128)
            ForEach(0..<4, id: \.self) { k in
                box(.white.opacity(0.25), 2, 6, 1).at(80, 112 + CGFloat(k) * 11)
            }
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { k in Rectangle().fill(k.isMultiple(of: 2) ? Color.white : .black).frame(width: 6, height: 4) }
            }
            .at(80, 104)
            shinyBall(.blue, 14).at(80, 140)
        }
    }
}

private struct PerfectTimingArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            label("12", 46, .white.opacity(0.12)).at(80, 122)
            box(Color(white: 0.16), 140, 40, 10).at(80, 72)
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color.blue.opacity(0.3), .blue.opacity(0.8), .blue.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 44, height: 40).at(104, 72)
            box(.yellow.opacity(0.7), 14, 40, 4).at(104, 72)
            box(.white.opacity(0.3), 6, 56, 3).at(98, 72)
            box(.white, 3.5, 52, 2).at(98, 72)
        }
    }
}

private struct WhackMoleArt: View {
    private static let rim = Color(red: 0.52, green: 0.34, blue: 0.18)
    private static let rimLight = Color(red: 0.66, green: 0.45, blue: 0.25)

    var body: some View {
        ArtCanvas(colors: [Color(red: 0.36, green: 0.62, blue: 0.28), Color(red: 0.22, green: 0.46, blue: 0.19)]) {
            ForEach(0..<9, id: \.self) { i in
                let x = 28 + CGFloat(i % 3) * 52, y = 40 + CGFloat(i / 3) * 48
                hole(mole: i == 4 ? .some(false) : i == 6 ? .some(true) : nil).at(x, y)
            }
        }
    }

    /// A dirt mound with the mole climbing out, as `ActionCollectionView` draws it.
    private func hole(mole: Bool?) -> some View {
        ZStack {
            Ellipse().fill(LinearGradient(colors: [Self.rimLight, Self.rim], startPoint: .top, endPoint: .bottom)).frame(width: 46, height: 18)
            Ellipse().fill(Color(red: 0.1, green: 0.06, blue: 0.03)).frame(width: 34, height: 11)
            if let golden = mole {
                face(golden: golden)
                    .offset(y: -12)
                    .mask(Rectangle().frame(width: 46, height: 40).offset(y: -20))
            }
            // The front of the mound over the mole.
            Ellipse().fill(LinearGradient(colors: [Self.rimLight, Self.rim], startPoint: .top, endPoint: .bottom))
                .frame(width: 46, height: 18)
                .mask(Rectangle().frame(width: 46, height: 9).offset(y: 4.5))
                .overlay { Ellipse().fill(Color(red: 0.1, green: 0.06, blue: 0.03)).frame(width: 34, height: 11).mask(Rectangle().frame(width: 34, height: 5.5).offset(y: 2.75)) }
        }
        .frame(width: 46, height: 60)
    }

    private func face(golden: Bool) -> some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
                .fill(LinearGradient(colors: golden ? [Color(red: 1, green: 0.85, blue: 0.3), .orange]
                                                    : [Color(red: 0.62, green: 0.44, blue: 0.3), Color(red: 0.4, green: 0.26, blue: 0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 28)
            Ellipse().fill(golden ? Color(red: 1, green: 0.95, blue: 0.7) : Color(red: 0.86, green: 0.7, blue: 0.54)).frame(width: 13, height: 9).offset(y: 3)
            ForEach([-4.5, 4.5], id: \.self) { dx in
                dot(.white, 5).overlay { dot(.black, 2.6) }.offset(x: dx, y: -4)
            }
            Ellipse().fill(Color(red: 0.95, green: 0.45, blue: 0.55)).frame(width: 6, height: 4).offset(y: 1.5)
        }
    }
}

private struct CirclePongArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(red: 0.06, green: 0.04, blue: 0.16), Color(red: 0.02, green: 0.02, blue: 0.07)]) {
            Circle().stroke(.white.opacity(0.05), lineWidth: 1).frame(width: 90, height: 90).at(80, 80)
            Circle().stroke(.pink.opacity(0.35), lineWidth: 2).frame(width: 132, height: 132).at(80, 80)
            ForEach(0..<2, id: \.self) { glow in
                Path { p in p.addArc(center: .init(x: 80, y: 80), radius: 66, startAngle: .degrees(60), endAngle: .degrees(120), clockwise: false) }
                    .stroke(Color.blue.opacity(glow == 0 ? 0.3 : 1), style: StrokeStyle(lineWidth: glow == 0 ? 12 : 7, lineCap: .round))
            }
            label("★", 14, .yellow).at(52, 54)
            ForEach(0..<3, id: \.self) { k in
                dot(.white.opacity(0.15 + 0.15 * Double(k)), 4 + CGFloat(k)).at(70 + CGFloat(k) * 6, 70 + CGFloat(k) * 9)
            }
            shinyBall(Color(white: 0.7), 11).at(90, 98)
        }
    }
}

private struct MiniGolfArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(red: 0.10, green: 0.33, blue: 0.16), Color(red: 0.05, green: 0.20, blue: 0.09)]) {
            RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.45, green: 0.30, blue: 0.18), lineWidth: 5)
                .frame(width: 146, height: 146).at(80, 80)
            // A wooden bumper between the ball and the hole.
            stroke(Color(red: 0.85, green: 0.55, blue: 0.25), 8) { p in p.move(to: .init(x: 54, y: 86)); p.addLine(to: .init(x: 108, y: 70)) }
            stroke(Color(red: 1, green: 0.75, blue: 0.4), 3) { p in p.move(to: .init(x: 54, y: 86)); p.addLine(to: .init(x: 108, y: 70)) }
            dot(.black, 14).at(112, 36)
            box(.white, 2, 26, 1).at(112, 22)
            Path { p in p.move(to: .init(x: 113, y: 9)); p.addLine(to: .init(x: 130, y: 15)); p.addLine(to: .init(x: 113, y: 21)) }.fill(.pink)
            stroke(.white.opacity(0.5), 2, dash: [4, 4]) { p in p.move(to: .init(x: 44, y: 128)); p.addQuadCurve(to: .init(x: 70, y: 102), control: .init(x: 48, y: 110)) }
            shinyBall(Color(white: 0.7), 13).at(42, 130)
        }
    }
}

private struct MergeFruitArt: View {
    private static func color(_ stage: Int) -> Color { Color(hue: Double(stage) / 12, saturation: 0.55, brightness: 0.9) }
    // (stage, x, y, radius) with `MergeFruitNode` emoji.
    private let fruit: [(Int, CGFloat, CGFloat, CGFloat)] = [(5, 52, 124, 26), (3, 106, 132, 18), (2, 128, 108, 14),
                                                            (4, 96, 98, 20), (1, 40, 90, 11), (0, 64, 92, 9)]

    var body: some View {
        ArtCanvas(colors: [Color(red: 0.98, green: 0.93, blue: 0.84), Color(red: 0.98, green: 0.93, blue: 0.84)]) {
            box(Color(red: 0.95, green: 0.84, blue: 0.66), 136, 110, 4).at(80, 99)
            ForEach(0..<3, id: \.self) { k in box(Color(red: 0.8, green: 0.64, blue: 0.45).opacity(0.6), 136, 1, 0).at(80, 70 + CGFloat(k) * 28) }
            stroke(Color(red: 0.6, green: 0.42, blue: 0.25), 5) { p in
                p.move(to: .init(x: 12, y: 30)); p.addLine(to: .init(x: 12, y: 154)); p.addLine(to: .init(x: 148, y: 154)); p.addLine(to: .init(x: 148, y: 30))
            }
            box(.red.opacity(0.5), 136, 2, 1).at(80, 44)
            stroke(.black.opacity(0.18), 1.5, dash: [5, 5]) { p in p.move(to: .init(x: 86, y: 36)); p.addLine(to: .init(x: 86, y: 76)) }
            fruitView(stage: 2, radius: 13).at(86, 22)
            ForEach(fruit.indices, id: \.self) { i in
                let f = fruit[i]
                fruitView(stage: f.0, radius: f.3).at(f.1, f.2)
            }
        }
    }

    private func fruitView(stage: Int, radius: CGFloat) -> some View {
        ZStack {
            Circle().fill(Self.color(stage)).overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
            Ellipse().fill(.white.opacity(0.3)).frame(width: radius * 0.7, height: radius * 0.45).offset(x: -radius * 0.3, y: -radius * 0.45)
            Text(MergeFruitNode.symbols[stage]).font(.system(size: radius * 1.3))
        }
        .frame(width: radius * 2, height: radius * 2)
    }
}

private struct StackArt: View {
    private static let hue = 0.55
    // (x, z, w, d) per level, bottom up; each placed block a little off the one below.
    private let slabs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (-40, -40, 80, 80), (-40, -40, 80, 80), (-40, -40, 80, 80), (-34, -40, 74, 80), (-34, -34, 74, 74), (-30, -34, 70, 74),
    ]

    var body: some View {
        ArtCanvas(colors: [Color(hue: Self.hue, saturation: 0.45, brightness: 0.32), Color(hue: Self.hue + 0.08, saturation: 0.5, brightness: 0.12)]) {
            label("6", 64, .white.opacity(0.07), weight: .black).at(80, 30)
            ForEach(slabs.indices, id: \.self) { i in
                let s = slabs[i]
                slab(x: s.0, z: s.1, w: s.2, d: s.3, level: i, hue: 0.52 + Double(max(0, i - 2)) * 0.031)
            }
            // The next block sliding in along x.
            slab(x: 4, z: -34, w: 70, d: 74, level: slabs.count, hue: 0.52 + 4 * 0.031)
        }
    }

    /// An isometric block, shaded like `ArcadeView.stackSlab`.
    private func slab(x: CGFloat, z: CGFloat, w: CGFloat, d: CGFloat, level: Int, hue: Double) -> some View {
        let h: CGFloat = 11
        func p(_ px: CGFloat, _ py: CGFloat, _ pz: CGFloat) -> CGPoint {
            CGPoint(x: 72 + (px - pz) * 0.866 * 0.62, y: 96 + ((px + pz) * 0.5 - py) * 0.62)
        }
        let top = CGFloat(level + 1) * h - 3 * h, bottom = top - h
        let x1 = x + w, z1 = z + d
        return ZStack {
            Path { $0.addLines([p(x, top, z1), p(x1, top, z1), p(x1, bottom, z1), p(x, bottom, z1)]); $0.closeSubpath() }
                .fill(Color(hue: hue, saturation: 0.62, brightness: 0.78))
            Path { $0.addLines([p(x1, top, z), p(x1, top, z1), p(x1, bottom, z1), p(x1, bottom, z)]); $0.closeSubpath() }
                .fill(Color(hue: hue, saturation: 0.7, brightness: 0.58))
            Path { $0.addLines([p(x, top, z), p(x1, top, z), p(x1, top, z1), p(x, top, z1)]); $0.closeSubpath() }
                .fill(Color(hue: hue, saturation: 0.5, brightness: 0.97))
            Path { $0.addLines([p(x, top, z1), p(x1, top, z1), p(x1, top, z)]) }
                .stroke(.white.opacity(0.35), lineWidth: 0.8)
        }
        .frame(width: 160, height: 160)
        .at(80, 80)
    }
}

private struct KnifeSpinArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            ForEach([20.0, 140.0, 250.0], id: \.self) { angle in
                knife(handle: .blue).rotationEffect(.degrees(angle)).offset(y: 0).at(80, 66)
            }
            dot(.black.opacity(0.35), 98).at(80, 69)
            dot(Color(red: 0.62, green: 0.38, blue: 0.2), 96).at(80, 66)
            dot(Color(red: 0.78, green: 0.52, blue: 0.3), 69).at(80, 66)
            dot(Color(red: 0.55, green: 0.33, blue: 0.17), 40).at(80, 66)
            dot(Color(red: 0.4, green: 0.22, blue: 0.1), 10).at(80, 66)
            ZStack {
                dot(.red, 15)
                dot(.white.opacity(0.5), 5).offset(x: -3, y: -3)
                Ellipse().fill(.green).frame(width: 4, height: 6).offset(x: 2, y: -9)
            }
            .at(128, 30)
            knife(handle: .white.opacity(0.9), flying: true).at(80, 138)
        }
    }

    /// Blade up, handle down: stuck ones sit below the centre with the blade
    /// buried in the wood, then turn into place.
    private func knife(handle: Color, flying: Bool = false) -> some View {
        VStack(spacing: 0) {
            UnevenRoundedRectangle(topLeadingRadius: 3.5, topTrailingRadius: 3.5)
                .fill(LinearGradient(colors: [.white, Color(white: 0.65)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 6, height: 20)
            box(Color(white: 0.4), 10, 3, 1.5)
            box(handle, 6, 15, 2)
        }
        .offset(y: flying ? 0 : 58)
    }
}

private struct HelixDropArt: View {
    // (y, hue, gap start, gap width, red start, red width) across the 160 canvas.
    private let floors: [(CGFloat, Double, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (34, 0.55, 98, 34, 0, 0), (72, 0.75, 20, 34, 116, 26), (110, 0.95, 116, 34, 30, 22), (148, 0.15, 40, 34, 0, 0),
    ]

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            Rectangle().fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.5), Color(white: 0.25)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 14, height: 170).at(80, 80)
            ForEach(floors.indices, id: \.self) { i in
                let f = floors[i]
                floor(y: f.0, hue: f.1, gap: f.2..<(f.2 + f.3), red: f.4..<(f.4 + f.5))
            }
            dot(.black.opacity(0.3), 13).at(116, 92)
            Circle().fill(RadialGradient(colors: [.white, .blue], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 9))
                .frame(width: 13, height: 13).at(116, 90)
        }
    }

    private func floor(y: CGFloat, hue: Double, gap: Range<CGFloat>, red: Range<CGFloat>) -> some View {
        ZStack {
            ForEach(Array(stride(from: CGFloat(0), to: 160, by: 4)), id: \.self) { x in
                if !gap.contains(x) {
                    let isRed = red.contains(x)
                    VStack(spacing: 0) {
                        Rectangle().fill(isRed ? Color.red : Color(hue: hue, saturation: 0.6, brightness: 0.95)).frame(width: 4.5, height: 7)
                        Rectangle().fill(isRed ? Color(red: 0.5, green: 0, blue: 0.05) : Color(hue: hue, saturation: 0.7, brightness: 0.55)).frame(width: 4.5, height: 5)
                    }
                    .at(x + 2, y)
                }
            }
        }
    }
}

private struct FlappyFlightArt: View {
    private static let pipe = LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.35), Color(red: 0.55, green: 0.95, blue: 0.55), Color(red: 0.15, green: 0.55, blue: 0.3)],
                                             startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ArtCanvas(colors: [Color(red: 0.16, green: 0.25, blue: 0.5), Color(red: 0.35, green: 0.55, blue: 0.75)]) {
            ForEach([(30.0, 30.0), (104.0, 52.0)], id: \.0) { c in
                Capsule().fill(.white.opacity(0.18)).frame(width: 34, height: 10).at(c.0, c.1)
            }
            Ellipse().fill(Color(red: 0.2, green: 0.45, blue: 0.35).opacity(0.7)).frame(width: 90, height: 60).at(20, 150)
            Ellipse().fill(Color(red: 0.2, green: 0.45, blue: 0.35).opacity(0.7)).frame(width: 90, height: 60).at(110, 152)
            // A pipe pair with its gap.
            Rectangle().fill(Self.pipe).frame(width: 26, height: 50).at(118, 25)
            RoundedRectangle(cornerRadius: 2).fill(Self.pipe).frame(width: 32, height: 9).at(118, 54)
            Rectangle().fill(Self.pipe).frame(width: 26, height: 44).at(118, 131)
            RoundedRectangle(cornerRadius: 2).fill(Self.pipe).frame(width: 32, height: 9).at(118, 105)
            ZStack {
                dot(.yellow, 11)
                Circle().stroke(.orange, lineWidth: 1.2).frame(width: 7, height: 7)
            }
            .at(118, 80)
            box(Color(red: 0.55, green: 0.4, blue: 0.25), 160, 9, 0).at(80, 155.5)
            ForEach(0..<6, id: \.self) { k in box(.green.opacity(0.8), 8, 2, 0).at(8 + CGFloat(k) * 28, 152) }
            bird.rotationEffect(.degrees(-12)).at(56, 82)
        }
    }

    private var bird: some View {
        ZStack {
            Ellipse().fill(RadialGradient(colors: [.yellow, .orange], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 1, endRadius: 18))
                .frame(width: 30, height: 23)
            Ellipse().fill(.white.opacity(0.9)).frame(width: 14, height: 9).offset(x: -6, y: 3)
            dot(.white, 9).offset(x: 6, y: -4)
            dot(.black, 4).offset(x: 8, y: -4)
            Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 9, y: 3.5)); p.addLine(to: .init(x: 0, y: 7)) }
                .fill(.orange).frame(width: 9, height: 7).offset(x: 18, y: 1)
        }
    }
}

private struct RoadHopArt: View {
    var body: some View {
        ArtCanvas(colors: [Color(red: 0.2, green: 0.5, blue: 0.28), Color(red: 0.2, green: 0.46, blue: 0.28)]) {
            ForEach([0, 1, 3], id: \.self) { lane in
                box(Color(white: 0.2), 160, 30, 0).at(80, 26 + CGFloat(lane) * 32)
            }
            ForEach(0..<5, id: \.self) { k in box(.white.opacity(0.45), 12, 1.5, 0).at(10 + CGFloat(k) * 34, 42) }
            car(.cyan, facingRight: true).at(46, 26)
            car(.yellow, facingRight: false).at(124, 58)
            car(.pink, facingRight: true).at(98, 122)
            dot(.yellow, 12).overlay { dot(.orange, 6) }.at(30, 90)
            hopper.at(80, 94)
            box(Color(red: 0.2, green: 0.5, blue: 0.28), 160, 18, 0).at(80, 152)
        }
    }

    private func car(_ color: Color, facingRight: Bool) -> some View {
        ZStack {
            ForEach([-11.0, 11.0], id: \.self) { x in
                box(.black, 8, 22, 2).offset(x: x)
            }
            box(color, 38, 18, 6)
            box(.black.opacity(0.35), 18, 10, 4)
            ForEach([-5.0, 5.0], id: \.self) { y in
                Ellipse().fill(.yellow).frame(width: 2.5, height: 4).offset(x: facingRight ? 18 : -18, y: y)
            }
        }
    }

    private var hopper: some View {
        ZStack {
            box(.white, 20, 20, 6)
            box(.red, 7, 5, 2).offset(y: -12)
            dot(.black, 3.5).offset(x: -4, y: -3)
            dot(.black, 3.5).offset(x: 4, y: -3)
            box(.orange, 6, 4, 0).offset(y: 3)
        }
    }
}

// MARK: - Card tables

/// An empty pile: the dashed outline the card games draw.
private func emptyPile(_ width: CGFloat, _ mark: String = "") -> some View {
    RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, dash: [3]))
        .frame(width: width, height: width * 1.4)
        .overlay { label(mark, width * 0.4, .white.opacity(0.22), weight: .semibold) }
}

private struct SolitaireArt: View {
    private let width: CGFloat = 20

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            ForEach(0..<4, id: \.self) { i in emptyPile(width, "A").at(14 + CGFloat(i) * 22, 22) }
            PlayingCard(rank: "A", suit: "hearts", width: width).at(14, 22)
            CardBackArt(width: width).at(146, 22)
            // Seven columns: blue backs under one face-up card each.
            ForEach(0..<7, id: \.self) { col in
                ForEach(0..<col, id: \.self) { k in
                    CardBackArt(width: width).at(14 + CGFloat(col) * 22, 62 + CGFloat(k) * 6)
                }
                PlayingCard(rank: ["J", "9", "9", "Q", "5", "2", "K"][col],
                            suit: ["hearts", "spades", "diamonds", "clubs", "hearts", "diamonds", "diamonds"][col], width: width)
                    .at(14 + CGFloat(col) * 22, 62 + CGFloat(col) * 6)
            }
            PlayingCard(rank: "10", suit: "spades", width: width).at(14, 76)
        }
    }
}

private struct SpiderArt: View {
    private let width: CGFloat = 25

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            ForEach(0..<5, id: \.self) { col in
                let depth = [4, 3, 4, 3, 2][col]
                ForEach(0..<depth, id: \.self) { k in
                    CardBackArt(width: width).at(19 + CGFloat(col) * 30.5, 26 + CGFloat(k) * 7)
                }
                // A spade run building down each column.
                ForEach(0..<(col == 2 ? 4 : 2), id: \.self) { k in
                    PlayingCard(rank: [["Q", "J"], ["9", "8"], ["K", "Q", "J", "10"], ["7", "6"], ["5", "4"]][col][k], suit: "spades", width: width)
                        .at(19 + CGFloat(col) * 30.5, 26 + CGFloat(depth) * 7 + CGFloat(k) * 14)
                }
            }
        }
    }
}

private struct FreeCellArt: View {
    private let width: CGFloat = 17

    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            ForEach(0..<8, id: \.self) { i in emptyPile(width, i < 4 ? "" : "A").at(12 + CGFloat(i) * 19.4, 22) }
            PlayingCard(rank: "7", suit: "diamonds", width: width).at(31.4, 22)
            // Eight columns, every card face up.
            ForEach(0..<8, id: \.self) { col in
                ForEach(0..<6, id: \.self) { row in
                    let ranks = ["2", "10", "5", "3", "7", "10", "8", "6", "5", "8", "4", "2", "K", "2", "7", "A", "J", "A", "Q", "9", "6", "K", "Q", "9"]
                    let suits = ["diamonds", "spades", "hearts", "clubs"]
                    PlayingCard(rank: ranks[(col * 3 + row) % ranks.count], suit: suits[(col + row) % 4], width: width)
                        .at(12 + CGFloat(col) * 19.4, 58 + CGFloat(row) * 13)
                }
            }
        }
    }
}

private struct DurakArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            // The bot's hand, the attack beaten on the table, the deck with its trump.
            ForEach(0..<5, id: \.self) { i in CardBackArt(width: 18).at(56 + CGFloat(i) * 12, 22) }
            CardBackArt(width: 24).at(22, 74)
            PlayingCard(rank: "K", suit: "diamonds", width: 24).rotationEffect(.degrees(90)).at(36, 74)
            PlayingCard(rank: "8", suit: "clubs", width: 26).at(86, 70)
            PlayingCard(rank: "10", suit: "clubs", width: 26).rotationEffect(.degrees(12)).at(100, 78)
            ForEach(0..<6, id: \.self) { i in
                PlayingCard(rank: ["Q", "10", "J", "J", "Q", "6"][i], suit: ["spades", "hearts", "hearts", "clubs", "clubs", "diamonds"][i], width: 26)
                    .at(22 + CGFloat(i) * 23, 140)
            }
        }
    }
}

private struct BattleshipArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            let cell: CGFloat = 20
            let origin = CGPoint(x: 10, y: 10)
            box(Color.blue.opacity(0.12), cell * 7, cell * 7, 8).at(80, 80)
            Path { path in
                for i in 0...7 {
                    let offset = CGFloat(i) * cell
                    path.move(to: CGPoint(x: origin.x + offset, y: origin.y)); path.addLine(to: CGPoint(x: origin.x + offset, y: origin.y + cell * 7))
                    path.move(to: CGPoint(x: origin.x, y: origin.y + offset)); path.addLine(to: CGPoint(x: origin.x + cell * 7, y: origin.y + offset))
                }
            }
            .stroke(Color.blue.opacity(0.35), lineWidth: 0.8)
            // Ships in grey; the one being hit turns red.
            ship(length: 4, horizontal: true, sunk: false).at(origin.x + cell * 3, origin.y + cell * 1.5)
            ship(length: 3, horizontal: false, sunk: false).at(origin.x + cell * 1.5, origin.y + cell * 4.5)
            ship(length: 2, horizontal: true, sunk: true).at(origin.x + cell * 5, origin.y + cell * 5.5)
            ForEach(Array([(2.5, 1.5), (3.5, 1.5)].enumerated()), id: \.offset) { _, hit in
                Image(systemName: "xmark").font(.system(size: 11, weight: .black)).foregroundStyle(.red).at(origin.x + cell * hit.0, origin.y + cell * hit.1)
            }
            ForEach(Array([(5.5, 3.5), (4.5, 6.5), (6.5, 0.5), (0.5, 0.5), (3.5, 3.5)].enumerated()), id: \.offset) { _, miss in
                dot(Color.gray, 5).at(origin.x + cell * miss.0, origin.y + cell * miss.1)
            }
        }
    }

    private func ship(length: Int, horizontal: Bool, sunk: Bool) -> some View {
        let long = CGFloat(length) * 20 - 5
        return Capsule()
            .fill(sunk ? Color.red.opacity(0.25) : Color.white.opacity(0.55))
            .overlay(Capsule().strokeBorder(sunk ? Color.red : Color.white.opacity(0.7), lineWidth: 1.2))
            .frame(width: horizontal ? long : 15, height: horizontal ? 15 : long)
    }
}

private struct HangmanArt: View {
    var body: some View {
        ArtCanvas(colors: Arena.colors) {
            GallowsView(mistakes: 4)
                .environment(\.colorScheme, .dark)
                .frame(width: 90, height: 90)
                .at(80, 52)
            HStack(spacing: 4) {
                ForEach(Array(["W", "O", "", "D", ""].enumerated()), id: \.offset) { _, letter in
                    Text(letter)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 22)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .at(80, 112)
            HStack(spacing: 3) {
                ForEach(["A", "B", "C", "D", "E", "F"], id: \.self) { key in
                    Text(key).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(key == "D" ? 0.3 : 0.9))
                        .frame(width: 19, height: 17)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .at(80, 142)
        }
    }
}

private struct MazePaintArt: View {
    // `#` corridor, `p` painted, `o` the ball, as in `MazePaintView`.
    private static let maze = [
        "#######..",
        "#.#.#.###",
        "#.###.#.#",
        "#.#...#.#",
        "pppppo#.#",
        "p.#.#.###",
        "p.#.#.#..",
        "ppp.###..",
    ]
    private static let paint = Color(red: 0.78, green: 0.2, blue: 0.3)
    private static let corridor = Color(red: 0.45, green: 0.53, blue: 0.72)

    var body: some View {
        ArtCanvas(colors: [Color(red: 0.12, green: 0.13, blue: 0.18), Color(red: 0.12, green: 0.13, blue: 0.18)]) {
            Cells(rows: 8, columns: 9, size: 16, gap: 0, origin: .init(x: 8, y: 16)) { r, c in
                let mark = Array(Self.maze[r])[c]
                Rectangle()
                    .fill(mark == "." ? Color.clear : mark == "#" ? Self.corridor : Self.paint)
                    .frame(width: 16.4, height: 16.4)
                    .overlay {
                        if mark == "o" {
                            Circle().fill(.white.opacity(0.18)).frame(width: 16, height: 16)
                            Circle().fill(.white).frame(width: 10, height: 10)
                        }
                    }
            }
        }
    }
}
