package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
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
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Hearts
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Көкпар — ride up the field, pick up the "серке" (goat carcass), swerve around rival riders
// and drop it in the kazan. Swipe left and right to change lanes.
class KokparRider(val id: Int, var x: Float, var d: Float, var vx: Float = 0f, val chaser: Boolean, var passed: Boolean = false)

class KokparEngine : FrameGame {
    companion object {
        const val LANES = 5
        val laneX = floatArrayOf(40f, 100f, 160f, 220f, 280f)
        const val PLAYER_Y = 372f
        const val MAX_LIVES = 3
    }

    private var bonus = 0
    override val score get() = (distance / 12).toInt() + bonus
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var lane = 2
    var px = 160f
    var distance by mutableFloatStateOf(0f)
    val riders = ArrayList<KokparRider>()
    /** World position of the serke while it lies on the ground. */
    var serkeX = 0f; var serkeY = 0f; var hasSerke = false
    var carrying by mutableStateOf(false)
    var goalD = 1500f
    var goals by mutableIntStateOf(0)
    var lives by mutableIntStateOf(MAX_LIVES)
    var invulnerable = 0f
    var stun = 0f
    var streak = 0
    var gait = 0f
    val fx = ArcadeFX()

    private var nextRow = 520f
    private var nextId = 0
    private var random = PuzzleRandom(99)
    private var roundStart = 0f

    val speed get() = (190 + min(goals, 8) * 14) * (if (stun > 0) 0.45f else 1f)
    val progress get() = min(1f, max(0f, (distance - roundStart) / max(1f, goalD - roundStart)))

    init { restart() }

    override fun restart() {
        state = GameState.Playing; bonus = 0; started = false
        lane = 2; px = laneX[2]; distance = 0f; riders.clear(); carrying = false
        goals = 0; lives = MAX_LIVES; invulnerable = 0f; stun = 0f; streak = 0; gait = 0f
        fx.reset()
        random = PuzzleRandom(System.nanoTime())
        beginRound()
    }

    private fun beginRound() {
        roundStart = distance
        goalD = distance + 1500 + min(goals, 8) * 120
        riders.removeAll { it.d < distance + 40 }
        carrying = false
        hasSerke = true; serkeX = laneX[random.nextInt(LANES)]; serkeY = distance + 300
        nextRow = distance + 540
    }

    fun swipe(direction: Int) {
        if (state != GameState.Playing) return
        if (!started) { started = true; return }
        val target = max(0, min(LANES - 1, lane + direction))
        if (target == lane) return
        lane = target
        Sfx.tap(); Haptics.tap()
    }

    fun start() { if (state == GameState.Playing) started = true }

    override fun advance(dt: Double) {
        val step = min(0.05, max(0.0, dt)).toFloat()
        fx.update(step)
        if (!started || state != GameState.Playing) return
        invulnerable = max(0f, invulnerable - step); stun = max(0f, stun - step)
        gait += step * 11 * (speed / 200)
        px += (laneX[lane] - px) * min(1f, 13 * step)
        distance += speed * step
        spawnRows(); updateRiders(step); collide(); pickUp(); checkGoal()
        riders.removeAll { it.d < distance - 120 }
    }

    private fun spawnRows() {
        if (nextRow >= goalD - 220) return
        while (nextRow < distance + 700 && nextRow < goalD - 220) {
            val level = min(goals, 10)
            val count = 1 + (if (random.nextInt(100) < 25 + level * 6) 1 else 0) + (if (level >= 4 && random.nextInt(100) < 25) 1 else 0)
            val free = (0 until LANES).shuffled(random).toMutableList()
            repeat(min(count, 3)) {
                val l = free.removeAt(free.lastIndex)
                val chaser = level >= 1 && random.nextInt(100) < 20 + level * 5
                riders.add(KokparRider(nextId++, laneX[l], nextRow, chaser = chaser))
            }
            nextRow += random.nextInt(170, 251) - level * 6
        }
    }

    private fun updateRiders(dt: Float) {
        for (r in riders) {
            val ahead = r.d - distance
            if (r.chaser && ahead > 30 && ahead < 280) r.vx = max(-80f, min(80f, (px - r.x) * 1.8f)) // Rivals cut across to block the player.
            else if (ahead < 30) r.vx *= 0.9f
            r.x = max(30f, min(290f, r.x + r.vx * dt))
            if (!r.passed && ahead < -30) {
                r.passed = true
                if (abs(r.x - px) < 58) {
                    streak++
                    val b = 15 * min(streak, 5)
                    bonus += b
                    fx.popup(L10n.t("Close call!") + " +$b", px, PLAYER_Y + 30, Color.Yellow, 14f)
                    Sfx.point()
                } else streak = 0
            }
        }
    }

