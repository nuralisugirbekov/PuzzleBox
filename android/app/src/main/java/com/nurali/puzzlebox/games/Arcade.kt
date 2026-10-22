package com.nurali.puzzlebox.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.background
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
import com.nurali.puzzlebox.games.kit.P2
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.R
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.games.kit.hsb
import com.nurali.puzzlebox.games.kit.rnd
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class ArcadeMode(val id: GameId, val hint: String) {
    Stack(GameId.Stack, "Tap to stack. Perfect drops keep the block whole, and three in a row make it grow."),
    KnifeSpin(GameId.KnifeSpin, "Tap to throw. Avoid the other pins and slice apples for bonus points."),
    HelixDrop(GameId.HelixDrop, "Drag sideways to rotate. Fall through three gaps in a row to smash the next floor."),
    FlappyFlight(GameId.FlappyFlight, "Tap to fly through the gaps and grab the coins."),
    RoadHop(GameId.RoadHop, "Swipe to hop. Tap to move forward. Avoid traffic and grab coins."),
}

class ArcadeBody(var rect: R, var value: Int = 0, var speed: Float = 0f, var counted: Boolean = false,
                 var hue: Double = 0.0, var phase: Float = 0f, var baseY: Float = 0f, var vx: Float = 0f)

/** Fixed 320 × 480 playfield, independent of the device size. */
class ArcadeEngine(val mode: ArcadeMode) : FrameGame {
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var level by mutableIntStateOf(1)
    var remainingPins by mutableIntStateOf(7)
    var totalPins = 7
    val fx = ArcadeFX()

    var px = 160f; var py = 400f
    var vy = 0f
    val bodies = ArrayList<ArcadeBody>()
    val debris = ArrayList<ArcadeBody>()
    val coins = ArrayList<P2>()
    var angle = 0f
    var time = 0f

    // Knife Spin
    val pins = ArrayList<Float>()
    val apples = ArrayList<Float>()
    var projectile: Float? = null
    var targetKick = 0f
    var levelIntro = 0f
    private var spinClock = 0f
    val isBossLevel get() = level % 5 == 0

    // Stack
    private var movingX = 20f
    var blockWidth = 180f
    var placed = 0
    var perfectStreak = 0
    var cameraLag = 0f
    var ripple: Pair<R, Float>? = null
    private var direction = 1f
    val stackHue get() = (0.52 + placed * 0.031) % 1.0

    // Helix Drop
    var combo = 0
    private var helixSpawned = 0
    val fireball get() = mode == ArcadeMode.HelixDrop && combo >= 3

    // Flappy Flight
    var scroll = 0f
    var flap = 0f
    private var pipesSpawned = 0
    private var pipesPassed = 0

    // Road Hop
    private var roadRow = 0
    private var furthestRoadRow = 0
    var hopTimer = 0f
    var facing = -1f

    private var cooldown = 0.0
    private var emitClock = 0f
    private var previousDrag: Float? = null
    var flash = 0.0

    init { restart() }

    override fun restart() {
        state = GameState.Playing; score = 0; started = false
        px = 160f; py = 400f; vy = 0f
        bodies.clear(); debris.clear(); coins.clear(); pins.clear(); apples.clear(); projectile = null
        angle = 0f; level = 1; remainingPins = 7; totalPins = 7; targetKick = 0f; levelIntro = 0f; spinClock = 0f
        fx.reset(); time = 0f
        cooldown = 0.0; flash = 0.0; emitClock = 0f
        movingX = 0f; blockWidth = 180f; direction = 1f; previousDrag = null
        placed = 0; perfectStreak = 0; cameraLag = 0f; ripple = null
        combo = 0; helixSpawned = 0
        scroll = 0f; flap = 0f; pipesSpawned = 0; pipesPassed = 0
        roadRow = 0; furthestRoadRow = 0; hopTimer = 0f; facing = -1f
        when (mode) {
            ArcadeMode.Stack -> bodies.add(ArcadeBody(R(70f, 420f, 180f, 22f), hue = stackHue))
            ArcadeMode.FlappyFlight -> { px = 78f; py = 240f; addPipe(380f); addPipe(580f) }
            ArcadeMode.HelixDrop -> { px = 160f; py = 130f; for (i in 0 until 7) addHelixPlatform(220f + i * 85f) }
            ArcadeMode.RoadHop -> { px = 160f; py = 430f; for (lane in 1..7) addLane(lane) }
            ArcadeMode.KnifeSpin -> setupKnifeLevel()
        }
    }

    val movingBlock get() = R(movingX, (bodies.lastOrNull()?.rect?.minY ?: 420f) - 24f, blockWidth, 22f)
    val roadProgress get() = furthestRoadRow

    private fun lose(x: Float? = null, y: Float? = null, color: Color = Color.Red) {
        if (x != null && y != null) {
            fx.burst(x, y, color, 26, 220f, 320f, 3.5f, 0.8f)
            fx.burst(x, y, Color.White, 10, 160f, 320f, 2f)
        }
        fx.kick(9f); fx.flash(Color.Red, 0.3f)
        state = GameState.GameOver(won = false); Haptics.error(); Sfx.lose()
    }

