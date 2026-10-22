package com.nurali.puzzlebox.games

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
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
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
import kotlinx.coroutines.delay

class FreeCellEngine : GameEngine {
    sealed interface Sel {
        data class Foundation(val pile: Int) : Sel
        data class Cascade(val col: Int, val index: Int) : Sel
        data class FreeCell(val i: Int) : Sel
    }

    class Snap(val cascades: List<List<Card>>, val freeCells: List<Card?>, val foundations: List<List<Card>>)

    var cascades by mutableStateOf(List(8) { listOf<Card>() })
    var freeCells by mutableStateOf(List<Card?>(4) { null })
    var foundations by mutableStateOf(List(4) { listOf<Card>() })
    var selection by mutableStateOf<Sel?>(null)
    override var state: GameState by mutableStateOf(GameState.Playing)
    override val score get() = foundations.sumOf { it.size } * 10

    private val history = ArrayList<Snap>()
    var historySize by mutableIntStateOf(0)
    val canUndo get() = state == GameState.Playing && historySize > 0

    init { deal() }

    override fun restart() = deal()

    private fun save() { history.add(Snap(cascades, freeCells, foundations)); historySize = history.size }

    fun undo() {
        if (!canUndo) return
        val p = history.removeAt(history.lastIndex); historySize = history.size
        cascades = p.cascades; freeCells = p.freeCells; foundations = p.foundations; selection = null
        Haptics.tap(); Sfx.tap()
    }

    private fun deal() {
        history.clear(); historySize = 0
        val deck = Card.deck().shuffled().toMutableList()
        cascades = (0 until 8).map { col -> (0 until if (col < 4) 7 else 6).map { deck.removeAt(deck.lastIndex) } }
        freeCells = List(4) { null }; foundations = List(4) { emptyList() }
        selection = null; state = GameState.Playing
    }

    /** A movable run is descending with alternating colours. */
    private fun isValidRun(col: Int, from: Int): Boolean {
        val pile = cascades[col]
        if (from !in pile.indices) return false
        for (i in from until pile.size - 1) if (!(pile[i].rank == pile[i + 1].rank + 1 && pile[i].isRed != pile[i + 1].isRed)) return false
        return true
    }

    private fun selectedCards(): List<Card> = when (val s = selection) {
        is Sel.Foundation -> foundations[s.pile].lastOrNull()?.let { listOf(it) } ?: emptyList()
        is Sel.Cascade -> cascades[s.col].let { it.subList(s.index, it.size).toList() }
        is Sel.FreeCell -> freeCells[s.i]?.let { listOf(it) } ?: emptyList()
        null -> emptyList()
    }

    private fun removeSelected() {
        when (val s = selection) {
            is Sel.Foundation -> foundations = foundations.mapIndexed { i, p -> if (i == s.pile) p.dropLast(1) else p }
            is Sel.Cascade -> cascades = cascades.mapIndexed { i, c -> if (i == s.col) c.subList(0, s.index).toList() else c }
            is Sel.FreeCell -> freeCells = freeCells.mapIndexed { i, c -> if (i == s.i) null else c }
            null -> {}
        }
    }

    /** Supermove capacity: (empty free cells + 1) × (empty cascades + 1). */
    private fun moveCapacity(target: Int): Int {
        val free = freeCells.count { it == null }
        val empty = cascades.withIndex().count { (i, p) -> p.isEmpty() && i != target }
        return (free + 1) * (empty + 1)
    }

    fun tapCascade(col: Int, index: Int?) {
        if (state != GameState.Playing) return
        if (selection != null && moveToCascade(col)) return
        val sel = selection
        if (sel is Sel.Cascade && sel.col == col && sel.index == index) { if (!autoMoveSelection()) selection = null; return }
        if (index != null && isValidRun(col, index)) { selection = Sel.Cascade(col, index); Haptics.tap(); Sfx.tap() } else selection = null
    }

    private fun moveToCascade(col: Int): Boolean {
        val sel = selection
        if (sel is Sel.Cascade && sel.col == col) return false
        val cards = selectedCards()
        val first = cards.firstOrNull() ?: return false
        if (cards.size > moveCapacity(col)) return false
        cascades[col].lastOrNull()?.let { if (!(it.rank == first.rank + 1 && it.isRed != first.isRed)) return false }
        save()
        removeSelected()
        cascades = cascades.mapIndexed { i, c -> if (i == col) c + cards else c }
        selection = null
        Haptics.move(); Sfx.tap()
        return true
    }

    fun tapFreeCell(i: Int) {
        if (state != GameState.Playing) return
        if (freeCells[i] != null) {
            if (selection == Sel.FreeCell(i)) { if (!autoMoveSelection()) selection = null }
            else if (selection == null) { selection = Sel.FreeCell(i); Haptics.tap(); Sfx.tap() }
            else selection = null
            return
        }
        // Empty cell: drop a single selected card here.
        val card = selectedCards().singleOrNull() ?: return
        save()
        removeSelected()
        freeCells = freeCells.mapIndexed { k, c -> if (k == i) card else c }
        selection = null
        Haptics.move(); Sfx.tap()
    }

