package com.nurali.puzzlebox.core

import android.content.Context
import android.os.LocaleList
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.util.Locale

/** Languages the app is translated into. Codes match the iOS .lproj folders. */
enum class AppLanguage(val code: String, val nativeName: String) {
    Russian("ru", "Русский"),
    Kazakh("kk", "Қазақша"),
    English("en", "English"),
    French("fr", "Français"),
    Hindi("hi", "हिन्दी"),
    German("de", "Deutsch"),
    Chinese("zh-Hans", "简体中文"),
    Korean("ko", "한국어");

    companion object {
        fun fromCode(code: String?): AppLanguage? = entries.firstOrNull { it.code == code }

        /** The first of the user's preferred system languages that the app is translated into, else English. */
        fun systemDefault(): AppLanguage {
            val list = LocaleList.getDefault()
            for (i in 0 until list.size()) {
                val lang = list[i].language
                val match = if (lang == "zh") Chinese else entries.firstOrNull { it.code == lang }
                if (match != null) return match
            }
            return English
        }
    }
}

/**
 * Text lookup shared with the iOS app: keys are the English phrases and the tables are generated
 * from the iOS Localizable.strings files (see tools/convert_strings.py).
 */
object L10n {
    private lateinit var appContext: Context
    private val tables = HashMap<String, Map<String, String>>()

    /** Compose-observable so the UI refreshes when the language changes. */
    var language by mutableStateOf(AppLanguage.English)
        private set

    fun init(context: Context) {
        appContext = context.applicationContext
        language = AppLanguage.fromCode(Settings.languageCode) ?: AppLanguage.systemDefault()
    }

    fun changeLanguage(value: AppLanguage) {
        AppAnalytics.selectLanguage(value.code)
        Settings.languageCode = value.code
        language = value
    }

    private fun table(lang: AppLanguage): Map<String, String> = tables.getOrPut(lang.code) {
        runCatching {
            val json = appContext.assets.open("l10n/${lang.code}.json").bufferedReader().use { it.readText() }
            val obj = JSONObject(json)
            buildMap { obj.keys().forEach { put(it, obj.getString(it)) } }
        }.getOrDefault(emptyMap())
    }

    fun t(key: String): String = if (language == AppLanguage.English) key else table(language)[key] ?: key

    fun f(key: String, vararg args: Any): String =
        runCatching {
            // English falls back to the raw key, which still has iOS-style specifiers.
            val pattern = t(key).replace("%@", "%s").replace("%lld", "%d").replace("%ld", "%d")
            String.format(Locale.forLanguageTag(language.code), pattern, *args)
        }.getOrDefault(key)
}
