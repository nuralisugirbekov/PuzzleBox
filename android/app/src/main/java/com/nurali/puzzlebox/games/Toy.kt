package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
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
import com.nurali.puzzlebox.games.kit.P2
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.games.kit.hsb
import com.nurali.puzzlebox.games.kit.rnd
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class ToyMode(val id: GameId, val hint: String, val maxLives: Int = 3) {
    BasketShot(GameId.BasketShot, "Pull back from the ball and release to throw in the opposite direction."),
    BottleFlip(GameId.BottleFlip, "Swipe up from the bottle. Land upright after a full flip."),
    MiniGolf(GameId.MiniGolf, "Pull back from the ball and release. Sink it in 3 shots or fewer."),
    Plinko(GameId.Plinko, "Drag across the top and release. Aim for the highlighted bin.", 5),
    RopeCut(GameId.RopeCut, "Swipe across ropes to cut them. Swing the candy into the goal."),
    DrawBridge(GameId.DrawBridge, "Draw a bridge between the platforms, then tap Roll."),
}

class ToySeg(var ax: Float, var ay: Float, var bx: Float, var by: Float)

/** Endless arcade run: every success raises the level, consecutive successes multiply points, and misses cost lives. */
class ToyEngine(val mode: ToyMode) : FrameGame {
    private enum class Outcome { Success, Safe, Miss }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var lives by mutableIntStateOf(3)
    var streak by mutableIntStateOf(0)
    var successes by mutableIntStateOf(0)
    var notice by mutableStateOf("")
    var launchedState by mutableStateOf(false)
    var windState by mutableStateOf(0f)
    val fx = ArcadeFX()

    var bx = 70f; var by = 380f
    var vx = 0f; var vy = 0f
    var tx = 245f; var ty = 190f
    var launched = false
        private set(value) { field = value; launchedState = value }
    var angle = 0f
    val trail = ArrayList<P2>()
    val bridge = ArrayList<P2>()
    var ropes = booleanArrayOf(true, true)
    var anchors = listOf(P2(75f, 60f), P2(245f, 60f))
    var selectedBin = 3

    var wind = 0f
        private set(value) { field = value; windState = value }
    var strokes = 0
    var obstacles = listOf<ToySeg>()
    var movingBar: ToySeg? = null
    var goldPegs = mutableSetOf<Int>()
    var stars = ArrayList<P2>()
    var leftTop = 200f; var leftEdge = 90f; var rightTop = 300f; var rightEdge = 230f
    var inkUsed = 0f; var inkMax = 420f
    var padX = 200f; var padWidth = 56f
    var targetHalfWidth = 30f
    val pegs: List<P2> = (0 until 7).flatMap { row ->
        (0 until 6).mapNotNull { col ->
            val x = col * 50f + (if (row % 2 == 0) 35f else 60f)
            if (x < 300f) P2(x, 95f + row * 38f) else null
        }
    }

    private var bridgeSegments = listOf<ToySeg>()
    private var ropeLengths = listOf<Float>()
    private var spin = 0f
    private var flight = 0.0
    private var delay = 0.0
    private var trailClock = 0.0
    private var clock = 0.0
    private var movingBaseX = 0f
    private var movingAmplitude = 0f
    private var touchedRim = false
    var cutLast: P2? = null

    val level get() = successes + 1
    val nextMultiplier get() = multiplier(streak + 1)
    val maxLives get() = mode.maxLives
    val binValues get() = (0 until 6).map { i -> if (i == selectedBin) 100 + 25 * (level - 1) else if (abs(i - selectedBin) == 1) 30 else 10 }
    val leftConnector get() = P2(leftEdge - 10, leftTop - 5)
    val rightConnector get() = P2(rightEdge + 10, rightTop - 5)

    init { restart() }

    private fun multiplier(s: Int) = if (s >= 5) 3 else if (s >= 3) 2 else 1

    override fun restart() {
        state = GameState.Playing; score = 0; started = false; successes = 0; streak = 0; delay = 0.0
        lives = mode.maxLives; fx.reset(); clock = 0.0
        prepare()
    }

    private fun prepare() {
        bx = 70f; by = 380f; vx = 0f; vy = 0f; tx = 245f; ty = 190f
        launched = false; angle = 0f; spin = 0f; flight = 0.0; trail.clear(); bridge.clear(); bridgeSegments = emptyList()
        notice = ""; strokes = 0; wind = 0f; movingAmplitude = 0f; movingBar = null; touchedRim = false; cutLast = null
        stars = ArrayList(); inkUsed = 0f
        val lv = level.toFloat()
        when (mode) {
            ToyMode.BasketShot -> {
                bx = 80f; by = 310f
                val spread = min(1f, (lv - 1) / 5)
                tx = rnd(225f - 35 * spread, 250f + 12 * spread)
                ty = rnd(190f - 40 * spread, 190f + 50 * spread)
                if (level >= 3) wind = rnd(20f, min(90f, 20 + lv * 8)) * (if (Random.nextBoolean()) 1 else -1)
                if (level >= 5) movingAmplitude = min(40f, 15 + lv * 3)
                movingBaseX = min(282 - movingAmplitude, max(200f, tx)); tx = movingBaseX
            }
            ToyMode.BottleFlip -> {
                bx = 130f; by = 370f
                padWidth = max(30f, 62 - lv * 4)
                padX = rnd(40f, 280f)
                while (abs(padX - 130) < 40) padX = rnd(40f, 280f)
            }
            ToyMode.MiniGolf -> layoutGolf()
            ToyMode.Plinko -> { bx = 160f; by = 35f; selectedBin = Random.nextInt(6); goldPegs = pegs.indices.shuffled().take(4).toMutableSet() }
            ToyMode.RopeCut -> layoutRopes()
            ToyMode.DrawBridge -> layoutBridge()
        }
    }

