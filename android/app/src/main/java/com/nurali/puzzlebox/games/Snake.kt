package com.nurali.puzzlebox.games

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
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
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs

data class P(val r: Int, val c: Int)

private val Dir.dr get() = when (this) { Dir.Up -> -1; Dir.Down -> 1; else -> 0 }
private val Dir.dc get() = when (this) { Dir.Left -> -1; Dir.Right -> 1; else -> 0 }
private val Dir.opposite get() = when (this) { Dir.Up -> Dir.Down; Dir.Down -> Dir.Up; Dir.Left -> Dir.Right; Dir.Right -> Dir.Left }

class SnakeEngine : GameEngine {
    companion object {
        const val COLS = 14
        const val ROWS = 14
        /** Ticks the golden apple stays on the board. */
        const val GOLDEN_LIFETIME = 32
        /** Eating again within this many ticks keeps the combo alive. */
        const val COMBO_WINDOW = 14
    }

    var snake by mutableStateOf(listOf<P>())          // head first
    var food by mutableStateOf(P(0, 0))
    var golden by mutableStateOf<P?>(null)
    var goldenTicksLeft by mutableIntStateOf(0)
    var rocks by mutableStateOf(setOf<P>())
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var eaten by mutableIntStateOf(0)
    var combo by mutableIntStateOf(0)
    var level by mutableIntStateOf(1)
    var bite by mutableIntStateOf(0)
    /** Bumped on restart so the game loop in the view starts over. */
    var runId by mutableIntStateOf(0)

    private var direction = Dir.Right
    private val queued = ArrayList<Dir>()
    private var ticksSinceFood = 0

    /** Tick interval shrinks as more food is eaten, down to a floor. */
    val tickMs: Long get() = maxOf(85, 210 - eaten * 4).toLong()

    init { reset() }

    override fun restart() {
        reset()
        state = GameState.Playing
        runId++
    }

    private fun reset() {
        val mid = ROWS / 2
        snake = listOf(P(mid, 6), P(mid, 5), P(mid, 4))
        direction = Dir.Right
        queued.clear()
        score = 0; eaten = 0; combo = 0; level = 1; bite = 0
        golden = null; goldenTicksLeft = 0; rocks = emptySet(); ticksSinceFood = 0
        spawnFood()
    }

    /** Up to two buffered turns, so quick swipes (e.g. a U-turn) are not lost. */
    fun turn(new: Dir) {
        if (state != GameState.Playing) return
        val last = queued.lastOrNull() ?: direction
        if (new == last || new == last.opposite || queued.size >= 2) return
        queued.add(new)
    }

    fun tick() {
        if (state != GameState.Playing) return
        if (queued.isNotEmpty()) direction = queued.removeAt(0)
        val head = snake.first()
        val next = P(head.r + direction.dr, head.c + direction.dc)
        if (next.r !in 0 until ROWS || next.c !in 0 until COLS || next in rocks) return die()

        val eatsFood = next == food
        val eatsGolden = next == golden
        val body = snake.toMutableList()
        if (!eatsFood && !eatsGolden) body.removeAt(body.lastIndex)  // the tail vacates its cell this tick
        if (next in body) return die()
        body.add(0, next)
        snake = body
        ticksSinceFood++

        if (goldenTicksLeft > 0) {
            goldenTicksLeft--
            if (goldenTicksLeft == 0) golden = null
        }

        if (eatsFood || eatsGolden) {
            combo = if (ticksSinceFood <= COMBO_WINDOW) combo + 1 else 1
            ticksSinceFood = 0
            val multiplier = minOf(combo, 4)
            score += (if (eatsGolden) 50 else 10) * multiplier
            bite++
            if (eatsGolden) {
                golden = null; goldenTicksLeft = 0
                Haptics.success(); Sfx.win()
            } else {
                eaten++
                Haptics.move(); Sfx.point()
                spawnFood()
                if (eaten % 5 == 0) levelUp()
                if (golden == null && eaten % 4 == 0) spawnGolden()
            }
        }
    }

    /** Every five apples the board gets a little harder: a new rock appears. */
    private fun levelUp() {
        level++
        val head = snake.first()
        val spot = freeCells().filter { abs(it.r - head.r) + abs(it.c - head.c) > 4 && it != food }.randomOrNull()
        if (spot != null) rocks = rocks + spot
    }

