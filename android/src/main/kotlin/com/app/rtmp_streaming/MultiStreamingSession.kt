package com.app.rtmp_streaming

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.pedro.common.ConnectChecker
import com.pedro.library.multiple.MultiStream
import com.pedro.library.multiple.MultiType
import com.pedro.library.view.OpenGlView

/**
 * Thin wrapper around RootEncoder experimental [MultiStream].
 * Destinations are grouped by protocol; indices match MultiStream arrays.
 */
@RequiresApi(Build.VERSION_CODES.LOLLIPOP)
class MultiStreamingSession(
    context: Context,
    private val dartMessenger: DartMessenger?,
    private val glView: OpenGlView,
    destinations: List<Destination>
) : ConnectChecker {

    data class Destination(
        val id: String,
        val protocol: String,
        val url: String
    )

    data class Slot(val type: MultiType, val index: Int, val id: String, val url: String)

    private val slots = mutableListOf<Slot>()
    private val multiStream: MultiStream
    private val idByKey = HashMap<String, String>() // "RTMP:0" -> streamId

    init {
        val rtmp = destinations.filter { it.protocol == "rtmp" }
        val rtsp = destinations.filter { it.protocol == "rtsp" }
        val srt = destinations.filter { it.protocol == "srt" }
        val udp = destinations.filter { it.protocol == "udp" }

        fun checkers(list: List<Destination>): Array<ConnectChecker>? {
            if (list.isEmpty()) return null
            return Array(list.size) { this }
        }

        rtmp.forEachIndexed { i, d ->
            slots.add(Slot(MultiType.RTMP, i, d.id, d.url))
            idByKey["RTMP:$i"] = d.id
        }
        rtsp.forEachIndexed { i, d ->
            slots.add(Slot(MultiType.RTSP, i, d.id, d.url))
            idByKey["RTSP:$i"] = d.id
        }
        srt.forEachIndexed { i, d ->
            slots.add(Slot(MultiType.SRT, i, d.id, d.url))
            idByKey["SRT:$i"] = d.id
        }
        udp.forEachIndexed { i, d ->
            slots.add(Slot(MultiType.UDP, i, d.id, d.url))
            idByKey["UDP:$i"] = d.id
        }

        multiStream = MultiStream(
            context,
            checkers(rtmp),
            checkers(rtsp),
            checkers(srt),
            checkers(udp)
        )
    }

    fun prepareAndStart(width: Int, height: Int, fps: Int, vBitrate: Int, aBitrate: Int): Boolean {
        val ok = multiStream.prepareVideo(width, height, vBitrate, fps = fps) &&
            multiStream.prepareAudio(32000, true, aBitrate)
        if (!ok) return false
        if (!multiStream.isOnPreview) {
            multiStream.startPreview(glView)
        }
        for (slot in slots) {
            multiStream.startStream(slot.type, slot.index, slot.url)
        }
        return true
    }

    fun stopDestination(id: String): Boolean {
        val slot = slots.firstOrNull { it.id == id } ?: return false
        multiStream.stopStream(slot.type, slot.index)
        slots.remove(slot)
        return true
    }

    fun stopAll() {
        for (slot in slots.toList()) {
            try {
                multiStream.stopStream(slot.type, slot.index)
            } catch (e: Exception) {
                Log.w("MultiStreamingSession", "stopStream ${slot.id}: ${e.message}")
            }
        }
        slots.clear()
        if (multiStream.isStreaming) {
            // no-op stopStream() per MultiStream docs; stop individually above
        }
        if (multiStream.isOnPreview) {
            multiStream.stopPreview()
        }
        multiStream.release()
    }

    fun hasSlots(): Boolean = slots.isNotEmpty()

    override fun onConnectionStarted(url: String) {}
    override fun onConnectionSuccess() {
        dartMessenger?.send(DartMessenger.EventType.SUCCESS, "connection success")
    }
    override fun onConnectionFailed(reason: String) {
        dartMessenger?.send(DartMessenger.EventType.ERROR, reason)
    }
    override fun onNewBitrate(bitrate: Long) {}
    override fun onDisconnect() {
        dartMessenger?.send(DartMessenger.EventType.RTMP_STOPPED, "disconnected")
    }
    override fun onAuthError() {
        dartMessenger?.send(DartMessenger.EventType.ERROR, "Auth error")
    }
    override fun onAuthSuccess() {}
}
