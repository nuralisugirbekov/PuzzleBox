package com.nurali.puzzlebox.games

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.ui.Pal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Rules of Togyzkumalak ("nine pebbles") for two players, with a shortened variant.
 * Indices 0 until n are the bottom player's pits (left to right) and n until 2n the top player's in the same
 * counter-clockwise order, so sowing simply walks the indices upward and wraps around.
 */
class TogyzBoard(val rules: Rules, var pits: IntArray, var kazan: IntArray = intArrayOf(0, 0), var tuzdyk: Array<Int?> = arrayOf(null, null), var turn: Side = Side.Bottom) {
    enum class Side(val v: Int) { Bottom(0), Top(1); val other get() = if (this == Bottom) Top else Bottom }

    /** Classic: 9 pits of 9 pebbles, tuzdyks, 82 to win. Quick: 6 pits of 5 pebbles, no tuzdyks, 31 to win. */
    class Rules(val pits: Int, val start: Int, val tuzdyksEnabled: Boolean) {
        val total get() = pits * 2 * start
        val winning get() = total / 2 + 1
        companion object { val classic = Rules(9, 9, true); val quick = Rules(6, 5, false) }
    }

    class Outcome(val drops: MutableList<Int> = ArrayList(), var last: Int = 0, var captured: Int = 0, var newTuzdyk: Int? = null)

    constructor(rules: Rules) : this(rules, IntArray(rules.pits * 2) { rules.start })

    fun copy() = TogyzBoard(rules, pits.copyOf(), kazan.copyOf(), tuzdyk.copyOf(), turn)

    val n get() = rules.pits
    fun side(i: Int) = if (i < n) Side.Bottom else Side.Top
    fun number(i: Int) = i % n + 1
    fun isTuzdyk(i: Int): Side? = if (tuzdyk[0] == i) Side.Bottom else if (tuzdyk[1] == i) Side.Top else null
    fun legalMoves(s: Side): List<Int> = (if (s == Side.Bottom) 0 until n else n until 2 * n).filter { pits[it] > 0 }

    /** Plays [index] for the side to move and passes the turn. Returns null if the move is illegal. */
    fun play(index: Int): Outcome? {
        if (index !in pits.indices || side(index) != turn || pits[index] <= 0) return null
        val mover = turn
        val outcome = Outcome()
        val count = pits[index]
        pits[index] = 0
        // One pebble moves on to the next pit; more are sown starting in the same pit.
        var pos = if (count == 1) (index + 1) % (2 * n) else index
        repeat(count) {
            outcome.drops.add(pos)
            val owner = isTuzdyk(pos)
            if (owner != null) kazan[owner.v]++ else pits[pos]++
            outcome.last = pos
            pos = (pos + 1) % (2 * n)
        }
        val last = outcome.last
        if (side(last) != mover && isTuzdyk(last) == null) {
            if (pits[last] % 2 == 0) { outcome.captured = pits[last]; kazan[mover.v] += pits[last]; pits[last] = 0 }
            else if (rules.tuzdyksEnabled && pits[last] == 3 && canMakeTuzdyk(last, mover)) {
                tuzdyk[mover.v] = last; kazan[mover.v] += 3; pits[last] = 0; outcome.captured = 3; outcome.newTuzdyk = last
            }
        }
        turn = mover.other
        return outcome
    }

    /** A tuzdyk cannot be the last pit, mirror an existing one, or be a second for the same player. */
    private fun canMakeTuzdyk(index: Int, mover: Side): Boolean {
        if (tuzdyk[mover.v] != null || number(index) == n) return false
        tuzdyk[mover.other.v]?.let { if (number(it) == number(index)) return false }
        return true
    }

    val pitsEmpty get() = pits.all { it == 0 }
    val isDraw get() = kazan[0] == kazan[1] && kazan[0] * 2 == rules.total && pitsEmpty
    val winner: Side?
        get() {
            if (kazan[0] >= rules.winning) return Side.Bottom
            if (kazan[1] >= rules.winning) return Side.Top
            if (pitsEmpty) return if (kazan[0] > kazan[1]) Side.Bottom else if (kazan[1] > kazan[0]) Side.Top else null
            return null
        }
    val isOver get() = winner != null || isDraw

