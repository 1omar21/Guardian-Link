package com.guardianlink.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isBrowsingMonitorEnabled" -> result.success(BrowserMonitorService.isEnabled(this))
                "openAccessibilitySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    result.success(null)
                }
                "flushBrowsingHistory" -> {
                    BrowserMonitorService.flushAsync(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Channels used by push notifications (ids must match the backend). */
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return

        val alerts = NotificationChannel(
            "guardian_alerts", "Safety alerts", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Check-ins, safe zone arrivals/departures and task updates"
        }

        val sos = NotificationChannel(
            "sos_alerts", "SOS emergencies", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Emergency SOS alerts from your child"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }

        manager.createNotificationChannels(listOf(alerts, sos))
    }

    companion object {
        const val CHANNEL = "guardianlink/native"
    }
}
