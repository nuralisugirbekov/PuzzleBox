package com.nurali.puzzlebox

import android.app.Application
import android.content.Context
import android.os.Bundle
import androidx.compose.runtime.*
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.AndroidViewModel
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import org.json.JSONObject
import java.util.Locale

object Palette {
    val background = Color(0xFF0C0E14)
    val surface = Color(0xFF161A25)
    val raised = Color(0xFF212735)
    val neon = Color(0xFFC6F31D)
    val secondary = Color(0xFF9E9E9E)
    val colors = listOf(Color(0xFFF06B87), Color(0xFF648BFF), Color(0xFF58CE9B), Color(0xFFFFD45B), Color(0xFFAA82ED), Color(0xFF54D5DE))
}

enum class Game(val title: String, val category: String, val difficulty: String, val symbol: String, val tagline: String) {
    match3("Three in a Row", "Casual", "Easy", "◆", "Swap gems, chase cascades"),
    sudoku("Mini Sudoku", "Logic", "Medium", "▦", "6×6 logic, quick rounds"),
    snake("Snake", "Arcade", "Medium", "〰", "Eat, grow, don't crash"),
    blockBlast("Block Blast", "Logic", "Easy", "▣", "Fill lines, clear the board"),
    waterSort("Water Sort", "Logic", "Medium", "◒", "Pour and sort the colors"),
    solitaire("Solitaire", "Cards", "Medium", "♦", "Classic Klondike patience"),
    spiderSolitaire("Spider", "Cards", "Hard", "♣", "Build runs, clear the table"),
    freecell("FreeCell", "Cards", "Hard", "♥", "Every deal is winnable"),
    spades("Spades", "Cards", "Medium", "♠", "Bid, trump, take tricks"),
    minesweeper("Minesweeper", "Logic", "Medium", "⚑", "Flag the mines, clear the field"),
    checkmate("Checkmate", "Logic", "Hard", "♔", "Mate in 1"),
    dominoes("Dominoes", "Cards", "Easy", "⚄", "Match pips, beat the bot");
    val timedCards get() = this in listOf(solitaire, spiderSolitaire, freecell, spades)
    val tint get() = Palette.colors[ordinal % Palette.colors.size]
}

enum class Phase { PLAYING, PAUSED, WON, LOST }
abstract class Engine {
    var revision by mutableIntStateOf(0)
    var phase = Phase.PLAYING
    open var score = 0
    var message = ""
    var messageArgs: List<Any> = emptyList()
    var error = false
    fun say(key: String, vararg args: Any) { message = key; messageArgs = args.toList() }
    fun changed() { revision++ }
    open fun tick(ms: Long) {}
    open fun undo() {}
    open val canUndo get() = false
    abstract fun restart()
    fun reset() { phase = Phase.PLAYING; score = 0; message = ""; messageArgs = emptyList(); error = false }
}

class Strings(context: Context, val language: String) {
    private val all = JSONObject(context.assets.open("translations.json").bufferedReader().use { it.readText() })
    private val strings = all.optJSONObject(language) ?: all.getJSONObject("en")
    fun text(key: String, vararg args: Any): String {
        val value = strings.optString(key, key).replace("%@", "%s")
        return if (args.isEmpty()) value else String.format(Locale.forLanguageTag(language), value, *args)
    }
}
val LocalStrings = staticCompositionLocalOf<Strings> { error("Strings not provided") }
val languages = linkedMapOf("ru" to "Русский", "kk" to "Қазақша", "en" to "English", "fr" to "Français", "hi" to "हिन्दी", "de" to "Deutsch", "zh-Hans" to "简体中文", "ko" to "한국어")

class Analytics(context: Context) {
    private val client = if (FirebaseApp.getApps(context).isNotEmpty()) FirebaseAnalytics.getInstance(context) else null
    private var languageCode = "not_selected"
    fun event(name: String, values: Map<String, Any> = emptyMap()) {
        client?.logEvent(name, Bundle().apply {
            putString("app_language", languageCode)
            for ((key, value) in values) when (value) {
                is Int -> putLong(key, value.toLong())
                is Long -> putLong(key, value)
                is Double -> putDouble(key, value)
                else -> putString(key, value.toString())
            }
        })
    }
    fun language(code: String) { languageCode = code.ifEmpty { "not_selected" }; client?.setUserProperty("app_language", code.takeIf { it.isNotEmpty() }) }
    fun screen(name: String) = event("screen_view", mapOf("screen_name" to name, "screen_class" to name))
}

