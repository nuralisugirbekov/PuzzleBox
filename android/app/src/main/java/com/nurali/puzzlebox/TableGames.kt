package com.nurali.puzzlebox

import kotlin.math.roundToInt

class SpadesEngine : Engine() {
    data class Seat(val hand: MutableList<Card>, var bid: Int = 0, var tricks: Int = 0)
    var seats = mutableListOf<Seat>(); var trick = mutableListOf<Pair<Int, Card>>()
    var turn = 0; var bidding = true; var userBid = 3; private var broken = false; private var clock = 0L
    init { restart() }
    override fun restart() {
        reset(); val cards = deck()
        seats = MutableList(4) { i -> Seat(cards.subList(i * 13, i * 13 + 13).sortedWith(compareBy<Card> { it.suit }.thenBy { it.high }).toMutableList()) }
        for (i in 1..3) {
            val estimate = seats[i].hand.sumOf { when (it.rank) { 1 -> 1.0; 13 -> 0.7; 12 -> 0.4; else -> 0.0 } } + maxOf(0, seats[i].hand.count { it.suit == 0 } - 3) * 0.7
            seats[i].bid = estimate.roundToInt().coerceIn(1, 7)
        }
        trick.clear(); turn = 0; bidding = true; broken = false; clock = 0; userBid = 3; say("Choose your bid"); changed()
    }
    fun start() { if (!bidding || phase != Phase.PLAYING) return; seats[0].bid = userBid; bidding = false; say("Your lead"); changed() }
    fun legal(seat: Int): List<Card> {
        val hand = seats[seat].hand
        if (trick.isEmpty()) return if (!broken && hand.any { it.suit != 0 }) hand.filter { it.suit != 0 } else hand
        val follow = hand.filter { it.suit == trick[0].second.suit }; return follow.ifEmpty { hand }
    }
    private fun beats(card: Card, other: Card) = (card.suit == 0 && other.suit != 0) || (card.suit == other.suit && card.high > other.high)
    private fun winner(): Pair<Int, Card> = trick.reduce { a, b -> if (beats(b.second, a.second)) b else a }
    fun userPlay(card: Card) {
        if (phase != Phase.PLAYING || bidding || turn != 0 || trick.size == 4 || card !in legal(0)) return
        play(0, card)
    }
    private fun play(seat: Int, card: Card) {
        seats[seat].hand.remove(card); trick.add(seat to card); if (card.suit == 0) broken = true
        turn = (seat + 1) % 4; clock = 0; changed()
    }
    override fun tick(ms: Long) {
        if (bidding || (turn == 0 && trick.size < 4)) return
        clock += ms
        if (clock < if (trick.size == 4) 1000 else 650) return
        clock = 0
        if (trick.size == 4) {
            val win = winner().first; seats[win].tricks++; trick.clear(); turn = win
            if (seats.all { it.hand.isEmpty() }) {
                val mine = team(0, 2); val theirs = team(1, 3)
                score = maxOf(0, mine); say("Your team %d — Opponents %d", mine, theirs); phase = if (mine > theirs) Phase.WON else Phase.LOST
            } else say(if (turn == 0) "Your lead" else "Bot is thinking…")
        } else {
            val choices = legal(turn)
            val winning = if (trick.isEmpty()) null else winner()
            val winners = if (winning == null) emptyList() else choices.filter { beats(it, winning.second) }
            val options = if (winning?.first == (turn + 2) % 4 || winners.isEmpty()) choices else winners
            play(turn, options.minBy { it.high })
            if (turn == 0 && trick.size < 4) say("Your turn")
        }
        changed()
    }
    private fun team(a: Int, b: Int): Int {
        val bid = seats[a].bid + seats[b].bid; val taken = seats[a].tricks + seats[b].tricks
        var result = if (taken >= bid) bid * 10 + taken - bid else -bid * 10
        for (i in listOf(a, b)) if (seats[i].bid == 0) result += if (seats[i].tricks == 0) 100 else -100
        return result
    }
}

data class Domino(val a: Int, val b: Int) { val pips get() = a + b }
class DominoEngine : Engine() {
    var hand = mutableListOf<Domino>(); var bot = mutableListOf<Domino>(); var stock = mutableListOf<Domino>()
    var chain = mutableListOf<Domino>(); var userTurn = true; var pending: Domino? = null
    private var passes = 0; private var clock = 0L
    init { restart() }
    override fun restart() {
        reset(); val tiles = (0..6).flatMap { a -> (a..6).map { Domino(a, it) } }.shuffled()
        hand = tiles.take(7).toMutableList(); bot = tiles.drop(7).take(7).toMutableList(); stock = tiles.drop(14).toMutableList()
        chain.clear(); passes = 0; clock = 0; pending = null; userTurn = true; say("Your move — play a tile"); changed()
    }
    fun fits(d: Domino) = chain.isEmpty() || d.a == chain.first().a || d.b == chain.first().a || d.a == chain.last().b || d.b == chain.last().b
    fun tap(d: Domino) {
        if (!userTurn || phase != Phase.PLAYING || !fits(d)) return
        val left = chain.isNotEmpty() && (d.a == chain.first().a || d.b == chain.first().a)
        val right = chain.isNotEmpty() && (d.a == chain.last().b || d.b == chain.last().b)
        if (left && right && chain.first().a != chain.last().b) { pending = d; changed() }
        else play(d, left, true)
    }
    fun choose(left: Boolean) { val d = pending ?: return; pending = null; play(d, left, true) }
    private fun play(d: Domino, left: Boolean, mine: Boolean) {
        if (chain.isEmpty()) chain.add(d)
        else if (left) chain.add(0, if (d.b == chain.first().a) d else Domino(d.b, d.a))
        else chain.add(if (d.a == chain.last().b) d else Domino(d.b, d.a))
        passes = 0
        (if (mine) hand else bot).remove(d)
        if (hand.isEmpty() || bot.isEmpty()) finish(hand.isEmpty())
        else { userTurn = !mine; clock = 0; say(if (userTurn) "Your move" else "Bot is thinking…") }
        changed()
    }
    fun draw() {
        if (!userTurn || phase != Phase.PLAYING || hand.any(::fits)) return
        if (stock.isNotEmpty()) { hand.add(stock.removeAt(stock.lastIndex)); say(if (hand.any(::fits)) "Drawn — you can play!" else "Still stuck — draw again") }
        else { passes++; if (passes == 2) blocked() else { userTurn = false; clock = 0; say("You passed") } }
        changed()
    }
    override fun tick(ms: Long) {
        if (userTurn) return
        clock += ms; if (clock < 700) return; clock = 0
        val choice = bot.filter(::fits).maxByOrNull { it.pips }
        if (choice != null) play(choice, chain.isNotEmpty() && (choice.a == chain.first().a || choice.b == chain.first().a), false)
        else if (stock.isNotEmpty()) { bot.add(stock.removeAt(stock.lastIndex)); changed() }
        else { passes++; if (passes >= 2) blocked() else { userTurn = true; say("Bot passed") }; changed() }
    }
    private fun blocked() {
        val mine = hand.sumOf { it.pips }; val theirs = bot.sumOf { it.pips }
        finish(mine <= theirs)
        if (mine <= theirs) say("Blocked — you have fewer pips (%d vs %d).", mine, theirs)
        else say("Blocked — bot has fewer pips (%d vs %d).", theirs, mine)
    }
    private fun finish(won: Boolean) {
        phase = if (won) Phase.WON else Phase.LOST
        score = if (won) 100 + bot.sumOf { it.pips } else 0
        say(if (won) "You played every tile!" else "Bot played every tile.")
    }
}