    private fun reward(points: Int, sound: Boolean = true) {
        score += points; flash = 0.18; Haptics.tap()
        if (sound) Sfx.point()
    }

    private fun wrap(value: Float, period: Float = 320f): Float {
        val r = value % period
        return if (r < 0) r + period else r
    }

    private fun angularDistance(a: Float, b: Float): Float {
        val v = wrap(a - b, (PI * 2).toFloat())
        return min(v, (PI * 2).toFloat() - v)
    }

    fun tap() {
        if (state != GameState.Playing) return
        if (!started) {
            started = true
            if (mode == ArcadeMode.FlappyFlight) flapUp()
            return
        }
        when (mode) {
            ArcadeMode.Stack -> placeBlock()
            ArcadeMode.KnifeSpin -> if (projectile == null && cooldown <= 0) { projectile = 425f; Sfx.tap() }
            ArcadeMode.FlappyFlight -> flapUp()
            ArcadeMode.RoadHop -> hop(0, -1)
            else -> {}
        }
    }

    fun drag(x: Float) {
        if (state != GameState.Playing || !started) return
        if (mode == ArcadeMode.HelixDrop) {
            previousDrag?.let { prev -> val d = x - prev; for (b in bodies) b.rect.x = wrap(b.rect.minX + d) }
            previousDrag = x
        }
    }

    fun endDrag() { previousDrag = null }

    /** Small fixed steps prevent fast objects from tunnelling through obstacles. */
    override fun advance(dt: Double) {
        if (!started || state != GameState.Playing) return
        val total = min(0.1, max(0.0, dt))
        var remaining = total
        while (remaining > 0 && state == GameState.Playing) {
            val step = min(remaining, 1.0 / 120)
            update(step.toFloat()); remaining -= step
        }
        time += total.toFloat()
        fx.update(total.toFloat())
    }

    private fun update(dt: Float) {
        cooldown = max(0.0, cooldown - dt); flash = max(0.0, flash - dt)
        when (mode) {
            ArcadeMode.Stack -> updateStack(dt)
            ArcadeMode.KnifeSpin -> updateKnife(dt)
            ArcadeMode.HelixDrop -> updateHelix(dt)
            ArcadeMode.FlappyFlight -> updateFlappy(dt)
            ArcadeMode.RoadHop -> updateRoad(dt)
        }
    }

    // MARK: Stack

    private fun updateStack(dt: Float) {
        movingX += direction * (105f + min(placed * 4.5f, 190f)) * dt
        if (movingX < 0) { movingX = 0f; direction = 1f }
        if (movingX + blockWidth > 320) { movingX = 320f - blockWidth; direction = -1f }
        for (d in debris) {
            d.speed += 760 * dt
            d.rect.y += d.speed * dt
            d.rect.x += d.vx * dt
            d.phase += d.vx * 0.02f * dt
        }
        debris.removeAll { it.rect.minY > 520 }
        cameraLag = max(0f, cameraLag - dt * max(60f, cameraLag * 9))
        ripple?.let { (r, t) -> ripple = if (t + dt > 0.5f) null else r to t + dt }
    }

    private fun placeBlock() {
        val base = bodies.lastOrNull() ?: return
        var rect = movingBlock
        val hue = (0.52 + (placed + 1) * 0.031) % 1.0
        val blockColor = hsb(hue, 0.6f, 0.95f)
        if (abs(rect.minX - base.rect.minX) < 4.5f && abs(rect.w - base.rect.w) < 0.5f) {
            // Perfect drop: keep the full width; a streak of three or more regrows the block.
            perfectStreak++
            var width = base.rect.w
            var x = base.rect.minX
            if (perfectStreak >= 3 && width < 180f) {
                val grow = min(14f, 180f - width)
                width += grow
                x = max(0f, min(320f - width, x - grow / 2))
            }
            rect = R(x, rect.minY, width, 22f)
            val bonus = 5 * min(perfectStreak, 6)
            score += 10 + bonus; flash = 0.18
            ripple = rect.copy() to 0f
            val label = if (perfectStreak > 1) L10n.t("Perfect!") + " ×$perfectStreak" else L10n.t("Perfect!")
            fx.popup(label, rect.midX, rect.minY - 18, Color.White, 18f)
            fx.burst(rect.minX, rect.midY, blockColor, 8, 120f, 200f)
            fx.burst(rect.maxX, rect.midY, blockColor, 8, 120f, 200f)
            if (perfectStreak >= 3) { Haptics.success(); Sfx.win() } else { Haptics.move(); Sfx.point() }
        } else {
            val left = max(rect.minX, base.rect.minX); val right = min(rect.maxX, base.rect.maxX)
            if (right <= left) {
                debris.add(ArcadeBody(rect.copy(), hue = hue, vx = direction * 40f))
                lose(rect.midX, rect.midY, blockColor)
                return
            }
            perfectStreak = 0
            if (rect.minX < left) debris.add(ArcadeBody(R(rect.minX, rect.minY, left - rect.minX, 22f), hue = hue, vx = -50f))
            if (rect.maxX > right) debris.add(ArcadeBody(R(right, rect.minY, rect.maxX - right, 22f), hue = hue, vx = 50f))
            rect.x = left; rect.w = right - left
            reward(10)
        }
        blockWidth = rect.w
        placed++
        bodies.add(ArcadeBody(rect, value = placed, hue = hue))
        if (rect.minY < 190f) {
            for (b in bodies) b.rect.y += 24f
            for (d in debris) d.rect.y += 24f
            ripple?.let { (r, t) -> r.y += 24f; ripple = r to t }
            cameraLag += 24f
            bodies.removeAll { it.rect.minY > 500f }
        }
        direction *= -1f; movingX = if (direction > 0) 0f else 320f - blockWidth
    }

