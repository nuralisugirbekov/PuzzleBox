package com.nurali.puzzlebox.games

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
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
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.ArcadeFX
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Hearts
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.games.kit.rnd
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.max
import kotlin.math.sin
import kotlin.random.Random
import androidx.compose.ui.graphics.drawscope.clipRect

enum class ActionMode(val id: GameId, val rules: String) {
    RedGreen(GameId.RedGreen, "Tap only on green. Tapping on yellow or red costs a heart and pushes you back. Beware of fake greens!"),
    PerfectTiming(GameId.PerfectTiming, "Hit the centre of the zone for a Perfect and a streak bonus. Three misses end the game."),
    BubblePop(GameId.BubblePop, "Golden bubbles give big points, clocks add time. Never pop the red bombs!"),
    WhackMole(GameId.WhackMole, "Golden moles are worth more. Don't hit the moles holding bombs!"),
    ChainReaction(GameId.ChainReaction, "One tap sets off a chain. Hit the target to reach the next level."),
}

/** Bubbles: kind 0 normal, 1 golden, 2 bomb, 3 clock. Chain balls: colour index. */
class ActionParticle(var x: Float, var y: Float, var vx: Float = 0f, var vy: Float = 0f, var radius: Float = 10f,
                     var age: Double = 0.0, var life: Double = 3.0, var kind: Int = 0)

/** A mole out of its hole: kind 0 normal, 1 golden, 2 bomb. */
class ActionMole(val kind: Int, var age: Double = 0.0, var life: Double, var whacked: Boolean = false)

class ActionEngine(val mode: ActionMode) : FrameGame {
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var timeLeft by mutableDoubleStateOf(30.0)
    var lives by mutableIntStateOf(3)
    var progress by mutableIntStateOf(0)
    var level by mutableIntStateOf(1)
    var streak by mutableIntStateOf(0)
    val fx = ArcadeFX()

    val particles = ArrayList<ActionParticle>()
    val blasts = ArrayList<ActionParticle>()
    var signal = 1 // green, yellow, red = 1, 2, 0
    var zone = 150f
    var zoneVelocity = 0f
    var marker = 25f
    val holes = arrayOfNulls<ActionMole>(9)
    var usedTap = false
    var pushback = 0.0
    var clock = 0.0

    private var elapsed = 0.0
    private var spawnIn = 0.0
    private var cooldown = 0.0
    private var markerDirection = 1f
    private var lastHitTime = -10.0
    private var fakeGreen = false

    companion object {
        const val RED_GREEN_GOAL = 30
        fun holeCenterX(i: Int) = (i % 3) * 106.66f + 53.33f
        fun holeCenterY(i: Int) = (i / 3) * 110f + 125f
        val chainColors = listOf(Color(0xFF32ADE6), Color(0xFFFF2D55), Color(0xFFFFCC00), Color(0xFF00C7BE), Color(0xFFFF9500))
        fun chainColor(kind: Int) = chainColors[kind % 5]
    }

    val chainBallCount get() = min(30 + (level - 1) * 3, 48)
    val chainTarget get() = min(10 + level * 3, chainBallCount - 2)
    val timed get() = mode == ActionMode.RedGreen || mode == ActionMode.BubblePop || mode == ActionMode.WhackMole
    val usesLives get() = mode != ActionMode.ChainReaction
    val maxLives get() = if (mode == ActionMode.BubblePop || mode == ActionMode.WhackMole) 5 else 3
    /** Points per hit grow with a quick streak of hits. */
    val multiplier get() = min(4, 1 + streak / 4)
    /** Half-width of the Perfect Timing zone, shrinking as you score. */
    val zoneHalfWidth get() = max(11f, 32f - progress * 0.9f)

    init { restart() }

    override fun restart() {
        state = GameState.Playing; score = 0; started = false; timeLeft = 30.0; lives = maxLives
        particles.clear(); blasts.clear(); fx.reset()
        signal = 1; progress = 0; streak = 0; level = 1; pushback = 0.0; clock = 0.0
        zone = rnd(80f, 240f); zoneVelocity = 0f; marker = 25f; holes.fill(null); usedTap = false
        elapsed = 0.0; spawnIn = 1.0; cooldown = 0.0; markerDirection = 1f; lastHitTime = -10.0; fakeGreen = false
        if (mode == ActionMode.ChainReaction) setupChainLevel()
    }

    private fun lose() { state = GameState.GameOver(won = false); Haptics.error() }

