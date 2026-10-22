package com.nurali.puzzlebox.games.kit

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/** Deterministic generator: the same level always produces the same puzzle. */
class PuzzleRandom(seed: Long) : Random() {
    private var state: Long = seed * -7046029254386353131L + -3335678366873096957L

    private fun next64(): Long {
        state += -7046029254386353131L
        var z = state
        z = (z xor (z ushr 30)) * -4658895280553007687L
        z = (z xor (z ushr 27)) * -7723592293110705685L
        return z xor (z ushr 31)
    }

    override fun nextBits(bitCount: Int): Int = if (bitCount <= 0) 0 else (next64() ushr (64 - bitCount)).toInt()
}

class SlidingPiece(val id: Int, var row: Int, var col: Int, val length: Int, val horizontal: Boolean) {
    val cells: List<Int>
        get() = (0 until length).map { (row + (if (horizontal) 0 else it)) * 6 + col + (if (horizontal) it else 0) }

    fun copy() = SlidingPiece(id, row, col, length, horizontal)
}

object PuzzleGenerators {
    private fun neighbors(i: Int, n: Int): List<Int> {
        val r = i / n; val c = i % n
        return buildList {
            if (r > 0) add(i - n)
            if (r < n - 1) add(i + n)
            if (c > 0) add(i - 1)
            if (c < n - 1) add(i + 1)
        }
    }

    /**
     * A random Hamiltonian path over an n×n grid, built with "backbite" moves from a serpentine
     * start. With [fixedStart], cell 0 stays the first cell and only the tail end moves.
     */
    fun hamiltonianPath(n: Int, fixedStart: Boolean = false, random: Random): List<Int> {
        var path = (0 until n).flatMap { r -> (0 until n).map { r * n + (if (r % 2 == 0) it else n - 1 - it) } }.toMutableList()
        if (fixedStart) path.reverse() // backbite below always moves path[0], so keep cell 0 at the end
        repeat(n * n * 20) {
            if (!fixedStart && random.nextBoolean()) path.reverse()
            val head = path[0]
            val choices = neighbors(head, n).filter { it != path[1] }
            val v = choices.randomOrNull(random) ?: return@repeat
            val j = path.indexOf(v)
            if (j < 0) return@repeat
            path = (path.subList(0, j).reversed() + path.subList(j, path.size)).toMutableList()
        }
        if (fixedStart) path.reverse()
        return path
    }

    /** Lights Out board made by pressing random cells, so it is always solvable. */
    fun lightsOut(n: Int, presses: Int, random: Random): IntArray {
        val grid = IntArray(n * n)
        for (i in (0 until n * n).shuffled(random).take(presses)) {
            for (index in listOf(i) + neighbors(i, n)) grid[index] = 1 - grid[index]
        }
        if (grid.all { it == 0 }) return lightsOut(n, presses + 1, random)
        return grid
    }

    /** A random picture for the nonogram; any grid matching the clues counts as solved. */
    fun nonogram(n: Int, random: Random): IntArray {
        while (true) {
            val grid = IntArray(n * n) { if (random.nextInt(100) < 58) 1 else 0 }
            val rowsOk = (0 until n).all { r -> (0 until n).any { grid[r * n + it] == 1 } }
            val colsOk = (0 until n).all { c -> (0 until n).any { grid[it * n + c] == 1 } }
            if (rowsOk && colsOk) return grid
        }
    }

    /** Splits a Hamiltonian path into [pairs] segments of at least three cells. */
    fun numberConnect(n: Int, pairs: Int, random: Random): IntArray {
        val path = hamiltonianPath(n, random = random)
        val lengths = IntArray(pairs) { 3 }
        repeat(n * n - 3 * pairs) { lengths[random.nextInt(pairs)]++ }
        val grid = IntArray(n * n)
        var start = 0
        for ((color, length) in lengths.withIndex()) {
            grid[path[start]] = color + 1
            grid[path[start + length - 1]] = color + 1
            start += length
        }
        return grid
    }

    class PipeResult(val grid: IntArray, val end: Int, val exit: Int)