    private fun layoutGolf() {
        bx = rnd(60f, 260f); by = 405f
        tx = rnd(45f, 275f); ty = rnd(70f, 140f)
        val templates = listOf(
            listOf(ToySeg(100f, 240f, 225f, 240f)),
            listOf(ToySeg(10f, 280f, 170f, 280f), ToySeg(150f, 190f, 310f, 190f)),
            listOf(ToySeg(55f, 265f, 145f, 215f), ToySeg(175f, 215f, 265f, 265f)),
            listOf(ToySeg(130f, 200f, 190f, 200f), ToySeg(190f, 200f, 190f, 260f), ToySeg(190f, 260f, 130f, 260f), ToySeg(130f, 260f, 130f, 200f)),
            listOf(ToySeg(10f, 230f, 120f, 230f), ToySeg(200f, 230f, 310f, 230f)),
        )
        var layout = if (level == 1) templates[0] else templates[Random.nextInt(templates.size)]
        // Mirror half of the layouts so they feel less familiar.
        if (level > 1 && Random.nextBoolean()) layout = layout.map { ToySeg(320 - it.ax, it.ay, 320 - it.bx, it.by) }
        obstacles = layout
        if (level >= 3) { movingBaseX = 160f; movingAmplitude = 105f; movingBar = ToySeg(125f, 340f, 195f, 340f) }
    }

    private fun layoutRopes() {
        bx = 160f; by = 210f
        anchors = if (level >= 3) listOf(P2(rnd(45f, 100f), rnd(55f, 85f)), P2(rnd(140f, 180f), rnd(35f, 50f)), P2(rnd(220f, 275f), rnd(55f, 85f)))
        else listOf(P2(rnd(55f, 95f), rnd(50f, 80f)), P2(rnd(225f, 265f), rnd(50f, 80f)))
        ropes = BooleanArray(anchors.size) { true }
        ropeLengths = anchors.map { hypot(bx - it.x, by - it.y) }
        targetHalfWidth = max(20f, 30f - (level - 1) * 2)
        val side = Random.nextBoolean()
        movingBaseX = if (side) rnd(210f, 270f) else rnd(50f, 110f)
        tx = movingBaseX; ty = 400f
        if (level >= 4) { movingAmplitude = min(45f, 15f + level * 4); movingBaseX = min(320 - movingAmplitude - 30, max(movingAmplitude + 30, movingBaseX)) }
        // Stars sit on the arc the candy follows when it swings from one rope.
        val swings = anchors.indices.filter { abs(atan2(bx - anchors[it].x, by - anchors[it].y)) > 0.35f }
        stars = ArrayList(swings.shuffled().take(if (level >= 2) 2 else 1).map { i ->
            val a = anchors[i]; val length = ropeLengths[i]
            val start = atan2(bx - a.x, by - a.y)
            val theta = start * rnd(-0.8f, 0.4f)
            P2(a.x + sin(theta) * length, a.y + cos(theta) * length)
        })
    }

    private fun layoutBridge() {
        leftTop = rnd(170f, 235f); leftEdge = rnd(75f, 105f)
        rightTop = min(370f, leftTop + rnd(40f, min(140f, 50f + level * 15f)))
        rightEdge = rnd(max(leftEdge + 100, 195f), 245f)
        bx = leftEdge - 45; by = leftTop - 12
        tx = rightEdge + 40; ty = rightTop - 12
        val l = leftConnector; val r = rightConnector
        val gap = hypot(r.x - l.x, r.y - l.y)
        inkMax = max(gap * 1.45f, 480f - level * 25f)
        val mx = (l.x + r.x) / 2; val my = (l.y + r.y) / 2
        stars = arrayListOf(P2(mx + rnd(-20f, 20f), my - rnd(18f, min(55f, 20f + level * 6f))))
    }

    fun start() { if (state == GameState.Playing) started = true }

    fun touch(x: Float, y: Float) {
        if (!started || state != GameState.Playing || delay != 0.0) return
        if (mode == ToyMode.RopeCut) {
            cutLast?.let { cut(it.x, it.y, x, y) }
            cutLast = P2(x, y)
            return
        }
        if (mode == ToyMode.Plinko && !launched) bx = x.coerceIn(20f, 300f)
        if (mode == ToyMode.DrawBridge && !launched) {
            val qx = x.coerceIn(10f, 310f); val qy = y.coerceIn(100f, 430f)
            val last = bridge.lastOrNull()
            if (last != null) {
                val step = hypot(last.x - qx, last.y - qy)
                if (step <= 5 || inkUsed + step > inkMax) return
                inkUsed += step
            }
            bridge.add(P2(qx, qy))
        }
    }

    fun endTouch() { cutLast = null }

