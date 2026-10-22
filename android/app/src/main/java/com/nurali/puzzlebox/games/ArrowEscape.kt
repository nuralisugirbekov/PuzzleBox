package com.nurali.puzzlebox.games

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Hearts
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

enum class EscDir(val dx: Int, val dy: Int) {
    Up(0, -1), Right(1, 0), Down(0, 1), Left(-1, 0);
    val opposite get() = when (this) { Up -> Down; Down -> Up; Left -> Right; Right -> Left }
}

data class EscCell(val x: Int, val y: Int) { fun offset(d: EscDir) = EscCell(x + d.dx, y + d.dy) }

class EscArrow(val id: Int, val cells: List<EscCell>, val direction: EscDir) { val head get() = cells.last() }

/** Stable integer PRNG: a level is identical across launches and devices. */
private class EscRandom(var state: Long) {
    fun index(upper: Int): Int {
        state = state * 6364136223846793005L + 1442695040888963407L
        return ((state ushr 32) % upper).toInt()
    }
}

class EscapePuzzle(val columns: Int, val rows: Int, val arrows: List<EscArrow>) {
    companion object {
        const val LEVEL_COUNT = 100

        fun make(level: Int): EscapePuzzle {
            val index = min(LEVEL_COUNT - 1, max(0, level))
            val columns = 8 + index * 8 / 99
            val rows = 11 + index * 11 / 99
            val random = EscRandom((index + 1) * -7046029254386353131L)
            val remaining = HashSet<EscCell>()
            for (y in 0 until rows) for (x in 0 until columns) remaining.add(EscCell(x, y))
            val arrows = ArrayList<EscArrow>()
            val owners = HashMap<EscCell, Int>()
            val depths = ArrayList<Int>()
            // Percentage of picks that chase the deepest blocking chain.
            val pickiness = 70 + index * 25 / 99
            fun inside(c: EscCell) = c.x in 0 until columns && c.y in 0 until rows
            while (remaining.isNotEmpty()) {
                // Only row/column extrema can see an edge.
                val candidates = ArrayList<Pair<EscCell, EscDir>>()
                for (y in 0 until rows) {
                    val xs = (0 until columns).filter { EscCell(it, y) in remaining }
                    if (xs.isNotEmpty()) { candidates.add(EscCell(xs.first(), y) to EscDir.Left); candidates.add(EscCell(xs.last(), y) to EscDir.Right) }
                }
                for (x in 0 until columns) {
                    val ys = (0 until rows).filter { EscCell(x, it) in remaining }
                    if (ys.isNotEmpty()) { candidates.add(EscCell(x, ys.first()) to EscDir.Up); candidates.add(EscCell(x, ys.last()) to EscDir.Down) }
                }
                val longer = candidates.filter { it.first.offset(it.second.opposite) in remaining }
                val pool = longer.ifEmpty { candidates }
                // Prefer heads whose exit ray is blocked by the deepest chain of earlier arrows.
                class Scored(val cell: EscCell, val dir: EscDir, val depth: Int, val blockers: Int)
                val scored = pool.map { (cell, dir) ->
                    var c = cell.offset(dir)
                    var depth = 0; val blockers = HashSet<Int>()
                    while (inside(c)) {
                        owners[c]?.let { blockers.add(it); depth = max(depth, depths[it]) }
                        c = c.offset(dir)
                    }
                    Scored(cell, dir, depth + 1, blockers.size)
                }
                val bestDepth = scored.maxOfOrNull { it.depth } ?: 1
                val greedy = random.index(100) < pickiness
                val best = scored.filter { !greedy || it.depth >= bestDepth - 1 }
                val mostBlocked = best.maxOfOrNull { it.blockers } ?: 0
                val finalists = best.filter { !greedy || it.blockers >= mostBlocked - 1 }
                val choice = finalists[random.index(finalists.size)]
                val direction = choice.dir
                val path = arrayListOf(choice.cell)
                remaining.remove(choice.cell)
                val targetLength = 3 + index / 25 + random.index(5)
                var backwards = direction.opposite
                while (path.size < targetLength) {
                    val end = path.last()
                    val options = (if (path.size == 1) listOf(backwards) else EscDir.entries).filter { end.offset(it) in remaining }
                    if (options.isEmpty()) break
                    val bends = options.filter { it != backwards }
                    val choices = if (bends.isNotEmpty() && random.index(100) < 65) bends else options
                    backwards = choices[random.index(choices.size)]
                    val next = end.offset(backwards)
                    path.add(next); remaining.remove(next)
                }
                for (c in path) owners[c] = arrows.size
                depths.add(choice.depth)
                arrows.add(EscArrow(arrows.size, path.reversed(), direction))
            }
            return EscapePuzzle(columns, rows, arrows)
        }
    }

