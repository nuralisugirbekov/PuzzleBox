package com.nurali.puzzlebox.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
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
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Алтыбақан — the traditional six-legged Kazakh swing. Tap as the swing passes the glowing spot
// at the bottom to pump it higher, and ring the bells hung along the arc.
class AltybakanEngine : FrameGame {
    companion object {
        /** Bells, in degrees from the vertical. After the last one the top bell can be rung again and again. */
        val bellAngles = doubleArrayOf(25.0, 40.0, 55.0, 70.0, 85.0)
        const val MAX_LIVES = 3
        private const val GRAVITY = 9.0     // g / L: a calm, two-second swing
        private const val DAMPING = 0.10
        private const val CAP = 1.5         // rad, a little over 85°
        private const val STEP = 1.0 / 240
    }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var lives by mutableIntStateOf(MAX_LIVES)
    var streak by mutableIntStateOf(0)
    var bellsRung by mutableIntStateOf(0)
    val fx = ArcadeFX()

    var theta = 0.15; var omega = 0.0
    var armed = true
    var amplitude = 0.15
    var clock = 0.0
    var lastRungSide = 1.0

    private var accumulator = 0.0
    private var lastRingAt = -10.0

    val multiplier get() = min(5, 1 + streak / 3)
    /** Half-width of the valid window at the bottom, in radians; it widens with speed. */
    val zone get() = 0.22 + 0.20 * min(1.0, amplitude / 1.2)
    val perfectZone get() = 0.09 + 0.06 * min(1.0, amplitude / 1.2)
    val nextBellDegrees get() = bellAngles[min(bellsRung, bellAngles.size - 1)]

    init { restart() }

    override fun restart() {
        state = GameState.Playing; score = 0; started = false
        theta = 0.15; omega = 0.0; lives = MAX_LIVES; streak = 0; bellsRung = 0
        armed = true; amplitude = 0.15; clock = 0.0; accumulator = 0.0; lastRingAt = -10.0
        fx.reset()
    }

    fun tap() {
        if (state != GameState.Playing) return
        if (!started) { started = true; return }
        if (!armed) return
        armed = false
        val offset = abs(theta)
        val towardCentre = theta * omega < 0
        if (!(offset < zone && towardCentre)) { miss(); return }
        val fx0 = (160 + 135 * sin(theta)).toFloat(); val fy0 = (150 + 135 * cos(theta)).toFloat()
        if (offset < perfectZone) {
            omega = (if (omega < 0) -1 else 1) * (abs(omega) * 1.10 + 0.05)
            streak++
            val points = 10 * multiplier
            score += points
            fx.burst(fx0, fy0, Color.Yellow, 12, 110f, 60f, 3f, 0.5f)
            fx.popup(if (streak > 2) "+$points ×$multiplier" else L10n.t("Perfect!"), fx0, fy0 - 26, Color.Yellow, 17f)
            Haptics.success(); Sfx.point()
        } else {
            omega = (if (omega < 0) -1 else 1) * (abs(omega) * 1.06 + 0.04)
            streak = max(0, streak - 1)
            score += 5
            fx.popup("+5", fx0, fy0 - 26, Color.White, 14f)
            Haptics.tap(); Sfx.tap()
        }
    }

    private fun miss() {
        lives--; streak = 0
        omega *= 0.82
        fx.kick(4f); fx.flash(Color.Red, 0.18f)
        fx.popup(L10n.t("Too early or late!"), 160f, 330f, Color.White, 15f)
        Haptics.error(); Sfx.wrong()
        if (lives <= 0) finish()
    }

    private fun finish() {
        fx.burst(160f, 250f, Color(0xFFFF9500), 24, 160f, 200f, 3.5f, 0.7f)
        state = GameState.GameOver(won = bellsRung >= 3)
    }

    override fun advance(dt: Double) {
        val elapsed = min(0.1, max(0.0, dt))
        fx.update(elapsed.toFloat())
        if (state != GameState.Playing) return
        if (!started) { clock += elapsed; return }
        accumulator += elapsed
        while (accumulator >= STEP && state == GameState.Playing) { accumulator -= STEP; integrate(STEP) }
        clock += elapsed
    }

    private fun integrate(dt: Double) {
        val prev = omega
        omega += (-GRAVITY * sin(theta) - DAMPING * omega) * dt
        theta += omega * dt
        // The chains never go slack over the top: the swing simply stops at the cap.
        if (abs(theta) > CAP) { theta = if (theta < 0) -CAP else CAP; omega = 0.0 }
        if (prev * omega <= 0 && abs(prev) + abs(omega) > 0) reachedExtreme()
    }

    /** Every turning point re-arms the next tap and checks the bells. */
    private fun reachedExtreme() {
        armed = true
        amplitude = abs(theta)
        lastRungSide = if (theta < 0) -1.0 else 1.0
        val degrees = abs(theta) * 180 / PI
        if (degrees >= nextBellDegrees && clock - lastRingAt > 1.2) ringBell()
        else if (amplitude < 0.05 && clock > 3) state = GameState.GameOver(won = bellsRung >= 3) // The swing has died down.
    }

