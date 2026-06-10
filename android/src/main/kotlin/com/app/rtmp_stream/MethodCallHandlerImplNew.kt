package com.app.rtmp_stream

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.OrientationEventListener
import androidx.annotation.RequiresApi
import com.app.rtmp_stream.CameraPermissions.ResolutionPreset
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
//    private val imageStreamChannel: EventChannel
    private var currentOrientation = OrientationEventListener.ORIENTATION_UNKNOWN
    private var dartMessenger: DartMessenger? = null
    private var nativeViewFactory: NativeViewFactory? = null
    private var handler: Handler? = null
    private val VIEW_TYPE: String = "hybrid-view-type"
    private val id = System.identityHashCode(this)

    private val textureId = 0L

    init {
        val handlerThread = HandlerThread("WorkerThread").apply {
            start()
        }
        handler = Handler(handlerThread.looper)
        Log.d("TAG", "init $platformViewRegistry")
        methodChannel = MethodChannel(messenger, "com.rtmp_streaming")
//        imageStreamChannel = EventChannel(messenger, "plugins.flutter.io/rtmp_publisher/imageStream")
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
                    result
                )
            }

            "startVideoRecordingAndStreaming" -> {
                Log.i("Stuff", "startVideoRecordingAndStreaming ${call.arguments}")
                getCameraView()?.startVideoRecordingAndStreaming(
                    call.argument("filePath"),
                    call.argument("url"),
                    call.argument("bitrate"),
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
                getCameraView()?.setForceBt709Color(call.argument("enabled"), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
            }
            "setRtmpShouldSendPings" -> {
                Log.i("Stuff", "setRtmpShouldSendPings")
                getCameraView()?.setRtmpShouldSendPings(call.argument("enabled"), result)
                    ?: result.error("no_camera", "Camera not initialized", null)
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
            }
            "removeFilter" -> {
              Log.i("Stuff", "removeFilter")
              getCameraView()?.removeFilter(call.argument("type"),result)
            }
            "dispose" -> {
                Log.i("Stuff", "dispose")
                val view = getCameraView()
                if (view != null) {
                    // stopVideoStreaming calls result.success/error - do NOT call result again
                    view.stopVideoStreaming(result)
                    view.dispose()
                } else {
                    result.success(null)
                }
                handler = null
                dartMessenger = null
                // Keep nativeViewFactory for hot restart - Flutter will call initialize again
            }

            else -> result.notImplemented()
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
                reply["previewQuarterTurns"] = currentOrientation / 90
                Log.i(
                    "TAG",
                    "open: width: " + reply["previewWidth"] + " height: " + reply["previewHeight"] + " currentOrientation: " + currentOrientation + " quarterTurns: " + reply["previewQuarterTurns"]
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