    private fun collide() {
        if (invulnerable > 0) return
        val hit = riders.firstOrNull { abs(it.d - distance) < 38 && abs(it.x - px) < 30 } ?: return
        lives--; streak = 0
        invulnerable = 1.4f; stun = 0.7f
        fx.burst(px, PLAYER_Y, Color(0xFFFF9500), 18, 150f, 0f, 3f, 0.6f)
        fx.kick(7f); fx.flash(Color.Red, 0.22f)
        Haptics.error(); Sfx.wrong()
        if (carrying) {
            // The serke is knocked loose and lands just ahead.
            carrying = false; hasSerke = true; serkeX = hit.x; serkeY = distance + 70
            fx.popup(L10n.t("Dropped it!"), px, PLAYER_Y - 60, Color.White, 18f)
        }
        if (lives <= 0) state = GameState.GameOver(won = goals >= 1)
    }

    private fun pickUp() {
        if (carrying || !hasSerke) return
        if (abs(serkeY - distance) < 34 && abs(serkeX - px) < 34) {
            carrying = true; hasSerke = false
            bonus += 50
            fx.popup(L10n.t("Got the serke! +50"), px, PLAYER_Y - 50, Color.Yellow, 17f)
            fx.burst(px, PLAYER_Y - 20, Color.Yellow, 14, 120f, 60f, 3f)
            Haptics.success(); Sfx.point()
        } else if (serkeY < distance - 80) {
            // Missed it: a new serke is thrown ahead so the round can go on.
            serkeX = laneX[random.nextInt(LANES)]; serkeY = distance + 260
        }
    }

    private fun checkGoal() {
        if (distance < goalD) return
        if (carrying) {
            goals++
            val reward = 300 + lives * 50
            bonus += reward
            fx.burst(160f, 130f, Color.Yellow, 40, 220f, 150f, 4f, 1f)
            fx.popup(L10n.f("Goal %d! +%d", goals, reward), 160f, 190f, Color.White, 24f)
            fx.flash(Color.Yellow, 0.25f)
            Haptics.heavy(); Sfx.win()
            beginRound()
        } else {
            goalD += 700
            fx.popup(L10n.t("Bring the serke first!"), 160f, 200f, Color.White, 17f)
            Haptics.error(); Sfx.wrong()
        }
    }
}

