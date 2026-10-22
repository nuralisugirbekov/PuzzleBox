package com.nurali.puzzlebox.games

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.ArcadeFX
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random

class BBPiece(val cells: List<Pair<Int, Int>>, val colorIndex: Int) {
    val width get() = (cells.maxOf { it.second }) + 1
    val height get() = (cells.maxOf { it.first }) + 1
}

class BlockBlastEngine : FrameGame {
    companion object {
        const val SIZE = 8
        const val COMBO_GRACE = 3
        val colors = listOf(Color(0xFF5856D6), Color(0xFF34C759), Color(0xFFAF52DE), Color(0xFFFF2D55), Color(0xFFFFCC00))

        private fun cells(rows: List<String>): List<Pair<Int, Int>> =
            rows.flatMapIndexed { r, row -> row.mapIndexedNotNull { c, ch -> if (ch == '#') r to c else null } }

        /** Squares, I4, and every rotation of T, L, J, the five-cell corner, S and Z. */
        val shapes: List<List<Pair<Int, Int>>> = listOf(
            listOf("###", "###", "###"), listOf("##", "##"),
            listOf("####"), listOf("#", "#", "#", "#"),
            listOf("###", ".#."), listOf("#.", "##", "#."), listOf(".#.", "###"), listOf(".#", "##", ".#"),
            listOf("#.", "#.", "##"), listOf("..#", "###"), listOf("##", ".#", ".#"), listOf("###", "#.."),
            listOf(".#", ".#", "##"), listOf("###", "..#"), listOf("##", "#.", "#."), listOf("#..", "###"),
            listOf("###", "..#", "..#"), listOf("###", "#..", "#.."), listOf("#..", "#..", "###"), listOf("..#", "..#", "###"),
            listOf("##.", ".##"), listOf(".#", "##", "#."), listOf(".##", "##."), listOf("#.", "##", ".#"),
        ).map { cells(it) }
    }

    class Snap(val grid: List<IntArray>, val tray: List<BBPiece?>, val score: Int, val combo: Int, val grace: Int)

    var grid = Array(SIZE) { IntArray(SIZE) { -1 } }
    var tray = listOf<BBPiece?>(null, null, null)
    override var score by mutableIntStateOf(0)
    var combo = 0
    var comboGraceLeft = 0
    /** Cells that just cleared, kept briefly so the view can burst them. */
    val flash = HashMap<Int, Int>()
    var flashTime = 0f
    override var state: GameState by mutableStateOf(GameState.Playing)
    val fx = ArcadeFX()
    private val history = ArrayList<Snap>()
    var historySize by mutableIntStateOf(0)
    val canUndo get() = state == GameState.Playing && historySize > 0

    init { restart() }

    override fun restart() {
        grid = Array(SIZE) { IntArray(SIZE) { -1 } }
        score = 0; combo = 0; comboGraceLeft = 0; flash.clear(); fx.reset(); history.clear(); historySize = 0
        refillTray(); state = GameState.Playing
    }

    fun undo() {
        if (!canUndo) return
        val p = history.removeAt(history.lastIndex); historySize = history.size
        grid = Array(SIZE) { p.grid[it].copyOf() }; tray = p.tray; score = p.score; combo = p.combo; comboGraceLeft = p.grace; flash.clear()
        Haptics.tap(); Sfx.tap()
    }

    /** Deals three random pieces, re-rolling a few times so at least one fits. */
    private fun refillTray() {
        for (attempt in 0 until 12) {
            val pieces = (0 until 3).map { BBPiece(shapes.random(), Random.nextInt(colors.size)) }
            tray = pieces
            if (attempt == 11 || pieces.any { canPlaceAnywhere(it) }) return
        }
    }

    fun canPlace(piece: BBPiece, r0: Int, c0: Int): Boolean = piece.cells.all { (r, c) ->
        val rr = r0 + r; val cc = c0 + c
        rr in 0 until SIZE && cc in 0 until SIZE && grid[rr][cc] < 0
    }

    fun canPlaceAnywhere(piece: BBPiece): Boolean {
        for (r in 0 until SIZE) for (c in 0 until SIZE) if (canPlace(piece, r, c)) return true
        return false
    }

    /** Rows and columns that would be completed by dropping [piece] at the origin. */
    fun linesCompleted(piece: BBPiece, r0: Int, c0: Int): Set<Int> {
        if (!canPlace(piece, r0, c0)) return emptySet()
        val added = piece.cells.map { (r0 + it.first) * SIZE + (c0 + it.second) }.toSet()
        fun filled(r: Int, c: Int) = grid[r][c] >= 0 || (r * SIZE + c) in added
        val out = HashSet<Int>()
        for (r in added.map { it / SIZE }.toSet()) if ((0 until SIZE).all { filled(r, it) }) for (c in 0 until SIZE) out.add(r * SIZE + c)
        for (c in added.map { it % SIZE }.toSet()) if ((0 until SIZE).all { filled(it, c) }) for (r in 0 until SIZE) out.add(r * SIZE + c)
        return out
    }