    /** Settles the game when it is over: the side to move having no pebbles hands the rest to the opponent. */
    fun finishIfStuck() {
        if (kazan[0] >= rules.winning || kazan[1] >= rules.winning) return
        if (legalMoves(turn).isNotEmpty()) return
        for (i in pits.indices) if (pits[i] > 0) { kazan[side(i).v] += pits[i]; pits[i] = 0 }
    }

    // MARK: Computer opponent

    fun evaluate(side: Side): Int {
        val me = side.v; val you = side.other.v
        var score = (kazan[me] - kazan[you]) * 10
        if (tuzdyk[me] != null) score += 30 + (tuzdyk[me]?.let { n - number(it) } ?: 0) * 2
        if (tuzdyk[you] != null) score -= 30
        for (i in pits.indices) score += (if (side(i) == side) 1 else -1) * pits[i]
        return score
    }

    /** Negamax with alpha-beta pruning; returns the best pit for the side to move. */
    fun bestMove(depth: Int, randomness: Int = 0): Int? {
        val moves = legalMoves(turn)
        if (moves.isEmpty()) return null
        val scored = moves.map { m ->
            val next = copy(); next.play(m)
            val v = -next.negamax(depth - 1, -INF, INF)
            m to v + (if (randomness > 0) Random.nextInt(0, randomness + 1) else 0)
        }
        val top = scored.maxOf { it.second }
        return scored.filter { it.second == top }.random().first
    }

    private fun negamax(depth: Int, alpha: Int, beta: Int): Int {
        val node = copy(); node.finishIfStuck()
        node.winner?.let { return if (it == node.turn) 100_000 else -100_000 }
        if (node.isDraw) return 0
        val moves = node.legalMoves(node.turn)
        if (depth <= 0 || moves.isEmpty()) return node.evaluate(node.turn)
        var best = -INF; var a = alpha
        for (m in moves) {
            val next = node.copy(); next.play(m)
            best = maxOf(best, -next.negamax(depth - 1, -beta, -a))
            a = maxOf(a, best)
            if (a >= beta) break
        }
        return best
    }

    companion object { private const val INF = 1_000_000 }
}

enum class TogyzMode(val titleKey: String, val rules: TogyzBoard.Rules, val depth: Int, val randomness: Int) {
    Quick("Quick", TogyzBoard.Rules.quick, 2, 6), Classic("Classic", TogyzBoard.Rules.classic, 4, 0)
}

class TogyzEngine(private val scope: CoroutineScope) : GameEngine {
    private val modeKey = "togyzMode"
    private var stateBacking by mutableStateOf<GameState>(GameState.Playing)
    override var state: GameState
        get() = stateBacking
        set(v) { stateBacking = v }
    var mode by mutableStateOf(TogyzMode.entries.getOrElse(Settings.prefs.getInt(modeKey, 0)) { TogyzMode.Quick })
        private set
    var board by mutableStateOf(TogyzBoard(TogyzMode.Quick.rules))
    /** What is on screen while a move is being sown pebble by pebble. */
    var display by mutableStateOf(TogyzBoard(TogyzMode.Quick.rules))
    var selected by mutableStateOf<Int?>(null)
    var hintPit by mutableStateOf<Int?>(null)
    var lastPit by mutableStateOf<Int?>(null)
    var busy by mutableStateOf(false)
    var message by mutableStateOf("")
    var hintsLeft by mutableIntStateOf(0)
    private var token = 0

    override val score get() = display.kazan[0] * (if (mode == TogyzMode.Quick) 8 else 5) + (if ((state as? GameState.GameOver)?.won == true) (if (mode == TogyzMode.Quick) 300 else 500) else 0)
    val playerTurn get() = board.turn == TogyzBoard.Side.Bottom && !busy && state == GameState.Playing
    val showsPreview get() = mode == TogyzMode.Quick

