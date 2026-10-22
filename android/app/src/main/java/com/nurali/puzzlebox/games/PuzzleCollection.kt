package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
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
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.PuzzleGenerators
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.games.kit.SlidingPiece
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

enum class PuzzleMode(val id: GameId, val hint: String) {
    LightsOut(GameId.LightsOut, "Tap to toggle a light and its neighbors. Turn all lights off."),
    Nonogram(GameId.Nonogram, "Use the row and column clues to fill the picture."),
    NumberConnect(GameId.NumberConnect, "Connect matching numbers without crossing. Fill every cell."),
    OneLine(GameId.OneLine, "Trace every edge once. Tap connected nodes."),
    Unblock(GameId.Unblock, "Slide blocks along their length. Free the red block."),
    FifteenPuzzle(GameId.FifteenPuzzle, "Slide tiles into order, with the empty cell last."),
    PipeConnect(GameId.PipeConnect, "Rotate pipes to connect IN to OUT through every cell."),
    Dots(GameId.Dots, "Connect adjacent matching dots, then release or tap Collect."),
    FloodFill(GameId.FloodFill, "Choose colors to fill the board from the top-left corner."),
    Laser(GameId.Laser, "Rotate mirrors to guide the beam from the arrow to the star."),
    ColorLines(GameId.ColorLines, "Move balls along clear paths. Make lines of five before the board fills."),
}

/**
 * Engine for the whole puzzle collection. Board data uses plain arrays; every change bumps
 * [version], which the view reads to redraw and refresh.
 */
class PuzzleEngine(val mode: PuzzleMode) : FrameGame {
    companion object { const val LEVEL_COUNT = 60 }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var version by mutableIntStateOf(0)
    var level by mutableIntStateOf(1)
    var moves by mutableIntStateOf(0)
    var movesLeft by mutableIntStateOf(25)
    var markMode by mutableStateOf(false)

    var n = 5
    var grid = IntArray(25)
    var target = IntArray(0)
    val marks = HashSet<Int>()
    var selected: Int? = null
    val paths = LinkedHashMap<Int, MutableList<Int>>()
    var activePath = ArrayList<Int>()
    var pieces = ArrayList<SlidingPiece>()
    var beam = ArrayList<Int>()
    var nodes: List<Int> = emptyList()
    var edges: List<List<Int>> = emptyList()
    /** Moves an expert needs; drives the star rating. */
    var par = 0
    // Snapshot state: the colour buttons must recompose when a level changes the palette size.
    var colorCount by mutableIntStateOf(5)
    var nextBalls = ArrayList<Int>()
    var laserSource = 10
    var laserTarget = 15
    var pipeEnd = 12
    var pipeExit = 4
    var loopClosed = false
    var combo = 0

    private val history = ArrayList<Pair<IntArray, Int>>()
    private val levelKey get() = "puzzleLevel." + mode.name.replaceFirstChar { it.lowercase() }

    init {
        level = Settings.prefs.getInt(levelKey, 1).coerceIn(1, LEVEL_COUNT)
        restart()
    }

    override fun advance(dt: Double) {}

    private fun touch() { version++ }

    /** Endless score-attack modes have no level ladder. */
    val hasLevels get() = mode != PuzzleMode.Dots && mode != PuzzleMode.ColorLines
    val hasNextLevel get() = hasLevels && level < LEVEL_COUNT
    /**
     * 3 stars at or under par, 2 within 50 % over, else 1. Par is always a move count a player can reach;
     * modes whose par is an optimal solution (sliding blocks, 15 puzzle) allow 25 % on top for 3 stars.
     */
    val stars: Int get() {
        if (par == 0) return 3
        val best = if (mode == PuzzleMode.Unblock || mode == PuzzleMode.FifteenPuzzle) Math.ceil(par * 1.25).toInt() else par
        return if (moves <= best) 3 else if (moves <= best * 1.5) 2 else 1
    }

    fun selectLevel(value: Int) {
        if (!hasLevels || value !in 1..LEVEL_COUNT) return
        level = value
        Settings.prefs.edit().putInt(levelKey, level).apply()
        restart()
    }

    fun nextLevel() = selectLevel(level + 1)

    val canUndo get() = state == GameState.Playing && (history.isNotEmpty() || activePath.isNotEmpty() || paths.isNotEmpty())

    private fun adjacent(a: Int, b: Int) = abs(a / n - b / n) + abs(a % n - b % n) == 1
    private fun neighbors(i: Int) = listOf(i - n, i + n, i - 1, i + 1).filter { it in grid.indices && adjacent(i, it) }

    private fun win() {
        score = 100 + level * 50 + stars * 100
        if (hasLevels) Settings.prefs.edit().putInt(levelKey, min(LEVEL_COUNT, level + 1)).apply()
        state = GameState.GameOver(won = true)
        Haptics.success()
    }

    private fun save() { history.add(grid.copyOf() to score) }