    fun place(index: Int, r0: Int, c0: Int): Boolean {
        if (state != GameState.Playing || index !in tray.indices) return false
        val piece = tray[index] ?: return false
        if (!canPlace(piece, r0, c0)) return false
        history.add(Snap(grid.map { it.copyOf() }, tray, score, combo, comboGraceLeft)); historySize = history.size
        for ((r, c) in piece.cells) grid[r0 + r][c0 + c] = piece.colorIndex
        score += piece.cells.size
        tray = tray.mapIndexed { i, p -> if (i == index) null else p }
        val (cleared, cellsCleared) = clearFullLines()
        if (cleared > 0) {
            combo++; comboGraceLeft = COMBO_GRACE
            // Multi-line clears pay off quadratically; streaks multiply them.
            val gained = cleared * cleared * 10 * combo
            score += gained
            val cx = cellsCleared.map { it % SIZE }.average().toFloat(); val cy = cellsCleared.map { it / SIZE }.average().toFloat()
            fx.popup("+$gained", boardX(cx + 0.5f), boardY(cy + 0.5f), Color.White, if (cleared > 1) 24f else 18f)
            if (combo > 1) fx.popup(L10n.f("Combo ×%d", combo), boardX(cx + 0.5f), max(40f, boardY(cy + 0.5f) - 44f), Color.Yellow, 22f)
            if (grid.all { row -> row.all { it < 0 } }) { score += 300; fx.popup(L10n.t("Board clear! +300"), 180f, 180f, Color(0xFF00C7BE), 24f) }
            if (combo > 1 || cleared > 1) Haptics.heavy() else Haptics.success()
            if (combo > 2) Sfx.point() else Sfx.win()
        } else {
            if (comboGraceLeft > 0) comboGraceLeft--
            if (comboGraceLeft == 0) combo = 0
            Haptics.move(); Sfx.tap()
        }
        if (tray.all { it == null }) refillTray()
        if (tray.filterNotNull().none { canPlaceAnywhere(it) }) { state = GameState.GameOver(won = false); Sfx.lose() }
        return true
    }

    private fun clearFullLines(): Pair<Int, Set<Int>> {
        val fullRows = (0 until SIZE).filter { r -> (0 until SIZE).all { grid[r][it] >= 0 } }
        val fullCols = (0 until SIZE).filter { c -> (0 until SIZE).all { grid[it][c] >= 0 } }
        val cells = HashSet<Int>()
        for (r in fullRows) for (c in 0 until SIZE) cells.add(r * SIZE + c)
        for (c in fullCols) for (r in 0 until SIZE) cells.add(r * SIZE + c)
        if (cells.isEmpty()) return 0 to emptySet()
        flash.clear()
        for (p in cells) { flash[p] = grid[p / SIZE][p % SIZE]; grid[p / SIZE][p % SIZE] = -1 }
        flashTime = 0.4f
        return (fullRows.size + fullCols.size) to cells
    }

    override fun advance(dt: Double) {
        fx.update(dt.toFloat())
        if (flashTime > 0) { flashTime -= dt.toFloat(); if (flashTime <= 0) flash.clear() }
    }
}

// Board geometry in field units (360 × 500): 8×8 cells, 38 wide with 4 gaps.
private const val CELL = 38f
private const val GAP = 4f
private const val PITCH = CELL + GAP
private const val BOARD_X = 10f
private const val BOARD_Y = 10f
private fun boardX(col: Float) = BOARD_X + GAP + col * PITCH - GAP / 2
private fun boardY(row: Float) = BOARD_Y + GAP + row * PITCH - GAP / 2
private const val TRAY_Y = 372f
private const val SLOT = 108f
private const val LIFT = 90f
private const val REACH = 1.8f

@Composable
fun BlockBlastScreen(onExit: () -> Unit) {
    val engine = remember { BlockBlastEngine() }
    val pal = Pal.current
    GameContainer(GameId.BlockBlast, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            val drag = remember(engine) { BlastDrag(engine) }
            ArcadeField(engine, Modifier.widthIn(max = 420.dp), fieldW = 360f, fieldH = 490f, background = Color.Transparent, fx = engine.fx, input = drag) { drawBlast(engine, drag, pal.surface, pal.surfaceHigh) }
            Column(Modifier.padding(top = 4.dp).clickable(enabled = engine.canUndo) { engine.undo() }, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("↩", fontSize = 26.sp, color = pal.text.copy(alpha = if (engine.canUndo) 1f else 0.4f))
                Text(L10n.t("Revert"), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = pal.text.copy(alpha = if (engine.canUndo) 1f else 0.4f))
            }
        }
    }
}

private class BlastDrag(val e: BlockBlastEngine) : FieldInput() {
    var index = -1
    var x = 0f; var y = 0f
    var startY = 0f

