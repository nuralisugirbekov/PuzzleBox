package com.nurali.puzzlebox.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import com.nurali.puzzlebox.core.AppTheme
import com.nurali.puzzlebox.core.Settings

/** App palette. Dark is the main look: near-black backgrounds, dark cards and a neon lime accent. */
data class Palette(
    val background: Color,
    val surface: Color,
    val surfaceHigh: Color,
    val accent: Color,
    val onAccent: Color,
    val text: Color,
    val textSecondary: Color,
    val stroke: Color,
    val dark: Boolean,
)

val DarkPalette = Palette(
    background = Color(0xFF0C0E14), surface = Color(0xFF161A25), surfaceHigh = Color(0xFF212735),
    accent = Color(0xFFC6F31D), onAccent = Color(0xFF0C0E14), text = Color(0xFFF4F5F8),
    textSecondary = Color(0xFF9EA3B0), stroke = Color(0x12FFFFFF), dark = true,
)

val LightPalette = Palette(
    background = Color(0xFFF2F2F7), surface = Color.White, surfaceHigh = Color(0xFFE5E5EA),
    accent = Color(0xFF007AFF), onAccent = Color.White, text = Color(0xFF111114),
    textSecondary = Color(0xFF6C6C70), stroke = Color(0x1F000000), dark = false,
)

val LocalPalette = staticCompositionLocalOf { DarkPalette }

object Pal {
    val current: Palette @Composable get() = LocalPalette.current
}

@Composable
fun OinaTheme(content: @Composable () -> Unit) {
    val dark = when (Settings.theme) {
        AppTheme.System -> isSystemInDarkTheme()
        AppTheme.Light -> false
        AppTheme.Dark -> true
    }
    val p = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(primary = p.accent, onPrimary = p.onAccent, background = p.background,
            surface = p.surface, onSurface = p.text, onBackground = p.text, surfaceVariant = p.surfaceHigh)
    } else {
        lightColorScheme(primary = p.accent, onPrimary = p.onAccent, background = p.background,
            surface = p.surface, onSurface = p.text, onBackground = p.text, surfaceVariant = p.surfaceHigh)
    }
    CompositionLocalProvider(LocalPalette provides p) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
