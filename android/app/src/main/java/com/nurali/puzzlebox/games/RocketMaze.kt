package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.StartPrompt
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sin

data class MazeCell(val column: Int, val row: Int)

enum class MazeHeading(val dx: Int, val dy: Int) {
    East(1, 0), North(0, 1), West(-1, 0), South(0, -1);
    val angle get() = ordinal * (PI / 2).toFloat()
    fun turned(left: Boolean) = entries[(ordinal + if (left) 1 else 3) % 4]
}

/** Coordinates: origin bottom-left, positive y up (flipped when drawn). */
class MazeLevel private constructor(val columns: Int, val rows: Int, val speed: Float, waypoints: List<Pair<Int, Int>>, branches: List<List<Pair<Int, Int>>>) {
    companion object {
        const val TILE = 72f

        private fun expand(points: List<Pair<Int, Int>>): List<MazeCell> {
            val cells = arrayListOf(MazeCell(points[0].first, points[0].second))
            for ((a, b) in points.zipWithNext()) {
                val dx = (b.first - a.first).sign; val dy = (b.second - a.second).sign
                for (step in 1..max(abs(b.first - a.first), abs(b.second - a.second))) cells.add(MazeCell(a.first + dx * step, a.second + dy * step))
            }
            return cells
        }

        private fun lv(c: Int, r: Int, speed: Int, wp: List<Pair<Int, Int>>, br: List<List<Pair<Int, Int>>> = emptyList()) = MazeLevel(c, r, speed.toFloat(), wp, br)
        private fun w(vararg p: Int): List<Pair<Int, Int>> = p.toList().chunked(2).map { it[0] to it[1] }

        val all: List<MazeLevel> = listOf(
            lv(9, 11, 100, w(1,1, 7,1, 7,5, 3,5, 3,9, 7,9), listOf(w(4,1, 4,3), w(3,7, 1,7))),
            lv(11, 13, 105, w(1,1, 1,5, 5,5, 5,1, 9,1, 9,9, 3,9, 3,11, 9,11), listOf(w(1,3, 3,3), w(9,7, 7,7))),
            lv(11, 15, 110, w(1,1, 9,1, 9,5, 3,5, 3,9, 7,9, 7,13, 1,13), listOf(w(5,1, 5,3), w(3,7, 1,7), w(7,11, 9,11))),
            lv(13, 15, 115, w(1,1, 1,11, 5,11, 5,3, 9,3, 9,7, 11,7, 11,13, 3,13), listOf(w(1,5, 3,5), w(5,7, 7,7), w(9,5, 11,5))),
            lv(13, 17, 120, w(1,1, 11,1, 11,5, 5,5, 5,9, 9,9, 9,13, 3,13, 3,15, 11,15), listOf(w(3,1, 3,3), w(7,5, 7,7), w(5,9, 1,9), w(9,11, 11,11))),
            lv(15, 17, 125, w(1,1, 1,7, 5,7, 5,3, 9,3, 9,9, 3,9, 3,13, 7,13, 7,15, 13,15, 13,5), listOf(w(1,3, 3,3), w(9,5, 11,5), w(3,11, 5,11), w(13,11, 11,11))),
            lv(15, 19, 130, w(1,1, 13,1, 13,5, 9,5, 9,3, 5,3, 5,7, 1,7, 1,11, 7,11, 7,9, 13,9, 13,17, 9,17, 9,13, 3,13, 3,17), listOf(w(13,3, 11,3), w(1,9, 3,9), w(13,13, 11,13))),
            lv(17, 21, 135, w(1,1, 15,1, 15,5, 1,5, 1,9, 15,9, 15,13, 1,13, 1,17, 15,17, 15,19), listOf(w(7,1, 7,3), w(9,5, 9,7), w(5,9, 5,11), w(11,13, 11,15), w(3,17, 3,19))),
            lv(17, 19, 140, w(1,1, 15,1, 15,17, 1,17, 1,3, 13,3, 13,15, 3,15, 3,5, 11,5, 11,13, 5,13, 5,7, 9,7, 9,11, 7,11)),
            lv(19, 21, 145, w(9,1, 17,1, 17,7, 11,7, 11,3, 1,3, 1,11, 7,11, 7,15, 1,15, 1,19, 11,19, 11,11, 17,11, 17,19), listOf(w(13,1, 13,5), w(1,7, 5,7), w(7,13, 9,13), w(17,15, 13,15))),
        )
    }

    val route: List<MazeCell>
    val floors: Set<MazeCell>
    val initialHeading: MazeHeading
    val gemCells: List<MazeCell>

