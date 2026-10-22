package com.nurali.puzzlebox.game

/** Lifecycle of a round. Mirrors the iOS `GameState`. */
sealed interface GameState {
    data object Playing : GameState
    data object Paused : GameState
    data class GameOver(val won: Boolean) : GameState
}

/**
 * Every mini-game exposes its engine through this interface so the shared [GameContainer] can drive
 * the header, pause/game-over overlays and high-score recording. Engines keep their data in Compose
 * snapshot state, so the game views recompose on their own.
 */
interface GameEngine {
    val score: Int
    var state: GameState
    fun restart()
}