    fun clearBridge() { if (state != GameState.Playing || launched) return; bridge.clear(); bridgeSegments = emptyList(); inkUsed = 0f; notice = "" }

    fun roll() {
        if (!started || state != GameState.Playing || launched || mode != ToyMode.DrawBridge) return
        val first = bridge.firstOrNull() ?: return; val last = bridge.lastOrNull() ?: return
        val l = leftConnector; val r = rightConnector
        val forward = hypot(first.x - l.x, first.y - l.y) < 35 && hypot(last.x - r.x, last.y - r.y) < 35
        val reverse = hypot(last.x - l.x, last.y - l.y) < 35 && hypot(first.x - r.x, first.y - r.y) < 35
        if (!(forward || reverse)) { notice = "Connect both platform edges."; Haptics.error(); return }
        bridgeSegments = bridge.zipWithNext().filter { hypot(it.second.x - it.first.x, it.second.y - it.first.y) > 0.5 }.map { ToySeg(it.first.x, it.first.y, it.second.x, it.second.y) }
        launched = true; vx = 110f; vy = 0f; notice = ""; Sfx.tap()
    }

    private fun cut(fx0: Float, fy0: Float, x: Float, y: Float) {
        for (i in anchors.indices) if (ropes[i]) {
            val a = anchors[i]
            if (intersects(fx0, fy0, x, y, a.x, a.y, bx, by) || dist(x, y, a.x, a.y, bx, by) < 12) {
                ropes[i] = false; launched = true; Sfx.tap(); Haptics.tap()
                burst((a.x + bx) / 2, (a.y + by) / 2, listOf(Color(0xFFFF9500), Color.Yellow), 6, 70f)
            }
        }
    }

    fun gesture(fx0: Float, fy0: Float, x: Float, y: Float) {
        if (!started || state != GameState.Playing || delay != 0.0) return
        if (mode == ToyMode.RopeCut) { val c = cutLast; cut(c?.x ?: fx0, c?.y ?: fy0, x, y); cutLast = null; return }
        if (launched || mode == ToyMode.DrawBridge) return
        if (mode == ToyMode.Plinko) { launched = true; bx = x.coerceIn(20f, 300f); Sfx.tap(); return }
        if (hypot(fx0 - bx, fy0 - by) >= 65) return
        val dx = x - fx0; val dy = y - fy0
        if (hypot(dx, dy) <= 18) return
        launched = true; trail.clear(); flight = 0.0; Sfx.tap()
        when (mode) {
            ToyMode.BottleFlip -> {
                if (dy >= -18) { launched = false; return }
                val power = min(440f, max(240f, -dy * 3))
                vx = min(100f, max(-100f, dx * 1.2f)); vy = -power
                // Flight time is 2*v/g; swipe strength controls the rotation independently.
                spin = 2.5f + (-dy) * 0.045f
            }
            ToyMode.MiniGolf -> { capped(-dx * 3, -dy * 3, 530f); strokes++ }
            ToyMode.BasketShot -> capped(-dx * 4, -dy * 4, 580f)
            else -> {}
        }
    }

    private fun capped(x: Float, y: Float, limit: Float) {
        val s = min(1f, limit / max(1f, hypot(x, y))); vx = x * s; vy = y * s
    }

    // MARK: Results and effects

    private fun finish(points: Int, outcome: Outcome, label: String? = null) {
        if (delay != 0.0) return
        when (outcome) {
            Outcome.Success -> {
                streak++; successes++
                val m = multiplier(streak); val total = points * m
                score += total
                popup(if (m > 1) "+$total  ×$m" else "+$total", bx, by, Color.Yellow, 22f)
                if (label != null) popup(L10n.t(label), bx, by - 28, Color.White, 15f)
                notice = label ?: "Nice shot!"
                burst(bx, by, listOf(Color.Yellow, Color(0xFFFF9500), Color(0xFFFF2D55), Color(0xFF32ADE6), Color.Green), 26, 180f)
                Haptics.success(); Sfx.win()
            }
            Outcome.Safe -> { streak = 0; score += points; popup("+$points", bx, by, Color.White, 15f); notice = ""; Haptics.tap(); Sfx.point() }
            Outcome.Miss -> {
                streak = 0; lives--; score += points
                if (points > 0) popup("+$points", bx, by, Color.White.copy(alpha = 0.8f), 15f)
                notice = "Missed!"
                Haptics.error(); Sfx.wrong()
            }
        }
        delay = 1.1
    }

    private fun popup(text: String, x: Float, y: Float, color: Color, size: Float) {
        fx.popup(text, x.coerceIn(40f, 280f), (y - 16).coerceIn(40f, 420f), color, size)
    }

    private fun burst(x: Float, y: Float, colors: List<Color>, count: Int, speed: Float) {
        for (i in 0 until count) fx.burst(x, y, colors[i % colors.size], 1, speed, 380f, rnd(2f, 4f), rnd(0.5f, 0.9f))
    }

    // MARK: Simulation

