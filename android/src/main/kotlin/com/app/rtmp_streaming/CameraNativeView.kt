package com.app.rtmp_streaming

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.hardware.camera2.CameraAccessException
import android.media.MediaPlayer
import android.os.Build
import android.os.SystemClock
import com.pedro.encoder.input.gl.render.filters.BaseFilterRender
import android.util.Log
import android.util.Size
import android.view.Surface
import android.view.SurfaceHolder
import android.view.View
import androidx.annotation.RequiresApi
import com.app.rtmp_streaming.CameraPermissions.ResolutionPreset
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.gl.SpriteGestureController
import com.pedro.encoder.input.gl.render.filters.BasicDeformationFilterRender
import com.pedro.encoder.input.gl.render.filters.BeautyFilterRender
import com.pedro.encoder.input.gl.render.filters.BlackFilterRender
import com.pedro.encoder.input.gl.render.filters.BlurFilterRender
import com.pedro.encoder.input.gl.render.filters.BrightnessFilterRender
import com.pedro.encoder.input.gl.render.filters.CartoonFilterRender
import com.pedro.encoder.input.gl.render.filters.ChromaFilterRender
import com.pedro.encoder.input.gl.render.filters.ChromaticAberrationFilterRender
import com.pedro.encoder.input.gl.render.filters.CircleFilterRender
import com.pedro.encoder.input.gl.render.filters.ColorFilterRender
import com.pedro.encoder.input.gl.render.filters.ContrastFilterRender
import com.pedro.encoder.input.gl.render.filters.CropFilterRender
import com.pedro.encoder.input.gl.render.filters.DistortedTvFilterRender
import com.pedro.encoder.input.gl.render.filters.DuotoneFilterRender
import com.pedro.encoder.input.gl.render.filters.EarlyBirdFilterRender
import com.pedro.encoder.input.gl.render.filters.EdgeDetectionFilterRender
import com.pedro.encoder.input.gl.render.filters.ExposureFilterRender
import com.pedro.encoder.input.gl.render.filters.FireFilterRender
import com.pedro.encoder.input.gl.render.filters.GammaFilterRender
import com.pedro.encoder.input.gl.render.filters.GlitchFilterRender
import com.pedro.encoder.input.gl.render.filters.GreyScaleFilterRender
import com.pedro.encoder.input.gl.render.filters.HalftoneLinesFilterRender
import com.pedro.encoder.input.gl.render.filters.Image70sFilterRender
import com.pedro.encoder.input.gl.render.filters.LamoishFilterRender
import com.pedro.encoder.input.gl.render.filters.MoneyFilterRender
import com.pedro.encoder.input.gl.render.filters.NegativeFilterRender
import com.pedro.encoder.input.gl.render.filters.NoiseFilterRender
import com.pedro.encoder.input.gl.render.filters.PixelatedFilterRender
import com.pedro.encoder.input.gl.render.filters.PolygonizationFilterRender
import com.pedro.encoder.input.gl.render.filters.RGBSaturationFilterRender
import com.pedro.encoder.input.gl.render.filters.RainbowFilterRender
import com.pedro.encoder.input.gl.render.filters.RippleFilterRender
import com.pedro.encoder.input.gl.render.filters.RotationFilterRender
import com.pedro.encoder.input.gl.render.filters.SaturationFilterRender
import com.pedro.encoder.input.gl.render.filters.SepiaFilterRender
import com.pedro.encoder.input.gl.render.filters.SharpnessFilterRender
import com.pedro.encoder.input.gl.render.filters.SnowFilterRender
import com.pedro.encoder.input.gl.render.filters.TemperatureFilterRender
import com.pedro.encoder.input.gl.render.filters.ZebraFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.GifFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.ImageFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.SurfaceFilterRender
import com.pedro.encoder.input.gl.render.filters.`object`.TextFilterRender
import com.pedro.encoder.input.audio.NoAudioEffect
import com.pedro.encoder.input.audio.PitchShiftEffect
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.video.Camera2Source
import com.pedro.encoder.input.video.CameraHelper
import com.pedro.encoder.input.video.CameraHelper.Facing.BACK
import com.pedro.encoder.utils.gl.AspectRatioMode
import com.pedro.encoder.utils.gl.TranslateTo
import com.pedro.library.generic.GenericCamera2
import com.pedro.library.generic.GenericStream
import com.pedro.library.util.streamclient.GenericStreamClient
import com.pedro.library.util.streamclient.RtmpStreamClient
import com.pedro.library.util.streamclient.WhipStreamClient
import com.pedro.library.whip.WhipStream
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import com.pedro.library.view.OpenGlView
import com.pedro.common.AudioCodec
import com.pedro.common.StreamingStatsReport
import com.pedro.common.VideoCodec
import com.pedro.encoder.input.sources.audio.BufferAudioSource
import com.pedro.encoder.input.sources.video.ScreenSource
import com.pedro.extrasources.CameraUvcSource
import com.pedro.extrasources.CameraXSource
import com.pedro.library.multiple.MultiCamera2
import com.pedro.library.multiple.MultiType
import com.pedro.library.util.QueueAwareBitrateAdapter
import android.content.Context
import android.media.projection.MediaProjection
import android.view.MotionEvent
import java.io.*
import java.util.Locale


