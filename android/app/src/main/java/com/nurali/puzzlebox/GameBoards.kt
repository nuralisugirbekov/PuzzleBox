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
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.min

fun Modifier.semanticsLabel(label: String) = semantics { contentDescription = label }
private fun DrawScope.letter(label: String, at: Offset, size: Float, color: Color = Color.White, bold: Boolean = false) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color.toArgb(); textSize = size; textAlign = Paint.Align.CENTER
        typeface = if (bold) Typeface.create("sans-serif", Typeface.BOLD) else Typeface.create("sans-serif", Typeface.NORMAL)
    }
    drawContext.canvas.nativeCanvas.drawText(label, at.x, at.y - (paint.ascent() + paint.descent()) / 2, paint)
}

@Composable
fun GridBoard(n: Int, engine: Engine, label: String, color: (Int) -> Color, text: (Int) -> String = { "" },
              ink: (Int) -> Color = { Color.White }, selected: Set<Int> = emptySet(),
              onTap: (Int) -> Unit, onLong: ((Int) -> Unit)? = null,
              onSwipe: ((Int, Int, Int) -> Unit)? = null, modifier: Modifier = Modifier) {
    val tap by rememberUpdatedState(onTap); val long by rememberUpdatedState(onLong); val swipe by rememberUpdatedState(onSwipe)
    var origin by remember { mutableStateOf(Offset.Zero) }; var distance by remember { mutableStateOf(Offset.Zero) }
    Canvas(modifier.fillMaxWidth().aspectRatio(1f).semanticsLabel(label)
        .pointerInput(n) { detectTapGestures(onTap = { p ->
            val c = (p.x / size.width * n).toInt(); val r = (p.y / size.height * n).toInt()
            if (r in 0 until n && c in 0 until n) tap(r * n + c)
        }, onLongPress = { p ->
            val c = (p.x / size.width * n).toInt(); val r = (p.y / size.height * n).toInt()
            if (r in 0 until n && c in 0 until n) long?.invoke(r * n + c)
        }) }
        .pointerInput(n) { detectDragGestures(onDragStart = { origin = it; distance = Offset.Zero },
            onDrag = { change, delta -> change.consume(); distance += delta }, onDragEnd = {
                val c = (origin.x / size.width * n).toInt(); val r = (origin.y / size.height * n).toInt()
                if (r in 0 until n && c in 0 until n && distance.getDistance() > 15) {
                    val dr = if (abs(distance.y) > abs(distance.x)) (if (distance.y > 0) 1 else -1) else 0
                    val dc = if (dr == 0) (if (distance.x > 0) 1 else -1) else 0
                    swipe?.invoke(r * n + c, dr, dc)
                }
            }) }) {
        val boardRevision = engine.revision
        val pitch = size.width / n
        for (i in 0 until n * n) {
            val offset = Offset(i % n * pitch + 1, i / n * pitch + 1)
            drawRoundRect(color(i), offset, Size(pitch - 2, pitch - 2), androidx.compose.ui.geometry.CornerRadius(pitch * .08f))
            if (i in selected) drawRoundRect(Palette.neon, offset + Offset(2f, 2f), Size(pitch - 6, pitch - 6), style = Stroke(3f))
            letter(text(i), Offset((i % n + .5f) * pitch, (i / n + .5f) * pitch), pitch * .5f, ink(i), true)
        }
    }
}