    private fun gain(base: Int, x: Float, y: Float, color: Color = Color.White) {
        val points = base * multiplier
        score += points
        fx.popup(if (multiplier > 1) "+$points ×$multiplier" else "+$points", x, y - 20, color, if (multiplier > 1) 18f else 15f)
    }

    private fun loseLife(x: Float, y: Float) {
        lives--; streak = 0
        fx.burst(x, y, Color.Red, 16, 160f, 200f, 3f)
        fx.kick(6f); fx.flash(Color.Red, 0.25f)
        Haptics.error(); Sfx.wrong()
        if (lives <= 0) lose()
    }

    fun tap(x: Float, y: Float) {
        if (state != GameState.Playing) return
        if (!started) { started = true; return }
        if (cooldown > 0) return
        when (mode) {
            ActionMode.RedGreen -> tapRedGreen()
            ActionMode.PerfectTiming -> tapTiming()
            ActionMode.BubblePop -> tapBubble(x, y)
            ActionMode.WhackMole -> tapMole(x, y)
            ActionMode.ChainReaction -> {
                if (usedTap) return
                usedTap = true; blasts.add(ActionParticle(x, y, radius = 2f, life = 2.5))
                Haptics.tap(); Sfx.tap()
            }
        }
    }

    // MARK: Red Light, Green Light

    private fun tapRedGreen() {
        val runnerY = 420f - progress.toFloat() / RED_GREEN_GOAL * 180f
        if (signal != 1) {
            progress = max(0, progress - 3); pushback = 0.4
            loseLife(160f, runnerY)
            cooldown = 0.3
            return
        }
        progress++; streak++
        score += 10
        cooldown = 0.12
        Haptics.tap(); Sfx.tap()
        fx.burst(160f, runnerY + 10, Color.White.copy(alpha = 0.7f), 3, 50f, 80f, 2f, 0.3f)
        if (progress >= RED_GREEN_GOAL) {
            val bonus = timeLeft.toInt() * 10 + lives * 50
            score += bonus
            fx.popup("+$bonus", 160f, 230f, Color.Green, 24f)
            state = GameState.GameOver(won = true)
        }
    }

    // MARK: Perfect Timing

    private fun tapTiming() {
        val distance = abs(marker - zone)
        val half = zoneHalfWidth
        if (distance > half) {
            loseLife(marker, 230f)
            cooldown = 0.35
            return
        }
        progress++
        if (distance <= half * 0.3f) {
            streak++
            gain(30, marker, 230f, Color.Yellow)
            fx.popup(L10n.t("Perfect!"), 160f, 150f, Color.Yellow, 22f)
            fx.burst(marker, 230f, Color.Yellow, 18, 160f, 100f, 3f)
            Haptics.success(); Sfx.point()
        } else {
            streak = 0
            gain(10, marker, 230f)
            fx.burst(marker, 230f, Color(0xFF007AFF), 8, 100f, 100f, 2.5f)
            Haptics.tap(); Sfx.tap()
        }
        zone = rnd(65f, 255f)
        // Later on, the zone itself drifts.
        zoneVelocity = if (progress >= 8) (if (Random.nextBoolean()) 1 else -1) * rnd(20f, min(90f, 20f + progress * 3f)) else 0f
        cooldown = 0.25
    }

    // MARK: Bubble Pop

    private fun tapBubble(x: Float, y: Float) {
        val i = particles.indexOfLast { hypot(it.x - x, it.y - y) < it.radius + 8 }
        if (i < 0) return
        val bubble = particles.removeAt(i)
        when (bubble.kind) {
            2 -> { fx.burst(bubble.x, bubble.y, Color(0xFFFF9500), 26, 220f, 0f, 3.5f); loseLife(bubble.x, bubble.y); return }
            3 -> {
                timeLeft = min(60.0, timeLeft + 3)
                fx.popup("+3s", bubble.x, bubble.y - 20, Color(0xFF32ADE6), 18f)
                fx.burst(bubble.x, bubble.y, Color(0xFF32ADE6), 14, 140f, 0f, 2.5f)
                Haptics.move(); Sfx.win()
                return
            }
        }
        streak = if (elapsed - lastHitTime < 0.9) streak + 1 else 1
        lastHitTime = elapsed
        val golden = bubble.kind == 1
        gain(if (golden) 50 else 10, bubble.x, bubble.y, if (golden) Color.Yellow else Color.White)
        fx.burst(bubble.x, bubble.y, if (golden) Color.Yellow else Color(0xFF32ADE6), if (golden) 20 else 10, 140f, 60f, 2.5f, 0.45f)
        Haptics.tap(); Sfx.point()
    }

