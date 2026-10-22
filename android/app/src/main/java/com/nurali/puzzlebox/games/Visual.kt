package com.nurali.puzzlebox.games

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
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
import com.nurali.puzzlebox.games.kit.FieldInput
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.Pen
import com.nurali.puzzlebox.games.kit.PuzzleRandom
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

enum class VisualMode(val id: GameId, val hint: String) {
    RotatePuzzle(GameId.RotatePuzzle, "Tap each tile to rotate it and restore the picture."),
    Matchstick(GameId.Matchstick, "Move exactly one match: tap a lit segment, then an empty segment. Fix the equation."),
}

class VisualEngine(val mode: VisualMode) : FrameGame {
    val levelCount = 20
    var levelIndex by mutableIntStateOf(0)
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var version by mutableIntStateOf(0)
    var moves by mutableIntStateOf(0)
    var feedback by mutableStateOf("")

    /** Rotate: quarter turns still needed per tile. Matchstick: lit segments. */
    var cells = IntArray(0)
    /** Rotate: total quarter turns applied per tile, and the angle currently shown. */
    var turns = IntArray(0)
    var shown = FloatArray(0)
    var selectedMatch: Int? = null
    var size = 3
    var par = 0
    var matchesToMove = 1
    var matchesMoved by mutableIntStateOf(0)
    private var startCells = IntArray(0)
    private var random = PuzzleRandom(1)

    val hasNextLevel get() = levelIndex + 1 < levelCount
    val stars get() = if (par == 0) 3 else if (moves <= par) 3 else if (moves <= par * 1.5) 2 else 1

    companion object { val digitMasks = intArrayOf(63, 6, 91, 79, 102, 109, 125, 7, 127, 111) }

    init { restart() }

    fun loadLevel(index: Int) { if (index in 0 until levelCount) { levelIndex = index; restart() } }
    fun nextLevel() = loadLevel(levelIndex + 1)

    override fun restart() {
        random = PuzzleRandom(((if (mode == VisualMode.RotatePuzzle) 4 else 10) * 1000 + levelIndex + 1).toLong())
        state = GameState.Playing; score = 0; moves = 0; cells = IntArray(0); turns = IntArray(0); feedback = ""; selectedMatch = null; matchesMoved = 0
        when (mode) {
            VisualMode.RotatePuzzle -> {
                size = if (levelIndex < 4) 3 else if (levelIndex < 11) 4 else 5
                cells = IntArray(size * size) { random.nextInt(0, 4) }
                if (cells.all { it == 0 }) cells[0] = 1
                turns = cells.copyOf()
                shown = FloatArray(cells.size) { turns[it] * 90f }
                par = cells.sumOf { (4 - it) % 4 }
            }
            VisualMode.Matchstick -> {
                matchesToMove = if (levelIndex < 8) 1 else 2
                makeMatches()
                startCells = cells.copyOf()
                par = matchesToMove
            }
        }
        version++
    }

    override fun advance(dt: Double) {
        if (mode != VisualMode.RotatePuzzle) return
        for (i in shown.indices) {
            val target = turns[i] * 90f
            if (shown[i] < target) shown[i] = min(target, shown[i] + 900f * dt.toFloat())
        }
    }

    private fun win() {
        score = 100 + levelIndex * 50 + stars * 100
        state = GameState.GameOver(won = true); Haptics.success()
    }

    fun tap(i: Int) {
        if (state != GameState.Playing) return
        feedback = ""
        when (mode) {
            VisualMode.RotatePuzzle -> {
                if (i !in cells.indices) return
                moves++; cells[i] = (cells[i] + 1) % 4; turns[i]++
                if (cells[i] == 0) { Sfx.point(); Haptics.move() } else Sfx.tap()
                if (cells.all { it == 0 }) win()
            }
            VisualMode.Matchstick -> match(i)
        }
        version++
    }

    fun isCorrect(i: Int) = i in cells.indices && cells[i] == 0

    private class Eq(val a: Int, val b: Int, val c: Int, val plus: Boolean)