    fun tapFoundation(pile: Int) {
        if (state != GameState.Playing) return
        if (selection == Sel.Foundation(pile)) { selection = null; Haptics.tap(); Sfx.tap(); return }
        if (moveToFoundation(pile)) return
        selection = if (foundations[pile].isEmpty()) null else Sel.Foundation(pile)
        Haptics.tap(); Sfx.tap()
    }

    private fun moveToFoundation(pile: Int): Boolean {
        if (selection is Sel.Foundation) return false
        val card = selectedCards().singleOrNull() ?: return false
        val top = foundations[pile].lastOrNull()
        if (top != null) { if (!(top.suit == card.suit && card.rank == top.rank + 1)) return false } else if (card.rank != 1) return false
        save()
        removeSelected()
        foundations = foundations.mapIndexed { i, p -> if (i == pile) p + card else p }
        selection = null
        if (foundations.sumOf { it.size } == 52) state = GameState.GameOver(won = true) else { Haptics.move(); Sfx.tap() }
        return true
    }

    fun isSelected(col: Int, index: Int): Boolean { val s = selection; return s is Sel.Cascade && s.col == col && index >= s.index }

    /** Foundation first, then a cascade with cards, then an empty cascade, then a free cell. */
    fun autoMoveSelection(): Boolean {
        if (selection == null) return false
        for (pile in 0 until 4) if (moveToFoundation(pile)) return true
        val order = cascades.indices.sortedBy { if (cascades[it].isEmpty()) 1 else 0 }
        for (col in order) if (moveToCascade(col)) return true
        if (selectedCards().size == 1 && selection is Sel.Cascade) {
            val cell = freeCells.indexOfFirst { it == null }
            if (cell >= 0) { tapFreeCell(cell); return true }
        }
        return false
    }

    /** A card is safe to send home when nothing could still need it as a base. */
    private fun isSafe(card: Card): Boolean {
        if (card.rank <= 2) return true
        val opposite = foundations.filter { p -> p.firstOrNull()?.let { it.isRed != card.isRed } ?: false }
        return opposite.size == 2 && opposite.all { (it.lastOrNull()?.rank ?: 0) >= card.rank - 1 }
    }

    /** Plays one safe card to a foundation; returns true if something moved. */
    fun autoStep(): Boolean {
        if (state != GameState.Playing || selection != null) return false
        val sources = cascades.indices.mapNotNull { c -> if (cascades[c].isEmpty()) null else Sel.Cascade(c, cascades[c].size - 1) } +
            freeCells.indices.mapNotNull { if (freeCells[it] == null) null else Sel.FreeCell(it) }
        for (src in sources) {
            selection = src
            val card = selectedCards().firstOrNull()
            if (card != null && isSafe(card) && (0 until 4).any { moveToFoundation(it) }) return true
            selection = null
        }
        return false
    }
}

@Composable
fun FreeCellScreen(onExit: () -> Unit) {
    val engine = remember { FreeCellEngine() }
    // Safe cards head to the foundations on their own, one by one.
    LaunchedEffect(engine.cascades, engine.freeCells, engine.foundations, engine.selection) {
        delay(140)
        engine.autoStep()
    }
    GameContainer(GameId.Freecell, engine, onExit, timed = true) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val gap = 4.dp
            val cw = (maxWidth - gap * 7) / 8
            val ch = cw * CARD_RATIO
            Column(Modifier.fillMaxSize()) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) {
                    for (i in 0 until 4) {
                        val card = engine.freeCells[i]
                        if (card != null) CardView(card, cw, engine.selection == FreeCellEngine.Sel.FreeCell(i)) { engine.tapFreeCell(i) } else CardSlot(cw) { engine.tapFreeCell(i) }
                    }
                    for (pile in 0 until 4) {
                        val top = engine.foundations[pile].lastOrNull()
                        if (top != null) CardView(top, cw, engine.selection == FreeCellEngine.Sel.Foundation(pile)) { engine.tapFoundation(pile) } else CardSlot(cw, "A") { engine.tapFoundation(pile) }
                    }
                }
                Spacer(Modifier.height(24.dp))
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                    val maxH = maxHeight.value
                    Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                        for (col in 0 until 8) {
                            val cards = engine.cascades[col]
                            val offs = fanOffsets(cards, ch.value, maxH)
                            Box(Modifier.width(cw)) {
                                CardSlot(cw) { engine.tapCascade(col, null) }
                                cards.forEachIndexed { i, c -> CardView(c, cw, engine.isSelected(col, i), Modifier.offset(y = offs[i].dp)) { engine.tapCascade(col, i) } }
                            }
                        }
                    }
                }
                CardGameControls(null, engine.canUndo, engine::undo)
            }
        }
    }
}