@Composable
fun GameBody(e: Engine) {
    val revision = e.revision
    val t = LocalStrings.current
    when (e) {
        is ChessEngine -> ChessBoard(e)
        is PatienceEngine -> PatienceBoard(e)
        is SpadesEngine -> SpadesBoard(e)
        is DominoEngine -> DominoBoard(e)
        is MinesEngine -> {
            Text("⚑ ${10 - e.flags.size}", color = Palette.neon)
            Action(if (e.flagMode) "Flag Mode" else "Dig Mode") { e.flagMode = !e.flagMode; e.changed() }
            GridBoard(9, e, t.text("Minesweeper"), { if (it in e.revealed) Palette.raised else Palette.surface },
                { if (it in e.flags) "⚑" else if (it !in e.revealed) "" else if (it in e.mines) "✹" else e.adjacent(it).let { k -> if (k == 0) "" else "$k" } },
                { if (it in e.mines) Color.Red else Palette.colors[e.adjacent(it) % 6] }, onTap = { e.tap(it) }, onLong = { e.tap(it, true) })
        }
        is SudokuEngine -> {
            Text(t.text("%d mistakes", e.mistakes), color = Palette.secondary)
            GridBoard(6, e, t.text("Mini Sudoku"), { if ((it / 6 / 2 + it % 6 / 3) % 2 == 0) Palette.surface else Palette.raised },
                { e.board[it].let { n -> if (n == 0) "" else "$n" } },
                { if (it in e.given) Color.White else if (e.board[it] == e.solution[it]) Palette.neon else Color(0xFFFF7272) },
                listOfNotNull(e.selected).toSet(), { if (e.phase == Phase.PLAYING) { e.selected = it; e.changed() } })
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                (1..6).forEach { value -> TextButton({ e.enter(value) }, Modifier.weight(1f), contentPadding = PaddingValues(0.dp)) { Text("$value", fontSize = 22.sp) } }
            }
            Action("Erase") { e.enter(0) }
        }
        is SnakeEngine -> {
            GridBoard(14, e, t.text("Snake"), { i -> val p = Cell(i / 14, i % 14); when { p == e.body.first() -> Color.White; p in e.body -> Palette.neon; p == e.food -> Palette.colors[0]; else -> Palette.surface } },
                onTap = {}, onSwipe = { _, dr, dc -> e.turn(dr, dc) })
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                DirectionButton("↑") { e.turn(-1, 0) }
                Row(horizontalArrangement = Arrangement.spacedBy(44.dp)) { DirectionButton("←") { e.turn(0, -1) }; DirectionButton("→") { e.turn(0, 1) } }
                DirectionButton("↓") { e.turn(1, 0) }
            }
        }
        is WaterEngine -> {
            Text(t.text("%d moves", e.moves))
            repeat(2) { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    repeat(4) { col ->
                        val i = row * 4 + col
                        Column(Modifier.weight(1f).height(170.dp).border(if (e.selected == i) 3.dp else 1.dp,
                            if (e.selected == i) Palette.neon else Palette.secondary, RoundedCornerShape(bottomStart = 18.dp, bottomEnd = 18.dp))
                            .clickable { e.tap(i) }.padding(5.dp), verticalArrangement = Arrangement.Bottom) {
                            repeat(4 - e.tubes[i].size) { Spacer(Modifier.weight(1f)) }
                            e.tubes[i].asReversed().forEach { color -> Box(Modifier.fillMaxWidth().weight(1f).background(Palette.colors[color])) }
                        }
                    }
                }
            }
            Text(t.text("Tap a tube to pick it up, then tap another to pour."), color = Palette.secondary, fontSize = 13.sp)
            Action("Undo", enabled = e.canUndo) { e.undo() }
        }
        is BlockEngine -> BlockBoard(e)
        is MatchEngine -> {
            Text(t.text("%d moves left", e.moves))
            GridBoard(6, e, t.text("Three in a Row"), { Palette.colors[e.board[it]].copy(alpha = if (it in e.matches) .35f else .9f) },
                { listOf("◆", "●", "▲", "■", "✦")[e.board[it]] }, selected = listOfNotNull(e.selected).toSet(), onTap = e::tap,
                onSwipe = { i, dr, dc -> val r = i / 6 + dr; val c = i % 6 + dc; if (r in 0..5 && c in 0..5) { e.selected = i; e.tap(r * 6 + c) } })
            Text(t.text("Swipe a gem toward a neighbor to swap them."), color = Palette.secondary, fontSize = 13.sp)
        }
    }
}

@Composable
fun DirectionButton(label: String, action: () -> Unit) { FilledTonalButton(action, Modifier.size(62.dp), contentPadding = PaddingValues(0.dp)) { Text(label, fontSize = 26.sp) } }

