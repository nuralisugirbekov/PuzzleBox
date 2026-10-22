package com.nurali.puzzlebox.games

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nurali.puzzlebox.core.GameId
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Sfx
import com.nurali.puzzlebox.game.GameContainer
import com.nurali.puzzlebox.game.GameState
import com.nurali.puzzlebox.games.kit.FrameGame
import com.nurali.puzzlebox.games.kit.FrameLoop
import com.nurali.puzzlebox.ui.Pal
import org.json.JSONArray
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max

enum class PieceType(val white: String, val black: String) {
    Pawn("♙", "♟"), Knight("♘", "♞"), Bishop("♗", "♝"), Rook("♖", "♜"), Queen("♕", "♛"), King("♔", "♚");
    companion object {
        fun fromFen(c: Char) = when (c) { 'p' -> Pawn; 'n' -> Knight; 'b' -> Bishop; 'r' -> Rook; 'q' -> Queen; 'k' -> King; else -> null }
    }
}

class ChessPiece(val isWhite: Boolean, val type: PieceType)

class ChessPuzzle(val title: String, val fen: String, val line: List<String>, val solutions: List<String> = emptyList())

class CheckmateEngine(private val loadLibrary: () -> List<ChessPuzzle>) : FrameGame {
    companion object {
        val durations = listOf(30, 60, 120)
        const val TIME_BONUS = 5.0

        private fun fallback() = listOf(
            ChessPuzzle("Mate in 1", "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w", listOf("e1e8")),
            ChessPuzzle("Mate in 1", "6k1/5p1p/7Q/8/8/8/1B3PPP/6K1 w", listOf("h6g7")),
            ChessPuzzle("Mate in 1", "6rk/6pp/8/6N1/8/8/8/6K1 w", listOf("g5f7")),
            ChessPuzzle("Mate in 1", "3k4/R7/8/8/8/8/8/1R4K1 w", listOf("b1b8")),
        )

        /** Validated mate-in-one diagrams, bundled for offline play. */
        fun loadFromAssets(context: android.content.Context): List<ChessPuzzle> = runCatching {
            val arr = JSONArray(context.assets.open("MateInOne.json").bufferedReader().use { it.readText() })
            val seen = HashSet<String>(); val out = ArrayList<ChessPuzzle>()
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val fen = o.getString("fen"); val fields = fen.split(" ")
                if (fields.size != 6 || fields[1] != "w") continue
                if (!seen.add(fields[0])) continue
                val sols = o.optJSONArray("solutions")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
                out.add(ChessPuzzle("Mate in 1", fen, listOf(o.getString("best")), sols))
            }
            out
        }.getOrDefault(emptyList())

        private fun parseFen(fen: String): Array<ChessPiece?> {
            val board = arrayOfNulls<ChessPiece>(64)
            val placement = fen.split(" ").firstOrNull() ?: return board
            var index = 0
            for (ch in placement) {
                if (index >= 64) break
                if (ch == '/') continue
                if (ch.isDigit()) index += ch.digitToInt()
                else PieceType.fromFen(ch.lowercaseChar())?.let { board[index] = ChessPiece(ch.isUpperCase(), it); index++ }
            }
            return board
        }

        private fun squareIndex(file: Char, rank: Char): Int? {
            val f = "abcdefgh".indexOf(file); val r = rank.digitToIntOrNull() ?: return null
            if (f < 0 || r !in 1..8) return null
            return (8 - r) * 8 + f
        }

        class Move(val from: Int, val to: Int, val promotion: PieceType?)

