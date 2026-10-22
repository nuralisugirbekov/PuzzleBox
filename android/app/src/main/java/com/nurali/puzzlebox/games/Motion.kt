package com.nurali.puzzlebox.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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
import com.nurali.puzzlebox.games.kit.P2
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.R
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.games.kit.hsb
import com.nurali.puzzlebox.games.kit.rnd
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class MotionMode(val id: GameId, val hint: String, val bonusHint: String) {
    Slope(GameId.Slope, "Drag sideways to steer the rolling ball around holes.",
        "Grab gems in a row to build a combo. Blocks start moving as you speed up."),
    CirclePong(GameId.CirclePong, "Drag around the circle to catch the ball with your paddle.",
        "Hit the star with the ball for bonus points. The paddle shrinks as the rally grows."),
    SpaceDodge(GameId.SpaceDodge, "Drag the ship with one finger to dodge asteroids.",
        "Collect stars for points. A blue shield saves you from one hit."),
    EndlessClimb(GameId.EndlessClimb, "Drag sideways. Jump onto platforms and keep climbing.",
        "Springs launch you higher. Cracked platforms break after one jump."),
}

/** Slope: kind 0 block, 1 sliding block. Climb: 0 plain, 1 moving, 2 cracked, 3 spring. Pickups: 0 gem/star/coin, 1 shield. */
class MotionObj(var x: Float, var y: Float, var w: Float, var h: Float, var vx: Float = 0f, var vy: Float = 0f, var kind: Int = 0, var spin: Float = 0f) {
    val rect get() = R(x - w / 2, y - h / 2, w, h)
}

class MotionEngine(val mode: MotionMode) : FrameGame {
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    val fx = ArcadeFX()

    var px = 160f; var py = 365f
    var vx = 0f; var vy = 0f
    val obstacles = ArrayList<MotionObj>()
    val pickups = ArrayList<MotionObj>()
    val trail = ArrayList<P2>()

    var paddle = (PI / 2).toFloat()
    var rally = 0
    var combo = 0
    var shield = false
    var invulnerable = 0.0
    var squash = 0f
    var distance = 0f
    var elapsed = 0.0

    private var spawn = 0.0
    private var pickupSpawn = 0.0
    private var shieldSpawn = 0.0
    private var bonus = 0
    private var lastMilestone = 0

    init { restart() }

    /** Paddle half-width in radians; the target narrows as the rally grows. */
    val paddleHalfWidth get() = max(0.2f, 0.36f - rally * 0.006f)

    override fun restart() {
        state = GameState.Playing; score = 0; started = false
        px = 160f; py = 365f; vx = 0f; vy = 0f; obstacles.clear(); pickups.clear(); trail.clear()
        paddle = (PI / 2).toFloat(); rally = 0; combo = 0; shield = false; invulnerable = 0.0; squash = 0f
        distance = 0f; spawn = 1.0; pickupSpawn = 1.6; shieldSpawn = 9.0; elapsed = 0.0; bonus = 0; lastMilestone = 0
        fx.reset()
        when (mode) {
            MotionMode.CirclePong -> { px = 160f; py = 230f; vx = 65f; vy = 140f; placePongStar() }
            MotionMode.EndlessClimb -> {
                px = 160f; py = 355f; vy = -320f
                for (i in 0 until 7) obstacles.add(MotionObj(if (i == 0) 160f else rnd(75f, 245f), 390f - i * 65f, 95f, 10f))
            }
            else -> {}
        }
    }

    fun touch(x: Float, y: Float) {
        if (!started || state != GameState.Playing) return
        when (mode) {
            MotionMode.Slope, MotionMode.EndlessClimb -> px = x.coerceIn(33f, 287f)
            MotionMode.SpaceDodge -> { px = x.coerceIn(13f, 307f); py = y.coerceIn(18f, 442f) }
            MotionMode.CirclePong -> paddle = atan2(y - 230f, x - 160f)
        }
    }

    fun start() { if (state == GameState.Playing) started = true }

