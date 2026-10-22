package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
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
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.max

enum class SudokuDifficulty(val titleKey: String, val size: Int, val clues: Int, val bonus: Int) {
    Easy("Easy", 6, 14, 200), Medium("Medium", 9, 34, 500), Hard("Hard", 9, 27, 900)
}

class SudokuEngine : GameEngine {
    companion object {
        const val MAX_MISTAKES = 3
        const val HINT_COUNT = 3
        private const val KEY = "sudokuDifficulty"
    }

    var difficulty by mutableStateOf(SudokuDifficulty.entries.getOrElse(Settings.prefs.getInt(KEY, 0)) { SudokuDifficulty.Easy })
        private set
    var version by mutableIntStateOf(0)
    var solution = Array(0) { IntArray(0) }
    var given = Array(0) { BooleanArray(0) }
    /** 0 = empty. */
    var board = Array(0) { IntArray(0) }
    var notes = Array(0) { Array(0) { mutableSetOf<Int>() } }
    var mistakes by mutableIntStateOf(0)
    var hintsLeft by mutableIntStateOf(HINT_COUNT)
    var notesMode by mutableStateOf(false)
    var selR by mutableIntStateOf(-1)
    var selC by mutableIntStateOf(-1)
    override var state: GameState by mutableStateOf(GameState.Playing)

    val size get() = difficulty.size
    val blockRows get() = if (size == 6) 2 else 3
    val blockCols get() = 3

    override val score: Int
        get() {
            version
            if (board.isEmpty()) return 0
            var s = 0
            for (r in 0 until size) for (c in 0 until size) if (!given[r][c] && board[r][c] == solution[r][c]) s += 10
            if ((state as? GameState.GameOver)?.won == true) s += difficulty.bonus + hintsLeft * 50
            return max(0, s - mistakes * 20)
        }

    init { newPuzzle() }

    override fun restart() { newPuzzle(); state = GameState.Playing }

    fun chooseDifficulty(v: SudokuDifficulty) {
        if (v == difficulty) return
        difficulty = v; Settings.prefs.edit().putInt(KEY, v.ordinal).apply(); restart()
    }

    private fun newPuzzle() {
        val n = size
        val (sol, giv) = generatePuzzle(n, blockRows, difficulty.clues)
        solution = sol; given = giv
        board = Array(n) { r -> IntArray(n) { c -> if (giv[r][c]) sol[r][c] else 0 } }
        notes = Array(n) { Array(n) { mutableSetOf<Int>() } }
        mistakes = 0; hintsLeft = HINT_COUNT; selR = -1; selC = -1; notesMode = false
        version++
    }

    /** Fills a random complete grid, then removes clues while the solution stays unique. */
    private fun generatePuzzle(n: Int, br: Int, clues: Int): Pair<Array<IntArray>, Array<BooleanArray>> {
        val grid = IntArray(n * n)
        solve(grid, n, br, randomize = true, limit = 1)
        val sol = Array(n) { r -> IntArray(n) { c -> grid[r * n + c] } }
        val puzzle = grid.copyOf()
        var remaining = n * n
        for (cell in (0 until n * n).shuffled()) {
            if (remaining <= clues) break
            val saved = puzzle[cell]
            puzzle[cell] = 0
            if (solve(puzzle.copyOf(), n, br, randomize = false, limit = 2) == 1) remaining-- else puzzle[cell] = saved
        }
        return sol to Array(n) { r -> BooleanArray(n) { c -> puzzle[r * n + c] != 0 } }
    }

    /** Backtracking with bitmasks; returns the number of solutions found (up to [limit]). */
    private fun solve(grid: IntArray, n: Int, br: Int, randomize: Boolean, limit: Int): Int {
        val bc = 3
        val rows = IntArray(n); val cols = IntArray(n); val boxes = IntArray(n)
        fun box(r: Int, c: Int) = (r / br) * (n / bc) + c / bc
        for (i in grid.indices) if (grid[i] != 0) { val bit = 1 shl grid[i]; rows[i / n] = rows[i / n] or bit; cols[i % n] = cols[i % n] or bit; boxes[box(i / n, i % n)] = boxes[box(i / n, i % n)] or bit }
        var found = 0
        var first: IntArray? = null
        fun search() {
            // Most constrained empty cell first.
            var best = -1; var bestCount = Int.MAX_VALUE; var bestMask = 0
            for (i in grid.indices) if (grid[i] == 0) {
                val r = i / n; val c = i % n
                val used = rows[r] or cols[c] or boxes[box(r, c)]
                var count = 0
                for (d in 1..n) if (used and (1 shl d) == 0) count++
                if (count < bestCount) { best = i; bestCount = count; bestMask = used; if (count <= 1) break }
            }
            if (best < 0) { found++; if (first == null) first = grid.copyOf(); return }
            if (bestCount == 0) return
            val r = best / n; val c = best % n; val b = box(r, c)
            val digits = (1..n).filter { bestMask and (1 shl it) == 0 }.let { if (randomize) it.shuffled() else it }
            for (d in digits) {
                val bit = 1 shl d
                grid[best] = d; rows[r] = rows[r] or bit; cols[c] = cols[c] or bit; boxes[b] = boxes[b] or bit
                search()
                grid[best] = 0; rows[r] = rows[r] and bit.inv(); cols[c] = cols[c] and bit.inv(); boxes[b] = boxes[b] and bit.inv()
                if (found >= limit) return
            }
        }
        search()
        first?.let { it.copyInto(grid) }
        return found
    }

