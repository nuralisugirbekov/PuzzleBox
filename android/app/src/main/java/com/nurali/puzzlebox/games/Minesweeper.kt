package com.nurali.puzzlebox.games

import android.os.SystemClock
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
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
import com.nurali.puzzlebox.ui.Pal
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

enum class MineLevel(val titleKey: String, val size: Int, val mines: Int, val bonus: Int) {
    Easy("Easy", 9, 10, 100), Medium("Medium", 12, 24, 300), Hard("Hard", 14, 40, 600)
}

data class MineCell(
    val isMine: Boolean = false,
    val revealed: Boolean = false,
    val flagged: Boolean = false,
    val adjacent: Int = 0,
    /** Distance from the opening tap, for a rippling reveal. */
    val wave: Int = 0,
)

class MinesweeperEngine : GameEngine {
    var level by mutableStateOf(MineLevel.entries.getOrElse(Settings.prefs.getInt("minesweeperDifficulty", 0)) { MineLevel.Easy })
        private set
    val grid = mutableStateListOf<MineCell>()
    var revealedCount by mutableIntStateOf(0)
    private var minesPlaced = false
    var exploded by mutableStateOf<Int?>(null)
    private var startedAt = 0L
    var finishSeconds by mutableStateOf<Int?>(null)
    var flagMode by mutableStateOf(false)
    override var state: GameState by mutableStateOf(GameState.Playing)

    val size get() = level.size
    val flagsUsed get() = grid.count { it.flagged }
    val minesLeft get() = level.mines - flagsUsed
    val elapsedSeconds: Int get() = finishSeconds ?: if (minesPlaced) ((SystemClock.elapsedRealtime() - startedAt) / 1000).toInt() else 0
    val running get() = minesPlaced && finishSeconds == null

    override val score: Int
        get() {
            val won = (state as? GameState.GameOver)?.won == true
            if (!won) return revealedCount * 2
            // Faster clears earn more.
            val seconds = finishSeconds ?: 999
            return revealedCount * 2 + level.bonus + max(0, 300 - seconds) * (level.ordinal + 1)
        }

    init { reset() }

    override fun restart() = reset()

    fun chooseLevel(value: MineLevel) {
        if (value == level) return
        level = value
        Settings.prefs.edit().putInt("minesweeperDifficulty", value.ordinal).apply()
        reset()
    }

    private fun reset() {
        grid.clear()
        repeat(size * size) { grid.add(MineCell()) }
        revealedCount = 0; minesPlaced = false; flagMode = false; exploded = null; finishSeconds = null
        state = GameState.Playing
    }

    private fun neighbors(i: Int): List<Int> {
        // `size` must be captured first: inside buildList it would resolve to the list's own size.
        val n = size
        val r = i / n; val c = i % n
        val out = ArrayList<Int>(8)
        for (dr in -1..1) for (dc in -1..1) if (dr != 0 || dc != 0) {
            val nr = r + dr; val nc = c + dc
            if (nr in 0 until n && nc in 0 until n) out.add(nr * n + nc)
        }
        return out
    }

    /** Mines are placed after the first dig so the opening tap is always safe. */
    private fun placeMines(safe: Int) {
        val sr = safe / size; val sc = safe % size
        val spots = grid.indices.filter { abs(it / size - sr) > 1 || abs(it % size - sc) > 1 }.shuffled().take(level.mines)
        for (s in spots) grid[s] = grid[s].copy(isMine = true)
        for (i in grid.indices) grid[i] = grid[i].copy(adjacent = neighbors(i).count { grid[it].isMine })
        minesPlaced = true
        startedAt = SystemClock.elapsedRealtime()
    }

    fun tap(i: Int) {
        if (state != GameState.Playing) return
        if (grid[i].revealed) { chord(i); return }
        if (flagMode) toggleFlag(i) else dig(i)
    }

    fun toggleFlag(i: Int) {
        if (state != GameState.Playing || grid[i].revealed) return
        grid[i] = grid[i].copy(flagged = !grid[i].flagged)
        Haptics.tap(); Sfx.tap()
    }

    /** Tapping a number whose flags are all placed opens the rest of its neighbours. */
    private fun chord(i: Int) {
        val cell = grid[i]
        if (cell.adjacent == 0) return
        val around = neighbors(i)
        if (around.count { grid[it].flagged } != cell.adjacent) return
        for (n in around) if (!grid[n].revealed && !grid[n].flagged) {
            dig(n)
            if (state != GameState.Playing) return
        }
    }

