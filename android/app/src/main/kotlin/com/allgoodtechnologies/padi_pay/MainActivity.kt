package com.allgoodtechnologies.padi_pay

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.view.WindowCompat
import com.qoreid.qoreidsdk.QoreidsdkPlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import java.io.File
import java.text.DecimalFormat

class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "padi_transactions_channel"
        private const val NOTIFICATION_CHANNEL_NAME = "Transactions Notifications"
        private const val NOTIFICATION_CHANNEL_DESC = "This channel is used for transactions notifications."
        private const val NOTIFICATION_METHOD_CHANNEL = "com.allgoodtech.padipay/notifications"
        private const val METHOD_SHOW_INCOMING_PAYMENT_NOTIFICATION = "showIncomingPaymentNotification"
        private const val METHOD_OPEN_TTS_SETTINGS = "openTtsSettings"
        private const val SECURE_CHANNEL = "com.padipay/screen_secure"
        private const val METHOD_SECURE_ON = "secureOn"
        private const val METHOD_SECURE_OFF = "secureOff"

        private const val JAILBREAK_CHANNEL = "com.padipay/jailbreak"
        private const val METHOD_IS_ROOTED = "isDeviceRootedOrJailbroken"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        QoreidsdkPlugin.initialize(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_SHOW_INCOMING_PAYMENT_NOTIFICATION -> {
                        try {
                            val amount = (call.argument<Number>("amountNaira")?.toDouble()) ?: 0.0
                            val sender = call.argument<String>("senderName") ?: "Customer"
                            val totalToday = call.argument<Number>("todayTotalNaira")?.toDouble()
                            val title = call.argument<String>("title") ?: "Cash Just Landed!"

                            showIncomingPaymentNotification(
                                title = title,
                                amountNaira = amount,
                                senderName = sender,
                                totalTodayNaira = totalToday,
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOTIFICATION_ERROR", e.message, null)
                        }
                    }

                    METHOD_OPEN_TTS_SETTINGS -> {
                        val opened = openTtsSettings()
                        result.success(opened)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_SECURE_ON -> {
                        try {
                            runOnUiThread {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SECURE_ERROR", e.message, null)
                        }
                    }
                    METHOD_SECURE_OFF -> {
                        try {
                            runOnUiThread {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SECURE_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JAILBREAK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_IS_ROOTED -> {
                        try {
                            val rooted = isDeviceRooted()
                            result.success(rooted)
                        } catch (e: Exception) {
                            result.error("JAILBREAK_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isDeviceRooted(): Boolean {
        try {
            // Check build tags
            val tags = android.os.Build.TAGS
            if (tags != null && tags.contains("test-keys")) return true

            // Common su paths
            val paths = arrayOf(
                "/system/app/Superuser.apk",
                "/sbin/su",
                "/system/bin/su",
                "/system/xbin/su",
                "/system/app/SuperSU.apk",
                "/system/bin/failsafe/su"
            )

            for (p in paths) {
                try {
                    if (File(p).exists()) return true
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }

        return false
    }

    private fun openTtsSettings(): Boolean {
        return try {
            val ttsIntent = Intent("com.android.settings.TTS_SETTINGS").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(ttsIntent)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                val fallbackIntent = Intent(Settings.ACTION_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(fallbackIntent)
                true
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun showIncomingPaymentNotification(
        title: String,
        amountNaira: Double,
        senderName: String,
        totalTodayNaira: Double?,
    ) {
        ensureNotificationChannel()

        val collapsedView = RemoteViews(packageName, R.layout.notification_incoming_payment)
        val expandedView = RemoteViews(packageName, R.layout.notification_incoming_payment)

        bindNotificationViews(collapsedView, title, amountNaira, senderName, totalTodayNaira)
        bindNotificationViews(expandedView, title, amountNaira, senderName, totalTodayNaira)

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        } ?: Intent(this, MainActivity::class.java)

        val pendingIntent = PendingIntent.getActivity(
            this,
            System.currentTimeMillis().toInt(),
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setContentIntent(pendingIntent)
            .setCustomContentView(collapsedView)
            .setCustomBigContentView(expandedView)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .build()

        NotificationManagerCompat.from(this)
            .notify((System.currentTimeMillis() % Int.MAX_VALUE).toInt(), notification)
    }

    private fun bindNotificationViews(
        view: RemoteViews,
        title: String,
        amountNaira: Double,
        senderName: String,
        totalTodayNaira: Double?,
    ) {
        val amountText = formatNaira(amountNaira)
        val totalTodayText = if (totalTodayNaira != null && totalTodayNaira > 0) {
            formatNaira(totalTodayNaira)
        } else {
            "--"
        }

        view.setTextViewText(R.id.tv_title, title)
        view.setTextViewText(R.id.tv_amount_value, amountText)
        view.setTextViewText(R.id.tv_sender_value, senderName.uppercase())
        view.setTextViewText(R.id.tv_daily_total_value, totalTodayText)
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = NOTIFICATION_CHANNEL_DESC
            enableVibration(true)
            enableLights(true)
            lightColor = Color.parseColor("#16C79A")
        }

        manager.createNotificationChannel(channel)
    }

    private fun formatNaira(amount: Double): String {
        val formatter = DecimalFormat("#,##0.00")
        return "₦${formatter.format(amount)}"
    }
}