    // MARK: Whack-a-Mole

    private fun tapMole(x: Float, y: Float) {
        val c = (x / 106.66f).toInt(); val r = ((y - 70f) / 110f).toInt()
        if (y < 70f || c !in 0..2 || r !in 0..2) return
        val i = r * 3 + c
        val cx = holeCenterXOf(i); val cy = ActionEngine.holeCenterY(i)
        val mole = holes[i]
        if (mole == null || mole.whacked) {
            // Whacking an empty hole breaks the streak but costs nothing else.
            streak = 0; Sfx.tap()
            return
        }
        mole.whacked = true
        mole.life = mole.age + 0.25
        if (mole.kind == 2) {
            fx.burst(cx, cy, Color(0xFFFF9500), 26, 220f, 100f, 3.5f)
            loseLife(cx, cy)
        } else {
            streak = if (elapsed - lastHitTime < 1.3) streak + 1 else 1
            lastHitTime = elapsed
            val golden = mole.kind == 1
            gain(if (golden) 50 else 10, cx, cy, if (golden) Color.Yellow else Color.White)
            fx.burst(cx, cy, if (golden) Color.Yellow else Color(0xFFBF8059), 12, 150f, 300f, 3f)
            fx.kick(2f)
            Haptics.move(); Sfx.point()
        }
    }

    private fun holeCenterXOf(i: Int) = ActionEngine.holeCenterX(i)

    // MARK: Chain Reaction

    private fun setupChainLevel() {
        particles.clear(); blasts.clear(); usedTap = false; progress = 0
        val boost = (level - 1) * 4f
        for (i in 0 until chainBallCount) {
            val heading = rnd(0f, (Math.PI * 2).toFloat()); val speed = rnd(25f, 65f) + boost
            particles.add(ActionParticle(rnd(15f, 305f), rnd(25f, 435f), cos(heading) * speed, sin(heading) * speed, radius = 6f, kind = i % 5))
        }
    }

    // MARK: Frame loop

    override fun advance(dt: Double) {
        fx.update(dt.toFloat())
        if (!started || state != GameState.Playing) return
        val total = min(0.1, max(0.0, dt))
        var rest = total
        while (rest > 0 && state == GameState.Playing) {
            val step = min(rest, 1.0 / 120); update(step); rest -= step
        }
        clock += total
    }

    private fun update(dt: Double) {
        elapsed += dt; spawnIn -= dt; cooldown = max(0.0, cooldown - dt); pushback = max(0.0, pushback - dt)
        if (timed) {
            timeLeft = max(0.0, timeLeft - dt)
            if (timeLeft == 0.0) { state = GameState.GameOver(won = mode != ActionMode.RedGreen || progress >= RED_GREEN_GOAL); return }
        }
        val step = dt.toFloat()
        when (mode) {
            ActionMode.RedGreen -> if (spawnIn <= 0) {
                if (fakeGreen) {
                    // A brief yellow flicker that turns back to green.
                    fakeGreen = false; signal = 1; spawnIn = rnd(0.8, 1.6)
                } else if (signal == 1) {
                    signal = 2
                    fakeGreen = progress > 8 && Random.nextInt(4) == 0
                    spawnIn = if (fakeGreen) 0.3 else max(0.3, 0.55 - progress * 0.006)
                } else if (signal == 2) { signal = 0; spawnIn = rnd(0.9, 2.1) }
                else { signal = 1; spawnIn = rnd(1.2, 2.8) }
            }
            ActionMode.PerfectTiming -> {
                marker += markerDirection * (160 + progress * 9) * step
                if (marker > 295f) { marker = 295f; markerDirection = -1f }
                if (marker < 25f) { marker = 25f; markerDirection = 1f }
                if (zoneVelocity != 0f) {
                    zone += zoneVelocity * step
                    if (zone < 50f || zone > 270f) { zoneVelocity *= -1; zone = zone.coerceIn(50f, 270f) }
                }
            }
            ActionMode.BubblePop -> updateBubbles(dt)
            ActionMode.WhackMole -> updateMoles(dt)
            ActionMode.ChainReaction -> updateChain(dt)
        }
    }