    // MARK: Knife Spin

    private fun setupKnifeLevel() {
        pins.clear(); apples.clear()
        totalPins = if (isBossLevel) min(14, 8 + level / 5) else min(12, 5 + level)
        remainingPins = totalPins
        val preplaced = if (isBossLevel) 3 else min(5, (level - 1) / 2)
        repeat(preplaced) { freeAngle(0.55f)?.let { pins.add(it) } }
        val appleCount = if (level == 1) 1 else if (isBossLevel) 3 else Random.nextInt(1, 3)
        repeat(appleCount) { freeAngle(0.5f)?.let { apples.add(it) } }
        levelIntro = 0.45f
    }

    private fun freeAngle(minGap: Float): Float? {
        repeat(40) {
            val a = rnd(0f, (PI * 2).toFloat())
            if (pins.all { angularDistance(it, a) > minGap } && apples.all { angularDistance(it, a) > minGap }) return a
        }
        return null
    }

    /** Angular velocity: steady early on, wobbling later, and swinging back and forth on boss levels. */
    private val spinSpeed: Float
        get() {
            val base = 1.1f + min(level, 14) * 0.12f
            val sign = if (level % 2 == 0) -1f else 1f
            if (isBossLevel) return base * (1.9f * sin(spinClock * 0.85f) + 0.25f)
            if (level >= 3) return sign * base * (0.8f + 0.45f * sin(spinClock * 1.4f))
            return sign * base
        }

    private fun updateKnife(dt: Float) {
        spinClock += dt
        angle = wrap(angle + dt * spinSpeed, (PI * 2).toFloat())
        targetKick = max(0f, targetKick - dt * 6)
        levelIntro = max(0f, levelIntro - dt)
        val y = projectile ?: return
        val next = y - dt * 700
        projectile = next
        if (next > 260f) return
        projectile = null
        val insertion = wrap((PI / 2).toFloat() - angle, (PI * 2).toFloat())
        if (pins.any { angularDistance(it, insertion) < 0.19f }) {
            fx.burst(160f, 262f, Color.Yellow, 14, 200f, 500f, 2.5f)
            lose(160f, 262f, Color.White)
            return
        }
        pins.add(insertion); remainingPins--; targetKick = 1f
        reward(10)
        fx.burst(160f, 262f, Color(0xFFD99959), 6, 90f, 400f, 2f)
        val hit = apples.indexOfFirst { angularDistance(it, insertion) < 0.24f }
        if (hit >= 0) {
            apples.removeAt(hit)
            score += 25
            fx.burst(160f, 270f, Color.Red, 16, 170f, 320f, 3f)
            fx.burst(160f, 270f, Color.Green, 6, 120f, 320f, 2.5f)
            fx.popup("+25", 200f, 290f, Color.Red, 18f)
            Sfx.point(); Haptics.move()
        }
        if (remainingPins == 0) {
            val bonus = if (isBossLevel) 100 else 20
            score += bonus
            fx.burst(160f, 180f, if (isBossLevel) Color.Red else Color(0xFFFF9500), 40, 260f, 320f, 4f, 0.9f)
            fx.flash(Color.White, 0.25f); fx.kick(5f)
            fx.popup("+$bonus", 160f, 180f, Color.Yellow, 22f)
            Haptics.success(); Sfx.win()
            level++
            setupKnifeLevel()
            if (isBossLevel) fx.popup(L10n.t("Boss!"), 160f, 130f, Color.Red, 26f)
            cooldown = 0.6
        }
    }

    // MARK: Helix Drop

    private fun addHelixPlatform(y: Float) {
        val n = helixSpawned
        helixSpawned++
        val gap = max(62f, 92f - n * 0.6f)
        var red = 0
        if (n >= 3) red = 1
        if (n >= 18 && Random.nextFloat() < min(0.75f, (n - 18) * 0.03f + 0.25f)) red = 2
        // Keep the first platform safe directly under the start position.
        val x = if (n == 0) wrap(160f - gap - 60f) else rnd(0f, 320f)
        bodies.add(ArcadeBody(R(x, y, gap, 12f), value = red, hue = (0.5 + n * 0.045) % 1.0))
    }

    /** Relative ranges (0..<320 from the platform's origin) that are deadly. */
    fun helixRedZones(body: ArcadeBody): List<ClosedFloatingPointRange<Float>> = buildList {
        if (body.value >= 1) add(200f..265f)
        if (body.value >= 2) add((body.rect.w + 24f)..(body.rect.w + 64f))
    }