    fun contains(c: EscCell) = c.x in 0 until columns && c.y in 0 until rows

    fun canRemove(arrow: EscArrow, occupancy: Map<EscCell, Int>): Boolean {
        var c = arrow.head.offset(arrow.direction)
        while (contains(c)) { val o = occupancy[c]; if (o != null && o != arrow.id) return false; c = c.offset(arrow.direction) }
        return true
    }
}

class ArrowEscapeEngine : FrameGame {
    companion object {
        const val MAX_LIVES = 3
        const val FLIGHT = 1.4
        fun flightDistance(t: Double): Float = (450 * t + 900 * t * t).toFloat()
    }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var levelIndex by mutableIntStateOf(0)
    var puzzle by mutableStateOf(EscapePuzzle.make(0))
    var version by mutableIntStateOf(0)
    var mistakes by mutableIntStateOf(0)
    var onBoardCount by mutableIntStateOf(0)
    var blockedId by mutableStateOf<Int?>(null)

    val remaining = HashSet<Int>()
    val moving = HashMap<Int, Double>()
    private val occupancy = HashMap<EscCell, Int>()

    val lives get() = max(0, MAX_LIVES - mistakes)
    val hasNextLevel get() = levelIndex + 1 < EscapePuzzle.LEVEL_COUNT

    init { resetBoard() }

    override fun restart() = resetBoard()

    fun selectLevel(i: Int) {
        if (i !in 0 until EscapePuzzle.LEVEL_COUNT || i == levelIndex) return
        levelIndex = i; puzzle = EscapePuzzle.make(i); resetBoard()
    }

    fun nextLevel() = selectLevel(levelIndex + 1)

    /** Launches the arrow in [cell]. Arrows already flying don't block. */
    fun tap(cell: EscCell) {
        if (state != GameState.Playing) return
        val id = occupancy[cell] ?: return
        val arrow = puzzle.arrows[id]
        if (!puzzle.canRemove(arrow, occupancy)) {
            blockedId = id; mistakes++
            Haptics.error()
            if (lives == 0) state = GameState.GameOver(won = false) else Sfx.wrong()
            return
        }
        if (blockedId == id) blockedId = null
        for (c in arrow.cells) occupancy.remove(c)
        moving[id] = 0.0
        onBoardCount = remaining.size - moving.size
        score = (puzzle.arrows.size - onBoardCount) * 10
        Haptics.tap(); Sfx.tap()
    }

    override fun advance(dt: Double) {
        if (state != GameState.Playing || moving.isEmpty()) return
        val step = min(max(dt, 0.0), 1.0 / 15)
        val it = moving.entries.iterator()
        val done = ArrayList<Int>()
        for (e in moving.entries) { val next = e.value + step; if (next >= FLIGHT) done.add(e.key) else e.setValue(next) }
        for (id in done) { moving.remove(id); remaining.remove(id) }
        version++
        if (remaining.isEmpty()) { score += 200 + lives * 150; state = GameState.GameOver(won = true) }
    }

    private fun resetBoard() {
        moving.clear(); blockedId = null; mistakes = 0; score = 0; state = GameState.Playing
        remaining.clear(); remaining.addAll(puzzle.arrows.map { it.id })
        occupancy.clear()
        for (a in puzzle.arrows) for (c in a.cells) occupancy[c] = a.id
        onBoardCount = remaining.size
        version++
    }
}

private const val CELL = 40f