    override fun restart() {
        state = GameState.Playing; score = 0; moves = 0; selected = null; marks.clear(); markMode = false
        paths.clear(); activePath = ArrayList(); pieces = ArrayList(); beam = ArrayList(); history.clear(); loopClosed = false; combo = 0
        n = 5; movesLeft = 25; grid = IntArray(25); target = IntArray(0); par = 0
        val random = PuzzleRandom(level.toLong() * 7919 + mode.name.fold(0L) { a, c -> (a * 31 + c.code) and 0xFFFFFF })
        val l = level
        when (mode) {
            PuzzleMode.LightsOut -> {
                n = min(7, 3 + (l - 1) / 6)
                val presses = min(n * n - 2, 2 + (l - 1) % 6 + n / 2)
                grid = PuzzleGenerators.lightsOut(n, presses, random)
                par = presses
            }
            PuzzleMode.Nonogram -> {
                n = min(9, 5 + (l - 1) / 10)
                target = PuzzleGenerators.nonogram(n, random)
                grid = IntArray(n * n)
            }
            PuzzleMode.NumberConnect -> {
                n = min(8, 5 + (l - 1) / 12)
                val pairs = min(n + 1, n - 1 + (l - 1) % 12 / 6)
                grid = PuzzleGenerators.numberConnect(n, min(pairs, 7), random)
            }
            PuzzleMode.OneLine -> {
                val size = if (l < 8) 3 else if (l < 25) 4 else 5
                n = size
                val r = PuzzleGenerators.oneLine(size, min(size * size * 2, 6 + l / 2), random)
                nodes = r.nodes; edges = r.edges
                grid = IntArray(n * n)
            }
            PuzzleMode.Unblock -> {
                n = 6; grid = IntArray(36)
                pieces = ArrayList(PuzzleGenerators.rushHour(min(12, 6 + l / 6), min(26, 5 + l / 2), random))
                par = PuzzleGenerators.rushHourDepth(pieces) ?: 0
            }
            PuzzleMode.FifteenPuzzle -> {
                n = if (l < 6) 3 else 4
                grid = IntArray(n * n) { if (it == n * n - 1) 0 else it + 1 }; target = grid.copyOf()
                val shuffles = if (n == 3) 12 + l * 4 else 30 + l * 6
                var last = -1
                repeat(shuffles) {
                    val empty = grid.indexOf(0)
                    val choices = neighbors(empty).filter { it != last }
                    val source = choices.random(random)
                    val t = grid[source]; grid[source] = grid[empty]; grid[empty] = t
                    last = empty
                }
                if (grid.contentEquals(target)) {
                    swap(grid.size - 2, grid.size - 1); swap(grid.size - 3, grid.size - 2)
                }
                par = min(shuffles, if (n == 3) 30 else 120)
            }
            PuzzleMode.PipeConnect -> {
                n = min(7, 4 + (l - 1) / 8)
                val r = PuzzleGenerators.pipes(n, random)
                target = r.grid; pipeEnd = r.end; pipeExit = r.exit
                grid = r.grid.copyOf()
                for (i in grid.indices) repeat(random.nextInt(4)) { grid[i] = rotate(grid[i]) }
                // Keep the entrance disconnected at the start, without changing solvability.
                while (grid[0] and 8 != 0) grid[0] = rotate(grid[0])
                // Each tap turns one tile a quarter turn, so par is the turns every tile still needs.
                par = grid.indices.sumOf { i -> (0..3).first { k -> (0 until k).fold(grid[i]) { v, _ -> rotate(v) } == target[i] } }
                updatePipes()
            }
            PuzzleMode.Dots -> {
                n = 6; colorCount = 4; grid = IntArray(36) { Random.nextInt(1, 5) }; movesLeft = 20
                grid[1] = grid[0] // At least one opening move.
            }
            PuzzleMode.FloodFill -> {
                n = min(14, 8 + (l - 1) / 5)
                colorCount = if (l < 15) 5 else 6
                grid = IntArray(n * n) { random.nextInt(1, colorCount + 1) }
                val greedy = PuzzleGenerators.floodGreedySteps(grid, n, colorCount)
                movesLeft = greedy + max(0, 4 - l / 6)
                par = greedy
            }
            PuzzleMode.Laser -> {
                n = min(8, 5 + (l - 1) / 12)
                val turns = min(n + 1, 2 + (l - 1) / 5)
                val r = PuzzleGenerators.laser(n, turns, min(8, l / 3), random)
                grid = r.grid; laserSource = r.source; laserTarget = r.target
                // Flip some mirrors so the beam starts off course.
                val mirrorCells = grid.indices.filter { grid[it] > 0 }
                for (i in mirrorCells) if (random.nextBoolean()) grid[i] = 3 - grid[i]
                updateLaser()
                if (beam.lastOrNull() == laserTarget && mirrorCells.isNotEmpty()) { grid[mirrorCells.first()] = 3 - grid[mirrorCells.first()]; updateLaser() }
                par = turns
            }
            PuzzleMode.ColorLines -> {
                n = 9; grid = IntArray(81); colorCount = 6
                nextBalls = ArrayList((0 until 3).map { Random.nextInt(1, colorCount + 1) })
                spawnBalls(5)
            }
        }
        touch()
    }