    /** Cells whose value duplicates another in its row, column or block. */
    fun conflicts(): Set<Int> {
        version
        val n = size; val out = HashSet<Int>()
        fun check(cells: List<Int>) {
            val seen = HashMap<Int, MutableList<Int>>()
            for (p in cells) { val v = board[p / n][p % n]; if (v != 0) seen.getOrPut(v) { ArrayList() }.add(p) }
            for ((_, list) in seen) if (list.size > 1) out.addAll(list)
        }
        for (r in 0 until n) check((0 until n).map { r * n + it })
        for (c in 0 until n) check((0 until n).map { it * n + c })
        for (brk in 0 until n / blockRows) for (bck in 0 until n / blockCols)
            check((0 until blockRows).flatMap { r -> (0 until blockCols).map { c -> (brk * blockRows + r) * n + bck * blockCols + c } })
        return out
    }

    /** How many more of each digit are still needed on the board. */
    fun remaining(d: Int): Int { version; return size - board.sumOf { row -> row.count { it == d } } }

    fun select(r: Int, c: Int) {
        if (state != GameState.Playing) return
        if (selR == r && selC == c) { selR = -1; selC = -1 } else { selR = r; selC = c }
        Haptics.tap(); Sfx.tap()
    }

    /** Enters a digit (or erases with null) in the selected cell. */
    fun enter(value: Int?) {
        if (state != GameState.Playing || selR < 0 || given[selR][selC]) return
        val r = selR; val c = selC
        if (value == null) { board[r][c] = 0; notes[r][c].clear(); Haptics.tap(); Sfx.tap(); version++; return }
        if (notesMode) {
            if (board[r][c] != 0) return
            if (!notes[r][c].add(value)) notes[r][c].remove(value)
            Haptics.tap(); Sfx.tap(); version++; return
        }
        if (board[r][c] == value) return
        board[r][c] = value
        if (value == solution[r][c]) {
            notes[r][c].clear(); clearNotes(value, r, c)
            Haptics.move(); Sfx.tap()
        } else {
            mistakes++
            Haptics.error(); Sfx.wrong()
            if (mistakes >= MAX_MISTAKES) { state = GameState.GameOver(won = false); version++; return }
        }
        version++
        checkCompletion()
    }

    /** Fills the selected empty cell (or a random one) with its correct digit. */
    fun hint() {
        if (state != GameState.Playing || hintsLeft <= 0) return
        val empties = (0 until size).flatMap { r -> (0 until size).map { r to it } }.filter { (r, c) -> board[r][c] != solution[r][c] }
        val target = (if (selR >= 0 && (selR to selC) in empties) selR to selC else empties.randomOrNull()) ?: return
        hintsLeft--
        board[target.first][target.second] = solution[target.first][target.second]
        notes[target.first][target.second].clear()
        clearNotes(solution[target.first][target.second], target.first, target.second)
        selR = target.first; selC = target.second
        Haptics.move(); Sfx.point()
        version++
        checkCompletion()
    }

    private fun clearNotes(value: Int, pr: Int, pc: Int) {
        for (r in 0 until size) for (c in 0 until size) {
            val sameBox = r / blockRows == pr / blockRows && c / blockCols == pc / blockCols
            if (r == pr || c == pc || sameBox) notes[r][c].remove(value)
        }
    }

    private fun checkCompletion() {
        for (r in 0 until size) for (c in 0 until size) if (board[r][c] != solution[r][c]) return
        state = GameState.GameOver(won = true)
    }
}

@Composable
fun SudokuScreen(onExit: () -> Unit) {
    val engine = remember { SudokuEngine() }
    val pal = Pal.current
    GameContainer(GameId.Sudoku, engine, onExit, summary = { L10n.t(engine.difficulty.titleKey) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(pal.surface)) {
                SudokuDifficulty.entries.forEach { d ->
                    Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (engine.difficulty == d) pal.accent else Color.Transparent)
                        .clickable { engine.chooseDifficulty(d) }.padding(vertical = 9.dp), contentAlignment = Alignment.Center) {
                        Text(L10n.t(d.titleKey), color = if (engine.difficulty == d) pal.onAccent else pal.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                }
            }
            Text("⚠ " + L10n.f("Mistakes: %d/%d", engine.mistakes, SudokuEngine.MAX_MISTAKES), color = if (engine.mistakes > 0) Color.Red else pal.textSecondary,
                fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp))
            SudokuBoard(engine)
            Spacer16()
            NumberPad(engine)
        }
    }
}