    /** One closed route through every pipe tile, entering at the top-left and leaving through the border. */
    fun pipes(n: Int, random: Random): PipeResult {
        var path: List<Int> = emptyList()
        var end = 0
        for (attempt in 0 until 200) {
            path = hamiltonianPath(n, fixedStart = true, random = random)
            end = path.last()
            val r = end / n; val c = end % n
            if (path[0] == 0 && end != 0 && (r == n - 1 || c == n - 1 || r == 0 || c == 0)) break
            if (attempt == 199) {
                path = (0 until n).flatMap { rr -> (0 until n).map { rr * n + (if (rr % 2 == 0) it else n - 1 - it) } }
                end = path.last()
            }
        }
        val grid = IntArray(n * n)
        grid[0] = grid[0] or 8
        for ((a, b) in path.zipWithNext()) {
            val bit = when (b) { a + 1 -> 2; a - 1 -> 8; a + n -> 4; else -> 1 }
            grid[a] = grid[a] or bit
            grid[b] = grid[b] or when (bit) { 1 -> 4; 4 -> 1; 2 -> 8; else -> 2 }
        }
        val r = end / n; val c = end % n
        val exit = if (r == n - 1) 4 else if (c == n - 1) 2 else if (r == 0) 1 else 8
        grid[end] = grid[end] or exit
        return PipeResult(grid, end, exit)
    }

    class LaserResult(val grid: IntArray, val source: Int, val target: Int)

    /** Beam route with mirrors at each turn (1 = "/", 2 = "\"); the beam fires right from column 0. */
    fun laser(n: Int, turns: Int, decoys: Int, random: Random): LaserResult {
        fun freeAhead(cell: Int, dr: Int, dc: Int, used: Set<Int>): Int {
            var count = 0; var r = cell / n + dr; var c = cell % n + dc
            while (r in 0 until n && c in 0 until n && (r * n + c) !in used) { count++; r += dr; c += dc }
            return count
        }
        repeat(500) {
            val grid = IntArray(n * n)
            val source = random.nextInt(n) * n
            var cell = source; var dr = 0; var dc = 1
            val used = mutableSetOf(cell)
            var ok = true
            for (turn in 0..turns) {
                val room = freeAhead(cell, dr, dc, used)
                if (room <= 0) { ok = false; break }
                val steps = random.nextInt(1, room + 1)
                repeat(steps) { cell = (cell / n + dr) * n + cell % n + dc; used.add(cell) }
                if (turn >= turns) break
                // Turn only where the beam can keep going afterwards.
                val options = listOf(-dc to dr, dc to -dr).filter { freeAhead(cell, it.first, it.second, used) > 0 }
                val pick = options.randomOrNull(random)
                if (pick == null) { ok = false; break }
                val (ndr, ndc) = pick
                // Mirror 1 maps (dr, dc) → (-dc, -dr); mirror 2 maps (dr, dc) → (dc, dr).
                grid[cell] = if (ndr == -dc && ndc == -dr) 1 else 2
                dr = ndr; dc = ndc
            }
            if (!ok || grid[cell] != 0 || cell == source) return@repeat
            val free = (0 until n * n).filter { it !in used }.shuffled(random)
            for (i in free.take(decoys)) grid[i] = random.nextInt(1, 3)
            return LaserResult(grid, source, cell)
        }
        return LaserResult(IntArray(n * n), 0, n - 1)
    }

    // MARK: Rush hour

    /** Breadth-first search over single-step slides; returns the shortest solution length. */
    fun rushHourDepth(pieces: List<SlidingPiece>, limit: Int = 25_000): Int? {
        fun key(p: List<SlidingPiece>): Long = p.fold(0L) { acc, s -> acc shl 3 or (if (s.horizontal) s.col else s.row).toLong() }
        val seen = hashSetOf(key(pieces))
        var frontier = listOf(pieces)
        var depth = 0
        while (frontier.isNotEmpty() && seen.size < limit) {
            val next = ArrayList<List<SlidingPiece>>()
            for (state in frontier) {
                if (state[0].col + state[0].length == 6) return depth
                val occupied = HashSet<Int>()
                for (p in state) occupied.addAll(p.cells)
                for ((index, piece) in state.withIndex()) {
                    for (delta in intArrayOf(-1, 1)) {
                        val moved = piece.copy()
                        if (piece.horizontal) moved.col += delta else moved.row += delta
                        if (moved.row < 0 || moved.col < 0 ||
                            moved.row + (if (moved.horizontal) 1 else moved.length) > 6 ||
                            moved.col + (if (moved.horizontal) moved.length else 1) > 6) continue
                        val fresh = moved.cells.toSet() - piece.cells.toSet()
                        if (fresh.any { it in occupied }) continue
                        val copy = state.toMutableList(); copy[index] = moved
                        if (seen.add(key(copy))) next.add(copy)
                    }
                }
            }
            frontier = next
            depth++
        }
        return null
    }

