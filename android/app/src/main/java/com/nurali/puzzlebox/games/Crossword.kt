package com.nurali.puzzlebox.games

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.AppLanguage
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.ui.Pal
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min

data class CrosswordCell(val row: Int, val col: Int)

class CrosswordClue(val id: Int, val number: Int, val answer: List<Char>, val clue: String, val start: CrosswordCell, val across: Boolean) {
    val cells: List<CrosswordCell> get() = answer.indices.map { if (across) CrosswordCell(start.row, start.col + it) else CrosswordCell(start.row + it, start.col) }
}

enum class CrosswordLang(val code: String, val rows: List<String>) {
    English("en", listOf("QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM")),
    Russian("ru", listOf("ЙЦУКЕНГШЩЗХЪ", "ФЫВАПРОЛДЖЭ", "ЯЧСМИТЬБЮ")),
    Kazakh("kk", listOf("ӘІҢҒҮҰҚӨҺ", "ЙЦУКЕНГШЩЗХ", "ФЫВАПРОЛДЖЭ", "ЯЧСМИТЬБЮ"));

    companion object {
        /** Russian and Kazakh players get native puzzles; other languages use English. */
        fun current() = when (L10n.language) { AppLanguage.Russian -> Russian; AppLanguage.Kazakh -> Kazakh; else -> English }
    }
}

object CrosswordGenerator {
    const val MAX_SIDE = 11
    private class Placed(val word: List<Char>, val clue: String, val row: Int, val col: Int, val across: Boolean)
    class Puzzle(val rows: Int, val cols: Int, val clues: List<CrosswordClue>)

    fun make(level: Int, lang: CrosswordLang, entries: List<Pair<String, String>>): Puzzle {
        val random = PuzzleRandom(level * 2654435761L + lang.code.fold(0L) { a, c -> a * 31 + c.code })
        val target = min(11, 6 + level / 6)
        var best: List<Placed> = emptyList()
        repeat(20) {
            val placed = attempt(entries.shuffled(random), target, random)
            if (placed.size > best.size) best = placed
            if (best.size >= target) return@repeat
        }
        val minRow = best.minOfOrNull { it.row } ?: 0; val minCol = best.minOfOrNull { it.col } ?: 0
        val maxRow = best.maxOfOrNull { it.row + if (it.across) 0 else it.word.size - 1 } ?: 0
        val maxCol = best.maxOfOrNull { it.col + if (it.across) it.word.size - 1 else 0 } ?: 0
        val starts = best.map { CrosswordCell(it.row - minRow, it.col - minCol) }.toSet()
        val numbers = HashMap<CrosswordCell, Int>(); var next = 1
        for (r in 0..(maxRow - minRow)) for (c in 0..(maxCol - minCol)) {
            val cell = CrosswordCell(r, c); if (cell in starts) numbers[cell] = next++
        }
        val clues = best.mapIndexed { i, p ->
            val start = CrosswordCell(p.row - minRow, p.col - minCol)
            CrosswordClue(i, numbers[start] ?: 0, p.word, p.clue, start, p.across)
        }.sortedWith(compareBy({ if (it.across) 0 else 1 }, { it.number }))
        return Puzzle(maxRow - minRow + 1, maxCol - minCol + 1, clues)
    }

    private fun attempt(pool: List<Pair<String, String>>, target: Int, random: PuzzleRandom): List<Placed> {
        val grid = HashMap<CrosswordCell, Char>()
        val placed = ArrayList<Placed>()
        val sorted = pool.sortedByDescending { it.first.length }
        val first = sorted.firstOrNull() ?: return emptyList()
        val remaining = sorted.drop(1).shuffled(random)
        val firstWord = first.first.toList()
        firstWord.forEachIndexed { i, ch -> grid[CrosswordCell(0, i)] = ch }
        placed.add(Placed(firstWord, first.second, 0, 0, true))
        for (entry in remaining) {
            if (placed.size >= target) break
            val word = entry.first.toList()
            data class Option(val row: Int, val col: Int, val across: Boolean, val crossings: Int)
            val options = ArrayList<Option>()
            // Sorted so a level is identical on every launch.
            for ((cell, letter) in grid.entries.sortedWith(compareBy({ it.key.row }, { it.key.col }))) {
                for ((i, ch) in word.withIndex()) if (ch == letter) for (across in listOf(true, false)) {
                    val row = if (across) cell.row else cell.row - i
                    val col = if (across) cell.col - i else cell.col
                    fits(word, row, col, across, grid)?.let { options.add(Option(row, col, across, it)) }
                }
            }
            val top = options.maxOfOrNull { it.crossings } ?: continue
            val choices = options.filter { it.crossings == top }
            val pick = choices[random.nextInt(choices.size)]
            word.forEachIndexed { i, ch -> grid[if (pick.across) CrosswordCell(pick.row, pick.col + i) else CrosswordCell(pick.row + i, pick.col)] = ch }
            placed.add(Placed(word, entry.second, pick.row, pick.col, pick.across))
        }
        return placed
    }