    init {
        val path = expand(waypoints)
        val walkable = HashSet(path)
        for (b in branches) walkable.addAll(expand(b))
        route = path; floors = walkable
        val first = path[0]; val second = path[1]
        initialHeading = if (second.column > first.column) MazeHeading.East else if (second.column < first.column) MazeHeading.West else if (second.row > first.row) MazeHeading.North else MazeHeading.South
        // Keep gems away from corners: every collectible is on the guaranteed route.
        gemCells = path.indices.filter { i ->
            i >= 2 && i < path.size - 2 && i % 5 == 2 && (path[i - 1].column == path[i + 1].column || path[i - 1].row == path[i + 1].row)
        }.map { path[it] }
    }

    val width get() = columns * TILE
    val height get() = rows * TILE
    fun center(c: MazeCell) = Offset((c.column + 0.5f) * TILE, (c.row + 0.5f) * TILE)
    fun cellAt(p: Offset) = MazeCell(floor(p.x / TILE).toInt(), floor(p.y / TILE).toInt())
    val spawn get() = center(route[0])
    val exit get() = center(route.last())
}

enum class MazeOutcome { Moving, Crashed, Escaped }

/** Deterministic rules with no rendering, timers or side effects. */
class MazeSimulation(val level: MazeLevel) {
    companion object {
        const val TIP_OFFSET = 18f; const val TIP_RADIUS = 4f; const val BODY_RADIUS = 10f
        const val GEM_RADIUS = 10f; const val EXIT_RADIUS = 22f; const val TURN_ASSIST = 18f
        /** Speed added once every gem is collected; it ramps up gem by gem. */
        const val MAX_BOOST = 0.75f
        const val TURN_COOLDOWN = 0.12
    }

    var position = level.spawn
    var heading = level.initialHeading
    val collected = HashSet<Int>()
    var elapsed = 0.0
    var turns = 0
    var outcome = MazeOutcome.Moving
    private var lastTurnTime = -1e9

    val tip get() = tipAt(position, heading.angle)
    val exitUnlocked get() = collected.size == level.gemCells.size
    val speedMultiplier get() = if (level.gemCells.isEmpty()) 1f else 1f + MAX_BOOST * collected.size / level.gemCells.size
    val speed get() = level.speed * speedMultiplier
    val score get() = collected.size * 100 + if (outcome == MazeOutcome.Escaped) 500 + max(0, 300 - elapsed.toInt() * 5) else 0

    private fun tipAt(p: Offset, angle: Float) = Offset(p.x + cos(angle) * TIP_OFFSET, p.y + sin(angle) * TIP_OFFSET)

    fun step(deltaTime: Double) {
        if (outcome != MazeOutcome.Moving || deltaTime <= 0) return
        val dt = min(deltaTime, 1.0 / 30)
        elapsed += dt
        val oldPos = position; val oldTip = tip
        val next = Offset(oldPos.x + cos(heading.angle) * speed * dt.toFloat(), oldPos.y + sin(heading.angle) * speed * dt.toFloat())
        val nextTip = tipAt(next, heading.angle)
        if (hitsWall(oldPos, next, BODY_RADIUS) || hitsWall(oldTip, nextTip, TIP_RADIUS)) { outcome = MazeOutcome.Crashed; return }
        position = next
        collectAlong(oldTip, nextTip)
        checkExit(oldTip, nextTip)
    }

    fun turn(left: Boolean): Boolean {
        if (outcome != MazeOutcome.Moving || elapsed - lastTurnTime < TURN_COOLDOWN) return false
        val center = level.center(level.cellAt(position))
        // Faster flight gets a proportionally wider assist window.
        val assist = max(TURN_ASSIST, speed * 0.1f)
        val aligned = if (hypot(center.x - position.x, center.y - position.y) <= assist) center else position
        val oldTip = tip
        val alignedTip = tipAt(aligned, heading.angle)
        if (hitsWall(position, aligned, BODY_RADIUS) || hitsWall(oldTip, alignedTip, TIP_RADIUS)) { outcome = MazeOutcome.Crashed; return false }
        val rotation = if (left) (PI / 2).toFloat() else (-PI / 2).toFloat()
        var previous = alignedTip
        // Check the swept tip during a turn as well as during forward motion.
        for (sample in 1..8) {
            val n = tipAt(aligned, heading.angle + rotation * sample / 8)
            if (hitsWall(previous, n, TIP_RADIUS)) { outcome = MazeOutcome.Crashed; return false }
            previous = n
        }
        position = aligned
        heading = heading.turned(left)
        turns++
        lastTurnTime = elapsed
        collectAlong(tip, tip); checkExit(tip, tip)
        return true
    }

    private fun collectAlong(a: Offset, b: Offset) {
        for (i in level.gemCells.indices) if (i !in collected) {
            val gem = level.center(level.gemCells[i])
            if (distToSeg(gem, a, b) <= TIP_RADIUS + GEM_RADIUS) collected.add(i)
        }
    }