    override fun advance(dt: Double) {
        fx.update(min(0.08, dt).toFloat())
        if (!started || state != GameState.Playing) return
        val d = min(0.08, max(0.0, dt))
        if (delay > 0) {
            delay = max(0.0, delay - d)
            if (delay == 0.0) { if (lives <= 0) state = GameState.GameOver(won = successes >= 3) else prepare() }
            return
        }
        animate(d)
        if (!launched && mode != ToyMode.RopeCut) return
        var rest = d
        while (rest > 0 && state == GameState.Playing && delay == 0.0) { val step = min(rest, 1.0 / 120); update(step); rest -= step }
    }

    /** Moving hoops, targets and bars keep moving even before the shot. */
    private fun animate(d: Double) {
        if (movingAmplitude <= 0) return
        clock += d
        when (mode) {
            ToyMode.BasketShot -> tx = movingBaseX + sin(clock * 1.3).toFloat() * movingAmplitude
            ToyMode.RopeCut -> tx = movingBaseX + sin(clock * 1.1).toFloat() * movingAmplitude
            ToyMode.MiniGolf -> { val x = movingBaseX + sin(clock * 1.2).toFloat() * movingAmplitude; movingBar = ToySeg(x - 35, 340f, x + 35, 340f) }
            else -> {}
        }
    }

    private fun update(dt: Double) {
        val d = dt.toFloat()
        val px = bx; val py = by
        if (launched) flight += dt
        if (mode != ToyMode.MiniGolf) vy += (if (mode == ToyMode.BottleFlip) 500f else 400f) * d
        if (mode == ToyMode.BasketShot) vx += wind * d
        bx += vx * d; by += vy * d
        angle += spin * d
        trailClock += dt
        if (trailClock > 0.035) { trailClock = 0.0; trail.add(P2(bx, by)); if (trail.size > 30) trail.removeAt(0) }
        when (mode) {
            ToyMode.BasketShot -> {
                if (vy > 0 && py <= ty && by >= ty && abs(bx - tx) < 21) { finish(if (touchedRim) 100 else 150, Outcome.Success, if (touchedRim) null else "Swish!"); return }
                var hit = circleCollision(tx - 25, ty, 4f, 0.6f)
                hit = circleCollision(tx + 25, ty, 4f, 0.6f) || hit
                hit = segmentCollision(tx + 30, ty - 55, tx + 30, ty + 8, 8f, 0.7f) || hit
                if (hit) { touchedRim = true; Sfx.tap() }
                if (by > 470 || bx < -30 || bx > 350 || flight > 5) finish(0, Outcome.Miss)
            }
            ToyMode.BottleFlip -> if (vy > 0 && by >= 370) {
                by = 370f
                val difference = abs(atan2(sin(angle), cos(angle)))
                val upright = difference < 0.28f && angle >= 2 * PI.toFloat() - 0.28f && bx > 20 && bx < 300
                if (upright) {
                    val double = angle >= 4 * PI.toFloat() - 0.28f
                    val onPad = abs(bx - padX) < padWidth / 2
                    angle = 0f
                    val label = if (double && onPad) "Perfect!" else if (double) "Double flip!" else if (onPad) "Bullseye!" else null
                    finish(100 + (if (double) 100 else 0) + (if (onPad) 75 else 0), Outcome.Success, label)
                } else {
                    // Tip the bottle over so the miss reads clearly.
                    angle = if (sin(angle) >= 0) (PI / 2).toFloat() else (-PI / 2).toFloat(); by = 389f
                    burst(bx, 398f, listOf(Color.White.copy(alpha = 0.6f)), 8, 60f)
                    finish(0, Outcome.Miss)
                }
            }
            ToyMode.MiniGolf -> {
                walls(0.8f)
                var hit = false
                for (s in obstacles) hit = segmentCollision(s.ax, s.ay, s.bx, s.by, 9f, 0.75f) || hit
                movingBar?.let { hit = segmentCollision(it.ax, it.ay, it.bx, it.by, 9f, 0.85f) || hit }
                if (hit) Sfx.tap()
                val speed = hypot(vx, vy); val factor = max(0f, 1 - 75 * d / max(1f, speed)); vx *= factor; vy *= factor
                if (hypot(bx - tx, by - ty) < 13 && speed < 185) {
                    bx = tx; by = ty
                    finish(intArrayOf(300, 150, 75)[min(2, max(0, strokes - 1))], Outcome.Success, if (strokes == 1) "Hole in one!" else null)
                } else if (speed < 4 || flight > 10) {
                    if (strokes >= 3) finish(0, Outcome.Miss)
                    else { launched = false; vx = 0f; vy = 0f; flight = 0.0; trail.clear(); Sfx.tap() }
                }
            }
            ToyMode.Plinko -> {
                if (bx < 9) { bx = 9f; vx = abs(vx) * 0.7f }
                if (bx > 311) { bx = 311f; vx = -abs(vx) * 0.7f }
                for ((index, peg) in pegs.withIndex()) if (abs(peg.y - by) < 14) {
                    if (circleCollision(peg.x, peg.y, 5f, 0.55f)) {
                        if (goldPegs.remove(index)) {
                            score += 20; popup("+20", peg.x, peg.y, Color.Yellow, 15f); Sfx.point()
                            burst(peg.x, peg.y, listOf(Color.Yellow, Color(0xFFFF9500)), 8, 90f)
                        } else Sfx.tap()
                        if (abs(vx) < 8) vx += if (Random.nextBoolean()) 22f else -22f
                    }
                }
                if (by > 420) {
                    val bin = min(5, max(0, (bx / (320f / 6)).toInt())); val value = binValues[bin]
                    if (bin == selectedBin) finish(value, Outcome.Success, "Jackpot!")
                    else if (abs(bin - selectedBin) == 1) finish(value, Outcome.Safe)
                    else finish(value, Outcome.Miss)
                } else if (flight > 12) finish(0, Outcome.Miss)
            }
            ToyMode.RopeCut -> {
                repeat(4) {
                    for (i in anchors.indices) if (ropes[i]) {
                        val a = anchors[i]
                        val dx = bx - a.x; val dy = by - a.y; val length = max(1f, hypot(dx, dy)); val limit = ropeLengths[i]
                        if (length > limit) {
                            val nx = dx / length; val ny = dy / length
                            bx = a.x + nx * limit; by = a.y + ny * limit
                            val out = vx * nx + vy * ny
                            if (out > 0) { vx -= out * nx; vy -= out * ny }
                        }
                    }
                }
                collectStars()
                if (by > 390 && by < 425 && abs(bx - tx) < targetHalfWidth - 2) finish(100, Outcome.Success)
                else if (by > 470 || bx < -30 || bx > 350 || flight > 12) finish(0, Outcome.Miss)
            }
            ToyMode.DrawBridge -> {
                segmentCollision(0f, leftTop, leftEdge, leftTop, 10f, 0f)
                segmentCollision(rightEdge, rightTop, 320f, rightTop, 10f, 0f)
                var nearest: ToySeg? = null; var best = 11f
                for (s in bridgeSegments) {
                    if (bx < min(s.ax, s.bx) - 11 || bx > max(s.ax, s.bx) + 11 || by < min(s.ay, s.by) - 11 || by > max(s.ay, s.by) + 11) continue
                    val gap = dist(bx, by, s.ax, s.ay, s.bx, s.by)
                    if (gap < best) { best = gap; nearest = s }
                }
                nearest?.let { s ->
                    segmentCollision(s.ax, s.ay, s.bx, s.by, 11f, 0f)
                    // Preserve rolling momentum over small joints, without pushing through a steep wall.
                    val dx = abs(s.bx - s.ax); val dy = abs(s.by - s.ay)
                    if (dx > dy && vx > 0) vx = max(80f, vx)
                }
                collectStars()
                if (hypot(bx - tx, by - ty) < 23) {
                    val saved = ((1 - inkUsed / max(1f, inkMax)) * 12).toInt() * 5
                    finish(100 + saved, Outcome.Success, if (saved >= 30) "Perfect!" else null)
                } else if (by > 470 || bx > 340 || bx < -20 || flight > 10) finish(0, Outcome.Miss)
            }
        }
    }