    init { restart() }

    override fun restart() {
        token++
        state = GameState.Playing
        board = TogyzBoard(mode.rules); display = board.copy()
        selected = null; hintPit = null; lastPit = null; busy = false
        hintsLeft = if (mode == TogyzMode.Quick) 99 else 3
        message = L10n.t("Your move")
    }

    fun chooseMode(v: TogyzMode) {
        if (v == mode) return
        mode = v; Settings.prefs.edit().putInt(modeKey, v.ordinal).apply(); restart()
    }

    class Preview(val last: Int, val captured: Int, val tuzdyk: Boolean)

    /** What playing a pit would do, for the Quick mode preview. */
    fun preview(index: Int): Preview? {
        val copy = board.copy()
        val o = copy.play(index) ?: return null
        return Preview(o.last, o.captured, o.newTuzdyk != null)
    }

    fun tap(index: Int) {
        if (!playerTurn || board.side(index) != TogyzBoard.Side.Bottom || board.pits[index] <= 0) return
        hintPit = null
        if (showsPreview && selected != index) {
            selected = index
            Haptics.tap(); Sfx.tap()
            preview(index)?.let { p ->
                message = if (p.tuzdyk) L10n.t("This move makes a tuzdyk!") else if (p.captured > 0) L10n.f("This move captures %d", p.captured) else L10n.t("Tap again to play this pit")
            }
            return
        }
        selected = null
        commit(index)
    }

    fun hint() {
        if (!playerTurn || hintsLeft <= 0) return
        val move = board.bestMove(4) ?: return
        hintsLeft--; hintPit = move; selected = null
        message = L10n.t("Try the highlighted pit")
        Haptics.move(); Sfx.point()
    }

    private fun commit(index: Int) {
        val next = board.copy()
        val outcome = next.play(index) ?: return
        val mover = board.turn
        val pre = board.copy()
        board = next; busy = true; message = ""; lastPit = outcome.last
        val id = token
        scope.launch { animate(pre, index, outcome, mover, id) }
    }

    private suspend fun animate(pre: TogyzBoard, index: Int, outcome: TogyzBoard.Outcome, mover: TogyzBoard.Side, id: Int) {
        val shown = pre.copy()
        shown.pits[index] = 0
        display = shown.copy()
        for (drop in outcome.drops) {
            while (state == GameState.Paused) delay(120)
            if (id != token) return
            delay(if (outcome.drops.size > 10) 90 else 130)
            if (id != token) return
            val owner = shown.isTuzdyk(drop)
            if (owner != null) { shown.kazan[owner.v]++; Sfx.point() } else { shown.pits[drop]++; Sfx.tap() }
            display = shown.copy()
        }
        delay(220)
        if (id != token) return
        // The settled position includes captures and new tuzdyks.
        display = board.copy()
        if (outcome.newTuzdyk != null) {
            message = if (mover == TogyzBoard.Side.Bottom) L10n.t("Tuzdyk! This pit is yours now") else L10n.t("The computer made a tuzdyk")
            Haptics.success(); Sfx.win()
        } else if (outcome.captured > 0) {
            message = if (mover == TogyzBoard.Side.Bottom) L10n.f("You captured %d", outcome.captured) else L10n.f("The computer captured %d", outcome.captured)
            if (mover == TogyzBoard.Side.Bottom) { Haptics.success(); Sfx.point() } else { Haptics.move(); Sfx.wrong() }
        } else message = if (mover == TogyzBoard.Side.Bottom) L10n.t("Computer is thinking…") else L10n.t("Your move")
        board.finishIfStuck()
        display = board.copy()
        busy = false
        if (finishGameIfOver()) return
        if (board.turn == TogyzBoard.Side.Top) computerMove(id) else if (outcome.captured == 0) message = L10n.t("Your move")
    }

