package com.nurali.puzzlebox.core

import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import com.google.firebase.analytics.FirebaseAnalytics

/** Firebase Analytics with the same event names and parameters as the iOS app. */
object AppAnalytics {
    private var analytics: FirebaseAnalytics? = null

    fun init(context: Context) {
        analytics = runCatching { FirebaseAnalytics.getInstance(context.applicationContext) }.getOrNull()
        updateLanguageProperty()
    }

    fun log(event: String, vararg params: Pair<String, Any>) {
        val bundle = Bundle()
        for ((k, v) in params) when (v) { is Int -> bundle.putLong(k, v.toLong()); is Long -> bundle.putLong(k, v); is Boolean -> bundle.putLong(k, if (v) 1 else 0); else -> bundle.putString(k, v.toString()) }
        if (!bundle.containsKey("app_language")) bundle.putString("app_language", Settings.languageCode.ifEmpty { "not_selected" })
        analytics?.logEvent(event, bundle)
    }

    fun screen(name: String) = log(FirebaseAnalytics.Event.SCREEN_VIEW, FirebaseAnalytics.Param.SCREEN_NAME to name, FirebaseAnalytics.Param.SCREEN_CLASS to name)

    fun updateLanguageProperty() { analytics?.setUserProperty("app_language", Settings.languageCode.ifEmpty { null }) }

    fun selectLanguage(code: String) {
        val previous = Settings.languageCode.ifEmpty { null }
        if (previous == code) return
        analytics?.setUserProperty("app_language", code)
        log("language_selected", "app_language" to code, "previous_language" to (previous ?: "not_selected"), "selection_source" to if (previous == null) "onboarding" else "settings")
    }

    fun selectGame(id: GameId, source: String) =
        log(FirebaseAnalytics.Event.SELECT_CONTENT, FirebaseAnalytics.Param.CONTENT_TYPE to "game", FirebaseAnalytics.Param.ITEM_ID to id.raw, "selection_source" to source)
}

/** One start/end pair per round; duration excludes pauses and time in the background. */
class GameRoundAnalytics {
    private var game: GameId? = null
    private var ended = true
    private var elapsed = 0L
    private var activeSince: Long? = null

    private fun now() = SystemClock.elapsedRealtime()

    fun start(game: GameId, active: Boolean) {
        if (!ended) return
        this.game = game; ended = false; elapsed = 0; activeSince = if (active) now() else null
        event(FirebaseAnalytics.Event.LEVEL_START)
    }

    fun setActive(active: Boolean) {
        if (ended) return
        if (active) { if (activeSince == null) activeSince = now() }
        else activeSince?.let { elapsed += now() - it; activeSince = null }
    }

    fun event(name: String, score: Int? = null) {
        val g = game ?: return
        if (ended && name != FirebaseAnalytics.Event.LEVEL_START) return
        val extra = if (score != null) arrayOf(FirebaseAnalytics.Param.SCORE to score as Any) else emptyArray()
        AppAnalytics.log(name, *context(g), *extra)
    }

    fun finish(score: Int, reason: String, won: Boolean = false, newRecord: Boolean = false, timeBonus: Int? = null) {
        val g = game ?: return
        if (ended) return
        setActive(false); ended = true
        val p = ArrayList<Pair<String, Any>>(context(g).toList())
        p += FirebaseAnalytics.Param.SCORE to score; p += FirebaseAnalytics.Param.SUCCESS to won; p += "end_reason" to reason
        p += "duration_seconds" to (elapsed / 1000).toInt(); p += "new_high_score" to newRecord
        timeBonus?.let { p += "time_bonus" to it }
        AppAnalytics.log(FirebaseAnalytics.Event.LEVEL_END, *p.toTypedArray())
        if (reason == "completed") {
            AppAnalytics.log(FirebaseAnalytics.Event.POST_SCORE, FirebaseAnalytics.Param.SCORE to score, "game_id" to g.raw)
            if (newRecord) AppAnalytics.log("new_high_score", "game_id" to g.raw, FirebaseAnalytics.Param.SCORE to score)
        }
    }

    private fun context(g: GameId): Array<Pair<String, Any>> = arrayOf(
        "game_id" to g.raw, FirebaseAnalytics.Param.LEVEL_NAME to g.raw,
        "game_category" to g.info.category.name.lowercase(), "difficulty" to g.info.difficulty.name.lowercase())
}