    private fun collectStars() {
        val i = stars.indexOfFirst { hypot(it.x - bx, it.y - by) < 20 }
        if (i < 0) return
        val star = stars.removeAt(i)
        score += 50; popup("★ +50", star.x, star.y, Color.Yellow, 15f)
        burst(star.x, star.y, listOf(Color.Yellow, Color.White), 12, 120f)
        Sfx.point(); Haptics.tap()
    }

    private fun walls(restitution: Float) {
        if (bx < 10) { bx = 10f; vx = abs(vx) * restitution }
        if (bx > 310) { bx = 310f; vx = -abs(vx) * restitution }
        if (by < 30) { by = 30f; vy = abs(vy) * restitution }
        if (by > 445) { by = 445f; vy = -abs(vy) * restitution }
    }

    private fun circleCollision(px: Float, py: Float, radius: Float, restitution: Float): Boolean {
        val dx = bx - px; val dy = by - py; val length = max(0.001f, hypot(dx, dy)); val limit = radius + 8
        if (length >= limit) return false
        val nx = dx / length; val ny = dy / length; val dot = vx * nx + vy * ny
        bx = px + nx * limit; by = py + ny * limit
        if (dot < 0) { vx -= (1 + restitution) * dot * nx; vy -= (1 + restitution) * dot * ny; return true }
        return false
    }

    private fun segmentCollision(ax: Float, ay: Float, cx: Float, cy: Float, radius: Float, restitution: Float): Boolean {
        val (qx, qy) = closest(bx, by, ax, ay, cx, cy)
        val dx = bx - qx; val dy = by - qy; val length = max(0.001f, hypot(dx, dy))
        if (length >= radius) return false
        val nx = dx / length; val ny = dy / length; val dot = vx * nx + vy * ny
        bx = qx + nx * radius; by = qy + ny * radius
        if (dot < 0) { vx -= (1 + restitution) * dot * nx; vy -= (1 + restitution) * dot * ny; return true }
        return false
    }

    private fun closest(px: Float, py: Float, ax: Float, ay: Float, cx: Float, cy: Float): Pair<Float, Float> {
        val dx = cx - ax; val dy = cy - ay
        val t = min(1f, max(0f, ((px - ax) * dx + (py - ay) * dy) / max(0.001f, dx * dx + dy * dy)))
        return (ax + t * dx) to (ay + t * dy)
    }

    private fun dist(px: Float, py: Float, ax: Float, ay: Float, cx: Float, cy: Float): Float {
        val (qx, qy) = closest(px, py, ax, ay, cx, cy); return hypot(qx - px, qy - py)
    }