    private fun fits(word: List<Char>, row: Int, col: Int, across: Boolean, grid: Map<CrosswordCell, Char>): Int? {
        val dr = if (across) 0 else 1; val dc = if (across) 1 else 0
        fun at(r: Int, c: Int) = grid[CrosswordCell(r, c)]
        if (at(row - dr, col - dc) != null || at(row + dr * word.size, col + dc * word.size) != null) return null
        var crossings = 0
        for ((i, ch) in word.withIndex()) {
            val r = row + dr * i; val c = col + dc * i
            val existing = at(r, c)
            if (existing != null) { if (existing != ch) return null; crossings++ }
            else if (at(r + dc, c + dr) != null || at(r - dc, c - dr) != null) return null
        }
        if (crossings == 0 || crossings >= word.size) return null
        val rs = grid.keys.map { it.row } + word.indices.map { row + dr * it }
        val cs = grid.keys.map { it.col } + word.indices.map { col + dc * it }
        if (rs.max() - rs.min() + 1 > MAX_SIDE || cs.max() - cs.min() + 1 > MAX_SIDE) return null
        return crossings
    }
}

class CrosswordEngine(context: Context) : GameEngine {
    companion object { const val LEVEL_COUNT = 60; const val HINTS = 3 }

    val lang = CrosswordLang.current()
    private val entries: List<Pair<String, String>> = runCatching {
        val o = JSONObject(context.assets.open("crossword.json").bufferedReader().use { it.readText() })
        val a = o.getJSONArray(lang.code)
        (0 until a.length()).map { a.getJSONArray(it).let { p -> p.getString(0) to p.getString(1) } }
    }.getOrDefault(emptyList())

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var level by mutableIntStateOf(1)
    var rows by mutableIntStateOf(1); var cols by mutableIntStateOf(1)
    var clues: List<CrosswordClue> by mutableStateOf(emptyList())
    var solution: Map<CrosswordCell, Char> by mutableStateOf(emptyMap())
    var letters: Map<CrosswordCell, Char> by mutableStateOf(emptyMap())
    var solved: Set<Int> by mutableStateOf(emptySet())
    var selected: CrosswordCell? by mutableStateOf(null)
    var across by mutableStateOf(true)
    var hintsLeft by mutableIntStateOf(HINTS)
    var mistakes = 0
    var wrongClue: Int? by mutableStateOf(null)

    private val levelKey get() = "crosswordLevel." + lang.code
    val hasNextLevel get() = level < LEVEL_COUNT

    init { level = Settings.prefs.getInt(levelKey, 1).coerceIn(1, LEVEL_COUNT); restart() }

    override fun restart() {
        val p = CrosswordGenerator.make(level, lang, entries)
        rows = p.rows; cols = p.cols; clues = p.clues
        val sol = HashMap<CrosswordCell, Char>()
        for (c in clues) c.cells.zip(c.answer).forEach { (cell, ch) -> sol[cell] = ch }
        solution = sol
        letters = emptyMap(); solved = emptySet(); hintsLeft = HINTS; mistakes = 0; wrongClue = null; score = 0
        across = clues.firstOrNull()?.across ?: true
        selected = clues.firstOrNull()?.start
        state = GameState.Playing
    }

    fun selectLevel(v: Int) { if (v !in 1..LEVEL_COUNT) return; level = v; Settings.prefs.edit().putInt(levelKey, v).apply(); restart() }
    fun nextLevel() = selectLevel(level + 1)

