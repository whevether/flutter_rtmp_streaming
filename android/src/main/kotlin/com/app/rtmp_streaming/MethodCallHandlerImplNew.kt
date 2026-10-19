package com.app.rtmp_streaming

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.ComponentName
import android.content.ServiceConnection
import android.os.IBinder
import android.hardware.camera2.CameraAccessException
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import androidx.annotation.RequiresApi
import com.app.rtmp_streaming.CameraPermissions.ResolutionPreset
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.*
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.platform.PlatformViewRegistry
import java.util.HashMap

class MethodCallHandlerImplNew(
    activity: Activity,
    private val messenger: BinaryMessenger,
    private val cameraPermissions: CameraPermissions,
    private val permissionsRegistry: PermissionStuff,
    private val platformViewRegistry: PlatformViewRegistry,
    private val registeredFactory: NativeViewFactory
) : MethodCallHandler {

    private var attachedActivity: Activity? = activity
    private val activity: Activity get() = requireNotNull(attachedActivity) { "Activity not attached" }
    private val methodChannel: MethodChannel
    private var dartMessenger: DartMessenger? = null
    private var nativeViewFactory: NativeViewFactory? = null
    private var handler: Handler? = null
    private val VIEW_TYPE: String = "hybrid-view-type"
    private val id = System.identityHashCode(this)

    private val textureId = 0L

    private val SCREEN_CAPTURE_REQUEST = 4001
    private var pendingScreenResult: MethodChannel.Result? = null
    private var pendingInitialization: MethodChannel.Result? = null
    private var screenCaptureListenerRegistered = false
    private var screenCaptureConnection: ServiceConnection? = null
    private var screenCaptureListener: PluginRegistry.ActivityResultListener? = null
    var activityBinding: ActivityPluginBinding? = null
        set(value) {
            if (field !== value) {
                screenCaptureListener?.let { field?.removeActivityResultListener(it) }
                screenCaptureListener = null
                screenCaptureListenerRegistered = false
            }
            field = value
        }

    init {
        handler = Handler(android.os.Looper.getMainLooper())
        Log.d("TAG", "init $platformViewRegistry")
        methodChannel = MethodChannel(messenger, "com.rtmp_streaming")
        methodChannel.setMethodCallHandler(this)
        dartMessenger = DartMessenger(messenger, id)
        nativeViewFactory = registeredFactory
        nativeViewFactory?.dartMessenger = dartMessenger
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (attachedActivity == null) {
            result.error("activity_detached", "Activity not attached", null)
            return
        }
        val requiresView = setOf("takePicture", "startVideoRecording", "startVideoStreaming",
            "startVideoRecordingAndStreaming", "stopRecordingOrStreaming", "stopRecording", "stopStreaming",
            "pauseVideoRecording", "resumeVideoRecording", "getStreamStatistics", "switchCamera",
            "switchFlashLight", "switchAudio", "setFilter", "removeFilter", "getHasAudio", "setHasAudio",
            "getHasVideo", "setHasVideo", "prepareForVideoStreaming")
        if (call.method in requiresView && getCameraView() == null) {
            result.error("no_camera", "Mount CameraPreview before calling ${call.method}", null)
            return
        }
        try {
        when (call.method) {
            "getCapabilities" -> {
                val encoderInfos = android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS)
                    .codecInfos.filter { it.isEncoder }
                val encoders = encoderInfos.flatMap { it.supportedTypes.toList() }.toSet()
                val heAac = encoderInfos.any { info -> runCatching {
                    info.getCapabilitiesForType("audio/mp4a-latm").profileLevels.any {
                        it.profile == android.media.MediaCodecInfo.CodecProfileLevel.AACObjectHE
                    }
                }.getOrDefault(false) }
                val video = mapOf("h264" to "video/avc", "h265" to "video/hevc", "av1" to "video/av01", "vp8" to "video/x-vnd.on2.vp8", "vp9" to "video/x-vnd.on2.vp9")
                result.success(mapOf(
                    "backend" to "RootEncoder/2.8.1",
                    "protocols" to listOf("rtmp", "rtsp", "srt", "udp", "whip"),
                    "videoCodecs" to video.filterValues { it in encoders }.keys.toList(),
                    "audioCodecs" to buildList {
                        if ("audio/mp4a-latm" in encoders) add("aac")
                        if (heAac) add("heAac")
                        if ("audio/opus" in encoders) add("opus")
                        add("g711")
                    },
                    "features" to mapOf("recordingPause" to true, "zoom" to true,
                        "focus" to true, "overlays" to true, "filters" to true,
                        "screenCapture" to true, "uvc" to true, "pcmInput" to true,
                        "whipBearerToken" to true, "playback" to false,
                        "multitaskingCameraAccess" to false, "rtmpPing" to true,
                        "captureTelemetry" to true, "bitRateMode" to false,
                        "microphoneDetach" to false,
                        "echoCanceler" to android.media.audiofx.AcousticEchoCanceler.isAvailable(),
                        "noiseSuppressor" to android.media.audiofx.NoiseSuppressor.isAvailable(),
                        "pitchShift" to true, "rtmpMetadata" to true) + (getCameraView()?.cameraCapabilityFlags()
                        ?: mapOf("zoom" to false, "focus" to false, "captureTelemetry" to false))
                ))
            }
            "availableCameras" -> try {
                Log.i("Stuff", "availableCameras")
                result.success(CameraUtils.getAvailableCameras(activity))
            } catch (e: Exception) {
                handleException(e, result)
            }

            "initialize" -> {
                Log.i("Stuff", "initialize")
                cameraPermissions.requestPermissions(
                    activity,
                    permissionsRegistry,
                    call.argument("enableAudio")!!,
                    object : ResultCallback {
                        override fun onResult(errorCode: String?, errorDescription: String?) {
                            if (errorCode == null) {
                                try {
                                    instantiateCamera(call, result)
                                } catch (e: Exception) {
                                    handleException(e, result)
                                }
                            } else {
                                result.error(errorCode, errorDescription, null)
                            }
                        }
                    })
            }

            "takePicture" -> {
                Log.i("Stuff", "takePicture")
                getCameraView()?.takePicture(call.argument("path")!!, result)
            }

            "startVideoRecording" -> {
                Log.i("Stuff", "startVideoRecording")
                getCameraView()?.startVideoRecording(call.argument("filePath")!!, result)
            }

            "startVideoStreaming" -> {
                Log.i("Stuff", "startVideoStreaming")
                getCameraView()?.startVideoStreaming(
                    call.argument("url"),
                    call.argument("bitrate"),
                    call.argument("protocol"),
                    call.argument("whipToken"),
                    result
                )
            }

            "startVideoRecordingAndStreaming" -> {
                Log.i("Stuff", "startVideoRecordingAndStreaming")
                getCameraView()?.startVideoRecordingAndStreaming(
                    call.argument("filePath"),
                    call.argument("url"),
                    call.argument("bitrate"),
                    call.argument("protocol"),
                    call.argument("whipToken"),
                    result
                )
            }

            "stopRecordingOrStreaming" -> {
                Log.i("Stuff", "stopRecordingOrStreaming")
                getCameraView()?.stopVideoRecordingOrStreaming(result)
            }

            "stopRecording" -> {
                Log.i("Stuff", "stopRecording")
                getCameraView()?.stopVideoRecording(result)
            }

            "stopStreaming" -> {
                Log.i("Stuff", "stopStreaming")
                getCameraView()?.stopVideoStreaming(result)
            }

            "pauseVideoRecording" -> {
                Log.i("Stuff", "pauseVideoRecording")
                getCameraView()?.pauseVideoRecording(result)
            }

            "resumeVideoRecording" -> {
                Log.i("Stuff", "resumeVideoRecording")
                getCameraView()?.resumeVideoRecording(result)
            }

            "getStreamStatistics" -> {
                Log.i("Stuff", "getStreamStatistics")
                try {
                    getCameraView()?.getStreamStatistics(result)
                } catch (e: Exception) {
                    handleException(e, result)
                }
            }
            "setForceBt709Color" -> {
                Log.i("Stuff", "setForceBt709Color")
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) {
                    result.error("setForceBt709Color", "enabled is required", null)
                } else {
                    // Always cache so remounted CameraPreview keeps the value.
                    nativeViewFactory?.pendingForceBt709Color = enabled
                    val view = getCameraView()
                    if (view != null) {
                        view.setForceBt709Color(enabled, result)
                    } else {
                        result.success(null)
                    }
                }
            }
            "setRtmpShouldSendPings" -> {
                Log.i("Stuff", "setRtmpShouldSendPings")
                val enabled = call.argument<Boolean>("enabled")
                if (enabled == null) {
                    result.error("setRtmpShouldSendPings", "enabled is required", null)
                } else {
                    nativeViewFactory?.pendingRtmpShouldSendPings = enabled
                    val view = getCameraView()
                    if (view != null) {
                        view.setRtmpShouldSendPings(enabled, result)
                    } else {
                        result.success(null)
                    }
                }
            }
            "prepareForVideoStreaming" -> {
                getCameraView()?.prepareForVideoStreaming(result)
                    ?: result.success(null)
            }
            "getHasAudio" -> {
                getCameraView()?.getHasAudio(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setHasAudio" -> {
                getCameraView()?.setHasAudio(call.argument("isEnable"), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "getHasVideo" -> {
                getCameraView()?.getHasVideo(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setHasVideo" -> {
                getCameraView()?.setHasVideo(call.argument("isEnable"), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setAudioSettings" -> {
                val bitrate = call.argument<Int>("bitrate")
                if (bitrate == null || bitrate <= 0) {
                    result.error("setAudioSettings", "bitrate must be > 0", null)
                } else {
                    nativeViewFactory?.pendingAudioBitrate = bitrate
                    val view = getCameraView()
                    if (view != null) {
                        view.setAudioSettings(bitrate, result)
                    } else {
                        result.success(null)
                    }
                }
            }
            "setCapturePreset" -> {
                val preset = ResolutionPreset.valueOf(requireNotNull(call.argument<String>("preset")))
                val cached = cacheOnSuccess(result) {
                    nativeViewFactory?.preset = preset
                    nativeViewFactory?.pendingVideoWidth = null
                    nativeViewFactory?.pendingVideoHeight = null
                }
                val view = getCameraView()
                if (view != null) view.setCapturePreset(preset, cached) else cached.success(null)
            }
            "setVideoSettings" -> {
                val expectedFps = call.argument<Number>("expectedFrameRate")?.toDouble()
                require(expectedFps == null || (expectedFps.isFinite() && expectedFps > 0 && expectedFps % 1.0 == 0.0)) { "expectedFrameRate must be a positive integer" }
                val mode = call.argument<String>("bitRateMode")
                require(mode == null) { "bitRateMode is not exposed on Android" }
                require(call.argument<String>("profileLevel") == null) { "profileLevel is not supported on Android" }
                val bitrate = call.argument<Int>("bitrate")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val frameInterval = call.argument<Int>("frameInterval")
                require(bitrate == null || bitrate > 0) { "bitrate must be > 0" }
                require((width == null) == (height == null)) { "Provide width and height together" }
                require(width == null || (width > 0 && height!! > 0 && width % 2 == 0 && height % 2 == 0)) {
                    "width and height must be positive even numbers"
                }
                require(frameInterval == null || frameInterval > 0) { "frameInterval must be > 0" }
                if (width != null) {
                    nativeViewFactory?.pendingVideoWidth = width
                    nativeViewFactory?.pendingVideoHeight = height
                }
                if (frameInterval != null) nativeViewFactory?.pendingFrameInterval = frameInterval
                if (bitrate != null) {
                    nativeViewFactory?.pendingVideoBitrate = bitrate
                }
                if (expectedFps != null) nativeViewFactory?.pendingFrameRate = expectedFps.toInt()
                val view = getCameraView()
                if (view != null) {
                    if (expectedFps != null) view.setFrameRate(expectedFps.toInt(), object : MethodChannel.Result {
                        override fun success(value: Any?) {}
                        override fun error(code: String, message: String?, details: Any?) {}
                        override fun notImplemented() {}
                    })
                    view.setVideoSettings(bitrate, width, height, frameInterval, result)
                } else {
                    result.success(null)
                }
            }
            "setFrameRate" -> {
                val frameRate = call.argument<Int>("frameRate")
                if (frameRate == null || frameRate <= 0) {
                    result.error("setFrameRate", "frameRate must be > 0", null)
                } else {
                    nativeViewFactory?.pendingFrameRate = frameRate
                    val view = getCameraView()
                    if (view != null) {
                        view.setFrameRate(frameRate, result)
                    } else {
                        result.success(null)
                    }
                }
            }
            "switchCamera" -> {
                Log.i("Stuff", "switchCamera")
                val name = call.argument<String>("cameraName")
                if (name != null) {
                    nativeViewFactory?.cameraName = name
                }
                getCameraView()?.switchCamera(name, result)
            }
            "switchAudio" -> {
                Log.i("Stuff", "switchAudio")
                getCameraView()?.switchAudio(call.argument("isEnable"),result)
            }
            "switchFlashLight" -> {
                Log.i("Stuff", "switchFlashLight")
                getCameraView()?.switchFlashLight(call.argument("isEnable"),result)
            }
            "setFilter" -> {
              Log.i("Stuff", "setFilter")
              getCameraView()?.setFilter(call.argument("type"),call.argument("filePath"),result)
                ?: result.error("no_camera", "Camera not initialized", null)
            }
            "removeFilter" -> {
              Log.i("Stuff", "removeFilter")
              getCameraView()?.removeFilter(call.argument("type"),result)
                ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setOverlayText" -> {
                getCameraView()?.setOverlayText(
                    call.argument("text"),
                    call.argument<Number>("fontSize")?.toDouble(),
                    call.argument<Number>("colorArgb")?.toInt(),
                    call.argument("position"),
                    call.argument<Number>("scale")?.toDouble(),
                    result
                ) ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setOverlayImage" -> {
                getCameraView()?.setOverlayImage(
                    call.argument("filePath"),
                    call.argument("position"),
                    call.argument<Number>("scale")?.toDouble(),
                    result
                ) ?: result.error("no_camera", "Camera not initialized", null)
            }
            "clearOverlay" -> {
                getCameraView()?.clearOverlay(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setPitchShift" -> {
                getCameraView()?.setPitchShift(call.argument<Number>("pitch")?.toDouble(), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "lockExposure" -> {
                getCameraView()?.lockExposure(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "unlockExposure" -> {
                getCameraView()?.unlockExposure(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "isExposureLocked" -> {
                getCameraView()?.isExposureLocked(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setVideoCodec" -> {
                val value = call.argument<String>("name")
                val cached = cacheOnSuccess(result) { nativeViewFactory?.pendingVideoCodec = value }
                val view = getCameraView()
                if (view != null) view.setVideoCodec(value, cached)
                else cached.success(null)
            }
            "setAudioCodec" -> {
                val value = call.argument<String>("name")
                val cached = cacheOnSuccess(result) { nativeViewFactory?.pendingAudioCodec = value }
                val view = getCameraView()
                if (view != null) view.setAudioCodec(value, cached)
                else cached.success(null)
            }
            "setAudioProcessing" -> {
                val echo = call.argument<Boolean>("echoCanceler")
                val noise = call.argument<Boolean>("noiseSuppressor")
                if (echo != null) nativeViewFactory?.pendingEchoCanceler = echo
                if (noise != null) nativeViewFactory?.pendingNoiseSuppressor = noise
                val view = getCameraView()
                if (view != null) {
                    view.setAudioProcessing(echo, noise, result)
                } else {
                    result.success(null)
                }
            }
            "lockWhiteBalance" -> {
                getCameraView()?.lockWhiteBalance(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "unlockWhiteBalance" -> {
                getCameraView()?.unlockWhiteBalance(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "isWhiteBalanceLocked" -> {
                getCameraView()?.isWhiteBalanceLocked(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "tapToMeter" -> {
                getCameraView()?.tapToMeter(
                    call.argument<Number>("x")?.toDouble(),
                    call.argument<Number>("y")?.toDouble(),
                    call.argument("mode"),
                    result
                ) ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setRtmpMetadata" -> {
                val metadata = call.argument<Map<String, Any>>("metadata")
                require(metadata != null && metadata.all { (key, value) ->
                    key.isNotBlank() && (value is String || value is Boolean ||
                        (value is Number && value.toDouble().isFinite()))
                }) { "Metadata requires nonempty keys and finite scalar values" }
                val cached = cacheOnSuccess(result) { nativeViewFactory?.pendingRtmpMetadata = metadata.toMap() }
                val view = getCameraView()
                if (view == null) cached.success(null) else view.setRtmpMetadata(metadata, cached)
            }
            "requestKeyFrame" -> getCameraView()?.requestKeyFrame(result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "setManualExposure" -> getCameraView()?.setManualExposure(
                call.argument<Number>("iso")?.toInt(),
                call.argument<Number>("exposureTimeNanos")?.toLong(), result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "setCaptureTelemetry" -> getCameraView()?.setCaptureTelemetry(
                call.argument("enabled"), call.argument<Number>("intervalMs")?.toLong(), result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "getCameraControls" -> getCameraView()?.getCameraControls(result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "setZoom" -> getCameraView()?.setZoom(call.argument<Number>("zoom")?.toFloat(), result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "setAutoFocus" -> getCameraView()?.setAutoFocus(call.argument("enabled"), result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "tapToFocus" -> getCameraView()?.tapToFocus(
                call.argument<Number>("x")?.toDouble(), call.argument<Number>("y")?.toDouble(), result)
                ?: result.error("no_camera", "Camera not initialized", null)
            "setVideoSource" -> {
                val value = call.argument<String>("mode")
                val cached = cacheOnSuccess(result) { nativeViewFactory?.pendingVideoSource = value }
                val view = getCameraView()
                if (view != null) view.setVideoSource(value, cached)
                else cached.success(null)
            }
            "enableBufferAudio" -> {
                val value = call.argument<Boolean>("enable")
                val cached = cacheOnSuccess(result) { nativeViewFactory?.pendingUseBufferAudio = value }
                val view = getCameraView()
                if (view != null) view.enableBufferAudio(value, cached)
                else cached.success(null)
            }
            "feedPcmAudio" -> {
                getCameraView()?.feedPcmAudio(call.argument("bytes") as ByteArray?, result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "startMultiStreaming" -> {
                @Suppress("UNCHECKED_CAST")
                val destinations = call.argument<List<Map<String, Any?>>>("destinations")
                getCameraView()?.startMultiStreaming(
                    destinations,
                    call.argument("bitrate"),
                    result
                ) ?: result.error("no_camera", "Camera not initialized", null)
            }
            "stopStreamingDestination" -> {
                getCameraView()?.stopStreamingDestination(call.argument("id"), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "stopMultiStreaming" -> {
                getCameraView()?.stopMultiStreaming(result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "requestScreenCapture" -> {
                requestScreenCapture(result)
            }
            "dispose" -> {
                Log.i("Stuff", "dispose")
                handler?.removeCallbacksAndMessages(null)
                pendingInitialization?.error("disposed", "Camera disposed during initialization", null)
                pendingInitialization = null
                pendingScreenResult?.error("disposed", "Camera disposed during screen capture request", null)
                pendingScreenResult = null
                disconnectScreenCaptureService()
                val view = getCameraView()
                if (view != null) {
                    try {
                        view.dispose()
                    } catch (e: Exception) {
                        Log.e("TAG", "dispose failed", e)
                    }
                }
                result.success(null)
                nativeViewFactory?.pendingRtmpMetadata = null
                nativeViewFactory?.pendingAudioBitrate = null
                nativeViewFactory?.pendingVideoBitrate = null
                nativeViewFactory?.pendingVideoWidth = null
                nativeViewFactory?.pendingVideoHeight = null
                nativeViewFactory?.pendingFrameInterval = null
                nativeViewFactory?.pendingFrameRate = null
                nativeViewFactory?.pendingForceBt709Color = null
                nativeViewFactory?.pendingRtmpShouldSendPings = null
                nativeViewFactory?.pendingVideoCodec = null
                nativeViewFactory?.pendingAudioCodec = null
                nativeViewFactory?.pendingEchoCanceler = null
                nativeViewFactory?.pendingNoiseSuppressor = null
                nativeViewFactory?.pendingVideoSource = null
                nativeViewFactory?.pendingUseBufferAudio = null
                nativeViewFactory?.cameraNativeView = null
                handler?.looper?.thread?.let { t ->
                    if (t is HandlerThread) t.quitSafely()
                }
                handler = null
                dartMessenger = null
                // Keep nativeViewFactory for hot restart - Flutter will call initialize again
            }

            else -> result.notImplemented()
        }
            } catch (e: Exception) {
            result.error("CameraError", e.message, null)
        }
    }

    private fun cacheOnSuccess(result: MethodChannel.Result, cache: () -> Unit): MethodChannel.Result =
        object : MethodChannel.Result {
            override fun success(reply: Any?) {
                cache()
                result.success(reply)
            }
            override fun error(code: String, message: String?, details: Any?) = result.error(code, message, details)
            override fun notImplemented() = result.notImplemented()
        }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun requestScreenCapture(result: MethodChannel.Result) {
        val binding = activityBinding
        if (binding == null) {
            result.error("requestScreenCapture", "Activity not attached", null)
            return
        }
        if (pendingScreenResult != null) {
            result.error("requestScreenCapture", "Screen capture request already in progress", null)
            return
        }
        val mgr = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        ensureScreenCaptureListener()
        if (getCameraView() == null) {
            result.error("requestScreenCapture", "Mount CameraPreview first", null)
            return
        }
        if (getCameraView()?.hasActiveCapture() == true) {
            result.error("requestScreenCapture", "Stop streaming and recording before requesting screen capture", null)
            return
        }
        disconnectScreenCaptureService()
        activity.stopService(Intent(activity, ScreenCaptureService::class.java))
        pendingScreenResult = result
        activity.startActivityForResult(mgr.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun ensureScreenCaptureListener() {
        if (screenCaptureListenerRegistered) return
        val binding = activityBinding ?: return
        screenCaptureListenerRegistered = true
        val listener = PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
            if (requestCode != SCREEN_CAPTURE_REQUEST) return@ActivityResultListener false
            val pending = pendingScreenResult
            if (pending == null) return@ActivityResultListener true
            if (resultCode == Activity.RESULT_OK && data != null) {
                val view = getCameraView()
                if (view == null) {
                    pendingScreenResult = null
                    pending.error("requestScreenCapture", "Mount CameraPreview first", null)
                    return@ActivityResultListener true
                }
                val context = activity.applicationContext
                val intent = Intent(context, ScreenCaptureService::class.java)
                val connection = object : ServiceConnection {
                    override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                        val reply = pendingScreenResult
                        pendingScreenResult = null
                        if (reply == null) {
                            disconnectScreenCaptureService()
                            context.stopService(intent)
                            return
                        }
                        try {
                            val projection = (binder as ScreenCaptureService.CaptureBinder)
                                .createProjection(resultCode, data, view.usesMicrophone())
                            val currentView = getCameraView()
                            if (currentView == null) {
                                projection.stop()
                                reply.error("requestScreenCapture", "Camera preview was disposed", null)
                            } else currentView.attachScreenMediaProjection(projection, reply)
                        } catch (e: Exception) {
                            reply.error("requestScreenCapture", e.message, null)
                            context.stopService(intent)
                        } finally {
                            disconnectScreenCaptureService()
                        }
                    }
                    override fun onServiceDisconnected(name: ComponentName) {
                        pendingScreenResult?.error("requestScreenCapture", "Screen capture service disconnected", null)
                        pendingScreenResult = null
                        disconnectScreenCaptureService()
                    }
                }
                screenCaptureConnection = connection
                try {
                    if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                    check(context.bindService(intent, connection, Context.BIND_AUTO_CREATE)) {
                        "Unable to bind screen capture service"
                    }
                } catch (e: Exception) {
                    pendingScreenResult = null
                    disconnectScreenCaptureService()
                    context.stopService(intent)
                    pending.error("requestScreenCapture", e.message, null)
                }
            } else {
                pendingScreenResult = null
                pending.error("requestScreenCapture", "User denied or cancelled", null)
            }
            true
        }
        screenCaptureListener = listener
        binding.addActivityResultListener(listener)
    }

    private fun disconnectScreenCaptureService() {
        screenCaptureConnection?.let { connection ->
            attachedActivity?.applicationContext?.let { context ->
                runCatching { context.unbindService(connection) }
            }
        }
        screenCaptureConnection = null
    }

    fun attachActivity(binding: ActivityPluginBinding) {
        attachedActivity = binding.activity
        registeredFactory.activity = binding.activity
        registeredFactory.cameraNativeView?.reattachActivity(binding.activity)
        activityBinding = binding
    }

    fun detachActivity(releaseView: Boolean = true) {
        handler?.removeCallbacksAndMessages(null)
        pendingInitialization?.error("activity_detached", "Activity detached during initialization", null)
        pendingInitialization = null
        disconnectScreenCaptureService()
        attachedActivity?.stopService(Intent(attachedActivity, ScreenCaptureService::class.java))
        pendingScreenResult?.error("activity_detached", "Activity detached during screen capture request", null)
        pendingScreenResult = null
        if (releaseView) {
            getCameraView()?.dispose()
            registeredFactory.cameraNativeView = null
        } else getCameraView()?.detachActivity()
        registeredFactory.activity = null
        activityBinding = null
        attachedActivity = null
    }

    fun stopListening() {
        detachActivity()
        dartMessenger?.dispose()
        registeredFactory.dartMessenger = null
        methodChannel.setMethodCallHandler(null)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    @Throws(CameraAccessException::class)
    private fun instantiateCamera(call: MethodCall, result: MethodChannel.Result) {
        val currentHandler: Handler = if (handler != null) {
            handler!!
        } else {
            // Re-init after dispose (e.g. hot restart) - recreate handler and dartMessenger
            Handler(android.os.Looper.getMainLooper()).also {
                handler = it
                dartMessenger = DartMessenger(messenger, id)
            }
        }
        if (activity.isFinishing) {
            result.error("activity_destroyed", "Activity is finishing, cannot initialize camera", null)
            return
        }
        pendingInitialization = result
        currentHandler.postDelayed({
            pendingInitialization = null
            if (activity.isFinishing) {
                activity.runOnUiThread { result.error("activity_destroyed", "Activity was destroyed during initialization", null) }
                return@postDelayed
            }
            try {
                val cameraName = call.argument<String>("cameraName") ?: "0"
                val resolutionPreset = call.argument<String>("resolutionPreset") ?: "low"
                val enableAudio = call.argument<Boolean>("enableAudio") ?: true

                val preset = ResolutionPreset.valueOf(resolutionPreset)
                val previewSize = CameraUtils.computeBestPreviewSize(activity, cameraName, preset)
                val size = previewSize["size"] as? Size ?: run {
                    activity.runOnUiThread { result.error("CameraError", "Failed to compute preview size", null) }
                    return@postDelayed
                }
                val reply: MutableMap<String, Any> = HashMap()
                reply["textureId"] = textureId
                reply["previewWidth"] = size.width
                reply["previewHeight"] = size.height
                reply["eventId"] = id
                reply["previewQuarterTurns"] = 0
                Log.i(
                    "TAG",
                    "open: width: " + reply["previewWidth"] + " height: " + reply["previewHeight"]
                )
                // TODO Refactor cameraView initialisation
                nativeViewFactory?.cameraName = cameraName
                nativeViewFactory?.preset = preset
                nativeViewFactory?.enableAudio = enableAudio
                nativeViewFactory?.dartMessenger = dartMessenger
                // CameraX lifecycle and binding must run on the main thread.
                activity.runOnUiThread {
                    getCameraView()?.startPreview(cameraName)
                    result.success(reply)
                }
            } catch (e: Exception) {
                Log.e("TAG", "instantiateCamera failed", e)
                activity.runOnUiThread {
                    if (e is CameraAccessException) {
                        result.error("CameraAccess", e.message, null)
                    } else {
                        result.error("CameraError", e.message ?: "Unknown error", null)
                    }
                }
            }
        }, 100)
    }


    // We move catching CameraAccessException out of onMethodCall because it causes a crash
    // on plugin registration for sdks incompatible with Camera2 (< 21). We want this plugin to
    // to be able to compile with <21 sdks for apps that want the camera and support earlier version.
    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun handleException(exception: Exception, result: MethodChannel.Result) {
        result.error(if (exception is CameraAccessException) "CameraAccess" else "CameraError",
            exception.message, null)
    }

    private fun getCameraView(): CameraNativeView? = nativeViewFactory?.cameraNativeView
}