    override fun advance(dt: Double) {
        fx.update(min(0.08, dt).toFloat())
        if (!started || state != GameState.Playing) return
        val total = min(0.08, max(0.0, dt))
        var remainder = total
        while (remainder > 0 && state == GameState.Playing) {
            val step = min(remainder, 1.0 / 120); update(step); remainder -= step
        }
        squash = max(0f, squash - total.toFloat() * 5)
        trail.add(P2(px, py))
        if (trail.size > 14) trail.removeAt(0)
    }

    private fun lose() {
        fx.burst(px, py, Color(0xFFC6F31D), 30, 220f, 320f, 3.5f, 0.8f)
        fx.burst(px, py, Color.White, 12, 150f, 320f, 2f)
        fx.kick(9f); fx.flash(Color.Red, 0.3f)
        Haptics.error(); Sfx.lose()
        state = GameState.GameOver(won = false)
    }

    private fun addBonus(points: Int, x: Float, y: Float, color: Color = Color.Yellow) {
        bonus += points
        fx.popup("+$points", x, y - 14, color)
        fx.burst(x, y, color, 10, 120f, 120f, 2.5f, 0.5f)
    }

    /** Distance-based score plus collected bonuses; a short chime every 100 points. */
    private fun refreshScore(divisor: Float) {
        score = (distance / divisor).toInt() + bonus
        val milestone = (distance / divisor).toInt() / 100
        if (milestone > lastMilestone) {
            lastMilestone = milestone
            Sfx.point()
            fx.popup("${milestone * 100}", 160f, 90f, Color.White.copy(alpha = 0.8f), 26f)
        }
    }

    private fun update(dt: Double) {
        val d = dt.toFloat()
        elapsed += dt; spawn -= dt; pickupSpawn -= dt; shieldSpawn -= dt
        invulnerable = max(0.0, invulnerable - dt)
        when (mode) {
            MotionMode.Slope -> updateSlope(d)
            MotionMode.SpaceDodge -> updateSpace(d)
            MotionMode.CirclePong -> updatePong(d)
            MotionMode.EndlessClimb -> updateClimb(d)
        }
    }

    // MARK: Slope

    private val runSpeed get() = 110f + min(150f, distance / 60f)

    private fun updateSlope(d: Float) {
        val speed = runSpeed
        distance += speed * d
        if (spawn <= 0) {
            val block = MotionObj(rnd(60f, 260f), -35f, rnd(55f, 100f), 45f)
            // Faster runs bring sideways-sliding blocks.
            if (distance > 1800 && Random.nextFloat() < min(0.5f, (distance - 1800) / 6000 + 0.2f)) {
                block.kind = 1
                block.vx = (if (Random.nextBoolean()) 1 else -1) * rnd(40f, 75f)
            }
            obstacles.add(block)
            spawn = max(0.55, 0.9 - distance / 12000.0)
        }
        if (pickupSpawn <= 0) {
            val x = rnd(50f, 270f)
            if (obstacles.none { abs(it.x - x) < it.w / 2 + 20 && it.y < 40 }) pickups.add(MotionObj(x, -20f, 18f, 18f))
            pickupSpawn = rnd(0.8, 1.4)
        }
        for (o in obstacles) {
            o.y += speed * d
            if (o.kind == 1) {
                o.x += o.vx * d
                val half = o.w / 2
                if (o.x < 22 + half || o.x > 298 - half) o.vx *= -1
            }
        }
        for (p in pickups) { p.y += speed * d; p.spin += d * 3 }
        obstacles.removeAll { it.y > 500f }
        if (pickups.any { it.y > 480f }) combo = 0
        pickups.removeAll { it.y > 480f }
        collectPickups(22f) {
            combo++
            (10 * min(combo, 5)) to (if (combo >= 2) "×$combo" else null)
        }
        refreshScore(12f)
        for (o in obstacles) {
            val r = o.rect
            if (px > r.minX - 9 && px < r.maxX + 9 && py > r.minY - 9 && py < r.maxY + 9) { lose(); return }
        }
    }

    // MARK: Space Dodge

