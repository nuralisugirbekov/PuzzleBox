package com.nurali.puzzlebox.games

import android.os.SystemClock
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
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
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.FrameLoop
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

enum class BrainMode(val id: GameId) { Reaction(GameId.ReactionTap), Simon(GameId.Simon) }

class BrainEngine(val mode: BrainMode) : FrameGame {
    override var score by mutableIntStateOf(0)
    private var stateBacking by mutableStateOf<GameState>(GameState.Playing)
    override var state: GameState
        get() = stateBacking
        set(value) {
            stateBacking = value
            // A paused reaction cue must not be used to prepare a zero-time answer.
            if (value == GameState.Paused && mode == BrainMode.Reaction && started && feedbackRemaining <= 0) prepareReaction()
        }
    var started by mutableStateOf(false)
    var message by mutableStateOf("Tap to start")
    var ready by mutableStateOf(false)
    var highlighted by mutableStateOf<Int?>(null)
    val sequence = ArrayList<Int>()
    var sequenceSize by mutableIntStateOf(0)
    var showingSequence by mutableStateOf(false)
    var round by mutableIntStateOf(0)
    val reactionTimes = ArrayList<Int>()
    var timesCount by mutableIntStateOf(0)
    var falseStarts by mutableIntStateOf(0)
    /** Reaction: a yellow decoy flash that must not be tapped. */
    var decoy by mutableStateOf(false)
    var bestTime by mutableStateOf<Int?>(null)
    /** Simon: one replay of the sequence after a mistake. */
    var secondChance by mutableStateOf(true)
    var feedback by mutableStateOf("")

    private var decoyIn: Double? = null
    private var decoyLeft = 0.0
    private var remaining = 0.0
    private var readySince = 0L
    private var sequenceStep = -1
    private var inputIndex = 0
    private var feedbackRemaining = 0.0

    init { restart() }

    override fun restart() {
        score = 0; state = GameState.Playing; started = false; message = "Tap to start"; ready = false
        highlighted = null; sequence.clear(); sequenceSize = 0; showingSequence = false; round = 0
        reactionTimes.clear(); timesCount = 0; falseStarts = 0; decoy = false; decoyIn = null; bestTime = null; secondChance = true
        feedback = ""; remaining = 0.0; readySince = 0; feedbackRemaining = 0.0
        sequenceStep = -1; inputIndex = 0
    }

    fun start() {
        if (state != GameState.Playing || started) return
        started = true
        if (mode == BrainMode.Reaction) prepareReaction() else addSequence()
    }

    private fun prepareReaction() {
        ready = false; readySince = 0; message = "Wait for green…"; decoy = false
        remaining = Random.nextDouble(1.5, 4.5)
        // From the third round on, a yellow decoy may flash before green.
        decoyIn = if (round >= 2 && Random.nextDouble() < 0.45) remaining * Random.nextDouble(0.3, 0.7) else null
    }

    fun tapReaction() {
        if (state != GameState.Playing) return
        if (!started) { start(); return }
        if (feedbackRemaining > 0) return
        if (!ready) {
            falseStarts++; Haptics.error(); Sfx.wrong(); feedback = "Too soon!"; feedbackRemaining = 1.0
            if (falseStarts >= 3) state = GameState.GameOver(won = false)
        } else {
            val ms = max(1, (SystemClock.elapsedRealtime() - readySince).toInt())
            reactionTimes.add(ms); timesCount = reactionTimes.size
            bestTime = min(bestTime ?: ms, ms)
            val (rating, bonus) = rating(ms)
            score += max(0, 1000 - ms) + bonus
            round++; ready = false; feedback = rating; feedbackRemaining = 1.1
            message = "Reaction recorded"
            Haptics.success(); Sfx.point()
            if (round == 5) state = GameState.GameOver(won = true)
        }
    }

    private fun rating(ms: Int): Pair<String, Int> = when {
        ms < 230 -> "Lightning!" to 300
        ms < 300 -> "Super fast!" to 200
        ms < 380 -> "Fast" to 100
        ms < 500 -> "Good" to 50
        else -> "Slow" to 0
    }

    private fun addSequence() {
        sequence.add(Random.nextInt(4)); sequenceSize = sequence.size; showingSequence = true
        sequenceStep = -1; inputIndex = 0; remaining = 0.7; highlighted = null; message = "Watch the sequence"
    }

