package com.nurali.puzzlebox

import android.graphics.Paint
import android.graphics.Typeface
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max

private fun DrawScope.cardText(text: String, at: Offset, size: Float, color: Color) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color.toArgb(); textSize = size; typeface = Typeface.create("sans-serif", Typeface.BOLD)
    }
    drawContext.canvas.nativeCanvas.drawText(text, at.x, at.y, paint)
}
private fun DrawScope.playingCard(card: Card?, at: Offset, width: Float, height: Float, selected: Boolean = false, placeholder: String = "") {
    val radius = androidx.compose.ui.geometry.CornerRadius(width * .09f)
    drawRoundRect(if (card == null) Palette.surface else if (card.faceUp) Color(0xFFF5F3EC) else Color(0xFF263D72), at, Size(width, height), radius)
    drawRoundRect(if (selected) Palette.neon else Color.White.copy(alpha = .25f), at, Size(width, height), radius, style = Stroke(if (selected) 4f else 1f))
    if (card != null && card.faceUp) {
        val ink = if (card.red) Color(0xFFBE3448) else Color(0xFF17212F)
        cardText(card.label, at + Offset(width * .07f, width * .38f), width * .32f, ink)
        cardText("♠♥♦♣"[card.suit].toString(), at + Offset(width * .28f, height * .76f), width * .55f, ink)
    } else if (card != null) {
        drawRoundRect(Color.White.copy(alpha = .2f), at + Offset(5f, 5f), Size(width - 10, height - 10), radius, style = Stroke(1f))
    } else if (placeholder.isNotEmpty()) cardText(placeholder, at + Offset(width * .24f, height * .6f), width * .42f, Palette.secondary)
}