    private fun checkExit(a: Offset, b: Offset) {
        if (exitUnlocked && distToSeg(level.exit, a, b) <= EXIT_RADIUS + TIP_RADIUS) outcome = MazeOutcome.Escaped
    }

    private fun hitsWall(a: Offset, b: Offset, radius: Float): Boolean {
        val tile = MazeLevel.TILE
        val left = floor((min(a.x, b.x) - radius) / tile).toInt(); val right = floor((max(a.x, b.x) + radius) / tile).toInt()
        val bottom = floor((min(a.y, b.y) - radius) / tile).toInt(); val top = floor((max(a.y, b.y) + radius) / tile).toInt()
        for (row in bottom..top) for (col in left..right) {
            val cell = MazeCell(col, row)
            if (cell !in level.floors && intersects(a, b, col * tile - radius, row * tile - radius, (col + 1) * tile + radius, (row + 1) * tile + radius)) return true
        }
        return false
    }

    /** Slab intersection against an expanded AABB. */
    private fun intersects(a: Offset, b: Offset, minX: Float, minY: Float, maxX: Float, maxY: Float): Boolean {
        var enter = 0f; var exit = 1f
        for ((origin, delta, low, high) in listOf(listOf(a.x, b.x - a.x, minX, maxX), listOf(a.y, b.y - a.y, minY, maxY))) {
            if (abs(delta) < 0.000001f) { if (origin < low || origin > high) return false }
            else {
                val first = (low - origin) / delta; val last = (high - origin) / delta
                enter = max(enter, min(first, last)); exit = min(exit, max(first, last))
                if (enter > exit) return false
            }
        }
        return true
    }

    private fun distToSeg(p: Offset, a: Offset, b: Offset): Float {
        val dx = b.x - a.x; val dy = b.y - a.y
        val f = min(1f, max(0f, ((p.x - a.x) * dx + (p.y - a.y) * dy) / max(0.000001f, dx * dx + dy * dy)))
        return hypot(p.x - a.x - f * dx, p.y - a.y - f * dy)
    }
}

class RocketMazeEngine : FrameGame {
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var levelIndex by mutableIntStateOf(0)
    var collectedCount by mutableIntStateOf(0)
    var speedMultiplier by mutableDoubleStateOf(1.0)
    var simulation = MazeSimulation(MazeLevel.all[0])
    val fx = ArcadeFX()
    val trail = ArrayList<Offset>()
    private var crashed = false

    val level get() = MazeLevel.all[levelIndex]
    val hasNextLevel get() = levelIndex + 1 < MazeLevel.all.size
    val canAdvance get() = started && state == GameState.Playing

    init { restart() }

    override fun restart() {
        simulation = MazeSimulation(level)
        score = 0; collectedCount = 0; speedMultiplier = 1.0; started = false; state = GameState.Playing
        trail.clear(); fx.reset(); crashed = false
    }

    fun selectLevel(i: Int) { if (i !in MazeLevel.all.indices || i == levelIndex) return; levelIndex = i; restart() }
    fun nextLevel() = selectLevel(levelIndex + 1)
    fun start() { if (state == GameState.Playing) started = true }

    fun turn(left: Boolean) {
        if (!canAdvance) return
        if (simulation.turn(left)) { Haptics.tap(); Sfx.tap() }
        publish()
    }

    override fun advance(dt: Double) {
        fx.update(min(0.05, dt).toFloat())
        if (!canAdvance) return
        var rest = min(dt, 0.05)
        while (rest > 0 && simulation.outcome == MazeOutcome.Moving) { val s = min(rest, 1.0 / 120); simulation.step(s); rest -= s }
        trail.add(simulation.position); if (trail.size > 18) trail.removeAt(0)
        publish()
    }

    private fun publish() {
        if (collectedCount != simulation.collected.size) {
            collectedCount = simulation.collected.size
            speedMultiplier = simulation.speedMultiplier.toDouble()
            Haptics.move(); Sfx.point()
        }
        if (score != simulation.score) score = simulation.score
        if (state != GameState.Playing) return
        when (simulation.outcome) {
            MazeOutcome.Moving -> {}
            MazeOutcome.Crashed -> {
                if (!crashed) { crashed = true; val t = simulation.tip; fx.burst(t.x, t.y, Color(0xFFFF9500), 30, 220f, 0f, 3.5f, 0.8f); fx.kick(8f) }
                state = GameState.GameOver(won = false)
            }
            MazeOutcome.Escaped -> state = GameState.GameOver(won = true)
        }
    }
}

