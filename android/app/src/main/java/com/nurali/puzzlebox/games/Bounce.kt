package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.ArcadeFX
import com.nurali.puzzlebox.games.kit.ArcadeField
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.P2
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.R
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

class BounceLevel(val width: Float, val spawnX: Float, val spawnY: Float, val platforms: List<R>, val spikes: List<R>, val rings: List<P2>, val exit: R) {
    companion object {
        private fun r(x: Number, y: Number, w: Number, h: Number) = R(x.toFloat(), y.toFloat(), w.toFloat(), h.toFloat())
        private fun p(x: Number, y: Number) = P2(x.toFloat(), y.toFloat())

        // Original layouts. Maximum jump height is ~108 units; gaps stay below 100.
        val levels: List<BounceLevel> = listOf(
            BounceLevel(1080f, 45f, 348f,
                listOf(r(0, 365, 380, 75), r(450, 365, 630, 75), r(170, 295, 100, 16), r(560, 285, 110, 16), r(740, 235, 110, 16)),
                listOf(r(300, 347, 35, 18), r(870, 347, 40, 18)),
                listOf(p(100, 340), p(215, 265), p(415, 305), p(610, 255), p(790, 205), p(960, 335)),
                r(1020, 310, 34, 55)),
            BounceLevel(1230f, 45f, 348f,
                listOf(r(0, 365, 290, 75), r(375, 365, 330, 75), r(790, 365, 440, 75), r(150, 295, 95, 16), r(325, 240, 100, 16), r(500, 190, 105, 16), r(690, 255, 100, 16), r(930, 290, 110, 16)),
                listOf(r(580, 347, 55, 18), r(1060, 347, 40, 18)),
                listOf(p(195, 265), p(370, 210), p(550, 160), p(740, 225), p(860, 335), p(980, 260)),
                r(1170, 310, 34, 55)),
            BounceLevel(1400f, 45f, 348f,
                listOf(r(0, 365, 250, 75), r(330, 365, 360, 75), r(780, 365, 290, 75), r(1150, 365, 250, 75), r(140, 295, 90, 16), r(310, 235, 110, 16), r(510, 175, 100, 16), r(700, 245, 110, 16), r(930, 280, 100, 16), r(1100, 235, 100, 16)),
                listOf(r(430, 347, 40, 18), r(835, 347, 45, 18), r(1230, 347, 45, 18)),
                listOf(p(185, 265), p(365, 205), p(560, 145), p(750, 215), p(980, 250), p(1150, 205), p(1310, 335)),
                r(1340, 310, 34, 55)),
        ) + (0 until 9).map { index ->
            // Four safe landing areas separated by jumpable gaps.
            val length = (270 + (index % 3) * 25).toFloat()
            val gap = (60 + (index / 3) * 10).toFloat()
            val width = length * 4 + gap * 3
            val platforms = ArrayList<R>(); val spikes = ArrayList<R>(); val rings = ArrayList<P2>()
            for (section in 0 until 4) {
                val x = section * (length + gap)
                val height = (55 + ((index + section) % 3) * 12).toFloat()
                platforms.add(R(x, 365f, length, 75f))
                platforms.add(R(x + 85, 365 - height, 90f, 16f))
                rings.add(P2(x + 125, 335 - height))
                if (section < 3) rings.add(P2(x + length + gap / 2, 305f))
                if (section > 0 || index > 2) spikes.add(R(x + 205, 347f, 25f + (index % 3) * 5, 18f))
            }
            BounceLevel(width, 45f, 348f, platforms, spikes, rings, R(width - 55, 310f, 34f, 55f))
        }
    }
}

/** A spiky critter patrolling a stretch of floor. Landing on it from above defeats it. */
class BounceEnemy(var x: Float, val y: Float, val minX: Float, val maxX: Float, var speed: Float, var alive: Boolean = true) {
    companion object { const val RADIUS = 11f }
}

class BounceEngine : FrameGame {
    override var score by mutableIntStateOf(0)
    private var stateBacking by mutableStateOf<GameState>(GameState.Playing)
    override var state: GameState
        get() = stateBacking
        set(v) { stateBacking = v; if (v != GameState.Playing) releaseControls() }
    var levelIndex by mutableIntStateOf(0)
    var lives by mutableIntStateOf(3)
    var started by mutableStateOf(false)
    var message by mutableStateOf("")
    var collectedCount by mutableIntStateOf(0)
    var transition by mutableStateOf(0.0)
    val fx = ArcadeFX()

    var bx = 0f; var by = 0f
    var rotation = 0f
    val collected = HashSet<Int>()
    var invulnerable = 0.0
    val enemies = ArrayList<BounceEnemy>()
    var clock = 0f

