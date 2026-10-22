package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.graphics.Color
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
import com.nurali.puzzlebox.games.kit.fanOffsets
import com.nurali.puzzlebox.ui.Pal
import kotlinx.coroutines.delay

// MARK: - Klondike (tap to select, tap to move)

class SolitaireEngine : GameEngine {
    sealed interface Sel {
        data class Foundation(val pile: Int) : Sel
        data object Waste : Sel
        data class Tableau(val col: Int, val index: Int) : Sel
    }

    class Snap(val stock: List<Card>, val waste: List<Card>, val foundations: List<List<Card>>, val tableau: List<List<Card>>, val score: Int)

    var stock by mutableStateOf(listOf<Card>())
    var waste by mutableStateOf(listOf<Card>())
    var foundations by mutableStateOf(List(4) { listOf<Card>() })
    var tableau by mutableStateOf(List(7) { listOf<Card>() })
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var selection by mutableStateOf<Sel?>(null)
    var stockHint by mutableIntStateOf(0)
    private val history = ArrayList<Snap>()
    var historySize by mutableIntStateOf(0)
    val canUndo get() = state == GameState.Playing && historySize > 0

    init { deal() }

    override fun restart() = deal()

    private fun save() { history.add(Snap(stock, waste, foundations, tableau, score)); historySize = history.size }

    fun undo() {
        if (!canUndo) return
        val p = history.removeAt(history.lastIndex); historySize = history.size
        stock = p.stock; waste = p.waste; foundations = p.foundations; tableau = p.tableau; score = p.score; selection = null
        Haptics.tap(); Sfx.tap()
    }

    private fun deal() {
        history.clear(); historySize = 0
        val deck = Card.deck().shuffled().toMutableList()
        tableau = (0 until 7).map { col ->
            (0..col).map { i -> deck.removeAt(deck.lastIndex).copy(faceUp = i == col) }
        }
        stock = deck.map { it.copy(faceUp = false) }
        waste = emptyList(); foundations = List(4) { emptyList() }
        score = 0; selection = null; state = GameState.Playing
    }

    fun tapStock() {
        if (state != GameState.Playing) return
        selection = null
        if (stock.isEmpty() && waste.isEmpty()) return
        save()
        if (stock.isNotEmpty()) {
            val card = stock.last().copy(faceUp = true)
            stock = stock.dropLast(1); waste = waste + card
        } else {
            stock = waste.reversed().map { it.copy(faceUp = false) }; waste = emptyList()
        }
        Haptics.tap(); Sfx.tap()
    }

    fun tapWaste() {
        if (state != GameState.Playing || waste.isEmpty()) return
        if (selection == Sel.Waste) { if (!autoMoveSelection()) selection = null; return }
        selection = Sel.Waste
        Haptics.tap(); Sfx.tap()
    }

    /** Moves the selection to a foundation if possible, otherwise to the first column that accepts it. */
    fun autoMoveSelection(): Boolean {
        if (selection == null) return false
        for (pile in 0 until 4) if (moveToFoundation(pile)) return true
        // Prefer building on cards over taking an empty column.
        val order = (0 until 7).sortedBy { if (tableau[it].isEmpty()) 1 else 0 }
        for (col in order) if (moveToColumn(col)) return true
        return false
    }

    private fun canFoundation(card: Card) = foundations.any { pile -> pile.lastOrNull()?.let { it.suit == card.suit && card.rank == it.rank + 1 } ?: (card.rank == 1) }
    private fun columnAccepts(card: Card, except: Int?) = tableau.indices.any { col ->
        col != except && (tableau[col].lastOrNull()?.let { it.faceUp && it.isRed != card.isRed && it.rank == card.rank + 1 } ?: false)
    }

