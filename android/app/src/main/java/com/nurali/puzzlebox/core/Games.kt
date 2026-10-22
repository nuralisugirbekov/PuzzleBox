package com.nurali.puzzlebox.core

import androidx.compose.ui.graphics.Color

enum class GameCategory(val key: String) {
    Logic("Logic"), Arcade("Arcade"), Cards("Cards"), Attention("Attention"), Visual("Visual puzzles"),
    Numbers("Numbers"), Japanese("Japanese puzzles"), Physics("Physics"), Reaction("Reaction");

    val title: String get() = L10n.t(key)
}

enum class Difficulty(val key: String) { Easy("Easy"), Medium("Medium"), Hard("Hard") }

/** iOS system tint colours, so tiles look the same on both platforms. */
object Tint {
    val green = Color(0xFF34C759)
    val orange = Color(0xFFFF9500)
    val red = Color(0xFFFF3B30)
    val mint = Color(0xFF00C7BE)
    val indigo = Color(0xFF5856D6)
    val cyan = Color(0xFF32ADE6)
    val pink = Color(0xFFFF2D55)
    val purple = Color(0xFFAF52DE)
    val yellow = Color(0xFFFFCC00)
    val teal = Color(0xFF30B0C7)
    val blue = Color(0xFF007AFF)
}

class GameInfo(
    val titleKey: String,
    val taglineKey: String,
    val emoji: String,
    val tint: Color,
    val category: GameCategory,
    val difficulty: Difficulty,
) {
    val title: String get() = L10n.t(titleKey)
    val tagline: String get() = L10n.t(taglineKey)
}

/**
 * Ids match the iOS app (`GameID` raw values) so stats and future cloud sync line up.
 * Only the games that are already ported to Android are listed; add a case here, an engine
 * and a composable, and register the view in [com.nurali.puzzlebox.games.GameHost].
 */
