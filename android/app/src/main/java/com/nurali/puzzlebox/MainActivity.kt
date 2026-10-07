package com.nurali.puzzlebox

import android.os.Bundle
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { PuzzleBoxApp() }
    }
}

@Composable
fun PuzzleBoxApp(model: AppModel = viewModel()) {
    val app = model.getApplication<android.app.Application>()
    val code = model.language.ifEmpty { languages.keys.firstOrNull { Locale.getDefault().toLanguageTag().startsWith(it.substringBefore('-')) } ?: "en" }
    val strings = remember(code) { Strings(app, code) }
    CompositionLocalProvider(LocalStrings provides strings) {
        MaterialTheme(colorScheme = darkColorScheme(primary = Palette.neon, onPrimary = Color.Black,
            background = Palette.background, surface = Palette.surface, onSurface = Color.White,
            secondary = Palette.neon), typography = Typography()) {
            Surface(Modifier.fillMaxSize(), color = Palette.background) {
                Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                    if (model.language.isEmpty()) LanguagePicker(code, { model.chooseLanguage(it) })
                    else if (model.engine != null) GameScreen(model)
                    else MainMenu(model)
                }
            }
        }
    }
}

@Composable
fun Action(key: String, modifier: Modifier = Modifier, enabled: Boolean = true, action: () -> Unit) {
    Button(onClick = action, modifier = modifier, enabled = enabled, shape = RoundedCornerShape(14.dp)) {
        Text(LocalStrings.current.text(key), fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun LanguagePicker(initial: String, onConfirm: (String) -> Unit, onDismiss: (() -> Unit)? = null) {
    var selected by rememberSaveable { mutableStateOf(initial) }
    var expanded by remember { mutableStateOf(false) }
    val app = androidx.compose.ui.platform.LocalContext.current
    val t = remember(selected) { Strings(app, selected) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(28.dp), verticalArrangement = Arrangement.Center) {
        Text("Puzzle Box", fontSize = 38.sp, fontWeight = FontWeight.ExtraBold, color = Palette.neon)
        Spacer(Modifier.height(16.dp))
        Text(t.text("Make yourself at home."), fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Text(t.text("Choose your language"), color = Palette.secondary, modifier = Modifier.padding(vertical = 16.dp))
        Box {
            OutlinedButton({ expanded = true }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                Text(languages.getValue(selected), Modifier.weight(1f), fontSize = 20.sp); Text("⌄")
            }
            DropdownMenu(expanded, { expanded = false }) {
                languages.forEach { (code, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { selected = code; expanded = false }) }
            }
        }
        Text(t.text("You can change it later in the main menu."), color = Palette.secondary, modifier = Modifier.padding(vertical = 20.dp))
        Button({ onConfirm(selected) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) { Text(t.text("Continue")) }
        if (onDismiss != null) TextButton(onDismiss, Modifier.align(Alignment.CenterHorizontally)) { Text(t.text("Main Menu")) }
    }
}

@Composable
fun MainMenu(model: AppModel) {
    val t = LocalStrings.current
    var languageSheet by rememberSaveable { mutableStateOf(false) }
    var search by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("All") }
    val revision = model.statsRevision
    LaunchedEffect(Unit) { model.analytics.screen("main_menu") }
    if (languageSheet) {
        BackHandler { languageSheet = false }
        LanguagePicker(model.language, { model.chooseLanguage(it); languageSheet = false }, { languageSheet = false }); return
    }
    val filtered = Game.entries.filter { (category == "All" || category == it.category) && t.text(it.title).contains(search, ignoreCase = true) }
    LazyVerticalGrid(columns = GridCells.Adaptive(155.dp), contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item(span = { GridItemSpan(maxLineSpan) }) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Row { Text("Puzzle ", fontSize = 34.sp, fontWeight = FontWeight.ExtraBold); Text("Box", fontSize = 34.sp, fontWeight = FontWeight.ExtraBold, color = Palette.neon) }
                    Text(t.text("Pick a game and start winning"), color = Palette.secondary, fontSize = 14.sp)
                }
                TextButton({ languageSheet = true }) { Text("◎", fontSize = 28.sp, modifier = Modifier.semanticsLabel(t.text("Language"))) }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            Surface(shape = RoundedCornerShape(20.dp), color = Palette.surface, border = BorderStroke(1.dp, Palette.neon.copy(alpha = .25f))) {
                Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text("${model.totalPlayed}", fontSize = 32.sp, color = Palette.neon, fontWeight = FontWeight.Bold); Text(t.text("puzzles played"), fontSize = 13.sp) }
                    Action("Random Game") { model.open(Game.entries.random(), "random") }
                }
            }
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), placeholder = { Text(t.text("Search games")) }, singleLine = true, shape = RoundedCornerShape(14.dp))
        }
        item(span = { GridItemSpan(maxLineSpan) }) {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("All", "Logic", "Casual", "Arcade", "Cards").forEach { name ->
                    FilterChip(category == name, {
                        category = name; model.analytics.event("category_selected", mapOf("game_category" to name.lowercase()))
                    }, label = { Text(t.text(name)) })
                }
            }
        }
        if (filtered.isEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { Text(t.text("No games found")) }
        items(filtered, key = { it.name }) { game ->
            Surface(onClick = { model.open(game, if (search.isEmpty()) "grid" else "search") }, shape = RoundedCornerShape(18.dp), color = Palette.surface) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                    Box(Modifier.fillMaxWidth().height(88.dp).background(game.tint.copy(alpha = .65f), RoundedCornerShape(14.dp)), contentAlignment = Alignment.Center) {
                        Text(game.symbol, fontSize = 40.sp, color = Color.White)
                    }
                    Text(t.text(game.title), fontWeight = FontWeight.Bold, minLines = 2, maxLines = 2)
                    Text(t.text(game.tagline), color = Palette.secondary, fontSize = 12.sp, minLines = 2, maxLines = 2)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(t.text(game.difficulty), fontSize = 11.sp, color = game.tint)
                        Text("★ ${model.best(game)}", fontSize = 12.sp, color = Color(0xFFFFD45B))
                    }
                }
            }
        }
    }
}