@Composable
fun RocketMazeScreen(onExit: () -> Unit) {
    val engine = remember { RocketMazeEngine() }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(GameId.ArrowMaze, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.levelIndex + 1) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box {
                    Text("▦ " + L10n.f("Level %d of %d", engine.levelIndex + 1, MazeLevel.all.size), color = pal.accent, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        for (i in MazeLevel.all.indices) DropdownMenuItem(text = { Text(L10n.f("Level %d", i + 1)) }, onClick = { menu = false; engine.selectLevel(i) })
                    }
                }
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text("⏩ ×%.1f".format(engine.speedMultiplier), color = if (engine.speedMultiplier > 1.01) Color(0xFFFF9500) else pal.textSecondary, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                Text("★ ${engine.collectedCount}/${engine.level.gemCells.size}", color = Color(0xFFFFCC00), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
            }
            ArcadeField(engine, Modifier.widthIn(max = 440.dp), fieldW = 360f, fieldH = 460f, fx = null,
                overlay = { if (!engine.started) StartPrompt() }) { drawMaze(engine) }
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for ((left, label, glyph) in listOf(Triple(true, "Turn left", "↰"), Triple(false, "Turn right", "↱"))) {
                    Box(Modifier.weight(1f).heightIn(min = 48.dp).clip(RoundedCornerShape(50)).background(pal.surfaceHigh).clickable(enabled = engine.canAdvance) { engine.turn(left) }.padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                        Text("$glyph  " + L10n.t(label), color = if (engine.canAdvance) pal.text else pal.textSecondary, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Text(L10n.t(if (engine.collectedCount == engine.level.gemCells.size) "Portal open! Fly into it." else "Collect every star. Each one speeds up the rocket."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp).fillMaxWidth())
        }
    }
}

private fun Pen.drawMaze(e: RocketMazeEngine) {
    val level = e.level; val sim = e.simulation
    val tile = MazeLevel.TILE
    val vw = 360f; val vh = 460f
    // Camera follows the rocket; y is flipped so north is up.
    val px = sim.position.x; val py = level.height - sim.position.y
    val camX = (px - vw / 2).coerceIn(0f, max(0f, level.width - vw))
    val camY = (py - vh / 2).coerceIn(0f, max(0f, level.height - vh))
    ds.drawRect(Brush.verticalGradient(listOf(Color(0xFF0A0A24), Color(0xFF16091F)), 0f, vh), size = androidx.compose.ui.geometry.Size(vw, vh))
    xf(-camX, -camY) {
        for (row in 0 until level.rows) for (col in 0 until level.columns) {
            val x = col * tile; val y = (level.rows - 1 - row) * tile
            if (MazeCell(col, row) in level.floors) {
                box(x + 1, y + 1, tile - 2, tile - 2, Color(0xFF1B2540), 6f)
                box(x + 1, y + 1, tile - 2, 3f, Color(0xFF32ADE6).copy(alpha = 0.12f), 0f)
            } else box(x, y, tile, tile, Color(0xFF0E0E1C), 0f)
        }
        // Stars.
        for (i in level.gemCells.indices) if (i !in sim.collected) {
            val c = level.center(level.gemCells[i]); val gx = c.x; val gy = level.height - c.y
            circle(gx, gy, 17f, Color(0xFFFFCC00).copy(alpha = 0.2f))
            val pts = (0 until 10).map { k -> val a = k * (PI / 5).toFloat() - (PI / 2).toFloat(); val len = if (k % 2 == 0) 11f else 5f; Offset(gx + cos(a) * len, gy + sin(a) * len) }
            polygon(pts, Color(0xFFFFCC00))
        }
        // Portal.
        val ex = level.exit.x; val ey = level.height - level.exit.y
        val open = sim.exitUnlocked
        circle(ex, ey, 26f, (if (open) Color(0xFF34C759) else Color(0xFF666666)).copy(alpha = 0.25f))
        circle(ex, ey, 20f, if (open) Color(0xFF34C759) else Color(0xFF666666), 3f)
        circle(ex, ey, 10f, (if (open) Color(0xFF34C759) else Color(0xFF666666)).copy(alpha = 0.5f))
        // Trail and rocket.
        e.trail.forEachIndexed { i, p -> circle(p.x, level.height - p.y, 6f * i / max(1, e.trail.size), Color(0xFFFF9500).copy(alpha = i.toFloat() / max(1, e.trail.size) * 0.5f)) }
        if (sim.outcome != MazeOutcome.Crashed) {
            xf(px, py, -sim.heading.angle) {
                polygon(listOf(Offset(18f, 0f), Offset(-12f, 10f), Offset(-6f, 0f), Offset(-12f, -10f)), Color(0xFFE6F2FF))
                circle(2f, 0f, 3f, Color(0xFF32ADE6))
                polygon(listOf(Offset(-8f, 3f), Offset(-8f - 6f - 4f * abs(sin(sim.elapsed.toFloat() * 30)), 0f), Offset(-8f, -3f)), Color(0xFFFF9500))
            }
        }
        e.fx.draw(this)
    }
}
