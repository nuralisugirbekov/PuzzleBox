package com.nurali.puzzlebox.core

import android.app.Activity
import com.google.android.play.core.review.ReviewManagerFactory

/** Asks for a Play Store rating once: the first time a round ends, and never again after that. */
object ReviewPrompt {
    private const val ASKED_KEY = "puzzlebox.review.asked"

    val shouldAsk: Boolean get() = !Settings.prefs.getBoolean(ASKED_KEY, false)

    fun markAsked() = Settings.prefs.edit().putBoolean(ASKED_KEY, true).apply()

    fun request(activity: Activity) {
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { task ->
            if (task.isSuccessful) manager.launchReviewFlow(activity, task.result)
        }
    }
}
