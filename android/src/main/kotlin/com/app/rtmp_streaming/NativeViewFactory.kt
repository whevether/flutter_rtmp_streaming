package com.app.rtmp_streaming

import android.app.Activity
import android.content.Context
import com.app.rtmp_streaming.CameraPermissions.ResolutionPreset
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class NativeViewFactory(var activity: Activity?) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    var cameraNativeView: CameraNativeView? = null
    var cameraName: String = "0"
    var preset: ResolutionPreset = ResolutionPreset.low
    var enableAudio: Boolean = false
    var dartMessenger: DartMessenger? = null

    /** Cached until CameraPreview's AndroidView creates the platform view. */
    var pendingRtmpMetadata: Map<String, Any>? = null
    var pendingAudioBitrate: Int? = null
    var pendingVideoBitrate: Int? = null
    var pendingVideoWidth: Int? = null
    var pendingVideoHeight: Int? = null
    var pendingFrameInterval: Int? = null
    var pendingFrameRate: Int? = null
    var pendingForceBt709Color: Boolean? = null
    var pendingRtmpShouldSendPings: Boolean? = null
    var pendingVideoCodec: String? = null
    var pendingAudioCodec: String? = null
    var pendingEchoCanceler: Boolean? = null
    var pendingNoiseSuppressor: Boolean? = null
    var pendingVideoSource: String? = null
    var pendingUseBufferAudio: Boolean? = null

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val view = CameraNativeView(requireNotNull(activity) { "Activity not attached" }, enableAudio, preset, cameraName, dartMessenger, context)
        view.applyCachedEncoderSettings(
            audioBitrate = pendingAudioBitrate,
            videoBitrate = pendingVideoBitrate,
            frameRate = pendingFrameRate,
            forceBt709Color = pendingForceBt709Color,
            rtmpShouldSendPings = pendingRtmpShouldSendPings,
            videoCodec = pendingVideoCodec,
            audioCodec = pendingAudioCodec,
            echoCanceler = pendingEchoCanceler,
            noiseSuppressor = pendingNoiseSuppressor,
            videoSource = pendingVideoSource,
            useBufferAudio = pendingUseBufferAudio,
        )
        pendingRtmpMetadata?.let { metadata ->
            view.setRtmpMetadata(metadata, object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(code: String, message: String?, details: Any?) {}
                override fun notImplemented() {}
            })
        }
        if (pendingVideoWidth != null || pendingFrameInterval != null) {
            view.setVideoSettings(null, pendingVideoWidth, pendingVideoHeight, pendingFrameInterval,
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(code: String, message: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
        }
        cameraNativeView = view
        return view
    }
}
