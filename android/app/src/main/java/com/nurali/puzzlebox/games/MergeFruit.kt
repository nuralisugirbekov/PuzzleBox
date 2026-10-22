package com.nurali.puzzlebox.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.text.style.TextAlign
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
import com.nurali.puzzlebox.games.kit.Ball
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.PhysWorld
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.hsb
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/** Playfield is 320 × 480, y down. The crate spans y 88..472; the red limit line is at y 88. */
class MergeFruitEngine : FrameGame {
    companion object {
        val symbols = listOf("🍒", "🍓", "🍇", "🍊", "🍎", "🍐", "🍑", "🍍", "🍉")
        val radii = floatArrayOf(12f, 16f, 21f, 27f, 34f, 42f, 51f, 61f, 73f)
        val maxStage get() = radii.size - 1
        const val HELD_Y = 35f
        const val LIMIT_Y = 90f
        fun color(stage: Int) = hsb(stage / 12.0, 0.55f, 0.9f)
    }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var currentFruit by mutableIntStateOf(Random.nextInt(3))
    var nextFruit by mutableIntStateOf(Random.nextInt(3))
    var chain by mutableIntStateOf(0)
    var biggest by mutableIntStateOf(0)
    var started by mutableStateOf(false)
    val fx = ArcadeFX()

    val world = PhysWorld(900f)
    private var clock = 0.0
    private var nextDrop = 0.0
    private var overflowTime = 0.0
    private var lastMerge = -10.0
    private var chainCount = 0
    var aimX = 160f
    var tooHigh = false

    init { restart() }

    val canDrop get() = clock >= nextDrop

    override fun restart() {
        score = 0; state = GameState.Playing; chain = 0; biggest = 0; started = false
        currentFruit = Random.nextInt(3); nextFruit = Random.nextInt(3)
        world.balls.clear(); world.segs.clear(); fx.reset()
        clock = 0.0; nextDrop = 0.0; overflowTime = 0.0; lastMerge = -10.0; chainCount = 0; aimX = 160f; tooHigh = false
        // Crate walls: left, floor, right (extending well above the top).
        world.wall(5f, -120f, 5f, 472f, 0.2f, 0.4f)
        world.wall(5f, 472f, 315f, 472f, 0.2f, 0.4f)
        world.wall(315f, 472f, 315f, -120f, 0.2f, 0.4f)
    }

    fun aim(x: Float) {
        val r = radii[currentFruit]
        aimX = min(314f - r, max(6f + r, x))
    }

    fun drop(x: Float) {
        if (state != GameState.Playing || !canDrop) return
        started = true
        val r = radii[currentFruit]
        val b = Ball(min(314f - r, max(6f + r, x)), HELD_Y, r, tag = currentFruit)
        b.restitution = 0.12f; b.friction = 0.55f; b.damping = 0.3f; b.birth = clock
        world.add(b)
        nextDrop = clock + 0.55
        aimX = b.x
        currentFruit = nextFruit
        // Bigger starting fruit appear once the board has grown up a little.
        nextFruit = Random.nextInt(if (biggest >= 5) 4 else 3)
        Haptics.tap(); Sfx.tap()
    }

    override fun advance(dt: Double) {
        fx.update(dt.toFloat())
        if (state != GameState.Playing) return
        val d = min(0.05, max(0.0, dt))
        clock += d
        world.step(d.toFloat())
        // Merge touching pairs of the same stage.
        val pending = world.touching.filter { (a, b) -> a.tag == b.tag && !a.dead && !b.dead }
        val used = HashSet<Ball>()
        for ((a, b) in pending) {
            if (a in used || b in used) continue
            used.add(a); used.add(b)
            a.dead = true; b.dead = true
            val px = (a.x + b.x) / 2; val py = (a.y + b.y) / 2
            if (a.tag == maxStage) {
                // Two watermelons pop together for a big bonus.
                score += 1000; Haptics.success(); Sfx.win()
                fx.burst(px, py, Color(0xFF34C759), 30, 240f, 300f, 4f, 0.7f)
                fx.popup(L10n.t("Melon party!") + " +1000", px, py, Color(0xFF34C759), 24f)
                continue
            }
            chainCount = if (clock - lastMerge < 0.9) chainCount + 1 else 1
            lastMerge = clock
            chain = chainCount
            val stage = a.tag + 1
            val r = radii[stage]
            val m = Ball(min(314f - r, max(9f + r, px)), min(463f - r, py), r, tag = stage)
            m.birth = clock; m.restitution = 0.12f; m.friction = 0.55f; m.damping = 0.3f
            world.add(m)
            biggest = max(biggest, stage)
            val points = (1 shl stage) * 10 * min(chainCount, 5)
            score += points
            Haptics.move(); Sfx.point()
            fx.burst(m.x, m.y, color(stage), 10 + stage * 2, 120f + r, 250f, 3f, 0.45f)
            fx.popup(if (chainCount > 1) "+$points ×${min(chainCount, 5)}" else "+$points", m.x, m.y - r,
                if (chainCount > 1) Color(0xFFFF9500) else Color.White, if (chainCount > 1) 22f else 18f)
        }
        world.balls.removeAll { it.dead }
        tooHigh = world.balls.any { clock - it.birth > 1.5 && it.y - it.r < LIMIT_Y }
        overflowTime = if (tooHigh) overflowTime + d else 0.0
        if (overflowTime > 1.6) { state = GameState.GameOver(won = false); Haptics.error(); Sfx.lose() }
    }
}