    private fun spawnGolden() {
        golden = freeCells().filter { it != food }.randomOrNull() ?: return
        goldenTicksLeft = GOLDEN_LIFETIME
    }

    private fun die() { state = GameState.GameOver(won = false) }

    private fun freeCells(): List<P> {
        val occupied = snake.toSet() + rocks + listOfNotNull(golden)
        return buildList {
            for (r in 0 until ROWS) for (c in 0 until COLS) P(r, c).let { if (it !in occupied) add(it) }
        }
    }

    private fun spawnFood() {
        val spot = freeCells().randomOrNull()
        if (spot != null) food = spot else state = GameState.GameOver(won = true)  // board completely filled
    }
}

@Composable
fun SnakeScreen(onExit: () -> Unit) {
    val engine = remember { SnakeEngine() }
    val pal = Pal.current
    LaunchedEffect(engine.state, engine.runId) {
        while (isActive && engine.state == GameState.Playing) {
            delay(engine.tickMs)
            engine.tick()
        }
    }
    GameContainer(GameId.Snake, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp)) {
                Text(L10n.f("Level %d", engine.level), color = pal.accent, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                if (engine.combo > 1) Text("×${minOf(engine.combo, 4)}", color = Color(0xFFFFCC00), fontWeight = FontWeight.Black)
            }
            Box(
                Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(16.dp)).pointerInput(engine) {
                    var dx = 0f; var dy = 0f
                    detectDragGestures(
                        onDragStart = { dx = 0f; dy = 0f },
                        onDrag = { _, d ->
                            dx += d.x; dy += d.y
                            if (maxOf(abs(dx), abs(dy)) > 28f) {
                                engine.turn(if (abs(dx) > abs(dy)) { if (dx > 0) Dir.Right else Dir.Left } else { if (dy > 0) Dir.Down else Dir.Up })
                                dx = 0f; dy = 0f
                            }
                        },
                    )
                },
            ) {
                Canvas(Modifier.fillMaxSize()) {
                    val cell = size.width / SnakeEngine.COLS
                    for (r in 0 until SnakeEngine.ROWS) for (c in 0 until SnakeEngine.COLS) {
                        drawRect(if ((r + c) % 2 == 0) Color(0xFF1F2A22) else Color(0xFF1A241D),
                            Offset(c * cell, r * cell), Size(cell, cell))
                    }
                    engine.rocks.forEach {
                        drawRoundRect(Color(0xFF7A7F8A), Offset(it.c * cell + cell * 0.08f, it.r * cell + cell * 0.08f),
                            Size(cell * 0.84f, cell * 0.84f), CornerRadius(cell * 0.25f))
                    }
                    drawCircle(Color(0xFFFF3B30), cell * 0.38f, Offset((engine.food.c + 0.5f) * cell, (engine.food.r + 0.5f) * cell))
                    engine.golden?.let {
                        val blink = engine.goldenTicksLeft > 8 || engine.goldenTicksLeft % 2 == 0
                        if (blink) drawCircle(Color(0xFFFFCC00), cell * 0.42f, Offset((it.c + 0.5f) * cell, (it.r + 0.5f) * cell))
                    }
                    engine.snake.forEachIndexed { i, p ->
                        val shade = 1f - i.toFloat() / (engine.snake.size + 4)
                        val color = Color(0xFF34C759).copy(alpha = 0.55f + 0.45f * shade)
                        val inset = if (i == 0) cell * 0.04f else cell * 0.1f
                        drawRoundRect(color, Offset(p.c * cell + inset, p.r * cell + inset),
                            Size(cell - inset * 2, cell - inset * 2), CornerRadius(cell * 0.3f))
                        if (i == 0) {
                            val cx = (p.c + 0.5f) * cell; val cy = (p.r + 0.5f) * cell
                            drawCircle(Color.White, cell * 0.12f, Offset(cx - cell * 0.18f, cy - cell * 0.1f))
                            drawCircle(Color.White, cell * 0.12f, Offset(cx + cell * 0.18f, cy - cell * 0.1f))
                            drawCircle(Color.Black, cell * 0.06f, Offset(cx - cell * 0.18f, cy - cell * 0.1f))
                            drawCircle(Color.Black, cell * 0.06f, Offset(cx + cell * 0.18f, cy - cell * 0.1f))
                        }
                    }
                }
            }
            Text(L10n.t("Swipe on the board to steer the snake."), color = pal.textSecondary, fontSize = 13.sp,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
        }
    }
}
