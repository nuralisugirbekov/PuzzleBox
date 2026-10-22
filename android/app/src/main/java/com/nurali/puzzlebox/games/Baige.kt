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
import androidx.compose.runtime.mutableFloatStateOf
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
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Бәйге — the long-distance horse race. A side-scrolling runner: tap to jump (hold for a higher jump),
// clear fences, rocks and ditches, collect coins and grab the golden whip for a burst of speed.
class BaigeThing(val id: Int, val kind: Kind, val d: Float, val w: Float, val h: Float, var taken: Boolean = false) {
    enum class Kind { Fence, Rock, Ditch, Coin, Boost }
}

class BaigeEngine : FrameGame {
    companion object {
        const val HORSE_X = 84f
        const val GROUND_Y = 338f
        const val MAX_LIVES = 3
        private const val GRAVITY = 1900f
        private const val JUMP_SPEED = 660f
    }

    private var bonus = 0
    override val score get() = (distance / 10).toInt() + bonus
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var distance by mutableFloatStateOf(0f)
    var height = 0f
    var verticalSpeed = 0f
    val things = ArrayList<BaigeThing>()
    var lives by mutableIntStateOf(MAX_LIVES)
    var coins by mutableIntStateOf(0)
    var boostLeft by mutableFloatStateOf(0f)
    var invulnerable = 0f
    var stumble = 0f
    var gait = 0f
    val fx = ArcadeFX()

    private var holding = false
    private var buffered = 0f
    private var nextD = 520f
    private var nextId = 0
    private var sinceBoost = 0f
    private var random = PuzzleRandom(5)
    private var strideClock = 0f

    val onGround get() = height <= 0.5f && verticalSpeed <= 0f
    val speed: Float get() { val base = 235 + min(150f, distance / 60); return base * (if (boostLeft > 0) 1.45f else 1f) * (if (stumble > 0) 0.55f else 1f) }

    init { restart() }

    override fun restart() {
        state = GameState.Playing; bonus = 0; started = false
        distance = 0f; height = 0f; verticalSpeed = 0f; things.clear(); lives = MAX_LIVES; coins = 0
        boostLeft = 0f; invulnerable = 0f; stumble = 0f; gait = 0f; holding = false; buffered = 0f
        nextD = 520f; nextId = 0; sinceBoost = 0f; strideClock = 0f
        random = PuzzleRandom(System.nanoTime())
        fx.reset()
    }

    fun press() {
        if (state != GameState.Playing) return
        if (!started) started = true
        holding = true
        if (onGround) jump() else buffered = 0.14f
    }

    fun release() { holding = false }

    private fun jump() {
        verticalSpeed = JUMP_SPEED; height = 1f; buffered = 0f
        Sfx.tap(); Haptics.tap()
        fx.burst(HORSE_X - 14, GROUND_Y, Color(0xFFCCB380), 6, 60f, -40f, 3f, 0.4f)
    }

    override fun advance(dt: Double) {
        val step = min(0.05, max(0.0, dt)).toFloat()
        fx.update(step)
        if (!started || state != GameState.Playing) return
        invulnerable = max(0f, invulnerable - step); stumble = max(0f, stumble - step)
        boostLeft = max(0f, boostLeft - step); buffered = max(0f, buffered - step)
        val v = speed
        distance += v * step
        gait += step * 12 * (v / 240)
        strideClock += step
        if (onGround && strideClock > 0.22f) strideClock = 0f

        // Gravity is lighter while the finger is down, so a long press makes a high jump.
        if (height > 0 || verticalSpeed > 0) {
            val g = GRAVITY * (if (holding && verticalSpeed > 0) 0.55f else 1f)
            verticalSpeed -= g * step
            height += verticalSpeed * step
            if (height <= 0) {
                height = 0f; verticalSpeed = 0f
                fx.burst(HORSE_X + 10, GROUND_Y, Color(0xFFCCB380), 5, 50f, -30f, 3f, 0.35f)
                if (buffered > 0) jump()
            }
        }
        if (boostLeft > 0) fx.burst(HORSE_X - 30, GROUND_Y - 26 - height, listOf(Color(0xFFFF9500), Color.Yellow).random(), 1, 40f, 0f, 3f, 0.35f)
        spawn(); interact()
        things.removeAll { it.d + it.w < distance - 160 }
    }

