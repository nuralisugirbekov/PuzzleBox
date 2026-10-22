package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
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
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.ArcadeFX
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.games.kit.hsb
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// Асық ату — the traditional Kazakh knucklebone game. Asyks stand inside a ring; the player flicks a heavy
// "сақа" to knock them out. Every asyk that leaves the ring is won.
class AsykBody(val id: Int, var x: Float, var y: Float, val r: Float, val mass: Float, val dye: Int?, val side: Int, var angle: Float,
               var vx: Float = 0f, var vy: Float = 0f, var out: Boolean = false, var counted: Boolean = false)

/** Arrangements of asyks inside the ring, one family per level (cycling every 8 levels). */
object AsykLayouts {
    const val SPACING = 23f
    fun count(level: Int) = min(16, 7 + (level - 1) / 3)
    fun throwsFor(level: Int, count: Int) = max(3, Math.ceil(count * 0.5).toInt()) + (if (level < 4) 1 else 0)

    private fun rows(counts: List<Int>, dy: Float = 20f, dx: Float = 23f, ox: Float = 0f, oy: Float = 0f): List<Pair<Float, Float>> {
        val out = ArrayList<Pair<Float, Float>>()
        for ((k, c) in counts.withIndex()) {
            val y = (k - (counts.size - 1) / 2f) * dy
            for (i in 0 until c) out.add(((i - (c - 1) / 2f) * dx + ox) to (y + oy))
        }
        return out
    }

    /** Positions relative to the ring centre. */
    fun points(level: Int, n: Int): List<Pair<Float, Float>> {
        val s = SPACING
        var pts: List<Pair<Float, Float>> = when ((level - 1) % 8) {
            0 -> if (n <= 9) rows(listOf(n), dy = s) else rows(listOf(9, n - 9), dy = s)
            1 -> rows(listOf((n + 1) / 2, n / 2), dy = s)
            2 -> { val counts = ArrayList<Int>(); var total = 0; var row = 1; while (total < n) { val c = min(row, n - total); counts.add(c); total += c; row++ }; rows(counts) }
            3 -> {
                val arm = max(2, (n - 1) / 4)
                val p = arrayListOf(0f to 0f)
                for (k in 1..arm) for (sign in listOf(-1f, 1f)) { p.add(sign * k * s to 0f); p.add(0f to sign * k * s) }
                p
            }
            4 -> { val radius = min(88f, max(42f, n * s / (2 * PI.toFloat()))); (0 until n).map { cos(it.toFloat() / n * PI.toFloat() * 2) * radius to sin(it.toFloat() / n * PI.toFloat() * 2) * radius } }
            5 -> {
                val counts = ArrayList<Int>(); var total = 0; var row = 1; var growing = true
                while (total < n) {
                    val c = min(row, n - total); counts.add(c); total += c
                    if (growing) { row++; if (row > 4) { growing = false; row = 3 } } else row = max(1, row - 1)
                }
                rows(counts)
            }
            6 -> {
                val a = (n + 1) / 2; val b = n / 2
                rows(if (a > 3) listOf(3, a - 3) else listOf(a), ox = -62f) + rows(if (b > 3) listOf(3, b - 3) else listOf(b), ox = 62f)
            }
            else -> { // scattered, but the same every time for a given level
                val random = PuzzleRandom(level * 40503L)
                val p = ArrayList<Pair<Float, Float>>(); var tries = 0
                while (p.size < n && tries < 4000) {
                    tries++
                    val a = random.nextFloat() * PI.toFloat() * 2; val d = random.nextFloat() * 90f
                    val q = cos(a) * d to sin(a) * d
                    if (p.all { hypot(it.first - q.first, it.second - q.second) >= s }) p.add(q)
                }
                p
            }
        }
        // Never outside the ring.
        pts = pts.filter { hypot(it.first, it.second) <= AsykEngine.RING_RADIUS - 16 }.take(n)
        return pts
    }
}

class AsykEngine : FrameGame {
    companion object {
        const val W = 360f; const val H = 540f
        const val RING_X = 180f; const val RING_Y = 262f; const val RING_RADIUS = 122f
        const val START_X = 180f; const val START_Y = 486f
        val sideNames = listOf("Алшы", "Тәйкі", "Бүк", "Шік")
        const val LEVEL_COUNT = 40
        private const val LEVEL_KEY = "asykLevel"
    }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var level by mutableIntStateOf(1)
    val bodies = ArrayList<AsykBody>()
    var moving = false
    var aimX = 0f; var aimY = 0f; var hasAim = false
    val fx = ArcadeFX()
    var throwsLeft by mutableIntStateOf(0)
    var totalAsyks by mutableIntStateOf(0)
    var knocked by mutableIntStateOf(0)