    private fun updateHelix(dt: Float) {
        val previousY = py
        vy = min(vy + 600 * dt, 560f); py += vy * dt
        if (fireball) {
            emitClock -= dt
            if (emitClock <= 0) {
                emitClock = 0.025f
                fx.burst(px, py, listOf(Color(0xFFFF9500), Color.Yellow, Color.Red).random(), 2, 40f, -120f, 4f, 0.35f)
            }
        }
        if (vy > 0) {
            var i = 0
            while (i < bodies.size) {
                val platform = bodies[i]
                if (!(previousY + 10 <= platform.rect.minY && py + 10 >= platform.rect.minY)) { i++; continue }
                val relative = wrap(px - platform.rect.minX)
                if (relative < platform.rect.w) {
                    if (!platform.counted) {
                        platform.counted = true
                        combo++
                        val points = 10 * min(combo, 5)
                        reward(points)
                        if (combo == 3) {
                            fx.popup(L10n.t("Fireball!"), 160f, py - 40f, Color(0xFFFF9500), 22f)
                            Haptics.move()
                        } else if (combo > 1) fx.popup("+$points", px + 24f, py - 10f, Color.Yellow)
                    }
                    i++
                } else if (fireball) {
                    // Smash straight through the floor, even red.
                    val color = hsb(platform.hue, 0.7f, 0.95f)
                    bodies.removeAt(i)
                    score += 30
                    fx.burst(px, platform.rect.minY, color, 30, 240f, 500f, 4f, 0.7f)
                    fx.burst(px, platform.rect.minY, Color(0xFFFF9500), 12, 160f, 320f, 3f)
                    fx.popup(L10n.t("Smash!") + " +30", 160f, platform.rect.minY - 20f, Color(0xFFFF9500), 20f)
                    fx.kick(6f)
                    combo = 0; vy = 120f
                    Haptics.heavy(); Sfx.win()
                    break
                } else if (helixRedZones(platform).any { relative in it }) {
                    lose(px, py, Color.Red); return
                } else {
                    py = platform.rect.minY - 10f; vy = -230f; Sfx.tap()
                    fx.burst(px, platform.rect.minY, hsb(platform.hue, 0.6f, 1f), 6, 90f, 400f, 2.5f, 0.4f, PI.toFloat(), (2 * PI).toFloat())
                    combo = 0
                    break
                }
            }
        }
        if (py > 250f) {
            val offset = py - 250f; py = 250f
            for (b in bodies) b.rect.y -= offset
            bodies.removeAll { it.rect.maxY < 0 }
            while ((bodies.lastOrNull()?.rect?.minY ?: 0f) < 560f) addHelixPlatform((bodies.lastOrNull()?.rect?.minY ?: 250f) + 85f)
        }
    }

    // MARK: Flappy Flight

    private fun flapUp() {
        vy = -235f; flap = 1f; Sfx.tap()
        fx.burst(px - 8, py + 6, Color.White.copy(alpha = 0.8f), 4, 60f, 100f, 2f, 0.35f, (PI * 0.5).toFloat(), (PI * 1.1).toFloat())
    }

    private fun addPipe(x: Float) {
        val n = pipesSpawned
        pipesSpawned++
        val gap = max(114f, 150f - n * 1.4f)
        val center = rnd(150f, 330f)
        val pipe = ArcadeBody(R(x, center - gap / 2, 52f, gap), baseY = center)
        if (n > 7 && Random.nextFloat() < min(0.55f, (n - 7) * 0.05f)) {
            pipe.speed = rnd(26f, 46f)
            pipe.phase = rnd(0f, (PI * 2).toFloat())
            pipe.baseY = min(330f, max(150f, center))
        }
        bodies.add(pipe)
        // Coins float between pipes, sometimes off the safe line to tempt a risky move.
        if (n > 0 && Random.nextFloat() < 0.6f) coins.add(P2(x - 74f, min(400f, max(80f, center + rnd(-60f, 60f)))))
    }

    private fun updateFlappy(dt: Float) {
        vy += 640 * dt; py += vy * dt
        flap = max(0f, flap - dt * 4)
        if (py <= 10f || py >= 462f) { lose(px, py, Color.Yellow); return }
        val speed = 110f + min(70f, pipesPassed * 2f)
        scroll += speed * dt
        for (b in bodies) {
            b.rect.x -= speed * dt
            if (b.speed > 0) {
                b.phase += dt * 1.6f
                b.rect.y = b.baseY + sin(b.phase) * b.speed - b.rect.h / 2
            }
            val pipe = b.rect
            if (pipe.minX < px + 10 && pipe.maxX > px - 10 && (py - 10 < pipe.minY || py + 10 > pipe.maxY)) { lose(px, py, Color.Yellow); return }
            if (!b.counted && pipe.maxX < px) { b.counted = true; pipesPassed++; reward(10) }
        }
        for (c in coins) c.x -= speed * dt
        val hit = coins.indexOfFirst { hypot(it.x - px, it.y - py) < 20f }
        if (hit >= 0) {
            val coin = coins.removeAt(hit)
            score += 5
            fx.burst(coin.x, coin.y, Color.Yellow, 10, 110f, 100f, 2.5f)
            fx.popup("+5", coin.x, coin.y - 16f, Color.Yellow)
            Sfx.point(); Haptics.tap()
        }
        coins.removeAll { it.x < -20f }
        bodies.removeAll { it.rect.maxX < -10f }
        if ((bodies.lastOrNull()?.rect?.minX ?: 0f) < 190f) addPipe((bodies.lastOrNull()?.rect?.minX ?: 190f) + 200f)
    }