    private fun updateSpace(d: Float) {
        val speed = runSpeed
        distance += speed * d
        if (spawn <= 0) {
            val small = distance > 1200 && Random.nextBoolean()
            val radius = if (small) rnd(9f, 13f) else rnd(15f, 25f)
            val drift = if (small) rnd(-70f, 70f) else rnd(-25f, 25f)
            obstacles.add(MotionObj(rnd(20f, 300f), -30f, radius * 2, radius * 2, drift, if (small) speed * 0.5f else 0f, Random.nextInt(3), rnd(0f, (PI * 2).toFloat())))
            spawn = max(0.32, 0.55 - distance / 15000.0)
        }
        if (pickupSpawn <= 0) { pickups.add(MotionObj(rnd(30f, 290f), -20f, 18f, 18f)); pickupSpawn = rnd(1.0, 1.8) }
        if (shieldSpawn <= 0) {
            if (!shield) pickups.add(MotionObj(rnd(40f, 280f), -20f, 22f, 22f, kind = 1))
            shieldSpawn = rnd(12.0, 18.0)
        }
        for (o in obstacles) {
            o.y += (speed + o.vy) * d
            o.x += o.vx * d
            o.spin += o.vx * 0.01f * d + 0.4f * d
        }
        for (p in pickups) { p.y += speed * 0.8f * d; p.spin += d * 3 }
        obstacles.removeAll { it.y > 500f }
        pickups.removeAll { it.y > 480f }
        collectPickups(24f) { pickup ->
            if (pickup.kind == 1) {
                shield = true
                fx.popup(L10n.t("Shield!"), px, py - 30f, Color(0xFF32ADE6), 18f)
                0 to null
            } else 25 to null
        }
        refreshScore(12f)
        if (invulnerable > 0) return
        val hit = obstacles.indexOfFirst { hypot(px - it.x, py - it.y) < 10 + it.w / 2 }
        if (hit >= 0) {
            if (shield) {
                val rock = obstacles.removeAt(hit)
                shield = false; invulnerable = 1.0
                fx.burst(rock.x, rock.y, Color.Gray, 20, 180f, 0f, 3f)
                fx.burst(px, py, Color(0xFF32ADE6), 16, 140f, 0f, 2.5f)
                fx.kick(5f); Haptics.heavy(); Sfx.wrong()
            } else lose()
        }
    }

    // MARK: Circle Pong

    private fun placePongStar() {
        val angle = rnd(0f, (PI * 2).toFloat()); val radius = rnd(25f, 85f)
        pickups.clear(); pickups.add(MotionObj(160f + cos(angle) * radius, 230f + sin(angle) * radius, 20f, 20f))
    }

    private fun updatePong(d: Float) {
        px += vx * d; py += vy * d
        for (p in pickups) p.spin += d * 2
        pickups.firstOrNull()?.let { star ->
            if (hypot(star.x - px, star.y - py) < 20) {
                combo++
                addBonus(20 + 10 * min(combo, 5), star.x, star.y)
                Sfx.point(); Haptics.move()
                placePongStar()
            }
        }
        score = bonus
        val dx = px - 160f; val dy = py - 230f; val radius = hypot(dx, dy)
        if (radius < 124f) return
        val nx = dx / radius; val ny = dy / radius
        val dot = vx * nx + vy * ny
        if (dot <= 0) return
        val a = atan2(dy, dx)
        val delta = atan2(sin(a - paddle), cos(a - paddle))
        if (abs(delta) > paddleHalfWidth) { lose(); return }
        vx -= 2 * dot * nx; vy -= 2 * dot * ny
        // Hitting off-centre angles the return, so aiming at the star is a real skill.
        val turn = -delta * 0.9f + rnd(-0.08f, 0.08f)
        val x = vx
        vx = x * cos(turn) - vy * sin(turn); vy = x * sin(turn) + vy * cos(turn)
        val speed = min(320f, hypot(vx, vy) * 1.03f)
        val current = max(1f, hypot(vx, vy))
        vx *= speed / current; vy *= speed / current
        px = 160f + nx * 123f; py = 230f + ny * 123f
        rally++
        bonus += 10
        score = bonus
        fx.burst(px, py, Color(0xFFC6F31D), 8, 110f, 0f, 2.5f, 0.4f)
        if (rally % 10 == 0) { fx.popup(L10n.f("Rally %d!", rally), 160f, 200f, Color.White, 22f); Sfx.win() } else Sfx.tap()
        Haptics.tap()
    }