    private fun add(kind: BaigeThing.Kind, d: Float, w: Float, h: Float) { things.add(BaigeThing(nextId++, kind, d, w, h)) }

    private fun arc(center: Float, count: Int = 5, peak: Float = 92f) {
        for (i in 0 until count) { val t = i.toFloat() / (count - 1) * 2 - 1; add(BaigeThing.Kind.Coin, center + t * 70, 14f, 26 + peak * (1 - t * t)) }
    }

    private fun spawn() {
        val level = min(1f, distance / 6000)
        while (nextD < distance + 560) {
            val pick = random.nextInt(100)
            var next = nextD
            when {
                pick < 30 -> { add(BaigeThing.Kind.Fence, nextD, 24f, 36f); arc(nextD + 12); next += 24 }
                pick < 52 -> { add(BaigeThing.Kind.Rock, nextD, 28f, 24f); arc(nextD + 14, 4, 70f); next += 28 }
                pick < 72 -> { val width = 74 + level * 40; add(BaigeThing.Kind.Ditch, nextD, width, 0f); arc(nextD + width / 2, 5, 100f); next += width }
                pick < 88 -> {
                    // A rock quickly followed by a fence: two short jumps.
                    add(BaigeThing.Kind.Rock, nextD, 28f, 24f); add(BaigeThing.Kind.Fence, nextD + 130, 24f, 36f)
                    arc(nextD + 65, 3, 55f); next += 154
                }
                else -> { for (i in 0 until 6) add(BaigeThing.Kind.Coin, nextD + i * 30, 14f, 24f); next += 180 } // A breather.
            }
            sinceBoost += next - nextD
            if (sinceBoost > 1500 && pick > 40) { sinceBoost = 0f; add(BaigeThing.Kind.Boost, next + 90, 22f, 54f + random.nextInt(0, 31)); next += 140 }
            // Leave room to land and read the next obstacle: more at higher speed.
            nextD = next + max(200f, speed * 0.78f) + random.nextInt(0, 121) * (1 - level)
        }
    }

    private fun interact() {
        val hx = HORSE_X + distance
        for (i in things.indices) {
            val t = things[i]
            if (t.taken) continue
            when (t.kind) {
                BaigeThing.Kind.Coin -> {
                    // A generous pick-up box around the horse's body.
                    if (!(abs(t.d - hx) < 24 && t.h >= height - 14 && t.h <= height + 60)) continue
                    t.taken = true; coins++
                    val points = 10 * (if (boostLeft > 0) 2 else 1)
                    bonus += points
                    fx.popup("+$points", HORSE_X + 20, GROUND_Y - t.h - 18, Color.Yellow, 15f)
                    fx.burst(HORSE_X + 10, GROUND_Y - t.h, Color.Yellow, 6, 80f, 40f, 2.5f, 0.4f)
                    Sfx.point()
                }
                BaigeThing.Kind.Boost -> {
                    if (!(abs(t.d - hx) < 28 && t.h >= height - 20 && t.h <= height + 70)) continue
                    t.taken = true
                    boostLeft = 3.5f; invulnerable = max(invulnerable, 3.5f); bonus += 50
                    fx.popup(L10n.t("Speed up!"), HORSE_X + 30, GROUND_Y - 90, Color(0xFFFF9500), 19f)
                    fx.flash(Color(0xFFFF9500), 0.2f)
                    Haptics.heavy(); Sfx.win()
                }
                BaigeThing.Kind.Fence, BaigeThing.Kind.Rock -> {
                    if (invulnerable > 0) continue
                    if (hx + 14 > t.d && hx - 14 < t.d + t.w && height < t.h - 4) hit(t, false)
                }
                BaigeThing.Kind.Ditch -> {
                    if (invulnerable > 0) continue
                    // Falling in needs the horse to be low while over the middle of the gap.
                    if (hx > t.d + 8 && hx < t.d + t.w - 8 && height < 6) hit(t, true)
                }
            }
        }
    }

