package com.nurali.puzzlebox.games

import android.os.SystemClock
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
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
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.ui.Pal
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.random.Random

class QuickMathEngine : GameEngine {
    companion object { val durations = listOf(30, 60, 120) }

    var hasStarted by mutableStateOf(false)
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var solved by mutableIntStateOf(0)
    var mistakes by mutableIntStateOf(0)
    var expression by mutableStateOf("")
    var input by mutableStateOf("")
    var wrongAnswer by mutableStateOf(false)
    var remaining by mutableFloatStateOf(60f)
    /** Correct answers in a row without a mistake. */
    var streak by mutableIntStateOf(0)
    var lastGain by mutableIntStateOf(0)
    private var answer = 0

    val secondsLeft get() = ceil(remaining).toInt()
    /** Every five correct answers bumps the multiplier, up to ×4. */
    val multiplier get() = minOf(4, 1 + streak / 5)
    /** Problems grow as you solve more of them. */
    private val tier get() = minOf(4, solved / 6)

    override fun restart() {
        hasStarted = false; score = 0; solved = 0; mistakes = 0; streak = 0; lastGain = 0
        input = ""; wrongAnswer = false; remaining = 60f
        state = GameState.Playing
    }

    fun start(seconds: Int) {
        if (hasStarted || seconds !in durations) return
        remaining = seconds.toFloat()
        hasStarted = true
        nextProblem()
    }

    fun advance(seconds: Float) {
        if (!hasStarted || state != GameState.Playing) return
        remaining = maxOf(0f, remaining - seconds)
        if (remaining <= 0f) state = GameState.GameOver(won = true)
    }

    fun enter(digit: Int) {
        if (!hasStarted || state != GameState.Playing) return
        if (wrongAnswer) { input = ""; wrongAnswer = false }
        if (input.length >= 3) return
        Sfx.tap()
        input = if (input == "0") digit.toString() else input + digit
        // Answers check themselves once enough digits are typed.
        if (input.length >= answer.toString().length) submit()
    }

    fun erase() {
        if (!hasStarted || state != GameState.Playing) return
        if (input.isNotEmpty()) input = input.dropLast(1)
        wrongAnswer = false
    }

    fun submit() {
        if (!hasStarted || state != GameState.Playing) return
        val value = input.toIntOrNull() ?: return
        if (value == answer) {
            solved++; streak++
            lastGain = 10 * multiplier
            score += lastGain
            Haptics.success(); Sfx.point()
            nextProblem()
        } else {
            // Keep the same problem, so repeated guessing cannot skip difficult questions.
            mistakes++; streak = 0; wrongAnswer = true; input = ""
            Haptics.error(); Sfx.wrong()
        }
    }

    private fun nextProblem() {
        val previous = expression
        val top = 10 + tier * 12
        do {
            val a = Random.nextInt(1, top + 1); val b = Random.nextInt(1, top + 1)
            when (Random.nextInt(if (tier >= 3) 5 else 4)) {
                0 -> { expression = "$a + $b"; answer = a + b }
                1 -> { expression = "${maxOf(a, b)} − ${minOf(a, b)}"; answer = abs(a - b) }
                2 -> {
                    val x = Random.nextInt(2, 7 + tier * 2); val y = Random.nextInt(2, 7 + tier * 2)
                    expression = "$x × $y"; answer = x * y
                }
                3 -> {
                    val divisor = Random.nextInt(2, 7 + tier * 2); val quotient = Random.nextInt(1, 7 + tier * 2)
                    expression = "${divisor * quotient} ÷ $divisor"; answer = quotient
                }
                else -> {
                    // Two-step problems for the top tiers.
                    val x = Random.nextInt(2, 10); val y = Random.nextInt(2, 10); val z = Random.nextInt(1, 21)
                    expression = "$x × $y + $z"; answer = x * y + z
                }
            }
        } while (expression == previous || answer > 999)
        input = ""; wrongAnswer = false
    }
}

@Composable
fun QuickMathScreen(onExit: () -> Unit) {
    val engine = remember { QuickMathEngine() }
    val pal = Pal.current
    LaunchedEffect(engine) {
        var last = SystemClock.elapsedRealtime()
        while (isActive) {
            delay(100)
            val now = SystemClock.elapsedRealtime()
            engine.advance((now - last) / 1000f)
            last = now
        }
    }
    GameContainer(GameId.QuickMath, engine, onExit) {
        if (!engine.hasStarted) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("➗", fontSize = 56.sp)
                Text(L10n.t("Beat the clock with mental math"), color = pal.text, fontSize = 20.sp, fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center, modifier = Modifier.padding(vertical = 12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    QuickMathEngine.durations.forEach { s ->
                        Box(Modifier.clip(RoundedCornerShape(20.dp)).background(pal.accent).clickable { engine.start(s) }
                            .padding(horizontal = 22.dp, vertical = 16.dp), contentAlignment = Alignment.Center) {
                            Text("$s s", color = pal.onAccent, fontSize = 20.sp, fontWeight = FontWeight.Black)
                        }
                    }
                }
            }
        } else {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.SpaceBetween) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("⏱ ${engine.secondsLeft}", color = if (engine.secondsLeft <= 10) Color(0xFFFF3B30) else pal.text,
                        fontSize = 22.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                    Text(L10n.f("Solved: %d", engine.solved), color = pal.textSecondary, fontSize = 14.sp)
                    if (engine.multiplier > 1) Text("  ×${engine.multiplier}", color = Color(0xFFFFCC00), fontWeight = FontWeight.Black)
                }
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(engine.expression, color = pal.text, fontSize = 44.sp, fontWeight = FontWeight.Black)
                    Spacer(Modifier.height(10.dp))
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                        .background(if (engine.wrongAnswer) Color(0x55FF3B30) else pal.surface).padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center) {
                        Text(if (engine.input.isEmpty()) "?" else engine.input, color = pal.text, fontSize = 36.sp, fontWeight = FontWeight.Bold)
                    }
                    if (engine.wrongAnswer) Text(L10n.t("Wrong answer — try again"), color = Color(0xFFFF3B30), fontSize = 13.sp,
                        modifier = Modifier.padding(top = 6.dp))
                }
                Keypad(engine)
            }
        }
    }
}

@Composable
private fun Keypad(engine: QuickMathEngine) {
    val pal = Pal.current
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("⌫", "0", "✓"))
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { key ->
                    Box(Modifier.weight(1f).height(56.dp).clip(RoundedCornerShape(16.dp))
                        .background(if (key == "✓") pal.accent else pal.surface)
                        .clickable {
                            when (key) { "⌫" -> engine.erase(); "✓" -> engine.submit(); else -> engine.enter(key.toInt()) }
                        }, contentAlignment = Alignment.Center) {
                        Text(key, color = if (key == "✓") pal.onAccent else pal.text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}
