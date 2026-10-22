package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameEngine
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.CARD_RATIO
import com.nurali.puzzlebox.games.kit.Card
import com.nurali.puzzlebox.games.kit.CardGameControls
import com.nurali.puzzlebox.games.kit.CardSlot
import com.nurali.puzzlebox.games.kit.CardView
import com.nurali.puzzlebox.games.kit.Suit
import com.nurali.puzzlebox.games.kit.fanOffsets
import com.nurali.puzzlebox.ui.Pal

class SpiderEngine : GameEngine {
    companion object { const val COLUMNS = 10 }

    class Snap(val tableau: List<List<Card>>, val stock: List<List<Card>>, val completedRuns: Int)

    var tableau by mutableStateOf(List(COLUMNS) { listOf<Card>() })
    var stock by mutableStateOf(listOf<List<Card>>())      // remaining deals of 10
    var completedRuns by mutableIntStateOf(0)
    var message by mutableStateOf("")
    var selCol by mutableIntStateOf(-1)
    var selIndex by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    /** 1 suit (spades) or 2 suits (spades and hearts). */
    var suitCount by mutableIntStateOf(if (Settings.prefs.getInt("spiderSuits", 1) == 2) 2 else 1)
        private set

    override val score get() = completedRuns * (if (suitCount == 2) 160 else 100)

    private val history = ArrayList<Snap>()
    var historySize by mutableIntStateOf(0)
    val canUndo get() = state == GameState.Playing && historySize > 0

    init { deal() }

    override fun restart() = deal()

    fun chooseSuits(value: Int) {
        if (value == suitCount) return
        suitCount = value
        Settings.prefs.edit().putInt("spiderSuits", value).apply()
        deal()
    }

    private fun save() { history.add(Snap(tableau, stock, completedRuns)); historySize = history.size }

    fun undo() {
        if (!canUndo) return
        val p = history.removeAt(history.lastIndex); historySize = history.size
        tableau = p.tableau; stock = p.stock; completedRuns = p.completedRuns; selCol = -1
        Haptics.tap(); Sfx.tap()
    }

    private fun deal() {
        // 104 cards: eight spade suits, or four spades plus four hearts.
        val deck = ArrayList<Card>()
        for (i in 0 until 8) {
            val suit = if (suitCount == 2 && i % 2 == 0) Suit.Hearts else Suit.Spades
            for (r in 1..13) deck.add(Card.make(suit, r, faceUp = false))
        }
        deck.shuffle()
        history.clear(); historySize = 0
        tableau = (0 until COLUMNS).map { col ->
            val count = if (col < 4) 6 else 5
            (0 until count).map { i -> deck.removeAt(deck.lastIndex).copy(faceUp = i == count - 1) }
        }
        stock = (0 until 5).map { (0 until 10).map { deck.removeAt(deck.lastIndex) } }
        completedRuns = 0; selCol = -1; message = ""; state = GameState.Playing
    }

    /** A grabbable run is face-up and strictly descending by one in a single suit. */
    private fun isValidRun(col: Int, from: Int): Boolean {
        val pile = tableau[col]
        if (from !in pile.indices || !pile[from].faceUp) return false
        for (i in from until pile.size - 1) if (!(pile[i].rank == pile[i + 1].rank + 1 && pile[i].suit == pile[i + 1].suit)) return false
        return true
    }

    /** The column a run should go to: a matching suit first, then any matching rank, then an empty column. */
    private fun bestTarget(col: Int, index: Int): Int? {
        val first = tableau[col][index]
        val candidates = (0 until COLUMNS).filter { it != col && (tableau[it].lastOrNull()?.let { c -> c.faceUp && c.rank == first.rank + 1 } ?: false) }
        candidates.firstOrNull { tableau[it].last().suit == first.suit }?.let { return it }
        candidates.firstOrNull()?.let { return it }
        // Moving a whole column into an empty one achieves nothing.
        if (index > 0) (0 until COLUMNS).firstOrNull { tableau[it].isEmpty() }?.let { return it }
        return null
    }

    fun hint() {
        if (state != GameState.Playing) return
        var fallback: Pair<Int, Int>? = null
        for (col in 0 until COLUMNS) {
            val start = (0 until tableau[col].size).firstOrNull { isValidRun(col, it) } ?: continue
            val target = bestTarget(col, start) ?: continue
            if (tableau[target].isEmpty()) continue
            // Prefer moves that uncover a face-down card or build on the same suit.
            if ((start > 0 && !tableau[col][start - 1].faceUp) || tableau[target].last().suit == tableau[col][start].suit) {
                selCol = col; selIndex = start; Haptics.tap(); Sfx.tap(); return
            }
            if (fallback == null) fallback = col to start
        }
        if (fallback != null) { selCol = fallback.first; selIndex = fallback.second; Haptics.tap(); Sfx.tap() }
        else { message = L10n.t(if (stock.isEmpty()) "No moves left" else "Deal more cards"); Haptics.error() }
    }