    private var vx = 0f; private var vy = 0f
    private var left = false; private var right = false; private var jumpHeld = false
    private var jumpBuffer = 0.0; private var coyote = 0.0
    private var grounded = false
    private var changingLevel = false
    val radius = 12f

    val level get() = BounceLevel.levels[levelIndex]
    val cameraX get() = max(0f, min(level.width - 360f, bx - 130f))
    val gateOpen get() = collected.size == level.rings.size

    init { restart() }

    override fun restart() {
        state = GameState.Playing; score = 0; levelIndex = 0; lives = 3; started = false
        collected.clear(); collectedCount = 0; transition = 0.0; changingLevel = false; message = ""; fx.reset(); clock = 0f
        setupEnemies(); respawn()
    }

    fun start() { if (state == GameState.Playing) started = true }

    private val canControl get() = started && state == GameState.Playing && transition == 0.0
    // Pressing any control also starts the round, so the first touch is never wasted.
    fun holdLeft(v: Boolean) { if (v) start(); left = v && canControl }
    fun holdRight(v: Boolean) { if (v) start(); right = v && canControl }
    fun holdJump(v: Boolean) { if (v) start(); if (v && !jumpHeld && canControl) jumpBuffer = 0.13; jumpHeld = v && canControl }
    fun releaseControls() { left = false; right = false; jumpHeld = false; jumpBuffer = 0.0 }

    private fun respawn() {
        bx = level.spawnX; by = level.spawnY; vx = 0f; vy = 0f; rotation = 0f; grounded = false; coyote = 0.0
        invulnerable = 0.8; releaseControls()
    }

    override fun advance(dt: Double) {
        fx.update(min(0.08, dt).toFloat())
        if (!started || state != GameState.Playing) return
        val d = min(0.08, max(0.0, dt))
        clock += d.toFloat()
        if (transition > 0) {
            transition = max(0.0, transition - d)
            if (transition == 0.0) {
                if (changingLevel) { levelIndex++; collected.clear(); collectedCount = 0; changingLevel = false; setupEnemies() }
                message = ""; respawn()
            }
            return
        }
        var remaining = d
        while (remaining > 0 && transition == 0.0 && state == GameState.Playing) { val step = min(remaining, 1.0 / 180); update(step); remaining -= step }
    }

    private fun update(dt: Double) {
        val d = dt.toFloat()
        invulnerable = max(0.0, invulnerable - dt); jumpBuffer = max(0.0, jumpBuffer - dt)
        coyote = if (grounded) 0.1 else max(0.0, coyote - dt)
        if (jumpBuffer > 0 && coyote > 0) { vy = -405f; grounded = false; coyote = 0.0; jumpBuffer = 0.0; Haptics.tap(); Sfx.tap() }
        val direction = (if (right) 1f else 0f) - (if (left) 1f else 0f)
        val target = direction * 180; val acceleration = if (direction == 0f) 1000f else 1300f
        vx += min(acceleration * d, max(-acceleration * d, target - vx))
        vy = min(600f, vy + 760 * d)
        val oldX = bx
        bx += vx * d
        // Resolve axes separately so floors, walls and platform undersides are solid.
        for (p in level.platforms) if (by + radius > p.minY + 0.5f && by - radius < p.maxY - 0.5f) {
            if (vx > 0 && oldX + radius <= p.minX + 0.5f && bx + radius > p.minX) { bx = p.minX - radius; vx = 0f }
            if (vx < 0 && oldX - radius >= p.maxX - 0.5f && bx - radius < p.maxX) { bx = p.maxX + radius; vx = 0f }
        }
        bx = min(level.width - radius, max(radius, bx)); rotation += (bx - oldX) / radius
        val oldY = by
        by += vy * d; grounded = false
        for (p in level.platforms) if (bx + radius > p.minX + 0.5f && bx - radius < p.maxX - 0.5f) {
            if (vy >= 0 && oldY + radius <= p.minY + 0.5f && by + radius >= p.minY) { by = p.minY - radius; vy = 0f; grounded = true }
            else if (vy < 0 && oldY - radius >= p.maxY - 0.5f && by - radius < p.maxY) { by = p.maxY + radius; vy = 0f }
        }
        for ((i, ring) in level.rings.withIndex()) if (i !in collected && hypot(bx - ring.x, by - ring.y) < 24) {
            collected.add(i); collectedCount = collected.size; score += 50; Haptics.success(); Sfx.point()
            fx.burst(ring.x, ring.y, Color.Yellow, 14, 120f, 200f, 2.5f, 0.5f)
            fx.popup("+50", ring.x, ring.y - 20, Color.Yellow)
            if (gateOpen) fx.popup(L10n.t("Exit open!"), ring.x, ring.y - 44, Color.Green, 18f)
        }
        if (by > 460 || (invulnerable == 0.0 && level.spikes.any { touches(it) })) { die(); return }
        for (e in enemies) {
            if (!e.alive) continue
            e.x += e.speed * d
            if (e.x < e.minX || e.x > e.maxX) e.speed *= -1
            if (hypot(bx - e.x, by - e.y) >= radius + BounceEnemy.RADIUS) continue
            if (vy > 0 && by < e.y - 4) {
                // Stomp: defeat it and bounce off.
                e.alive = false
                vy = -330f; score += 100
                fx.burst(e.x, e.y, Color(0xFFAF52DE), 22, 170f, 400f, 3f)
                fx.popup("+100", e.x, e.y - 24, Color.White, 18f)
                fx.kick(4f); Haptics.heavy(); Sfx.wrong()
            } else if (invulnerable == 0.0) { die(); return }
        }
        val ex = level.exit
        if (gateOpen && bx >= ex.minX - radius && bx <= ex.maxX + radius && by >= ex.minY && by <= ex.maxY) {
            score += 250
            if (levelIndex == BounceLevel.levels.size - 1) { score += lives * 100; state = GameState.GameOver(won = true) }
            else { changingLevel = true; message = "Level complete!"; transition = 1.0; releaseControls(); Sfx.win() }
        }
    }