    fun tapColor(index: Int) {
        if (state != GameState.Playing || !started || showingSequence || feedbackRemaining > 0) return
        if (sequence[inputIndex] != index) {
            Haptics.error(); Sfx.wrong()
            if (secondChance) {
                // Replay the same sequence once instead of ending the game.
                secondChance = false; feedback = "Second chance!"
                showingSequence = true; sequenceStep = -1; inputIndex = 0; remaining = 1.0; highlighted = null
                message = "Watch the sequence"
            } else state = GameState.GameOver(won = false)
            return
        }
        highlighted = index; remaining = 0.16; inputIndex++; Haptics.tap(); Sfx.pad(index, 160)
        if (inputIndex == sequence.size) {
            score += sequence.size * 10; round++; showingSequence = true
            feedbackRemaining = 0.6
        }
    }

    override fun advance(dt: Double) {
        if (!started || state != GameState.Playing) return
        if (feedbackRemaining > 0) {
            feedbackRemaining -= dt
            if (feedbackRemaining <= 0) {
                feedback = ""
                if (mode == BrainMode.Reaction) prepareReaction() else addSequence()
            }
            return
        }
        when (mode) {
            BrainMode.Reaction -> if (!ready) {
                remaining -= dt
                decoyIn?.let { left ->
                    decoyIn = left - dt
                    if (left - dt <= 0) { decoyIn = null; decoy = true; decoyLeft = 0.35; Sfx.tap() }
                }
                if (decoy) { decoyLeft -= dt; if (decoyLeft <= 0) decoy = false }
                if (remaining <= 0) { ready = true; decoy = false; readySince = SystemClock.elapsedRealtime(); message = "Tap now!"; Sfx.tap() }
            }
            BrainMode.Simon -> {
                remaining -= dt
                if (showingSequence && remaining <= 0) {
                    sequenceStep++
                    if (sequenceStep >= sequence.size * 2) {
                        showingSequence = false; highlighted = null; message = "Repeat the sequence"; feedback = ""
                    } else {
                        highlighted = if (sequenceStep % 2 == 0) sequence[sequenceStep / 2] else null
                        highlighted?.let { Sfx.pad(it) }
                        // Playback speeds up as the sequence grows.
                        val count = sequence.size
                        remaining = if (sequenceStep % 2 == 0) max(0.22, 0.45 - count * 0.015) else max(0.1, 0.22 - count * 0.008)
                    }
                } else if (!showingSequence && remaining <= 0) highlighted = null
            }
        }
    }
}

private val padColors = listOf(Color(0xFF34C759), Color(0xFFFF3B30), Color(0xFFFFCC00), Color(0xFF007AFF))

@Composable
fun BrainScreen(mode: BrainMode, onExit: () -> Unit) {
    val engine = remember { BrainEngine(mode) }
    FrameLoop(engine)
    GameContainer(mode.id, engine, onExit, summary = {
        if (mode == BrainMode.Reaction && engine.reactionTimes.isNotEmpty())
            L10n.f("Average: %d ms", engine.reactionTimes.sum() / engine.reactionTimes.size)
        else L10n.f("Rounds: %d", engine.round)
    }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            if (mode == BrainMode.Reaction) ReactionBoard(engine) else SimonBoard(engine)
        }
    }
}