    private fun swap(a: Int, b: Int) { val t = grid[a]; grid[a] = grid[b]; grid[b] = t }

    fun tap(i: Int) {
        if (state != GameState.Playing || i !in grid.indices) return
        when (mode) {
            PuzzleMode.LightsOut -> {
                save(); toggle(i); moves++
                if (grid.all { it == 0 }) win()
            }
            PuzzleMode.Nonogram -> {
                if (markMode) { if (!marks.add(i)) marks.remove(i); grid[i] = 0 }
                else { grid[i] = 1 - grid[i]; marks.remove(i) }
                moves++
                if (nonogramSolved) win()
            }
            PuzzleMode.NumberConnect -> connect(i)
            PuzzleMode.OneLine -> trace(i)
            PuzzleMode.Unblock -> selected = pieces.indexOfFirst { i in it.cells }.takeIf { it >= 0 }
            PuzzleMode.FifteenPuzzle -> {
                val empty = grid.indexOf(0)
                if (empty < 0) return
                // Tapping any tile in the empty cell's row or column slides the whole line.
                val sameRow = i / n == empty / n; val sameColumn = i % n == empty % n
                if (i == empty || !(sameRow || sameColumn)) return
                save()
                val step = if (sameRow) (if (i > empty) 1 else -1) else (if (i > empty) n else -n)
                var hole = empty
                while (hole != i) { swap(hole, hole + step); hole += step; moves++ }
                if (grid.contentEquals(target)) win()
            }
            PuzzleMode.PipeConnect -> { save(); grid[i] = rotate(grid[i]); moves++; updatePipes() }
            PuzzleMode.Dots -> extendDots(i)
            PuzzleMode.FloodFill -> {} // Color buttons are the controls for this mode.
            PuzzleMode.Laser -> {
                if (grid[i] <= 0) return
                save(); grid[i] = 3 - grid[i]; moves++; updateLaser()
                if (beam.lastOrNull() == laserTarget) win()
            }
            PuzzleMode.ColorLines -> moveBall(i)
        }
        Haptics.tap(); Sfx.tap()
        touch()
    }

    private fun clues(values: List<Int>): List<Int> {
        val result = ArrayList<Int>(); var count = 0
        for (v in values + 0) { if (v == 1) count++ else if (count > 0) { result.add(count); count = 0 } }
        return result.ifEmpty { listOf(0) }
    }

    val rowClues: List<List<Int>> get() = (0 until n).map { r -> clues((0 until n).map { target[r * n + it] }) }
    val columnClues: List<List<Int>> get() = (0 until n).map { c -> clues((0 until n).map { target[it * n + c] }) }
    fun rowSolved(r: Int) = clues((0 until n).map { grid[r * n + it] }) == rowClues[r]
    fun columnSolved(c: Int) = clues((0 until n).map { grid[it * n + c] }) == columnClues[c]
    val nonogramSolved get() = (0 until n).all { rowSolved(it) } && (0 until n).all { columnSolved(it) }

    private fun toggle(i: Int) { for (index in listOf(i) + neighbors(i)) grid[index] = 1 - grid[index] }

    fun undo() {
        if (state != GameState.Playing) return
        if (mode == PuzzleMode.NumberConnect) { paths.clear(); activePath.clear(); selected = null; touch(); return }
        if (mode == PuzzleMode.OneLine || mode == PuzzleMode.Dots) {
            if (activePath.isNotEmpty()) { activePath.removeAt(activePath.lastIndex); loopClosed = false }
            touch(); return
        }
        if (history.isNotEmpty()) {
            val prev = history.removeAt(history.lastIndex)
            grid = prev.first; score = prev.second; moves++
            if (mode == PuzzleMode.PipeConnect) updatePipes()
            if (mode == PuzzleMode.Laser) updateLaser()
        }
        touch()
    }

    val pairCount get() = grid.filter { it > 0 }.toSet().size

    private fun connect(i: Int) {
        val color = selected
        val last = activePath.lastOrNull()
        if (color != null && last != null && adjacent(last, i)) {
            if (activePath.size > 1 && activePath[activePath.size - 2] == i) {
                activePath.removeAt(activePath.lastIndex); paths[color] = ArrayList(activePath); return
            }
            val occupied = paths.filter { it.key != color }.values.flatten()
            if (i !in activePath && i !in occupied && (grid[i] == 0 || grid[i] == color)) {
                activePath.add(i); paths[color] = ArrayList(activePath)
                if (grid[i] == color) {
                    selected = null; activePath = ArrayList()
                    Sfx.tap()
                    val complete = paths.values.count { it.size > 1 && grid[it.first()] == grid[it.last()] }
                    if (complete == pairCount && paths.values.flatten().toSet().size == n * n) win()
                }
                return
            }
        }
        if (grid[i] > 0) { selected = grid[i]; activePath = arrayListOf(i); paths[grid[i]] = arrayListOf(i) }
    }