    private var knockedThisShot = 0
    private var restTime = 0.0
    private var nextId = 0

    val hasNextLevel get() = level < LEVEL_COUNT

    init {
        level = Settings.prefs.getInt(LEVEL_KEY, 1).coerceIn(1, LEVEL_COUNT)
        restart()
    }

    override fun restart() { state = GameState.Playing; score = 0; fx.reset(); hasAim = false; moving = false; loadLevel() }

    fun selectLevel(v: Int) { if (v !in 1..LEVEL_COUNT) return; level = v; Settings.prefs.edit().putInt(LEVEL_KEY, v).apply(); restart() }
    fun nextLevel() = selectLevel(level + 1)

    private fun loadLevel() {
        bodies.clear(); nextId = 0; knocked = 0
        val n = AsykLayouts.count(level)
        val random = PuzzleRandom(level * 7177L)
        for ((i, q) in AsykLayouts.points(level, n).withIndex()) {
            bodies.add(AsykBody(nextId++, RING_X + q.first, RING_Y + q.second, 10.5f, 1f, i % 5, random.nextInt(4), (random.nextFloat() * 0.7f) - 0.35f))
        }
        totalAsyks = bodies.size
        throwsLeft = AsykLayouts.throwsFor(level, totalAsyks)
        placeSaqa()
    }

    private fun placeSaqa() {
        bodies.removeAll { it.dye == null }
        bodies.add(AsykBody(nextId++, START_X, START_Y, 14f, 2.4f, null, 0, 0f))
        knockedThisShot = 0
    }

    val saqa get() = bodies.firstOrNull { it.dye == null }
    val canAim get() = state == GameState.Playing && !moving && throwsLeft > 0

    /** Moves the сақа along the throwing line before a shot. */
    fun slide(x: Float) { if (!canAim) return; saqa?.let { it.x = min(W - 30, max(30f, x)) } }

    /** [dx], [dy] point from the сақа toward the finger: the throw goes that way. */
    fun updateAim(dx: Float, dy: Float) {
        if (!canAim) return
        if (hypot(dx, dy) < 12f) hasAim = false else { aimX = dx; aimY = dy; hasAim = true }
    }

    fun release() {
        val s = saqa
        if (!canAim || !hasAim || s == null) { hasAim = false; return }
        hasAim = false
        val length = max(1f, hypot(aimX, aimY))
        val speed = min(950f, length * 8)
        s.vx = aimX / length * speed; s.vy = aimY / length * speed
        throwsLeft--
        moving = true; restTime = 0.0
        Sfx.tap(); Haptics.tap()
    }

    override fun advance(dt: Double) {
        val total = min(0.05, max(0.0, dt))
        fx.update(total.toFloat())
        if (state != GameState.Playing || !moving) return
        var remaining = total
        while (remaining > 0) { val step = min(remaining, 1.0 / 240); physics(step.toFloat()); remaining -= step }
        val still = bodies.all { hypot(it.vx, it.vy) < 4f }
        restTime = if (still) restTime + total else 0.0
        if (restTime > 0.25) endShot()
    }