    private fun updateBubbles(dt: Double) {
        if (spawnIn <= 0) {
            val roll = Random.nextInt(100)
            val kind = if (elapsed > 4 && roll < 8) 2 else if (roll < 16) 1 else if (roll < 21) 3 else 0
            val radius = if (kind == 1) 18f else if (kind == 3) 20f else rnd(20f, 28f)
            val life = if (kind == 1) 1.3 else if (kind == 2) 2.6 else 2.2 - min(0.7, elapsed / 60)
            particles.add(ActionParticle(rnd(32f, 288f), rnd(70f, 420f), rnd(-12f, 12f), rnd(-30f, -10f), radius, life = life, kind = kind))
            spawnIn = max(0.28, 0.65 - elapsed / 70)
        }
        for (p in particles) { p.age += dt; p.x += p.vx * dt.toFloat(); p.y += p.vy * dt.toFloat() }
        // Missing a normal or golden bubble costs a life; bombs and clocks just fade.
        val missed = particles.filter { it.age >= it.life && (it.kind == 0 || it.kind == 1) }
        particles.removeAll { it.age >= it.life }
        for (b in missed) if (state == GameState.Playing) {
            fx.burst(b.x, b.y, Color.Gray, 6, 60f, 0f, 2f)
            loseLife(b.x, b.y)
        }
    }

    private fun updateMoles(dt: Double) {
        for (i in holes.indices) {
            val mole = holes[i] ?: continue
            mole.age += dt
            if (mole.age >= mole.life) {
                // An escaped normal or golden mole costs a life.
                if (!mole.whacked && mole.kind != 2) loseLife(holeCenterX(i), holeCenterY(i))
                holes[i] = null
            }
        }
        if (spawnIn > 0 || state != GameState.Playing) return
        val free = holes.indices.filter { holes[it] == null }
        val maxOut = if (elapsed > 18) 3 else if (elapsed > 8) 2 else 1
        if (free.isNotEmpty() && holes.count { it != null } < maxOut) {
            val i = free.random()
            val roll = Random.nextInt(100)
            val kind = if (elapsed > 3 && roll < 15) 2 else if (roll < 25) 1 else 0
            val life = max(0.75, 1.35 - elapsed / 45) * (if (kind == 1) 0.75 else 1.0)
            holes[i] = ActionMole(kind, life = life)
        }
        spawnIn = max(0.35, 0.9 - elapsed / 50)
    }

    private fun updateChain(dt: Double) {
        val d = dt.toFloat()
        for (p in particles) {
            p.x += p.vx * d; p.y += p.vy * d
            if (p.x < 6f) { p.x = 6f; p.vx = abs(p.vx) }
            if (p.x > 314f) { p.x = 314f; p.vx = -abs(p.vx) }
            if (p.y < 6f) { p.y = 6f; p.vy = abs(p.vy) }
            if (p.y > 454f) { p.y = 454f; p.vy = -abs(p.vy) }
        }
        for (b in blasts) {
            b.age += dt
            val age = b.age
            b.radius = (if (age < 0.5) age / 0.5 * 43 else if (age < 1.7) 43.0 else max(0.0, (2.5 - age) / 0.8 * 43)).toFloat()
        }
        val hit = particles.filter { ball -> blasts.any { hypot(it.x - ball.x, it.y - ball.y) < it.radius + ball.radius } }
        if (hit.isNotEmpty()) {
            for (ball in hit) {
                progress++
                // Later links in the chain are worth more.
                score += 10 + 2 * progress
                blasts.add(ActionParticle(ball.x, ball.y, radius = 2f, life = 2.5, kind = ball.kind))
                fx.burst(ball.x, ball.y, chainColor(ball.kind), 6, 90f, 0f, 2.5f, 0.5f)
                if (progress % 5 == 0) fx.popup("×$progress", ball.x, ball.y, Color.White, 16f)
            }
            particles.removeAll(hit.toSet())
            Sfx.point()
            if (progress == chainTarget) { fx.popup(L10n.t("Target reached!"), 160f, 200f, Color.Green, 22f); Sfx.win() }
        }
        blasts.removeAll { it.age >= it.life }
        if (usedTap && blasts.isEmpty()) {
            if (progress >= chainTarget) {
                val bonus = if (particles.isEmpty()) 200 else 50
                score += bonus
                fx.popup(L10n.f("Level %d", level + 1), 160f, 230f, Color.Yellow, 26f)
                if (particles.isEmpty()) fx.popup(L10n.t("Board clear! +200"), 160f, 270f, Color(0xFF00C7BE), 18f)
                Haptics.success(); Sfx.win()
                level++
                setupChainLevel()
            } else {
                state = GameState.GameOver(won = level > 1)
            }
        }
    }
}

