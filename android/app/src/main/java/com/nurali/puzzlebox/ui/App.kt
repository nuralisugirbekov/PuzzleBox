package com.nurali.puzzlebox.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Stats
import com.nurali.puzzlebox.games.GameHost

private enum class Tab(val titleKey: String, val glyph: String) {
    Home("Home", "🏠"), Discover("Discover", "🌐"), Rating("Rating", "🏁"), Games("Games", "🎮"), Search("Search", "🔍")
}

@Composable
fun OinaApp(initialGame: String? = null) {
    OinaTheme {
        val pal = Pal.current
        var tab by rememberSaveable { mutableStateOf(Tab.Home) }
        var activeRaw by rememberSaveable { mutableStateOf<String?>(initialGame?.takeIf { GameId.fromRaw(it) != null }) }
        var showSettings by rememberSaveable { mutableStateOf(false) }
        val active = activeRaw?.let { GameId.fromRaw(it) }

        val play: (GameId) -> Unit = { id ->
            Haptics.tap()
            Stats.markOpened(id)
            com.nurali.puzzlebox.core.AppAnalytics.selectGame(id, "home")
            activeRaw = id.raw
        }

        BackHandler(enabled = showSettings && active == null) { showSettings = false }
        // Fade between the catalogue, settings and a running game.
        Crossfade(targetState = active?.raw ?: if (showSettings) "settings" else "main", animationSpec = tween(220), label = "screen") { screen ->
            when {
                screen == "settings" -> Box(Modifier.fillMaxSize().background(pal.background).statusBarsPadding().navigationBarsPadding()) {
                    SettingsScreen(onClose = { showSettings = false })
                }
                screen != "main" -> GameId.fromRaw(screen)?.let { GameHost(it, onExit = { activeRaw = null }) }
                else -> MainShell(tab, { tab = it }, play) { showSettings = true }
            }
        }
    }
}

@Composable
private fun MainShell(tab: Tab, onTab: (Tab) -> Unit, play: (GameId) -> Unit, onSettings: () -> Unit) {
    val pal = Pal.current
    run {
        Column(Modifier.fillMaxSize().background(pal.background).statusBarsPadding()) {
            Box(Modifier.weight(1f)) {
                Crossfade(targetState = tab, animationSpec = tween(160), label = "tab") { t ->
                    when (t) {
                        Tab.Home -> HomeScreen(play, onSettings = onSettings)
                        Tab.Discover -> DiscoverScreen(play)
                        Tab.Rating -> RatingScreen(play)
                        Tab.Games -> MyGamesScreen(play, onDiscover = { onTab(Tab.Discover) })
                        Tab.Search -> SearchScreen(play)
                    }
                }
            }
            NavigationBar(containerColor = pal.surface, modifier = Modifier.navigationBarsPadding()) {
                Tab.entries.forEach { t ->
                    NavigationBarItem(
                        selected = tab == t, onClick = { onTab(t) },
                        icon = { Text(t.glyph, fontSize = 20.sp) },
                        label = { Text(L10n.t(t.titleKey), fontSize = 11.sp, maxLines = 1) },
                        colors = NavigationBarItemDefaults.colors(
                            selectedTextColor = pal.accent, unselectedTextColor = pal.textSecondary,
                            indicatorColor = pal.surfaceHigh),
                    )
                }
            }
        }
    }
}