enum class GameId(val raw: String, val info: GameInfo) {
    Game2048("game2048", GameInfo("2048", "Merge tiles, reach 2048", "🔢", Tint.orange, GameCategory.Numbers, Difficulty.Medium)),
    Snake("snake", GameInfo("Snake", "Eat, grow, don't crash", "🐍", Tint.green, GameCategory.Arcade, Difficulty.Medium)),
    Minesweeper("minesweeper", GameInfo("Minesweeper", "Flag the mines, clear the field", "💣", Tint.red, GameCategory.Logic, Difficulty.Medium)),
    QuickMath("quickMath", GameInfo("Quick Math", "Beat the clock with mental math", "➗", Tint.mint, GameCategory.Numbers, Difficulty.Medium)),
    Simon("simon", GameInfo("Simon", "Watch, remember, repeat", "🎵", Tint.indigo, GameCategory.Reaction, Difficulty.Medium)),
    ReactionTap("reactionTap", GameInfo("Reaction Tap", "Wait for green, react fast", "⚡", Tint.red, GameCategory.Reaction, Difficulty.Easy)),
    LightsOut("lightsOut", GameInfo("Lights Out", "Tap to toggle a light and its neighbors. Turn all lights off.", "💡", Tint.yellow, GameCategory.Logic, Difficulty.Medium)),
    RedGreen("redGreen", GameInfo("Red Light, Green Light", "Tap to advance only on green. Reach the finish.", "🚦", Tint.red, GameCategory.Reaction, Difficulty.Medium)),
    PerfectTiming("perfectTiming", GameInfo("Perfect Timing", "Tap when the marker is inside the zone.", "🎯", Tint.mint, GameCategory.Reaction, Difficulty.Medium)),
    BubblePop("bubblePop", GameInfo("Bubble Pop", "Pop bubbles before they disappear.", "🫧", Tint.pink, GameCategory.Reaction, Difficulty.Medium)),
    WhackMole("whackMole", GameInfo("Whack-a-Mole", "Tap the target before it hides.", "🔨", Tint.orange, GameCategory.Reaction, Difficulty.Medium)),
    Nonogram("nonogram", GameInfo("Nonogram", "Use the row and column clues to fill the picture.", "🧩", Tint.cyan, GameCategory.Japanese, Difficulty.Medium)),
    NumberConnect("numberConnect", GameInfo("Numberlink", "Connect matching numbers without crossing. Fill every cell.", "🔗", Tint.pink, GameCategory.Japanese, Difficulty.Medium)),
    OneLine("oneLine", GameInfo("One Line", "Trace every edge once. Tap connected nodes.", "✏️", Tint.mint, GameCategory.Logic, Difficulty.Medium)),
    Unblock("unblock", GameInfo("Unblock", "Slide blocks along their length. Free the red block.", "🚗", Tint.orange, GameCategory.Logic, Difficulty.Medium)),
    FifteenPuzzle("fifteenPuzzle", GameInfo("15 Puzzle", "Slide tiles into order, with the empty cell last.", "🔢", Tint.indigo, GameCategory.Logic, Difficulty.Medium)),
    PipeConnect("pipeConnect", GameInfo("Pipe Connect", "Rotate pipes to connect IN to OUT through every cell.", "🚰", Tint.teal, GameCategory.Logic, Difficulty.Medium)),
    Dots("dots", GameInfo("Dots", "Connect adjacent matching dots, then release or tap Collect.", "🔴", Tint.pink, GameCategory.Logic, Difficulty.Medium)),
    FloodFill("floodFill", GameInfo("Flood Fill", "Choose colors to fill the board from the top-left corner.", "🌊", Tint.blue, GameCategory.Logic, Difficulty.Medium)),
    Laser("laser", GameInfo("Laser", "Rotate mirrors to guide the beam from the arrow to the star.", "🔦", Tint.red, GameCategory.Logic, Difficulty.Medium)),
    ColorLines("colorLines", GameInfo("Color Lines", "Move balls along clear paths. Make lines of five before the board fills.", "🎱", Tint.green, GameCategory.Logic, Difficulty.Medium)),
    ArrowMaze("arrowEscape", GameInfo("Rocket Maze", "Grab stars, speed up, reach the portal", "🚀", Tint.cyan, GameCategory.Arcade, Difficulty.Medium)),
    ArrowEscape("arrowEscapePuzzle", GameInfo("Arrow Escape", "Untangle the arrows and clear the board", "➡️", Tint.indigo, GameCategory.Logic, Difficulty.Medium)),
    Bounce("bounce", GameInfo("Bounce", "Roll, jump and collect every ring", "🔴", Tint.red, GameCategory.Arcade, Difficulty.Medium)),
    BasketShot("basketShot", GameInfo("Basket Shot", "Pull back from the ball and release to throw in the opposite direction.", "🏀", Tint.cyan, GameCategory.Physics, Difficulty.Medium)),
    BottleFlip("bottleFlip", GameInfo("Bottle Flip", "Swipe up from the bottle. Land upright after a full flip.", "🍼", Tint.pink, GameCategory.Physics, Difficulty.Medium)),
    MiniGolf("miniGolf", GameInfo("Golf", "Pull back from the ball and release. Sink it in 3 shots or fewer.", "⛳", Tint.purple, GameCategory.Physics, Difficulty.Medium)),
    Plinko("plinko", GameInfo("Plinko", "Drag across the top and release. Aim for the highlighted bin.", "🔮", Tint.pink, GameCategory.Physics, Difficulty.Medium)),
    RopeCut("ropeCut", GameInfo("Rope Cut", "Swipe across ropes to cut them. Swing the candy into the goal.", "✂️", Tint.mint, GameCategory.Physics, Difficulty.Medium)),
    DrawBridge("drawBridge", GameInfo("Draw Bridge", "Draw a bridge between the platforms, then tap Roll.", "🌉", Tint.purple, GameCategory.Physics, Difficulty.Medium)),
    Checkmate("checkmate", GameInfo("Checkmate", "Solve as many mates as you can", "♚", Tint.yellow, GameCategory.Logic, Difficulty.Hard)),
    BlockBlast("blockBlast", GameInfo("Block Blast", "Fill lines, clear the board", "🟧", Tint.orange, GameCategory.Logic, Difficulty.Easy)),
    Sudoku("sudoku", GameInfo("Sudoku", "6×6 and 9×9 puzzles with notes and hints", "🔟", Tint.indigo, GameCategory.Japanese, Difficulty.Medium)),
    WaterSort("waterSort", GameInfo("Water Sort", "Pour and sort the colors", "🧪", Tint.cyan, GameCategory.Logic, Difficulty.Medium)),
    Solitaire("solitaire", GameInfo("Solitaire", "Classic Klondike patience", "♦️", Tint.teal, GameCategory.Cards, Difficulty.Medium)),
    SpiderSolitaire("spiderSolitaire", GameInfo("Spider", "Build runs, clear the table", "♣️", Tint.purple, GameCategory.Cards, Difficulty.Hard)),
    Freecell("freecell", GameInfo("FreeCell", "Every deal is winnable", "♥️", Tint.pink, GameCategory.Cards, Difficulty.Hard)),
    FindColor("findColor", GameInfo("Find the Color", "Choose the ink color, not the word.", "🎨", Tint.pink, GameCategory.Attention, Difficulty.Medium)),
    FindPair("findPair", GameInfo("Find the Pair", "Find and tap the two identical symbols.", "🔍", Tint.pink, GameCategory.Attention, Difficulty.Medium)),
    RotatePuzzle("rotatePuzzle", GameInfo("Rotate Puzzle", "Tap each tile to rotate it and restore the picture.", "🖼️", Tint.mint, GameCategory.Visual, Difficulty.Medium)),
    Matchstick("matchstick", GameInfo("Matchstick Puzzle", "Move exactly one match: tap a lit segment, then an empty segment. Fix the equation.", "🔥", Tint.purple, GameCategory.Numbers, Difficulty.Medium)),
    Slope("slope", GameInfo("Slope", "Drag sideways to steer the rolling ball around holes.", "⚪", Tint.cyan, GameCategory.Arcade, Difficulty.Medium)),
    CirclePong("circlePong", GameInfo("Circle Pong", "Drag around the circle to catch the ball with your paddle.", "🏓", Tint.pink, GameCategory.Arcade, Difficulty.Medium)),
    SpaceDodge("spaceDodge", GameInfo("Space Dodge", "Drag the ship with one finger to dodge asteroids.", "🚀", Tint.purple, GameCategory.Arcade, Difficulty.Medium)),
    EndlessClimb("endlessClimb", GameInfo("Endless Climb", "Drag sideways. Jump onto platforms and keep climbing.", "🪜", Tint.pink, GameCategory.Arcade, Difficulty.Medium)),
    MergeFruit("mergeFruit", GameInfo("Merge Fruit", "Drop fruit and merge pairs", "🍉", Tint.green, GameCategory.Physics, Difficulty.Medium)),
    Stack("stack", GameInfo("Stack", "Build the tallest tower", "🧱", Tint.mint, GameCategory.Arcade, Difficulty.Easy)),
    KnifeSpin("knifeSpin", GameInfo("Knife Spin", "Hit the target, avoid the pins", "🔪", Tint.orange, GameCategory.Arcade, Difficulty.Medium)),
    HelixDrop("helixDrop", GameInfo("Helix Drop", "Rotate, drop, avoid red", "🌀", Tint.cyan, GameCategory.Arcade, Difficulty.Medium)),
    FlappyFlight("flappyFlight", GameInfo("Flappy Flight", "Tap to fly between obstacles", "🐦", Tint.yellow, GameCategory.Arcade, Difficulty.Hard)),
    RoadHop("roadHop", GameInfo("Road Hop", "Hop across busy lanes", "🚗", Tint.teal, GameCategory.Arcade, Difficulty.Medium)),
    ChainReaction("chainReaction", GameInfo("Chain Reaction", "One tap sets off a chain. Hit the target to reach the next level.", "✨", Tint.green, GameCategory.Arcade, Difficulty.Medium)),
    Asyk("asyk", GameInfo("Asyk", "Knock the asyks out of the ring", "🎯", Tint.orange, GameCategory.Physics, Difficulty.Medium)),
    Crossword("crossword", GameInfo("Crossword", "Fill the grid from the clues", "🔤", Tint.indigo, GameCategory.Logic, Difficulty.Medium)),
    Baige("baige", GameInfo("Baige", "Gallop, jump, collect, win the race", "🏇", Tint.orange, GameCategory.Arcade, Difficulty.Medium)),
    Kokpar("kokpar", GameInfo("Kokpar", "Ride, dodge rivals, deliver the serke", "🐎", Tint.green, GameCategory.Arcade, Difficulty.Medium)),
    Altybakan("altybakan", GameInfo("Altybakan", "Swing higher and ring the bells", "🔔", Tint.yellow, GameCategory.Reaction, Difficulty.Medium)),
    Togyzkumalak("togyzkumalak", GameInfo("Togyzkumalak", "The Kazakh strategy game of nine pebbles", "⚫", Tint.teal, GameCategory.Logic, Difficulty.Hard));

    companion object {
        /** Games kept in the code but not offered yet. */
        val hidden: Set<GameId> = setOf(
            Togyzkumalak, Altybakan, Kokpar, Baige, Asyk, Crossword,
            QuickMath, BubblePop, Dots, ArrowMaze, BottleFlip, DrawBridge, FindColor, RotatePuzzle, Slope, ChainReaction,
        )
        val visible: List<GameId> get() = entries.filter { it !in hidden }
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}