    fun dig(i: Int) {
        if (state != GameState.Playing || grid[i].revealed || grid[i].flagged) return
        if (!minesPlaced) placeMines(i)

        if (grid[i].isMine) {
            exploded = i
            finishSeconds = ((SystemClock.elapsedRealtime() - startedAt) / 1000).toInt()
            for (k in grid.indices) if (grid[k].isMine) grid[k] = grid[k].copy(revealed = true, wave = abs(k / size - i / size) + abs(k % size - i % size))
            Haptics.heavy(); Sfx.wrong()
            state = GameState.GameOver(won = false)
            return
        }

        // Flood reveal from the tapped cell.
        val stack = ArrayDeque<Int>().apply { add(i) }
        var opened = 0
        while (stack.isNotEmpty()) {
            val cur = stack.removeLast()
            val cell = grid[cur]
            if (cell.revealed || cell.isMine) continue
            grid[cur] = cell.copy(revealed = true, flagged = false, wave = max(abs(cur / size - i / size), abs(cur % size - i % size)))
            revealedCount++; opened++
            if (cell.adjacent == 0) neighbors(cur).filter { !grid[it].revealed }.forEach { stack.add(it) }
        }
        Haptics.move(); if (opened > 8) Sfx.point() else Sfx.tap()

        if (revealedCount == size * size - level.mines) {
            finishSeconds = ((SystemClock.elapsedRealtime() - startedAt) / 1000).toInt()
            for (k in grid.indices) if (grid[k].isMine) grid[k] = grid[k].copy(flagged = true)
            state = GameState.GameOver(won = true)
        }
    }
}

private fun clockText(seconds: Int) = "%d:%02d".format(seconds / 60, seconds % 60)

private val numberColors = listOf(
    Color.Transparent, Color(0xFF3B82F6), Color(0xFF22A06B), Color(0xFFEF4444), Color(0xFF6D28D9),
    Color(0xFFB45309), Color(0xFF0E9AA7), Color(0xFF111111), Color(0xFF6B7280),
)

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MinesweeperScreen(onExit: () -> Unit) {
    val engine = remember { MinesweeperEngine() }
    val pal = Pal.current
    var clock by remember { mutableIntStateOf(0) }
    LaunchedEffect(engine.state, engine.running) {
        while (isActive) {
            clock = engine.elapsedSeconds
            if (engine.state != GameState.Playing) break
            delay(500)
        }
    }
    GameContainer(GameId.Minesweeper, engine, onExit,
        summary = { engine.finishSeconds?.let { L10n.f("Time: %@", clockText(it)) } ?: L10n.t(engine.level.titleKey) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                MineLevel.entries.forEach { lv ->
                    val sel = lv == engine.level
                    Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp))
                        .background(if (sel) pal.accent else pal.surface).clickable { engine.chooseLevel(lv) }.padding(vertical = 10.dp),
                        contentAlignment = Alignment.Center) {
                        Text(L10n.t(lv.titleKey), color = if (sel) pal.onAccent else pal.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("🚩 ${engine.minesLeft}", color = Color(0xFFFF3B30), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                Text("⏱ " + clockText(clock), color = pal.text, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                Box(Modifier.clip(RoundedCornerShape(16.dp)).background(if (engine.flagMode) pal.accent else pal.surface)
                    .clickable { engine.flagMode = !engine.flagMode }.padding(horizontal = 12.dp, vertical = 8.dp)) {
                    Text(if (engine.flagMode) "🚩 " + L10n.t("Flag Mode") else "⛏ " + L10n.t("Dig Mode"),
                        color = if (engine.flagMode) pal.onAccent else pal.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val cell = (maxWidth - 12.dp) / engine.size
                Column(Modifier.clip(RoundedCornerShape(16.dp)).background(pal.surface).padding(6.dp)) {
                    for (r in 0 until engine.size) Row {
                        for (c in 0 until engine.size) {
                            val i = r * engine.size + c
                            CellView(engine, i, Modifier.size(cell))
                        }
                    }
                }
            }
            Text(L10n.t("Long-press to flag. Tap a number with all its flags placed to open the cells around it."),
                color = pal.textSecondary, fontSize = 12.sp, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CellView(engine: MinesweeperEngine, i: Int, modifier: Modifier) {
    val pal = Pal.current
    val cell = engine.grid[i]
    val lost = (engine.state as? GameState.GameOver)?.won == false
    // Cells open in a ripple from the tapped cell.
    val open by animateFloatAsState(if (cell.revealed) 1f else 0f, tween(180, delayMillis = min(cell.wave, 12) * 25, easing = FastOutSlowInEasing), label = "open")
    val revealedColor = if (engine.exploded == i) Color(0xFFEF4444) else pal.background
    val covered = Brush.verticalGradient(listOf(pal.surfaceHigh, pal.surfaceHigh.copy(alpha = 0.6f)))
    val shape = RoundedCornerShape(if (engine.size > 10) 3.dp else 5.dp)
    Box(
        modifier.padding(if (engine.size > 10) 1.dp else 1.5.dp).graphicsLayer { val s = 0.96f + 0.04f * open; scaleX = s; scaleY = s }
            .clip(shape).background(covered).background(revealedColor.copy(alpha = open))
            .combinedClickable(onClick = { engine.tap(i) }, onLongClick = { engine.toggleFlag(i) }),
        contentAlignment = Alignment.Center,
    ) {
        val fs = (if (engine.size > 12) 12 else 16).sp
        when {
            cell.revealed && cell.isMine -> Text(if (cell.flagged) "🚩" else "💣", fontSize = fs, modifier = Modifier.alpha(open))
            cell.revealed && cell.adjacent > 0 -> Text("${cell.adjacent}", color = numberColors[cell.adjacent], fontSize = fs, fontWeight = FontWeight.Black, modifier = Modifier.alpha(open))
            !cell.revealed && cell.flagged -> Text(if (lost && !cell.isMine) "❌" else "🚩", fontSize = fs)
        }
    }
}
