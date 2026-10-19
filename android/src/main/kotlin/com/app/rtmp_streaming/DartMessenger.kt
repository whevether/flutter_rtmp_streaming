package com.app.rtmp_streaming

import android.text.TextUtils
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import java.util.*


class DartMessenger(messenger: BinaryMessenger, eventChannelId: Int) {
    private var eventSink: EventSink? = null
    private val channel = EventChannel(messenger, "com.rtmp_streaming.eventchannel/$eventChannelId")

    fun dispose() {
        eventSink = null
        channel.setStreamHandler(null)
    }

    enum class EventType {
        ERROR, CAMERA_CLOSING, RTMP_STOPPED, RTMP_RETRY, SUCCESS,WAIT,DESTINATION_STOPPED
    }

    fun sendCameraClosingEvent() {
        send(EventType.CAMERA_CLOSING, "close connection")
    }

    fun send(eventType: EventType, description: String?, destinationId: String? = null) {
        if (eventSink == null) {
            return
        }
        val event: MutableMap<String, String?> = HashMap()
        event["eventType"] = eventType.toString().lowercase()
        // Only errors have a description.
        if (!TextUtils.isEmpty(description)) {
            event["errorDescription"] = description
        }
        if (destinationId != null) event["destinationId"] = destinationId
        eventSink?.success(event)
    }

    fun sendCaptureStatistics(values: Map<String, Any?>) {
        eventSink?.success(mapOf("eventType" to "capture_statistics", "captureStatistics" to values))
    }

    init {
        channel.setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventSink) {
                        eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                })
    }
}