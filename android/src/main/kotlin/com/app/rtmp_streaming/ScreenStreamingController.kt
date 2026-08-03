package com.app.rtmp_streaming

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.video.ScreenSource
import com.pedro.library.generic.GenericStream
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * In-app screen capture streaming via MediaProjection + [GenericStream]/[ScreenSource].
 */
@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class ScreenStreamingController(
    private val activity: Activity,
    private val dartMessenger: DartMessenger?
) : ConnectChecker, PluginRegistry.ActivityResultListener {

    companion object {
        const val REQUEST_CODE = 4001
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingUrl: String? = null
    private var pendingProtocol: String = "rtmp"
    private var pendingBitrate: Int = 1200 * 1000
    private var genericStream: GenericStream? = null
    private var screenSource: ScreenSource? = null

    fun start(
        url: String,
        protocol: String,
        bitrate: Int,
        result: MethodChannel.Result
    ) {
        if (pendingResult != null) {
            result.error("startScreenStreaming", "Screen capture permission already pending", null)
            return
        }
        pendingUrl = url
        pendingProtocol = protocol
        pendingBitrate = bitrate
        pendingResult = result
        val mpm = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        activity.startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_CODE)
    }

    fun stop() {
        try {
            genericStream?.stopStream()
            genericStream?.release()
        } catch (e: Exception) {
            Log.w("ScreenStreaming", "stop: ${e.message}")
        }
        genericStream = null
        screenSource = null
    }

    fun isStreaming(): Boolean = genericStream?.isStreaming == true

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult
        pendingResult = null
        val url = pendingUrl
        pendingUrl = null
        if (result == null || url == null) return true
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.error("startScreenStreaming", "User denied screen capture", null)
            return true
        }
        try {
            val mpm = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = mpm.getMediaProjection(resultCode, data)
                ?: throw IllegalStateException("MediaProjection null")
            val source = ScreenSource(activity, projection)
            screenSource = source
            val stream = GenericStream(activity, this, source, MicrophoneSource())
            stream.getGlInterface().setForceRender(true, 15)
            val width = 720
            val height = 1280
            val prepared = stream.prepareVideo(width, height, pendingBitrate, rotation = 0) &&
                stream.prepareAudio(32000, true, 128 * 1000, echoCanceler = true, noiseSuppressor = true)
            if (!prepared) {
                result.error("startScreenStreaming", "prepareVideo/Audio failed", null)
                stream.release()
                return true
            }
            genericStream = stream
            stream.startStream(url)
            result.success(null)
        } catch (e: Exception) {
            result.error("startScreenStreaming", e.message, null)
        }
        return true
    }

    override fun onConnectionStarted(url: String) {}
    override fun onConnectionSuccess() {
        dartMessenger?.send(DartMessenger.EventType.SUCCESS, "connection success")
    }
    override fun onConnectionFailed(reason: String) {
        dartMessenger?.send(DartMessenger.EventType.ERROR, reason)
    }
    override fun onNewBitrate(bitrate: Long) {}
    override fun onDisconnect() {
        dartMessenger?.send(DartMessenger.EventType.RTMP_STOPPED, "screen disconnected")
    }
    override fun onAuthError() {
        dartMessenger?.send(DartMessenger.EventType.ERROR, "Auth error")
    }
    override fun onAuthSuccess() {}
}