        fun parseMove(m: String): Move? {
            if (m.length != 4 && m.length != 5) return null
            val from = squareIndex(m[0], m[1]) ?: return null
            val to = squareIndex(m[2], m[3]) ?: return null
            val promo = if (m.length == 5) { if (m[4] !in "qrbn") return null; PieceType.fromFen(m[4]) } else null
            return Move(from, to, promo)
        }
    }

    var hasStarted by mutableStateOf(false)
    override var score by mutableIntStateOf(0)
    override var state: GameState by mutableStateOf(GameState.Playing)
    var remainingTime by mutableDoubleStateOf(30.0)
    var solvedCount by mutableIntStateOf(0)
    var streak by mutableIntStateOf(0)
    var message by mutableStateOf("")
    var hasMoveError by mutableStateOf(false)
    var version by mutableIntStateOf(0)
    var bonusFlash by mutableIntStateOf(0)
    var awaitingBot = false
    var hintSquare by mutableStateOf<Int?>(null)

    private var puzzles = listOf<ChessPuzzle>()
    private var puzzleIndex = 0
    private var step = 0
    private var attempts = 0
    var board: Array<ChessPiece?> = arrayOfNulls(64)
    var selected by mutableStateOf<Int?>(null)
    var targets = setOf<Int>()
    var lastMove: Pair<Int, Int>? = null
    private val scheduled = ArrayList<Pair<Double, () -> Unit>>()

    val puzzle get() = puzzles[puzzleIndex]
    val secondsLeft get() = ceil(remainingTime).toInt()

    init { restart() }

    fun start(seconds: Int) {
        if (seconds !in durations || hasStarted) return
        remainingTime = seconds.toDouble(); hasStarted = true
    }

    override fun restart() {
        hasStarted = false; scheduled.clear()
        val lib = loadLibrary().shuffled()
        puzzles = lib.ifEmpty { fallback().shuffled() }
        puzzleIndex = 0; score = 0; solvedCount = 0; streak = 0; remainingTime = 30.0
        state = GameState.Playing
        loadPuzzle()
    }

    private fun loadPuzzle() {
        hasMoveError = false; board = parseFen(puzzle.fen); step = 0; attempts = 0
        selected = null; targets = emptySet(); awaitingBot = false; hintSquare = null; lastMove = null
        message = L10n.t("White to move — find the mate!")
        version++
    }

    private fun later(seconds: Double, action: () -> Unit) { scheduled.add(seconds to action) }

    override fun advance(dt: Double) {
        if (hasStarted && state == GameState.Playing) {
            val d = minOf(dt, 0.1)
            remainingTime = max(0.0, remainingTime - d)
            if (remainingTime <= 0) { scheduled.clear(); selected = null; targets = emptySet(); awaitingBot = false; state = GameState.GameOver(won = true); Sfx.win(); return }
            if (scheduled.isNotEmpty()) {
                val due = ArrayList<() -> Unit>()
                val it = scheduled.listIterator()
                while (it.hasNext()) { val (t, a) = it.next(); if (t - d <= 0) { due.add(a); it.remove() } else it.set((t - d) to a) }
                due.forEach { it() }
            }
        }
    }

    /** Highlights the piece that starts the winning move; the mate is then worth half. */
    fun hint() {
        if (!hasStarted || state != GameState.Playing || awaitingBot || hintSquare != null) return
        val move = acceptedMoves().mapNotNull { parseMove(it) }.firstOrNull() ?: return
        hintSquare = move.from; streak = 0
        Haptics.tap(); Sfx.tap()
    }

    fun tap(square: Int) {
        if (!hasStarted || state != GameState.Playing || awaitingBot || square !in board.indices) return
        val sel = selected
        if (sel != null && square in targets) { tryMove(sel, square); return }
        val piece = board[square]
        if (piece != null && piece.isWhite) {
            hasMoveError = false; message = L10n.t("White to move — find the mate!")
            selected = square; targets = legalMoves(square); Haptics.tap(); Sfx.tap()
        } else {
            if (selected != null) { reportMoveError(L10n.t("Illegal move — choose a highlighted square")); return }
            selected = null; targets = emptySet()
        }
        version++
    }

    private fun reportMoveError(text: String) { attempts++; hasMoveError = true; message = text; Haptics.error(); Sfx.wrong(); version++ }

    private fun acceptedMoves(): List<String> {
        if (step !in puzzle.line.indices) return emptyList()
        return if (step == 0 && puzzle.line.size == 1) listOf(puzzle.line[0]) + puzzle.solutions else listOf(puzzle.line[step])
    }

    private fun tryMove(from: Int, to: Int) {
        if (state != GameState.Playing || awaitingBot || board[from]?.isWhite != true || to !in legalMoves(from) || step !in puzzle.line.indices) return
        selected = null; targets = emptySet()
        val solution = acceptedMoves().mapNotNull { parseMove(it) }.firstOrNull { it.from == from && it.to == to }
        if (solution == null) {
            val previous = board.copyOf()
            awaitingBot = true
            // Show the attempted move, including captures and pawn promotion.
            val promo = if (board[from]?.type == PieceType.Pawn && to / 8 == 0) PieceType.Queen else null
            apply(from, to, promo)
            reportMoveError(L10n.t("Not the winning move — try again"))
            later(0.8) { board = previous; lastMove = null; awaitingBot = false; version++ }
            return
        }
        hasMoveError = false
        apply(from, to, solution.promotion)
        step++
        Haptics.move(); Sfx.tap()
        if (step == puzzle.line.size) puzzleSolved()
        else {
            // Black's stored reply, then back to the user.
            awaitingBot = true; message = L10n.t("Black replies…")
            later(0.6) {
                val reply = puzzle.line.getOrNull(step)?.let { parseMove(it) }
                if (reply != null && board[reply.from]?.isWhite == false) {
                    apply(reply.from, reply.to, reply.promotion); step++; awaitingBot = false
                    message = L10n.t("Now finish it — mate!"); version++
                }
            }
        }
    }

    private fun apply(from: Int, to: Int, promotion: PieceType?) {
        val piece = board[from] ?: return
        lastMove = from to to
        // En passant: a diagonal pawn move to an empty square removes the pawn beside it.
        if (piece.type == PieceType.Pawn && from % 8 != to % 8 && board[to] == null) board[(from / 8) * 8 + to % 8] = null
        if (piece.type == PieceType.King && abs(from % 8 - to % 8) == 2) {
            val rookFrom = (from / 8) * 8 + (if (to > from) 7 else 0)
            val rookTo = if (to > from) to - 1 else to + 1
            board[rookTo] = board[rookFrom]; board[rookFrom] = null
        }
        board[to] = ChessPiece(piece.isWhite, promotion ?: piece.type)
        board[from] = null
        version++
    }

    private fun puzzleSolved() {
        awaitingBot = true; solvedCount++
        // First-try mates build a streak; hints halve the reward.
        if (attempts == 0 && hintSquare == null) streak++ else streak = 0
        score += (if (hintSquare == null) 100 else 50) + max(0, streak - 1) * 25
        remainingTime += TIME_BONUS; bonusFlash++
        message = L10n.t("Checkmate! 🎉")
        Haptics.success(); Sfx.win(); version++
        later(1.5) {
            puzzleIndex++
            if (puzzleIndex >= puzzles.size) { puzzles = puzzles.shuffled(); puzzleIndex = 0 }
            loadPuzzle()
        }
    }

    /** Move hints exclude captures of the king and moves exposing our own king. */
    private fun legalMoves(square: Int): Set<Int> {
        val piece = board[square]?.takeIf { it.isWhite } ?: return emptySet()
        return pseudoMoves(square).filter { dest ->
            if (board[dest]?.type == PieceType.King) return@filter false
            val pos = board.copyOf()
            if (piece.type == PieceType.Pawn && square % 8 != dest % 8 && pos[dest] == null) pos[(square / 8) * 8 + dest % 8] = null
            if (piece.type == PieceType.King && abs(square % 8 - dest % 8) == 2) {
                val mid = square + if (dest > square) 1 else -1
                if (isAttacked(square, false, pos)) return@filter false
                pos[square] = null; pos[mid] = piece
                if (isAttacked(mid, false, pos)) return@filter false
                pos[mid] = null
                val rookFrom = (square / 8) * 8 + (if (dest > square) 7 else 0)
                val rookTo = if (dest > square) dest - 1 else dest + 1
                pos[rookTo] = pos[rookFrom]; pos[rookFrom] = null
            }
            pos[dest] = piece; pos[square] = null
            val king = pos.indexOfFirst { it?.isWhite == true && it.type == PieceType.King }
            if (king < 0) false else !isAttacked(king, false, pos)
        }.toSet()
    }

    /** Attack maps intentionally include pinned pieces and pawn attacks on empty squares. */
    private fun isAttacked(square: Int, byWhite: Boolean, pos: Array<ChessPiece?>): Boolean {
        val tr = square / 8; val tc = square % 8
        for ((source, occ) in pos.withIndex()) {
            val p = occ ?: continue
            if (p.isWhite != byWhite) continue
            val row = source / 8; val col = source % 8
            val dr = tr - row; val dc = tc - col
            when (p.type) {
                PieceType.Pawn -> if (dr == (if (byWhite) -1 else 1) && abs(dc) == 1) return true
                PieceType.Knight -> if ((abs(dr) == 2 && abs(dc) == 1) || (abs(dr) == 1 && abs(dc) == 2)) return true
                PieceType.King -> if (max(abs(dr), abs(dc)) == 1) return true
                else -> {
                    val diagonal = abs(dr) == abs(dc) && dr != 0
                    val straight = (dr == 0) != (dc == 0)
                    if (!((p.type != PieceType.Rook && diagonal) || (p.type != PieceType.Bishop && straight))) continue
                    val rs = if (dr == 0) 0 else if (dr > 0) 1 else -1; val cs = if (dc == 0) 0 else if (dc > 0) 1 else -1
                    var r = row + rs; var c = col + cs; var blocked = false
                    while (r != tr || c != tc) { if (pos[r * 8 + c] != null) { blocked = true; break }; r += rs; c += cs }
                    if (!blocked) return true
                }
            }
        }
        return false
    }

    /** Candidate destinations, filtered for king safety by [legalMoves]. */
    private fun pseudoMoves(square: Int): Set<Int> {
        val piece = board[square] ?: return emptySet()
        val row = square / 8; val col = square % 8
        val out = HashSet<Int>()
        fun add(r: Int, c: Int): Boolean {
            if (r !in 0..7 || c !in 0..7) return false
            val t = r * 8 + c
            val occ = board[t]
            if (occ != null) { if (occ.isWhite != piece.isWhite) out.add(t); return false }
            out.add(t); return true
        }
        fun ray(dr: Int, dc: Int) { var r = row + dr; var c = col + dc; while (add(r, c)) { r += dr; c += dc } }
        when (piece.type) {
            PieceType.Knight -> for ((dr, dc) in listOf(1 to 2, 2 to 1, -1 to 2, -2 to 1, 1 to -2, 2 to -1, -1 to -2, -2 to -1)) add(row + dr, col + dc)
            PieceType.King -> for (dr in -1..1) for (dc in -1..1) if (dr != 0 || dc != 0) add(row + dr, col + dc)
            PieceType.Rook -> { ray(1, 0); ray(-1, 0); ray(0, 1); ray(0, -1) }
            PieceType.Bishop -> { ray(1, 1); ray(1, -1); ray(-1, 1); ray(-1, -1) }
            PieceType.Queen -> { ray(1, 0); ray(-1, 0); ray(0, 1); ray(0, -1); ray(1, 1); ray(1, -1); ray(-1, 1); ray(-1, -1) }
            PieceType.Pawn -> {
                val dir = if (piece.isWhite) -1 else 1; val startRow = if (piece.isWhite) 6 else 1
                val one = (row + dir) * 8 + col
                if (row + dir in 0..7 && board[one] == null) {
                    out.add(one)
                    val two = (row + 2 * dir) * 8 + col
                    if (row == startRow && board[two] == null) out.add(two)
                }
                for (dc in listOf(-1, 1)) {
                    val r = row + dir; val c = col + dc
                    if (r !in 0..7 || c !in 0..7) continue
                    val occ = board[r * 8 + c]
                    if (occ != null && occ.isWhite != piece.isWhite) out.add(r * 8 + c)
                }
            }
        }
        // Castling and en passant are not covered by the basic move hints above.
        for (sol in acceptedMoves().mapNotNull { parseMove(it) }) if (sol.from == square) out.add(sol.to)
        return out
    }
}

