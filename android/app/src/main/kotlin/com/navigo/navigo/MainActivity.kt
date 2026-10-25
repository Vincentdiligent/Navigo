package com.navigo.navigo

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
    }

    /**
     * The map is a full-bleed canvas: the Android system navigation bar must
     * be transparent (no opaque black strip over the basemap). Flutter draws
     * behind both bars and handles safe-area insets in Dart.
     */
    private fun enableEdgeToEdge() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.navigationBarColor = Color.TRANSPARENT
        window.statusBarColor = Color.TRANSPARENT
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        // Navigation-bar icons stay light over the (possibly light) map;
        // the Flutter layer re-styles them per theme when needed.
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.isAppearanceLightNavigationBars = false
        controller.isAppearanceLightStatusBars = false
    }

    /**
     * v5.7 — the navigation channel:
     *  • requestPermissions → POST_NOTIFICATIONS (13+) and, separately,
     *    ACCESS_BACKGROUND_LOCATION (10+; Android silently ignores it when
     *    requested in a group, so it gets its own request);
     *  • show / stop → the [NavService] foreground service + notification;
     *  • keepScreenOn → FLAG_KEEP_SCREEN_ON while the HUD is up.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "navigo/nav")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> {
                        requestNavPermissions()
                        result.success(true)
                    }
                    "show" -> {
                        val i = Intent(this, NavService::class.java)
                            .putExtra(NavService.EXTRA_TITLE, call.argument<String>("title") ?: "Navigo")
                            .putExtra(NavService.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        ContextCompat.startForegroundService(this, i)
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, NavService::class.java))
                        result.success(true)
                    }
                    "keepScreenOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(true)
                    }
                    // v5.8: the system share sheet — place cards and the
                    // long-press map menu hand off to any app.
                    "share" -> {
                        try {
                            val text = call.argument<String>("text") ?: ""
                            val title = call.argument<String>("title") ?: "Navigo"
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                                putExtra(Intent.EXTRA_TITLE, title)
                            }
                            startActivity(Intent.createChooser(send, title))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Two SEQUENTIAL permission requests: notifications first, background
     *  location second (it must ride alone on Android 10+). */
    private fun requestNavPermissions() {
        if (Build.VERSION.SDK_INT >= 33 &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                4701
            )
            return // background location follows in onRequestPermissionsResult
        }
        requestBackgroundLocation()
    }

    private fun requestBackgroundLocation() {
        if (Build.VERSION.SDK_INT >= 29 &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                4702
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4701) requestBackgroundLocation()
    }
}
