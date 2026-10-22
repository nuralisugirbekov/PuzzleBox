package com.nurali.puzzlebox.games

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.ui.Pal
import kotlin.random.Random

enum class Dir { Up, Down, Left, Right }

class Game2048Engine : GameEngine {
    companion object { const val N = 4 }

    val cells = mutableStateListOf<Int>().apply { repeat(N * N) { add(0) } }
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var bestTile by mutableIntStateOf(2)
    /** Undo is limited so it cannot be used to reroll every spawn. */
    var undosLeft by mutableIntStateOf(3)
    private var snapshot: Pair<List<Int>, Int>? = null

    init { restart() }

    override fun restart() {
        for (i in cells.indices) cells[i] = 0
        score = 0; bestTile = 2; undosLeft = 3; snapshot = null
        state = GameState.Playing
        spawn(); spawn()
    }

    private fun spawn() {
        val free = cells.indices.filter { cells[it] == 0 }
        if (free.isEmpty()) return
        cells[free.random()] = if (Random.nextInt(10) == 0) 4 else 2
    }

    fun move(dir: Dir) {
        if (state != GameState.Playing) return
        val before = cells.toList()
        var gained = 0
        var biggest = 0
        val next = IntArray(N * N)
        for (line in 0 until N) {
            // Cell indexes of this line, ordered from the edge the tiles slide toward.
            val idx = (0 until N).map { i ->
                when (dir) {
                    Dir.Left -> line * N + i
                    Dir.Right -> line * N + (N - 1 - i)
                    Dir.Up -> i * N + line
                    Dir.Down -> (N - 1 - i) * N + line
                }
            }
            val values = idx.map { before[it] }.filter { it != 0 }
            val merged = ArrayList<Int>()
            var i = 0
            while (i < values.size) {
                if (i + 1 < values.size && values[i] == values[i + 1]) {
                    val v = values[i] * 2
                    merged.add(v); gained += v; biggest = maxOf(biggest, v); i += 2
                } else { merged.add(values[i]); i++ }
            }
            merged.forEachIndexed { slot, v -> next[idx[slot]] = v }
        }
        if (next.toList() == before) return
        snapshot = before to score
        for (i in next.indices) cells[i] = next[i]
        score += gained
        spawn()
        if (gained > 0) { Haptics.move(); Sfx.point() } else Haptics.tap()
        if (biggest > bestTile) { bestTile = biggest; if (biggest >= 128) Haptics.heavy() }
        if (cells.contains(2048)) state = GameState.GameOver(won = true)
        else if (!hasMoves()) state = GameState.GameOver(won = false)
    }

    fun undo() {
        val s = snapshot ?: return
        if (state != GameState.Playing || undosLeft <= 0) return
        undosLeft--
        for (i in s.first.indices) cells[i] = s.first[i]
        score = s.second
        bestTile = maxOf(2, cells.max())
        snapshot = null
        Haptics.tap()
    }

    private fun hasMoves(): Boolean {
        if (cells.contains(0)) return true
        for (i in cells.indices) {
            if (i % N < N - 1 && cells[i] == cells[i + 1]) return true
            if (i / N < N - 1 && cells[i] == cells[i + N]) return true
        }
        return false
    }
}

fun tileColor(v: Int): Color = when {
    v <= 2 -> Color(0xFFEDE3D9)
    v == 4 -> Color(0xFFEDE0C7)
    v == 8 -> Color(0xFFF2B078)
    v == 16 -> Color(0xFFF59563)
    v == 32 -> Color(0xFFF57D5E)
    v == 64 -> Color(0xFFF55E3B)
    v == 128 -> Color(0xFFEDCF73)
    v == 256 -> Color(0xFFEDCC61)
    v == 512 -> Color(0xFFEDC850)
    v == 1024 -> Color(0xFFEDC53F)
    else -> Color(0xFFEDC22E)
}

@Composable
fun Game2048Screen(onExit: () -> Unit) {
    val engine = remember { Game2048Engine() }
    val pal = Pal.current
    GameContainer(GameId.Game2048, engine, onExit) {
        Column(
            Modifier.fillMaxSize().pointerInput(engine) {
                var dx = 0f; var dy = 0f
                detectDragGestures(
                    onDragStart = { dx = 0f; dy = 0f },
                    onDrag = { _, d -> dx += d.x; dy += d.y },
                    onDragEnd = {
                        if (maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy)) > 40f) {
                            engine.move(if (kotlin.math.abs(dx) > kotlin.math.abs(dy)) { if (dx > 0) Dir.Right else Dir.Left } else { if (dy > 0) Dir.Down else Dir.Up })
                        }
                    },
                )
            },
            verticalArrangement = Arrangement.Center,
        ) {
            Text(L10n.t("Merge matching tiles to reach 2048."), color = pal.textSecondary, fontSize = 14.sp,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("★ " + L10n.f("Best tile: %d", engine.bestTile), color = tileColor(engine.bestTile),
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Box(Modifier.clip(RoundedCornerShape(20.dp)).background(pal.surface).clickable { engine.undo() }
                    .padding(horizontal = 14.dp, vertical = 10.dp)) {
                    Text("↩ " + L10n.t("Undo") + " (${engine.undosLeft})", color = pal.text, fontWeight = FontWeight.Bold)
                }
            }
            Spacer(Modifier.height(12.dp))
            Column(
                Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF9E8F80)).padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                for (r in 0 until Game2048Engine.N) {
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (c in 0 until Game2048Engine.N) {
                            Tile(engine.cells[r * Game2048Engine.N + c], Modifier.weight(1f).fillMaxSize())
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Tile(value: Int, modifier: Modifier) {
    val pop = remember { Animatable(1f) }
    LaunchedEffect(value) {
        if (value != 0) { pop.snapTo(0.8f); pop.animateTo(1f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessMedium)) }
    }
    Box(
        modifier.clip(RoundedCornerShape(10.dp)).background(if (value == 0) Color(0x38FFFFFF) else tileColor(value)),
        contentAlignment = Alignment.Center,
    ) {
        if (value != 0) {
            Text("$value", modifier = Modifier.scale(pop.value),
                color = if (value <= 4) Color(0xFF776E65) else Color.White,
                fontSize = when { value < 100 -> 30.sp; value < 1000 -> 24.sp; else -> 19.sp },
                fontWeight = FontWeight.Black)
        }
    }
}
