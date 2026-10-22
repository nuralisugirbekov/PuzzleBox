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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
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
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.FrameLoop
import com.nurali.puzzlebox.games.kit.Hearts
import com.nurali.puzzlebox.ui.Pal
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

enum class AttentionMode(val id: GameId, val hint: String) {
    FindColor(GameId.FindColor, "Choose the ink color, not the word."),
    FindPair(GameId.FindPair, "Find and tap the two identical symbols."),
}

class AttentionEngine(val mode: AttentionMode) : FrameGame {
    companion object {
        val symbols = listOf("●", "■", "◆", "▲", "★", "♥", "♠", "♣", "☾", "⚡", "☀", "❀", "⚑", "♪", "⬢", "⬟")
        val colorNames = listOf("Red", "Blue", "Green", "Orange", "Purple", "Yellow")
        val colors = listOf(Color(0xFFFF3B30), Color(0xFF007AFF), Color(0xFF34C759), Color(0xFFFF9500), Color(0xFFAF52DE), Color(0xFFFFCC00))
        val tileColors = listOf(Color(0xFF32ADE6), Color(0xFFFF2D55), Color(0xFFFFCC00), Color(0xFF00C7BE), Color(0xFFFF9500), Color(0xFFAF52DE))
    }

    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var started by mutableStateOf(false)
    var timeLeft by mutableDoubleStateOf(30.0)
    var lives by mutableIntStateOf(3)
    /** Find Pair tiles: symbol index and colour index. */
    var items by mutableStateOf(listOf<Pair<Int, Int>>())
    var options by mutableStateOf(listOf<Int>())
    /** Misleading ink for each option label. */
    var optionInks by mutableStateOf(listOf<Int>())
    var marked by mutableStateOf(setOf<Int>())
    private var first: Int? = null
    var round by mutableIntStateOf(0)
    var prompt by mutableIntStateOf(0)
    var ink by mutableIntStateOf(0)
    /** Find Color: when true, the answer is the written word instead of the ink. */
    var askWord by mutableStateOf(false)
    var streak by mutableIntStateOf(0)
    var feedback by mutableStateOf("")
    var lastCorrect by mutableStateOf(false)
    private var answer = 0
    private var delay = 0.0
    private var roundTime = 0.0

    val multiplier get() = min(4, 1 + streak / 3)
    val colorCount get() = if (round < 5) 4 else 6
    val columns get() = if (items.size >= 25) 5 else 4

    init { restart() }

    override fun restart() {
        score = 0; state = GameState.Playing; started = false; timeLeft = 30.0; lives = 3; round = 0; delay = 0.0; feedback = ""; streak = 0
        prepare()
    }

    fun start() { if (state == GameState.Playing && !started) started = true }

    private fun prepare() {
        marked = emptySet(); first = null; roundTime = 0.0; feedback = ""
        when (mode) {
            AttentionMode.FindColor -> {
                val count = colorCount
                prompt = Random.nextInt(count); ink = (prompt + Random.nextInt(1, count)) % count
                askWord = round >= 6 && Random.nextInt(10) < 3
                answer = if (askWord) prompt else ink
                val opts = (0 until count).shuffled()
                options = opts
                // Later rounds paint the option labels in the wrong colours too.
                optionInks = opts.map { option -> if (round >= 3) (option + Random.nextInt(1, count)) % count else -1 }
            }
            AttentionMode.FindPair -> {
                val total = if (round < 3) 12 else if (round < 7) 16 else if (round < 12) 20 else 25
                val colorVariety = if (round < 5) 1 else min(tileColors.size, 2 + round / 5)
                val pool = LinkedHashSet<Pair<Int, Int>>()
                while (pool.size < total - 1) pool.add(Random.nextInt(symbols.size) to Random.nextInt(colorVariety))
                val list = pool.toMutableList()
                list.add(list[0]); list.shuffle()
                items = list
            }
        }
    }

    fun choose(index: Int) {
        if (!started || state != GameState.Playing || delay != 0.0) return
        when (mode) {
            AttentionMode.FindColor -> { if (index in options.indices) finish(options[index] == answer) }
            AttentionMode.FindPair -> {
                if (index !in items.indices || first == index) return
                val f = first
                if (f != null) {
                    marked = marked + index
                    finish(items[f] == items[index])
                } else { first = index; marked = marked + index; Sfx.tap() }
            }
        }
    }

    private fun finish(correct: Boolean) {
        lastCorrect = correct
        if (correct) {
            streak++
            val gained = (100 + max(0, 50 - (roundTime * 10).toInt())) * multiplier
            score += gained
            // Quick answers buy a little extra time.
            timeLeft = min(60.0, timeLeft + if (roundTime < 1.5) 2.0 else 1.0)
            feedback = if (multiplier > 1) "+$gained ×$multiplier" else "+$gained"
            Haptics.success(); Sfx.point()
        } else {
            streak = 0; lives--; feedback = L10n.t("Try again"); Haptics.error(); Sfx.wrong()
        }
        delay = 0.55
        if (lives == 0) state = GameState.GameOver(won = false)
    }