    private fun equation(bits: IntArray): Eq? {
        fun digit(offset: Int): Int? {
            val mask = (0 until 7).fold(0) { acc, k -> acc or (bits[offset + k] shl k) }
            return digitMasks.indexOf(mask).takeIf { it >= 0 }
        }
        if (bits.size != 23 || bits[7] != 1) return null
        val a = digit(0) ?: return null; val b = digit(9) ?: return null; val c = digit(16) ?: return null
        return Eq(a, b, c, bits[8] == 1)
    }

    private fun correct(bits: IntArray): Boolean { val e = equation(bits) ?: return false; return (if (e.plus) e.a + e.b else e.a - e.b) == e.c }

    private fun encoded(a: Int, b: Int, c: Int, plus: Boolean): IntArray {
        fun bits(n: Int) = IntArray(7) { (digitMasks[n] shr it) and 1 }
        return bits(a) + intArrayOf(1, if (plus) 1 else 0) + bits(b) + bits(c)
    }

    /** Starts from a true equation and moves [matchesToMove] matches away from it, so it is solvable in that many moves. */
    private fun makeMatches() {
        repeat(400) {
            val a = random.nextInt(0, 10); val b = random.nextInt(0, 10); val plus = random.nextInt(0, 2) == 1
            val c = if (plus) a + b else a - b
            if (c !in 0..9) return@repeat
            val candidate = encoded(a, b, c, plus)
            repeat(matchesToMove) {
                val lit = candidate.indices.filter { candidate[it] == 1 && it != 7 }.shuffled(random)
                val empty = candidate.indices.filter { candidate[it] == 0 }.shuffled(random)
                val from = lit.firstOrNull(); val to = empty.firstOrNull()
                if (from != null && to != null) { candidate[from] = 0; candidate[to] = 1 }
            }
            if (equation(candidate) != null && !correct(candidate) && !candidate.contentEquals(encoded(a, b, c, plus))) { cells = candidate; return }
        }
        cells = encoded(6, 4, 4, true) // Move the vertical match of '+' to make 8 − 4 = 4.
    }

    fun resetMatches() {
        if (mode != VisualMode.Matchstick || state != GameState.Playing) return
        cells = startCells.copyOf(); matchesMoved = 0; selectedMatch = null; feedback = ""
        Sfx.tap(); version++
    }

    private fun match(i: Int) {
        if (i !in cells.indices || i == 7) return // the equals sign's anchor stays put
        if (cells[i] == 1) { selectedMatch = if (selectedMatch == i) null else i; Sfx.tap(); return }
        val from = selectedMatch ?: return
        moves++; matchesMoved++
        cells[from] = 0; cells[i] = 1; selectedMatch = null
        Sfx.point()
        if (correct(cells)) { win(); return }
        if (matchesMoved >= matchesToMove) {
            // Out of moves: put the matches back for another try.
            feedback = "Try again"; Haptics.error(); Sfx.wrong()
            cells = startCells.copyOf(); matchesMoved = 0
        }
    }
}

