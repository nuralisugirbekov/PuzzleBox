package com.nurali.puzzlebox

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.nurali.puzzlebox.core.Haptics
import com.nurali.puzzlebox.core.L10n
import com.nurali.puzzlebox.core.Settings
import com.nurali.puzzlebox.core.Stats
import com.nurali.puzzlebox.ui.OinaApp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Settings.init(this)
        Stats.init()
        L10n.init(this)
        Haptics.init(this)
        com.nurali.puzzlebox.core.AppAnalytics.init(this)
        requestHighRefreshRate()
        setContent { OinaApp(initialGame = intent?.getStringExtra("game")) }
    }

    /** Games animate every frame, so ask for the panel's fastest mode (90/120 Hz) at the current resolution. */
    @Suppress("DEPRECATION")
    private fun requestHighRefreshRate() {
        runCatching {
            val display = if (android.os.Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
            val current = display?.mode ?: return
            val best = display.supportedModes.filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            window.attributes = window.attributes.also { it.preferredDisplayModeId = best.modeId }
        }
    }
}