    /** Selects a source that has a useful move; the next tap on it plays the move. */
    fun hint() {
        if (state != GameState.Playing) return
        waste.lastOrNull()?.let { if (canFoundation(it)) { selection = Sel.Waste; hintFx(); return } }
        for (col in tableau.indices) tableau[col].lastOrNull()?.let { if (it.faceUp && canFoundation(it)) { selection = Sel.Tableau(col, tableau[col].size - 1); hintFx(); return } }
        for (col in tableau.indices) {
            val start = tableau[col].indexOfFirst { it.faceUp }
            if (start > 0 && columnAccepts(tableau[col][start], col)) { selection = Sel.Tableau(col, start); hintFx(); return }
        }
        waste.lastOrNull()?.let { if (columnAccepts(it, null) || (it.rank == 13 && tableau.any { c -> c.isEmpty() })) { selection = Sel.Waste; hintFx(); return } }
        selection = null; stockHint++; Haptics.tap(); Sfx.tap()
    }

    private fun hintFx() { Haptics.tap(); Sfx.tap() }

    /** All cards are face up and the stock is empty: the rest plays itself. */
    val canAutoComplete get() = state == GameState.Playing && stock.isEmpty() && waste.isEmpty() &&
        tableau.all { c -> c.all { it.faceUp } } && tableau.any { it.isNotEmpty() }

    /** One automatic step; returns false when nothing can move. */
    fun autoStep(): Boolean {
        if (!canAutoComplete) return false
        for (col in tableau.indices) {
            val card = tableau[col].lastOrNull() ?: continue
            val pile = foundations.indexOfFirst { p -> p.lastOrNull()?.let { it.suit == card.suit && card.rank == it.rank + 1 } ?: (card.rank == 1) }
            if (pile >= 0) { selection = Sel.Tableau(col, tableau[col].size - 1); moveToFoundation(pile); return true }
        }
        return false
    }

    private fun selectedCards(): List<Card> = when (val s = selection) {
        is Sel.Foundation -> foundations[s.pile].lastOrNull()?.let { listOf(it) } ?: emptyList()
        Sel.Waste -> waste.lastOrNull()?.let { listOf(it) } ?: emptyList()
        is Sel.Tableau -> tableau.getOrNull(s.col)?.let { if (s.index in it.indices) it.subList(s.index, it.size).toList() else emptyList() } ?: emptyList()
        null -> emptyList()
    }

    private fun removeSelected() {
        when (val s = selection) {
            is Sel.Foundation -> {
                foundations = foundations.mapIndexed { i, p -> if (i == s.pile) p.dropLast(1) else p }
                // Reverse the foundation bonus to prevent scoring by cycling a card.
                score = maxOf(0, score - 10)
            }
            Sel.Waste -> { waste = waste.dropLast(1); score += 5 }
            is Sel.Tableau -> {
                var col = tableau[s.col].subList(0, s.index).toList()
                if (col.isNotEmpty() && !col.last().faceUp) { col = col.dropLast(1) + col.last().copy(faceUp = true); score += 5 }
                tableau = tableau.mapIndexed { i, c -> if (i == s.col) col else c }
            }
            null -> {}
        }
    }

    fun tapColumn(col: Int, index: Int?) {
        if (state != GameState.Playing) return
        if (selection != null && moveToColumn(col)) return
        val sel = selection
        if (sel is Sel.Tableau && sel.col == col && sel.index == index) {
            // Tapping the same card again sends it to the best place.
            if (!autoMoveSelection()) selection = null
            return
        }
        if (index != null && tableau[col][index].faceUp) { selection = Sel.Tableau(col, index); Haptics.tap(); Sfx.tap() } else selection = null
    }

    private fun moveToColumn(col: Int): Boolean {
        val sel = selection
        if (sel is Sel.Tableau && sel.col == col) return false
        val cards = selectedCards()
        val first = cards.firstOrNull() ?: return false
        val target = tableau[col].lastOrNull()
        if (target != null) { if (!(target.faceUp && target.isRed != first.isRed && target.rank == first.rank + 1)) return false }
        else if (first.rank != 13) return false
        save()
        removeSelected()
        tableau = tableau.mapIndexed { i, c -> if (i == col) c + cards else c }
        selection = null
        Haptics.move(); Sfx.tap()
        return true
    }