@Composable
private fun Spacer16() = androidx.compose.foundation.layout.Spacer(Modifier.height(16.dp))

@Composable
private fun SudokuBoard(e: SudokuEngine) {
    val pal = Pal.current
    val n = e.size
    val conflicts = e.conflicts()
    e.version
    Column(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(10.dp)).background(pal.stroke.copy(alpha = 0.35f))
        .drawWithContent {
            drawContent()
            // Thick separators outlining the blocks.
            val w = size.width; val h = size.height
            var k = e.blockCols
            while (k < n) { drawLine(pal.text.copy(alpha = 0.6f), Offset(w * k / n, 0f), Offset(w * k / n, h), 2.dp.toPx()); k += e.blockCols }
            k = e.blockRows
            while (k < n) { drawLine(pal.text.copy(alpha = 0.6f), Offset(0f, h * k / n), Offset(w, h * k / n), 2.dp.toPx()); k += e.blockRows }
        }.border(2.dp, pal.text.copy(alpha = 0.6f), RoundedCornerShape(10.dp)), verticalArrangement = Arrangement.spacedBy(1.dp)) {
        for (r in 0 until n) Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
            for (c in 0 until n) {
                val value = e.board[r][c]; val given = e.given[r][c]
                val isSel = e.selR == r && e.selC == c
                val wrong = !given && value != 0 && ((r * n + c) in conflicts || value != e.solution[r][c])
                val sameBox = e.selR >= 0 && r / e.blockRows == e.selR / e.blockRows && c / e.blockCols == e.selC / e.blockCols
                val sameUnit = e.selR >= 0 && !isSel && (r == e.selR || c == e.selC || sameBox)
                val selVal = if (e.selR >= 0) e.board[e.selR][e.selC] else 0
                val sameValue = value != 0 && value == selVal && !isSel
                val bg = when { isSel -> pal.accent.copy(alpha = 0.30f); wrong -> Color.Red.copy(alpha = 0.18f); sameValue -> pal.accent.copy(alpha = 0.2f); sameUnit -> pal.accent.copy(alpha = 0.07f); else -> pal.surface }
                Box(Modifier.weight(1f).fillMaxSize().background(bg).clickable(remember { MutableInteractionSource() }, null) { e.select(r, c) }, contentAlignment = Alignment.Center) {
                    if (value != 0) Text("$value", color = if (wrong) Color.Red else if (given) pal.text else pal.accent, fontSize = if (n == 9) 20.sp else 24.sp, fontWeight = if (given) FontWeight.Bold else FontWeight.Medium)
                    else if (e.notes[r][c].isNotEmpty()) Column(Modifier.fillMaxSize().padding(1.dp)) {
                        for (row in 0 until n / 3) Row(Modifier.weight(1f)) {
                            for (col in 1..3) { val d = row * 3 + col; Text(if (d in e.notes[r][c]) "$d" else " ", color = pal.textSecondary, fontSize = if (n == 9) 8.sp else 10.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f)) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun NumberPad(e: SudokuEngine) {
    val pal = Pal.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(if (e.size == 9) 5.dp else 10.dp)) {
        for (d in 1..e.size) {
            val left = e.remaining(d)
            Column(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(12.dp)).background(pal.accent.copy(alpha = if (e.notesMode) 0.05f else 0.12f))
                .border(1.dp, pal.accent.copy(alpha = if (e.notesMode) 0.6f else 0.3f), RoundedCornerShape(12.dp))
                .clickable(enabled = left > 0) { e.enter(d) }.padding(top = 4.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("$d", color = pal.accent.copy(alpha = if (left <= 0) 0.3f else 1f), fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text("${max(0, left)}", color = pal.accent.copy(alpha = 0.6f), fontSize = 11.sp)
            }
        }
    }
    Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ToolButton("🧽 " + L10n.t("Erase"), false, true) { e.enter(null) }
        ToolButton("✏️ " + L10n.t("Notes"), e.notesMode, true) { e.notesMode = !e.notesMode; Haptics.tap() }
        ToolButton("💡 " + L10n.f("Hint (%d)", e.hintsLeft), false, e.hintsLeft > 0) { e.hint() }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ToolButton(text: String, active: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val pal = Pal.current
    Box(Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(12.dp)).background(if (active) pal.accent else pal.surfaceHigh).clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(text, color = if (active) pal.onAccent else pal.text.copy(alpha = if (enabled) 1f else 0.4f), fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
    }
}