    private fun trace(i: Int) {
        if (i !in nodes) return
        if (activePath.isEmpty()) { activePath.add(i); return }
        val a = activePath.last()
        if (edges.none { setOf(it[0], it[1]) == setOf(a, i) }) return
        val used = activePath.zipWithNext().any { setOf(it.first, it.second) == setOf(a, i) }
        if (used) return
        activePath.add(i); moves++
        if (activePath.size == edges.size + 1) win()
    }

    fun slide(dr: Int, dc: Int) {
        val index = selected ?: return
        if (state != GameState.Playing || index !in pieces.indices) return
        val piece = pieces[index].copy()
        if (!(if (piece.horizontal) (dr == 0 && abs(dc) == 1) else (dc == 0 && abs(dr) == 1))) return
        piece.row += dr; piece.col += dc
        if (piece.row < 0 || piece.col < 0 ||
            piece.row + (if (piece.horizontal) 1 else piece.length) > 6 ||
            piece.col + (if (piece.horizontal) piece.length else 1) > 6) return
        val occupied = pieces.filter { it.id != piece.id }.flatMap { it.cells }.toSet()
        if (piece.cells.any { it in occupied }) return
        pieces[index] = piece; moves++; Haptics.move(); Sfx.tap()
        if (piece.id == 0 && piece.col + piece.length == 6) win()
        touch()
    }

    /** Slides the selected piece as far as a drag of [steps] cells allows. */
    fun slide(dr: Int, dc: Int, steps: Int) {
        repeat(max(1, steps)) {
            if (state != GameState.Playing) return
            val before = moves
            slide(dr, dc)
            if (moves == before) return
        }
    }

    private fun rotate(mask: Int) = ((mask shl 1) and 15) or (mask shr 3)
    private fun opposite(bit: Int) = when (bit) { 1 -> 4; 4 -> 1; 2 -> 8; else -> 2 }

    private fun updatePipes() {
        val reached = HashSet<Int>(); val queue = ArrayDeque<Int>(); queue.add(0)
        if (grid[0] and 8 == 0) { beam = ArrayList(); return }
        while (queue.isNotEmpty()) {
            val i = queue.removeLast()
            if (!reached.add(i)) continue
            for ((bit, delta) in listOf(1 to -n, 2 to 1, 4 to n, 8 to -1)) if (grid[i] and bit != 0) {
                val next = i + delta
                if (next in grid.indices && adjacent(i, next) && grid[next] and opposite(bit) != 0) queue.add(next)
            }
        }
        beam = ArrayList(reached)
        // Each tile has exactly two ports; reaching all cells and the sink makes one sealed route.
        if (reached.size == grid.size && grid[pipeEnd] and pipeExit != 0) win()
    }

    private fun region(source: Int): Set<Int> {
        val found = HashSet<Int>(); val queue = ArrayDeque<Int>(); queue.add(source)
        val value = grid[source]
        while (queue.isNotEmpty()) {
            val i = queue.removeLast()
            if (!found.add(i)) continue
            queue.addAll(neighbors(i).filter { grid[it] == value && it !in found })
        }
        return found
    }

    // MARK: Dots

    private fun extendDots(i: Int) {
        if (activePath.isEmpty()) { activePath = arrayListOf(i); loopClosed = false; return }
        if (activePath.last() == i) return
        if (activePath.size > 1 && activePath[activePath.size - 2] == i) { activePath.removeAt(activePath.lastIndex); loopClosed = false; return }
        if (loopClosed) return
        if (grid[i] == grid[activePath[0]] && adjacent(activePath.last(), i)) {
            if (i !in activePath) { activePath.add(i); Sfx.tap() }
            else if (activePath.size >= 4) {
                // Closing a loop clears every dot of that colour.
                activePath.add(i); loopClosed = true; Haptics.move(); Sfx.point()
            }
        } else activePath = arrayListOf(i)
    }

    private val hasGroups get() = grid.indices.any { i -> grid[i] > 0 && neighbors(i).any { grid[it] == grid[i] } }

    fun collectDots() {
        if (state != GameState.Playing || mode != PuzzleMode.Dots || activePath.size < 2) return
        val color = grid[activePath[0]]
        val cleared = if (loopClosed) grid.indices.filter { grid[it] == color }.toSet() else activePath.toSet()
        score += cleared.size * cleared.size * 5 + (if (loopClosed) 100 else 0)
        for (i in cleared) grid[i] = 0
        activePath = ArrayList(); loopClosed = false; moves++; movesLeft--
        Haptics.move(); Sfx.point()
        collapse()
        if (movesLeft == 0) state = GameState.GameOver(won = true)
        else if (!hasGroups) grid[1] = grid[0]
        touch()
    }