    private fun intersects(ax: Float, ay: Float, bx2: Float, by2: Float, cx: Float, cy: Float, dx: Float, dy: Float): Boolean {
        fun cross(px: Float, py: Float, qx: Float, qy: Float, rx: Float, ry: Float) = (qx - px) * (ry - py) - (qy - py) * (rx - px)
        if (!(max(ax, bx2) >= min(cx, dx) && max(cx, dx) >= min(ax, bx2) && max(ay, by2) >= min(cy, dy) && max(cy, dy) >= min(ay, by2))) return false
        return cross(ax, ay, bx2, by2, cx, cy) * cross(ax, ay, bx2, by2, dx, dy) <= 0 && cross(cx, cy, dx, dy, ax, ay) * cross(cx, cy, dx, dy, bx2, by2) <= 0
    }
}

@Composable
fun ToyScreen(mode: ToyMode, onExit: () -> Unit) {
    val engine = remember { ToyEngine(mode) }
    val pal = Pal.current
    GameContainer(mode.id, engine, onExit, summary = { L10n.f("Level %d", engine.level) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(L10n.f("Level %d", engine.level), color = pal.accent, fontWeight = FontWeight.Bold)
                if (engine.streak >= 2) Text("🔥×${engine.nextMultiplier}", color = Color(0xFFFF9500), fontWeight = FontWeight.Bold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                if (mode == ToyMode.BasketShot && engine.windState != 0f) Text("💨 " + (if (engine.windState > 0) "→" else "←") + " ${abs(engine.windState).toInt()}", color = pal.textSecondary, fontSize = 13.sp)
                Hearts(engine.lives, engine.maxLives)
            }
            val view = remember(engine) { ToyInput(engine) }
            ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, fx = engine.fx, input = view,
                overlay = { if (!engine.started) StartPrompt() }) { drawToy(engine, view) }
            if (mode == ToyMode.DrawBridge) Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val on = engine.started && !engine.launchedState
                Text(L10n.t("Clear"), color = if (on) pal.text else pal.textSecondary, modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surface).clickable(enabled = on) { engine.clearBridge() }.padding(horizontal = 22.dp, vertical = 10.dp), fontWeight = FontWeight.SemiBold)
                Text(L10n.t("Roll"), color = if (on) pal.onAccent else pal.textSecondary, modifier = Modifier.clip(RoundedCornerShape(50)).background(if (on) pal.accent else pal.surface).clickable(enabled = on) { engine.roll() }.padding(horizontal = 22.dp, vertical = 10.dp), fontWeight = FontWeight.Bold)
            }
            Text(L10n.t(engine.notice.ifEmpty { mode.hint }), color = if (engine.notice.isEmpty()) pal.textSecondary else pal.accent,
                fontSize = if (engine.notice.isEmpty()) 13.sp else 15.sp, fontWeight = if (engine.notice.isEmpty()) FontWeight.Normal else FontWeight.Bold,
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp).heightIn(min = 36.dp).fillMaxWidth())
        }
    }
}

private class ToyInput(val e: ToyEngine) : FieldInput() {
    var fingerX = -1f; var fingerY = -1f
    var startX = 0f; var startY = 0f
    var down = false
    val blade = ArrayList<P2>()
    override fun onDown(x: Float, y: Float) { down = true; startX = x; startY = y; fingerX = x; fingerY = y; e.touch(x, y); if (e.mode == ToyMode.RopeCut && e.started) addBlade(x, y) }
    override fun onMove(x: Float, y: Float) { fingerX = x; fingerY = y; e.touch(x, y); if (e.mode == ToyMode.RopeCut && e.started) addBlade(x, y) }
    override fun onUp(x: Float, y: Float, tapped: Boolean) {
        if (!e.started) e.start() else e.gesture(startX, startY, x, y)
        e.endTouch(); down = false; blade.clear()
    }
    private fun addBlade(x: Float, y: Float) { blade.add(P2(x, y)); if (blade.size > 10) blade.removeAt(0) }
}

private val Yel = Color(0xFFFFCC00)
private val Orange = Color(0xFFFF9500)
private val Cyan = Color(0xFF32ADE6)
private val Pink = Color(0xFFFF2D55)
private val Accent = Color(0xFFC6F31D)

private fun Pen.ballShiny(x: Float, y: Float, r: Float, light: Color, dark: Color) {
    circle(x + 2, y + 3, r, Color.Black.copy(alpha = 0.3f)); shiny(x, y, r, light, dark)
}

private fun Pen.starShape(x: Float, y: Float, r: Float) {
    val pts = (0 until 10).map { i -> val a = i * (PI / 5).toFloat() - (PI / 2).toFloat(); val len = if (i % 2 == 0) r else r * 0.45f; Offset(x + cos(a) * len, y + sin(a) * len) }
    circle(x, y, r * 1.3f, Yel.copy(alpha = 0.15f)); polygon(pts, Yel)
}

private fun Pen.vg(x: Float, y: Float, w: Float, h: Float, top: Color, bottom: Color, radius: Float = 0f) = tile(x, y, w, h, top, bottom, radius)