    override fun advance(dt: Double) {
        if (!started || state != GameState.Playing) return
        val d = min(0.1, max(0.0, dt))
        if (delay > 0) {
            delay = max(0.0, delay - d)
            if (delay == 0.0) { round++; prepare() }
            return
        }
        timeLeft = max(0.0, timeLeft - d)
        if (timeLeft == 0.0) { state = GameState.GameOver(won = true); return }
        roundTime += d
    }
}

@Composable
fun AttentionScreen(mode: AttentionMode, onExit: () -> Unit) {
    val engine = remember { AttentionEngine(mode) }
    val pal = Pal.current
    FrameLoop(engine)
    GameContainer(mode.id, engine, onExit, summary = { L10n.f("Rounds: %d", engine.round) }) {
        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
            Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("⏱ 0:%02d".format(ceil(engine.timeLeft).toInt()), color = if (engine.timeLeft < 6) Color.Red else pal.accent, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                if (engine.multiplier > 1) Text("🔥×${engine.multiplier}", color = Color(0xFFFF9500), fontWeight = FontWeight.Bold)
                androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                Hearts(engine.lives, 3)
            }
            if (!engine.started) {
                Box(Modifier.fillMaxWidth().height(300.dp), contentAlignment = Alignment.Center) {
                    Box(Modifier.clip(RoundedCornerShape(16.dp)).background(pal.accent).clickable { engine.start() }.padding(horizontal = 28.dp, vertical = 14.dp)) {
                        Text(L10n.t("Tap to start"), color = pal.onAccent, fontWeight = FontWeight.Bold, fontSize = 18.sp)
                    }
                }
            } else Box(Modifier.heightIn(min = 300.dp)) { AttentionBoard(engine) }
            Text(engine.feedback.ifEmpty { " " }, color = if (engine.lastCorrect) Color(0xFF34C759) else Color.Red, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 12.dp))
            Text(L10n.t(mode.hint), color = pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        }
    }
}

@Composable
private fun AttentionBoard(e: AttentionEngine) {
    val pal = Pal.current
    when (e.mode) {
        AttentionMode.FindColor -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(22.dp)) {
            // The rule banner flips colour when the word is what counts.
            Text((if (e.askWord) "Aa " else "🎨 ") + L10n.t(if (e.askWord) "Tap the WORD" else "Tap the INK color"), color = Color.White, fontWeight = FontWeight.Bold, fontSize = 16.sp,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(if (e.askWord) Color(0xFFFF9500) else Color(0xFF007AFF)).padding(horizontal = 16.dp, vertical = 8.dp))
            Text(L10n.t(AttentionEngine.colorNames[e.prompt]), color = AttentionEngine.colors[e.ink], fontSize = 52.sp, fontWeight = FontWeight.ExtraBold)
            for (row in 0 until (e.options.size + 1) / 2) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (col in 0 until 2) {
                    val i = row * 2 + col
                    if (i >= e.options.size) { Box(Modifier.weight(1f)); continue }
                    val inkIndex = e.optionInks.getOrElse(i) { -1 }
                    Box(Modifier.weight(1f).height(58.dp).clip(RoundedCornerShape(14.dp)).background(pal.surfaceHigh).clickable { e.choose(i) }, contentAlignment = Alignment.Center) {
                        Text(L10n.t(AttentionEngine.colorNames[e.options[i]]), color = if (inkIndex >= 0) AttentionEngine.colors[inkIndex] else pal.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
        AttentionMode.FindPair -> Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val cols = e.columns
            for (row in 0 until (e.items.size + cols - 1) / cols) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (col in 0 until cols) {
                    val i = row * cols + col
                    if (i >= e.items.size) { Box(Modifier.weight(1f)); continue }
                    val item = e.items[i]
                    val marked = i in e.marked
                    Box(Modifier.weight(1f).height(if (cols == 5) 52.dp else 60.dp).clip(RoundedCornerShape(12.dp))
                        .background(if (marked) pal.accent.copy(alpha = 0.3f) else pal.surfaceHigh)
                        .then(if (marked) Modifier.border(2.dp, pal.accent, RoundedCornerShape(12.dp)) else Modifier)
                        .clickable { e.choose(i) }, contentAlignment = Alignment.Center) {
                        Text(AttentionEngine.symbols[item.first], color = AttentionEngine.tileColors[item.second], fontSize = if (cols == 5) 24.sp else 28.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
        }
    }
}
