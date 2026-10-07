package com.nurali.puzzlebox

data class Card(val suit: Int, val rank: Int, val faceUp: Boolean = true, val id: Int = suit * 13 + rank) {
    val red get() = suit == 1 || suit == 2
    val high get() = if (rank == 1) 14 else rank
    val label get() = (when (rank) { 1 -> "A"; 11 -> "J"; 12 -> "Q"; 13 -> "K"; else -> rank.toString() }) + "♠♥♦♣"[suit]
}
fun deck() = (0..3).flatMap { s -> (1..13).map { Card(s, it) } }.shuffled().toMutableList()
data class CardSelection(val area: Int, val col: Int = 0, val index: Int = 0) // 0 tableau, 1 foundation, 2 cell, 3 waste

class PatienceEngine(val game: Game) : Engine() {
    val spider get() = game == Game.spiderSolitaire
    val freecell get() = game == Game.freecell
    val columns get() = if (spider) 10 else if (freecell) 8 else 7
    var tableau = mutableListOf<MutableList<Card>>()
    var foundations = MutableList(4) { mutableListOf<Card>() }
    var cells = MutableList<Card?>(4) { null }
    var stock = mutableListOf<Card>(); var waste = mutableListOf<Card>()
    var selection: CardSelection? = null; var runs = 0
    private data class Snapshot(val tableau: List<List<Card>>, val foundations: List<List<Card>>, val cells: List<Card?>,
        val stock: List<Card>, val waste: List<Card>, val runs: Int, val score: Int)
    private val history = mutableListOf<Snapshot>()
    override val canUndo get() = history.isNotEmpty() && phase == Phase.PLAYING
    init { restart() }
    override fun restart() {
        reset(); history.clear(); selection = null; runs = 0
        val cards = if (spider) (0..7).flatMap { copy -> (1..13).map { Card(0, it, false, copy * 13 + it) } }.shuffled().toMutableList() else deck()
        tableau = MutableList(columns) { col ->
            val count = if (spider) (if (col < 4) 6 else 5) else if (freecell) (if (col < 4) 7 else 6) else col + 1
            MutableList(count) { i -> cards.removeAt(cards.lastIndex).copy(faceUp = freecell || i == count - 1) }
        }
        stock = cards.map { it.copy(faceUp = false) }.toMutableList(); waste.clear()
        foundations = MutableList(4) { mutableListOf() }; cells = MutableList(4) { null }; changed()
    }
    private fun save() { history.add(Snapshot(tableau.map { it.toList() }, foundations.map { it.toList() }, cells.toList(), stock.toList(), waste.toList(), runs, score)) }
    override fun undo() {
        if (!canUndo) return
        val s = history.removeAt(history.lastIndex)
        tableau = s.tableau.map { it.toMutableList() }.toMutableList(); foundations = s.foundations.map { it.toMutableList() }.toMutableList()
        cells = s.cells.toMutableList(); stock = s.stock.toMutableList(); waste = s.waste.toMutableList(); runs = s.runs; score = s.score
        selection = null; message = ""; changed()
    }
    fun draw() {
        if (phase != Phase.PLAYING) return
        if (spider) {
            if (stock.isEmpty()) return
            if (tableau.any { it.isEmpty() }) { say("Fill every empty column before dealing"); changed(); return }
            save(); repeat(10) { tableau[it].add(stock.removeAt(stock.lastIndex).copy(faceUp = true)) }; completeRuns()
        } else if (!freecell) {
            if (stock.isEmpty() && waste.isEmpty()) return
            save()
            if (stock.isNotEmpty()) waste.add(stock.removeAt(stock.lastIndex).copy(faceUp = true))
            else { stock = waste.asReversed().map { it.copy(faceUp = false) }.toMutableList(); waste.clear() }
        }
        selection = null; message = ""; changed()
    }
    private fun cards(): List<Card> {
        val s = selection ?: return emptyList()
        return when (s.area) { 0 -> tableau[s.col].drop(s.index); 1 -> foundations[s.col].takeLast(1); 2 -> listOfNotNull(cells[s.col]); else -> waste.takeLast(1) }
    }
    private fun flip(col: Int) {
        val p = tableau[col]
        if (p.isNotEmpty() && !p.last().faceUp) { p[p.lastIndex] = p.last().copy(faceUp = true); if (!spider) score += 5 }
    }
    private fun remove() {
        val s = selection ?: return
        when (s.area) {
            0 -> { tableau[s.col].subList(s.index, tableau[s.col].size).clear(); flip(s.col) }
            1 -> { foundations[s.col].removeAt(foundations[s.col].lastIndex); if (!freecell) score = maxOf(0, score - 10) }
            2 -> cells[s.col] = null
            3 -> { waste.removeAt(waste.lastIndex); score += 5 }
        }
    }
    private fun validRun(col: Int, index: Int): Boolean {
        val run = tableau[col].drop(index)
        return run.isNotEmpty() && run.all { it.faceUp } && run.zipWithNext().all { (a, b) -> a.rank == b.rank + 1 && (spider || a.red != b.red) }
    }
    fun tapColumn(col: Int, index: Int? = null) {
        if (phase != Phase.PLAYING) return
        val selected = selection; val moving = cards(); val top = tableau[col].lastOrNull()
        val different = selected != null && (selected.area != 0 || selected.col != col)
        val first = moving.firstOrNull()
        val capacity = if (freecell) (cells.count { it == null } + 1) * (1 shl tableau.indices.count { it != col && tableau[it].isEmpty() }) else Int.MAX_VALUE
        if (different && first != null && moving.size <= capacity &&
            (if (top == null) freecell || spider || first.rank == 13 else top.faceUp && top.rank == first.rank + 1 && (spider || top.red != first.red))) {
            save(); remove(); tableau[col].addAll(moving); selection = null
            if (spider) completeRuns()
            if (freecell) score = foundations.sumOf { it.size } * 10
        } else {
            val next = index?.takeIf { it in tableau[col].indices && validRun(col, it) }?.let { CardSelection(0, col, it) }
            selection = next.takeUnless { it == selected }
        }
        message = ""; changed()
    }
    fun tapFoundation(col: Int) {
        if (phase != Phase.PLAYING || spider) return
        val moving = cards(); val card = moving.singleOrNull(); val top = foundations[col].lastOrNull()
        if (card != null && selection?.area != 1 && (if (top == null) card.rank == 1 else card.suit == top.suit && card.rank == top.rank + 1)) {
            save(); remove(); foundations[col].add(card); selection = null
            if (freecell) score = foundations.sumOf { it.size } * 10 else score += 10
            if (foundations.sumOf { it.size } == 52) phase = Phase.WON
        } else {
            val next = CardSelection(1, col)
            selection = next.takeIf { foundations[col].isNotEmpty() && selection != next }
        }
        changed()
    }
    fun tapCell(col: Int) {
        if (!freecell || phase != Phase.PLAYING) return
        val card = cards().singleOrNull()
        if (cells[col] == null && card != null) { save(); remove(); cells[col] = card; selection = null; score = foundations.sumOf { it.size } * 10 }
        else { val next = CardSelection(2, col); selection = next.takeIf { cells[col] != null && selection != next } }
        changed()
    }
    fun tapWaste() { if (phase == Phase.PLAYING) { val next = CardSelection(3); selection = next.takeIf { waste.isNotEmpty() && selection != next }; changed() } }
    private fun completeRuns() {
        for (col in tableau.indices) {
            while (tableau[col].size >= 13) {
                val run = tableau[col].takeLast(13)
                if (!run.all { it.faceUp } || run.map { it.rank } != (13 downTo 1).toList()) break
                repeat(13) { tableau[col].removeAt(tableau[col].lastIndex) }; runs++; flip(col)
            }
        }
        score = runs * 100; if (runs == 8) phase = Phase.WON
    }
}