    /** From level 2 on, critters patrol the wider floor sections (never the spawn floor). */
    private fun setupEnemies() {
        enemies.clear()
        if (levelIndex <= 0) return
        val floors = level.platforms.filter { it.h > 40 && it.w >= 220 && !(level.spawnX >= it.minX && level.spawnX <= it.maxX) }
        val count = min(floors.size, 1 + levelIndex / 3)
        for ((i, floor) in floors.take(count).withIndex()) {
            val mn = floor.minX + 30; val mx = floor.maxX - 30
            enemies.add(BounceEnemy((mn + mx) / 2, floor.minY - BounceEnemy.RADIUS, mn, mx, (if (i % 2 == 0) 1 else -1) * (45f + levelIndex * 4)))
        }
    }

    private fun touches(rect: R): Boolean {
        val x = min(rect.maxX, max(rect.minX, bx)); val y = min(rect.maxY, max(rect.minY, by))
        return hypot(bx - x, by - y) < radius - 2
    }

    private fun die() {
        fx.burst(bx, by, Color.Red, 26, 200f, 300f, 3.5f, 0.7f)
        fx.kick(7f)
        lives--; Haptics.error(); releaseControls()
        if (lives == 0) state = GameState.GameOver(won = false)
        else { message = "Try again"; transition = 0.8; changingLevel = false; Sfx.wrong() }
        // Collected rings remain collected, so a respawn cannot farm points.
    }
}

@Composable
fun BounceScreen(onExit: () -> Unit) {
    val engine = remember { BounceEngine() }
    val pal = Pal.current
    GameContainer(GameId.Bounce, engine, onExit) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L10n.f("Level %d of %d", engine.levelIndex + 1, BounceLevel.levels.size), color = pal.accent, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(1f))
                Text("◯ ${engine.collectedCount}/${engine.level.rings.size}", color = pal.accent, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                Text("❤ ${engine.lives}", color = Color(0xFFFF2D55), fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
            val tapToStart = remember(engine) { object : FieldInput() { override fun onDown(x: Float, y: Float) = engine.start() } }
            ArcadeField(engine, Modifier.widthIn(max = 430.dp), fieldW = 360f, fieldH = 420f, fx = null, input = tapToStart,
                overlay = {
                    if (!engine.started) StartPrompt()
                    else if (engine.message.isNotEmpty()) Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(L10n.t(engine.message), color = pal.text, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                            modifier = Modifier.clip(RoundedCornerShape(16.dp)).background(pal.background.copy(alpha = 0.9f)).padding(20.dp))
                    }
                }) { drawBounce(engine) }
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                HoldButton("←") { engine.holdLeft(it) }
                HoldButton("→") { engine.holdRight(it) }
                Spacer(Modifier.weight(1f))
                HoldButton("↑") { engine.holdJump(it) }
            }
            Text(L10n.t(if (engine.gateOpen) "All rings collected! Reach the green exit." else "Hold arrows to roll. Tap Jump to leap. Collect every ring, stomp the critters and reach the exit."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp).fillMaxWidth())
        }
    }
}

