package com.nurali.puzzlebox.games

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
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
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.max
import kotlin.math.min

class WaterSortEngine : GameEngine {
    companion object {
        const val CAPACITY = 4
        const val EMPTY_TUBES = 2
        const val LEVEL_COUNT = 60
        private const val LEVEL_KEY = "waterSortLevel"

        private fun solved(t: List<List<Int>>) = t.all { it.isEmpty() || (it.size == CAPACITY && it.toSet().size == 1) }

        /** Depth-first search over pours with a visited set and a node budget. */
        fun isSolvable(start: List<List<Int>>, budget: Int = 40_000): Boolean {
            val seen = HashSet<String>()
            val stack = ArrayList<List<List<Int>>>().apply { add(start) }
            while (stack.isNotEmpty()) {
                val tubes = stack.removeAt(stack.lastIndex)
                if (solved(tubes)) return true
                if (!seen.add(tubes.map { it.joinToString(",") }.sorted().joinToString("|"))) continue
                if (seen.size > budget) return false
                for (from in tubes.indices) {
                    val fromTube = tubes[from]
                    val color = fromTube.lastOrNull() ?: continue
                    if (fromTube.size == CAPACITY && fromTube.toSet().size == 1) continue
                    val run = fromTube.reversed().takeWhile { it == color }.size
                    var triedEmpty = false
                    for (to in tubes.indices) {
                        if (to == from) continue
                        val target = tubes[to]
                        val free = CAPACITY - target.size
                        if (free <= 0 || !(target.isEmpty() || target.last() == color)) continue
                        if (target.isEmpty()) {
                            // Pouring a single-colour tube into an empty one changes nothing.
                            if (run == fromTube.size || triedEmpty) continue
                            triedEmpty = true
                        }
                        val amount = min(run, free)
                        val next = tubes.toMutableList()
                        next[from] = fromTube.dropLast(amount)
                        next[to] = target + List(amount) { color }
                        stack.add(next)
                    }
                }
            }
            return false
        }

        /** Deterministic per level, and checked by a solver so every deal can be finished. */
        fun generate(level: Int, colors: Int): List<List<Int>> {
            val random = PuzzleRandom(level * 104729L + 17)
            while (true) {
                val pool = ArrayList<Int>()
                for (c in 0 until colors) repeat(CAPACITY) { pool.add(c) }
                pool.shuffle(random)
                val deal = (0 until colors).map { i -> pool.subList(i * CAPACITY, (i + 1) * CAPACITY).toList() }.toMutableList()
                if (deal.any { it.toSet().size == 1 }) continue
                repeat(EMPTY_TUBES) { deal.add(emptyList()) }
                if (isSolvable(deal)) return deal
            }
        }
    }

    /** Each tube stores colour indices bottom-to-top. */
    var tubes by mutableStateOf(listOf<List<Int>>())
    var moves by mutableIntStateOf(0)
    var level by mutableIntStateOf(1)
    var extraTubeUsed by mutableStateOf(false)
    var selected by mutableStateOf<Int?>(null)
    override var state: GameState by mutableStateOf(GameState.Playing)
    private val history = ArrayList<List<List<Int>>>()
    var historySize by mutableIntStateOf(0)

    val colorCount get() = min(10, 3 + (level - 1) / 3)
    val hasNextLevel get() = level < LEVEL_COUNT
    val canUndo get() = historySize > 0
    private val isWon get() = solved(tubes)
    val completedTubes get() = tubes.count { it.size == CAPACITY && it.toSet().size == 1 }

    override val score get() = completedTubes * 20 + if (isWon) 100 + level * 30 + max(0, 150 - moves * 2) else 0

    init {
        level = Settings.prefs.getInt(LEVEL_KEY, 1).coerceIn(1, LEVEL_COUNT)
        tubes = generate(level, colorCount)
    }

    override fun restart() {
        tubes = generate(level, colorCount)
        moves = 0; history.clear(); historySize = 0; selected = null; extraTubeUsed = false; state = GameState.Playing
    }

    fun selectLevel(v: Int) {
        if (v !in 1..LEVEL_COUNT) return
        level = v; Settings.prefs.edit().putInt(LEVEL_KEY, v).apply(); restart()
    }

    fun nextLevel() = selectLevel(level + 1)

    /** One spare empty tube per level, for when you get stuck. */
    fun addTube() {
        if (state != GameState.Playing || extraTubeUsed) return
        extraTubeUsed = true
        history.add(tubes); historySize = history.size
        tubes = tubes + listOf(emptyList())
        Haptics.move(); Sfx.tap()
    }

    fun tap(index: Int) {
        if (state != GameState.Playing || index !in tubes.indices) return
        val source = selected
        if (source == null) {
            if (tubes[index].isNotEmpty()) { selected = index; Haptics.tap(); Sfx.tap() }
            return
        }
        if (source == index) { selected = null; return }
        if (pour(source, index)) selected = null
        else { selected = if (tubes[index].isEmpty()) null else index; Haptics.tap(); Sfx.tap() }
    }