    private fun hit(t: BaigeThing, ditch: Boolean) {
        lives--
        invulnerable = 1.5f; stumble = 0.6f
        if (ditch) { verticalSpeed = 560f; height = 2f } else t.taken = true
        fx.burst(HORSE_X + 16, GROUND_Y - 24 - height, Color(0xFFFF9500), 16, 140f, 120f, 3f, 0.6f)
        fx.kick(7f); fx.flash(Color.Red, 0.22f)
        Haptics.error(); Sfx.wrong()
        if (lives <= 0) state = GameState.GameOver(won = distance > 1500)
    }
}

@Composable
fun BaigeScreen(onExit: () -> Unit) {
    val engine = remember { BaigeEngine() }
    val pal = Pal.current
    GameContainer(GameId.Baige, engine, onExit, summary = { L10n.f("Distance: %d m", (engine.distance / 10).toInt()) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("→ " + L10n.f("%d m", (engine.distance / 10).toInt()), color = pal.accent, fontWeight = FontWeight.SemiBold)
                Text("◉ ${engine.coins}", color = Color.Yellow, fontWeight = FontWeight.SemiBold)
                if (engine.boostLeft > 0) Text("⚡ %.1f".format(engine.boostLeft), color = Color(0xFFFF9500), fontWeight = FontWeight.SemiBold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Hearts(engine.lives, BaigeEngine.MAX_LIVES)
            }
            val input = remember(engine) {
                object : FieldInput() {
                    override fun onDown(x: Float, y: Float) = engine.press()
                    override fun onUp(x: Float, y: Float, tapped: Boolean) = engine.release()
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, fx = engine.fx, input = input,
                overlay = { if (!engine.started) StartPrompt() }) { drawRace(engine) }
            Text(L10n.t("Tap to jump, hold to jump higher. Clear fences, rocks and ditches, collect coins and grab the golden whip for a burst of speed."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private fun screenX(e: BaigeEngine, d: Float) = BaigeEngine.HORSE_X + d - e.distance

private fun Pen.drawRace(e: BaigeEngine) {
    val ground = BaigeEngine.GROUND_Y; val dist = e.distance
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF66B3FA), Color(0xFFFFE0AD)), 0f, ground), size = Size(320f, 460f))
    circle(261f, 69f, 23f, Color(0xFFFFF5BF))
    // Clouds, mountains and yurts at different parallax speeds.
    for (k in 0 until 4) {
        val x = (k * 150f - dist * 0.05f) % 600f; val cx = if (x < -90) x + 600 else x
        val cy = 70f + (k * 37) % 90
        box(cx, cy, 80f, 16f, Color.White.copy(alpha = 0.6f), 8f); oval(cx + 18, cy - 10, 36f, 26f, Color.White.copy(alpha = 0.6f))
    }
    for (layer in 0 until 2) {
        val factor = if (layer == 0) 0.12f else 0.28f; val period = if (layer == 0) 420f else 330f
        val tone = if (layer == 0) Color(0xFF8C9EBA) else Color(0xFF66947F)
        val base = (-(dist * factor)) % period
        for (k in -1..3) {
            val x0 = base + k * period
            val peak = ground - (if (layer == 0) 190 else 110) - ((k + 8) * 17) % 30
            polygon(listOf(Offset(x0, ground - 30), Offset(x0 + period * 0.45f, peak), Offset(x0 + period, ground - 30)), tone)
            if (layer == 0) polygon(listOf(Offset(x0 + period * 0.36f, ground - 150), Offset(x0 + period * 0.45f, peak), Offset(x0 + period * 0.54f, ground - 150)), Color.White.copy(alpha = 0.85f))
        }
    }
    val yurtBase = (-(dist * 0.5f)) % 520f
    for (k in 0..1) yurt(yurtBase + k * 520f + 200f, ground - 8)
    // Ground with the ditches cut out of it.
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF73B34D), Color(0xFF4D8033)), ground, 460f), Offset(0f, ground), Size(320f, 460f - ground))
    box(0f, ground, 320f, 6f, Color(0xFF8CCC59), 0f)
    val tuftBase = (-dist) % 40f
    for (k in -1..8) {
        val x = tuftBase + k * 40f
        for (blade in -1..1) line(x, ground + 22 + (k % 3 + 3) % 3 * 12, x + blade * 3, ground + 14 + (k % 3 + 3) % 3 * 12, Color(0xFF336624).copy(alpha = 0.7f), 1.5f)
    }
    for (t in e.things) if (t.kind == BaigeThing.Kind.Ditch) {
        val x = screenX(e, t.d)
        if (!(x < 340 && x + t.w > -20)) continue
        box(x, ground, t.w, 460f - ground, Color(0xFF2E1A0F), 0f)
        ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF4D2E1A), Color(0xFF1F120A)), ground, ground + 14), Offset(x, ground), Size(t.w, 14f))
        for (edge in listOf(x, x + t.w - 5)) box(edge, ground - 3, 5f, 8f, Color(0xFF66A647), 2f)
    }
    for (t in e.things) {
        if (t.taken) continue
        val x = screenX(e, t.d)
        if (!(x > -80 && x < 360)) continue
        when (t.kind) {
            BaigeThing.Kind.Fence -> fence(x, t.w, t.h, ground)
            BaigeThing.Kind.Rock -> rock(x, t.w, t.h, ground)
            BaigeThing.Kind.Coin -> coin(e, x, ground - t.h, t.id.toFloat())
            BaigeThing.Kind.Boost -> boost(e, x, ground - t.h)
            BaigeThing.Kind.Ditch -> {}
        }
    }
    // Horse and rider; blinking while protected (but steady glow during a boost).
    val blink = e.invulnerable > 0 && e.boostLeft == 0f && (e.invulnerable * 12).toInt() % 2 == 0
    if (!blink) {
        if (e.boostLeft > 0) {
            oval(BaigeEngine.HORSE_X - 52, ground - e.height - 62, 112f, 80f, Color(0xFFFF9500).copy(alpha = 0.28f))
            for (k in 1..4) { val y = ground - e.height - 14 - k * 9; line(BaigeEngine.HORSE_X - 34 - k * 4, y, BaigeEngine.HORSE_X - 70 - k * 8, y, Color.White.copy(alpha = 0.7f), 2f) }
        }
        galloper(e, BaigeEngine.HORSE_X, ground - e.height)
    }
}

