package com.nurali.puzzlebox.core

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

object Haptics {
    private var vibrator: Vibrator? = null

    fun init(context: Context) {
        val app = context.applicationContext
        vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION") app.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    private fun buzz(ms: Long, amplitude: Int) {
        if (!Settings.hapticsEnabled) return
        vibrator?.takeIf { it.hasVibrator() }?.vibrate(VibrationEffect.createOneShot(ms, amplitude))
    }

    fun tap() = buzz(12, 60)
    fun move() = buzz(18, 110)
    fun heavy() = buzz(40, 220)
    fun success() = buzz(35, 160)
    fun error() = buzz(60, 255)
}