@Composable
fun CheckmateScreen(onExit: () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val engine = remember { CheckmateEngine { CheckmateEngine.loadFromAssets(context) } }
    val pal = Pal.current
    FrameLoop(engine)
    GameContainer(GameId.Checkmate, engine, onExit, resultTitle = L10n.t("Time's up!"), summary = { L10n.f("Solved: %d", engine.solvedCount) }) {
        if (!engine.hasStarted) {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text("👑", fontSize = 48.sp)
                Text(L10n.t("Checkmate"), color = pal.text, fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Text(L10n.t("Choose challenge time"), color = pal.text, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 18.dp))
                Text(L10n.t("Solve as many mates as you can"), color = pal.textSecondary, modifier = Modifier.padding(vertical = 6.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(top = 10.dp)) {
                    CheckmateEngine.durations.forEach { s ->
                        Text(L10n.t(if (s == 30) "30 seconds" else if (s == 60) "1 minute" else "2 minutes"), color = pal.onAccent, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                            modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(pal.accent).clickable { engine.start(s) }.padding(horizontal = 16.dp, vertical = 14.dp))
                    }
                }
                Text(L10n.t("100 points per mate"), color = pal.textSecondary, fontSize = 12.sp, modifier = Modifier.padding(top = 10.dp))
            }
        } else {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("⏱ %d:%02d".format(engine.secondsLeft / 60, engine.secondsLeft % 60), color = if (engine.secondsLeft <= 5) Color.Red else pal.accent, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    if (engine.bonusFlash > 0) Text("+${CheckmateEngine.TIME_BONUS.toInt()}s", color = Color(0xFF34C759), fontWeight = FontWeight.Bold)
                    if (engine.streak > 1) Text("🔥×${engine.streak}", color = Color(0xFFFF9500), fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    val canHint = engine.hintSquare == null && !engine.awaitingBot
                    Text("💡 " + L10n.t("Hint"), color = pal.text.copy(alpha = if (canHint) 1f else 0.4f), fontWeight = FontWeight.Bold, fontSize = 14.sp,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(pal.surfaceHigh).clickable(enabled = canHint) { engine.hint() }.padding(horizontal = 12.dp, vertical = 6.dp))
                    Text(L10n.f("Solved: %d", engine.solvedCount), color = pal.text, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                }
                Text(L10n.t("Mate on the first try to build a streak. Each mate adds 5 seconds."), color = pal.textSecondary, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                Text(L10n.t(engine.puzzle.title), color = pal.accent, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 6.dp))
                Text(engine.message, color = if (engine.hasMoveError) Color.Red else pal.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center,
                    fontWeight = if (engine.hasMoveError) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.padding(vertical = 10.dp))
                ChessBoard(engine)
            }
        }
    }
}

@Composable
private fun ChessBoard(e: CheckmateEngine) {
    val pal = Pal.current
    e.version
    Column(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(12.dp)).border(1.dp, pal.stroke, RoundedCornerShape(12.dp))) {
        for (row in 0 until 8) Row(Modifier.weight(1f)) {
            for (col in 0 until 8) {
                val index = row * 8 + col
                val light = (row + col) % 2 == 0
                val piece = e.board[index]
                Box(Modifier.weight(1f).fillMaxSize().background(if (light) Color(0xFFA6B09C) else Color(0xFF526348))
                    .clickable(remember { MutableInteractionSource() }, null) { e.tap(index) }, contentAlignment = Alignment.Center) {
                    e.lastMove?.let { if (it.first == index || it.second == index) Box(Modifier.fillMaxSize().background(Color.Yellow.copy(alpha = 0.35f))) }
                    if (e.selected == index) Box(Modifier.fillMaxSize().background(pal.accent.copy(alpha = 0.35f)))
                    if (e.hintSquare == index) Box(Modifier.fillMaxSize().border(3.dp, Color.Yellow))
                    if (piece != null) Text(if (piece.isWhite) piece.type.white else piece.type.black, fontSize = 30.sp,
                        style = TextStyle(color = if (piece.isWhite) Color.White else Color.Black, fontSize = 30.sp,
                            shadow = Shadow(if (piece.isWhite) Color.Black.copy(alpha = 0.9f) else Color.White.copy(alpha = 0.45f), Offset.Zero, 3f)))
                    if (index in e.targets) {
                        if (piece != null) Box(Modifier.fillMaxSize().padding(2.dp).border(2.5.dp, pal.accent, RoundedCornerShape(4.dp)))
                        else Box(Modifier.size(10.dp).clip(CircleShape).background(pal.accent.copy(alpha = 0.6f)))
                    }
                    if (col == 0) Text("${8 - row}", color = Color.Black.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.TopStart).padding(2.dp))
                    if (row == 7) Text("abcdefgh"[col].toString(), color = Color.Black.copy(alpha = 0.7f), fontSize = 9.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.align(Alignment.BottomEnd).padding(2.dp))
                }
            }
        }
    }
}
