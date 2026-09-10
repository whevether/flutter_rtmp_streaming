package com.app.rtmp_streaming

import android.app.Activity
import android.content.Context
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
    private val activity: Activity,
    private val messenger: BinaryMessenger,
    private val cameraPermissions: CameraPermissions,
    private val permissionsRegistry: PermissionStuff,
    private val platformViewRegistry: PlatformViewRegistry
) : MethodCallHandler {

    private val methodChannel: MethodChannel
    private var dartMessenger: DartMessenger? = null
    private var nativeViewFactory: NativeViewFactory? = null
    private var handler: Handler? = null
    private val VIEW_TYPE: String = "hybrid-view-type"
    private val id = System.identityHashCode(this)

    private val textureId = 0L

    private val SCREEN_CAPTURE_REQUEST = 4001
    private var pendingScreenResult: MethodChannel.Result? = null
    private var screenCaptureListenerRegistered = false
    var activityBinding: ActivityPluginBinding? = null
        set(value) {
            if (field !== value) {
                screenCaptureListenerRegistered = false
            }
            field = value
        }

    init {
        val handlerThread = HandlerThread("WorkerThread").apply {
            start()
        }
        handler = Handler(handlerThread.looper)
        Log.d("TAG", "init $platformViewRegistry")
        methodChannel = MethodChannel(messenger, "com.rtmp_streaming")
        methodChannel.setMethodCallHandler(this)
        dartMessenger = DartMessenger(messenger, id)
        nativeViewFactory = NativeViewFactory(activity)

        platformViewRegistry
            .registerViewFactory(VIEW_TYPE, nativeViewFactory as NativeViewFactory)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
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
                Log.i("Stuff", "startVideoStreaming ${call.arguments}")
                getCameraView()?.startVideoStreaming(
                    call.argument("url"),
                    call.argument("bitrate"),
                    call.argument("protocol"),
                    call.argument("whipToken"),
                    result
                )
            }

            "startVideoRecordingAndStreaming" -> {
                Log.i("Stuff", "startVideoRecordingAndStreaming ${call.arguments}")
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
                if (bitrate == null) {
                    result.error("setAudioSettings", "bitrate is required", null)
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
            "setVideoSettings" -> {
                val bitrate = call.argument<Int>("bitrate")
                val width = call.argument<Int>("width")
                val height = call.argument<Int>("height")
                val frameInterval = call.argument<Int>("frameInterval")
                if (bitrate != null) {
                    nativeViewFactory?.pendingVideoBitrate = bitrate
                }
                val view = getCameraView()
                if (view != null) {
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
                getCameraView()?.switchCamera(call.argument("cameraName"),result)
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
                val name = call.argument<String>("name")
                nativeViewFactory?.pendingVideoCodec = name
                val view = getCameraView()
                if (view != null) {
                    view.setVideoCodec(name, result)
                } else {
                    result.success(null)
                }
            }
            "setAudioCodec" -> {
                val name = call.argument<String>("name")
                nativeViewFactory?.pendingAudioCodec = name
                val view = getCameraView()
                if (view != null) {
                    view.setAudioCodec(name, result)
                } else {
                    result.success(null)
                }
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
            "setVideoSource" -> {
                val mode = call.argument<String>("mode")
                nativeViewFactory?.pendingVideoSource = mode
                val view = getCameraView()
                if (view != null) {
                    view.setVideoSource(mode, result)
                } else {
                    result.success(null)
                }
            }
            "enableBufferAudio" -> {
                val enable = call.argument<Boolean>("enable")
                nativeViewFactory?.pendingUseBufferAudio = enable
                val view = getCameraView()
                if (view != null) {
                    view.enableBufferAudio(enable, result)
                } else {
                    result.success(null)
                }
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
                val view = getCameraView()
                if (view != null) {
                    try {
                        view.dispose()
                    } catch (e: Exception) {
                        Log.e("TAG", "dispose failed", e)
                    }
                }
                result.success(null)
                nativeViewFactory?.pendingAudioBitrate = null
                nativeViewFactory?.pendingVideoBitrate = null
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
        pendingScreenResult = result
        activity.startActivityForResult(mgr.createScreenCaptureIntent(), SCREEN_CAPTURE_REQUEST)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    private fun ensureScreenCaptureListener() {
        if (screenCaptureListenerRegistered) return
        val binding = activityBinding ?: return
        screenCaptureListenerRegistered = true
        binding.addActivityResultListener { requestCode, resultCode, data ->
            if (requestCode != SCREEN_CAPTURE_REQUEST) return@addActivityResultListener false
            val pending = pendingScreenResult
            pendingScreenResult = null
            if (pending == null) return@addActivityResultListener true
            if (resultCode == Activity.RESULT_OK && data != null) {
                val mgr = activity.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val projection = mgr.getMediaProjection(resultCode, data)
                val view = getCameraView()
                if (projection != null && view != null) {
                    view.attachScreenMediaProjection(projection, pending)
                } else {
                    try {
                        projection?.stop()
                    } catch (_: Exception) {
                    }
                    pending.error(
                        "requestScreenCapture",
                        if (projection == null) {
                            "Failed to create MediaProjection"
                        } else {
                            "Camera not initialized; mount CameraPreview before requestScreenCapture"
                        },
                        null
                    )
                }
            } else {
                pending.error("requestScreenCapture", "User denied or cancelled", null)
            }
            true
        }
    }

    fun stopListening() {
        methodChannel.setMethodCallHandler(null)
    }

    @RequiresApi(Build.VERSION_CODES.LOLLIPOP)
    @Throws(CameraAccessException::class)
    private fun instantiateCamera(call: MethodCall, result: MethodChannel.Result) {
        val currentHandler: Handler = if (handler != null) {
            handler!!
        } else {
            // Re-init after dispose (e.g. hot restart) - recreate handler and dartMessenger
            val handlerThread = HandlerThread("WorkerThread").apply { start() }
            Handler(handlerThread.looper).also {
                handler = it
                dartMessenger = DartMessenger(messenger, id)
            }
        }
        if (activity.isFinishing) {
            result.error("activity_destroyed", "Activity is finishing, cannot initialize camera", null)
            return
        }
        currentHandler.postDelayed({
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
                getCameraView()?.startPreview(cameraName)
                // MethodChannel.Result must be invoked on the main thread
                activity.runOnUiThread { result.success(reply) }
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
        if (exception is CameraAccessException) {
            result.error("CameraAccess", exception.message, null)
        }
        throw (exception as RuntimeException)
    }

    private fun getCameraView(): CameraNativeView? = nativeViewFactory?.cameraNativeView
}