    // MARK: Endless Climb

    private fun climbPlatform(y: Float, above: MotionObj): MotionObj {
        val x = min(255f, max(65f, above.x + rnd(-95f, 95f)))
        val platform = MotionObj(x, y, 85f, 10f)
        val roll = Random.nextFloat()
        if (distance > 2500 && roll < 0.18f) platform.kind = 2
        else if (distance > 900 && roll < 0.42f) {
            platform.kind = 1
            platform.vx = (if (Random.nextBoolean()) 1 else -1) * rnd(40f, 70f + min(60f, distance / 100f))
        } else if (roll > 0.9f) platform.kind = 3
        if (platform.kind != 2 && Random.nextFloat() < 0.3f) pickups.add(MotionObj(x, y - 26f, 16f, 16f, platform.vx))
        // Narrower footholds the higher you climb.
        platform.w = max(62f, 85f - distance / 250f)
        return platform
    }

    private fun updateClimb(d: Float) {
        val previousY = py
        vy += 520 * d; py += vy * d
        for (o in obstacles) if (o.kind == 1) {
            o.x += o.vx * d
            if (o.x < 50f || o.x > 270f) o.vx *= -1
        }
        for (p in pickups) {
            p.x += p.vx * d
            if (p.x < 50f || p.x > 270f) p.vx *= -1
            p.spin += d * 3
        }
        if (vy > 0) {
            for ((index, platform) in obstacles.withIndex()) {
                if (abs(px - platform.x) >= platform.w / 2 + 8) continue
                if (!(previousY + 10 <= platform.y && py + 10 >= platform.y)) continue
                py = platform.y - 10
                squash = 1f
                when (platform.kind) {
                    3 -> {
                        vy = -540f
                        fx.burst(px, platform.y, Color.Yellow, 12, 140f, 300f, 2.5f)
                        Sfx.win(); Haptics.move()
                    }
                    2 -> {
                        vy = -320f
                        fx.burst(platform.x, platform.y, Color(0xFFBF8C59), 18, 120f, 500f, 3f)
                        obstacles.removeAt(index)
                        Sfx.wrong()
                    }
                    else -> { vy = -320f; Sfx.tap() }
                }
                break
            }
        }
        collectPickups(20f) { 15 to null }
        if (py < 220f) {
            val shift = 220f - py; py = 220f; distance += shift
            for (o in obstacles) o.y += shift
            for (p in pickups) p.y += shift
            obstacles.removeAll { it.y > 490f }
            pickups.removeAll { it.y > 490f }
            while (true) {
                val top = obstacles.minByOrNull { it.y } ?: break
                if (top.y <= -40f) break
                obstacles.add(climbPlatform(top.y - 65f, top))
            }
        }
        refreshScore(10f)
        if (py > 480f) lose()
    }

    // MARK: Pickups

    private fun collectPickups(radius: Float, reward: (MotionObj) -> Pair<Int, String?>) {
        val index = pickups.indexOfFirst { hypot(it.x - px, it.y - py) < radius }
        if (index < 0) return
        val pickup = pickups.removeAt(index)
        val (points, label) = reward(pickup)
        if (points > 0) {
            addBonus(points, pickup.x, pickup.y, if (mode == MotionMode.SpaceDodge) Color.White else Color.Yellow)
            Sfx.point()
        } else {
            fx.burst(pickup.x, pickup.y, Color(0xFF32ADE6), 14, 120f, 0f, 2.5f)
            Sfx.win()
        }
        if (label != null) fx.popup(label, pickup.x + 22f, pickup.y - 26f, Color(0xFFFF9500), 15f)
        Haptics.tap()
    }
}

