package com.nurali.puzzlebox.core

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject

/** Local player statistics: records, rounds played, favourites and recently opened games. */
object Stats {
    private var highScores by mutableStateOf(loadInts("puzzlebox.highScores"))
    private var played by mutableStateOf(loadInts("puzzlebox.gamesPlayed"))
    private var favorites by mutableStateOf(loadSet("puzzlebox.favorites"))
    private var lastOpened by mutableStateOf(loadLongs("puzzlebox.lastOpened"))

    // The maps above are read before Settings.init in static init order, so reload explicitly.
    fun init() {
        highScores = loadInts("puzzlebox.highScores")
        played = loadInts("puzzlebox.gamesPlayed")
        favorites = loadSet("puzzlebox.favorites")
        lastOpened = loadLongs("puzzlebox.lastOpened")
    }

    fun highScore(id: GameId) = highScores[id.raw] ?: 0
    fun gamesPlayed(id: GameId) = played[id.raw] ?: 0
    val totalPlayed: Int get() = played.values.sum()
    val gamesTried: Int get() = played.count { it.value > 0 }

    fun isFavorite(id: GameId) = id.raw in favorites
    val favoriteGames: List<GameId> get() = GameId.visible.filter { isFavorite(it) }

    fun toggleFavorite(id: GameId) {
        AppAnalytics.log(if (id.raw in favorites) "favorite_removed" else "favorite_added", "game_id" to id.raw)
        favorites = if (id.raw in favorites) favorites - id.raw else favorites + id.raw
        Settings.prefs.edit().putStringSet("puzzlebox.favorites", favorites).apply()
    }

    /** Games the player has opened, most recent first. */
    val recentGames: List<GameId>
        get() = GameId.visible.filter { lastOpened[it.raw] != null }.sortedByDescending { lastOpened[it.raw] }

    fun markOpened(id: GameId) {
        lastOpened = lastOpened + (id.raw to System.currentTimeMillis())
        Settings.prefs.edit().putString("puzzlebox.lastOpened", JSONObject(lastOpened as Map<*, *>).toString()).apply()
    }

    /** Records a finished round. Returns true when [score] set a new high score. */
    fun record(id: GameId, score: Int): Boolean {
        played = played + (id.raw to gamesPlayed(id) + 1)
        val isNewHigh = score > highScore(id)
        if (isNewHigh) highScores = highScores + (id.raw to score)
        Settings.prefs.edit()
            .putString("puzzlebox.gamesPlayed", JSONObject(played as Map<*, *>).toString())
            .putString("puzzlebox.highScores", JSONObject(highScores as Map<*, *>).toString())
            .apply()
        return isNewHigh
    }

    private fun loadInts(key: String): Map<String, Int> = runCatching {
        val o = JSONObject(Settings.prefs.getString(key, "{}") ?: "{}")
        o.keys().asSequence().associateWith { o.getInt(it) }
    }.getOrDefault(emptyMap())

    private fun loadLongs(key: String): Map<String, Long> = runCatching {
        val o = JSONObject(Settings.prefs.getString(key, "{}") ?: "{}")
        o.keys().asSequence().associateWith { o.getLong(it) }
    }.getOrDefault(emptyMap())

    private fun loadSet(key: String): Set<String> = runCatching {
        Settings.prefs.getStringSet(key, emptySet())?.toSet() ?: emptySet()
    }.getOrDefault(emptySet())
}