@Composable
private fun ReactionBoard(e: BrainEngine) {
    val pal = Pal.current
    val pad = when {
        e.ready -> Color(0xFF34C759)
        e.decoy -> Color(0xFFFFCC00)
        e.feedback == "Too soon!" -> Color(0xFFFF3B30)
        else -> pal.surfaceHigh
    }
    val onPad = if (e.ready || e.decoy) Color.Black else pal.text
    Row(Modifier.fillMaxWidth().padding(bottom = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L10n.f("Round %d of %d", min(5, e.round + 1), 5), color = pal.textSecondary, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        e.bestTime?.let { Text("🏆 " + L10n.f("Best: %d ms", it), color = Color(0xFFFF9500), fontWeight = FontWeight.SemiBold) }
    }
    Box(Modifier.fillMaxWidth().height(280.dp).clip(RoundedCornerShape(28.dp)).background(pad).clickable { e.tapReaction() }, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(if (e.ready) "⚡" else if (e.decoy) "⚠️" else "👆", fontSize = 52.sp)
            Text(L10n.t(if (e.feedback.isEmpty()) e.message else e.feedback), color = onPad, fontSize = 26.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 10.dp))
            if (e.timesCount > 0 && e.feedback.isNotEmpty() && e.feedback != "Too soon!")
                Text(L10n.f("Reaction: %d ms", e.reactionTimes.last()), color = onPad, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        }
    }
    Row(Modifier.fillMaxWidth().height(92.dp).padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Bottom) {
        for (i in 0 until 5) {
            val time = if (i < e.timesCount) e.reactionTimes[i] else null
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                if (time != null) Text("$time", color = pal.textSecondary, fontSize = 10.sp)
                Box(Modifier.fillMaxWidth().height(if (time != null) max(10, min(70, time / 8)).dp else 10.dp).clip(RoundedCornerShape(6.dp))
                    .background(if (time == null) pal.surfaceHigh else if (time < 300) Color(0xFF34C759) else if (time < 450) Color(0xFFFFCC00) else Color(0xFFFF9500)))
            }
        }
    }
    Text(L10n.f("False starts: %d/3", e.falseStarts), color = if (e.falseStarts > 0) Color.Red else pal.textSecondary, fontSize = 13.sp,
        modifier = Modifier.padding(top = 8.dp).fillMaxWidth(), textAlign = TextAlign.Center)
    Text(L10n.t("Tap the moment the pad turns green. Yellow is a trick!"), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center,
        modifier = Modifier.padding(top = 6.dp).fillMaxWidth())
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.SimonBoard(e: BrainEngine) {
    val pal = Pal.current
    Row(Modifier.fillMaxWidth().padding(bottom = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(L10n.t(if (e.feedback.isEmpty()) e.message else e.feedback), color = if (e.feedback.isEmpty()) pal.text else Color(0xFFFF9500),
            fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        Text(if (e.secondChance) "❤" else "♡", color = if (e.secondChance) Color(0xFFFF2D55) else pal.textSecondary, fontSize = 20.sp)
    }
    Box(Modifier.fillMaxWidth().widthIn(max = 360.dp).aspectRatio(1f).align(Alignment.CenterHorizontally)) {
        Canvas(Modifier.fillMaxSize().pointerInput(e) {
            detectTapGestures { pos ->
                if (!e.started || e.showingSequence) return@detectTapGestures
                val c = Offset(size.width / 2f, size.height / 2f)
                val outer = min(size.width, size.height) / 2f - 6f * density
                val inner = outer * 0.42f
                val d = hypot(pos.x - c.x, pos.y - c.y)
                if (d < inner || d > outer) return@detectTapGestures
                var a = Math.toDegrees(atan2((pos.y - c.y).toDouble(), (pos.x - c.x).toDouble())).toFloat()
                if (a < 0) a += 360f
                // Index 0 spans 180°–270° (top-left), then clockwise.
                e.tapColor((((a - 180f + 360f) % 360f) / 90f).toInt())
            }
        }) {
            val c = Offset(size.width / 2f, size.height / 2f)
            val outer = min(size.width, size.height) / 2f - 6f * density
            val inner = outer * 0.42f
            drawCircle(Color(0xFF1F1F1F), outer + 6f * density, c)
            for (i in 0 until 4) {
                val lit = e.highlighted == i
                val gap = 4f
                val start = i * 90f + 180f + gap; val sweep = 90f - gap * 2
                val path = Path().apply {
                    arcTo(Rect(c.x - outer, c.y - outer, c.x + outer, c.y + outer), start, sweep, true)
                    arcTo(Rect(c.x - inner, c.y - inner, c.x + inner, c.y + inner), start + sweep, -sweep, false)
                    close()
                }
                if (lit) drawPath(path, padColors[i].copy(alpha = 0.35f), style = androidx.compose.ui.graphics.drawscope.Stroke(18f * density))
                drawPath(path, padColors[i].copy(alpha = if (lit) 1f else 0.38f))
            }
            drawCircle(pal.background, outer * 0.36f * 1f, c)
        }
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("${e.sequenceSize}", color = pal.text, fontSize = 36.sp, fontWeight = FontWeight.Black)
            Text(L10n.t("steps"), color = pal.textSecondary, fontSize = 12.sp)
        }
    }
    if (!e.started) {
        Spacer(Modifier.height(16.dp))
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(pal.accent).clickable { e.start() }.padding(18.dp), contentAlignment = Alignment.Center) {
            Text(L10n.t("Tap to start"), color = pal.onAccent, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        }
    }
    Text(L10n.t("Repeat the growing sequence. It speeds up as it gets longer. One mistake is forgiven."), color = pal.textSecondary, fontSize = 13.sp,
        textAlign = TextAlign.Center, modifier = Modifier.padding(top = 14.dp).fillMaxWidth())
}
