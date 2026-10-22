package com.nurali.puzzlebox.games.kit

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.ui.Pal
import java.util.concurrent.atomic.AtomicInteger

enum class Suit(val symbol: String, val isRed: Boolean) {
    Spades("♠", false), Hearts("♥", true), Diamonds("♦", true), Clubs("♣", false)
}

private val nextId = AtomicInteger(1)

/** rank 1 = ace … 13 = king. */
data class Card(val id: Int, val suit: Suit, val rank: Int, val faceUp: Boolean = true) {
    val isRed get() = suit.isRed
    val rankLabel get() = when (rank) { 1 -> "A"; 11 -> "J"; 12 -> "Q"; 13 -> "K"; else -> "$rank" }

    companion object {
        fun make(suit: Suit, rank: Int, faceUp: Boolean = true) = Card(nextId.getAndIncrement(), suit, rank, faceUp)
        fun deck(): List<Card> = Suit.entries.flatMap { suit -> (1..13).map { make(suit, it) } }
    }
}

object CardColors {
    val red = Color(0xFFDB0A17)
    val black = Color(0xFF141417)
    val glow = Color(0xFFDB9E3D)
}

const val CARD_RATIO = 72f / 50f

/** A 50×72 card scaled to [width]: rank and a small pip top-left, a large pip below the centre. */
@Composable
fun CardView(card: Card, width: Dp, highlighted: Boolean = false, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val h = width * CARD_RATIO
    val radius = width * 4f / 50f
    val shape = RoundedCornerShape(radius)
    val ink = if (card.isRed) CardColors.red else CardColors.black
    val s = width.value / 50f
    val click = if (onClick != null) Modifier.clickable(remember { MutableInteractionSource() }, null) { onClick() } else Modifier
    Box(modifier.size(width, h).clip(shape)
        .background(if (card.faceUp) Color.White else Pal.current.accent)
        .border(if (highlighted) 2.dp else 1.dp, if (highlighted) CardColors.glow else Color.Black, shape)
        .then(click)) {
        if (card.faceUp) {
            Text(card.rankLabel, color = ink, fontSize = (14 * s).sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(start = (3 * s).dp, top = (1 * s).dp))
            Text(card.suit.symbol, color = ink, fontSize = (11 * s).sp, modifier = Modifier.align(Alignment.TopEnd).padding(end = (4 * s).dp, top = (3 * s).dp))
            Text(card.suit.symbol, color = ink, fontSize = (26 * s).sp, modifier = Modifier.align(Alignment.Center).padding(top = (14 * s).dp))
        } else {
            Box(Modifier.padding(width * 0.08f).fillMaxWidth().height(h - width * 0.16f).border(1.dp, Color.White.copy(alpha = 0.45f), RoundedCornerShape(radius * 0.6f)))
        }
    }
}

/** Empty pile placeholder (foundations, free cells, empty columns). */
@Composable
fun CardSlot(width: Dp, label: String = "", modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val pal = Pal.current
    val click = if (onClick != null) Modifier.clickable(remember { MutableInteractionSource() }, null) { onClick() } else Modifier
    Box(modifier.size(width, width * CARD_RATIO)
        .border(1.5.dp, pal.text.copy(alpha = 0.18f), RoundedCornerShape(width * 4f / 50f)).then(click), contentAlignment = Alignment.Center) {
        Text(label, color = pal.text.copy(alpha = 0.18f), fontSize = (width.value * 0.4f).sp)
    }
}

/** Vertical offsets for a fanned column; the fan tightens when it would run past [maxHeight]. */
fun fanOffsets(cards: List<Card>, cardHeight: Float, maxHeight: Float): List<Float> {
    val faceUp = cardHeight * 20 / 72
    val faceDown = cardHeight * 0.12f
    val steps = cards.dropLast(1).map { if (it.faceUp) faceUp else faceDown }
    val natural = steps.sum()
    val room = maxOf(0f, maxHeight - cardHeight)
    val squeeze = if (natural > room && natural > 0) room / natural else 1f
    var y = 0f
    return cards.indices.map { i -> val out = y; if (i < steps.size) y += steps[i] * squeeze; out }
}

/** Hint and undo controls under the table. Pass a null [hint] for games without hints. */
@Composable
fun CardGameControls(hint: (() -> Unit)?, canUndo: Boolean, undo: () -> Unit) {
    val pal = Pal.current
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(64.dp, Alignment.CenterHorizontally)) {
        if (hint != null) ControlCircle("💡", true, hint)
        ControlCircle("↩", canUndo, undo)
    }
}

@Composable
private fun ControlCircle(glyph: String, enabled: Boolean, onClick: () -> Unit) {
    val pal = Pal.current
    Box(Modifier.size(50.dp).clip(CircleShape).background(pal.surface).clickable(enabled = enabled, onClick = onClick), contentAlignment = Alignment.Center) {
        Text(glyph, fontSize = 20.sp, color = pal.text.copy(alpha = if (enabled) 1f else 0.4f))
    }
}