@Composable
fun VisualScreen(mode: VisualMode, onExit: () -> Unit) {
    val engine = remember { VisualEngine(mode) }
    val pal = Pal.current
    var menu by remember { mutableStateOf(false) }
    GameContainer(mode.id, engine, onExit, nextLevel = if (engine.hasNextLevel) ({ engine.nextLevel() }) else null,
        summary = { L10n.f("Level %d", engine.levelIndex + 1) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                androidx.compose.foundation.layout.Box {
                    Text("▦ " + L10n.f("Level %d", engine.levelIndex + 1), color = pal.accent, fontWeight = FontWeight.Bold, modifier = Modifier.clickable { menu = true })
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.heightIn(max = 360.dp)) {
                        for (lv in 0 until engine.levelCount) DropdownMenuItem(text = { Text(L10n.f("Level %d", lv + 1)) }, onClick = { menu = false; engine.loadLevel(lv) })
                    }
                }
                Text(L10n.f("%d moves", engine.moves), color = pal.accent)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Text((0 until 3).joinToString("") { if (it < engine.stars) "★" else "☆" }, color = Color(0xFFFFCC00), fontSize = 14.sp)
                if (mode == VisualMode.Matchstick) Text("↺", color = pal.accent, fontSize = 22.sp, modifier = Modifier.clickable { engine.resetMatches() })
            }
            if (mode == VisualMode.Matchstick) {
                Text(L10n.f(if (engine.matchesToMove == 1) "Move %d match" else "Move %d matches", engine.matchesToMove - engine.matchesMoved),
                    color = Color(0xFFFF9500), fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.padding(bottom = 8.dp))
                val input = remember(engine) {
                    object : FieldInput() {
                        override fun onDown(x: Float, y: Float) {
                            val segs = matchSegments()
                            val candidates = segs.indices.filter { engine.selectedMatch != null || engine.cells[it] == 1 }
                            val best = candidates.minByOrNull { segDistance(x, y, segs[it]) } ?: return
                            if (segDistance(x, y, segs[best]) < 13f) engine.tap(best)
                        }
                    }
                }
                ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 320f, fieldH = 460f, animated = false, input = input) {
                    @Suppress("UNUSED_EXPRESSION") engine.version
                    drawMatches(engine)
                }
            } else {
                val input = remember(engine) {
                    object : FieldInput() {
                        override fun onDown(x: Float, y: Float) {
                            val n = engine.size; val tile = 360f / n
                            if (x < 0 || y < 0 || x >= 360f || y >= 360f) return
                            engine.tap((y / tile).toInt() * n + (x / tile).toInt())
                        }
                    }
                }
                ArcadeField(engine, Modifier.widthIn(max = 380.dp), fieldW = 360f, fieldH = 360f, input = input) {
                    @Suppress("UNUSED_EXPRESSION") engine.version
                    drawRotate(engine)
                }
            }
            if (engine.feedback.isNotEmpty()) Text(L10n.t(engine.feedback), color = Color(0xFFFF9500), fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
            Text(L10n.t(mode.hint), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp).fillMaxWidth())
        }
    }
}

private fun segDistance(px: Float, py: Float, s: Pair<Offset, Offset>): Float {
    val (a, b) = s
    val dx = b.x - a.x; val dy = b.y - a.y
    val t = min(1f, max(0f, ((px - a.x) * dx + (py - a.y) * dy) / max(1f, dx * dx + dy * dy)))
    return hypot(px - a.x - t * dx, py - a.y - t * dy)
}

private fun matchSegments(): List<Pair<Offset, Offset>> {
    fun digit(x: Float): List<Pair<Offset, Offset>> {
        val y = 175f; val w = 38f; val h = 76f
        return listOf(
            Offset(x + 3, y) to Offset(x + w - 3, y),
            Offset(x + w, y + 3) to Offset(x + w, y + h / 2 - 3),
            Offset(x + w, y + h / 2 + 3) to Offset(x + w, y + h - 3),
            Offset(x + 3, y + h) to Offset(x + w - 3, y + h),
            Offset(x, y + h / 2 + 3) to Offset(x, y + h - 3),
            Offset(x, y + 3) to Offset(x, y + h / 2 - 3),
            Offset(x + 3, y + h / 2) to Offset(x + w - 3, y + h / 2),
        )
    }
    return digit(16f) + listOf(Offset(78f, 213f) to Offset(108f, 213f), Offset(93f, 198f) to Offset(93f, 228f)) + digit(130f) + digit(262f)
}

private fun Pen.drawMatches(e: VisualEngine) {
    val accent = Color(0xFFC6F31D)
    for ((i, seg) in matchSegments().withIndex()) {
        val (a, b) = seg
        if (e.cells[i] == 1) {
            val sel = e.selectedMatch == i
            line(a.x, a.y, b.x, b.y, if (sel) accent.copy(alpha = 0.4f) else Color.Black.copy(alpha = 0.4f), 11f)
            line(a.x, a.y, b.x, b.y, if (sel) accent else Color(0xFFF2BF73), 6f)
            circle(a.x, a.y, 3f, Color.Red)
        } else line(a.x, a.y, b.x, b.y, Color.White.copy(alpha = if (e.selectedMatch == null) 0.1f else 0.3f), 5f)
    }
    line(197f, 204f, 229f, 204f, Color.White, 4f)
    line(197f, 223f, 229f, 223f, Color.White, 4f)
}

