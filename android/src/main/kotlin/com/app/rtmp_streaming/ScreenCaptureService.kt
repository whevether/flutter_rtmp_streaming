package com.app.rtmp_streaming

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/** Owns the foreground notification required for MediaProjection on Android 10+. */
class ScreenCaptureService : Service() {
    inner class CaptureBinder : Binder() {
        fun createProjection(resultCode: Int, data: Intent, captureMicrophone: Boolean): MediaProjection {
            check(projection == null) { "Screen capture is already authorized; request fresh consent" }
            startCaptureForeground(captureMicrophone)
            val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            return requireNotNull(manager.getMediaProjection(resultCode, data)).also { capture ->
                projection = capture
                capture.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        projection = null
                        stopSelf()
                    }
                }, Handler(Looper.getMainLooper()))
            }
        }
    }
    private val binder = CaptureBinder()
    private var projection: MediaProjection? = null

    private fun startCaptureForeground(captureMicrophone: Boolean) {
        val channelId = "rtmp_screen_capture"
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(channelId,
                "Screen sharing", NotificationManager.IMPORTANCE_LOW))
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId)
            else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.presence_video_online)
            .setContentTitle("Screen sharing is active")
            .setContentText(applicationInfo.loadLabel(packageManager))
            .setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 29) {
            var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            if (captureMicrophone && Build.VERSION.SDK_INT >= 30) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            startForeground(0x5254, notification, types)
        } else startForeground(0x5254, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder = binder
    override fun onDestroy() {
        val capture = projection
        projection = null
        runCatching { capture?.stop() }
        super.onDestroy()
    }
}
