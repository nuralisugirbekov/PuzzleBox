package com.nurali.puzzlebox.core

import android.media.AudioManager
import android.media.ToneGenerator

/** Tiny synthesized feedback tones, so the app needs no audio assets. */
object Sfx {
    private var generator: ToneGenerator? = null

    private fun tone(type: Int, ms: Int) {
        if (!Settings.hapticsEnabled) return
        runCatching {
            val g = generator ?: ToneGenerator(AudioManager.STREAM_MUSIC, 60).also { generator = it }
            g.startTone(type, ms)
        }
    }

    fun tap() = tone(ToneGenerator.TONE_PROP_BEEP, 40)
    fun point() = tone(ToneGenerator.TONE_PROP_ACK, 90)
    fun wrong() = tone(ToneGenerator.TONE_PROP_NACK, 160)
    fun win() = tone(ToneGenerator.TONE_CDMA_CONFIRM, 300)
    fun lose() = tone(ToneGenerator.TONE_CDMA_ABBR_ALERT, 300)

    /** Four distinct pad tones for Simon. */
    fun pad(index: Int, ms: Int = 220) =
        tone(intArrayOf(ToneGenerator.TONE_DTMF_1, ToneGenerator.TONE_DTMF_5, ToneGenerator.TONE_DTMF_9, ToneGenerator.TONE_DTMF_D)[index % 4], ms)
}