@Composable
fun MotionScreen(mode: MotionMode, onExit: () -> Unit) {
    val engine = remember { MotionEngine(mode) }
    val pal = Pal.current
    GameContainer(mode.id, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            val input = remember(engine) {
                object : FieldInput() {
                    override fun onDown(x: Float, y: Float) = engine.touch(x, y)
                    override fun onMove(x: Float, y: Float) = engine.touch(x, y)
                    override fun onUp(x: Float, y: Float, tapped: Boolean) = engine.start()
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, fx = engine.fx, input = input,
                overlay = { if (!engine.started) StartPrompt() }) { drawMotion(engine) }
            Text(L10n.t(mode.hint), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
            Text(L10n.t(mode.bonusHint), color = pal.accent, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

private val Yellow = Color(0xFFFFCC00)
private val Cyan = Color(0xFF32ADE6)
private val Pink = Color(0xFFFF2D55)
private val Mint = Color(0xFF00C7BE)
private val Orange = Color(0xFFFF9500)
private val Lime = Color(0xFFC6F31D)

private fun hash(i: Int, salt: Int): Float {
    val v = sin(i * 12.9898 + salt * 78.233) * 43758.5453
    return (v - floor(v)).toFloat()
}

private fun Pen.bg(top: Color, bottom: Color) {
    ds.drawRect(Brush.verticalGradient(listOf(top, bottom), 0f, 460f), size = Size(320f, 460f))
}

private fun Pen.shinyBall(x: Float, y: Float, r: Float, light: Color, dark: Color) {
    circle(x + 1.5f, y + 2.5f, r, Color.Black.copy(alpha = 0.35f))
    shiny(x, y, r, light, dark)
}

private fun Pen.starShape(x: Float, y: Float, r: Float, spin: Float, color: Color) {
    val pts = (0 until 10).map { i ->
        val a = i * (PI / 5).toFloat() - (PI / 2).toFloat() + spin
        val len = if (i % 2 == 0) r else r * 0.45f
        Offset(x + cos(a) * len, y + sin(a) * len)
    }
    circle(x, y, r * 1.5f, color.copy(alpha = 0.18f))
    polygon(pts, color)
}

private fun Pen.gem(x: Float, y: Float, r: Float, spin: Float) {
    val w = r * (0.55f + 0.45f * abs(cos(spin)))
    circle(x, y, r * 1.4f, Mint.copy(alpha = 0.18f))
    polygon(listOf(Offset(x, y - r), Offset(x + w, y), Offset(x, y + r), Offset(x - w, y)), Mint)
}

private fun Pen.trailDots(e: MotionEngine, color: Color, radius: Float) {
    e.trail.forEachIndexed { i, p ->
        val t = i.toFloat() / max(1, e.trail.size)
        circle(p.x, p.y, radius * t, color.copy(alpha = t * 0.35f))
    }
}

private fun Pen.drawMotion(e: MotionEngine) {
    when (e.mode) {
        MotionMode.Slope -> {
            bg(Color(0xFF0D0824), Color(0xFF051429))
            ds.drawRect(Brush.verticalGradient(listOf(Cyan.copy(alpha = 0.03f), Cyan.copy(alpha = 0.14f)), 0f, 460f), Offset(22f, 0f), Size(276f, 460f))
            for (i in -1 until 10) {
                val y = i * 55f + e.distance % 55f
                line(22f, y, 298f, y, Cyan.copy(alpha = (0.08f + y / 460f * 0.25f).coerceIn(0f, 1f)), 1f)
            }
            for (x in listOf(91f, 160f, 229f)) line(x, 0f, x, 460f, Cyan.copy(alpha = 0.15f), 1f)
            for (x in listOf(22f, 298f)) { line(x, 0f, x, 460f, Pink.copy(alpha = 0.3f), 6f); line(x, 0f, x, 460f, Pink, 2f) }
            for (o in e.obstacles) {
                val edge = if (o.kind == 1) Orange else Pink
                val r = o.rect
                box(r.minX - 3, r.minY - 3, r.w + 6, r.h + 6, edge.copy(alpha = 0.2f), 8f)
                tile(r.minX, r.minY, r.w, r.h, Color(0xFF050505), Color(0xFF260524), 6f)
                strokeBox(r.minX, r.minY, r.w, r.h, edge, 2f, 6f)
                if (o.kind == 1) label(if (o.vx > 0) "›" else "‹", o.x, o.y, 22f, edge)
            }
            for (p in e.pickups) gem(p.x, p.y, 9f, p.spin)
            trailDots(e, Lime, 11f)
            shinyBall(e.px, e.py, 12f, Color.White, Lime)
            val a = e.distance / 12f
            circle(e.px + sin(a) * 6, e.py + cos(a) * 6, 2.5f, Color.Black.copy(alpha = 0.45f))
            if (e.combo >= 2) label("×${min(e.combo, 5)}", e.px + 26f, e.py - 16f, 15f, Mint)
        }
        MotionMode.CirclePong -> {
            bg(Color(0xFF0F0A29), Color(0xFF050512))
            var r = 30
            while (r <= 120) { circle(160f, 230f, r.toFloat(), Color.White.copy(alpha = 0.04f), 1f); r += 30 }
            circle(160f, 230f, 134f, Pink.copy(alpha = 0.35f), 2f)
            label("${e.rally}", 160f, 230f, 64f, Color.White.copy(alpha = 0.07f))
            for (p in e.pickups) starShape(p.x, p.y, 10f, p.spin, Yellow)
            val start = Math.toDegrees((e.paddle - e.paddleHalfWidth).toDouble()).toFloat()
            val sweep = Math.toDegrees((e.paddleHalfWidth * 2).toDouble()).toFloat()
            val tl = Offset(160f - 134f, 230f - 134f); val sz = Size(268f, 268f)
            ds.drawArc(Lime.copy(alpha = 0.3f), start, sweep, false, tl, sz, style = androidx.compose.ui.graphics.drawscope.Stroke(18f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
            ds.drawArc(Lime, start, sweep, false, tl, sz, style = androidx.compose.ui.graphics.drawscope.Stroke(10f, cap = androidx.compose.ui.graphics.StrokeCap.Round))
            trailDots(e, Color.White, 7f)
            shinyBall(e.px, e.py, 8f, Color.White, Color(0xFFB3B3B3))
        }
        MotionMode.SpaceDodge -> {
            bg(Color(0xFF050514), Color(0xFF140824))
            for (i in 0 until 40) {
                val layer = (i % 3 + 1).toFloat()
                val y = (hash(i, 1) * 460f + e.distance * 0.25f * layer) % 460f
                circle(hash(i, 2) * 320f, y, 0.5f * layer, Color.White.copy(alpha = 0.2f + 0.15f * layer))
            }
            for (o in e.obstacles) xf(o.x, o.y, o.spin) {
                val r = o.w / 2
                val pts = (0 until 9).map { k ->
                    val a = k / 9f * (PI * 2).toFloat()
                    val wobble = 0.82f + 0.18f * sin(k * (o.kind + 3) * 1.7f)
                    Offset(cos(a) * r * wobble, sin(a) * r * wobble)
                }
                polygon(pts, Color(0xFF8C7F85))
                oval(-r * 0.45f, -r * 0.35f, r * 0.5f, r * 0.45f, Color.Black.copy(alpha = 0.25f))
                oval(r * 0.15f, r * 0.2f, r * 0.3f, r * 0.3f, Color.Black.copy(alpha = 0.2f))
            }
            for (p in e.pickups) {
                if (p.kind == 1) {
                    circle(p.x, p.y, 16f, Cyan.copy(alpha = 0.2f)); circle(p.x, p.y, 11f, Cyan, 3f); label("🛡", p.x, p.y, 11f, Cyan)
                } else starShape(p.x, p.y, 9f, p.spin, Yellow)
            }
            val x = e.px; val y = e.py
            // Engine flame flickers behind the ship.
            val flame = 10 + 5 * abs(sin((e.elapsed * 30).toFloat()))
            polygon(listOf(Offset(x - 5, y + 8), Offset(x, y + 8 + flame), Offset(x + 5, y + 8)), Orange.copy(alpha = 0.85f))
            val hullAlpha = if (e.invulnerable > 0 && e.elapsed % 0.2 < 0.1) 0.35f else 1f
            polygon(listOf(Offset(x, y - 15), Offset(x - 12, y + 12), Offset(x, y + 6), Offset(x + 12, y + 12)), Color(0xFFE6F2FF).copy(alpha = hullAlpha))
            circle(x, y - 2, 3f, Cyan)
            if (e.shield) {
                val pulse = 1 + 0.06f * sin((e.elapsed * 6).toFloat())
                circle(x, y, 21f * pulse, Cyan.copy(alpha = 0.75f), 2.5f)
                circle(x, y, 21f * pulse, Cyan.copy(alpha = 0.12f))
            }
        }
        MotionMode.EndlessClimb -> {
            // The sky darkens into space as you climb.
            val height = min(1.0, e.distance / 6000.0)
            bg(hsb(0.6 + height * 0.15, 0.6f, (0.45 - height * 0.33).toFloat()), hsb(0.55 + height * 0.1, 0.5f, (0.25 - height * 0.18).toFloat()))
            for (i in 0 until 16) {
                val y = (hash(i, 3) * 460f + e.distance * 0.3f) % 460f
                circle(hash(i, 4) * 300f + 10f, y, 1.2f, Color.White.copy(alpha = (0.1 + height * 0.5).toFloat()))
            }
            for (o in e.obstacles) {
                val r = o.rect
                when (o.kind) {
                    1 -> { box(r.minX, r.minY, r.w, r.h, Orange, 5f); box(r.minX + 3, r.minY + 1, r.w - 6, 3f, Color.White.copy(alpha = 0.4f), 2f) }
                    2 -> {
                        box(r.minX, r.minY, r.w, r.h, Color(0xFF99734D), 5f)
                        line(r.midX - 10, r.minY, r.midX, r.maxY - 3, Color.Black.copy(alpha = 0.55f), 1.5f)
                        line(r.midX, r.maxY - 3, r.midX + 8, r.minY + 2, Color.Black.copy(alpha = 0.55f), 1.5f)
                    }
                    else -> { box(r.minX, r.minY, r.w, r.h, Mint, 5f); box(r.minX + 3, r.minY + 1, r.w - 6, 3f, Color.White.copy(alpha = 0.5f), 2f) }
                }
                if (o.kind == 3) {
                    for (k in 0 until 4) line(r.midX + (if (k % 2 == 0) -6 else 6), r.minY - k * 2.5f, r.midX + (if ((k + 1) % 2 == 0) -6 else 6), r.minY - (k + 1) * 2.5f, Yellow, 2f)
                    box(r.midX - 9, r.minY - 13, 18f, 4f, Color.Red, 2f)
                }
            }
            for (p in e.pickups) {
                val squeeze = abs(cos(p.spin))
                oval(p.x - 8 * squeeze, p.y - 8, 16 * squeeze, 16f, Yellow)
                strokeOval(p.x - 5 * squeeze, p.y - 5, 10 * squeeze, 10f, Orange, 1.5f)
            }
            trailDots(e, Lime, 8f)
            val s = e.squash
            val w = 20 * (1 + s * 0.3f); val h = 20 * (1 - s * 0.25f)
            val bx = e.px - w / 2; val by = e.py + 10 - h
            ds.drawOval(Brush.radialGradient(listOf(Color.White, Lime), Offset(bx + w / 2 - 3, by + h / 2 - 4), 14f), Offset(bx, by), Size(w, h))
            circle(bx + w / 2 - 4, by + h / 2 - 1, 2f, Color.Black); circle(bx + w / 2 + 4, by + h / 2 - 1, 2f, Color.Black)
        }
    }
}