private fun Pen.drawRotate(e: VisualEngine) {
    val n = e.size; val side = 360f; val tile = side / n
    for (i in e.cells.indices) {
        val r = i / n; val c = i % n
        val cx = c * tile + tile / 2; val cy = r * tile + tile / 2
        ds.clipRect(c * tile, r * tile, c * tile + tile, r * tile + tile) {
            xf(cx, cy, Math.toRadians(e.shown.getOrElse(i) { 0f }.toDouble()).toFloat()) {
                xf(-tile / 2 - c * tile, -tile / 2 - r * tile, 0f, side / 300f) { picture(e) }
            }
        }
        // Tiles already in place lose their seam, a gentle hint of progress.
        if (!e.isCorrect(i)) strokeBox(c * tile, r * tile, tile, tile, Color.Black.copy(alpha = 0.35f), 1f, 0f)
    }
}

private fun Pen.curve(p0: Offset, c1: Offset, c2: Offset, p1: Offset, color: Color, width: Float) {
    val path = Path().apply { moveTo(p0.x, p0.y); cubicTo(c1.x, c1.y, c2.x, c2.y, p1.x, p1.y) }
    ds.drawPath(path, color, style = Stroke(width, cap = StrokeCap.Round))
}

private fun Pen.vgrad(x: Float, y: Float, w: Float, h: Float, top: Color, bottom: Color) {
    ds.drawRect(Brush.verticalGradient(listOf(top, bottom), y, y + h), Offset(x, y), Size(w, h))
}