    private fun collapse() {
        for (c in 0 until n) {
            var values = (0 until n).map { grid[it * n + c] }.filter { it > 0 }
            val empty = n - values.size
            values = (0 until empty).map { Random.nextInt(1, colorCount + 1) } + values
            for (r in 0 until n) grid[r * n + c] = values[r]
        }
    }

    // MARK: Flood fill

    val floodRegionSize get() = if (grid.isEmpty()) 0 else region(0).size

    fun flood(color: Int) {
        if (mode != PuzzleMode.FloodFill || state != GameState.Playing || color == grid[0]) return
        val before = region(0).size
        for (i in region(0)) grid[i] = color
        moves++; movesLeft--
        val gained = region(0).size - before
        Haptics.tap(); if (gained >= 8) Sfx.point() else Sfx.tap()
        if (grid.toSet().size == 1) { win(); score += movesLeft * 50 }
        else if (movesLeft == 0) { score = region(0).size * 5; state = GameState.GameOver(won = false) }
        touch()
    }

    // MARK: Laser

    private fun updateLaser() {
        var cell = laserSource; var dr = 0; var dc = 1
        val visited = HashSet<String>(); beam = ArrayList()
        while (cell in grid.indices) {
            if (!visited.add("$cell:$dr:$dc")) break
            beam.add(cell)
            if (cell == laserTarget) break
            if (grid[cell] == 1) { val old = dr; dr = -dc; dc = -old }
            else if (grid[cell] == 2) { val old = dr; dr = dc; dc = old }
            val r = cell / n + dr; val c = cell % n + dc
            if (r !in 0 until n || c !in 0 until n) break
            cell = r * n + c
        }
    }

    // MARK: Color lines

    private fun moveBall(i: Int) {
        if (grid[i] > 0) { selected = i; return }
        val from = selected ?: return
        val seen = hashSetOf(from); val queue = ArrayDeque<Int>(); queue.add(from)
        while (queue.isNotEmpty()) {
            val p = queue.removeLast()
            for (next in neighbors(p)) if (grid[next] == 0 && seen.add(next)) queue.add(next)
        }
        if (i !in seen) { Sfx.wrong(); return }
        grid[i] = grid[from]; grid[from] = 0; selected = null; moves++
        if (clearLines()) combo++ else { combo = 0; spawnBalls(3); clearLines() }
        if (!grid.contains(0)) state = GameState.GameOver(won = false)
    }

    private fun spawnBalls(count: Int) {
        val free = grid.indices.filter { grid[it] == 0 }.shuffled()
        for ((k, i) in free.take(count).withIndex()) grid[i] = if (k < nextBalls.size) nextBalls[k] else Random.nextInt(1, colorCount + 1)
        nextBalls = ArrayList((0 until 3).map { Random.nextInt(1, colorCount + 1) })
    }

    private fun clearLines(): Boolean {
        val removed = HashSet<Int>()
        for (i in grid.indices) if (grid[i] > 0) {
            for ((dr, dc) in listOf(0 to 1, 1 to 0, 1 to 1, 1 to -1)) {
                val line = arrayListOf(i); var r = i / n + dr; var c = i % n + dc
                while (r in 0 until n && c in 0 until n && grid[r * n + c] == grid[i]) { line.add(r * n + c); r += dr; c += dc }
                if (line.size >= 5) removed.addAll(line)
            }
        }
        if (removed.isEmpty()) return false
        for (i in removed) grid[i] = 0
        // Longer lines and back-to-back clears pay more.
        score += removed.size * 10 + max(0, removed.size - 5) * 20 + combo * 25
        Haptics.success(); Sfx.win()
        return true
    }
}

val PuzzleColors = listOf(Color.Transparent, Color(0xFF32ADE6), Color(0xFFFF2D55), Color(0xFFFF9500), Color(0xFF34C759),
    Color(0xFFAF52DE), Color(0xFFFFCC00), Color(0xFFFF3B30))

