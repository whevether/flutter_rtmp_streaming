package com.app.rtmp_streaming

import android.app.Activity
import android.content.Context
import com.app.rtmp_streaming.CameraPermissions.ResolutionPreset
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class NativeViewFactory(private val activity: Activity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    var cameraNativeView: CameraNativeView? = null
    var cameraName: String = "0"
    var preset: ResolutionPreset = ResolutionPreset.low
    var enableAudio: Boolean = false
    var dartMessenger: DartMessenger? = null

    /** Cached until CameraPreview's AndroidView creates the platform view. */
    var pendingAudioBitrate: Int? = null
    var pendingVideoBitrate: Int? = null
    var pendingFrameRate: Int? = null
    var pendingForceBt709Color: Boolean? = null
    var pendingRtmpShouldSendPings: Boolean? = null

    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val view = CameraNativeView(activity, enableAudio, preset, cameraName, dartMessenger)
        view.applyCachedEncoderSettings(
            audioBitrate = pendingAudioBitrate,
            videoBitrate = pendingVideoBitrate,
            frameRate = pendingFrameRate,
            forceBt709Color = pendingForceBt709Color,
            rtmpShouldSendPings = pendingRtmpShouldSendPings,
        )
        cameraNativeView = view
        return view
    }
}