    private fun physics(dt: Float) {
        for (b in bodies) {
            var speed = hypot(b.vx, b.vy)
            if (speed <= 0f) continue
            // Rolling friction on hard steppe ground.
            val newSpeed = max(0f, speed - (if (b.dye == null) 300f else 420f) * dt)
            b.vx *= newSpeed / speed; b.vy *= newSpeed / speed; speed = newSpeed
            b.x += b.vx * dt; b.y += b.vy * dt
            b.angle += speed * dt * 0.04f * (if (b.id % 2 == 0) 1 else -1)
            // Field edges stop pieces dead.
            if (b.x < b.r || b.x > W - b.r || b.y < b.r || b.y > H - b.r) {
                b.x = min(W - b.r, max(b.r, b.x)); b.y = min(H - b.r, max(b.r, b.y)); b.vx = 0f; b.vy = 0f
            }
        }
        for (i in bodies.indices) for (j in i + 1 until bodies.size) {
            val a = bodies[i]; val b = bodies[j]
            val dx = b.x - a.x; val dy = b.y - a.y
            val distance = hypot(dx, dy); val minimum = a.r + b.r
            if (distance >= minimum || distance <= 0.001f) continue
            val nx = dx / distance; val ny = dy / distance
            val overlap = minimum - distance
            val total = a.mass + b.mass
            a.x -= nx * overlap * b.mass / total; a.y -= ny * overlap * b.mass / total
            b.x += nx * overlap * a.mass / total; b.y += ny * overlap * a.mass / total
            val relative = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
            if (relative <= 0) continue
            val impulse = (1 + 0.86f) * relative / (1 / a.mass + 1 / b.mass)
            a.vx -= impulse / a.mass * nx; a.vy -= impulse / a.mass * ny
            b.vx += impulse / b.mass * nx; b.vy += impulse / b.mass * ny
            if (relative > 120) { fx.burst(a.x + nx * a.r, a.y + ny * a.r, Color(0xFFD9BF8C), 6, 80f, 0f, 2.5f, 0.4f); Sfx.wrong() }
        }
        // Asyks that leave the ring are won; several in one throw pay a growing bonus.
        for (b in bodies) {
            if (b.dye == null || b.counted) continue
            if (hypot(b.x - RING_X, b.y - RING_Y) <= RING_RADIUS + b.r) continue
            b.out = true; b.counted = true
            knockedThisShot++; knocked++
            val alshy = b.side == 0
            val points = 100 + 50 * (knockedThisShot - 1) + (if (alshy) 50 else 0)
            score += points
            val label = if (knockedThisShot > 1) "+$points ×$knockedThisShot" else "+$points"
            fx.popup(if (alshy) "${sideNames[0]}! $label" else label, b.x, b.y - 18, if (knockedThisShot > 1) Color(0xFFFF9500) else Color.Yellow, if (knockedThisShot > 1) 20f else 17f)
            fx.burst(b.x, b.y, Color.Yellow, 14, 120f, 0f, 3f)
            if (knockedThisShot > 1) Sfx.win() else Sfx.point(); Haptics.success()
        }
    }

    private fun endShot() {
        moving = false
        for (b in bodies) { b.vx = 0f; b.vy = 0f }
        bodies.removeAll { it.out }
        val remaining = bodies.count { it.dye != null }
        if (remaining == 0) {
            score += throwsLeft * 75 + 200
            Settings.prefs.edit().putInt(LEVEL_KEY, min(LEVEL_COUNT, level + 1)).apply()
            state = GameState.GameOver(won = true)
        } else if (throwsLeft == 0) state = GameState.GameOver(won = false)
        else {
            if (knockedThisShot == 0) fx.popup(L10n.t("Missed!"), 180f, 430f, Color.White.copy(alpha = 0.8f), 16f)
            placeSaqa()
        }
    }
}