@Composable
fun PuzzleScreen(mode: PuzzleMode, onExit: () -> Unit) {
    val engine = remember { PuzzleEngine(mode) }
    val pal = Pal.current
    val sliding = mode == PuzzleMode.Unblock
    GameContainer(mode.id, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            PuzzleHud(engine)
            val input = remember(engine) {
                object : FieldInput() {
                    var last: Int? = null
                    var startX = 0f; var startY = 0f
                    override fun onDown(x: Float, y: Float) {
                        startX = x; startY = y; last = null
                        val cell = engine.cellAt(x, y) ?: return
                        if (sliding || mode in setOf(PuzzleMode.Dots, PuzzleMode.NumberConnect, PuzzleMode.OneLine)) { engine.tap(cell); last = cell }
                    }
                    override fun onMove(x: Float, y: Float) {
                        if (sliding) return
                        if (mode !in setOf(PuzzleMode.Dots, PuzzleMode.NumberConnect, PuzzleMode.OneLine)) return
                        val cell = engine.cellAt(x, y) ?: return
                        if (cell != last) { engine.tap(cell); last = cell }
                    }
                    override fun onUp(x: Float, y: Float, tapped: Boolean) {
                        val dx = x - startX; val dy = y - startY
                        if (sliding) {
                            val cellSize = engine.cellSize()
                            if (max(abs(dx), abs(dy)) > 15f * 360f / 320f) {
                                val steps = Math.round(max(abs(dx), abs(dy)) / cellSize)
                                engine.slide(if (abs(dy) > abs(dx)) (if (dy > 0) 1 else -1) else 0, if (abs(dx) >= abs(dy)) (if (dx > 0) 1 else -1) else 0, steps)
                            }
                        } else if (mode == PuzzleMode.Dots) {
                            if (hypot(dx, dy) > 12f) engine.collectDots()
                        } else if (mode != PuzzleMode.NumberConnect && mode != PuzzleMode.OneLine) {
                            engine.cellAt(x, y)?.let { engine.tap(it) }
                        }
                        last = null
                    }
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 420.dp), fieldW = 360f, fieldH = 360f, animated = false, input = input) {
                @Suppress("UNUSED_EXPRESSION") engine.version
                drawPuzzle(engine)
            }
            Spacer8()
            PuzzleControls(engine)
            Text(L10n.t(mode.hint), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

@Composable
private fun Spacer8() = androidx.compose.foundation.layout.Spacer(Modifier.size(8.dp))

@Composable
private fun PuzzleHud(e: PuzzleEngine) {
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        if (e.hasLevels) Box {
            Text("▦ " + L10n.f("Level %d", e.level), color = pal.accent, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { menu = true })
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                for (lv in 1..PuzzleEngine.LEVEL_COUNT) DropdownMenuItem(text = { Text(L10n.f("Level %d", lv)) }, onClick = { menu = false; e.selectLevel(lv) })
            }
        }
        Text(L10n.f("%d moves", e.moves), color = pal.accent)
        Spacer(Modifier.weight(1f))
        if (e.mode == PuzzleMode.Dots || e.mode == PuzzleMode.FloodFill) {
            Text(L10n.f("%d moves left", e.movesLeft), color = if (e.movesLeft <= 3) Color.Red else pal.accent, fontWeight = FontWeight.SemiBold)
        } else if (e.par > 0) {
            Text((0 until 3).joinToString("") { if (it < e.stars) "★" else "☆" }, color = Color(0xFFFFCC00), fontSize = 14.sp)
        }
        if (e.mode == PuzzleMode.ColorLines) Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            e.nextBalls.forEach { Box(Modifier.size(14.dp).clip(CircleShape).background(PuzzleColors[it])) }
        }
        if (e.canUndo) Text("↩", color = pal.accent, fontSize = 20.sp, modifier = Modifier.clickable { e.undo() })
    }
}

@Composable
private fun PuzzleControls(e: PuzzleEngine) {
    val pal = Pal.current
    if (e.mode == PuzzleMode.Nonogram) Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(pal.surface), horizontalArrangement = Arrangement.SpaceEvenly) {
        listOf(false to "Fill", true to "Mark empty").forEach { (v, label) ->
            Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (e.markMode == v) pal.accent else Color.Transparent)
                .clickable { e.markMode = v }.padding(vertical = 10.dp), contentAlignment = Alignment.Center) {
                Text(L10n.t(label), color = if (e.markMode == v) pal.onAccent else pal.text, fontWeight = FontWeight.SemiBold)
            }
        }
    }
    if (e.mode == PuzzleMode.Unblock) Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        listOf("←" to (0 to -1), "↑" to (-1 to 0), "↓" to (1 to 0), "→" to (0 to 1)).forEach { (g, d) ->
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(pal.surface).clickable { e.slide(d.first, d.second) }, contentAlignment = Alignment.Center) {
                Text(g, color = pal.text, fontSize = 20.sp)
            }
        }
    }
    if (e.mode == PuzzleMode.Dots) {
        val enabled = e.activePath.size >= 2
        Box(Modifier.clip(RoundedCornerShape(24.dp)).background(if (!enabled) pal.surfaceHigh else if (e.loopClosed) Color(0xFFFF9500) else pal.accent)
            .clickable(enabled = enabled) { e.collectDots() }.padding(horizontal = 28.dp, vertical = 12.dp)) {
            Text(L10n.t(if (e.loopClosed) "Collect all!" else "Collect"), color = if (enabled) pal.onAccent else pal.textSecondary, fontWeight = FontWeight.Bold)
        }
    }
    if (e.mode == PuzzleMode.FloodFill) Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (color in 1..e.colorCount) Box(Modifier.size(42.dp).clip(CircleShape).background(PuzzleColors[color]).clickable { e.flood(color) }, contentAlignment = Alignment.Center) {
            if (e.grid.firstOrNull() == color) Text("✓", color = Color.Black, fontWeight = FontWeight.Black)
        }
    }
}