    override fun onDown(x: Float, y: Float) {
        if (e.state != GameState.Playing) return
        if (y < TRAY_Y) return
        val slot = ((x - 10f) / (SLOT + 8f)).toInt()
        if (slot in 0..2 && e.tray.getOrNull(slot) != null) { index = slot; this.x = x; this.y = y; startY = y; Haptics.tap(); Sfx.tap() }
    }

    override fun onMove(x: Float, y: Float) { if (index >= 0) { this.x = x; this.y = y } }

    override fun onUp(x: Float, y: Float, tapped: Boolean) {
        if (index < 0) return
        this.x = x; this.y = y
        target()?.let { if (it.valid) e.place(index, it.r, it.c) }
        index = -1
    }

    class Target(val r: Int, val c: Int, val valid: Boolean, val cells: Set<Int>, val clears: Set<Int>)

    /** Where the dragged piece is drawn: above the finger, pulling further ahead as the finger climbs. */
    fun center(piece: BBPiece): Pair<Float, Float> {
        val climbed = max(0f, startY - y)
        val py = y - LIFT - climbed * (REACH - 1)
        val topRow = BOARD_Y + piece.height * PITCH / 2
        return x to max(py, topRow)
    }

    fun target(): Target? {
        if (index < 0) return null
        val piece = e.tray.getOrNull(index) ?: return null
        val (cx, cy) = center(piece)
        val gx = (cx - BOARD_X - GAP) / PITCH - piece.width / 2f
        val gy = (cy - BOARD_Y - GAP) / PITCH - piece.height / 2f
        val r0 = gy.roundToInt(); val c0 = gx.roundToInt()
        val cells = piece.cells.map { (r0 + it.first) * BlockBlastEngine.SIZE + (c0 + it.second) }.toSet()
        return Target(r0, c0, e.canPlace(piece, r0, c0), cells, e.linesCompleted(piece, r0, c0))
    }
}

private fun Pen.blastCell(x: Float, y: Float, size: Float, color: Color) = box(x, y, size, size, color, 4f)

private fun Pen.drawBlast(e: BlockBlastEngine, d: BlastDrag, surface: Color, surfaceHigh: Color) {
    val n = BlockBlastEngine.SIZE
    val target = d.target()
    val dragged = if (d.index >= 0) e.tray.getOrNull(d.index) else null
    box(BOARD_X, BOARD_Y, n * PITCH + GAP, n * PITCH + GAP, surface, 8f)
    for (r in 0 until n) for (c in 0 until n) {
        val x = BOARD_X + GAP + c * PITCH; val y = BOARD_Y + GAP + r * PITCH
        val p = r * n + c
        val color = e.grid[r][c]
        val preview = target?.cells?.contains(p) == true
        when {
            color >= 0 -> blastCell(x, y, CELL, BlockBlastEngine.colors[color])
            preview && target?.valid == true && dragged != null -> blastCell(x, y, CELL, BlockBlastEngine.colors[dragged.colorIndex].copy(alpha = 0.5f))
            else -> blastCell(x, y, CELL, if (preview) Color.Red.copy(alpha = 0.35f) else surfaceHigh)
        }
        if (target?.clears?.contains(p) == true) strokeBox(x, y, CELL, CELL, Color.White, 2f, 4f)
        e.flash[p]?.let { fc ->
            val t = (e.flashTime / 0.4f).coerceIn(0f, 1f)
            val s = CELL * (0.05f + 0.95f * t)
            blastCell(x + (CELL - s) / 2, y + (CELL - s) / 2, s, BlockBlastEngine.colors[fc].copy(alpha = t))
            blastCell(x + (CELL - s) / 2, y + (CELL - s) / 2, s, Color.White.copy(alpha = 0.55f * t))
        }
    }
    // Tray: three square slots.
    for (i in 0 until 3) {
        val sx = 10f + i * (SLOT + 8f)
        box(sx, TRAY_Y, SLOT, SLOT, surface, 8f)
        val piece = e.tray.getOrNull(i) ?: continue
        if (d.index == i) continue
        val cs = if (piece.width > 3 || piece.height > 3) 18f else 24f
        val pitch = cs + 2f
        val ox = sx + (SLOT - (piece.width * pitch - 2f)) / 2; val oy = TRAY_Y + (SLOT - (piece.height * pitch - 2f)) / 2
        val alpha = if (e.canPlaceAnywhere(piece)) 1f else 0.3f
        for ((r, c) in piece.cells) blastCell(ox + c * pitch, oy + r * pitch, cs, BlockBlastEngine.colors[piece.colorIndex].copy(alpha = alpha))
    }
    if (dragged != null) {
        val (cx, cy) = d.center(dragged)
        val ox = cx - (dragged.width * PITCH - GAP) / 2; val oy = cy - (dragged.height * PITCH - GAP) / 2
        for ((r, c) in dragged.cells) {
            box(ox + c * PITCH + 1, oy + r * PITCH + 4, CELL, CELL, Color.Black.copy(alpha = 0.25f), 4f)
            blastCell(ox + c * PITCH, oy + r * PITCH, CELL, BlockBlastEngine.colors[dragged.colorIndex])
        }
    }
}