@Composable
fun ArrowEscapeScreen(onExit: () -> Unit) {
    val engine = remember { ArrowEscapeEngine() }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(GameId.ArrowEscape, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.levelIndex + 1) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box {
                    Text("▦ " + L10n.f("Level %d of %d", engine.levelIndex + 1, EscapePuzzle.LEVEL_COUNT), color = pal.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                        for (i in 0 until EscapePuzzle.LEVEL_COUNT) DropdownMenuItem(text = { Text(L10n.f("Level %d", i + 1)) }, onClick = { menu = false; engine.selectLevel(i) })
                    }
                }
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text("${engine.onBoardCount}/${engine.puzzle.arrows.size}", color = pal.text, fontWeight = FontWeight.SemiBold)
            }
            val puzzle = engine.puzzle
            val input = remember(engine, puzzle) {
                object : FieldInput() {
                    override fun onDown(x: Float, y: Float) {
                        engine.tap(EscCell(floor(x / CELL).toInt(), floor(y / CELL).toInt()))
                    }
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                ArcadeField(engine, Modifier, fieldW = puzzle.columns * CELL, fieldH = puzzle.rows * CELL, background = pal.surface, input = input) { drawEscape(engine) }
            }
            Hearts(engine.lives, ArrowEscapeEngine.MAX_LIVES)
            Text(L10n.t(if (engine.blockedId == null) "Tap an arrow with a clear path." else "The path is blocked. Remove the arrow in front first."),
                color = if (engine.blockedId == null) pal.textSecondary else Color.Red, fontSize = 13.sp, textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 8.dp).heightIn(min = 36.dp).fillMaxWidth())
        }
    }
}

private fun Pen.drawEscape(e: ArrowEscapeEngine) {
    @Suppress("UNUSED_EXPRESSION") e.version
    val pal = listOf(Color(0xFFE8E8EC), Color(0xFF007AFF), Color(0xFF5856D6), Color(0xFF30B0C7))
    val lineWidth = max(2.5f, CELL * 0.22f)
    for (arrow in e.puzzle.arrows) {
        if (arrow.id !in e.remaining) continue
        val elapsed = e.moving[arrow.id]
        val travel = if (elapsed == null) 0f else ArrowEscapeEngine.flightDistance(elapsed) / CELL
        val color = if (e.blockedId == arrow.id) Color.Red else pal[arrow.id % pal.size]
        val pts = visiblePoints(arrow, travel)
        if (pts.size < 2) continue
        polyline(pts, color, lineWidth)
        val head = pts.last()
        val dx = arrow.direction.dx.toFloat(); val dy = arrow.direction.dy.toFloat()
        val size = CELL * 0.34f
        val a = Offset(head.x - dx * size - dy * size * 0.7f, head.y - dy * size + dx * size * 0.7f)
        val b = Offset(head.x - dx * size + dy * size * 0.7f, head.y - dy * size - dx * size * 0.7f)
        polyline(listOf(a, head, b), color, lineWidth)
    }
}

/** The tail follows the original winding path while the head extends along its exit ray. */
private fun visiblePoints(arrow: EscArrow, travel: Float): List<Offset> {
    val points = arrow.cells.map { Offset(it.x + 0.5f, it.y + 0.5f) }.toMutableList()
    val dx = arrow.direction.dx.toFloat(); val dy = arrow.direction.dy.toFloat()
    if (points.size == 1) points.add(0, Offset(points[0].x - dx * 0.6f, points[0].y - dy * 0.6f))
    val length = if (arrow.cells.size == 1) 0.6f else (arrow.cells.size - 1).toFloat()
    val head = points.last()
    // Long enough that the whole arrow can travel past any screen edge.
    val extension = length + ArrowEscapeEngine.flightDistance(ArrowEscapeEngine.FLIGHT) / CELL
    points.add(Offset(head.x + dx * extension, head.y + dy * extension))
    val start = travel; val end = start + length
    var distance = 0f
    val result = ArrayList<Offset>()
    for ((a, b) in points.zipWithNext()) {
        val segment = hypot(b.x - a.x, b.y - a.y)
        val low = max(start, distance); val high = min(end, distance + segment)
        if (high >= low && segment > 0) for (v in listOf(low, high)) {
            val t = (v - distance) / segment
            result.add(Offset((a.x + (b.x - a.x) * t) * CELL, (a.y + (b.y - a.y) * t) * CELL))
        }
        distance += segment
    }
    return result
}