class CameraNativeView(
    private var activity: Activity? = null,
    private var enableAudio: Boolean = false,
    private val preset: ResolutionPreset,
    private var cameraName: String,
    private var dartMessenger: DartMessenger? = null
) :
    PlatformView,
    SurfaceHolder.Callback,
    ConnectChecker {
    private val glView = OpenGlView(activity)
    private val genericCamera: GenericCamera2
    /** WHIP uses StreamBase API; non-null only while WHIP streaming. */
    private var whipStream: WhipStream? = null
    private var isSurfaceCreated = false
    private var fps = 0
    private val aBitrate = 128 * 1000
    private val vBitrate = 1200 * 1000
    private var queueBitrateAdapter: QueueAwareBitrateAdapter
    private var lastStreamingStats: StreamingStatsReport? = null
    private var videoCodec: VideoCodec = VideoCodec.H264
    private var audioCodec: AudioCodec = AudioCodec.AAC
    private var echoCanceler: Boolean = false
    private var noiseSuppressor: Boolean = false
    private var videoSourceMode: String = "camera2" // camera2|cameraX|uvc|screen
    private var bufferAudioSource: BufferAudioSource? = null
    private var useBufferAudio: Boolean = false
    private var multiCamera: MultiCamera2? = null
    /** StreamBase path for CameraX / UVC / screen / buffer-audio on RTMP/RTSP/SRT/UDP. */
    private var genericStream: GenericStream? = null
    private var multiDestinations: MutableList<MultiDest> = mutableListOf()
    private var screenMediaProjection: MediaProjection? = null
    data class MultiDest(
        val id: String,
        val url: String,
        val protocol: String,
        val type: MultiType,
        val index: Int
    )
  val spriteGestureController = SpriteGestureController()
    /** 当前已设置的滤镜实例，removeFilter 必须用同一实例才能生效 */
    private var currentFilter: BaseFilterRender? = null
    private var currentFilterType: Int? = null
    /** RootEncoder PitchShiftEffect；pitch≈1 时使用 NoAudioEffect */
    private var pitchShiftEffect: PitchShiftEffect? = null
    /** Overlay object filter (text/image); cleared via clearOverlay */
    private var overlayFilter: BaseFilterRender? = null
    /** RootEncoder 2.7.0+：下一帧编码使用 BT.709 色彩（在 prepare 前设置） */
    private var forceBt709Color: Boolean = false
    /** RootEncoder 2.7.0+：RTMP 周期 ping，用于 RTT（须在与 startStream 前对 RtmpStreamClient 设置） */
    private var rtmpShouldSendPings: Boolean = false
    /** 自定义音频码率（bps），在 prepareAudio 时使用 */
    private var customAudioBitrate: Int? = null
    /** 自定义视频帧率，在 prepareVideo / startPreview 时使用 */
    private var customVideoFps: Int? = null
    /** 自定义视频码率（bps），推流中可通过 setVideoBitrateOnFly 热更新 */
    private var customVideoBitrate: Int? = null
    /** 切后台前正在推流时，Surface 重建后自动恢复 */
    private var lastStreamUrl: String? = null
    private var lastStreamBitrate: Int? = null
    private var lastStreamProtocol: String? = null
    private var lastWhipToken: String? = null
    private var resumeStreamAfterSurfaceCreated = false
    /** 因 Surface 销毁暂停推流时，忽略 stopStream 触发的 onDisconnect */
    private var isRestoringFromSurfaceDestroy = false
    private var currentProtocol: String = "rtmp"
    init {
//        glView.isKeepAspectRatio = true
        glView.setAspectRatioMode(AspectRatioMode.Adjust)
        glView.holder.addCallback(this)
        genericCamera = GenericCamera2(glView, this)
        genericCamera.streamClient.setReTries(10)
        genericCamera.setFpsListener { fps = it }
        queueBitrateAdapter = QueueAwareBitrateAdapter(vBitrate + aBitrate) { adapted ->
            val audio = customAudioBitrate ?: aBitrate
            val videoBitrate = (adapted - audio).coerceAtLeast(adapted / 10)
            when {
                whipStream?.isStreaming == true -> whipStream?.setVideoBitrateOnFly(videoBitrate)
                multiCamera != null -> multiCamera?.setVideoBitrateOnFly(videoBitrate)
                genericStream?.isStreaming == true -> genericStream?.setVideoBitrateOnFly(videoBitrate)
                else -> genericCamera.setVideoBitrateOnFly(videoBitrate)
            }
        }
    }

    private fun isStreamingNow(): Boolean =
        whipStream?.isStreaming == true ||
            multiCamera?.isStreaming == true ||
            genericStream?.isStreaming == true ||
            genericCamera.isStreaming

    private fun needsStreamBasePath(): Boolean =
        videoSourceMode != "camera2" || useBufferAudio

    private fun rtmpStreamClientOrNull(): RtmpStreamClient? {
        return try {
            val field = GenericStreamClient::class.java.getDeclaredField("rtmpClient")
            field.isAccessible = true
            field.get(genericCamera.streamClient) as? RtmpStreamClient
        } catch (_: Exception) {
            null
        }
    }

    private fun validateProtocolAndUrl(protocol: String, url: String): String? {
        val lower = url.lowercase(Locale.getDefault())
        return when (protocol) {
            "rtmp" -> if (lower.startsWith("rtmp")) null else "URL must start with rtmp:// or rtmps://"
            "rtsp" -> if (lower.startsWith("rtsp")) null else "URL must start with rtsp:// or rtsps://"
            "srt" -> if (lower.startsWith("srt")) null else "URL must start with srt://"
            "udp" -> if (lower.startsWith("udp")) null else "URL must start with udp://"
            "whip" -> if (lower.startsWith("http://") || lower.startsWith("https://")) null
                else "WHIP URL must start with http:// or https://"
            else -> "Unsupported protocol: $protocol"
        }
    }

    private fun applyRtmpPingsIfNeeded() {
        if (currentProtocol == "rtmp") {
            rtmpStreamClientOrNull()?.shouldSendPings(rtmpShouldSendPings)
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d("CameraNativeView", "surfaceCreated")
        isSurfaceCreated = true
        glView.post { restorePreviewAfterSurfaceChange() }
    }

    override fun surfaceChanged(p0: SurfaceHolder, p1: Int, p2: Int, p3: Int) {
        // TODO("Not yet implemented")
    }

    override fun surfaceDestroyed(p0: SurfaceHolder) {
        Log.d("CameraNativeView", "surfaceDestroyed")
        if (isStreamingNow()) {
            resumeStreamAfterSurfaceCreated = true
            isRestoringFromSurfaceDestroy = true
            try {
                stopActiveStream(restorePreview = false)
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stopStream on surfaceDestroyed failed", e)
                isRestoringFromSurfaceDestroy = false
                resumeStreamAfterSurfaceCreated = false
            }
        }
        try {
            if (multiCamera?.isOnPreview == true) {
                multiCamera?.stopCamera()
            }
        } catch (e: Exception) {
            Log.e("CameraNativeView", "stop multiCamera on surfaceDestroyed failed", e)
        }
        if (genericCamera.isOnPreview) {
            try {
                genericCamera.stopCamera()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stopCamera on surfaceDestroyed failed", e)
            }
        }
        isSurfaceCreated = false
    }

    override fun onConnectionStarted(url: String) {
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.WAIT, "connection wait")
        }
    }

    override fun onConnectionSuccess() {
        isRestoringFromSurfaceDestroy = false
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.SUCCESS, "connection success")
        }
    }

    override fun onNewBitrate(bitrate: Long) {
        // ABR is driven by onStreamingStats + QueueAwareBitrateAdapter.
    }

    override fun onStreamingStats(report: StreamingStatsReport) {
        lastStreamingStats = report
        if (whipStream != null) return
        queueBitrateAdapter.onStreamingStats(report)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    override fun onConnectionFailed(reason: String) {
        activity?.runOnUiThread {
            val streamClient = when {
                whipStream != null -> whipStream?.getStreamClient()
                multiCamera != null -> {
                    val dest = multiDestinations.firstOrNull()
                    if (dest != null) multiCamera?.getStreamClient(dest.type, dest.index) else null
                }
                genericStream != null -> genericStream?.getStreamClient()
                else -> genericCamera.streamClient
            }
            if (streamClient != null && streamClient.reTry(5000, reason)) {
                dartMessenger?.send(DartMessenger.EventType.RTMP_RETRY, reason)
            } else {
                dartMessenger?.send(DartMessenger.EventType.RTMP_STOPPED, "Failed retry")
                isRestoringFromSurfaceDestroy = false
                stopActiveStream()
            }
        }
    }

    override fun onDisconnect() {
        if (isRestoringFromSurfaceDestroy) {
            Log.d("CameraNativeView", "onDisconnect ignored during surface restore")
            return
        }
        activity?.runOnUiThread {
            dartMessenger?.sendCameraClosingEvent()
        }
    }

    override fun onAuthError() {
        activity?.runOnUiThread {
            dartMessenger?.send(DartMessenger.EventType.ERROR, "Auth error")
        }
    }

    override fun onAuthSuccess() {
    }

    private fun applyCodecsToGenericCamera() {
        genericCamera.setVideoCodec(videoCodec)
        genericCamera.setAudioCodec(audioCodec)
    }

    private fun prepareAudioEncoder(): Boolean {
        if (!enableAudio) {
            return true
        }
        val bitrate = customAudioBitrate ?: aBitrate
        return genericCamera.prepareAudio(bitrate, 32000, true, echoCanceler, noiseSuppressor)
    }

    private fun prepareVideoEncoder(size: Size, bitrate: Int): Boolean {
        applyCodecsToGenericCamera()
        val fps = customVideoFps ?: 30
        val rotation = CameraHelper.getCameraOrientation(getActivity() ?: glView.context)
        return genericCamera.prepareVideo(size.width, size.height, fps, bitrate, rotation)
    }

    fun prepareForVideoStreaming(result: MethodChannel.Result) {
        // Android 无需预准备音频，与 iOS 行为对齐为 no-op
        result.success(null)
    }

    fun getHasAudio(result: MethodChannel.Result) {
        result.success(!genericCamera.isAudioMuted)
    }

    fun setHasAudio(isEnable: Boolean?, result: MethodChannel.Result) {
        if (isEnable == null) {
            result.error("setHasAudio", "isEnable is required", null)
            return
        }
        try {
            if (isEnable) {
                genericCamera.enableAudio()
            } else {
                genericCamera.disableAudio()
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("setHasAudio", e.message, null)
        }
    }

    fun getHasVideo(result: MethodChannel.Result) {
        val muted = genericCamera.glInterface?.isVideoMuted ?: false
        result.success(!muted)
    }

    fun setHasVideo(isEnable: Boolean?, result: MethodChannel.Result) {
        if (isEnable == null) {
            result.error("setHasVideo", "isEnable is required", null)
            return
        }
        try {
            val gl = genericCamera.glInterface
            if (gl == null) {
                result.error("setHasVideo", "OpenGL interface not available", null)
                return
            }
            if (isEnable) {
                gl.unMuteVideo()
            } else {
                gl.muteVideo()
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("setHasVideo", e.message, null)
        }
    }

    /** Apply settings that were set after Dart [initialize] but before AndroidView was created. */
    fun applyCachedEncoderSettings(
        audioBitrate: Int?,
        videoBitrate: Int?,
        frameRate: Int?,
        forceBt709Color: Boolean?,
        rtmpShouldSendPings: Boolean?,
        videoCodec: String? = null,
        audioCodec: String? = null,
        echoCanceler: Boolean? = null,
        noiseSuppressor: Boolean? = null,
        videoSource: String? = null,
        useBufferAudio: Boolean? = null,
    ) {
        if (audioBitrate != null) {
            customAudioBitrate = audioBitrate
        }
        if (videoBitrate != null) {
            customVideoBitrate = videoBitrate
        }
        if (frameRate != null && frameRate > 0) {
            customVideoFps = frameRate
            try {
                genericCamera.glInterface?.forceFpsLimit(frameRate)
            } catch (_: Exception) {
            }
        }
        if (forceBt709Color != null) {
            this.forceBt709Color = forceBt709Color
            try {
                genericCamera.forceBt709Color(forceBt709Color)
            } catch (_: Exception) {
            }
        }
        if (rtmpShouldSendPings != null) {
            this.rtmpShouldSendPings = rtmpShouldSendPings
        }
        if (echoCanceler != null) {
            this.echoCanceler = echoCanceler
        }
        if (noiseSuppressor != null) {
            this.noiseSuppressor = noiseSuppressor
        }
        if (!videoSource.isNullOrBlank()) {
            videoSourceMode = videoSource.lowercase(Locale.getDefault())
        }
        if (useBufferAudio != null) {
            this.useBufferAudio = useBufferAudio
            if (useBufferAudio && bufferAudioSource == null) {
                bufferAudioSource = BufferAudioSource()
            }
            if (!useBufferAudio) {
                bufferAudioSource = null
            }
        }
        if (!videoCodec.isNullOrBlank()) {
            parseVideoCodec(videoCodec)?.let {
                this.videoCodec = it
                try {
                    genericCamera.setVideoCodec(it)
                } catch (_: Exception) {
                }
            }
        }
        if (!audioCodec.isNullOrBlank()) {
            parseAudioCodec(audioCodec)?.let {
                this.audioCodec = it
                try {
                    genericCamera.setAudioCodec(it)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun parseVideoCodec(name: String): VideoCodec? {
        return when (name.lowercase(Locale.getDefault())) {
            "h264", "avc" -> VideoCodec.H264
            "h265", "hevc" -> VideoCodec.H265
            "av1" -> VideoCodec.AV1
            "vp8" -> VideoCodec.VP8
            "vp9" -> VideoCodec.VP9
            else -> null
        }
    }

    private fun parseAudioCodec(name: String): AudioCodec? {
        return when (name.lowercase(Locale.getDefault()).replace('-', '_')) {
            "aac" -> AudioCodec.AAC
            "he_aac", "heaac" -> AudioCodec.HE_AAC
            "opus" -> AudioCodec.OPUS
            "g711", "g711_alaw", "alaw" -> AudioCodec.G711
            else -> null
        }
    }

    fun setAudioSettings(bitrate: Int?, result: MethodChannel.Result) {
        if (bitrate == null) {
            result.error("setAudioSettings", "bitrate is required", null)
            return
        }
        customAudioBitrate = bitrate
        result.success(null)
    }

    fun setVideoSettings(
        bitrate: Int?,
        width: Int?,
        height: Int?,
        frameInterval: Int?,
        result: MethodChannel.Result
    ) {
        try {
            if (bitrate != null) {
                customVideoBitrate = bitrate
                when {
                    whipStream?.isStreaming == true -> whipStream?.setVideoBitrateOnFly(bitrate)
                    multiCamera?.isStreaming == true -> multiCamera?.setVideoBitrateOnFly(bitrate)
                    genericStream?.isStreaming == true -> genericStream?.setVideoBitrateOnFly(bitrate)
                    genericCamera.isStreaming -> genericCamera.setVideoBitrateOnFly(bitrate)
                }
            }
            if (frameInterval != null) {
                // RootEncoder 在推流中修改 I 帧间隔需重新 prepare，此处仅记录供文档说明
                Log.w("CameraNativeView", "setVideoSettings frameInterval ignored on Android during stream")
            }
            if (width != null && height != null && !genericCamera.isStreaming) {
                Log.w("CameraNativeView", "setVideoSettings width/height apply on next startVideoStreaming")
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("setVideoSettings", e.message, null)
        }
    }

    fun setFrameRate(frameRate: Int?, result: MethodChannel.Result) {
        if (frameRate == null || frameRate <= 0) {
            result.error("setFrameRate", "frameRate must be > 0", null)
            return
        }
        customVideoFps = frameRate
        try {
            genericCamera.glInterface?.forceFpsLimit(frameRate)
            result.success(null)
        } catch (e: Exception) {
            result.error("setFrameRate", e.message, null)
        }
    }

    fun takePicture(filePath: String, result: MethodChannel.Result) {
        Log.d("CameraNativeView", "takePicture filePath: $filePath result: $result")
        val file: File = File(filePath)
        if (file.exists()) {
            result.error(
                "fileExists",
                "File at path '$filePath' already exists. Cannot overwrite.",
                null
            )
            return
        }
        glView.takePhoto {
            try {
                val outputStream: OutputStream = BufferedOutputStream(FileOutputStream(file))
                it.compress(Bitmap.CompressFormat.JPEG, 100, outputStream)
                outputStream.close()
                view.post { result.success(null) }
            } catch (e: IOException) {
                result.error("IOError", "Failed saving image", null)
            }
        }
    }

    fun startVideoRecording(filePath: String?, result: MethodChannel.Result) {
        if (filePath == null) {
            result.error("fileExists", "Must specify a filePath.", null)
            return
        }

        val file = File(filePath)
        if (file.exists()) {
            result.error(
                "fileExists",
                "File at path '$filePath' already exists. Cannot overwrite.",
                null
            )
            return
        }
        Log.d("CameraNativeView", "startVideoRecording filePath: $filePath result: $result")


        /*if (genericCamera.isRecording || genericCamera.prepareAudio() && genericCamera.prepareVideo(
                streamingSize.videoFrameWidth,
                streamingSize.videoFrameHeight,
                streamingSize.videoBitRate
            )*/
        //判断如果不是视频流的话并且其用了音频
        try {
            if (!genericCamera.isStreaming) {
                val streamingSize = CameraUtils.computeBestPreviewSize(activity, cameraName, preset)
                val size = streamingSize["size"] as Size
                val bitrateRes = streamingSize["bitrate"] as Int
                genericCamera.forceBt709Color(forceBt709Color)
                if (prepareAudioEncoder() && prepareVideoEncoder(
                        size,
                        bitrateRes
                    )
                ) {
                    genericCamera.startRecord(filePath)
                }

            } else {
                genericCamera.startRecord(filePath)
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoRecordingFailed", e.message, null)
        }

    }


    fun startVideoStreaming(
        url: String?,
        bitrate: Int?,
        protocol: String?,
        whipToken: String?,
        result: MethodChannel.Result
    ) {
        Log.d("CameraNativeView", "startVideoStreaming url: $url protocol: $protocol")
        if (url == null) {
            result.error("startVideoStreaming", "Must specify a url.", null)
            return
        }
        val proto = (protocol ?: "rtmp").lowercase(Locale.getDefault())
        validateProtocolAndUrl(proto, url)?.let {
            result.error("startVideoStreaming", it, null)
            return
        }

        try {
            if (isStreamingNow()) {
                // Restart: stop current session then start the new URL.
                stopActiveStream(restorePreview = false)
            }
            currentProtocol = proto
            lastStreamUrl = url
            lastStreamBitrate = bitrate
            lastStreamProtocol = proto
            lastWhipToken = whipToken

            if (proto == "whip") {
                startWhipStreaming(url, bitrate, whipToken, result)
            } else {
                startGenericStreaming(url, bitrate, result)
            }
        } catch (e: CameraAccessException) {
            result.error("videoStreamingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoStreamingFailed", e.message, null)
        } catch (e: Exception) {
            result.error("videoStreamingFailed", e.message, null)
        }
    }

    private fun startGenericStreaming(url: String, bitrate: Int?, result: MethodChannel.Result) {
        if (needsStreamBasePath()) {
            startGenericStreamBaseStreaming(url, bitrate, result)
            return
        }
        val streamingSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
        val size = streamingSize["size"] as Size
        val bitrateRes = customVideoBitrate ?: (bitrate ?: (streamingSize["bitrate"] as Int))
        genericCamera.forceBt709Color(forceBt709Color)
        applyRtmpPingsIfNeeded()
        if (genericCamera.isRecording || prepareAudioEncoder() && prepareVideoEncoder(size, bitrateRes)) {
            genericCamera.startStream(url)
            result.success(null)
        } else {
            result.error(
                "videoStreamingFailed",
                "Error preparing stream, This device cant do it",
                null
            )
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun startGenericStreamBaseStreaming(
        url: String,
        bitrate: Int?,
        result: MethodChannel.Result
    ) {
        val ctx = getActivity() ?: glView.context
        if (genericCamera.isOnPreview) {
            try {
                genericCamera.stopCamera()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stopCamera before GenericStream failed", e)
            }
        }
        stopGenericStreamInternal(restorePreview = false)

        val stream = GenericStream(ctx, this)
        stream.getStreamClient().setReTries(10)
        stream.setVideoCodec(videoCodec)
        stream.setAudioCodec(audioCodec)

        val streamingSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
        val size = streamingSize["size"] as Size
        val bitrateRes = customVideoBitrate ?: (bitrate ?: (streamingSize["bitrate"] as Int))
        val fpsValue = customVideoFps ?: 30
        val rotation = CameraHelper.getCameraOrientation(ctx)
        val audioOk = if (!enableAudio) {
            true
        } else {
            val ab = customAudioBitrate ?: aBitrate
            stream.prepareAudio(
                sampleRate = 32000,
                isStereo = true,
                bitrate = ab,
                echoCanceler = echoCanceler,
                noiseSuppressor = noiseSuppressor
            )
        }
        val videoOk = stream.prepareVideo(
            size.width, size.height, bitrateRes, fpsValue, 2, rotation
        )
        if (!audioOk || !videoOk) {
            result.error(
                "videoStreamingFailed",
                "Error preparing stream (StreamBase), This device cant do it",
                null
            )
            return
        }
        try {
            applyPreferredVideoSourceToStreamBase(stream, ctx)
        } catch (e: Exception) {
            result.error("videoStreamingFailed", e.message, null)
            return
        }
        if (useBufferAudio) {
            val buf = bufferAudioSource ?: BufferAudioSource().also { bufferAudioSource = it }
            try {
                stream.changeAudioSource(buf)
            } catch (e: Exception) {
                result.error("videoStreamingFailed", e.message, null)
                return
            }
        }
        try {
            stream.forceBt709Color(forceBt709Color)
        } catch (_: Exception) {
        }
        stream.setFpsListener { fps = it }
        stream.startPreview(glView)
        // RTMP pings via GenericStreamClient reflection if needed
        if (currentProtocol == "rtmp" && rtmpShouldSendPings) {
            try {
                val field = GenericStreamClient::class.java.getDeclaredField("rtmpClient")
                field.isAccessible = true
                (field.get(stream.getStreamClient()) as? RtmpStreamClient)
                    ?.shouldSendPings(true)
            } catch (_: Exception) {
            }
        }
        stream.startStream(url)
        genericStream = stream
        result.success(null)
    }

    private fun stopGenericStreamInternal(restorePreview: Boolean) {
        genericStream?.let { stream ->
            try {
                if (stream.isStreaming) stream.stopStream()
                if (stream.isOnPreview) stream.stopPreview()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stop GenericStream failed", e)
            }
            genericStream = null
            if (restorePreview && isSurfaceCreated) {
                startPreview(cameraName)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun startWhipStreaming(
        url: String,
        bitrate: Int?,
        whipToken: String?,
        result: MethodChannel.Result
    ) {
        val ctx = getActivity() ?: glView.context
        // Release Camera2 preview so WhipStream can own the camera / surface.
        if (genericCamera.isOnPreview) {
            try {
                genericCamera.stopCamera()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stopCamera before WHIP failed", e)
            }
        }
        whipStream?.let { existing ->
            try {
                if (existing.isStreaming) existing.stopStream()
                if (existing.isOnPreview) existing.stopPreview()
            } catch (_: Exception) {
            }
            whipStream = null
        }

        val stream = WhipStream(ctx, this)
        stream.getStreamClient().setReTries(10)
        if (!whipToken.isNullOrEmpty()) {
            (stream.getStreamClient() as? WhipStreamClient)?.setAuthorization(whipToken)
                ?: stream.getStreamClient().setAuthorization(whipToken, null)
        }

        stream.setVideoCodec(videoCodec)
        stream.setAudioCodec(audioCodec)

        val streamingSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
        val size = streamingSize["size"] as Size
        val bitrateRes = customVideoBitrate ?: (bitrate ?: (streamingSize["bitrate"] as Int))
        val fpsValue = customVideoFps ?: 30
        val rotation = CameraHelper.getCameraOrientation(ctx)
        val audioOk = if (!enableAudio) {
            true
        } else {
            val ab = customAudioBitrate ?: aBitrate
            stream.prepareAudio(
                sampleRate = 32000,
                isStereo = true,
                bitrate = ab,
                echoCanceler = echoCanceler,
                noiseSuppressor = noiseSuppressor
            )
        }
        val videoOk = stream.prepareVideo(
            size.width, size.height, bitrateRes, fpsValue, 2, rotation
        )
        if (!audioOk || !videoOk) {
            result.error(
                "videoStreamingFailed",
                "Error preparing WHIP stream, This device cant do it",
                null
            )
            return
        }
        // changeVideoSource / changeAudioSource must run after prepare*.
        try {
            applyPreferredVideoSourceToWhip(stream, ctx)
        } catch (e: Exception) {
            result.error("videoStreamingFailed", e.message, null)
            return
        }
        if (useBufferAudio) {
            val buf = bufferAudioSource ?: BufferAudioSource().also { bufferAudioSource = it }
            try {
                stream.changeAudioSource(buf)
            } catch (e: Exception) {
                result.error("videoStreamingFailed", e.message, null)
                return
            }
        }
        try {
            stream.forceBt709Color(forceBt709Color)
        } catch (_: Exception) {
        }
        stream.setFpsListener { fps = it }
        stream.startPreview(glView)
        stream.startStream(url)
        whipStream = stream
        result.success(null)
    }

    private fun stopActiveStream(restorePreview: Boolean = true) {
        val hadMulti = multiCamera != null
        stopMultiStreamingInternal(restorePreview = false)
        if (genericStream != null) {
            stopGenericStreamInternal(restorePreview = restorePreview)
            return
        }
        whipStream?.let { stream ->
            try {
                if (stream.isStreaming) stream.stopStream()
                if (stream.isOnPreview) stream.stopPreview()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stop WHIP stream failed", e)
            }
            whipStream = null
            if (restorePreview && isSurfaceCreated) {
                startPreview(cameraName)
            }
            return
        }
        if (genericCamera.isStreaming) {
            genericCamera.stopStream()
        }
        if (hadMulti && restorePreview && isSurfaceCreated) {
            startPreview(cameraName)
        }
    }

    private fun stopMultiStreamingInternal(restorePreview: Boolean = true) {
        val mc = multiCamera ?: return
        for (dest in multiDestinations.toList()) {
            try {
                mc.stopStream(dest.type, dest.index)
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stop multi dest ${dest.id} failed", e)
            }
        }
        try {
            if (mc.isOnPreview) {
                mc.stopCamera()
            }
        } catch (e: Exception) {
            Log.e("CameraNativeView", "stop multi camera preview failed", e)
        }
        multiCamera = null
        multiDestinations.clear()
        lastStreamingStats = null
        if (restorePreview && isSurfaceCreated && whipStream == null) {
            startPreview(cameraName)
        }
    }

    fun startVideoRecordingAndStreaming(
        filePath: String?,
        url: String?,
        bitrate: Int?,
        protocol: String?,
        whipToken: String?,
        result: MethodChannel.Result
    ) {
        if (filePath == null) {
            result.error("fileExists", "Must specify a filePath.", null)
            return
        }
        if (File(filePath).exists()) {
            result.error("fileExists", "File at path '$filePath' already exists.", null)
            return
        }
        if (url == null) {
            result.error("fileExists", "Must specify a url.", null)
            return
        }
        val proto = (protocol ?: "rtmp").lowercase(Locale.getDefault())
        if (proto == "whip") {
            result.error(
                "videoRecordingFailed",
                "Recording while streaming is not supported for WHIP in this version.",
                null
            )
            return
        }
        try {
            startVideoRecording(filePath, result)
            startVideoStreaming(url, bitrate, protocol, whipToken, result)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IOException) {
            result.error("videoRecordingFailed", e.message, null)
        }
    }


    //开/关闪光灯
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchFlashLight(isEnable: Boolean?, result: MethodChannel.Result) {
        try {
            if(genericCamera.cameraFacing != BACK){
                result.error("switchFlashLightFailed", "camera is Not BACK", null)
                return
            }
             if (isEnable == null) {
                result.error("switchFlashLightFailed", "isEnable not empty.", null)
                return
            }
            if(isEnable == true){
                 genericCamera.enableLantern()
            }else{
                genericCamera.disableLantern()
            }
          result.success(null)
        } catch (e: CameraAccessException) {
            result.error("switchFlashLightFailed", e.message, null)
        } catch (e: IOException) {
            result.error("switchFlashLightFailed", e.message, null)
        }
    }

    //切换相机式
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchCamera(cameraId: String?, result: MethodChannel.Result) {

        try {
          if (cameraId == null) {
            result.error("cameraIdExist", "empty cameraId!", null)
            return
          }
          genericCamera.switchCamera(cameraId)
          cameraName = cameraId
          result.success(null)
        } catch (e: CameraAccessException) {
            result.error("switchCameraFailed", e.message, null)
        } catch (e: IOException) {
            result.error("switchCameraFailed", e.message, null)
        }


    }

    //开/关声音
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun switchAudio(isEnable: Boolean?,result: MethodChannel.Result) {
        try {
            if (isEnable == null) {
                result.error("switchAudioFailed", "empty isEnable!", null)
                return
            }
            if(isEnable == true){
                genericCamera.enableAudio()
            }else{
                genericCamera.disableAudio()
            }
          result.success(null)
        } catch (e: CameraAccessException) {
            result.error("switchAudioFailed", e.message, null)
        } catch (e: IOException) {
            result.error("switchAudioFailed", e.message, null)
        }
    }

    //设置滤镜
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun setFilter(type: Int?,filePath: String?, result: MethodChannel.Result) {
        try {
          if(type == null){
            result.error("setFilter", "type is empty", null)
            return
          }
            spriteGestureController.stopListener()
          when (type) {
            0 -> {
              val f = BasicDeformationFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            1 -> {
              val f = BeautyFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            2 -> {
              val f = BlackFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            3 -> {
              val f = BlurFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            4 -> {
              val f = BrightnessFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            5 -> {
              val f = CartoonFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            6 -> {
              if (filePath == null) {
                result.error("setFilter", "filePath Not Empty", null)
                return
              }
              val chromaFilterRender = ChromaFilterRender()
              genericCamera.glInterface?.setFilter(chromaFilterRender)
              chromaFilterRender.setImage(
                BitmapFactory.decodeFile(filePath)
              )
              currentFilter = chromaFilterRender
              currentFilterType = type
              result.success(null)
            }
            7 -> {
              val f = ChromaticAberrationFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            8 -> {
              val f = CircleFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            9 -> {
              val f = ColorFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            10 -> {
              val f = ContrastFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            11 -> {
              val f = CropFilterRender().apply {
                //crop center of the image with 40% of width and 40% of height
                setCropArea(30f, 30f, 40f, 40f)
              }
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            12 -> {
              val f = DistortedTvFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            13 -> {
              val f = DuotoneFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            14 -> {
              val f = EarlyBirdFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            15 -> {
              val f = EdgeDetectionFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            43 -> {
              val f = EdgeDetectionFilterRender(false)
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            16 -> {
              val f = ExposureFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            17 -> {
              val f = FireFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            18 -> {
              val f = GammaFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            19 -> {
              val f = GlitchFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            20 -> {
              if (filePath == null) {
                result.error("setFilter", "filePath Not Empty", null)
                return
              }
              val file = File(filePath)
              val inputStream = FileInputStream(file)
              val gifObjectFilterRender = GifFilterRender()
              gifObjectFilterRender.setGif(inputStream)
              genericCamera.glInterface?.setFilter(gifObjectFilterRender)
              gifObjectFilterRender.setScale(50f, 50f)
              gifObjectFilterRender.setPosition(TranslateTo.BOTTOM)
              spriteGestureController.setSprite(gifObjectFilterRender.sprite)
              currentFilter = gifObjectFilterRender
              currentFilterType = type
              result.success(null)
            }
            21 -> {
              val f = GreyScaleFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            22 -> {
              val f = HalftoneLinesFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            23 -> {
              if (filePath == null) {
                result.error("setFilter", "filePath Not Empty", null)
                return
              }
              val imageObjectFilterRender = ImageFilterRender()
              genericCamera.glInterface?.setFilter(imageObjectFilterRender)
              imageObjectFilterRender.setImage(
                BitmapFactory.decodeFile(filePath)
              )
              imageObjectFilterRender.setScale(50f, 50f)
              imageObjectFilterRender.setPosition(TranslateTo.RIGHT)
              spriteGestureController.setSprite(imageObjectFilterRender.sprite) //Optional
              spriteGestureController.setPreventMoveOutside(false)
              currentFilter = imageObjectFilterRender
              currentFilterType = type
              result.success(null)
            }
            24 -> {
              val f = Image70sFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            25 -> {
              val f = LamoishFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            26 -> {
              val f = MoneyFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            27 -> {
              val f = NegativeFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            28 -> {
              val f = NoiseFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            29 -> {
              val f = PixelatedFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            30 -> {
              val f = PolygonizationFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            31 -> {
              val f = RainbowFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            32 -> {
              val rgbSaturationFilterRender = RGBSaturationFilterRender()
              genericCamera.glInterface?.setFilter(rgbSaturationFilterRender)
              rgbSaturationFilterRender.setRGBSaturation(1f, 0.8f, 0.8f)
              currentFilter = rgbSaturationFilterRender
              currentFilterType = type
              result.success(null)
            }
            33 -> {
              val f = RippleFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            34 -> {
              val rotationFilterRender = RotationFilterRender()
              genericCamera.glInterface?.setFilter(rotationFilterRender)
              rotationFilterRender.rotation = 90
              currentFilter = rotationFilterRender
              currentFilterType = type
              result.success(null)
            }
            35 -> {
              val f = SaturationFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            36 -> {
              val f = SepiaFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            37 -> {
              val f = SharpnessFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            38-> {
              val f = SnowFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            39-> {
              if (filePath == null) {
                result.error("setFilter", "filePath Not Empty", null)
                return
              }
              val surfaceFilterRender =
                SurfaceFilterRender { surfaceTexture -> //You can render this filter with other api that draw in a surface. for example you can use VLC
                  val mediaPlayer = MediaPlayer()
                  mediaPlayer.setDataSource(filePath)
                  mediaPlayer.setSurface(Surface(surfaceTexture))
                  mediaPlayer.start()
                }
              genericCamera.glInterface?.setFilter(surfaceFilterRender)
              surfaceFilterRender.setScale(50f, 33.3f)
              spriteGestureController.setSprite(surfaceFilterRender.sprite)
              currentFilter = surfaceFilterRender
              currentFilterType = type
              result.success(null)
            }
            40 -> {
              val f = TemperatureFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            41 -> {
              val textObjectFilterRender = TextFilterRender()
              genericCamera.glInterface?.setFilter(textObjectFilterRender)
              textObjectFilterRender.setText("Hello world", 22f, Color.RED)
              textObjectFilterRender.setScale(50f, 50f)
              textObjectFilterRender.setPosition(TranslateTo.CENTER)
              spriteGestureController.setSprite(textObjectFilterRender.sprite) //Optional
              currentFilter = textObjectFilterRender
              currentFilterType = type
              result.success(null)
            }
            42 -> {
              val f = ZebraFilterRender()
              genericCamera.glInterface?.setFilter(f)
              currentFilter = f
              currentFilterType = type
              result.success(null)
            }
            else -> {
              result.success(null)
            }
          }

        } catch (e: CameraAccessException) {
          result.error("setFilter", e.message, null)
        } catch (e: IOException) {
          result.error("setFilter", e.message, null)
        }
    }

    //移除滤镜：必须使用 setFilter 时缓存的同一滤镜实例，底层按对象引用比较
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun removeFilter(type: Int?, result: MethodChannel.Result) {
        try {
          if (type == null) {
            result.error("removeFilter", "type is empty", null)
            return
          }
          spriteGestureController.stopListener()
          val filterToRemove = currentFilter
          val filterType = currentFilterType
          if (filterToRemove != null && filterType == type) {
            genericCamera.glInterface?.removeFilter(filterToRemove)
            currentFilter = null
            currentFilterType = null
          }
          result.success(null)
        } catch (e: CameraAccessException) {
          result.error("removeFilter", e.message, null)
        } catch (e: IOException) {
          result.error("removeFilter", e.message, null)
        }
    }

    fun stopVideoRecordingOrStreaming(result: MethodChannel.Result) {
        try {
            resumeStreamAfterSurfaceCreated = false
            isRestoringFromSurfaceDestroy = false
            lastStreamUrl = null
            lastStreamBitrate = null
            lastStreamProtocol = null
            lastWhipToken = null
            stopActiveStream()
            if (genericCamera.isRecording) {
                genericCamera.stopRecord()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("videoRecordingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("videoRecordingFailed", e.message, null)
        }
    }

    fun stopVideoRecording(result: MethodChannel.Result) {
        try {
            genericCamera.apply {
                if (isRecording) stopRecord()
            }
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("stopVideoRecordingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("stopVideoRecordingFailed", e.message, null)
        }
    }

    fun stopVideoStreaming(result: MethodChannel.Result) {
        try {
            resumeStreamAfterSurfaceCreated = false
            isRestoringFromSurfaceDestroy = false
            lastStreamUrl = null
            lastStreamBitrate = null
            lastStreamProtocol = null
            lastWhipToken = null
            stopActiveStream()
            result.success(null)
        } catch (e: CameraAccessException) {
            result.error("stopVideoStreamingFailed", e.message, null)
        } catch (e: IllegalStateException) {
            result.error("stopVideoStreamingFailed", e.message, null)
        }
    }

    fun pauseVideoRecording(result: MethodChannel.Result) {
        try {
            if (!genericCamera.isRecording) {
                result.error("pauseVideoRecording", "没有正在录制的视频", null)
                return
            }
            genericCamera.pauseRecord();
          result.success(null)
        } catch (e: CameraAccessException) {
            result.error("pauseVideoRecording", e.message, null)
            return
        } catch (e: IllegalStateException) {
            result.error("pauseVideoRecording", e.message, null)
            return
        }

    }

    fun resumeVideoRecording(result: MethodChannel.Result) {
        try {
            if (!genericCamera.isRecording) {
                result.error("resumeVideoRecording", "没有正在录制的视频", null)
                return
            }
            genericCamera.resumeRecord()
          result.success(null)
        } catch (e: CameraAccessException) {
            result.error("resumeVideoRecording", e.message, null)
            return
        } catch (e: IllegalStateException) {
            result.error("resumeVideoRecording", e.message, null)
            return
        }

    }

    fun startPreview(cameraNameArg: String? = null): Boolean {
        val targetCamera = if (cameraNameArg.isNullOrEmpty()) {
            cameraName
        } else {
            cameraNameArg
        }
        cameraName = targetCamera

        Log.d("CameraNativeView", "startPreview: $preset camera=$targetCamera")
        if (!isSurfaceCreated) {
            return false
        }
        return try {
            val previewSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
            val size = previewSize["size"] as Size
            genericCamera.startPreview(targetCamera, size.width, size.height)
            true
        } catch (e: CameraAccessException) {
            if (genericCamera.isOnPreview) {
                try {
                    genericCamera.stopCamera()
                } catch (_: Exception) {
                }
            }
            getActivity()?.runOnUiThread {
                dartMessenger?.send(
                    DartMessenger.EventType.ERROR,
                    "CameraAccessException"
                )
            }
            false
        } catch (e: Exception) {
            Log.e("CameraNativeView", "startPreview failed", e)
            getActivity()?.runOnUiThread {
                dartMessenger?.send(
                    DartMessenger.EventType.ERROR,
                    e.message ?: "startPreview failed"
                )
            }
            false
        }
    }

    private fun restorePreviewAfterSurfaceChange() {
        if (!isSurfaceCreated) {
            return
        }
        if (resumeStreamAfterSurfaceCreated && lastStreamUrl != null) {
            resumeStreamAfterSurfaceChange()
            return
        }
        if (genericCamera.isOnPreview) {
            try {
                genericCamera.stopCamera()
            } catch (e: Exception) {
                Log.e("CameraNativeView", "stopCamera before restore failed", e)
            }
        }
        startPreview(cameraName)
    }

    private fun resumeStreamAfterSurfaceChange() {
        val url = lastStreamUrl ?: run {
            resumeStreamAfterSurfaceCreated = false
            isRestoringFromSurfaceDestroy = false
            return
        }
        val protocol = lastStreamProtocol ?: currentProtocol
        resumeStreamAfterSurfaceCreated = false
        try {
            currentProtocol = protocol
            if (protocol == "whip") {
                startWhipStreaming(url, lastStreamBitrate, lastWhipToken, object : MethodChannel.Result {
                    override fun success(result: Any?) {}
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        isRestoringFromSurfaceDestroy = false
                        getActivity()?.runOnUiThread {
                            dartMessenger?.send(
                                DartMessenger.EventType.RTMP_STOPPED,
                                errorMessage ?: "Failed to resume WHIP stream after background"
                            )
                        }
                    }
                    override fun notImplemented() {}
                })
                return
            }
            if (genericCamera.isOnPreview) {
                genericCamera.stopCamera()
            }
            val streamingSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
            val size = streamingSize["size"] as Size
            val bitrateRes = lastStreamBitrate ?: customVideoBitrate ?: (streamingSize["bitrate"] as Int)
            genericCamera.forceBt709Color(forceBt709Color)
            applyRtmpPingsIfNeeded()
            val prepared = prepareAudioEncoder() && prepareVideoEncoder(size, bitrateRes)
            if (genericCamera.isRecording || prepared) {
                Log.d("CameraNativeView", "resumeStreamAfterSurfaceChange: $url")
                genericCamera.startStream(url)
            } else {
                isRestoringFromSurfaceDestroy = false
                getActivity()?.runOnUiThread {
                    dartMessenger?.send(
                        DartMessenger.EventType.RTMP_STOPPED,
                        "Failed to resume stream after background"
                    )
                }
            }
        } catch (e: Exception) {
            Log.e("CameraNativeView", "resumeStreamAfterSurfaceChange failed", e)
            isRestoringFromSurfaceDestroy = false
            getActivity()?.runOnUiThread {
                dartMessenger?.send(
                    DartMessenger.EventType.RTMP_STOPPED,
                    e.message ?: "Failed to resume stream after background"
                )
            }
        }
    }

    fun getStreamStatistics(result: MethodChannel.Result) {
        val ret = hashMapOf<String, Any>()
        val stats = lastStreamingStats
        val whip = whipStream
        val multi = multiCamera
        if (whip != null) {
            val client = whip.getStreamClient()
            ret["cacheSize"] = client.getCacheSize()
            ret["sentAudioFrames"] = client.getSentAudioFrames()
            ret["sentVideoFrames"] = client.getSentVideoFrames()
            ret["droppedAudioFrames"] = client.getDroppedAudioFrames()
            ret["droppedVideoFrames"] = client.getDroppedVideoFrames()
            ret["bytesSend"] = client.getBytesSend()
            ret["isAudioMuted"] = false
            ret["isVideoMuted"] = false
            ret["bitrate"] = customVideoBitrate ?: (lastStreamBitrate ?: vBitrate)
            ret["width"] = 0
            ret["height"] = 0
            ret["fps"] = fps
            ret["rttMicros"] = 0
            ret["queueBytesOut"] = stats?.queueBytesOut ?: client.getQueueBytesOut()
            ret["bytesOutPerSecond"] = stats?.bytesOutPerSecond ?: 0L
            ret["queueCongestionPercent"] = stats?.queueCongestionPercent ?: 0f
            ret["totalBytesOut"] = stats?.totalBytesOut ?: 0L
        } else if (multi != null && multiDestinations.isNotEmpty()) {
            val dest = multiDestinations.first()
            val client = multi.getStreamClient(dest.type, dest.index)
            ret["cacheSize"] = client.getCacheSize()
            ret["sentAudioFrames"] = client.getSentAudioFrames()
            ret["sentVideoFrames"] = client.getSentVideoFrames()
            ret["droppedAudioFrames"] = client.getDroppedAudioFrames()
            ret["droppedVideoFrames"] = client.getDroppedVideoFrames()
            ret["bytesSend"] = client.getBytesSend()
            ret["isAudioMuted"] = multi.isAudioMuted
            ret["isVideoMuted"] = multi.glInterface?.isVideoMuted ?: false
            ret["bitrate"] = multi.bitrate
            ret["width"] = multi.streamWidth
            ret["height"] = multi.streamHeight
            ret["fps"] = fps
            ret["rttMicros"] = 0
            ret["queueBytesOut"] = stats?.queueBytesOut ?: client.getQueueBytesOut()
            ret["bytesOutPerSecond"] = stats?.bytesOutPerSecond ?: 0L
            ret["queueCongestionPercent"] = stats?.queueCongestionPercent ?: 0f
            ret["totalBytesOut"] = stats?.totalBytesOut ?: 0L
        } else if (genericStream != null) {
            val stream = genericStream!!
            val client = stream.getStreamClient()
            ret["cacheSize"] = client.getCacheSize()
            ret["sentAudioFrames"] = client.getSentAudioFrames()
            ret["sentVideoFrames"] = client.getSentVideoFrames()
            ret["droppedAudioFrames"] = client.getDroppedAudioFrames()
            ret["droppedVideoFrames"] = client.getDroppedVideoFrames()
            ret["bytesSend"] = client.getBytesSend()
            ret["isAudioMuted"] = false
            ret["isVideoMuted"] = false
            ret["bitrate"] = customVideoBitrate ?: (lastStreamBitrate ?: vBitrate)
            ret["width"] = 0
            ret["height"] = 0
            ret["fps"] = fps
            ret["rttMicros"] = 0
            ret["queueBytesOut"] = stats?.queueBytesOut ?: client.getQueueBytesOut()
            ret["bytesOutPerSecond"] = stats?.bytesOutPerSecond ?: 0L
            ret["queueCongestionPercent"] = stats?.queueCongestionPercent ?: 0f
            ret["totalBytesOut"] = stats?.totalBytesOut ?: 0L
        } else {
            val client = genericCamera.streamClient
            ret["cacheSize"] = client.getCacheSize()
            ret["sentAudioFrames"] = client.getSentAudioFrames()
            ret["sentVideoFrames"] = client.getSentVideoFrames()
            ret["droppedAudioFrames"] = client.getDroppedAudioFrames()
            ret["droppedVideoFrames"] = client.getDroppedVideoFrames()
            ret["bytesSend"] = client.getBytesSend()
            ret["isAudioMuted"] = genericCamera.isAudioMuted
            ret["isVideoMuted"] = genericCamera.glInterface?.isVideoMuted ?: false
            ret["bitrate"] = genericCamera.bitrate
            ret["width"] = genericCamera.streamWidth
            ret["height"] = genericCamera.streamHeight
            ret["fps"] = fps
            ret["rttMicros"] = if (currentProtocol == "rtmp") {
                rtmpStreamClientOrNull()?.getRtt() ?: 0
            } else {
                0
            }
            ret["queueBytesOut"] = stats?.queueBytesOut ?: client.getQueueBytesOut()
            ret["bytesOutPerSecond"] = stats?.bytesOutPerSecond ?: 0L
            ret["queueCongestionPercent"] = stats?.queueCongestionPercent ?: 0f
            ret["totalBytesOut"] = stats?.totalBytesOut ?: 0L
        }
        result.success(ret)
    }

    private fun translateTo(position: String?): TranslateTo {
        return when (position) {
            "topLeft" -> TranslateTo.TOP_LEFT
            "topRight" -> TranslateTo.TOP_RIGHT
            "bottomLeft" -> TranslateTo.BOTTOM_LEFT
            "bottomRight" -> TranslateTo.BOTTOM_RIGHT
            else -> TranslateTo.CENTER
        }
    }

    private fun clearOverlayInternal() {
        overlayFilter?.let { genericCamera.glInterface?.removeFilter(it) }
        overlayFilter = null
        spriteGestureController.stopListener()
    }

    private fun applyNaturalObjectScale(
        render: com.pedro.encoder.input.gl.render.filters.`object`.BaseObjectFilterRender,
        streamW: Int,
        streamH: Int
    ) {
        try {
            val field = com.pedro.encoder.input.gl.render.filters.`object`.BaseObjectFilterRender::class.java
                .getDeclaredField("streamObject")
            field.isAccessible = true
            val obj = field.get(render) as? com.pedro.encoder.utils.gl.StreamObjectBase ?: return
            val w = obj.width
            val h = obj.height
            if (w > 0 && h > 0 && streamW > 0 && streamH > 0) {
                render.setScale(w * 100f / streamW, h * 100f / streamH)
            }
        } catch (_: Exception) {
            render.setScale(50f, 50f)
        }
    }

    fun setOverlayText(
        text: String?,
        fontSize: Double?,
        colorArgb: Int?,
        position: String?,
        scale: Double?,
        result: MethodChannel.Result
    ) {
        if (text.isNullOrEmpty()) {
            result.error("setOverlayText", "text is required", null)
            return
        }
        try {
            clearOverlayInternal()
            val render = TextFilterRender()
            val color = colorArgb ?: Color.RED
            // Paint size in bitmap pixels; larger = sharper when mapped 1:1 via setDefaultScale.
            val density = activity?.resources?.displayMetrics?.density ?: 1f
            val size = ((fontSize ?: 22.0).toFloat() * density).coerceAtLeast(12f)
            render.setText(text, size, color)
            val encoder = genericCamera.glInterface?.encoderSize
            val streamW = genericCamera.streamWidth.takeIf { it > 0 }
                ?: encoder?.x?.takeIf { it > 0 }
                ?: 1280
            val streamH = genericCamera.streamHeight.takeIf { it > 0 }
                ?: encoder?.y?.takeIf { it > 0 }
                ?: 720
            // Natural pixel mapping so fontSize controls on-screen size (avoids 50% upscale blur).
            applyNaturalObjectScale(render, streamW, streamH)
            val scaleFactor = ((scale ?: 100.0) / 100.0).toFloat().coerceIn(0.1f, 4f)
            if (kotlin.math.abs(scaleFactor - 1f) > 0.01f) {
                val current = render.scale
                render.setScale(current.x * scaleFactor, current.y * scaleFactor)
            }
            render.setPosition(translateTo(position))
            genericCamera.glInterface?.setFilter(render)
            spriteGestureController.setSprite(render.sprite)
            overlayFilter = render
            result.success(null)
        } catch (e: Exception) {
            result.error("setOverlayText", e.message, null)
        }
    }

    fun setOverlayImage(
        filePath: String?,
        position: String?,
        scale: Double?,
        result: MethodChannel.Result
    ) {
        if (filePath.isNullOrEmpty()) {
            result.error("setOverlayImage", "filePath is required", null)
            return
        }
        try {
            clearOverlayInternal()
            val bitmap = BitmapFactory.decodeFile(filePath)
            if (bitmap == null) {
                result.error("setOverlayImage", "Failed to decode image", null)
                return
            }
            val render = ImageFilterRender()
            render.setImage(bitmap)
            val encoder = genericCamera.glInterface?.encoderSize
            val streamW = genericCamera.streamWidth.takeIf { it > 0 }
                ?: encoder?.x?.takeIf { it > 0 }
                ?: 1280
            val streamH = genericCamera.streamHeight.takeIf { it > 0 }
                ?: encoder?.y?.takeIf { it > 0 }
                ?: 720
            applyNaturalObjectScale(render, streamW, streamH)
            val scaleFactor = ((scale ?: 100.0) / 100.0).toFloat().coerceIn(0.1f, 4f)
            if (kotlin.math.abs(scaleFactor - 1f) > 0.01f) {
                val current = render.scale
                render.setScale(current.x * scaleFactor, current.y * scaleFactor)
            }
            render.setPosition(translateTo(position))
            genericCamera.glInterface?.setFilter(render)
            spriteGestureController.setSprite(render.sprite)
            overlayFilter = render
            result.success(null)
        } catch (e: Exception) {
            result.error("setOverlayImage", e.message, null)
        }
    }

    fun clearOverlay(result: MethodChannel.Result) {
        try {
            clearOverlayInternal()
            result.success(null)
        } catch (e: Exception) {
            result.error("clearOverlay", e.message, null)
        }
    }

    fun setPitchShift(pitch: Double?, result: MethodChannel.Result) {
        if (pitch == null) {
            result.error("setPitchShift", "pitch is required", null)
            return
        }
        try {
            val effect = if (kotlin.math.abs(pitch - 1.0) < 0.001) {
                pitchShiftEffect = null
                NoAudioEffect()
            } else {
                val pitchEffect = pitchShiftEffect ?: PitchShiftEffect().also { pitchShiftEffect = it }
                pitchEffect.pitch = pitch.toFloat()
                pitchEffect
            }
            val whip = whipStream
            if (whip != null && whip.isStreaming) {
                val mic = whip.audioSource as? MicrophoneSource
                if (mic == null) {
                    result.error(
                        "setPitchShift",
                        "PitchShift is not available for the current WHIP audio source.",
                        null
                    )
                    return
                }
                mic.setAudioEffect(effect)
            } else {
                genericCamera.setCustomAudioEffect(effect)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("setPitchShift", e.message, null)
        }
    }

    fun lockExposure(result: MethodChannel.Result) {
        try {
            val ok = enableExposureLockOnActiveCamera()
            result.success(ok)
        } catch (e: Exception) {
            result.error("lockExposure", e.message, null)
        }
    }

    fun unlockExposure(result: MethodChannel.Result) {
        try {
            disableExposureLockOnActiveCamera()
            result.success(null)
        } catch (e: Exception) {
            result.error("unlockExposure", e.message, null)
        }
    }

    fun isExposureLocked(result: MethodChannel.Result) {
        try {
            result.success(isExposureLockEnabledOnActiveCamera())
        } catch (e: Exception) {
            result.error("isExposureLocked", e.message, null)
        }
    }

    private fun enableExposureLockOnActiveCamera(): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.enableExposureLock()
                ?: throw IllegalStateException("Exposure lock is not available for the current WHIP video source.")
        }
        return genericCamera.enableExposureLock()
    }

    private fun disableExposureLockOnActiveCamera() {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
                ?: throw IllegalStateException("Exposure unlock is not available for the current WHIP video source.")
            camera2.disableExposureLock()
            return
        }
        genericCamera.disableExposureLock()
    }

    private fun isExposureLockEnabledOnActiveCamera(): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.isExposureLockEnabled() ?: false
        }
        return genericCamera.isExposureLockEnabled
    }

    fun setForceBt709Color(enabled: Boolean?, result: MethodChannel.Result) {
        if (enabled == null) {
            result.error("setForceBt709Color", "enabled is required", null)
            return
        }
        forceBt709Color = enabled
        try {
            genericCamera.forceBt709Color(enabled)
            whipStream?.forceBt709Color(enabled)
            genericStream?.forceBt709Color(enabled)
            multiCamera?.forceBt709Color(enabled)
            result.success(null)
        } catch (e: Exception) {
            result.error("setForceBt709Color", e.message, null)
        }
    }

    fun setRtmpShouldSendPings(enabled: Boolean?, result: MethodChannel.Result) {
        if (enabled == null) {
            result.error("setRtmpShouldSendPings", "enabled is required", null)
            return
        }
        rtmpShouldSendPings = enabled
        result.success(null)
    }

    fun setVideoCodec(name: String?, result: MethodChannel.Result) {
        if (name.isNullOrBlank()) {
            result.error("setVideoCodec", "name is required", null)
            return
        }
        val codec = parseVideoCodec(name)
        if (codec == null) {
            result.error("setVideoCodec", "Unsupported video codec: $name", null)
            return
        }
        videoCodec = codec
        try {
            whipStream?.setVideoCodec(codec)
            multiCamera?.setVideoCodec(codec)
            genericStream?.setVideoCodec(codec)
            genericCamera.setVideoCodec(codec)
            result.success(null)
        } catch (e: Exception) {
            result.error("setVideoCodec", e.message, null)
        }
    }

    fun setAudioCodec(name: String?, result: MethodChannel.Result) {
        if (name.isNullOrBlank()) {
            result.error("setAudioCodec", "name is required", null)
            return
        }
        val codec = parseAudioCodec(name)
        if (codec == null) {
            result.error("setAudioCodec", "Unsupported audio codec: $name", null)
            return
        }
        audioCodec = codec
        try {
            whipStream?.setAudioCodec(codec)
            multiCamera?.setAudioCodec(codec)
            genericStream?.setAudioCodec(codec)
            genericCamera.setAudioCodec(codec)
            result.success(null)
        } catch (e: Exception) {
            result.error("setAudioCodec", e.message, null)
        }
    }

    fun setAudioProcessing(
        echoCanceler: Boolean?,
        noiseSuppressor: Boolean?,
        result: MethodChannel.Result
    ) {
        if (echoCanceler != null) {
            this.echoCanceler = echoCanceler
        }
        if (noiseSuppressor != null) {
            this.noiseSuppressor = noiseSuppressor
        }
        result.success(null)
    }

    fun lockWhiteBalance(result: MethodChannel.Result) {
        try {
            result.success(enableWhiteBalanceLockOnActiveCamera())
        } catch (e: Exception) {
            result.error("lockWhiteBalance", e.message, null)
        }
    }

    fun unlockWhiteBalance(result: MethodChannel.Result) {
        try {
            disableWhiteBalanceLockOnActiveCamera()
            result.success(null)
        } catch (e: Exception) {
            result.error("unlockWhiteBalance", e.message, null)
        }
    }

    fun isWhiteBalanceLocked(result: MethodChannel.Result) {
        try {
            result.success(isWhiteBalanceLockEnabledOnActiveCamera())
        } catch (e: Exception) {
            result.error("isWhiteBalanceLocked", e.message, null)
        }
    }

    private fun enableWhiteBalanceLockOnActiveCamera(): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.enableWhiteBalanceLock()
                ?: throw IllegalStateException("White balance lock is not available for the current WHIP video source.")
        }
        return genericCamera.enableWhiteBalanceLock()
    }

    private fun disableWhiteBalanceLockOnActiveCamera() {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
                ?: throw IllegalStateException("White balance unlock is not available for the current WHIP video source.")
            camera2.disableWhiteBalanceLock()
            return
        }
        genericCamera.disableWhiteBalanceLock()
    }

    private fun isWhiteBalanceLockEnabledOnActiveCamera(): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.isWhiteBalanceLockEnabled() ?: false
        }
        return genericCamera.isWhiteBalanceLockEnabled
    }

    fun tapToMeter(
        x: Double?,
        y: Double?,
        mode: String?,
        result: MethodChannel.Result
    ) {
        try {
            val nx = (x ?: 0.5).coerceIn(0.0, 1.0)
            val ny = (y ?: 0.5).coerceIn(0.0, 1.0)
            val view = glView
            val px = (nx * view.width).toFloat()
            val py = (ny * view.height).toFloat()
            val now = SystemClock.uptimeMillis()
            val event = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, px, py, 0)
            val meterMode = (mode ?: "exposure").lowercase(Locale.getDefault())
            val ok = try {
                when (meterMode) {
                    "whitebalance", "wb", "white_balance" ->
                        tapToMeterWhiteBalanceOnActiveCamera(view, event)
                    else ->
                        tapToMeterExposureOnActiveCamera(view, event)
                }
            } finally {
                event.recycle()
            }
            result.success(ok)
        } catch (e: Exception) {
            result.error("tapToMeter", e.message, null)
        }
    }

    private fun tapToMeterExposureOnActiveCamera(view: View, event: MotionEvent): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.tapToMeterExposure(view, event)
                ?: throw IllegalStateException("tapToMeterExposure is not available for the current WHIP video source.")
        }
        return genericCamera.tapToMeterExposure(view, event)
    }

    private fun tapToMeterWhiteBalanceOnActiveCamera(view: View, event: MotionEvent): Boolean {
        val whip = whipStream
        if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
            val camera2 = whip.videoSource as? Camera2Source
            return camera2?.tapToMeterWhiteBalance(view, event)
                ?: throw IllegalStateException("tapToMeterWhiteBalance is not available for the current WHIP video source.")
        }
        return genericCamera.tapToMeterWhiteBalance(view, event)
    }

    fun setVideoSource(mode: String?, result: MethodChannel.Result) {
        if (mode.isNullOrBlank()) {
            result.error("setVideoSource", "mode is required", null)
            return
        }
        val normalized = mode.lowercase(Locale.getDefault())
        when (normalized) {
            "camera2", "camerax", "uvc", "screen" -> {
                videoSourceMode = normalized
                val ctx = getActivity() ?: glView.context
                try {
                    val whip = whipStream
                    if (whip != null && (whip.isStreaming || whip.isOnPreview)) {
                        applyPreferredVideoSourceToWhip(whip, ctx)
                        result.success(null)
                        return
                    }
                    val gs = genericStream
                    if (gs != null && (gs.isStreaming || gs.isOnPreview)) {
                        applyPreferredVideoSourceToStreamBase(gs, ctx)
                        result.success(null)
                        return
                    }
                    // Applied on next startVideoStreaming via GenericStream path when needed.
                    result.success(null)
                } catch (e: Exception) {
                    result.error("setVideoSource", e.message, null)
                }
            }
            else -> result.error(
                "setVideoSource",
                "Unsupported mode: $mode (expected camera2|cameraX|uvc|screen)",
                null
            )
        }
    }

    private fun applyPreferredVideoSource(
        changeVideoSource: (com.pedro.encoder.input.sources.video.VideoSource) -> Unit,
        currentSource: com.pedro.encoder.input.sources.video.VideoSource?,
        ctx: Context
    ) {
        when (videoSourceMode) {
            "camerax" -> changeVideoSource(CameraXSource(ctx))
            "uvc" -> changeVideoSource(CameraUvcSource())
            "screen" -> {
                val projection = screenMediaProjection
                    ?: throw IllegalStateException(
                        "Screen source requires MediaProjection; call requestScreenCapture first."
                    )
                changeVideoSource(ScreenSource(ctx, projection))
            }
            else -> {
                if (currentSource !is Camera2Source) {
                    changeVideoSource(Camera2Source(ctx))
                }
            }
        }
    }

    private fun applyPreferredVideoSourceToStreamBase(stream: GenericStream, ctx: Context) {
        applyPreferredVideoSource(stream::changeVideoSource, stream.videoSource, ctx)
    }

    private fun applyPreferredVideoSourceToWhip(stream: WhipStream, ctx: Context) {
        applyPreferredVideoSource(stream::changeVideoSource, stream.videoSource, ctx)
    }

    fun attachScreenMediaProjection(projection: MediaProjection?, result: MethodChannel.Result) {
        releaseScreenMediaProjection()
        screenMediaProjection = projection
        result.success(null)
    }

    private fun releaseScreenMediaProjection() {
        try {
            screenMediaProjection?.stop()
        } catch (e: Exception) {
            Log.w("CameraNativeView", "MediaProjection.stop failed", e)
        }
        screenMediaProjection = null
    }

    fun enableBufferAudio(enable: Boolean?, result: MethodChannel.Result) {
        if (enable == null) {
            result.error("enableBufferAudio", "enable is required", null)
            return
        }
        useBufferAudio = enable
        try {
            if (enable) {
                val src = bufferAudioSource ?: BufferAudioSource().also { bufferAudioSource = it }
                whipStream?.changeAudioSource(src)
                genericStream?.changeAudioSource(src)
            } else {
                bufferAudioSource = null
                whipStream?.changeAudioSource(MicrophoneSource())
                genericStream?.changeAudioSource(MicrophoneSource())
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("enableBufferAudio", e.message, null)
        }
    }

    fun feedPcmAudio(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null) {
            result.error("feedPcmAudio", "bytes is required", null)
            return
        }
        val src = bufferAudioSource
        if (!useBufferAudio || src == null) {
            result.error("feedPcmAudio", "Buffer audio is not enabled", null)
            return
        }
        try {
            src.setBuffer(bytes)
            result.success(null)
        } catch (e: Exception) {
            result.error("feedPcmAudio", e.message, null)
        }
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    fun startMultiStreaming(
        destinations: List<Map<String, Any?>>?,
        bitrate: Int?,
        result: MethodChannel.Result
    ) {
        if (destinations.isNullOrEmpty()) {
            result.error("startMultiStreaming", "destinations is required", null)
            return
        }
        try {
            if (isStreamingNow() || multiCamera != null) {
                stopActiveStream(restorePreview = false)
            }
            if (genericCamera.isOnPreview) {
                try {
                    genericCamera.stopCamera()
                } catch (e: Exception) {
                    Log.e("CameraNativeView", "stopCamera before multi failed", e)
                }
            }

            val rtmpCheckers = mutableListOf<ConnectChecker>()
            val rtspCheckers = mutableListOf<ConnectChecker>()
            val srtCheckers = mutableListOf<ConnectChecker>()
            val udpCheckers = mutableListOf<ConnectChecker>()
            val built = mutableListOf<MultiDest>()

            destinations.forEachIndexed { i, dest ->
                val url = dest["url"] as? String
                if (url.isNullOrBlank()) {
                    result.error("startMultiStreaming", "destination[$i].url is required", null)
                    return
                }
                val protocol = ((dest["protocol"] as? String) ?: "rtmp").lowercase(Locale.getDefault())
                validateProtocolAndUrl(protocol, url)?.let {
                    result.error("startMultiStreaming", it, null)
                    return
                }
                if (protocol == "whip" || protocol == "whep") {
                    result.error(
                        "startMultiStreaming",
                        "WHIP/WHEP are not supported in multi-streaming",
                        null
                    )
                    return
                }
                val id = (dest["id"] as? String)?.takeIf { it.isNotBlank() } ?: "dest_$i"
                val type = when (protocol) {
                    "rtmp" -> MultiType.RTMP
                    "rtsp" -> MultiType.RTSP
                    "srt" -> MultiType.SRT
                    "udp" -> MultiType.UDP
                    else -> {
                        result.error("startMultiStreaming", "Unsupported protocol: $protocol", null)
                        return
                    }
                }
                val index = when (type) {
                    MultiType.RTMP -> {
                        val idx = rtmpCheckers.size
                        rtmpCheckers.add(this)
                        idx
                    }
                    MultiType.RTSP -> {
                        val idx = rtspCheckers.size
                        rtspCheckers.add(this)
                        idx
                    }
                    MultiType.SRT -> {
                        val idx = srtCheckers.size
                        srtCheckers.add(this)
                        idx
                    }
                    MultiType.UDP -> {
                        val idx = udpCheckers.size
                        udpCheckers.add(this)
                        idx
                    }
                }
                built.add(MultiDest(id, url, protocol, type, index))
            }

            val mc = MultiCamera2(
                glView,
                rtmpCheckers.takeIf { it.isNotEmpty() }?.toTypedArray(),
                rtspCheckers.takeIf { it.isNotEmpty() }?.toTypedArray(),
                srtCheckers.takeIf { it.isNotEmpty() }?.toTypedArray(),
                udpCheckers.takeIf { it.isNotEmpty() }?.toTypedArray()
            )
            mc.setVideoCodec(videoCodec)
            mc.setAudioCodec(audioCodec)
            mc.forceBt709Color(forceBt709Color)
            mc.setFpsListener { fps = it }

            val streamingSize = CameraUtils.computeBestPreviewSize(getActivity(), cameraName, preset)
            val size = streamingSize["size"] as Size
            val bitrateRes = customVideoBitrate ?: (bitrate ?: (streamingSize["bitrate"] as Int))
            val fpsValue = customVideoFps ?: 30
            val rotation = CameraHelper.getCameraOrientation(getActivity() ?: glView.context)
            val audioOk = if (!enableAudio) {
                true
            } else {
                val ab = customAudioBitrate ?: aBitrate
                mc.prepareAudio(ab, 32000, true, echoCanceler, noiseSuppressor)
            }
            val videoOk = mc.prepareVideo(size.width, size.height, fpsValue, bitrateRes, rotation)
            if (!audioOk || !videoOk) {
                result.error(
                    "startMultiStreaming",
                    "Error preparing multi stream, This device cant do it",
                    null
                )
                return
            }

            // Start preview on the multi instance (OpenGlView already attached).
            try {
                mc.startPreview(cameraName, size.width, size.height)
            } catch (e: Exception) {
                Log.w("CameraNativeView", "multi startPreview failed, continuing", e)
            }

            multiDestinations = built
            multiCamera = mc
            lastStreamBitrate = bitrateRes
            currentProtocol = built.first().protocol
            queueBitrateAdapter.reset()

            for (dest in built) {
                mc.startStream(dest.type, dest.index, dest.url)
            }
            result.success(null)
        } catch (e: Exception) {
            multiCamera = null
            multiDestinations.clear()
            result.error("startMultiStreaming", e.message, null)
        }
    }

    fun stopStreamingDestination(id: String?, result: MethodChannel.Result) {
        if (id.isNullOrBlank()) {
            result.error("stopStreamingDestination", "id is required", null)
            return
        }
        val mc = multiCamera
        if (mc == null) {
            result.error("stopStreamingDestination", "Multi streaming is not active", null)
            return
        }
        val dest = multiDestinations.firstOrNull { it.id == id }
        if (dest == null) {
            result.error("stopStreamingDestination", "Unknown destination id: $id", null)
            return
        }
        try {
            mc.stopStream(dest.type, dest.index)
            multiDestinations.removeAll { it.id == id }
            if (multiDestinations.isEmpty()) {
                stopMultiStreamingInternal(restorePreview = true)
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("stopStreamingDestination", e.message, null)
        }
    }

    fun stopMultiStreaming(result: MethodChannel.Result) {
        try {
            stopMultiStreamingInternal(restorePreview = true)
            result.success(null)
        } catch (e: Exception) {
            result.error("stopMultiStreaming", e.message, null)
        }
    }

    override fun getView(): View {
        return glView
    }

    override fun dispose() {
        isSurfaceCreated = false
        resumeStreamAfterSurfaceCreated = false
        isRestoringFromSurfaceDestroy = false
        lastStreamUrl = null
        lastStreamBitrate = null
        lastStreamProtocol = null
        lastWhipToken = null
        try {
            stopActiveStream(restorePreview = false)
        } catch (_: Exception) {
        }
        if (genericCamera.isOnPreview) {
            try {
                genericCamera.stopCamera()
            } catch (_: Exception) {
            }
        }
        bufferAudioSource = null
        releaseScreenMediaProjection()
        activity = null
    }

    /** Activity 在 surfaceDestroyed 后仍有效；若引用丢失则用 glView 的 Context 兜底。 */
    private fun getActivity(): Activity? = activity ?: glView.context as? Activity
}