    val activeClue: CrosswordClue?
        get() { val s = selected ?: return null; return clues.firstOrNull { it.across == across && s in it.cells } ?: clues.firstOrNull { s in it.cells } }

    fun isLocked(cell: CrosswordCell) = clues.any { it.id in solved && cell in it.cells }

    fun tap(cell: CrosswordCell) {
        if (state != GameState.Playing || cell !in solution) return
        if (selected == cell) { if (clues.any { it.across != across && cell in it.cells }) across = !across }
        else { selected = cell; if (clues.none { it.across == across && cell in it.cells }) across = !across }
        Haptics.tap(); Sfx.tap()
    }

    fun select(clue: CrosswordClue) {
        across = clue.across
        selected = clue.cells.firstOrNull { letters[it] == null } ?: clue.start
        Sfx.tap()
    }

    fun stepClue(delta: Int) {
        val current = activeClue ?: return
        val index = clues.indexOfFirst { it.id == current.id }.takeIf { it >= 0 } ?: return
        val open = clues.indices.map { ((index + delta * (it + 1)) % clues.size + clues.size) % clues.size }.firstOrNull { clues[it].id !in solved }
        if (open != null) select(clues[open])
    }

    fun type(letter: Char) {
        if (state != GameState.Playing) return
        val cell = selected ?: return; val clue = activeClue ?: return
        if (!isLocked(cell)) letters = letters + (cell to letter)
        Sfx.tap()
        evaluate(clue)
        val cells = clue.cells
        val i = cells.indexOf(cell)
        if (i >= 0) selected = cells.drop(i + 1).firstOrNull { !isLocked(it) && letters[it] == null } ?: cells[min(i + 1, cells.size - 1)]
        if (clue.id in solved) stepClue(1)
    }

    fun backspace() {
        if (state != GameState.Playing) return
        val cell = selected ?: return; val clue = activeClue ?: return
        if (letters[cell] != null && !isLocked(cell)) letters = letters - cell
        else {
            val i = clue.cells.indexOf(cell)
            if (i > 0) { val prev = clue.cells[i - 1]; selected = prev; if (!isLocked(prev)) letters = letters - prev }
        }
        Sfx.tap()
    }

    fun hint() {
        if (state != GameState.Playing || hintsLeft <= 0) return
        val target = selected?.takeIf { letters[it] != solution[it] && !isLocked(it) } ?: activeClue?.cells?.firstOrNull { letters[it] != solution[it] }
        val answer = target?.let { solution[it] } ?: return
        hintsLeft--
        letters = letters + (target to answer)
        Haptics.move(); Sfx.point()
        for (c in clues) if (target in c.cells) evaluate(c)
    }

    private fun evaluate(clue: CrosswordClue) {
        if (clue.id in solved) return
        val entered = clue.cells.map { letters[it] }
        if (entered.any { it == null }) return
        if (entered.filterNotNull() == clue.answer) {
            solved = solved + clue.id
            score += 20 + clue.answer.size * 5
            Haptics.success(); Sfx.win()
            for (o in clues) if (o.id != clue.id && o.id !in solved && o.cells.any { it in clue.cells }) evaluate(o)
            if (solved.size == clues.size) {
                score += 200 + level * 20 + hintsLeft * 50 + max(0, 100 - mistakes * 20)
                Settings.prefs.edit().putInt(levelKey, min(LEVEL_COUNT, level + 1)).apply()
                state = GameState.GameOver(won = true)
            }
        } else { mistakes++; wrongClue = clue.id; Haptics.error(); Sfx.wrong() }
    }
}

@Composable
fun CrosswordScreen(onExit: () -> Unit) {
    val context = LocalContext.current
    val engine = remember { CrosswordEngine(context.applicationContext) }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(GameId.Crossword, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.level) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box {
                    Text("▦ " + L10n.f("Level %d", engine.level), color = pal.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                        for (lv in 1..CrosswordEngine.LEVEL_COUNT) DropdownMenuItem(text = { Text(L10n.f("Level %d", lv)) }, onClick = { menu = false; engine.selectLevel(lv) })
                    }
                }
                Text("${engine.solved.size}/${engine.clues.size}", color = pal.textSecondary, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.weight(1f))
                Text("💡 " + L10n.f("Hint (%d)", engine.hintsLeft), color = if (engine.hintsLeft > 0) pal.accent else pal.textSecondary, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surfaceHigh).clickable(enabled = engine.hintsLeft > 0) { engine.hint() }.padding(horizontal = 12.dp, vertical = 6.dp))
            }
            Board(engine, Modifier.fillMaxWidth().heightIn(max = 360.dp).aspectRatio(engine.cols / max(1f, engine.rows.toFloat())).align(Alignment.CenterHorizontally))
            ClueBar(engine)
            Keyboard(engine)
        }
    }
}

