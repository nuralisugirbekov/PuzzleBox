package com.nurali.puzzlebox.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Stats

/** Gradient artwork tile with the game's emoji. */
@Composable
fun GameArt(id: GameId, modifier: Modifier = Modifier, emojiSize: Int = 56) {
    val tint = id.info.tint
    Box(
        modifier.clip(RoundedCornerShape(22.dp)).background(
            Brush.linearGradient(listOf(tint.copy(alpha = 0.95f), tint.copy(alpha = 0.55f), Color(0xFF1B1F2B)))
        ),
        contentAlignment = Alignment.Center,
    ) {
        Text(id.info.emoji, fontSize = emojiSize.sp)
    }
}

/** A game card; pass [Dp.Unspecified] as [width] to let the parent decide. */
@Composable
fun GameTile(id: GameId, width: Dp, onPlay: (GameId) -> Unit, modifier: Modifier = Modifier) {
    val pal = Pal.current
    val sized = if (width == Dp.Unspecified) modifier else modifier.width(width)
    val press = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val pressed by press.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.96f else 1f, spring(dampingRatio = 0.6f, stiffness = 500f), label = "press")
    Column(sized.graphicsLayer { scaleX = scale; scaleY = scale }.clickable(interactionSource = press, indication = null) { onPlay(id) }) {
        Box {
            GameArt(id, Modifier.fillMaxWidth().aspectRatio(1f))
            Box(Modifier.align(Alignment.BottomEnd).padding(8.dp)) { FavoriteButton(id) }
        }
        Spacer(Modifier.height(8.dp))
        Text(id.info.title, color = pal.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(id.info.tagline, color = pal.textSecondary, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
fun FavoriteButton(id: GameId) {
    val fav = Stats.isFavorite(id)
    Box(
        Modifier.size(34.dp).clip(RoundedCornerShape(17.dp)).background(Color.Black.copy(alpha = 0.35f))
            .clickable { Stats.toggleFavorite(id) },
        contentAlignment = Alignment.Center,
    ) {
        Icon(if (fav) Icons.Default.Favorite else Icons.Default.FavoriteBorder, null,
            tint = if (fav) Color(0xFFFF2D55) else Color.White, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier) {
    Text(text, color = Pal.current.text, fontSize = 22.sp, fontWeight = FontWeight.Bold,
        modifier = modifier.padding(horizontal = 20.dp, vertical = 8.dp))
}

@Composable
fun GameShelf(title: String, games: List<GameId>, onPlay: (GameId) -> Unit) {
    if (games.isEmpty()) return
    SectionTitle(title)
    LazyRow(contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        items(games) { GameTile(it, 150.dp, onPlay) }
    }
    Spacer(Modifier.height(18.dp))
}

@Composable
fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val pal = Pal.current
    Box(modifier.clip(RoundedCornerShape(18.dp)).background(pal.surface).border(1.dp, pal.stroke, RoundedCornerShape(18.dp))) { content() }
}

@Composable
fun StatRow(label: String, value: String) {
    val pal = Pal.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = pal.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(value, color = pal.textSecondary, fontSize = 16.sp)
    }
}