/** Five painted scenes cycle through the levels; corner ticks keep each tile's orientation readable. */
private fun Pen.picture(e: VisualEngine) {
    when (e.levelIndex % 5) {
        0 -> {
            vgrad(0f, 0f, 300f, 300f, Color(0xFF73CCFF), Color(0xFFBFEBFF))
            circle(238f, 55f, 32f, Color(0xFFFFCC00))
            polygon(listOf(Offset(0f, 240f), Offset(90f, 65f), Offset(190f, 240f), Offset(235f, 145f), Offset(300f, 220f), Offset(300f, 300f), Offset(0f, 300f)), Color(0xFF5856D6))
            polygon(listOf(Offset(72f, 100f), Offset(90f, 65f), Offset(108f, 100f)), Color.White)
            curve(Offset(160f, 170f), Offset(250f, 230f), Offset(55f, 240f), Offset(90f, 300f), Color(0xFF00C7BE), 23f)
            box(28f, 213f, 43f, 42f, Color(0xFFFF9500), 0f)
            polygon(listOf(Offset(20f, 214f), Offset(50f, 189f), Offset(80f, 214f)), Color(0xFFFF2D55))
            for ((x, y) in listOf(30 to 35, 100 to 15, 5 to 125, 255 to 265)) oval(x.toFloat(), y.toFloat(), 28f, 12f, Color.White.copy(alpha = 0.8f))
        }
        1 -> {
            vgrad(0f, 0f, 300f, 300f, Color(0xFF0D0D33), Color(0xFF4D2673))
            circle(70f, 60f, 26f, Color(0xFFFFF2BF)); circle(82f, 52f, 24f, Color(0xFF141240))
            for (k in 0 until 25) circle(((k * 67) % 300).toFloat(), ((k * 41) % 150).toFloat(), 1.6f, Color.White.copy(alpha = 0.8f))
            val heights = listOf(120f, 180f, 95f, 210f, 140f, 165f, 105f)
            for ((k, h) in heights.withIndex()) {
                val x = k * 43f
                box(x, 300 - h, 40f, h, Color(0xFF1F1F40), 0f)
                var wy = 300 - h + 12
                while (wy < 290) {
                    for (wx in listOf(x + 8, x + 24)) if ((wy.toInt() + wx.toInt() + k) % 3 == 0) box(wx, wy, 8f, 10f, Color(0xFFFFCC00).copy(alpha = 0.85f), 0f)
                    wy += 20
                }
            }
        }
        2 -> {
            vgrad(0f, 0f, 300f, 170f, Color(0xFFFA7359), Color(0xFFFFCC73))
            circle(150f, 165f, 48f, Color(0xFFFFE666))
            vgrad(0f, 165f, 300f, 135f, Color(0xFF265AA6), Color(0xFF0D2659))
            for (k in 0 until 6) box((60 + k * 12).toFloat(), (185 + k * 16).toFloat(), (180 - k * 24).toFloat(), 4f, Color(0xFFFFCC00).copy(alpha = 0.5f), 2f)
            polygon(listOf(Offset(40f, 230f), Offset(100f, 230f), Offset(90f, 245f), Offset(50f, 245f)), Color(0xFF4D261A))
            polygon(listOf(Offset(70f, 228f), Offset(70f, 180f), Offset(98f, 228f)), Color.White)
            for ((x, y) in listOf(210 to 60, 240 to 75, 225 to 95)) {
                line(x - 8f, y.toFloat(), x - 4f, y - 4f, Color.Black.copy(alpha = 0.6f), 2f); line(x - 4f, y - 4f, x.toFloat(), y.toFloat(), Color.Black.copy(alpha = 0.6f), 2f)
                line(x.toFloat(), y.toFloat(), x + 4f, y - 4f, Color.Black.copy(alpha = 0.6f), 2f); line(x + 4f, y - 4f, x + 8f, y.toFloat(), Color.Black.copy(alpha = 0.6f), 2f)
            }
        }
        3 -> {
            vgrad(0f, 0f, 300f, 300f, Color(0xFF99E0FF), Color(0xFFD9F2FF))
            oval(-60f, 150f, 260f, 200f, Color(0xFF59B34D)); oval(120f, 170f, 260f, 200f, Color(0xFF4D9E40))
            val petals = listOf(Color(0xFFFF2D55), Color(0xFFFFCC00), Color(0xFFAF52DE), Color(0xFFFF9500), Color(0xFFFF3B30), Color.White)
            for (k in 0 until 14) {
                val x = (20 + (k * 53) % 270).toFloat(); val y = (200 + (k * 29) % 90).toFloat()
                line(x, y, x, y + 22f, Color(0xFF34C759), 2f)
                for (a in 0 until 5) { val t = a / 5f * (PI * 2).toFloat(); circle(x + cos(t) * 6, y + sin(t) * 6, 4.5f, petals[k % petals.size]) }
                circle(x, y, 3.5f, Color(0xFFFFCC00))
            }
            circle(60f, 60f, 30f, Color(0xFFFFCC00))
            oval(170f, 40f, 70f, 24f, Color.White); oval(190f, 28f, 40f, 30f, Color.White)
        }
        else -> {
            vgrad(0f, 0f, 300f, 300f, Color(0xFF08051F), Color(0xFF1F0D40))
            for (k in 0 until 40) circle(((k * 73) % 300).toFloat(), ((k * 131) % 300).toFloat(), if (k % 5 == 0) 2f else 1f, Color.White.copy(alpha = 0.85f))
            circle(110f, 170f, 70f, Color(0xFFF28C4D))
            strokeOval(20f, 150f, 180f, 40f, Color(0xFFFFD999), 6f)
            circle(85f, 150f, 12f, Color(0xFFCC6633)); circle(130f, 195f, 8f, Color(0xFFCC6633))
            circle(240f, 70f, 22f, Color(0xFF99CCFF)); circle(234f, 64f, 6f, Color.White.copy(alpha = 0.6f))
            polygon(listOf(Offset(240f, 220f), Offset(255f, 250f), Offset(225f, 250f)), Color.White)
            oval(233f, 250f, 14f, 20f, Color(0xFFFF9500))
        }
    }
    // Corner ticks: one per tile region, always at the region's top-left.
    val n = e.size; val step = 300f / n
    for (r in 0 until n) for (col in 0 until n) {
        val x = col * step + step * 0.1f; val y = r * step + step * 0.1f; val len = step * 0.18f
        val w = max(2f, step * 0.035f)
        line(x, y + len, x, y, Color.White.copy(alpha = 0.75f), w); line(x, y, x + len, y, Color.White.copy(alpha = 0.75f), w)
    }
}