    fun tapFoundation(pile: Int) {
        if (state != GameState.Playing) return
        if (selection == Sel.Foundation(pile)) { selection = null; Haptics.tap(); Sfx.tap(); return }
        if (moveToFoundation(pile)) return
        selection = if (foundations[pile].isEmpty()) null else Sel.Foundation(pile)
        Haptics.tap(); Sfx.tap()
    }

    private fun moveToFoundation(pile: Int): Boolean {
        // A selected foundation card can return to play, not to another foundation.
        if (selection is Sel.Foundation) return false
        val cards = selectedCards()
        val card = cards.singleOrNull() ?: return false
        val sel = selection
        if (sel is Sel.Tableau && sel.index != tableau[sel.col].size - 1) return false
        val top = foundations[pile].lastOrNull()
        if (top != null) { if (!(top.suit == card.suit && card.rank == top.rank + 1)) return false } else if (card.rank != 1) return false
        save()
        removeSelected()
        foundations = foundations.mapIndexed { i, p -> if (i == pile) p + card else p }
        score += 10
        selection = null
        if (foundations.sumOf { it.size } == 52) state = GameState.GameOver(won = true) else { Haptics.move(); Sfx.tap() }
        return true
    }

    fun isSelected(col: Int, index: Int): Boolean { val s = selection; return s is Sel.Tableau && s.col == col && index >= s.index }
}

@Composable
fun SolitaireScreen(onExit: () -> Unit) {
    val engine = remember { SolitaireEngine() }
    val pal = Pal.current
    var autoRun by remember { mutableStateOf(false) }
    LaunchedEffect(autoRun) {
        while (autoRun && engine.autoStep()) delay(90)
        autoRun = false
    }
    GameContainer(GameId.Solitaire, engine, onExit, timed = true) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val gap = 4.dp
            val cw = (maxWidth - gap * 6) / 7
            val ch = cw * CARD_RATIO
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (pile in 0 until 4) {
                        val top = engine.foundations[pile].lastOrNull()
                        if (top != null) CardView(top, cw, engine.selection == SolitaireEngine.Sel.Foundation(pile)) { engine.tapFoundation(pile) }
                        else CardSlot(cw, "A") { engine.tapFoundation(pile) }
                    }
                    Spacer(Modifier.weight(1f))
                    // Waste, fanned 10dp per card.
                    val shown = engine.waste.takeLast(3)
                    val step = cw * 10 / 50
                    Box(Modifier.width(cw + step * maxOf(shown.size - 1, 0)).height(ch).clickable(remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null) { engine.tapWaste() }) {
                        if (shown.isEmpty()) CardSlot(cw)
                        shown.forEachIndexed { i, c -> CardView(c, cw, i == shown.size - 1 && engine.selection == SolitaireEngine.Sel.Waste, Modifier.offset(x = step * i)) }
                    }
                    Spacer(Modifier.width(step))
                    val top = engine.stock.lastOrNull()
                    if (top != null) CardView(top, cw) { engine.tapStock() } else CardSlot(cw, "↻") { engine.tapStock() }
                }
                Spacer(Modifier.height(24.dp))
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                    val maxH = maxHeight.value
                    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                        for (col in 0 until 7) {
                            val cards = engine.tableau[col]
                            val offs = fanOffsets(cards, ch.value, maxH)
                            Box(Modifier.width(cw)) {
                                CardSlot(cw, if (cards.isEmpty()) "K" else "") { engine.tapColumn(col, null) }
                                cards.forEachIndexed { i, c -> CardView(c, cw, engine.isSelected(col, i), Modifier.offset(y = offs[i].dp)) { engine.tapColumn(col, i) } }
                            }
                        }
                    }
                }
                if (engine.canAutoComplete && !autoRun) Box(Modifier.align(Alignment.CenterHorizontally).clip(RoundedCornerShape(50)).background(pal.accent)
                    .clickable { autoRun = true }.padding(horizontal = 14.dp, vertical = 8.dp)) {
                    Text("✨ " + L10n.t("Auto-complete"), color = pal.onAccent, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
                CardGameControls(engine::hint, engine.canUndo, engine::undo)
            }
        }
    }
}