@Composable
fun GameScreen(model: AppModel) {
    val engine = model.engine ?: return
    val game = model.game ?: return
    val revision = engine.revision // Engine changes are published as a single board revision.
    val t = LocalStrings.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle.currentStateAsState().value
    val foreground = lifecycle == Lifecycle.State.RESUMED
    LaunchedEffect(engine, foreground) {
        if (!foreground) { model.pause(); return@LaunchedEffect }
        var last = SystemClock.elapsedRealtime()
        while (true) {
            delay(16)
            val now = SystemClock.elapsedRealtime()
            model.tick((now - last).coerceAtLeast(0)); last = now
        }
    }
    BackHandler { if (engine.phase == Phase.PLAYING) model.pause() else { model.close(); model.analytics.screen("main_menu") } }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton({ model.pause() }) { Text("Ⅱ", fontSize = 24.sp, modifier = Modifier.semanticsLabel(t.text("Paused"))) }
            Text(t.text(game.title), Modifier.weight(1f), fontWeight = FontWeight.Bold, fontSize = 19.sp)
            Column(horizontalAlignment = Alignment.End) { Text(t.text("Score"), fontSize = 11.sp, color = Palette.secondary); Text("${model.finalScore ?: engine.score}", fontSize = 22.sp, color = Palette.neon, fontWeight = FontWeight.Bold) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (game.timedCards) {
                val seconds = model.elapsed / 1000
                Text(t.text("Time: %@ · Bonus: +%d", "%02d:%02d".format(seconds / 60, seconds % 60), model.bonus()), color = Palette.neon, fontSize = 13.sp)
            }
            if (engine.message.isNotEmpty()) Surface(color = if (engine.error) Color.Red.copy(alpha = .12f) else Color.Transparent, shape = RoundedCornerShape(12.dp)) {
                Text(t.text(engine.message, *engine.messageArgs.toTypedArray()), Modifier.padding(10.dp), color = if (engine.error) Color(0xFFFF7272) else Palette.secondary)
            }
            GameBody(engine)
        }
    }
    if (engine.phase != Phase.PLAYING) {
        val paused = engine.phase == Phase.PAUSED
        AlertDialog(onDismissRequest = { if (paused) model.resume() },
            title = { Text(t.text(if (paused) "Paused" else if (engine.phase == Phase.WON) "You Win!" else "Game Over")) },
            text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (!paused) {
                    Text("${t.text("Score")}: ${model.finalScore ?: engine.score}")
                    if (model.newRecord) Text(t.text("New High Score!"), color = Palette.neon)
                    if (game.timedCards && engine.phase == Phase.WON) Text(t.text("Win bonus: +%d", model.bonus()))
                }
                if (paused) Action("Resume", Modifier.fillMaxWidth()) { model.resume() }
                Action(if (paused) "Restart" else "Play Again", Modifier.fillMaxWidth()) { model.restart() }
            } },
            confirmButton = { TextButton({ model.close(); model.analytics.screen("main_menu") }) { Text(t.text("Main Menu")) } })
    }
}