@Composable
fun KokparScreen(onExit: () -> Unit) {
    val engine = remember { KokparEngine() }
    val pal = Pal.current
    GameContainer(GameId.Kokpar, engine, onExit, summary = { L10n.f("Goals: %d", engine.goals) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("🏁 ${engine.goals}", color = pal.accent, fontWeight = FontWeight.SemiBold)
                Box(Modifier.weight(1f).height(8.dp).clip(CircleShape).background(pal.surfaceHigh)) {
                    Box(Modifier.fillMaxWidth(engine.progress).height(8.dp).clip(CircleShape).background(if (engine.carrying) Color.Yellow else pal.accent))
                }
                Text(if (engine.carrying) "✔" else "◌", color = if (engine.carrying) Color.Yellow else pal.textSecondary, fontWeight = FontWeight.Bold)
                Hearts(engine.lives, KokparEngine.MAX_LIVES)
            }
            val input = remember(engine) {
                object : FieldInput() {
                    var sx = 0f
                    override fun onDown(x: Float, y: Float) { sx = x }
                    override fun onUp(x: Float, y: Float, tapped: Boolean) {
                        val dx = x - sx
                        if (abs(dx) > 18f) engine.swipe(if (dx > 0) 1 else -1)
                        else if (!engine.started) engine.start()
                        else engine.swipe(if (x < 160f) -1 else 1)
                    }
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, fx = engine.fx, input = input,
                overlay = { if (!engine.started) com.nurali.puzzlebox.games.kit.StartPrompt(L10n.t("Swipe to start")) }) { drawField(engine) }
            Text(L10n.t("Swipe left or right to change lanes. Grab the serke, dodge the rival riders and carry it to the kazan."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private fun screenY(e: KokparEngine, d: Float) = KokparEngine.PLAYER_Y - (d - e.distance)

private fun Pen.drawField(e: KokparEngine) {
    // Mown stripes scroll with the distance.
    val stripe = 70f
    val offset = e.distance % (stripe * 2)
    box(0f, 0f, 320f, 460f, Color(0xFF5C9E45), 0f)
    var y = -stripe * 2 + offset
    while (y < 480) { box(0f, y, 320f, stripe, Color(0xFF66AB4D), 0f); y += stripe * 2 }
    for (x in listOf(10f, 310f)) line(x, 0f, x, 460f, Color.White.copy(alpha = 0.5f), 3f)
    for (x in listOf(70f, 130f, 190f, 250f)) line(x, 0f, x, 460f, Color.White.copy(alpha = 0.07f), 2f)
    // Spectators' flags along the edges, fixed to the field.
    val firstFlag = kotlin.math.floor(e.distance / 170f) * 170f
    for (k in -1..3) {
        val yy = screenY(e, firstFlag + k * 170f)
        for ((x, c) in listOf(4f to Color.Red, 316f to Color.Yellow)) { line(x, yy, x, yy - 14, Color.White.copy(alpha = 0.8f), 1.5f); box(if (x < 160) x else x - 9, yy - 14, 9f, 6f, c, 0f) }
    }
    val gy = screenY(e, e.goalD)
    if (gy > -90 && gy < 520) goal(gy)
    if (e.hasSerke) { val sy = screenY(e, e.serkeY); if (sy > -40 && sy < 500) serke(e, e.serkeX, sy, false) }
    for (r in e.riders) {
        val ry = screenY(e, r.d)
        if (ry <= -60 || ry >= 520) continue
        horse(r.x, ry, if (r.chaser) Color(0xFF40404D) else Color(0xFF8C8C99), if (r.chaser) Color(0xFF3373E6) else Color(0xFF33A680), Color.White, false, e.gait + r.id)
    }
    // The player: blinks while protected.
    if (!(e.invulnerable > 0 && (e.invulnerable * 12).toInt() % 2 == 0)) {
        horse(e.px, KokparEngine.PLAYER_Y, Color(0xFF8C5229), Color(0xFFE63340), Color(0xFFFFD940), true, e.gait)
        if (e.carrying) serke(e, e.px + 13, KokparEngine.PLAYER_Y - 4, true)
    }
}

private fun Pen.goal(y: Float) {
    box(0f, y - 4, 320f, 8f, Color.White.copy(alpha = 0.85f), 0f)
    oval(60f, y - 90, 200f, 180f, Color(0xFFE0C780).copy(alpha = 0.7f)); strokeOval(60f, y - 90, 200f, 180f, Color.White, 4f)
    val cx = 160f
    circle(cx, y + 6, 44f, Color.Black.copy(alpha = 0.25f))
    shiny(cx, y, 44f, Color(0xFF524D57), Color(0xFF1A1A21))
    circle(cx, y, 44f, Color(0xFFFFCC40), 6f)
    for (k in 0 until 10) { val a = k / 10f * (PI * 2).toFloat(); circle(cx + cos(a) * 44, y + sin(a) * 44, 3f, Color(0xFFE64040)) }
    for (side in listOf(-1f, 1f)) strokeOval(cx + side * 50 - 6, y - 8, 12f, 16f, Color(0xFFFFCC40), 3f)
    label("🔥", cx, y, 24f, Color.White)
    for (x in listOf(34f, 286f)) { line(x, y + 20, x, y - 50, Color.White, 3f); box(if (x < 160) x else x - 22, y - 50, 22f, 14f, Color(0xFF33A6E6), 0f) }
}

private fun Pen.serke(e: KokparEngine, x: Float, y: Float, carried: Boolean) {
    xf(x, y, if (carried) (75 * PI / 180).toFloat() else 0f) {
        if (!carried) {
            val pulse = 1 + 0.12f * sin(e.gait * 0.6f)
            oval(-22 * pulse, -26 * pulse, 44 * pulse, 52 * pulse, Color.Yellow.copy(alpha = 0.25f))
        }
        oval(-8f, -4f, 16f, 30f, Color.Black.copy(alpha = 0.2f))
        ds.drawOval(Brush.linearGradient(listOf(Color(0xFFB8854D), Color(0xFF734D29)), Offset(-8f, -14f), Offset(8f, 14f)), Offset(-8f, -14f), androidx.compose.ui.geometry.Size(16f, 28f))
        oval(-6f, -22f, 8f, 10f, Color(0xFF8C6133))
        for ((dx, dy) in listOf(-9f to -8f, 9f to -8f, -9f to 8f, 9f to 8f)) line(dx * 0.6f, dy, dx * 1.6f, dy + (if (dy < 0) -3f else 3f), Color(0xFF59381A), 2.4f)
    }
}

/** A horse and rider seen from above. */
private fun Pen.horse(x: Float, y: Float, body: Color, coat: Color, hat: Color, facingUp: Boolean, phase: Float) {
    xf(x, y, if (facingUp) 0f else PI.toFloat()) {
        oval(-13f, -18f, 26f, 48f, Color.Black.copy(alpha = 0.22f))
        listOf(-7f to -14f, 7f to -14f, -7f to 13f, 7f to 13f).forEachIndexed { i, (dx, dy) ->
            val swing = sin(phase + (if (i % 2 == 0) 0f else PI.toFloat())) * 5
            box(dx - 2, dy + swing - 5, 4f, 10f, body.copy(alpha = 0.85f), 2f)
        }
        line(0f, 22f, sin(phase) * 3, 38f, body.copy(alpha = 0.9f), 4f)
        oval(-10f, -18f, 20f, 42f, body)
        oval(-4.5f, -32f, 9f, 18f, body); oval(-4f, -40f, 8f, 13f, body.copy(alpha = 0.9f))
        line(0f, -30f, 0f, -14f, Color.Black.copy(alpha = 0.45f), 2f)
        box(-7f, -4f, 14f, 12f, coat.copy(alpha = 0.85f), 3f)
        oval(-9.5f, -9f, 19f, 9f, coat)
        oval(-5f, -10f, 10f, 10f, Color(0xFFF2C79E))
        oval(-5.5f, -12f, 11f, 9f, hat)
        box(-5.5f, -8.5f, 11f, 2f, Color.Black.copy(alpha = 0.35f), 0f)
    }
}