private fun Pen.drawToy(e: ToyEngine, input: ToyInput) {
    when (e.mode) {
        ToyMode.BasketShot -> {
            vg(0f, 0f, 320f, 460f, Color(0xFF1A2147), Color(0xFF0D0F1F))
            box(0f, 430f, 320f, 30f, Color(0xFF593824), 4f)
            val x = e.tx; val y = e.ty
            box(x + 27, y - 60, 8f, 72f, Color.White.copy(alpha = 0.9f), 4f)
            box(x + 29, y - 38, 4f, 24f, Color.Red.copy(alpha = 0.7f), 4f)
            line(x + 34, y + 12, x + 34, 460f, Color.Gray.copy(alpha = 0.5f), 4f)
            for (i in 0..4) { val t = i / 4f; line(x - 25 + 50 * t, y, x - 14 + 28 * t, y + 35, Color.White.copy(alpha = 0.45f), 1.5f) }
            line(x - 20, y + 17, x + 20, y + 17, Color.White.copy(alpha = 0.35f), 1.5f)
            line(x - 14, y + 35, x + 14, y + 35, Color.White.copy(alpha = 0.45f), 1.5f)
            line(x - 25, y, x + 25, y, Orange, 4f)
            if (e.wind != 0f) {
                val len = min(40f, abs(e.wind) * 0.45f)
                for (row in 0 until 3) { val yy = 70f + row * 45f; val xx = 40f + row * 30f; line(xx, yy, xx + (if (e.wind > 0) len else -len), yy, Color.White.copy(alpha = 0.18f), 2f) }
            }
        }
        ToyMode.BottleFlip -> {
            vg(0f, 0f, 320f, 400f, Color(0xFF291F40), Color(0xFF0F0F1A))
            vg(0f, 400f, 320f, 60f, Color(0xFF734D2E), Color(0xFF402919))
            circle(e.padX, 399f, e.padWidth * 0.6f, Yel.copy(alpha = 0.12f))
            box(e.padX - e.padWidth / 2, 396f, e.padWidth, 6f, Yel, 4f)
        }
        ToyMode.MiniGolf -> {
            vg(0f, 0f, 320f, 460f, Color(0xFF1A5429), Color(0xFF0D3317))
            for (i in 0 until 9 step 2) box(10f, 30f + i * 46f, 300f, 46f, Color.White.copy(alpha = 0.03f), 0f)
            strokeBox(6f, 26f, 308f, 423f, Color(0xFF734D2E), 6f, 8f)
            for (s in e.obstacles) { line(s.ax, s.ay, s.bx, s.by, Color(0xFFD98C40), 12f); line(s.ax, s.ay, s.bx, s.by, Color(0xFFFFBF66), 4f) }
            e.movingBar?.let { line(it.ax, it.ay, it.bx, it.by, Pink, 12f); line(it.ax, it.ay, it.bx, it.by, Color.White.copy(alpha = 0.6f), 3f) }
            circle(e.tx, e.ty, 15f, Color.Black.copy(alpha = 0.25f)); circle(e.tx, e.ty, 13f, Color.Black)
            line(e.tx, e.ty, e.tx, e.ty - 38, Color.White, 2f)
            polygon(listOf(Offset(e.tx, e.ty - 38), Offset(e.tx + 22, e.ty - 28), Offset(e.tx, e.ty - 20)), Pink)
            for (i in 0 until 3) circle(24f + i * 14f, 14f, 4.5f, if (i < 3 - e.strokes) Color.White else Color.White.copy(alpha = 0.2f))
        }
        ToyMode.Plinko -> {
            vg(0f, 0f, 320f, 460f, Color(0xFF1F1438), Color(0xFF0A0D1F))
            for ((i, p) in e.pegs.withIndex()) {
                if (i in e.goldPegs) { circle(p.x, p.y, 10f, Yel.copy(alpha = 0.2f)); shiny(p.x, p.y, 6f, Color.White, Yel) }
                else circle(p.x, p.y, 5f, Cyan.copy(alpha = 0.8f))
            }
            val values = e.binValues
            for (i in 0 until 6) {
                val x = i * 320f / 6; val jackpot = i == e.selectedBin; val near = abs(i - e.selectedBin) == 1
                if (jackpot) circle(x + 320f / 12, 431f, 34f, Accent.copy(alpha = 0.2f))
                vg(x + 2, 411f, 320f / 6 - 4, 40f, if (jackpot) Cyan else if (near) Color(0xFF595959) else Color(0xFF333333), if (jackpot) Accent else Color(0xFF1F1F1F), 6f)
                label("${values[i]}", x + 320f / 12, 431f, 13f, if (jackpot) Color.Black else Color.White)
            }
            if (!e.launched && e.started) line(e.bx, 50f, e.bx, 80f, Color.White.copy(alpha = 0.25f), 2f)
        }
        ToyMode.RopeCut -> {
            vg(0f, 0f, 320f, 460f, Color(0xFF2E1A33), Color(0xFF0F0D1A))
            for (s in e.stars) starShape(s.x, s.y, 11f)
            for (i in e.anchors.indices) {
                val a = e.anchors[i]
                if (e.ropes[i]) { line(a.x, a.y, e.bx, e.by, Color(0xFF996633), 4f); line(a.x, a.y, e.bx, e.by, Color(0xFFF2BF73), 1.5f) }
                circle(a.x, a.y, 7f, Color.White); circle(a.x, a.y, 3f, Color.Gray)
            }
            val half = e.targetHalfWidth
            val bowl = Path().apply { moveTo(e.tx - half, 398f); quadraticTo(e.tx, 440f, e.tx + half, 398f); close() }
            ds.drawPath(bowl, Brush.verticalGradient(listOf(Color(0xFF34C759), Color(0xFF1A8033)), 398f, 430f))
            circle(e.tx - 9, 408f, 2.5f, Color.Black); circle(e.tx + 9, 408f, 2.5f, Color.Black)
            if (input.blade.size > 1) polyline(input.blade.map { Offset(it.x, it.y) }, Color.White.copy(alpha = 0.7f), 3f)
        }
        ToyMode.DrawBridge -> {
            vg(0f, 0f, 320f, 460f, Color(0xFF14293F), Color(0xFF0A0F1F))
            box(0f, 440f, 320f, 20f, Color(0xFF1A4D80).copy(alpha = 0.6f), 0f)
            vg(0f, e.leftTop, e.leftEdge, 460 - e.leftTop, Color(0xFF737373), Color(0xFF333333), 6f)
            vg(e.rightEdge, e.rightTop, 320 - e.rightEdge, 460 - e.rightTop, Color(0xFF737373), Color(0xFF333333), 6f)
            circle(e.leftConnector.x, e.leftConnector.y, 7f, Cyan); circle(e.rightConnector.x, e.rightConnector.y, 7f, Cyan)
            for (s in e.stars) starShape(s.x, s.y, 11f)
            val pts = e.bridge.map { Offset(it.x, it.y) }
            if (pts.size > 1) { polyline(pts, Cyan.copy(alpha = 0.25f), 11f); polyline(pts, Cyan, 5f) }
            circle(e.tx, e.ty, 22f, Color.Green.copy(alpha = 0.25f)); circle(e.tx, e.ty, 10f, Color.Green.copy(alpha = 0.6f))
            val left = max(0f, 1 - e.inkUsed / max(1f, e.inkMax))
            box(14f, 14f, 100f, 8f, Color.White.copy(alpha = 0.15f), 4f)
            box(14f, 14f, 100f * left, 8f, if (left < 0.2f) Color.Red else Cyan, 4f)
        }
    }
    if (e.mode != ToyMode.BottleFlip) e.trail.forEachIndexed { i, p -> circle(p.x, p.y, 2f, Color.White.copy(alpha = i.toFloat() / max(1, e.trail.size) * 0.3f)) }
    when (e.mode) {
        ToyMode.BottleFlip -> {
            val lift = max(0f, 370f - e.by)
            oval(e.bx - 14 + lift * 0.02f, 398f, 28f - lift * 0.04f, 5f, Color.Black.copy(alpha = 0.35f))
            xf(e.bx, e.by, e.angle) {
                box(-11f, -20f, 22f, 50f, Cyan.copy(alpha = 0.85f), 6f)
                box(-6f, -31f, 12f, 13f, Color.White, 2f)
                box(-11f, 2f, 22f, 12f, Color.White.copy(alpha = 0.6f), 0f)
                box(-7f, -16f, 3f, 40f, Color.White.copy(alpha = 0.35f), 1.5f)
            }
        }
        ToyMode.BasketShot -> {
            ballShiny(e.bx, e.by, 10f, Color(0xFFFFA64D), Color(0xFFCC4D0D))
            xf(e.bx, e.by, e.bx / 10f) {
                line(-10f, 0f, 10f, 0f, Color.Black.copy(alpha = 0.4f), 1f); line(0f, -10f, 0f, 10f, Color.Black.copy(alpha = 0.4f), 1f)
            }
        }
        ToyMode.RopeCut -> { ballShiny(e.bx, e.by, 11f, Pink, Color(0xFFB31A66)); circle(e.bx - 3, e.by - 3, 3.5f, Color.White.copy(alpha = 0.85f)) }
        ToyMode.MiniGolf -> ballShiny(e.bx, e.by, 8f, Color.White, Color(0xFFB3B3B3))
        ToyMode.Plinko -> ballShiny(e.bx, e.by, 8f, Color.White, Accent)
        ToyMode.DrawBridge -> ballShiny(e.bx, e.by, 10f, Orange, Color.Red)
    }
    if (input.down && !e.launched && (e.mode == ToyMode.BasketShot || e.mode == ToyMode.MiniGolf)) {
        val sx = input.startX; val sy = input.startY
        val dx = sx - input.fingerX; val dy = sy - input.fingerY
        val power = min(1f, hypot(dx, dy) / (if (e.mode == ToyMode.BasketShot) 145f else 175f))
        val scale = min(1f, 90f / max(1f, hypot(dx, dy)))
        val ax = e.bx + dx * scale; val ay = e.by + dy * scale
        val tint = hsb((0.33f * (1 - power)).toDouble(), 0.85f, 1f)
        line(e.bx, e.by, input.fingerX, input.fingerY, Color.White.copy(alpha = 0.2f), 2f)
        for (i in 1..6) { val t = i / 6f; circle(e.bx + (ax - e.bx) * t, e.by + (ay - e.by) * t, 2 + t * 1.5f, tint.copy(alpha = 0.4f + 0.6f * t)) }
    }
}