@Composable
fun PatienceBoard(e: PatienceEngine) {
    val revision = e.revision
    val t = LocalStrings.current
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        if (e.spider) Text(t.text("%d of 8 runs", e.runs), color = Palette.neon)
        Action("Undo", enabled = e.canUndo) { e.undo() }
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val pitchDp = maxWidth / e.columns
        val widthDp = pitchDp - 3.dp
        val cardHeightDp = widthDp * 1.42f
        val stackStepDp = maxOf(20.dp, widthDp * .42f)
        val topDp = cardHeightDp + 26.dp
        val heightDp = maxOf(420.dp, topDp + stackStepDp * (e.tableau.maxOf { it.size }.coerceAtLeast(1) - 1) + cardHeightDp + 40.dp)
        Canvas(Modifier.fillMaxWidth().height(heightDp).semanticsLabel(t.text(e.game.title))
            .pointerInput(e) {
                fun hit(p: Offset): Triple<Int, Int, Int?>? {
                    val pitch = size.width.toFloat() / e.columns; val w = pitch - 3.dp.toPx(); val h = w * 1.42f
                    val top = h + 26.dp.toPx(); val step = max(20.dp.toPx(), w * .42f)
                    if (p.x < 0 || p.x >= size.width || p.y < 0 || p.y >= size.height) return null
                    val col = (p.x / pitch).toInt()
                    if (p.y < h) {
                        return if (e.freecell) { if (col < 4) Triple(2, col, null) else Triple(1, col - 4, null) }
                        else if (e.spider) Triple(4, 0, null)
                        else when (col) { 0 -> Triple(4, 0, null); 1 -> Triple(3, 0, null); in 3..6 -> Triple(1, col - 3, null); else -> null }
                    }
                    if (p.y >= top) {
                        val pile = e.tableau[col]
                        val index = if (pile.isEmpty()) null else ((p.y - top) / step).toInt().coerceAtMost(pile.lastIndex)
                        return Triple(0, col, index)
                    }
                    return null
                }
                fun tap(p: Offset) { val target = hit(p) ?: return; when (target.first) {
                    0 -> e.tapColumn(target.second, target.third); 1 -> e.tapFoundation(target.second)
                    2 -> e.tapCell(target.second); 3 -> e.tapWaste(); 4 -> e.draw()
                } }
                detectTapGestures(onTap = ::tap)
            }
            .pointerInput(e) {
                var start = Offset.Zero; var end = Offset.Zero; var valid = false
                detectDragGestures(onDragStart = { p ->
                    start = p; end = p; valid = false
                    val pitch = size.width.toFloat() / e.columns; val w = pitch - 3.dp.toPx(); val h = w * 1.42f
                    val top = h + 26.dp.toPx(); val step = max(20.dp.toPx(), w * .42f)
                    val col = (p.x / pitch).toInt()
                    if (col in 0 until e.columns && e.phase == Phase.PLAYING) {
                        e.selection = null
                        if (p.y >= top && e.tableau[col].isNotEmpty()) e.tapColumn(col, ((p.y - top) / step).toInt().coerceAtMost(e.tableau[col].lastIndex))
                        else if (p.y in 0f..h) {
                            if (e.freecell) { if (col < 4) e.tapCell(col) else e.tapFoundation(col - 4) }
                            else if (!e.spider) { if (col == 1) e.tapWaste() else if (col in 3..6) e.tapFoundation(col - 3) }
                        }
                        valid = e.selection != null
                    }
                }, onDrag = { change, delta -> change.consume(); end += delta }, onDragCancel = { valid = false }, onDragEnd = {
                    if (valid && (end - start).getDistance() > 10 && end.x >= 0 && end.x < size.width && end.y >= 0 && end.y < size.height) {
                        val pitch = size.width.toFloat() / e.columns; val h = (pitch - 3.dp.toPx()) * 1.42f
                        val col = (end.x / pitch).toInt()
                        if (end.y >= h + 26.dp.toPx()) e.tapColumn(col)
                        else if (end.y < h) {
                            if (e.freecell) { if (col < 4) e.tapCell(col) else e.tapFoundation(col - 4) }
                            else if (!e.spider && col in 3..6) e.tapFoundation(col - 3)
                        }
                    }
                })
            }) {
            val boardRevision = e.revision
            val pitch = size.width / e.columns; val w = pitch - 3.dp.toPx(); val h = w * 1.42f
            val top = h + 26.dp.toPx(); val step = max(20.dp.toPx(), w * .42f)
            if (e.freecell) {
                repeat(4) { i -> playingCard(e.cells[i], Offset(i * pitch, 0f), w, h, e.selection == CardSelection(2, i)) }
                repeat(4) { i -> playingCard(e.foundations[i].lastOrNull(), Offset((i + 4) * pitch, 0f), w, h, e.selection == CardSelection(1, i), "A") }
            } else if (e.spider) {
                playingCard(e.stock.lastOrNull(), Offset.Zero, w, h, placeholder = "↻")
                cardText(t.text("Deal (%d)", e.stock.size / 10), Offset(pitch + 8, h * .6f), 14.sp.toPx(), Palette.neon)
            } else {
                playingCard(e.stock.lastOrNull(), Offset.Zero, w, h, placeholder = "↻")
                playingCard(e.waste.lastOrNull(), Offset(pitch, 0f), w, h, e.selection == CardSelection(3))
                repeat(4) { i -> playingCard(e.foundations[i].lastOrNull(), Offset((i + 3) * pitch, 0f), w, h, e.selection == CardSelection(1, i), "A") }
            }
            for (col in e.tableau.indices) {
                val x = col * pitch
                // The whole empty column below this slot is a valid tap/drop destination.
                if (e.tableau[col].isEmpty()) playingCard(null, Offset(x, top), w, h)
                e.tableau[col].forEachIndexed { i, card ->
                    val sel = e.selection
                    playingCard(card, Offset(x, top + i * step), w, h, sel?.area == 0 && sel.col == col && i >= sel.index)
                }
            }
        }
    }
}

