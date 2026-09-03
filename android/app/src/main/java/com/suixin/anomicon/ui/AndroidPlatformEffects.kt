package com.suixin.anomicon.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat

internal class AndroidHapticFeedback(context: Context) {
    private val appContext = context.applicationContext
    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        appContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        appContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    fun playSelection(enabled: Boolean, view: View? = null) {
        if (!enabled) return
        if (view?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP) == true) {
            return
        }
        val target = vibrator ?: return
        if (!target.hasVibrator()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            target.vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
        } else {
            target.vibrate(VibrationEffect.createOneShot(12L, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }
}

@Composable
internal fun rememberAndroidHapticFeedback(): AndroidHapticFeedback {
    val context = LocalContext.current
    return remember(context) { AndroidHapticFeedback(context) }
}

@Composable
internal fun ApplyAndroidSystemBars(
    immersiveMaterialEnabled: Boolean,
    darkTheme: Boolean
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val surfaceColor = MaterialTheme.colorScheme.surface.toArgb()
    val transparent = Color.TRANSPARENT
    SideEffect {
        val window = activity?.window ?: return@SideEffect
        WindowCompat.setDecorFitsSystemWindows(window, !immersiveMaterialEnabled)
        val barColor = if (immersiveMaterialEnabled) transparent else surfaceColor
        @Suppress("DEPRECATION")
        window.statusBarColor = barColor
        @Suppress("DEPRECATION")
        window.navigationBarColor = barColor
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = !immersiveMaterialEnabled
            window.isNavigationBarContrastEnforced = !immersiveMaterialEnabled
        }
        WindowInsetsControllerCompat(window, window.decorView).apply {
            isAppearanceLightStatusBars = !darkTheme
            isAppearanceLightNavigationBars = !darkTheme
        }
    }
}

@Composable
internal fun currentAndroidView(): View = LocalView.current

private tailrec fun Context.findActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
