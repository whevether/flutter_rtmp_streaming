package com.app.rtmp_streaming
import android.app.Activity
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.platform.PlatformViewRegistry

interface PermissionStuff {
    fun adddListener(listener: PluginRegistry.RequestPermissionsResultListener);
}
/** RtmppublisherPlugin */
public class RtmppublisherPlugin : FlutterPlugin, ActivityAware {

    val TAG = "RtmppublisherPlugin"

    /// The MethodChannel that will the˙ communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private var methodCallHandler: MethodCallHandlerImplNew? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        Log.v(TAG, "onAttachedToEngine $flutterPluginBinding")
        this.flutterPluginBinding = flutterPluginBinding
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.v(TAG, "onDetachedFromEngine $binding")
        flutterPluginBinding = null
    }

    private fun maybeStartListening(
        activity: Activity,
        messenger: BinaryMessenger,
        permissionsRegistry: PermissionStuff,
        platformViewRegistry: PlatformViewRegistry) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            // If the sdk is less than 21 (min sdk for Camera2) we don't register the plugin.
            return
        }
        methodCallHandler = MethodCallHandlerImplNew(
            activity,
            messenger,
            CameraPermissions(),
            permissionsRegistry,
            platformViewRegistry)
    }

    override fun onDetachedFromActivity() {
        Log.v(TAG, "onDetachedFromActivity")
        methodCallHandler?.stopListening()
        methodCallHandler = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.v(TAG, "onAttachedToActivity $binding")
        flutterPluginBinding?.apply {
            maybeStartListening(
                binding.activity,
                binaryMessenger,
                object : PermissionStuff {
                    override fun adddListener(listener: PluginRegistry.RequestPermissionsResultListener) {
                        binding.addRequestPermissionsResultListener(listener);
                    }
                },
                platformViewRegistry
            )
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }
}