    private fun ringBell() {
        lastRingAt = clock
        val points = 100 * (min(bellsRung, bellAngles.size - 1) + 1)
        val a = lastRungSide * bellAngles[min(bellsRung, bellAngles.size - 1)] * PI / 180
        bellsRung++
        score += points
        val ax = (160 + 150 * sin(a)).toFloat(); val ay = (150 + 150 * cos(a)).toFloat()
        fx.burst(ax, ay, Color.Yellow, 22, 150f, 80f, 3.5f, 0.8f)
        fx.popup("+$points", ax, ay - 24, Color.Yellow, 22f)
        fx.flash(Color.Yellow, 0.15f)
        Haptics.heavy(); Sfx.win()
    }
}

@Composable
fun AltybakanScreen(onExit: () -> Unit) {
    val engine = remember { AltybakanEngine() }
    val pal = Pal.current
    GameContainer(GameId.Altybakan, engine, onExit, summary = { L10n.f("Bells: %d", engine.bellsRung) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("🔔 ${engine.bellsRung}", color = Color.Yellow, fontWeight = FontWeight.SemiBold)
                Text(L10n.f("Next bell: %d°", engine.nextBellDegrees.toInt()), color = pal.textSecondary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                if (engine.multiplier > 1) Text("🔥×${engine.multiplier}", color = Color(0xFFFF9500), fontWeight = FontWeight.SemiBold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Hearts(engine.lives, AltybakanEngine.MAX_LIVES)
            }
            val input = remember(engine) { object : FieldInput() { override fun onDown(x: Float, y: Float) = engine.tap() } }
            ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, fx = engine.fx, input = input,
                overlay = { if (!engine.started) StartPrompt() }) { drawSwing(engine) }
            Text(L10n.t("Tap as the swing passes the glowing spot to pump it higher. Reach the bells on both sides. Three mistimed taps end the ride."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private val Wood = Color(0xFF8C542B)
private val WoodDark = Color(0xFF61381A)

private fun Pen.drawSwing(e: AltybakanEngine) {
    val px = 160f; val py = 150f; val rope = 135f
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF5C9EEB), Color(0xFFFFD69E)), 0f, 380f), size = Size(320f, 460f))
    circle(254f, 62f, 22f, Color(0xFFFFF2B3))
    for ((x, y, w) in listOf(Triple(30f, 60f, 70f), Triple(150f, 30f, 54f), Triple(230f, 110f, 64f))) {
        box(x, y, w, 16f, Color.White.copy(alpha = 0.55f), 8f); oval(x + w * 0.2f, y - 9, w * 0.4f, 22f, Color.White.copy(alpha = 0.55f))
    }
    // Distant hills, a yurt, grass.
    val hills = Path().apply {
        moveTo(0f, 340f); quadraticTo(60f, 285f, 140f, 330f); quadraticTo(240f, 290f, 320f, 335f); lineTo(320f, 460f); lineTo(0f, 460f); close()
    }
    ds.drawPath(hills, Color(0xFF8CB366))
    yurt(262f, 345f)
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF6BA34D), Color(0xFF4D8038)), 358f, 460f), Offset(0f, 358f), Size(320f, 102f))
    for (k in 0 until 26) {
        val x = ((k * 53) % 320).toFloat(); val y = 366f + (k * 31) % 84
        line(x, y, x - 2, y - 6, Color(0xFF336626).copy(alpha = 0.7f), 1.3f); line(x, y, x + 2, y - 7, Color(0xFF336626).copy(alpha = 0.7f), 1.3f)
    }
    // Bells along the arc on both sides.
    val radius = 150f
    ds.drawArc(Color.White.copy(alpha = 0.22f), 2f, 176f, false, Offset(px - radius, py - radius), Size(radius * 2, radius * 2), style = Stroke(2f))
    for ((index, degrees) in AltybakanEngine.bellAngles.withIndex()) {
        val rung = index < e.bellsRung
        val isNext = index == min(e.bellsRung, AltybakanEngine.bellAngles.size - 1)
        for (side in listOf(-1.0, 1.0)) {
            val a = side * degrees * PI / 180
            bell(px + radius * sin(a).toFloat(), py + radius * cos(a).toFloat(), rung, isNext, index == e.bellsRung - 1 && side == e.lastRungSide, e.clock.toFloat())
        }
    }
    // The A-frame legs and brace.
    line(px, py - 8, 58f, 372f, WoodDark.copy(alpha = 0.55f), 11f); line(px, py - 8, 262f, 372f, WoodDark.copy(alpha = 0.55f), 11f)
    line(px, py - 8, 58f, 372f, Wood.copy(alpha = 0.75f), 7f); line(px, py - 8, 262f, 372f, Wood.copy(alpha = 0.75f), 7f)
    line(100f, 275f, 220f, 275f, Wood.copy(alpha = 0.6f), 5f)
    circle(px, py - 6, 9f, WoodDark); circle(px, py - 6, 4f, Color.Yellow.copy(alpha = 0.8f))
    // Glowing sweet spot on the ground arc, only while a tap would count.
    val glowing = e.armed && e.started
    for ((width, color, alpha) in listOf(Triple(e.zone, Color.White, 0.18f), Triple(e.perfectZone, Color.Yellow, 0.5f))) {
        val sweep = Math.toDegrees(width * 2).toFloat()
        ds.drawArc(color.copy(alpha = if (glowing) alpha else alpha * 0.4f), 90f - sweep / 2, sweep, false,
            Offset(px - rope - 6, py - rope - 6), Size((rope + 6) * 2, (rope + 6) * 2), style = Stroke(11f, cap = StrokeCap.Round))
    }
    // The swing itself.
    val sx = px + rope * sin(e.theta).toFloat(); val sy = py + rope * cos(e.theta).toFloat()
    line(px - 5, py, sx - 14, sy, Color(0xFFE0CC9E), 2.4f); line(px + 5, py, sx + 14, sy, Color(0xFFE0CC9E), 2.4f)
    xf(sx, sy, (-e.theta).toFloat()) {
        riders()
        box(-22f, -2f, 44f, 7f, Wood, 3f); box(-22f, -2f, 44f, 2.5f, Color.White.copy(alpha = 0.35f), 1f)
        listOf(Color.Red, Color.Yellow, Color(0xFF32ADE6), Color.Red, Color.Yellow).forEachIndexed { i, c -> box(-14f + i * 7, 1.5f, 4f, 2.5f, c, 0f) }
    }
}

