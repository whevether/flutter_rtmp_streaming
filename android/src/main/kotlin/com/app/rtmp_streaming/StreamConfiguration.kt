package com.app.rtmp_streaming

import com.pedro.common.AudioCodec
import com.pedro.common.VideoCodec
import java.net.URI
import java.util.Locale

/** Shared validation runs before a camera session or network client is replaced. */
internal object StreamConfiguration {
    fun validateUrl(protocol: String, url: String): String? {
        val schemes = when (protocol) {
            "rtmp" -> setOf("rtmp", "rtmps")
            "rtsp" -> setOf("rtsp", "rtsps")
            "srt" -> setOf("srt")
            "udp" -> setOf("udp")
            "whip" -> setOf("http", "https")
            else -> return "Unsupported protocol: $protocol"
        }
        val uri = runCatching { URI(url) }.getOrNull()
        return if (uri?.scheme?.lowercase(Locale.ROOT) in schemes && !uri?.host.isNullOrBlank()) null
        else "Invalid $protocol URL: expected ${schemes.joinToString(" or ") { "$it://host" }}"
    }

    fun audioCodec(protocol: String, configured: AudioCodec, explicit: Boolean): AudioCodec =
        if (protocol == "whip" && !explicit) AudioCodec.OPUS else configured

    fun sampleRate(codec: AudioCodec): Int = when (codec) {
        AudioCodec.OPUS -> 48000
        AudioCodec.G711 -> 8000
        else -> 32000
    }

    fun validateCodecs(protocol: String, video: VideoCodec, audio: AudioCodec): String? = when {
        protocol in setOf("srt", "udp") && video !in setOf(VideoCodec.H264, VideoCodec.H265) ->
            "$protocol supports H264/H265 video only"
        protocol in setOf("srt", "udp") && audio == AudioCodec.G711 ->
            "$protocol does not support G711 audio"
        protocol == "whip" && audio !in setOf(AudioCodec.OPUS, AudioCodec.G711) ->
            "WHIP supports OPUS/G711 audio only"
        else -> null
    }
}
