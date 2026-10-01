package com.mgkcodes.fitness.run

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one activity, and the Android half of the run's live readout.
 *
 * **A run's figures on the lock screen.** While a run records, the app keeps a
 * notification up to date with the distance and the pace, and Android counts
 * the time on it by itself. A phone in an armband is a locked phone, and until
 * this the three numbers a runner looks at were behind the lock for the whole
 * of every run.
 *
 * **Its own notification, not the recording one.** The location plugin already
 * shows "Recording your run" for its foreground service, and that would be the
 * obvious thing to update. It cannot carry this: the plugin makes its channel
 * with no importance and private visibility, which a lock screen will not
 * show, and a channel's importance cannot be changed once it exists. So this
 * is a second notification on a channel of its own, quiet (no sound, no
 * vibration) and public.
 *
 * The Dart side is `PlatformLiveReadout`, and the channel name is written in
 * both. Everything here is best effort: a runner who refuses notifications
 * still records a run.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LIVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        askForNotifications()
                        result.success(true)
                    }
                    "show" -> {
                        show(
                            distance = call.argument<String>("distance") ?: "",
                            pace = call.argument<String>("pace") ?: "",
                            elapsedSeconds = (call.argument<Number>("elapsedSeconds") ?: 0).toLong(),
                            elapsed = call.argument<String>("elapsed") ?: "",
                            paused = call.argument<Boolean>("paused") ?: false,
                        )
                        result.success(true)
                    }
                    "end" -> {
                        notifications().cancel(LIVE_ID)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun notifications(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    /**
     * Android 13 and later hide every notification until the runner allows
     * them. Asked once, before a run, while they are still looking at the
     * screen: after two refusals Android stops showing the question at all,
     * and asking again on every run would only spend the second one.
     */
    private fun askForNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(ASKED, false)) return
        prefs.edit().putBoolean(ASKED, true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), LIVE_ID)
    }

    private fun show(
        distance: String,
        pace: String,
        elapsedSeconds: Long,
        elapsed: String,
        paused: Boolean,
    ) {
        val manager = notifications()
        // Low: on the lock screen and in the shade, with no sound and no
        // heads-up. It is refreshed every few seconds for an hour.
        manager.createNotificationChannel(
            NotificationChannel(
                LIVE_CHANNEL_ID,
                "Run in progress",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Distance, time and pace while a run is being recorded."
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(false)
            },
        )

        val open = packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = Notification.Builder(this, LIVE_CHANNEL_ID)
            // The mark as a single-colour silhouette, which is what a status
            // bar icon has to be.
            .setSmallIcon(R.mipmap.ic_launcher_monochrome)
            .setContentTitle("$distance  ·  $pace")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open)

        if (paused) {
            // Nothing counts while the run is paused.
            builder
                .setContentText("Paused at $elapsed")
                .setShowWhen(false)
        } else {
            // Android counts up from here by itself, every second, whether or
            // not the app is awake to say so.
            builder
                .setContentText("Recording your run")
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis() - elapsedSeconds * 1000)
                .setUsesChronometer(true)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setCategory(Notification.CATEGORY_WORKOUT)
        }
        // With the permission refused this posts nothing and throws nothing.
        manager.notify(LIVE_ID, builder.build())
    }

    private companion object {
        /** Also written in `PlatformLiveReadout` and `LiveRunChannel.swift`. */
        const val LIVE_CHANNEL = "com.mgkcodes.fitness.run/live"
        const val LIVE_CHANNEL_ID = "run_live"
        const val LIVE_ID = 4201
        const val PREFS = "run_live"
        const val ASKED = "asked_for_notifications"
    }
}
