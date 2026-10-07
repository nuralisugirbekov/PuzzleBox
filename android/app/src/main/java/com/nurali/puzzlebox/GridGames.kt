package com.nurali.puzzlebox

import kotlin.math.abs
import kotlin.random.Random

data class Cell(val r: Int, val c: Int)
fun neighbors(index: Int, size: Int) = (-1..1).flatMap { dr -> (-1..1).mapNotNull { dc ->
    val r = index / size + dr; val c = index % size + dc
    if ((dr != 0 || dc != 0) && r in 0 until size && c in 0 until size) r * size + c else null
} }

class MinesEngine : Engine() {
    var mines = emptySet<Int>(); var revealed = mutableSetOf<Int>(); var flags = mutableSetOf<Int>()
    var flagMode = false
    init { restart() }
    override fun restart() { reset(); mines = emptySet(); revealed = mutableSetOf(); flags = mutableSetOf(); flagMode = false; changed() }
    fun adjacent(i: Int) = neighbors(i, 9).count { it in mines }
    fun tap(i: Int, forceFlag: Boolean = false) {
        if (phase != Phase.PLAYING || i in revealed) return
        if (flagMode || forceFlag) { if (!flags.add(i)) flags.remove(i); changed(); return }
        if (i in flags) return
        if (mines.isEmpty()) mines = (0..80).filter { it != i && it !in neighbors(i, 9) }.shuffled().take(10).toSet()
        if (i in mines) { phase = Phase.LOST; revealed.addAll(mines); changed(); return }
        val queue = ArrayDeque<Int>(); queue.add(i)
        while (queue.isNotEmpty()) {
            val cell = queue.removeFirst()
            if (cell in revealed || cell in mines || cell in flags) continue
            revealed.add(cell)
            if (adjacent(cell) == 0) queue.addAll(neighbors(cell, 9))
        }
        score = revealed.size * 2
        if (revealed.size == 71) { score += 100; phase = Phase.WON }
        changed()
    }
}

class SudokuEngine : Engine() {
    var solution = IntArray(36); var board = IntArray(36); var given = emptySet<Int>()
    var selected: Int? = null; var mistakes = 0
    init { restart() }
    override fun restart() {
        reset(); selected = null; mistakes = 0
        val digits = (1..6).shuffled()
        val rows = (0..2).shuffled().flatMap { band -> (0..1).shuffled().map { band * 2 + it } }
        val cols = (0..1).shuffled().flatMap { stack -> (0..2).shuffled().map { stack * 3 + it } }
        solution = IntArray(36) { val r = rows[it / 6]; digits[(r * 3 + r / 2 + cols[it % 6]) % 6] }
        board = solution.copyOf()
        // Remove clues only when the puzzle still has a unique solution.
        for (i in (0..35).shuffled()) {
            if (board.count { it != 0 } <= 16) break
            val old = board[i]; board[i] = 0
            if (countSolutions(board.copyOf()) != 1) board[i] = old
        }
        given = (0..35).filter { board[it] != 0 }.toSet(); changed()
    }
    private fun countSolutions(b: IntArray): Int {
        var best = -1; var options = emptyList<Int>()
        for (i in b.indices) if (b[i] == 0) {
            val r = i / 6; val c = i % 6
            val possible = (1..6).filter { v -> (0..35).none { j -> b[j] == v &&
                (j / 6 == r || j % 6 == c || (j / 6 / 2 == r / 2 && j % 6 / 3 == c / 3)) } }
            if (possible.isEmpty()) return 0
            if (best < 0 || possible.size < options.size) { best = i; options = possible }
        }
        if (best < 0) return 1
        var count = 0
        for (v in options) { b[best] = v; count += countSolutions(b); if (count >= 2) break }
        b[best] = 0; return count.coerceAtMost(2)
    }
    fun enter(value: Int) {
        val i = selected ?: return
        if (phase != Phase.PLAYING || i in given || board[i] == value) return
        board[i] = value
        if (value != 0 && value != solution[i]) mistakes++
        score = ((0..35).count { it !in given && board[it] == solution[it] } * 10 - mistakes * 5).coerceAtLeast(0)
        if (board.contentEquals(solution)) phase = Phase.WON
        changed()
    }
}