    private suspend fun computerMove(id: Int) {
        busy = true
        delay(650)
        if (id != token) return
        while (state == GameState.Paused) { delay(120); if (id != token) return }
        val snapshot = board.copy()
        val move = withContext(Dispatchers.Default) { snapshot.bestMove(mode.depth, mode.randomness) }
        if (id != token) return
        if (move == null) { busy = false; finishGameIfOver(); return }
        val next = board.copy()
        val outcome = next.play(move) ?: run { busy = false; return }
        val pre = board.copy()
        board = next; lastPit = outcome.last
        animate(pre, move, outcome, TogyzBoard.Side.Top, id)
    }

    /** Ends the game when someone has enough pebbles or the board is empty. */
    private fun finishGameIfOver(): Boolean {
        board.finishIfStuck()
        display = board.copy()
        if (!board.isOver) return false
        val w = board.winner
        message = if (w == TogyzBoard.Side.Bottom) L10n.t("You won!") else if (w == TogyzBoard.Side.Top) L10n.t("The computer won") else L10n.t("A draw")
        state = GameState.GameOver(won = w == TogyzBoard.Side.Bottom)
        busy = false
        return true
    }
}

private val You = Color(0xFF33B3F2)
private val Them = Color(0xFFFF8C4D)

@Composable
fun TogyzScreen(onExit: () -> Unit) {
    val scope = rememberCoroutineScope()
    val engine = remember { TogyzEngine(scope) }
    val pal = Pal.current
    GameContainer(GameId.Togyzkumalak, engine, onExit, summary = { L10n.t(engine.mode.titleKey) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(pal.surface)) {
                TogyzMode.entries.forEach { m ->
                    Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (engine.mode == m) pal.accent else Color.Transparent)
                        .clickable { engine.chooseMode(m) }.padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                        Text(L10n.t(m.titleKey), color = if (engine.mode == m) pal.onAccent else pal.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }
                }
            }
            androidx.compose.foundation.layout.Spacer(Modifier.height(12.dp))
            val b = engine.display; val n = b.n
            Kazan(engine, TogyzBoard.Side.Top)
            androidx.compose.foundation.layout.Spacer(Modifier.height(10.dp))
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(Brush.verticalGradient(listOf(Color(0xFF9E6638), Color(0xFF73451F))))
                .border(1.5.dp, Color.White.copy(alpha = 0.18f), RoundedCornerShape(22.dp)).padding(10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                // The top player's pits are drawn right to left: sowing runs counter-clockwise.
                Row(horizontalArrangement = Arrangement.spacedBy(if (n > 6) 4.dp else 8.dp)) { for (i in (n until 2 * n).reversed()) Pit(engine, i, true, Modifier.weight(1f)) }
                Row(horizontalArrangement = Arrangement.spacedBy(if (n > 6) 4.dp else 8.dp)) { for (i in 0 until n) Pit(engine, i, false, Modifier.weight(1f)) }
            }
            androidx.compose.foundation.layout.Spacer(Modifier.height(10.dp))
            Kazan(engine, TogyzBoard.Side.Bottom)
            Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(engine.message, color = if (engine.board.turn == TogyzBoard.Side.Bottom) pal.accent else Color(0xFFFF9500), fontWeight = FontWeight.SemiBold, fontSize = 14.sp, modifier = Modifier.weight(1f))
                val canHint = engine.playerTurn && engine.hintsLeft > 0
                Text("💡 " + if (engine.mode == TogyzMode.Quick) L10n.t("Hint") else L10n.f("Hint (%d)", engine.hintsLeft), color = pal.text.copy(alpha = if (canHint) 1f else 0.4f), fontWeight = FontWeight.Bold, fontSize = 14.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surfaceHigh).clickable(enabled = canHint) { engine.hint() }.padding(horizontal = 12.dp, vertical = 7.dp))
            }
            Text(L10n.t(if (engine.mode == TogyzMode.Quick) "Pick a pit to see what it does, then tap it again to play. Collect 31 pebbles to win."
            else "Sow counter-clockwise. End on the opponent's side with an even count to capture it; make exactly 3 to claim a tuzdyk. Collect 82 to win."),
                color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
        }
    }
}

