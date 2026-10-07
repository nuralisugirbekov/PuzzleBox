package com.nurali.puzzlebox

import android.content.Context
import org.json.JSONArray

/** Static, independently validated positions: no network and no approximate move generator. */
class ChessEngine(context: Context) : Engine() {
    data class Puzzle(val id: Int, val fen: String, val best: String, val solutions: List<String>, val legal: List<String>)
    private fun JSONArray.strings() = List(length()) { getString(it) }
    private val bank = JSONArray(context.assets.open("mates.json").bufferedReader().use { it.readText() }).let { a ->
        List(a.length()) { val p = a.getJSONObject(it); Puzzle(p.getInt("source_id"), p.getString("fen"),
            p.getString("best"), p.getJSONArray("solutions").strings(), p.getJSONArray("legal_moves").strings()) }
    }
    private var puzzles = bank.shuffled(); private var index = 0
    val puzzle get() = puzzles[index]
    var board = CharArray(64) { ' ' }; var selected: Int? = null
    var targets = emptySet<Int>(); var solved = 0
    private var wait = 0L; private var previous: CharArray? = null
    var moveFrom: Int? = null; var moveTo: Int? = null
    var animation = 1f; private var movingPiece = ' '
    val movingGlyph get() = movingPiece
    init { restart() }
    override fun restart() { reset(); puzzles = bank.shuffled(); index = 0; solved = 0; load(); changed() }
    private fun load() {
        board = CharArray(64) { ' ' }; var i = 0
        for (c in puzzle.fen.substringBefore(' ')) when {
            c == '/' -> Unit
            c.isDigit() -> i += c.digitToInt()
            else -> board[i++] = c
        }
        selected = null; targets = emptySet(); previous = null; wait = 0; error = false; returning = false
        moveFrom = null; moveTo = null; animation = 1f; say("White to move — find the mate!")
    }
    private fun square(s: String) = (8 - s[1].digitToInt()) * 8 + (s[0] - 'a')
    private fun uci(i: Int) = "${'a' + i % 8}${8 - i / 8}"
    fun tap(i: Int) {
        if (phase != Phase.PLAYING || wait > 0) return
        val from = selected
        if (from != null && i in targets) {
            val prefix = uci(from) + uci(i)
            val solution = (listOf(puzzle.best) + puzzle.solutions).firstOrNull { it.startsWith(prefix) }
            val move = solution ?: puzzle.legal.first { it.startsWith(prefix) }
            val old = board.copyOf()
            apply(move); selected = null; targets = emptySet()
            if (solution == null) { previous = old; error = true; say("Not the winning move — try again"); wait = 800 }
            else { error = false; solved++; score = solved * 100; say("Checkmate! 🎉"); wait = 1500 }
        } else if (board[i].isUpperCase()) {
            selected = if (from == i) null else i
            targets = if (selected == null) emptySet() else puzzle.legal.filter { it.startsWith(uci(i)) }.map { square(it.substring(2, 4)) }.toSet()
            error = false; say("White to move — find the mate!")
        } else if (from != null) { error = true; say("Illegal move — choose a highlighted square") }
        changed()
    }
    private fun apply(move: String) {
        val from = square(move.take(2)); val to = square(move.substring(2, 4)); val piece = board[from]
        if (piece == 'P' && from % 8 != to % 8 && board[to] == ' ') board[from / 8 * 8 + to % 8] = ' '
        if (piece == 'K' && kotlin.math.abs(from - to) == 2) {
            val rook = from / 8 * 8 + if (to > from) 7 else 0
            board[if (to > from) to - 1 else to + 1] = board[rook]; board[rook] = ' '
        }
        board[to] = if (move.length == 5) move[4].uppercaseChar() else piece; board[from] = ' '
        moveFrom = from; moveTo = to; movingPiece = board[to]; animation = 0f
    }
    override fun tick(ms: Long) {
        if (animation < 1f) { animation = (animation + ms / 200f).coerceAtMost(1f); changed() }
        if (wait <= 0) return
        wait -= ms
        if (wait > 0) return
        val old = previous
        if (old != null) {
            val from = moveFrom; val to = moveTo
            board = old; previous = null
            moveFrom = to; moveTo = from; movingPiece = from?.let { old[it] } ?: ' '; animation = 0f
            // Block input until the return animation has finished as well.
            wait = 200; returning = true
        } else if (returning) { returning = false; moveFrom = null; moveTo = null }
        else { index++; if (index == puzzles.size) { puzzles = bank.shuffled(); index = 0 }; load() }
        changed()
    }
    private var returning = false
}
