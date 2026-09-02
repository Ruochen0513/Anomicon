package com.suixin.anomicon.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightScheme = lightColorScheme(
    primary = Color(0xFF345C72),
    onPrimary = Color.White,
    secondary = Color(0xFF5A6145),
    tertiary = Color(0xFF7A4D45),
    background = Color(0xFFF8F7F2),
    surface = Color(0xFFFFFBF4),
    surfaceVariant = Color(0xFFE2E2D7),
    onSurface = Color(0xFF202124)
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFF9BCBE3),
    onPrimary = Color(0xFF043547),
    secondary = Color(0xFFC3CAAA),
    tertiary = Color(0xFFEAB3A8),
    background = Color(0xFF151713),
    surface = Color(0xFF1D201B),
    surfaceVariant = Color(0xFF46483F),
    onSurface = Color(0xFFE5E4DC)
)

@Composable
fun AnomiconTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        typography = AnomiconTypography,
        content = content
    )
}