@Composable
private fun HoldButton(glyph: String, set: (Boolean) -> Unit) {
    val pal = Pal.current
    var pressed by remember { mutableStateOf(false) }
    Box(Modifier.size(70.dp, 58.dp).clip(RoundedCornerShape(16.dp)).background(if (pressed) pal.accent else pal.surfaceHigh)
        .pointerInput(Unit) {
            awaitEachGesture {
                awaitFirstDown(); pressed = true; set(true)
                waitForUpOrCancellation(); pressed = false; set(false)
            }
        }, contentAlignment = Alignment.Center) {
        Text(glyph, color = if (pressed) pal.onAccent else pal.accent, fontSize = 26.sp, fontWeight = FontWeight.Bold)
    }
}

private fun Pen.drawBounce(e: BounceEngine) {
    val offset = e.cameraX
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF141233), Color(0xFF291A40)), 0f, 420f), Offset(-20f, -20f), Size(400f, 460f))
    circle(250 - offset * 0.05f + 28, 68f, 28f, Color(0xFFFFE6B3).copy(alpha = 0.85f))
    // Distant scenery scrolls more slowly than the foreground.
    for (i in 0 until 12) {
        val x = i * 130f - offset * 0.3f
        polygon(listOf(Offset(x - 80, 365f), Offset(x, 150f + (i % 3) * 30), Offset(x + 110, 365f)), Color(0xFF5856D6).copy(alpha = 0.13f))
    }
    xf(-offset, 0f) {
        for (p in e.level.platforms) {
            box(p.minX, p.minY, p.w, p.h, Color(0xFF212735), 3f)
            box(p.minX, p.minY, p.w, 4f, Color(0xFF32ADE6).copy(alpha = 0.85f), 0f)
            var x = p.minX + 8
            while (x < p.maxX) { box(x, p.minY + 9, 12f, 3f, Color.White.copy(alpha = 0.08f), 0f); x += 24f }
        }
        for (s in e.level.spikes) {
            val count = max(1, (s.w / 12).toInt()); val w = s.w / count
            for (i in 0 until count) { val x = s.minX + i * w; polygon(listOf(Offset(x, s.maxY), Offset(x + w / 2, s.minY), Offset(x + w, s.maxY)), Color(0xFFFF2D55)) }
        }
        for ((i, p) in e.level.rings.withIndex()) if (i !in e.collected) {
            // Rings slowly spin around their vertical axis.
            val w = 24 * max(0.25f, abs(cos(e.clock * 2.2f + i)))
            strokeOval(p.x - w / 2, p.y - 16, w, 32f, Color.Yellow.copy(alpha = 0.15f), 10f)
            strokeOval(p.x - w / 2, p.y - 16, w, 32f, Color.Yellow, 4f)
        }
        val gate = e.level.exit
        box(gate.minX, gate.minY, gate.w, gate.h, if (e.gateOpen) Color.Green.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.05f), 10f)
        strokeBox(gate.minX, gate.minY, gate.w, gate.h, if (e.gateOpen) Color(0xFFC6F31D) else Color(0xFF9E9E9E), 3f, 10f)
        label(if (e.gateOpen) "→" else "🔒", gate.midX, gate.midY, 18f, if (e.gateOpen) Color(0xFFC6F31D) else Color(0xFF9E9E9E))
        for (en in e.enemies) if (en.alive) {
            val r = BounceEnemy.RADIUS
            val cx = en.x; val cy = en.y + sin(e.clock * 10 + en.x * 0.05f) * 1.5f
            val pts = (0 until 12).map { k ->
                val a = k / 12f * (PI * 2).toFloat() + e.clock * 1.5f
                val len = if (k % 2 == 0) r + 5 else r - 1
                Offset(cx + cos(a) * len, cy + sin(a) * len)
            }
            polygon(pts, Color(0xFF8C40D9))
            shiny(cx, cy, r, Color(0xFFD999FF), Color(0xFF7326B3))
            val look = if (en.speed > 0) 2f else -2f
            for (s in listOf(-4f, 4f)) { oval(cx + s - 3, cy - 5, 6f, 7f, Color.White); oval(cx + s - 1.5f + look * 0.6f, cy - 3, 3f, 4f, Color.Black) }
        }
        val blink = e.invulnerable > 0 && ((e.invulnerable * 12).toInt() % 2 == 0)
        val a = if (blink) 0.55f else 1f
        xf(e.bx, e.by, e.rotation) {
            ds.drawCircle(Brush.radialGradient(listOf(Color(0xFFFF8073).copy(alpha = a), Color.Red.copy(alpha = a), Color(0xFF990D0D).copy(alpha = a)), Offset(-4f, -5f), 18f), 12f, Offset.Zero)
            oval(-7f, -8f, 8f, 6f, Color.White.copy(alpha = 0.8f * a))
            circle(0f, 0f, 11f, Color(0xFFFF2D55).copy(alpha = a), 1.5f)
        }
    }
    e.fx.draw(this)
}