private fun Pen.fence(x: Float, w: Float, h: Float, ground: Float) {
    val wood = Color(0xFF9E6633)
    oval(x - 4, ground - 3, w + 8, 8f, Color.Black.copy(alpha = 0.2f))
    for (px in listOf(x, x + w - 5)) box(px, ground - h, 5f, h, wood, 2f)
    for (ry in listOf(ground - h + 6, ground - h * 0.5f)) box(x - 2, ry, w + 4, 5f, wood.copy(alpha = 0.9f), 2f)
    box(x + w / 2 - 3, ground - h - 2, 6f, 8f, Color(0xFFE64040), 0f)
}

private fun Pen.rock(x: Float, w: Float, h: Float, ground: Float) {
    val path = Path().apply { moveTo(x, ground); quadraticTo(x + 1, ground - h * 0.9f, x + w * 0.35f, ground - h); quadraticTo(x + w + 3, ground - h * 0.8f, x + w, ground); close() }
    ds.drawPath(path, Brush.linearGradient(listOf(Color(0xFFB8B8B8), Color(0xFF737373)), Offset(x, ground - h), Offset(x + w, ground)))
    oval(x + w * 0.22f, ground - h * 0.75f, w * 0.22f, h * 0.2f, Color.White.copy(alpha = 0.4f))
}

private fun Pen.coin(e: BaigeEngine, x: Float, y: Float, phase: Float) {
    val squash = max(0.2f, abs(cos(e.gait * 0.4f + phase)))
    oval(x - 8 * squash - 3, y - 11, 16 * squash + 6, 22f, Color.Yellow.copy(alpha = 0.22f))
    oval(x - 8 * squash, y - 8, 16 * squash, 16f, Color(0xFFFFCC33))
    strokeOval(x - 5 * squash, y - 5, 10 * squash, 10f, Color(0xFFD98C1A), 1.5f)
}

private fun Pen.boost(e: BaigeEngine, x: Float, y: Float) {
    val pulse = 1 + 0.12f * sin(e.gait * 0.5f)
    circle(x, y, 22 * pulse, Color(0xFFFF9500).copy(alpha = 0.28f))
    ds.drawCircle(Brush.verticalGradient(listOf(Color.Yellow, Color(0xFFFF9500)), y - 14, y + 14), 14f, Offset(x, y))
    polygon(listOf(Offset(x + 2, y - 9), Offset(x - 5, y + 1), Offset(x, y + 1), Offset(x - 2, y + 9), Offset(x + 5, y - 2), Offset(x, y - 2)), Color.White)
}