@Composable
fun SmallCard(card: Card, enabled: Boolean = true, action: () -> Unit) {
    Canvas(Modifier.width(52.dp).height(76.dp).semanticsLabel(card.label).clickable(enabled = enabled, onClick = action)) {
        playingCard(card, Offset(2f, 2f), size.width - 4, size.height - 4)
        if (!enabled) drawRect(Color.Black.copy(alpha = .4f))
    }
}

@Composable
fun SpadesBoard(e: SpadesEngine) {
    val revision = e.revision
    val t = LocalStrings.current
    val names = listOf("You", "West", "North", "East")
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
        for (i in 1..3) Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(t.text(names[i]), color = if (i == 2) Palette.neon else Palette.secondary)
            Text(t.text("%d/%d tricks", e.seats[i].tricks, e.seats[i].bid), fontSize = 12.sp)
        }
    }
    Surface(Modifier.fillMaxWidth().height(172.dp), color = Palette.surface, shape = RoundedCornerShape(18.dp)) {
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
            e.trick.forEach { (seat, card) -> Column(horizontalAlignment = Alignment.CenterHorizontally) { Text(t.text(names[seat]), fontSize = 12.sp); SmallCard(card, false) {} } }
        }
    }
    if (e.bidding) {
        Text(t.text("How many tricks will you take?"))
        Text("${e.userBid}", fontSize = 28.sp, color = Palette.neon)
        Slider(e.userBid.toFloat(), { e.userBid = it.toInt(); e.changed() }, valueRange = 0f..13f, steps = 12)
        Text(t.text("Nil bid: +100 if you take no tricks, −100 if you take any!"), fontSize = 12.sp, color = Palette.secondary)
        Action("Start Hand") { e.start() }
    } else Text(t.text("You: %d/%d", e.seats[0].tricks, e.seats[0].bid), color = Palette.neon)
    e.seats[0].hand.chunked(6).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally)) {
            row.forEach { card -> SmallCard(card, !e.bidding && e.turn == 0 && e.trick.size < 4 && card in e.legal(0)) { e.userPlay(card) } }
        }
    }
}

@Composable
fun DominoBoard(e: DominoEngine) {
    val revision = e.revision
    val t = LocalStrings.current
    Text("${t.text("Bot")}: ${e.bot.size}", color = Palette.secondary)
    Row(Modifier.fillMaxWidth().height(100.dp).background(Palette.surface, RoundedCornerShape(16.dp)).horizontalScroll(rememberScrollState()).padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        if (e.chain.isEmpty()) Text(t.text("Play the first tile"), color = Palette.secondary)
        e.chain.forEach { d -> DominoTile(d, false) {} }
    }
    e.hand.chunked(4).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)) {
            row.forEach { d -> DominoTile(d, e.userTurn && e.fits(d)) { e.tap(d) } }
        }
    }
    Action(if (e.stock.isEmpty()) "Pass" else t.text("Draw (%d)", e.stock.size), enabled = e.userTurn && e.hand.none(e::fits)) { e.draw() }
    if (e.pending != null) AlertDialog(onDismissRequest = { e.pending = null; e.changed() }, title = { Text(t.text("Play on which end?")) },
        confirmButton = { TextButton({ e.choose(false) }) { Text(t.text("Right")) } }, dismissButton = { TextButton({ e.choose(true) }) { Text(t.text("Left")) } })
}

@Composable
fun DominoTile(d: Domino, enabled: Boolean, action: () -> Unit) {
    Surface(onClick = action, enabled = enabled, shape = RoundedCornerShape(8.dp), color = Color(0xFFF5F3EC), border = BorderStroke(2.dp, if (enabled) Palette.neon else Color.Transparent)) {
        Text("${"⚀⚁⚂⚃⚄⚅".getOrNull(d.a - 1) ?: '○'}│${"⚀⚁⚂⚃⚄⚅".getOrNull(d.b - 1) ?: '○'}", Modifier.padding(horizontal = 7.dp, vertical = 12.dp), color = Color(0xFF17212F), fontSize = 22.sp)
    }
}