    /** Random solvable rush-hour layout whose shortest solution is as close as possible to [targetDepth]. */
    fun rushHour(pieceCount: Int, targetDepth: Int, random: Random): List<SlidingPiece> {
        var best: List<SlidingPiece> = emptyList()
        var bestDepth = -1
        val deadline = System.currentTimeMillis() + 250
        for (round in 0 until 60) {
            if (System.currentTimeMillis() >= deadline) break
            val pieces = mutableListOf(SlidingPiece(0, 2, random.nextInt(0, 2), 2, true))
            val occupied = pieces[0].cells.toMutableSet()
            var attempts = 0
            while (pieces.size < pieceCount && attempts < 200) {
                attempts++
                val horizontal = random.nextBoolean()
                val length = if (random.nextInt(100) < 70) 2 else 3
                val row = random.nextInt(0, if (horizontal) 6 else 7 - length)
                val col = random.nextInt(0, if (horizontal) 7 - length else 6)
                if (horizontal && row == 2) continue // would wall in the red block
                val piece = SlidingPiece(pieces.size, row, col, length, horizontal)
                if (piece.cells.any { it in occupied }) continue
                pieces.add(piece); occupied.addAll(piece.cells)
            }
            val depth = rushHourDepth(pieces, 12_000)
            if (depth == null || depth < 3) continue
            if (bestDepth < 0 || abs(depth - targetDepth) < abs(bestDepth - targetDepth)) { best = pieces.toList(); bestDepth = depth }
            if (depth >= targetDepth) break
        }
        return best.ifEmpty { listOf(SlidingPiece(0, 2, 0, 2, true), SlidingPiece(1, 1, 3, 3, false)) }
    }

    /** Greedy flood-fill solution length: an upper bound used to set a fair move limit. */
    fun floodGreedySteps(start: IntArray, n: Int, colors: Int): Int {
        val grid = start.copyOf()
        fun region(): Set<Int> {
            val found = HashSet<Int>(); val queue = ArrayDeque<Int>(); queue.add(0)
            val value = grid[0]
            while (queue.isNotEmpty()) {
                val i = queue.removeLast()
                if (!found.add(i)) continue
                queue.addAll(neighbors(i, n).filter { grid[it] == value && it !in found })
            }
            return found
        }
        var steps = 0
        while (grid.toSet().size > 1 && steps < 200) {
            val current = region()
            var bestColor = grid[0]; var bestSize = -1
            for (color in 1..colors) if (color != grid[0]) {
                val saved = grid.copyOf()
                for (i in current) grid[i] = color
                val size = region().size
                saved.copyInto(grid)
                if (size > bestSize) { bestSize = size; bestColor = color }
            }
            for (i in current) grid[i] = bestColor
            steps++
        }
        return steps
    }

    class OneLineResult(val nodes: List<Int>, val edges: List<List<Int>>)

    /** One-line puzzle: a random trail over a node lattice; the trail itself is an Euler path. */
    fun oneLine(size: Int, edgeCount: Int, random: Random): OneLineResult {
        val n = size
        fun adjacent(i: Int): List<Int> = buildList {
            val r = i / n; val c = i % n
            for (dr in -1..1) for (dc in -1..1) if (dr != 0 || dc != 0) {
                val nr = r + dr; val nc = c + dc
                if (nr in 0 until n && nc in 0 until n) add(nr * n + nc)
            }
        }
        var best: List<List<Int>> = emptyList()
        for (round in 0 until 300) {
            var current = random.nextInt(n * n)
            val edges = ArrayList<List<Int>>()
            val used = HashSet<List<Int>>()
            while (edges.size < edgeCount) {
                // Avoid diagonals that would cross an existing diagonal in the same square.
                val options = adjacent(current).filter { next ->
                    val e = listOf(min(current, next), max(current, next))
                    if (e in used) return@filter false
                    val dr = next / n - current / n; val dc = next % n - current % n
                    if (dr != 0 && dc != 0) {
                        val a = current + dc; val b = current + dr * n
                        if (listOf(min(a, b), max(a, b)) in used) return@filter false
                    }
                    true
                }
                val next = options.randomOrNull(random) ?: break
                val e = listOf(min(current, next), max(current, next))
                used.add(e); edges.add(listOf(current, next)); current = next
            }
            if (edges.size > best.size) best = edges.toList()
            if (edges.size == edgeCount) break
        }
        val nodes = best.flatten().toSet().sorted()
        return OneLineResult(nodes, best.shuffled(random))
    }
}