class SnakeEngine : Engine() {
    var body = listOf(Cell(7, 6), Cell(7, 5), Cell(7, 4))
    var food = Cell(0, 0)
    private var direction = Cell(0, 1); private var pending = direction; private var clock = 0L
    init { restart() }
    override fun restart() { reset(); body = listOf(Cell(7, 6), Cell(7, 5), Cell(7, 4)); direction = Cell(0, 1); pending = direction; clock = 0; spawn(); changed() }
    private fun spawn() {
        val free = (0..195).map { Cell(it / 14, it % 14) }.filter { it !in body }
        if (free.isEmpty()) phase = Phase.WON else food = free.random()
    }
    fun turn(dr: Int, dc: Int) { if (dr != -direction.r || dc != -direction.c) pending = Cell(dr, dc) }
    override fun tick(ms: Long) {
        clock += ms
        if (clock < maxOf(90, 220 - score)) return
        clock = 0; direction = pending
        val next = Cell(body[0].r + direction.r, body[0].c + direction.c)
        val grow = next == food; val rest = if (grow) body else body.dropLast(1)
        if (next.r !in 0..13 || next.c !in 0..13 || next in rest) phase = Phase.LOST
        else { body = listOf(next) + rest; if (grow) { score += 10; spawn() } }
        changed()
    }
}

class WaterEngine : Engine() {
    var tubes = mutableListOf<MutableList<Int>>(); var selected: Int? = null; var moves = 0
    private val history = mutableListOf<List<List<Int>>>()
    override val canUndo get() = history.isNotEmpty() && phase == Phase.PLAYING
    init { restart() }
    override fun restart() {
        reset(); selected = null; moves = 0; history.clear()
        do { tubes = List(24) { it / 4 }.shuffled().chunked(4).map { it.toMutableList() }.toMutableList() }
        while (tubes.any { it.distinct().size == 1 })
        repeat(2) { tubes.add(mutableListOf()) }; updateScore(); changed()
    }
    private fun updateScore() {
        val complete = tubes.count { it.size == 4 && it.distinct().size == 1 }
        score = complete * 50 + if (complete == 6) maxOf(0, 200 - moves * 3) else 0
        if (complete == 6) phase = Phase.WON
    }
    fun tap(i: Int) {
        if (phase != Phase.PLAYING) return
        val source = selected
        if (source == null) { selected = i.takeIf { tubes[it].isNotEmpty() }; changed(); return }
        if (source == i) { selected = null; changed(); return }
        val color = tubes[source].last()
        if (tubes[i].size < 4 && (tubes[i].isEmpty() || tubes[i].last() == color)) {
            history.add(tubes.map { it.toList() })
            val amount = minOf(tubes[source].asReversed().takeWhile { it == color }.size, 4 - tubes[i].size)
            repeat(amount) { tubes[source].removeAt(tubes[source].lastIndex); tubes[i].add(color) }
            moves++; selected = null; updateScore()
        } else selected = i.takeIf { tubes[it].isNotEmpty() }
        changed()
    }
    override fun undo() { if (canUndo) { tubes = history.removeAt(history.lastIndex).map { it.toMutableList() }.toMutableList(); selected = null; updateScore(); changed() } }
}