@Composable
fun AsykScreen(onExit: () -> Unit) {
    val engine = remember { AsykEngine() }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(GameId.Asyk, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.level) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box {
                    Text("▦ " + L10n.f("Level %d", engine.level), color = pal.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                        for (lv in 1..AsykEngine.LEVEL_COUNT) DropdownMenuItem(text = { Text(L10n.f("Level %d", lv)) }, onClick = { menu = false; engine.selectLevel(lv) })
                    }
                }
                Text(L10n.f("Out: %d / %d", engine.knocked, engine.totalAsyks), color = pal.accent, fontWeight = FontWeight.SemiBold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                // One mark per remaining throw.
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    repeat(max(engine.throwsLeft, 0)) {
                        Box(Modifier.size(16.dp, 10.dp).clip(CircleShape).background(Color(0xFFD92633)).border(1.5.dp, Color(0xFFFFD14D), CircleShape))
                    }
                }
            }
            val input = remember(engine) {
                object : FieldInput() {
                    var sx = 0f; var sy = 0f
                    override fun onDown(x: Float, y: Float) { sx = x; sy = y }
                    override fun onMove(x: Float, y: Float) {
                        val s = engine.saqa ?: return
                        if (hypot(sx - s.x, sy - s.y) < 46f) engine.updateAim(x - s.x, y - s.y) else if (sy > 430f) engine.slide(x)
                    }
                    override fun onUp(x: Float, y: Float, tapped: Boolean) = engine.release()
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 400.dp), fieldW = AsykEngine.W, fieldH = AsykEngine.H, fx = engine.fx, input = input) { drawAsyk(engine) }
            Text(L10n.t("Swipe from your saqa toward the asyks. Knock them all out of the ring before you run out of throws. Several in one throw earn a bonus."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private val Dyes = listOf(Color(0xFFF5E6C7), Color.Red, Color(0xFF3373F2), Color(0xFF33B366), Color(0xFFAF52DE))

private fun Pen.drawAsyk(e: AsykEngine) {
    // Packed steppe earth with scattered pebbles and grass.
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFFC79E6B), Color(0xFF9E754D)), 0f, AsykEngine.H), size = androidx.compose.ui.geometry.Size(AsykEngine.W, AsykEngine.H))
    for (k in 0 until 70) {
        val x = ((k * 137) % 360).toFloat(); val y = ((k * 89 + k * k * 7) % 540).toFloat()
        if (k % 3 == 0) for (blade in -1..1) line(x, y, x + blade * 4, y - 8, Color(0xFF738C40).copy(alpha = 0.7f), 1.5f)
        else oval(x, y, 3f + k % 3, 2f + k % 2, Color.Black.copy(alpha = 0.12f))
    }
    // The ring, scratched into the ground.
    val cx = AsykEngine.RING_X; val cy = AsykEngine.RING_Y; val r = AsykEngine.RING_RADIUS
    circle(cx, cy, r, Color(0xFFDBB880).copy(alpha = 0.5f)); circle(cx, cy, r, Color(0xFF664729), 4f)
    circle(cx, cy, r - 3, Color.White.copy(alpha = 0.25f), 1.5f)
    // The throwing line.
    val ly = AsykEngine.START_Y - 22
    var x = 24f
    while (x < AsykEngine.W - 24) { line(x, ly, min(x + 10, AsykEngine.W - 24), ly, Color.White.copy(alpha = 0.35f), 2f); x += 16f }
    val s = e.saqa
    if (e.hasAim && s != null) {
        val length = hypot(e.aimX, e.aimY)
        val power = min(1f, length * 8 / 950f)
        val ux = e.aimX / length; val uy = e.aimY / length
        val tint = hsb((0.33f * (1 - power)).toDouble(), 0.9f, 1f)
        for (k in 1..9) { val t = k / 9f; circle(s.x + ux * (26 + 190 * power * t), s.y + uy * (26 + 190 * power * t), 3f, tint.copy(alpha = 0.4f + 0.6f * t)) }
        circle(s.x, s.y, 22f, tint.copy(alpha = 0.7f), 2f)
    }
    for (b in e.bodies.sortedBy { if (it.dye == null) 1 else 0 }) piece(b)
}

/** Top-down knucklebone: a waisted bone shape with knuckles at both ends. */
private fun Pen.piece(b: AsykBody) {
    xf(b.x, b.y) {
        oval(-b.r * 0.9f, -b.r * 0.6f + 3, b.r * 1.8f, b.r * 1.4f, Color.Black.copy(alpha = 0.25f))
        xf(0f, 0f, b.angle) {
            val r = b.r
            val base = b.dye?.let { Dyes[it] } ?: Color(0xFFD92633)
            oval(-r, -r * 0.62f, r * 0.95f, r * 1.24f, base); oval(r * 0.05f, -r * 0.62f, r * 0.95f, r * 1.24f, base)
            box(-r * 0.55f, -r * 0.42f, r * 1.1f, r * 0.84f, base, 3f)
            oval(-r * 0.7f, -r * 0.5f, r * 0.6f, r * 0.35f, Color.White.copy(alpha = 0.35f))
            // The face that lands up: a hollow for бүк/шік, a ridge for алшы/тәйкі.
            if (b.side >= 2) oval(-r * 0.25f, -r * 0.22f, r * 0.5f, r * 0.44f, Color.Black.copy(alpha = 0.22f))
            else line(-r * 0.45f, if (b.side == 0) -r * 0.1f else r * 0.1f, r * 0.45f, if (b.side == 0) -r * 0.1f else r * 0.1f, Color.Black.copy(alpha = 0.25f), 1.5f)
            if (b.dye == null) { strokeOval(-r, -r * 0.62f, r * 0.95f, r * 1.24f, Color(0xFFFFD14D), 2f); strokeOval(r * 0.05f, -r * 0.62f, r * 0.95f, r * 1.24f, Color(0xFFFFD14D), 2f) }
        }
    }
}