    // MARK: Road Hop

    fun hop(dx: Int, dy: Int) {
        if (mode != ArcadeMode.RoadHop || state != GameState.Playing || !started || cooldown > 0) return
        val x = px + dx * 40f
        if (x < 20f || x > 300f) return
        val nextRow = roadRow - dy
        if (nextRow < max(0, furthestRoadRow - 3)) return
        px = x; roadRow = nextRow
        py += dy * 50f
        if (dx != 0) facing = dx.toFloat()
        cooldown = 0.12; hopTimer = 0.14f
        Sfx.tap()
        val hit = coins.indexOfFirst { abs(it.x - px) < 20f && abs(it.y - py) < 20f }
        if (hit >= 0) {
            val coin = coins.removeAt(hit)
            score += 25
            fx.burst(coin.x, coin.y, Color.Yellow, 12, 120f, 150f, 2.5f)
            fx.popup("+25", coin.x, coin.y - 18f, Color.Yellow)
            Sfx.point(); Haptics.move()
        }
        if (roadRow > furthestRoadRow) {
            furthestRoadRow = roadRow; reward(10, sound = furthestRoadRow % 5 == 0)
            if (furthestRoadRow % 10 == 0) fx.popup("$furthestRoadRow", px, py - 30f, Color(0xFFC6F31D), 22f)
            if (py < 280f) {
                py += 50f
                for (b in bodies) b.rect.y += 50f
                for (c in coins) c.y += 50f
                bodies.removeAll { it.rect.minY > 500f }
                coins.removeAll { it.y > 500f }
                addLane(roadRow + 4)
            }
        }
        roadCollision()
    }

    fun isGrassRow(row: Int) = row <= 0 || row % 4 == 0

    /** Visible rows, bottom to top, with their centre y. */
    val visibleRoadRows: List<Pair<Int, Float>>
        get() = (roadRow - 4..roadRow + 9).map { it to py - (it - roadRow) * 50f }

    private fun updateRoad(dt: Float) {
        hopTimer = max(0f, hopTimer - dt)
        for (b in bodies) {
            b.rect.x += b.speed * dt
            if (b.speed > 0 && b.rect.minX > 350f) b.rect.x -= 450f
            if (b.speed < 0 && b.rect.maxX < -30f) b.rect.x += 450f
        }
        roadCollision()
    }

    private fun addLane(row: Int) {
        val y = py - (row - roadRow) * 50f
        if (row > 2 && Random.nextFloat() < 0.22f) coins.add(P2(40f * Random.nextInt(1, 8), y))
        if (isGrassRow(row)) return // Every fourth row is a safe grass strip.
        val truck = row > 8 && Random.nextFloat() < 0.25f
        val base = (50 + row % 6 * 13) + min(70f, row * 1.2f)
        val speed = (if (row % 2 == 0) 1f else -1f) * base * (if (truck) 0.75f else 1f)
        val count = if (!truck && row > 20 && Random.nextFloat() < 0.4f) 3 else 2
        val spacing = 450f / count
        val width = if (truck) 100f else 62f
        val offset = rnd(-80f, 20f)
        for (i in 0 until count) bodies.add(ArcadeBody(R(offset + i * spacing, y - 16f, width, 32f), value = if (truck) -1 else row + i, speed = speed))
    }

    private fun roadCollision() {
        val rect = R(px - 11f, py - 11f, 22f, 22f)
        if (bodies.any { it.rect.intersects(rect) }) lose(px, py, Color(0xFF007AFF))
    }
}

