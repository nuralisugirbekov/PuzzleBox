package com.nurali.puzzlebox.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.AppLanguage
import com.nurali.puzzlebox.core.AppTheme
import com.nurali.puzzlebox.core.Difficulty
import com.nurali.puzzlebox.core.GameCategory
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Stats
import java.time.LocalDate

@Composable
private fun ScreenHeader(title: String, trailing: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Pal.current.text, fontSize = 32.sp, fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
        trailing()
    }
}

@Composable
fun HomeScreen(onPlay: (GameId) -> Unit, onSettings: () -> Unit) {
    val pal = Pal.current
    val visible = GameId.visible
    val daily = visible[LocalDate.now().toEpochDay().toInt().mod(visible.size)]
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenHeader("Oina Games") {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClick = onSettings), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Settings, L10n.t("Settings"), tint = pal.text)
            }
        }
        // Game of the day.
        SectionTitle(L10n.t("Game of the Day"))
        Box(Modifier.padding(horizontal = 20.dp).fillMaxWidth().aspectRatio(1.6f).clip(RoundedCornerShape(26.dp)).clickable { onPlay(daily) }) {
            GameArt(daily, Modifier.fillMaxSize(), emojiSize = 90)
            Column(Modifier.align(Alignment.BottomStart).fillMaxWidth()
                .background(Brush.verticalGradient(listOf(androidx.compose.ui.graphics.Color.Transparent, androidx.compose.ui.graphics.Color(0xAA000000))))
                .padding(16.dp)) {
                Text(daily.info.title, color = androidx.compose.ui.graphics.Color.White, fontSize = 24.sp, fontWeight = FontWeight.Black)
                Text(daily.info.tagline, color = androidx.compose.ui.graphics.Color(0xCCFFFFFF), fontSize = 14.sp, maxLines = 2)
            }
        }
        Spacer(Modifier.height(18.dp))
        GameShelf(L10n.t("Recently Played"), Stats.recentGames, onPlay)
        GameShelf(L10n.t("Top picks for you"), visible.filter { it != daily }, onPlay)
        GameShelf(L10n.t("Quick and Easy"), visible.filter { it.info.difficulty == Difficulty.Easy || it.info.category == GameCategory.Reaction }, onPlay)
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun DiscoverScreen(onPlay: (GameId) -> Unit) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenHeader(L10n.t("Discover"))
        for (category in GameCategory.entries) {
            GameShelf(category.title, GameId.visible.filter { it.info.category == category }, onPlay)
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun RatingScreen(onPlay: (GameId) -> Unit) {
    val pal = Pal.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        ScreenHeader(L10n.t("Rating"))
        Row(Modifier.padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Card(Modifier.weight(1f)) { Column(Modifier.padding(16.dp)) {
                Text(L10n.t("Games played"), color = pal.textSecondary, fontSize = 13.sp)
                Text("${Stats.totalPlayed}", color = pal.text, fontSize = 30.sp, fontWeight = FontWeight.Black)
            } }
            Card(Modifier.weight(1f)) { Column(Modifier.padding(16.dp)) {
                Text(L10n.t("Games tried"), color = pal.textSecondary, fontSize = 13.sp)
                Text("${Stats.gamesTried}", color = pal.text, fontSize = 30.sp, fontWeight = FontWeight.Black)
            } }
        }
        SectionTitle(L10n.t("Your Records"))
        Card(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            Column {
                GameId.visible.sortedByDescending { Stats.highScore(it) }.forEach { id ->
                    Row(Modifier.fillMaxWidth().clickable { onPlay(id) }.padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        GameArt(id, Modifier.size(44.dp), emojiSize = 22)
                        Column(Modifier.weight(1f).padding(start = 12.dp)) {
                            Text(id.info.title, color = pal.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                            Text(L10n.f("Played: %d", Stats.gamesPlayed(id)), color = pal.textSecondary, fontSize = 12.sp)
                        }
                        Text("${Stats.highScore(id)}", color = pal.accent, fontSize = 20.sp, fontWeight = FontWeight.Black)
                    }
                }
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
fun MyGamesScreen(onPlay: (GameId) -> Unit, onDiscover: () -> Unit) {
    val pal = Pal.current
    val favorites = Stats.favoriteGames
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(L10n.t("My Games"))
        if (favorites.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Text("❤️", fontSize = 48.sp)
                Text(L10n.t("No Favorites Yet"), color = pal.text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(L10n.t("Tap the heart on any game to keep it here."), color = pal.textSecondary, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                Spacer(Modifier.height(18.dp))
                PrimaryChip(L10n.t("Discover Games"), onDiscover)
            }
        } else {
            GameGrid(favorites, onPlay)
        }
    }
}

@Composable
fun SearchScreen(onPlay: (GameId) -> Unit) {
    val pal = Pal.current
    var query by remember { mutableStateOf("") }
    val results = GameId.visible.filter {
        query.isBlank() || it.info.title.contains(query, true) || it.info.tagline.contains(query, true) ||
            it.info.titleKey.contains(query, true)
    }
    Column(Modifier.fillMaxSize()) {
        ScreenHeader(L10n.t("Search"))
        OutlinedTextField(
            value = query, onValueChange = { query = it }, singleLine = true,
            placeholder = { Text(L10n.t("Search games"), color = pal.textSecondary) },
            shape = RoundedCornerShape(16.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = pal.text, unfocusedTextColor = pal.text, focusedBorderColor = pal.accent,
                unfocusedBorderColor = pal.stroke, cursorColor = pal.accent,
                focusedContainerColor = pal.surface, unfocusedContainerColor = pal.surface),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        )
        Spacer(Modifier.height(12.dp))
        if (results.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text("🔍", fontSize = 44.sp)
                Text(L10n.t("No games found"), color = pal.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Text(L10n.t("Try another search."), color = pal.textSecondary)
            }
        } else {
            GameGrid(results, onPlay)
        }
    }
}

@Composable
private fun GameGrid(games: List<GameId>, onPlay: (GameId) -> Unit) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 24.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        items(games) { GameTile(it, androidx.compose.ui.unit.Dp.Unspecified, onPlay, Modifier.fillMaxWidth()) }
    }
}

@Composable
private fun PrimaryChip(text: String, onClick: () -> Unit) {
    val pal = Pal.current
    Box(Modifier.clip(RoundedCornerShape(24.dp)).background(pal.accent).clickable(onClick = onClick).padding(horizontal = 24.dp, vertical = 12.dp)) {
        Text(text, color = pal.onAccent, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun SettingsScreen(onClose: () -> Unit) {
    val pal = Pal.current
    Column(Modifier.fillMaxSize().background(pal.background).verticalScroll(rememberScrollState())) {
        ScreenHeader(L10n.t("Settings")) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClick = onClose), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.Close, L10n.t("Close"), tint = pal.text)
            }
        }
        SectionTitle(L10n.t("Language"))
        Card(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            Column {
                AppLanguage.entries.forEach { lang ->
                    Row(Modifier.fillMaxWidth().clickable { L10n.changeLanguage(lang) }.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(lang.nativeName, color = pal.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        if (L10n.language == lang) Icon(Icons.Default.Check, null, tint = pal.accent)
                    }
                }
            }
        }
        SectionTitle(L10n.t("Appearance"))
        Card(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            Column {
                AppTheme.entries.forEach { theme ->
                    Row(Modifier.fillMaxWidth().clickable { Settings.chooseTheme(theme) }.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(L10n.t(theme.label), color = pal.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                        if (Settings.theme == theme) Icon(Icons.Default.Check, null, tint = pal.accent)
                    }
                }
            }
        }
        SectionTitle(L10n.t("Haptics"))
        Card(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(L10n.t("Haptics"), color = pal.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
                Switch(checked = Settings.hapticsEnabled, onCheckedChange = { Settings.setHaptics(it) })
            }
        }
        SectionTitle(L10n.t("Statistics"))
        Card(Modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
            Column {
                StatRow(L10n.t("Games played"), "${Stats.totalPlayed}")
                StatRow(L10n.t("Games tried"), "${Stats.gamesTried}")
            }
        }
        Spacer(Modifier.height(32.dp))
    }
}