    /** Pours the top same-colour run of [from] into [to] when allowed. */
    private fun pour(from: Int, to: Int): Boolean {
        val color = tubes[from].lastOrNull() ?: return false
        val free = CAPACITY - tubes[to].size
        if (free <= 0 || !(tubes[to].isEmpty() || tubes[to].last() == color)) return false
        val run = tubes[from].reversed().takeWhile { it == color }.size
        val amount = min(run, free)
        history.add(tubes); historySize = history.size
        tubes = tubes.mapIndexed { i, t -> when (i) { from -> t.dropLast(amount); to -> t + List(amount) { color }; else -> t } }
        moves++
        val filled = tubes[to].size == CAPACITY && tubes[to].toSet().size == 1
        if (filled) { Haptics.success(); Sfx.win() } else { Haptics.move(); Sfx.tap() }
        if (isWon) state = GameState.GameOver(won = true) else if (isStuck) state = GameState.GameOver(won = false)
        return true
    }

    fun undo() {
        if (state != GameState.Playing || history.isEmpty()) return
        tubes = history.removeAt(history.lastIndex); historySize = history.size
        selected = null; Haptics.tap(); Sfx.tap()
    }

    /** True when no legal pour exists anywhere. */
    private val isStuck: Boolean
        get() {
            for (from in tubes.indices) {
                val color = tubes[from].lastOrNull() ?: continue
                for (to in tubes.indices) if (to != from) {
                    val free = CAPACITY - tubes[to].size
                    if (free > 0 && (tubes[to].isEmpty() || tubes[to].last() == color)) return false
                }
            }
            return true
        }
}

private val WaterPalette = listOf(Color(0xFFFF3B30), Color(0xFF007AFF), Color(0xFF34C759), Color(0xFFFFCC00), Color(0xFFAF52DE),
    Color(0xFF32ADE6), Color(0xFFFF9500), Color(0xFFFF2D55), Color(0xFF00C7BE), Color(0xFF8C5933))

@Composable
fun WaterSortScreen(onExit: () -> Unit) {
    val engine = remember { WaterSortEngine() }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(GameId.WaterSort, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.level) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box {
                    Text("🧪 " + L10n.f("Level %d", engine.level), color = pal.text, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                        for (lv in 1..WaterSortEngine.LEVEL_COUNT) DropdownMenuItem(text = { Text(L10n.f("Level %d", lv)) }, onClick = { menu = false; engine.selectLevel(lv) })
                    }
                }
                Text("⇄ " + L10n.f("%d moves", engine.moves), color = pal.accent, fontWeight = FontWeight.SemiBold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text("+", color = if (engine.extraTubeUsed) pal.textSecondary else pal.accent, fontWeight = FontWeight.Bold, fontSize = 18.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surface).clickable(enabled = !engine.extraTubeUsed) { engine.addTube() }.padding(horizontal = 14.dp, vertical = 6.dp))
                Text("↩", color = if (engine.canUndo) pal.accent else pal.textSecondary, fontWeight = FontWeight.Bold, fontSize = 18.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surface).clickable(enabled = engine.canUndo) { engine.undo() }.padding(horizontal = 14.dp, vertical = 6.dp))
            }
            val tubeCount = engine.tubes.size
            val perRow = (tubeCount + 1) / 2
            // Tubes narrow as the level adds colours, so two rows always fit.
            val width = min(58f, (340f - 10 * (perRow - 1)) / perRow).dp
            Column(verticalArrangement = Arrangement.spacedBy(28.dp)) {
                for (row in 0 until 2) Row(horizontalArrangement = Arrangement.spacedBy(if (perRow > 5) 10.dp else 18.dp), modifier = Modifier.align(Alignment.CenterHorizontally)) {
                    for (col in 0 until perRow) {
                        val index = row * perRow + col
                        if (index < tubeCount) Tube(engine, index, width)
                    }
                }
            }
            Text(L10n.t("Tap a tube to pick it up, then tap another to pour."), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 24.dp))
        }
    }
}

@Composable
private fun Tube(engine: WaterSortEngine, index: Int, width: androidx.compose.ui.unit.Dp) {
    val pal = Pal.current
    val contents = engine.tubes[index]
    val sel = engine.selected == index
    val lift by animateDpAsState(if (sel) (-14).dp else 0.dp, label = "lift")
    val shape = RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp, bottomStart = 18.dp, bottomEnd = 18.dp)
    Column(Modifier.offset(y = lift).width(width).clip(shape).background(pal.surface).border(if (sel) 2.dp else 1.dp, if (sel) pal.accent else pal.stroke, shape)
        .clickable(remember { MutableInteractionSource() }, null) { engine.tap(index) }.padding(5.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        for (slot in WaterSortEngine.CAPACITY - 1 downTo 0) {
            Box(Modifier.fillMaxWidth().height(30.dp).clip(RoundedCornerShape(6.dp)).background(if (slot < contents.size) WaterPalette[contents[slot]] else Color.Transparent))
        }
    }
}