@Composable
fun ArcadeScreen(mode: ArcadeMode, onExit: () -> Unit) {
    val engine = remember { ArcadeEngine(mode) }
    val pal = Pal.current
    GameContainer(mode.id, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            if (mode == ArcadeMode.KnifeSpin) Row(Modifier.padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L10n.f("Level %d · Remaining: %d", engine.level, engine.remainingPins), color = pal.accent, fontWeight = FontWeight.SemiBold)
                if (engine.isBossLevel) Text(L10n.t("Boss!"), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.Red).padding(horizontal = 8.dp, vertical = 3.dp))
            }
            val input = remember(engine) {
                object : FieldInput() {
                    var sx = 0f; var sy = 0f
                    var fired = false
                    // Taps react on touch-down; only Road Hop waits for the finger to lift to tell a swipe from a tap.
                    override fun onDown(x: Float, y: Float) {
                        sx = x; sy = y
                        fired = mode != ArcadeMode.RoadHop || !engine.started
                        if (fired) engine.tap()
                    }
                    override fun onMove(x: Float, y: Float) { engine.drag(x) }
                    override fun onUp(x: Float, y: Float, tapped: Boolean) {
                        engine.endDrag()
                        if (fired) { fired = false; return }
                        val dx = x - sx; val dy = y - sy
                        if (max(abs(dx), abs(dy)) > 15f) {
                            if (abs(dx) > abs(dy)) engine.hop(if (dx > 0) 1 else -1, 0) else engine.hop(0, if (dy > 0) 1 else -1)
                        } else engine.tap()
                    }
                }
            }
            ArcadeField(engine, Modifier.widthIn(max = 400.dp), fieldW = 320f, fieldH = 480f, fx = engine.fx, input = input,
                overlay = { if (!engine.started) StartPrompt() }) { drawArcade(engine) }
            Text(L10n.t(mode.hint), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private val carColors = listOf(Color(0xFF32ADE6), Color(0xFFFF2D55), Color(0xFFFFCC00), Color(0xFFAF52DE), Color(0xFFFF9500), Color(0xFF00C7BE))
private val Yellow = Color(0xFFFFCC00)
private val Orange = Color(0xFFFF9500)
private val AccentBlue = Color(0xFF007AFF)

private fun Pen.drawArcade(e: ArcadeEngine) {
    when (e.mode) {
        ArcadeMode.Stack -> drawStack(e)
        ArcadeMode.KnifeSpin -> drawKnife(e)
        ArcadeMode.HelixDrop -> drawHelix(e)
        ArcadeMode.FlappyFlight -> drawFlappy(e)
        ArcadeMode.RoadHop -> drawRoad(e)
    }
    if (e.flash > 0) strokeBox(2f, 2f, 316f, 476f, Color(0xFFC6F31D).copy(alpha = (e.flash * 3).toFloat().coerceIn(0f, 1f)), 3f, 16f)
}

// MARK: Stack

private fun Pen.stackBlock(r: R, hue: Double) {
    val face = hsb(hue, 0.55f, 0.92f); val shade = hsb(hue, 0.7f, 0.62f)
    tile(r.minX, r.minY, r.w, r.h, face, shade, 4f)
    box(r.minX + 2, r.minY + 1, max(0f, r.w - 4), 4f, Color.White.copy(alpha = 0.35f), 2f)
}

private fun Pen.drawStack(e: ArcadeEngine) {
    val hue = e.stackHue
    ds.drawRect(Brush.verticalGradient(listOf(hsb(hue, 0.45f, 0.32f), hsb(hue + 0.08, 0.5f, 0.12f)), 0f, 480f), size = androidx.compose.ui.geometry.Size(320f, 480f))
    label("${e.placed}", 160f, 120f, 120f, Color.White.copy(alpha = 0.07f))
    xf(0f, -e.cameraLag) {
        for (b in e.bodies) stackBlock(b.rect, b.hue)
        e.ripple?.let { (r, t) ->
            val grow = t * 40
            strokeBox(r.minX - grow, r.minY - grow * 0.5f, r.w + grow * 2, r.h + grow, Color.White.copy(alpha = (1 - t * 2).coerceIn(0f, 1f)), 2.5f, 6f)
        }
        for (piece in e.debris) xf(piece.rect.midX, piece.rect.midY, piece.phase) {
            stackBlock(R(-piece.rect.w / 2, -11f, piece.rect.w, 22f), piece.hue)
        }
        if (e.state == GameState.Playing) {
            val next = (0.52 + (e.placed + 1) * 0.031) % 1.0
            val mb = e.movingBlock
            stackBlock(mb, next)
            if (e.perfectStreak >= 2) strokeBox(mb.minX - 2, mb.minY - 2, mb.w + 4, mb.h + 4, Color.White.copy(alpha = 0.5f + 0.3f * sin(e.time * 8)), 1.5f, 5f)
        }
    }
}

// MARK: Knife Spin

private fun Pen.knifeShape(length: Float, handle: Color) {
    // The origin is the blade tip; the handle extends along +y.
    polygon(listOf(Offset(0f, 0f), Offset(4f, length * 0.12f), Offset(4f, length * 0.55f), Offset(-3f, length * 0.55f), Offset(-3f, length * 0.12f)), Color(0xFFE6E6E6))
    box(-6f, length * 0.53f, 13f, 4f, Color(0xFF666666), 2f)
    box(-3.5f, length * 0.57f, 8f, length * 0.43f, handle, 3f)
}

private fun Pen.drawKnife(e: ArcadeEngine) {
    val cx = 160f; val cy = 180f - e.targetKick * 6
    val intro = 1 - e.levelIntro / 0.45f
    val radius = 80f * (0.6f + 0.4f * intro)
    val boss = e.isBossLevel
    val accent = Color(0xFFC6F31D)
    for (pin in e.pins) {
        xf(cx, cy, pin + e.angle - (PI / 2).toFloat()) { xf(0f, radius - 10f) { knifeShape(48f, accent) } }
    }
    val rings = if (boss) listOf(Color(0xFF8C1A1F), Color(0xFFBF2E33), Color(0xFF660F14)) else listOf(Color(0xFF9E6133), Color(0xFFC78549), Color(0xFF8C5430))
    circle(cx, cy + 4, radius + 2, Color.Black.copy(alpha = 0.35f))
    listOf(1.0f, 0.72f, 0.42f).forEachIndexed { i, f -> circle(cx, cy, radius * f, rings[i % rings.size]) }
    for (i in 0 until 6) {
        val a = i * (PI / 3).toFloat() + e.angle
        line(cx + cos(a) * 12, cy + sin(a) * 12, cx + cos(a) * radius * 0.92f, cy + sin(a) * radius * 0.92f, Color.Black.copy(alpha = 0.15f), 2f)
    }
    circle(cx, cy, 9f, if (boss) Color.Black.copy(alpha = 0.6f) else Color(0xFF66381A))
    for (apple in e.apples) {
        val a = apple + e.angle
        val x = cx + cos(a) * (radius + 9); val y = cy + sin(a) * (radius + 9)
        circle(x, y, 9f, Color.Red); circle(x - 3, y - 3, 3f, Color.White.copy(alpha = 0.5f)); oval(x - 1, y - 13, 5f, 6f, Color.Green)
    }
    if (e.state == GameState.Playing || e.projectile != null) xf(160f, e.projectile ?: 425f) { knifeShape(54f, Color.White.copy(alpha = 0.9f)) }
    for (i in 0 until e.totalPins) {
        val used = i >= e.remainingPins
        xf(22f, 452f - i * 18f, (-PI / 2).toFloat(), 0.3f) { knifeShape(54f, accent.copy(alpha = if (used) 0.2f else 0.9f)) }
    }
}

// MARK: Helix Drop

private fun Pen.drawHelix(e: ArcadeEngine) {
    boxBrush(148f, -10f, 24f, 500f, Brush.horizontalGradient(listOf(Color(0xFF404040), Color(0xFF808080), Color(0xFF404040)), 148f, 172f), 8f)
    for (body in e.bodies) {
        val safe = hsb(body.hue, 0.6f, 0.95f); val side = hsb(body.hue, 0.7f, 0.55f)
        // Split the solid part (gap excluded) into safe and red ranges in platform space.
        val cuts = ArrayList<Triple<Float, Float, Boolean>>()
        var cursor = body.rect.w
        for (zone in e.helixRedZones(body).sortedBy { it.start }) {
            if (zone.start > cursor) cuts.add(Triple(cursor, zone.start, false))
            cuts.add(Triple(zone.start, zone.endInclusive, true)); cursor = zone.endInclusive
        }
        if (cursor < 320f) cuts.add(Triple(cursor, 320f, false))
        for ((from, to, red) in cuts) {
            var start = (body.rect.minX + from) % 320f
            var length = to - from
            while (length > 0) {
                val piece = min(length, 320f - start)
                box(start, body.rect.minY + 6, piece, 10f, if (red) Color(0xFF80000D) else side, 0f)
                box(start, body.rect.minY, piece, 12f, if (red) Color.Red else safe, 0f)
                length -= piece; start = 0f
            }
        }
    }
    val x = e.px; val y = e.py
    if (e.fireball) {
        circle(x, y, 16f, Orange.copy(alpha = 0.35f)); circle(x, y, 11f, Orange); circle(x, y, 6f, Yellow)
    } else {
        circle(x, y + 2, 10f, Color.Black.copy(alpha = 0.3f))
        shiny(x, y, 10f, Color.White, Color(0xFFC6F31D))
    }
    if (e.combo >= 2 && !e.fireball) label("×${e.combo}", x + 26f, y - 14f, 16f, Yellow)
}

// MARK: Flappy Flight

private fun Pen.drawFlappy(e: ArcadeEngine) {
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF294080), Color(0xFF598CBF)), 0f, 480f), size = androidx.compose.ui.geometry.Size(320f, 480f))
    for (i in 0 until 5) {
        val x = (i * 90f - e.scroll * 0.15f) % 450f
        val cx = if (x < -60f) x + 450f else x
        val y = 60f + ((i * 53) % 120)
        box(cx, y, 58f, 18f, Color.White.copy(alpha = 0.18f), 9f)
        oval(cx + 12, y - 10, 28f, 24f, Color.White.copy(alpha = 0.18f))
    }
    for (i in 0 until 6) {
        val x = (i * 80f - e.scroll * 0.4f) % 480f
        val hx = if (x < -80f) x + 480f else x
        oval(hx - 20, 400f, 140f, 120f, Color(0xFF337359).copy(alpha = 0.7f))
    }
    for (b in e.bodies) {
        val r = b.rect
        val g = Brush.horizontalGradient(listOf(Color(0xFF33B359), Color(0xFF8CF28C), Color(0xFF268C4D)), r.minX, r.maxX)
        ds.drawRect(g, Offset(r.minX + 3, -10f), androidx.compose.ui.geometry.Size(r.w - 6, max(0f, r.minY + 10)))
        ds.drawRect(g, Offset(r.minX + 3, r.maxY), androidx.compose.ui.geometry.Size(r.w - 6, max(0f, 480 - r.maxY)))
        boxBrush(r.minX - 2, r.minY - 16, r.w + 4, 16f, g, 3f)
        boxBrush(r.minX - 2, r.maxY, r.w + 4, 16f, g, 3f)
        if (b.speed > 0) {
            strokeBox(r.minX - 2, r.minY - 16, r.w + 4, 16f, Yellow.copy(alpha = 0.7f), 1.5f, 3f)
            strokeBox(r.minX - 2, r.maxY, r.w + 4, 16f, Yellow.copy(alpha = 0.7f), 1.5f, 3f)
        }
    }
    for (c in e.coins) {
        val squash = abs(cos(e.time * 4 + c.y))
        oval(c.x - 9 * squash, c.y - 9, 18 * squash, 18f, Yellow)
        strokeOval(c.x - 6 * squash, c.y - 6, 12 * squash, 12f, Orange, 1.5f)
    }
    box(0f, 462f, 320f, 18f, Color(0xFF8C6640), 0f)
    for (i in 0 until 12) {
        val x = (i * 30f - e.scroll) % 360f
        box(if (x < -30f) x + 360f else x, 462f, 14f, 4f, Color.Green.copy(alpha = 0.8f), 0f)
    }
    // Bird tilts with its velocity and flaps its wing.
    xf(e.px, e.py, min(1.1f, max(-0.5f, e.vy / 420f))) {
        ds.drawOval(Brush.radialGradient(listOf(Yellow, Orange), Offset(-3f, -4f), 16f), Offset(-13f, -10f), androidx.compose.ui.geometry.Size(26f, 20f))
        val wing = if (e.flap > 0) -6 * e.flap else 2 * sin(e.time * 12)
        oval(-11f, -2 + wing, 13f, 8f, Color.White.copy(alpha = 0.9f))
        oval(2f, -8f, 8f, 8f, Color.White)
        oval(5.5f, -6f, 3.5f, 4f, Color.Black)
        polygon(listOf(Offset(10f, -1f), Offset(18f, 2f), Offset(10f, 5f)), Orange)
    }
}