/** Activity ViewModel retains rounds across rotation; foreground time only. */
class AppModel(application: Application) : AndroidViewModel(application) {
    private val prefs = application.getSharedPreferences("puzzlebox", Context.MODE_PRIVATE)
    val analytics = Analytics(application)
    var language by mutableStateOf(prefs.getString("language", "") ?: "")
    var game by mutableStateOf<Game?>(null)
    var engine by mutableStateOf<Engine?>(null)
    var elapsed by mutableLongStateOf(0)
    var finalScore by mutableStateOf<Int?>(null)
    var newRecord by mutableStateOf(false)
    var statsRevision by mutableIntStateOf(0)
    private var ended = true
    val totalPlayed get() = Game.entries.sumOf { prefs.getInt("played_${it.name}", 0) }
    fun best(id: Game) = prefs.getInt("best_${id.name}", 0)
    init { analytics.language(language) }
    fun chooseLanguage(code: String) {
        if (code == language) return
        val first = language.isEmpty()
        val previous = language.ifEmpty { "not_selected" }
        language = code
        prefs.edit().putString("language", code).apply()
        analytics.language(code)
        analytics.event("language_selected", mapOf("app_language" to code, "previous_language" to previous, "selection_source" to if (first) "onboarding" else "settings"))
    }
    private fun context(id: Game) = mapOf<String, Any>("game_id" to id.name, "level_name" to id.name,
        "game_category" to id.category.lowercase(), "difficulty" to id.difficulty.lowercase())
    fun open(id: Game, source: String = "grid") {
        close()
        game = id
        engine = when (id) {
            Game.checkmate -> ChessEngine(getApplication())
            Game.solitaire, Game.freecell, Game.spiderSolitaire -> PatienceEngine(id)
            Game.spades -> SpadesEngine()
            Game.dominoes -> DominoEngine()
            Game.match3 -> MatchEngine()
            Game.sudoku -> SudokuEngine()
            Game.minesweeper -> MinesEngine()
            Game.snake -> SnakeEngine()
            Game.waterSort -> WaterEngine()
            Game.blockBlast -> BlockEngine()
        }
        analytics.event("select_content", mapOf("content_type" to "game", "item_id" to id.name, "selection_source" to source))
        analytics.screen("game_${id.name}")
        start()
    }
    private fun start() {
        elapsed = 0; finalScore = null; newRecord = false; ended = false
        game?.let { analytics.event("level_start", context(it)) }
    }
    fun pause() {
        engine?.let { if (it.phase == Phase.PLAYING) { it.phase = Phase.PAUSED; it.changed(); log("game_pause") } }
    }
    fun resume() {
        engine?.let { if (it.phase == Phase.PAUSED) { it.phase = Phase.PLAYING; it.changed(); log("game_resume") } }
    }
    private fun log(name: String) { game?.let { analytics.event(name, context(it) + ("score" to (engine?.score ?: 0))) } }
    fun tick(ms: Long) {
        val e = engine ?: return
        if (e.phase == Phase.PLAYING) {
            elapsed += ms
            e.tick(ms)
        }
        if (!ended && e.phase in listOf(Phase.WON, Phase.LOST)) {
            val id = game ?: return
            val bonus = if (id.timedCards && e.phase == Phase.WON) bonus() else 0
            val total = e.score + bonus
            finalScore = total
            newRecord = total > best(id)
            prefs.edit().putInt("played_${id.name}", prefs.getInt("played_${id.name}", 0) + 1)
                .putInt("best_${id.name}", maxOf(best(id), total)).apply()
            statsRevision++
            finish("completed", bonus)
        }
    }
    fun bonus() = (1000.0 / (1 + elapsed / 300000.0)).toInt()
    private fun finish(reason: String, bonus: Int = 0) {
        if (ended) return
        val id = game ?: return
        val points = finalScore ?: engine?.score ?: 0
        analytics.event("level_end", context(id) + mapOf("score" to points, "end_reason" to reason,
            "duration_seconds" to elapsed / 1000, "success" to if (engine?.phase == Phase.WON) 1 else 0,
            "new_high_score" to if (newRecord) 1 else 0, "time_bonus" to bonus))
        if (reason == "completed") {
            analytics.event("post_score", mapOf("game_id" to id.name, "score" to points))
            if (newRecord) analytics.event("new_high_score", mapOf("game_id" to id.name, "score" to points))
        }
        ended = true
    }
    fun restart() { log("game_restart"); finish("restart"); engine?.restart(); start() }
    fun close() { finish("exit"); engine = null; game = null }
}