    fun tapColumn(col: Int, index: Int?) {
        if (state != GameState.Playing) return
        message = ""
        if (selCol >= 0 && selCol != col && moveSelection(col)) return
        if (selCol == col && selIndex == index) {
            // Tapping the same run again sends it to the best column.
            val t = bestTarget(col, selIndex)
            if (t != null && moveSelection(t)) return
            selCol = -1; return
        }
        if (index != null && isValidRun(col, index)) { selCol = col; selIndex = index; Haptics.tap(); Sfx.tap() } else selCol = -1
    }

    private fun moveSelection(col: Int): Boolean {
        if (selCol < 0) return false
        val src = selCol; val idx = selIndex
        val cards = tableau[src].subList(idx, tableau[src].size).toList()
        val first = cards.firstOrNull() ?: return false
        tableau[col].lastOrNull()?.let { if (!(it.faceUp && it.rank == first.rank + 1)) return false }
        save()
        var from = tableau[src].subList(0, idx).toList()
        if (from.isNotEmpty() && !from.last().faceUp) from = from.dropLast(1) + from.last().copy(faceUp = true)
        tableau = tableau.mapIndexed { i, c -> when (i) { src -> from; col -> c + cards; else -> c } }
        selCol = -1
        Haptics.move(); Sfx.tap()
        checkCompletedRun(col)
        return true
    }

    private fun checkCompletedRun(col: Int) {
        val pile = tableau[col]
        if (pile.size < 13) return
        val top13 = pile.takeLast(13)
        if (top13.first().rank != 13 || !top13.all { it.faceUp }) return
        for (i in 0 until 12) if (top13[i].rank != top13[i + 1].rank + 1 || top13[i].suit != top13[i + 1].suit) return
        var rest = pile.dropLast(13)
        if (rest.isNotEmpty() && !rest.last().faceUp) rest = rest.dropLast(1) + rest.last().copy(faceUp = true)
        tableau = tableau.mapIndexed { i, c -> if (i == col) rest else c }
        completedRuns++
        Haptics.success(); Sfx.win()
        if (completedRuns == 8) state = GameState.GameOver(won = true)
    }

    fun dealFromStock() {
        if (state != GameState.Playing) return
        val next = stock.lastOrNull() ?: return
        if (tableau.any { it.isEmpty() }) { message = L10n.t("Fill every empty column before dealing"); Haptics.error(); Sfx.wrong(); return }
        selCol = -1
        save()
        stock = stock.dropLast(1)
        tableau = tableau.mapIndexed { i, c -> c + next[i].copy(faceUp = true) }
        Haptics.move(); Sfx.tap()
        for (c in 0 until COLUMNS) checkCompletedRun(c)
    }

    fun isSelected(col: Int, index: Int) = selCol == col && index >= selIndex
}

@Composable
fun SpiderScreen(onExit: () -> Unit) {
    val engine = remember { SpiderEngine() }
    val pal = Pal.current
    GameContainer(GameId.SpiderSolitaire, engine, onExit, timed = true) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val gap = 4.dp
            val cw = (maxWidth - gap * (SpiderEngine.COLUMNS - 1)) / SpiderEngine.COLUMNS
            val ch = cw * CARD_RATIO
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(pal.surface)) {
                    listOf(1 to "1 suit", 2 to "2 suits").forEach { (n, label) ->
                        Box(Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).background(if (engine.suitCount == n) pal.accent else Color.Transparent)
                            .clickable { engine.chooseSuits(n) }.padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                            Text(L10n.t(label), color = if (engine.suitCount == n) pal.onAccent else pal.text, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                        }
                    }
                }
                Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("✔ " + L10n.f("%d of 8 runs", engine.completedRuns), color = pal.accent, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    if (engine.message.isNotEmpty()) Text("  " + engine.message, color = Color.Red, fontSize = 12.sp, modifier = Modifier.weight(1f))
                    else androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
                    val enabled = engine.stock.isNotEmpty()
                    Box(Modifier.clip(RoundedCornerShape(50)).background(if (enabled) pal.accent else pal.surface)
                        .clickable(enabled = enabled) { engine.dealFromStock() }.padding(horizontal = 14.dp, vertical = 8.dp)) {
                        Text("🂠 " + L10n.f("Deal (%d)", engine.stock.size), color = if (enabled) pal.onAccent else pal.textSecondary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                    val maxH = maxHeight.value
                    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                        for (col in 0 until SpiderEngine.COLUMNS) {
                            val cards = engine.tableau[col]
                            val offs = fanOffsets(cards, ch.value, maxH)
                            Box(Modifier.width(cw)) {
                                CardSlot(cw) { engine.tapColumn(col, null) }
                                cards.forEachIndexed { i, c -> CardView(c, cw, engine.isSelected(col, i), Modifier.offset(y = offs[i].dp)) { engine.tapColumn(col, i) } }
                            }
                        }
                    }
                }
                CardGameControls(engine::hint, engine.canUndo, engine::undo)
            }
        }
    }
}