@Composable
private fun Pit(e: TogyzEngine, index: Int, top: Boolean, modifier: Modifier) {
    val b = e.display
    val count = b.pits[index]
    val owner = b.isTuzdyk(index)
    val selected = e.selected == index
    val preview = e.selected?.let { e.preview(it) }
    val isEnd = preview?.last == index
    val hinted = e.hintPit == index
    val last = e.lastPit == index && !e.busy
    val ring = if (selected) Color.White else if (hinted) Color.Yellow else if (isEnd) Color.Green else if (last) Color.White.copy(alpha = 0.7f) else Color.Transparent
    Box(modifier.aspectRatio(1f).clickable(remember { MutableInteractionSource() }, null) { e.tap(index) }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val side = size.width
            drawCircle(Color.Black.copy(alpha = 0.42f), side / 2)
            drawCircle(Brush.radialGradient(listOf(Color(0xFF402412), Color(0xFF1F0F08)), center, side * 0.55f), side / 2 - side * 0.04f)
            if (owner != null) drawCircle(if (owner == TogyzBoard.Side.Bottom) You else Them, side / 2 - side * 0.04f, style = androidx.compose.ui.graphics.drawscope.Stroke(3.dp.toPx()))
            // Up to a dozen small pebbles around the pit's centre.
            val tones = listOf(Color(0xFFEDE0C7), Color(0xFFD9C7A8), Color(0xFFF5EDDB))
            for (k in 0 until min(count, 12)) {
                val ringIdx = if (k < 5) 0 else 1
                val inRing = if (ringIdx == 0) 5 else 7
                val a = ((if (ringIdx == 0) k else k - 5).toFloat() / inRing) * (PI * 2).toFloat() + ringIdx * 0.5f
                val r = side * (if (ringIdx == 0) 0.17f else 0.3f)
                drawCircle(tones[k % 3].copy(alpha = 0.55f), side * 0.075f, Offset(side / 2 + cos(a) * r, side / 2 + sin(a) * r))
            }
            drawCircle(ring, side / 2 - 1.dp.toPx(), style = androidx.compose.ui.graphics.drawscope.Stroke(if (selected || hinted || isEnd) 3.dp.toPx() else 2.dp.toPx()))
        }
        if (owner != null) Text("★", color = (if (owner == TogyzBoard.Side.Bottom) You else Them).copy(alpha = 0.9f), fontSize = 22.sp)
        else if (count > 0) Text("$count", color = Color.White, fontWeight = FontWeight.ExtraBold, fontSize = 15.sp)
        if (isEnd && preview != null && preview.captured > 0) Text("+${preview.captured}", color = Color.Black, fontSize = 10.sp, fontWeight = FontWeight.Bold,
            modifier = Modifier.align(Alignment.TopCenter).clip(RoundedCornerShape(50)).background(Color.Green).padding(horizontal = 4.dp))
    }
}

@Composable
private fun Kazan(e: TogyzEngine, side: TogyzBoard.Side) {
    val pal = Pal.current
    val b = e.display
    val value = b.kazan[side.v]
    val color = if (side == TogyzBoard.Side.Bottom) You else Them
    val goal = b.rules.winning
    val active = e.board.turn == side && e.state == GameState.Playing
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(pal.surface).border(2.dp, if (active) color.copy(alpha = 0.8f) else Color.Transparent, RoundedCornerShape(16.dp)).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(if (side == TogyzBoard.Side.Bottom) "👤" else "🖥", fontSize = 20.sp)
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(L10n.t(if (side == TogyzBoard.Side.Bottom) "Your kazan" else "Computer's kazan"), color = pal.textSecondary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text("$value", color = color, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text(" / $goal", color = pal.textSecondary, fontSize = 12.sp)
            }
            Box(Modifier.fillMaxWidth().height(8.dp).clip(CircleShape).background(pal.surfaceHigh)) {
                Box(Modifier.fillMaxWidth(min(1f, value.toFloat() / goal)).height(8.dp).clip(CircleShape).background(color))
            }
        }
    }
}