// MARK: - Layout & drawing (field is 360 × 360 units)

private fun PuzzleEngine.margin(): Float {
    if (mode == PuzzleMode.Nonogram) {
        val longest = (rowClues + columnClues).maxOf { it.size }
        return min(90f, 18f + longest * 12f)
    }
    return 14f
}

fun PuzzleEngine.cellSize(): Float = (360f - margin() - 14f) / n

fun PuzzleEngine.cellAt(px: Float, py: Float): Int? {
    val m = margin(); val cell = cellSize()
    val x = px - m; val y = py - m
    if (x < 0 || y < 0 || x >= cell * n || y >= cell * n) return null
    return (y / cell).toInt() * n + (x / cell).toInt()
}

private fun Pen.drawPuzzle(e: PuzzleEngine) {
    val margin = e.margin(); val cell = e.cellSize(); val n = e.n
    val surfaceHigh = Color(0xFF212735); val surface = Color(0xFF161A25); val secondary = Color(0xFF9E9E9E)
    val accent = Color(0xFF007AFF)
    fun cx(i: Int) = margin + ((i % n) + 0.5f) * cell
    fun cy(i: Int) = margin + ((i / n) + 0.5f) * cell
    fun pt(i: Int) = Offset(cx(i), cy(i))
    fun rx(i: Int) = margin + (i % n) * cell + 2f
    fun ry(i: Int) = margin + (i / n) * cell + 2f
    val rs = cell - 4f
    val clueFont = max(9f, min(13f, cell * 0.32f))

    if (e.mode == PuzzleMode.Nonogram) for (i in 0 until n) {
        val rowColor = if (e.rowSolved(i)) Color(0xFF34C759) else Color.White
        val colColor = if (e.columnSolved(i)) Color(0xFF34C759) else Color.White
        label(e.rowClues[i].joinToString(" "), margin / 2, cy(i * n), clueFont, rowColor)
        label(e.columnClues[i].joinToString("\n"), cx(i), margin / 2, clueFont, colColor)
    }
    if (e.mode == PuzzleMode.OneLine) {
        for (edge in e.edges) polyline(edge.map { pt(it) }, secondary.copy(alpha = 0.45f), 6f)
        polyline(e.activePath.map { pt(it) }, accent.copy(alpha = 0.35f), 14f)
        polyline(e.activePath.map { pt(it) }, accent, 7f)
        for (i in e.nodes) {
            val inset = cell * 0.28f
            val color = if (e.activePath.lastOrNull() == i) Color(0xFFFF9500) else if (i in e.activePath) accent else PuzzleColors[1]
            ball(rx(i) + inset, ry(i) + inset, rs - inset * 2, color)
        }
        return
    }
    for (i in e.grid.indices) {
        val value = e.grid[i]; val x = rx(i); val y = ry(i); val px = cx(i); val py = cy(i)
        when (e.mode) {
            PuzzleMode.LightsOut -> if (value == 1) {
                box(x - 2, y - 2, rs + 4, rs + 4, Color(0xFFFFCC00).copy(alpha = 0.25f), 9f)
                tile(x, y, rs, rs, Color(0xFFFFF299), Color(0xFFFF9500), 8f)
            } else tile(x, y, rs, rs, Color(0xFF3D3D3D), Color(0xFF292929), 8f)
            PuzzleMode.Nonogram -> {
                if (value == 1) tile(x, y, rs, rs, PuzzleColors[1], Color(0xFF008CBF), 4f) else box(x, y, rs, rs, surfaceHigh, 4f)
                if (i in e.marks) label("×", px, py, 18f, secondary)
            }
            PuzzleMode.FloodFill -> box(margin + (i % n) * cell, margin + (i / n) * cell, cell + 0.5f, cell + 0.5f, PuzzleColors[value], 0f)
            PuzzleMode.FifteenPuzzle -> if (value > 0) {
                val home = value - 1 == i
                tile(x, y, rs, rs, if (home) Color(0xFF73CC8C) else Color(0xFF8073F2), if (home) Color(0xFF338C59) else Color(0xFF4D40B3), 10f)
                label(value.toString(), px, py, cell * 0.38f, Color.White)
            } else box(x, y, rs, rs, surface.copy(alpha = 0.4f), 10f)
            PuzzleMode.NumberConnect -> box(x, y, rs, rs, surfaceHigh, 5f)
            PuzzleMode.Dots, PuzzleMode.ColorLines -> {
                box(x, y, rs, rs, surfaceHigh.copy(alpha = 0.6f), 5f)
                if (value > 0) {
                    val inset = cell * 0.15f
                    ball(x + inset, y + inset, rs - inset * 2, PuzzleColors[value])
                    if (e.selected == i) strokeOval(x + 2, y + 2, rs - 4, rs - 4, Color.White, 2.5f)
                }
            }
            PuzzleMode.PipeConnect -> {
                box(x, y, rs, rs, surfaceHigh, 6f)
                val lit = i in e.beam
                for ((bit, d) in listOf(1 to (0 to -1), 2 to (1 to 0), 4 to (0 to 1), 8 to (-1 to 0))) if (value and bit != 0) {
                    val end = Offset(px + d.first * cell / 2, py + d.second * cell / 2)
                    if (lit) polyline(listOf(Offset(px, py), end), PuzzleColors[1].copy(alpha = 0.35f), cell * 0.36f)
                    polyline(listOf(Offset(px, py), end), if (lit) PuzzleColors[1] else Color(0xFF808080), cell * 0.2f)
                }
                circle(px, py, cell * 0.1f, if (lit) PuzzleColors[1] else Color(0xFF808080))
            }
            PuzzleMode.Laser -> {
                box(x, y, rs, rs, surfaceHigh.copy(alpha = 0.6f), 5f)
                if (value > 0) {
                    val dx = cell * 0.32f; val dy = if (value == 1) -dx else dx
                    polyline(listOf(Offset(px - dx, py - dy), Offset(px + dx, py + dy)), Color(0xFFD9D9D9), 6f)
                    polyline(listOf(Offset(px - dx, py - dy), Offset(px + dx, py + dy)), PuzzleColors[1].copy(alpha = 0.5f), 2f)
                }
            }
            else -> box(x, y, rs, rs, surfaceHigh, 5f)
        }
    }
    when (e.mode) {
        PuzzleMode.NumberConnect -> {
            for ((color, path) in e.paths) polyline(path.map { pt(it) }, PuzzleColors[color].copy(alpha = 0.7f), cell * 0.36f)
            for (i in e.grid.indices) if (e.grid[i] > 0) {
                val inset = cell * 0.14f
                ball(rx(i) + inset, ry(i) + inset, rs - inset * 2, PuzzleColors[e.grid[i]])
                label(e.grid[i].toString(), cx(i), cy(i), cell * 0.34f, Color.Black)
            }
        }
        PuzzleMode.Dots -> e.activePath.firstOrNull()?.let { first ->
            val color = PuzzleColors[e.grid[first]]
            polyline(e.activePath.map { pt(it) }, color.copy(alpha = if (e.loopClosed) 0.9f else 0.6f), cell * 0.18f)
            if (e.loopClosed) strokeBox(margin - 4, margin - 4, cell * n + 8, cell * n + 8, color, 3f, 12f)
        }
        PuzzleMode.Laser -> {
            val beam = e.beam.map { pt(it) }
            polyline(beam, Color.Red.copy(alpha = 0.3f), 9f)
            polyline(beam, Color(0xFFFF6666), 3f)
            val sy = cy(e.laserSource)
            box(margin - 12, sy - 9, 14f, 18f, Color.Red, 3f)
            val tx = cx(e.laserTarget); val ty = cy(e.laserTarget)
            val reached = e.beam.lastOrNull() == e.laserTarget
            circle(tx, ty, cell * 0.38f, Color(0xFFFFCC00).copy(alpha = if (reached) 0.5f else 0.18f))
            label("★", tx, ty, cell * 0.5f, Color(0xFFFFCC00))
        }
        PuzzleMode.PipeConnect -> {
            label("▶", margin / 2, cy(0), 12f, PuzzleColors[1])
            val ex = cx(e.pipeEnd); val ey = cy(e.pipeEnd)
            val offset = cell / 2 + margin / 2
            val x = ex + (if (e.pipeExit == 2) offset else if (e.pipeExit == 8) -offset else 0f)
            val y = ey + (if (e.pipeExit == 4) offset else if (e.pipeExit == 1) -offset else 0f)
            label(when (e.pipeExit) { 2 -> "▶"; 8 -> "◀"; 4 -> "▼"; else -> "▲" }, x, y, 12f, Color(0xFF34C759))
        }
        else -> {}
    }
    if (e.mode == PuzzleMode.Unblock) {
        box(margin + cell * 6 - 2, margin + cell * 2 + 6, 8f, cell - 12, Color(0xFF34C759), 3f)
        for ((index, piece) in e.pieces.withIndex()) {
            val x = margin + piece.col * cell + 3; val y = margin + piece.row * cell + 3
            val w = (if (piece.horizontal) piece.length else 1) * cell - 6; val h = (if (piece.horizontal) 1 else piece.length) * cell - 6
            val color = if (piece.id == 0) Color.Red else PuzzleColors[piece.id % 6 + 1]
            box(x, y + 3, w, h, Color.Black.copy(alpha = 0.35f), 10f)
            tile(x, y, w, h, color, color.copy(alpha = 0.7f), 10f)
            box(x + 6, y + 6, w - 12, h - 12, Color.White.copy(alpha = 0.15f), 6f)
            if (e.selected == index) strokeBox(x, y, w, h, Color.White, 3f, 10f)
            label(if (piece.horizontal) "↔" else "↕", x + w / 2, y + h / 2, 18f, Color.Black.copy(alpha = 0.6f))
        }
    }
}