@Composable
private fun Board(engine: CrosswordEngine, modifier: Modifier) {
    val pal = Pal.current
    val active = engine.activeClue?.cells?.toSet() ?: emptySet()
    val numbers = engine.clues.associate { it.start to it.number }
    val wrong = engine.wrongClue?.let { id -> engine.clues.firstOrNull { it.id == id } }?.cells?.toSet() ?: emptySet()
    Column(modifier) {
        for (r in 0 until engine.rows) Row(Modifier.weight(1f).fillMaxWidth()) {
            for (c in 0 until engine.cols) {
                val pos = CrosswordCell(r, c)
                Box(Modifier.weight(1f).fillMaxSize().padding(1.dp)) {
                    if (pos in engine.solution) {
                        val locked = engine.isLocked(pos); val sel = engine.selected == pos
                        val fill = when { sel -> pal.accent; locked -> Color(0xFF34C759).copy(alpha = 0.28f); pos in active -> pal.accent.copy(alpha = 0.22f); else -> pal.surface }
                        val edge = if (locked) Color(0xFF34C759).copy(alpha = 0.7f) else if (pos in wrong && engine.letters[pos] != null) Color.Red else pal.stroke
                        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(5.dp)).background(fill).border(1.dp, edge, RoundedCornerShape(5.dp)).clickable { engine.tap(pos) }) {
                            numbers[pos]?.let { Text("$it", fontSize = 8.sp, fontWeight = FontWeight.Bold, color = if (sel) Color.White.copy(alpha = 0.85f) else pal.textSecondary, modifier = Modifier.padding(start = 2.dp, top = 1.dp)) }
                            engine.letters[pos]?.let {
                                Text(it.toString(), fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                                    color = if (sel) Color.White else if (locked) Color(0xFF34C759) else pal.text, modifier = Modifier.align(Alignment.Center))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ClueBar(engine: CrosswordEngine) {
    val pal = Pal.current
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(pal.surface), verticalAlignment = Alignment.CenterVertically) {
        Text("‹", fontSize = 26.sp, color = pal.accent, textAlign = TextAlign.Center, modifier = Modifier.size(44.dp, 52.dp).clickable { engine.stepClue(-1) }.padding(top = 8.dp))
        Column(Modifier.weight(1f)) {
            engine.activeClue?.let {
                Text("${it.number} ${if (it.across) "→" else "↓"} · ${it.answer.size}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = pal.accent)
                Text(it.clue, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = pal.text, maxLines = 2)
            }
        }
        Text("›", fontSize = 26.sp, color = pal.accent, textAlign = TextAlign.Center, modifier = Modifier.size(44.dp, 52.dp).clickable { engine.stepClue(1) }.padding(top = 8.dp))
    }
}

@Composable
private fun Keyboard(engine: CrosswordEngine) {
    val pal = Pal.current
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        engine.lang.rows.forEachIndexed { index, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (letter in row) Box(Modifier.weight(1f).heightIn(min = 40.dp).clip(RoundedCornerShape(7.dp)).background(pal.surfaceHigh).clickable { engine.type(letter) }.padding(vertical = 9.dp),
                    contentAlignment = Alignment.Center) { Text(letter.toString(), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = pal.text) }
                if (index == engine.lang.rows.size - 1) Box(Modifier.weight(1f).heightIn(min = 40.dp).clip(RoundedCornerShape(7.dp)).background(pal.accent.copy(alpha = 0.18f)).clickable { engine.backspace() },
                    contentAlignment = Alignment.Center) { Text("⌫", fontSize = 17.sp, color = pal.text) }
            }
        }
    }
}
