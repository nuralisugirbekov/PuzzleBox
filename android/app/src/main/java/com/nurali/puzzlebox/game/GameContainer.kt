package com.nurali.puzzlebox.game

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.AppAnalytics
import com.nurali.puzzlebox.core.GameRoundAnalytics
import com.nurali.puzzlebox.core.ReviewPrompt
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.core.Stats
import com.nurali.puzzlebox.ui.Pal
import kotlinx.coroutines.delay

/**
 * Shared chrome for every game: header, score cards, pause and game-over overlays, high-score
 * recording and the one-time rating prompt. [nextLevel] makes a win advance automatically.
 */
@Composable
fun GameContainer(
    id: GameId,
    engine: GameEngine,
    onExit: () -> Unit,
    nextLevel: (() -> Unit)? = null,
    summary: () -> String? = { null },
    timed: Boolean = false,
    resultTitle: String? = null,
    content: @Composable BoxScope.() -> Unit,
) {
    val pal = Pal.current
    val state = engine.state
    val activity = LocalContext.current as? Activity
    var finalScore by remember { mutableIntStateOf(0) }
    var newRecord by remember { mutableStateOf(false) }
    var advancing by remember { mutableStateOf(false) }
    var elapsed by remember { mutableDoubleStateOf(0.0) }
    var timeBonus by remember { mutableIntStateOf(0) }
    val round = remember { GameRoundAnalytics() }
    val restartGame = {
        AppAnalytics.log("game_restart", "game_id" to id.raw, "score" to engine.score)
        round.finish(engine.score, "restart")
        engine.restart(); elapsed = 0.0; timeBonus = 0
        round.start(id, true)
    }
    LaunchedEffect(Unit) { AppAnalytics.screen("game_" + id.raw); round.start(id, engine.state == GameState.Playing) }
    DisposableEffect(Unit) { onDispose { round.finish(engine.score, "exit") } }
    LaunchedEffect(state) {
        round.setActive(state == GameState.Playing)
        if (state == GameState.Paused) round.event("game_pause", engine.score)
    }

    // Pause when the app goes to the background.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, engine) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE && engine.state == GameState.Playing) engine.state = GameState.Paused
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Card games run a round clock that only ticks while playing; a win earns a time bonus.
    LaunchedEffect(engine, timed) {
        if (!timed) return@LaunchedEffect
        var last = android.os.SystemClock.elapsedRealtime()
        while (true) {
            delay(250)
            val now = android.os.SystemClock.elapsedRealtime()
            if (engine.state == GameState.Playing) elapsed += (now - last) / 1000.0
            last = now
        }
    }

    LaunchedEffect(state) {
        if (state is GameState.GameOver) {
            timeBonus = if (timed && state.won) (1000 / (1 + elapsed / 300)).toInt() else 0
            finalScore = engine.score + timeBonus
            newRecord = Stats.record(id, finalScore)
            round.finish(finalScore, "completed", state.won, newRecord, if (timed) timeBonus else null)
            if (state.won) { Haptics.success(); Sfx.win() } else { Haptics.error(); Sfx.lose() }
            if (nextLevel == null && ReviewPrompt.shouldAsk && activity != null) {
                ReviewPrompt.markAsked()
                delay(2500)
                ReviewPrompt.request(activity)
            }
            if (state.won && nextLevel != null) {
                advancing = true
                delay(1700)
                advancing = false
                nextLevel()
            }
        } else {
            advancing = false
        }
    }

    BackHandler {
        when (engine.state) {
            GameState.Playing -> engine.state = GameState.Paused
            else -> onExit()
        }
    }

    Box(Modifier.fillMaxSize().background(pal.background)) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 16.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                RoundButton(onClick = onExit) { Icon(Icons.Default.Close, null, tint = pal.text) }
                Text(id.info.title, color = pal.text, fontSize = 22.sp, fontWeight = FontWeight.Bold,
                    modifier = Modifier.weight(1f).padding(start = 12.dp), maxLines = 1)
                RoundButton(onClick = {
                    if (engine.state == GameState.Playing) engine.state = GameState.Paused
                }) { PauseGlyph(pal.text) }
                Spacer(Modifier.width(8.dp))
                RoundButton(onClick = { restartGame() }) { Icon(Icons.Default.Refresh, null, tint = pal.text) }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard(L10n.t("Score"), engine.score, Modifier.weight(1f))
                StatCard(L10n.t("Your Records"), maxOf(Stats.highScore(id), 0), Modifier.weight(1f))
            }
            if (timed) Text("⏱ %02d:%02d".format(elapsed.toInt() / 60, elapsed.toInt() % 60), color = pal.textSecondary, fontSize = 13.sp,
                modifier = Modifier.padding(top = 6.dp))
            Spacer(Modifier.height(12.dp))
            Box(Modifier.weight(1f).fillMaxWidth(), content = content)
        }

        AnimatedVisibility(state == GameState.Paused, enter = fadeIn(tween(180)) + scaleIn(tween(220), initialScale = 0.94f), exit = fadeOut(tween(150))) {
            Overlay {
                Text(L10n.t("Game Paused"), color = pal.text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(16.dp))
                PrimaryButton(L10n.t("Resume")) { engine.state = GameState.Playing }
                Spacer(Modifier.height(8.dp))
                SecondaryButton(L10n.t("Restart")) { restartGame() }
                Spacer(Modifier.height(8.dp))
                SecondaryButton(L10n.t("Main Menu"), onClick = onExit)
            }
        }

        val over = state as? GameState.GameOver
        AnimatedVisibility(over != null && !(over.won && nextLevel != null), enter = fadeIn(tween(220)) + scaleIn(tween(260), initialScale = 0.92f), exit = fadeOut(tween(150))) {
            Overlay {
                val won = over?.won == true
                Text(if (won) "🎉" else "💥", fontSize = 40.sp)
                Text(resultTitle?.takeIf { won } ?: L10n.t(if (won) "You Win!" else "Game Over"), color = pal.text, fontSize = 26.sp,
                    fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Spacer(Modifier.height(6.dp))
                Text(L10n.t("Score"), color = pal.textSecondary, fontSize = 14.sp)
                Text("$finalScore", color = pal.text, fontSize = 40.sp, fontWeight = FontWeight.Black)
                if (timed) Text(L10n.f("Time: %@ · Bonus: +%d", "%02d:%02d".format(elapsed.toInt() / 60, elapsed.toInt() % 60), timeBonus), color = pal.textSecondary, fontSize = 14.sp)
                else summary()?.let { Text(it, color = pal.textSecondary, fontSize = 14.sp) }
                if (newRecord) {
                    Text(L10n.t("New High Score!"), color = pal.accent, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                }
                Spacer(Modifier.height(16.dp))
                PrimaryButton(L10n.t("Play Again")) { restartGame() }
                Spacer(Modifier.height(8.dp))
                SecondaryButton(L10n.t("Main Menu"), onClick = onExit)
            }
        }

        // A short banner between levels; the next level starts on its own.
        AnimatedVisibility(advancing, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.align(Alignment.Center)) {
            Box(Modifier.clip(RoundedCornerShape(20.dp)).background(pal.surface).padding(horizontal = 28.dp, vertical = 18.dp)) {
                Text("🎉 " + L10n.t("You Win!"), color = pal.text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun Overlay(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)).clickable(enabled = false) {},
        contentAlignment = Alignment.Center) {
        Column(
            Modifier.padding(horizontal = 32.dp).fillMaxWidth().clip(RoundedCornerShape(28.dp))
                .background(Pal.current.surface).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, content = content,
        )
    }
}

@Composable
fun StatCard(title: String, value: Int, modifier: Modifier = Modifier) {
    val pal = Pal.current
    Column(modifier.clip(RoundedCornerShape(18.dp)).background(pal.surface).padding(horizontal = 16.dp, vertical = 10.dp)) {
        Text(title, color = pal.textSecondary, fontSize = 12.sp, maxLines = 1)
        Text("$value", color = pal.text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun RoundButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    Box(Modifier.size(44.dp).clip(CircleShape).background(Pal.current.surface).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) { content() }
}

@Composable
private fun PauseGlyph(color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        repeat(2) { Box(Modifier.width(4.dp).height(16.dp).clip(RoundedCornerShape(2.dp)).background(color)) }
    }
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val pal = Pal.current
    Box(modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(26.dp)).background(pal.accent).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text, color = pal.onAccent, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
fun SecondaryButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val pal = Pal.current
    Box(modifier.fillMaxWidth().height(48.dp).clip(RoundedCornerShape(24.dp)).background(pal.surfaceHigh).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Text(text, color = pal.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
    }
}