data class BlockPiece(val cells: List<Cell>, val color: Int)
class BlockEngine : Engine() {
    var board = IntArray(64) { -1 }; var tray = mutableListOf<BlockPiece?>(); var selected: Int? = null
    private val shapes = listOf(listOf(Cell(0, 0)), listOf(Cell(0, 0), Cell(0, 1)), listOf(Cell(0, 0), Cell(1, 0)),
        List(3) { Cell(0, it) }, List(3) { Cell(it, 0) }, List(4) { Cell(0, it) }, List(4) { Cell(it, 0) },
        listOf(Cell(0, 0), Cell(0, 1), Cell(1, 0), Cell(1, 1)), listOf(Cell(0, 0), Cell(1, 0), Cell(1, 1)),
        listOf(Cell(0, 1), Cell(1, 0), Cell(1, 1)), listOf(Cell(0, 0), Cell(0, 1), Cell(1, 1)),
        listOf(Cell(0, 0), Cell(0, 1), Cell(1, 0)), listOf(Cell(0, 0), Cell(1, 0), Cell(2, 0), Cell(2, 1)),
        listOf(Cell(0, 0), Cell(0, 1), Cell(0, 2), Cell(1, 0)))
    init { restart() }
    private fun refill() { tray = MutableList(3) { BlockPiece(shapes.random(), Random.nextInt(6)) } }
    override fun restart() { reset(); board = IntArray(64) { -1 }; refill(); selected = null; changed() }
    fun fits(piece: BlockPiece, i: Int) = piece.cells.all { val r = i / 8 + it.r; val c = i % 8 + it.c; r in 0..7 && c in 0..7 && board[r * 8 + c] < 0 }
    fun place(i: Int) {
        if (phase != Phase.PLAYING) return
        val slot = selected ?: return; val piece = tray[slot] ?: return
        if (!fits(piece, i)) return
        piece.cells.forEach { board[(i / 8 + it.r) * 8 + i % 8 + it.c] = piece.color }
        score += piece.cells.size; tray[slot] = null; selected = null
        val rows = (0..7).filter { r -> (0..7).all { c -> board[r * 8 + c] >= 0 } }
        val cols = (0..7).filter { c -> (0..7).all { r -> board[r * 8 + c] >= 0 } }
        rows.forEach { r -> (0..7).forEach { board[r * 8 + it] = -1 } }
        cols.forEach { c -> (0..7).forEach { board[it * 8 + c] = -1 } }
        val count = rows.size + cols.size; score += count * count * 10
        if (tray.all { it == null }) refill()
        if (tray.filterNotNull().none { p -> (0..63).any { fits(p, it) } }) phase = Phase.LOST
        changed()
    }
}

class MatchEngine : Engine() {
    var board = IntArray(36); var selected: Int? = null; var moves = 20
    private var delay = 0L; private var reverse: Pair<Int, Int>? = null; private var cascade = 1
    var matches = emptySet<Int>()
    init { restart() }
    override fun restart() { reset(); moves = 20; selected = null; delay = 0; reverse = null; matches = emptySet(); fresh(); changed() }
    private fun fresh() {
        do { board = IntArray(36) { -1 }; for (i in board.indices) {
            val choices = (0..4).filter { k -> !(i % 6 >= 2 && board[i - 1] == k && board[i - 2] == k) && !(i >= 12 && board[i - 6] == k && board[i - 12] == k) }
            board[i] = choices.random()
        } } while (!hasMove())
    }
    private fun findMatches(): Set<Int> {
        val out = mutableSetOf<Int>()
        for (i in 0..35) {
            if (i % 6 < 4 && board[i] == board[i + 1] && board[i] == board[i + 2]) out.addAll(listOf(i, i + 1, i + 2))
            if (i / 6 < 4 && board[i] == board[i + 6] && board[i] == board[i + 12]) out.addAll(listOf(i, i + 6, i + 12))
        }; return out
    }
    private fun swap(a: Int, b: Int) { val value = board[a]; board[a] = board[b]; board[b] = value }
    private fun hasMove(): Boolean {
        for (i in 0..35) for (j in listOf(i + 1, i + 6)) {
            if (j > 35 || abs(i / 6 - j / 6) + abs(i % 6 - j % 6) != 1) continue
            swap(i, j); val found = findMatches().isNotEmpty(); swap(i, j); if (found) return true
        }; return false
    }
    fun tap(i: Int) {
        if (phase != Phase.PLAYING || delay > 0) return
        val source = selected
        if (source != null && abs(source / 6 - i / 6) + abs(source % 6 - i % 6) == 1) {
            swap(source, i); selected = null; matches = findMatches(); cascade = 1
            if (matches.isEmpty()) reverse = source to i else moves--
            delay = 250
        } else selected = i.takeUnless { it == source }
        changed()
    }
    override fun tick(ms: Long) {
        if (delay <= 0) return
        delay -= ms; if (delay > 0) return
        reverse?.let { swap(it.first, it.second); reverse = null; changed(); return }
        score += matches.size * 10
        for (c in 0..5) {
            val keep = (0..5).map { it * 6 + c }.filter { it !in matches }.map { board[it] }
            val column = List(6 - keep.size) { Random.nextInt(5) } + keep
            column.forEachIndexed { r, k -> board[r * 6 + c] = k }
        }
        matches = findMatches()
        if (matches.isNotEmpty()) { cascade++; delay = 280 }
        else if (moves == 0) phase = Phase.LOST else if (!hasMove()) fresh()
        changed()
    }
}