private fun Pen.riders() {
    // Two children sitting side by side: a boy and a girl in festive chapans.
    data class Kid(val x: Float, val shirt: Color, val hat: Color, val hair: Color)
    for (k in listOf(Kid(-9f, Color(0xFF338CE6), Color(0xFF264DB3), Color(0xFF1A120D)), Kid(9f, Color(0xFFE63F66), Color(0xFFF2BF33), Color(0xFF40200F)))) {
        val x = k.x
        box(x - 7, -22f, 14f, 22f, k.shirt, 5f); box(x - 7, -10f, 14f, 3f, Color.White.copy(alpha = 0.7f), 1f)
        oval(x - 6.5f, -35f, 13f, 13f, Color(0xFFF7CCA3)); oval(x - 7, -37f, 14f, 9f, k.hair)
        box(x - 5.5f, -41f, 11f, 6f, k.hat, 3f)
        oval(x - 2.5f, -31f, 2f, 2f, Color.Black); oval(x + 1, -31f, 2f, 2f, Color.Black)
        box(x - 4, -1f, 3.5f, 9f, k.shirt.copy(alpha = 0.8f), 1.5f); box(x + 0.5f, -1f, 3.5f, 9f, k.shirt.copy(alpha = 0.8f), 1.5f)
    }
}

private fun Pen.bell(x: Float, y: Float, rung: Boolean, next: Boolean, swinging: Boolean, clock: Float) {
    val rot = if (swinging) sin(clock * 22) * 0.35f else 0f
    xf(x, y, rot, if (next) 1.15f else 0.85f) {
        if (next) circle(0f, 0f, 17f, Color.Yellow.copy(alpha = 0.28f))
        val body = Path().apply {
            moveTo(-9f, 7f); quadraticTo(-9f, -3f, -6f, -6f); quadraticTo(0f, -13f, 6f, -6f); quadraticTo(9f, -3f, 9f, 7f); close()
        }
        ds.drawPath(body, if (rung) Color.White.copy(alpha = 0.45f) else Color(0xFFFFC733))
        ds.drawPath(body, Color.Black.copy(alpha = 0.25f), style = Stroke(1f))
        circle(0f, 8.5f, 2.5f, if (rung) Color.Gray else Color(0xFFB36E1A))
        if (rung) label("✓", 0f, -1f, 8f, Color(0xFF34C759))
    }
}

private fun Pen.yurt(x: Float, y: Float) {
    box(x - 28, y - 16, 56f, 28f, Color(0xFFF2EBD6), 4f)
    val dome = Path().apply { moveTo(x - 30, y - 14); quadraticTo(x, y - 48, x + 30, y - 14); close() }
    ds.drawPath(dome, Color(0xFFFAF5E6)); ds.drawPath(dome, Color(0xFF3380A6), style = Stroke(2f))
    box(x - 6, y - 6, 12f, 18f, Color(0xFF3380A6), 3f)
    line(x - 28, y - 12, x + 28, y - 12, Color(0xFFD94D33), 2.5f)
}