// MARK: Road Hop

private fun Pen.drawRoad(e: ArcadeEngine) {
    for ((row, y) in e.visibleRoadRows) if (y > -30 && y < 510) {
        if (e.isGrassRow(row)) {
            box(0f, y - 25, 320f, 50f, Color(0xFF337F47).let { if (row % 2 == 0) Color(0xFF338047) else Color(0xFF33754A) }, 0f)
            for (i in 0 until 5) {
                val x = ((row * 37 + i * 71) % 300 + 10).toFloat()
                oval(x, y - 6 + (i % 3) * 6, 6f, 4f, Color.Green.copy(alpha = 0.6f))
            }
        } else {
            box(0f, y - 25, 320f, 50f, Color(0xFF333333), 0f)
            if (!e.isGrassRow(row + 1)) {
                var x = 6
                while (x < 320) { box(x.toFloat(), y - 26, 20f, 2f, Color.White.copy(alpha = 0.45f), 0f); x += 40 }
            }
        }
    }
    for (c in e.coins) {
        val bob = sin(e.time * 4 + c.x) * 2
        circle(c.x, c.y + bob, 8f, Yellow); circle(c.x, c.y + bob, 4.5f, Orange)
    }
    for (car in e.bodies) {
        val r = car.rect
        val color = if (car.value < 0) Color(0xFFD97333) else carColors[abs(car.value) % carColors.size]
        for (wx in listOf(r.minX + 10, r.maxX - 20)) {
            box(wx, r.minY - 3, 10f, 5f, Color.Black, 2f); box(wx, r.maxY - 2, 10f, 5f, Color.Black, 2f)
        }
        box(r.minX, r.minY, r.w, r.h, color, 7f)
        if (car.value < 0) {
            val cabX = if (car.speed > 0) r.maxX - 24 else r.minX + 4
            box(cabX, r.minY + 3, 20f, r.h - 6, Color.White.copy(alpha = 0.35f), 4f)
        } else box(r.midX - 13, r.minY + 5, 26f, r.h - 10, Color.Black.copy(alpha = 0.35f), 5f)
        val front = if (car.speed > 0) r.maxX - 3 else r.minX + 1
        oval(front, r.minY + 4, 3f, 5f, Yellow); oval(front, r.maxY - 9, 3f, 5f, Yellow)
    }
    // Hopper with a small arc and squash while jumping.
    val progress = e.hopTimer / 0.14f
    val lift = sin(progress * PI.toFloat()) * 8
    val x = e.px; val y = e.py - lift
    circle(e.px, e.py + 9, 9 - lift * 0.4f, Color.Black.copy(alpha = 0.3f))
    val w = 22 - lift * 0.4f; val h = 22 + lift * 0.5f
    box(x - w / 2, y - h / 2, w, h, Color.White, 7f)
    box(x - 4, y - h / 2 - 4, 8f, 6f, Color.Red, 2f)
    val eyeX = x + e.facing * 3
    circle(eyeX - 4, y - 3, 2f, Color.Black); circle(eyeX + 4, y - 3, 2f, Color.Black)
    box(x - 3, y + 1, 6f, 4f, Orange, 0f)
}