private fun Pen.yurt(x: Float, y: Float) {
    box(x - 26, y - 18, 52f, 26f, Color(0xFFF5EDD9), 4f)
    val dome = Path().apply { moveTo(x - 28, y - 16); quadraticTo(x, y - 46, x + 28, y - 16); close() }
    ds.drawPath(dome, Color(0xFFFCF7EB)); ds.drawPath(dome, Color(0xFF3380A6), style = Stroke(2f))
    box(x - 5, y - 8, 10f, 16f, Color(0xFF3380A6), 3f)
}

/** Side view of a galloping horse with a young rider. */
private fun Pen.galloper(e: BaigeEngine, px: Float, py: Float) {
    val airborne = e.height > 2
    val phase = e.gait
    oval(px - 30, BaigeEngine.GROUND_Y - 3, 60f, 8f, Color.Black.copy(alpha = max(0.05f, 0.22f - e.height / 600)))
    val coat = Color(0xFF804D29); val dark = Color(0xFF522E17)
    xf(px, py) {
        // Tail streams behind.
        ds.drawPath(Path().apply { moveTo(-26f, -34f); cubicTo(-38f, -42f, -46f, -34f, -52f, -22f + sin(phase * 1.3f) * 4) }, Color(0xFF1F140D), style = Stroke(6f, cap = StrokeCap.Round))
        // Legs: far pair first, then body, then near pair.
        fun leg(hipX: Float, offset: Float, near: Boolean) {
            val swing = if (airborne) (if (hipX > 0) 0.9f else -0.9f) else sin(phase + offset) * 0.95f
            val upper = 12f; val lower = 13f
            val hx = hipX; val hy = -16f
            val kx = hx + sin(swing) * upper; val ky = hy + cos(swing) * upper
            val bend = if (airborne) (if (hipX > 0) 0.2f else 1.1f) else swing - 0.6f * sin(phase + offset + 1.2f)
            val ox = kx + sin(bend) * lower; val oy = min(0f, ky + cos(bend) * lower)
            polyline(listOf(Offset(hx, hy), Offset(kx, ky), Offset(ox, oy)), if (near) coat else dark, if (near) 5f else 4.5f)
            oval(ox - 2.5f, oy - 2, 5f, 4f, Color.Black.copy(alpha = 0.6f))
        }
        leg(-20f, PI_F, false); leg(18f, 0f, false)
        ds.drawOval(Brush.verticalGradient(listOf(coat, dark), -40f, -12f), Offset(-30f, -40f), Size(62f, 28f))
        polygon(listOf(Offset(18f, -36f), Offset(32f, -56f), Offset(40f, -50f), Offset(28f, -22f)), coat)
        xf(0f, 0f, 0.45f) { oval(30f, -64f, 24f, 13f, coat) }
        oval(41f, -52f, 3.5f, 3.5f, Color.Black)
        polygon(listOf(Offset(32f, -56f), Offset(30f, -66f), Offset(37f, -58f)), dark)
        ds.drawPath(Path().apply { moveTo(34f, -58f); cubicTo(22f, -62f + sin(phase * 1.4f) * 2, 18f, -50f, 16f, -38f) }, Color(0xFF1F140D), style = Stroke(5f, cap = StrokeCap.Round))
        leg(-16f, PI_F * 0.5f, true); leg(22f, -PI_F * 0.5f, true)
        // Saddle cloth and the young rider leaning forward.
        box(-8f, -43f, 22f, 10f, Color(0xFFD92E40), 3f)
        box(-6f, -39f, 18f, 2f, Color(0xFFFFD94D), 0f)
        xf(0f, 0f, 0.35f) { oval(-3f, -66f, 14f, 24f, Color(0xFF3380E6)) }
        oval(8f, -75f, 11f, 11f, Color(0xFFF5C79E))
        box(7.5f, -80f, 12f, 7f, Color(0xFFFFD940), 3f)
        line(14f, -58f, 38f, -52f, Color.Black.copy(alpha = 0.6f), 1.2f)
    }
}

private const val PI_F = 3.1415927f