@Composable
fun BlockBoard(e: BlockEngine) {
    val revision = e.revision
    var boardBounds by remember { mutableStateOf(androidx.compose.ui.geometry.Rect.Zero) }
    var preview by remember { mutableStateOf<Int?>(null) }
    val piece = e.selected?.let { e.tray[it] }
    val highlighted = if (piece != null && preview != null && e.fits(piece, preview!!)) {
        piece.cells.map { (preview!! / 8 + it.r) * 8 + preview!! % 8 + it.c }.toSet()
    } else emptySet()
    GridBoard(8, e, LocalStrings.current.text("Block Blast"), { if (e.board[it] < 0) Palette.surface else Palette.colors[e.board[it]] },
        selected = highlighted, onTap = e::place, modifier = Modifier.onGloballyPositioned { boardBounds = it.boundsInRoot() })
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        e.tray.forEachIndexed { i, piece ->
            var trayOrigin by remember(i) { mutableStateOf(Offset.Zero) }
            Box(Modifier.weight(1f).height(106.dp).background(Palette.surface, RoundedCornerShape(12.dp))
                .border(1.dp, if (e.selected == i) Palette.neon else Color.Transparent, RoundedCornerShape(12.dp))
                .onGloballyPositioned { trayOrigin = it.boundsInRoot().topLeft }
                .clickable { if (piece != null) { e.selected = i; e.changed() } }
                .pointerInput(e, i) {
                    var pointer = Offset.Zero
                    detectDragGestures(onDragStart = {
                        pointer = trayOrigin + it
                        if (e.tray[i] != null && e.phase == Phase.PLAYING) { e.selected = i; e.changed() }
                    }, onDrag = { change, delta ->
                        change.consume(); pointer += delta
                        val current = e.tray[i]
                        val pitch = boardBounds.width / 8
                        if (current != null && pitch > 0) {
                            val col = kotlin.math.round((pointer.x - boardBounds.left) / pitch - (current.cells.maxOf { it.c } + 1) / 2f).toInt()
                            val row = kotlin.math.round((pointer.y - 60.dp.toPx() - boardBounds.top) / pitch - (current.cells.maxOf { it.r } + 1) / 2f).toInt()
                            preview = if (row in 0..7 && col in 0..7) row * 8 + col else null
                        }
                    }, onDragEnd = { preview?.let(e::place); preview = null }, onDragCancel = { preview = null })
                }, contentAlignment = Alignment.Center) {
                if (piece != null) Canvas(Modifier.size(80.dp)) {
                    val unit = size.width / 4.5f
                    val width = (piece.cells.maxOf { it.c } + 1) * unit
                    val height = (piece.cells.maxOf { it.r } + 1) * unit
                    piece.cells.forEach { drawRoundRect(Palette.colors[piece.color], Offset((size.width - width) / 2 + it.c * unit, (size.height - height) / 2 + it.r * unit), Size(unit - 2, unit - 2)) }
                }
            }
        }
    }
}

@Composable
fun ChessBoard(e: ChessEngine) {
    val revision = e.revision
    val t = LocalStrings.current
    Text(t.text("Solved: %d", e.solved), color = Palette.neon, fontWeight = FontWeight.Bold)
    Text("${t.text("Mate in 1")} · #${e.puzzle.id}", color = Palette.secondary)
    val glyphs = mapOf('K' to "♔", 'Q' to "♕", 'R' to "♖", 'B' to "♗", 'N' to "♘", 'P' to "♙", 'k' to "♚", 'q' to "♛", 'r' to "♜", 'b' to "♝", 'n' to "♞", 'p' to "♟︎")
    Canvas(Modifier.fillMaxWidth().aspectRatio(1f).semanticsLabel(t.text("Checkmate"))
        .pointerInput(e) { detectTapGestures { p -> val c = (p.x / size.width * 8).toInt(); val r = (p.y / size.height * 8).toInt(); if (r in 0..7 && c in 0..7) e.tap(r * 8 + c) } }) {
        val boardRevision = e.revision
        val unit = size.width / 8
        for (i in 0..63) {
            val r = i / 8; val c = i % 8
            val at = Offset(c * unit, r * unit)
            drawRect(if ((r + c) % 2 == 0) Color(0xFFA6B09C) else Color(0xFF526449), at, Size(unit, unit))
            if (e.selected == i) drawRect(Palette.neon.copy(alpha = .4f), at, Size(unit, unit))
            if (i in e.targets) drawCircle(Palette.neon.copy(alpha = .65f), unit * .1f, at + Offset(unit / 2, unit / 2))
            val piece = e.board[i]
            if (piece != ' ' && !(e.animation < 1 && i == e.moveTo)) {
                letter(glyphs[piece] ?: "", at + Offset(unit / 2, unit / 2), unit * .8f, if (piece.isUpperCase()) Color.White else Color.Black)
            }
            if (c == 0) letter("${8 - r}", at + Offset(unit * .1f, unit * .12f), unit * .18f, Color.Black)
            if (r == 7) letter("${'a' + c}", at + Offset(unit * .9f, unit * .9f), unit * .18f, Color.Black)
        }
        val from = e.moveFrom; val to = e.moveTo
        if (e.animation < 1 && from != null && to != null) {
            val a = e.animation
            val c = from % 8 + (to % 8 - from % 8) * a; val r = from / 8 + (to / 8 - from / 8) * a
            letter(glyphs[e.movingGlyph] ?: "", Offset((c + .5f) * unit, (r + .5f) * unit), unit * .8f, Color.White)
        }
    }
}