@Composable
fun ActionScreen(mode: ActionMode, onExit: () -> Unit) {
    val engine = remember { ActionEngine(mode) }
    val pal = Pal.current
    GameContainer(mode.id, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (engine.timed) Text("⏱ 0:%02d".format(ceil(engine.timeLeft).toInt()), fontWeight = FontWeight.Bold,
                    color = if (engine.timeLeft < 6) Color.Red else pal.accent)
                if (mode == ActionMode.ChainReaction) Text(L10n.f("Level %d", engine.level), color = pal.accent, fontWeight = FontWeight.Bold)
                if (engine.multiplier > 1) Text("🔥×${engine.multiplier}", color = Color(0xFFFF9500), fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                when (mode) {
                    ActionMode.ChainReaction -> Text("${engine.progress} / ${engine.chainTarget}", color = pal.accent, fontWeight = FontWeight.Bold)
                    ActionMode.RedGreen -> Text("${engine.progress} / ${ActionEngine.RED_GREEN_GOAL}", color = pal.accent, fontWeight = FontWeight.Bold)
                    else -> {}
                }
                if (engine.usesLives) Hearts(engine.lives, engine.maxLives)
            }
            ArcadeField(
                engine, Modifier.widthIn(max = 380.dp), fx = engine.fx,
                input = remember(engine) {
                    object : FieldInput() {
                        override fun onDown(x: Float, y: Float) { engine.tap(x, y) }
                    }
                },
                overlay = { if (!engine.started) StartPrompt() },
            ) { drawAction(engine) }
            Text(L10n.t(mode.rules), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

private fun com.nurali.puzzlebox.games.kit.Pen.drawAction(e: ActionEngine) {
    val green = Color(0xFF34C759); val yellow = Color(0xFFFFCC00); val red = Color(0xFFFF3B30); val cyan = Color(0xFF32ADE6)
    when (e.mode) {
        ActionMode.RedGreen -> {
            // Traffic light with three lamps.
            box(120f, 18f, 80f, 170f, Color(0xFF1F1F1F), 20f)
            listOf(red, yellow, green).forEachIndexed { i, color ->
                val lit = (i == 0 && e.signal == 0) || (i == 1 && e.signal == 2) || (i == 2 && e.signal == 1)
                val cy = 50f + i * 53f
                if (lit) circle(160f, cy, 32f, color.copy(alpha = 0.3f))
                circle(160f, cy, 22f, if (lit) color else color.copy(alpha = 0.15f))
            }
            label(L10n.t(if (e.signal == 1) "Go!" else "Stop!"), 160f, 210f, 26f, if (e.signal == 1) green else red)
            // Track with lane stripes, finish line and the runner.
            box(125f, 232f, 70f, 200f, Color(0xFF734033), 8f)
            var y = 242f
            while (y < 432f) { box(158f, y, 4f, 10f, Color.White.copy(alpha = 0.25f), 1f); y += 20f }
            for (k in 0 until 7) box(125f + k * 10f, 232f, 10f, 6f, if (k % 2 == 0) Color.White else Color.Black, 0f)
            val runnerY = 420f - e.progress.toFloat() / ActionEngine.RED_GREEN_GOAL * 180f
            val bob = if (e.pushback > 0) sin(e.clock * 60).toFloat() * 3f else 0f
            shiny(160f + bob, runnerY, 13f, Color.White, Color(0xFF007AFF))
        }
        ActionMode.PerfectTiming -> {
            box(20f, 195f, 280f, 70f, Color(0xFF292929), 14f)
            val half = e.zoneHalfWidth
            val accent = Color(0xFF007AFF)
            boxBrush(e.zone - half, 195f, half * 2, 70f, androidx.compose.ui.graphics.Brush.horizontalGradient(
                listOf(accent.copy(alpha = 0.3f), accent.copy(alpha = 0.8f), accent.copy(alpha = 0.3f)), e.zone - half, e.zone + half), 10f)
            box(e.zone - half * 0.3f, 195f, half * 0.6f, 70f, yellow.copy(alpha = 0.7f), 6f)
            box(e.marker - 4f, 180f, 8f, 100f, Color.White.copy(alpha = 0.3f), 4f)
            box(e.marker - 2.5f, 183f, 5f, 94f, Color.White, 2.5f)
            label("${e.progress}", 160f, 340f, 54f, Color.White.copy(alpha = 0.12f))
        }
        ActionMode.BubblePop -> for (p in e.particles) {
            val fade = 1 - p.age / p.life
            // Bubbles grow in, then shrink as they are about to pop.
            val scale = min(1.0, p.age * 6).toFloat() * (if (fade < 0.25) (0.75 + fade).toFloat() else 1f)
            val r = p.radius * scale
            when (p.kind) {
                1 -> { circle(p.x, p.y, r * 1.3f, yellow.copy(alpha = 0.2f)); shiny(p.x, p.y, r, Color.White, yellow) }
                2 -> { shiny(p.x, p.y, r, Color(0xFFFF6666), Color(0xFF800010)); label("🔥", p.x, p.y, r * 0.9f, Color.White) }
                3 -> { shiny(p.x, p.y, r, Color.White, cyan); label("⏰", p.x, p.y, r * 0.9f, Color.White) }
                else -> {
                    circle(p.x, p.y, r, cyan.copy(alpha = 0.25f))
                    circle(p.x, p.y, r, cyan.copy(alpha = 0.8f), 2f)
                    circle(p.x - r * 0.35f, p.y - r * 0.4f, r * 0.22f, Color.White.copy(alpha = 0.8f))
                }
            }
            if (fade < 0.3 && p.kind != 2) circle(p.x, p.y, r + 4, red.copy(alpha = (0.6 * (0.3 - fade) / 0.3).toFloat()), 2f)
        }
        ActionMode.WhackMole -> {
            box(0f, 0f, 320f, 460f, Color(0xFF408038), 0f)
            for (i in 0 until 9) {
                val px = ActionEngine.holeCenterX(i); val py = ActionEngine.holeCenterY(i)
                ds.drawOval(Color(0xFF402614), androidx.compose.ui.geometry.Offset(px - 42f, py + 2f), androidx.compose.ui.geometry.Size(84f, 34f))
                e.holes[i]?.let { mole ->
                    // Rise out of the hole, then duck back down.
                    val t = (mole.age / mole.life).toFloat()
                    val rise = min(1f, min(t, 1 - t) * 6f)
                    val cx = px; val cy = py + 30f - rise * 34f
                    ds.clipRect(px - 45f, py - 70f, px + 45f, py + 20f) {
                        val (c1, c2) = if (mole.kind == 1) yellow to Color(0xFFFF9500) else Color(0xFFB38059) to Color(0xFF734D2E)
                        boxBrush(cx - 26f, cy - 26f, 52f, 60f, androidx.compose.ui.graphics.Brush.verticalGradient(listOf(c1, c2), cy - 26f, cy + 30f), 26f)
                        if (mole.whacked) label("x  x", cx, cy - 6f, 12f, Color.Black)
                        else {
                            ds.drawOval(Color.Black, androidx.compose.ui.geometry.Offset(cx - 13f, cy - 12f), androidx.compose.ui.geometry.Size(7f, 8f))
                            ds.drawOval(Color.Black, androidx.compose.ui.geometry.Offset(cx + 6f, cy - 12f), androidx.compose.ui.geometry.Size(7f, 8f))
                        }
                        ds.drawOval(Color(0xFFFF2D55), androidx.compose.ui.geometry.Offset(cx - 6f, cy - 3f), androidx.compose.ui.geometry.Size(12f, 8f))
                        if (mole.kind == 2) {
                            val bx = cx + 22f; val by = cy + 6f
                            circle(bx, by, 11f, Color.Black)
                            circle(bx + 5f, by - 14f, 3f, if (sin(e.clock * 25) > 0) Color(0xFFFF9500) else yellow)
                        }
                    }
                }
                // Front lip of the hole hides the mole's lower body.
                ds.drawOval(Color(0xFF529945), androidx.compose.ui.geometry.Offset(px - 44f, py + 20f), androidx.compose.ui.geometry.Size(88f, 26f))
            }
        }
        ActionMode.ChainReaction -> {
            for (p in e.particles) shiny(p.x, p.y, p.radius, Color.White, ActionEngine.chainColor(p.kind))
            for (p in e.blasts) {
                val color = ActionEngine.chainColor(p.kind)
                circle(p.x, p.y, p.radius, color.copy(alpha = 0.28f))
                circle(p.x, p.y, p.radius, color, 2f)
            }
            if (!e.usedTap && e.started) label(L10n.f("Destroy %d", e.chainTarget), 160f, 30f, 16f, Color.White.copy(alpha = 0.7f))
        }
    }
}