@Composable
fun MergeFruitScreen(onExit: () -> Unit) {
    val engine = remember { MergeFruitEngine() }
    val pal = Pal.current
    GameContainer(GameId.MergeFruit, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L10n.t("Next fruit"), color = pal.accent, fontWeight = FontWeight.SemiBold)
                Text(MergeFruitEngine.symbols[engine.nextFruit], fontSize = 26.sp)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                if (engine.chain > 1) Text("🔥×${min(engine.chain, 5)}", color = Color(0xFFFF9500), fontWeight = FontWeight.Bold)
                Text(MergeFruitEngine.symbols[engine.biggest], fontSize = 24.sp)
            }
            val input = remember(engine) {
                object : FieldInput() {
                    override fun onDown(x: Float, y: Float) = engine.aim(x)
                    override fun onMove(x: Float, y: Float) = engine.aim(x)
                    override fun onUp(x: Float, y: Float, tapped: Boolean) = engine.drop(x)
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 400.dp), fieldW = 320f, fieldH = 480f, background = Color(0xFFFAEDD6), fx = engine.fx, input = input) { drawMerge(engine) }
            Text(L10n.t("Drag to aim and release to drop. Quick merges build a combo, and two watermelons make a melon party!"),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private fun Pen.fruit(x: Float, y: Float, stage: Int, alpha: Float = 1f, squash: Float = 1f) {
    val r = MergeFruitEngine.radii[stage] * squash
    circle(x, y, r, MergeFruitEngine.color(stage).copy(alpha = alpha))
    circle(x, y, r, Color.White.copy(alpha = 0.35f * alpha), 1.5f)
    oval(x - r * 0.65f, y - r * 0.75f, r * 0.7f, r * 0.45f, Color.White.copy(alpha = 0.3f * alpha))
    label(MergeFruitEngine.symbols[stage], x, y, r * 1.4f, Color.White.copy(alpha = alpha))
}

private fun Pen.drawMerge(e: MergeFruitEngine) {
    // A soft wooden crate behind the fruit.
    box(5f, 88f, 310f, 384f, Color(0xFFF2D6A8), 6f)
    var y = 88f + 64f
    while (y < 472f) { box(5f, y, 310f, 1.5f, Color(0xFFCCA373).copy(alpha = 0.6f), 0f); y += 64f }
    // Held fruit and aim guide.
    val r = MergeFruitEngine.radii[e.currentFruit]
    var gy = MergeFruitEngine.HELD_Y + r + 6
    while (gy < 468f) { line(e.aimX, gy, e.aimX, gy + 7f, Color.Black.copy(alpha = 0.18f), 2f); gy += 14f }
    for (b in e.world.balls) fruit(b.x, b.y, b.tag)
    fruit(e.aimX, MergeFruitEngine.HELD_Y, e.currentFruit, if (e.canDrop) 1f else 0.4f)
    // Walls and the limit line.
    line(5f, -20f, 5f, 472f, Color(0xFF996B40), 6f)
    line(5f, 472f, 315f, 472f, Color(0xFF996B40), 6f)
    line(315f, 472f, 315f, -20f, Color(0xFF996B40), 6f)
    val a = if (e.tooHigh) 0.5f + 0.5f * abs(sin(System.nanoTime() / 1e9f * 12f)) else 0.5f
    box(6f, 88f, 308f, 3f, Color(0xFFFF3B30).copy(alpha = a), 0f)
}

