package com.nurali.puzzlebox.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class AppTheme(val key: String, val label: String) {
    System("system", "Automatic"), Light("light", "Light"), Dark("dark", "Dark");

    companion object {
        fun from(key: String?) = entries.firstOrNull { it.key == key } ?: Dark
    }
}

/** Process-wide preferences, backed by SharedPreferences. */
object Settings {
    lateinit var prefs: SharedPreferences
        private set

    fun init(context: Context) {
        prefs = context.applicationContext.getSharedPreferences("oina", Context.MODE_PRIVATE)
        theme = AppTheme.from(prefs.getString("theme", null))
        hapticsEnabled = prefs.getBoolean("haptics", true)
    }

    var languageCode: String
        get() = prefs.getString("appLanguage", "") ?: ""
        set(value) = prefs.edit().putString("appLanguage", value).apply()

    var theme by mutableStateOf(AppTheme.Dark)
        private set

    fun chooseTheme(value: AppTheme) {
        AppAnalytics.log("theme_selected", "theme" to value.key)
        theme = value
        prefs.edit().putString("theme", value.key).apply()
    }

    var hapticsEnabled by mutableStateOf(true)
        private set

    fun setHaptics(value: Boolean) {
        AppAnalytics.log("haptics_toggled", "enabled" to value)
        hapticsEnabled = value
        prefs.edit().putBoolean("haptics", value).apply()
    }
}
