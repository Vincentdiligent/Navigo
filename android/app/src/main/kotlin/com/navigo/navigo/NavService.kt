package com.navigo.navigo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * v5.7 — Navigation foreground service + the ongoing turn-by-turn
 * notification.
 *
 * WHY: the user navigates with the screen off / the app in the background
 * and demands real guidance there («пуш на заблокированном тоже красиво и
 * удобно было бы чтобы навигация работала»).
 *
 * HOW:
 *  • startForegroundService(...) from Flutter keeps the process alive
 *    (foregroundServiceType=location — declared in the manifest together
 *    with FOREGROUND_SERVICE / FOREGROUND_SERVICE_LOCATION);
 *  • the notification channel runs at IMPORTANCE_HIGH → heads-up + lock
 *    screen, VISIBILITY_PUBLIC shows the full maneuver text on the lock
 *    screen, CATEGORY_NAVIGATION makes the system treat it as guidance;
 *  • every Flutter update re-enters onStartCommand and re-posts the
 *    notification with the fresh maneuver + ETA.
 */
class NavService : Service() {

    companion object {
        const val CHANNEL_ID = "lux_nav"
        const val NOTIF_ID = 4711
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        @Volatile
        var running = false
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Навигация",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Пошаговые подсказки маршрута"
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Navigo"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: ""
        val notification = build(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(NOTIF_ID, notification)
        }
        running = true
        return START_STICKY
    }

    private fun build(title: String, text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        launch?.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
        val pi = PendingIntent.getActivity(
            this,
            0,
            launch ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_nav_notify)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_NAVIGATION)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(0xFF22B573.toInt())
            .setColorized(false)
            .setContentIntent(pi)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
