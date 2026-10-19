package com.app.rtmp_streaming

import com.pedro.common.AudioCodec
import com.pedro.common.VideoCodec
import org.junit.Assert.*
import org.junit.Test

class StreamConfigurationTest {
    @Test fun rejectsLookalikeAndMissingHostUrls() {
        for (url in listOf("rtmpbad://host/live", "rtmp://", "rtmp:live", "https://host/live", "rtmp://bad host/live")) {
            assertNotNull(url, StreamConfiguration.validateUrl("rtmp", url))
        }
    }
    @Test fun acceptsSecureAndIpv6Urls() {
        for (url in listOf("rtmp://localhost/live/key", "rtmps://host:443/live/key", "RTMP://host/live", "rtmp://[::1]:1935/live")) {
            assertNull(url, StreamConfiguration.validateUrl("rtmp", url))
        }
        assertNull(StreamConfiguration.validateUrl("whip", "https://host/whip"))
        assertNull(StreamConfiguration.validateUrl("srt", "srt://host:9000?streamid=publish:live"))
    }
    @Test fun whepCannotBeUsedForPublishing() {
        assertNotNull(StreamConfiguration.validateUrl("whep", "https://host/whep"))
    }
    @Test fun whipDefaultsToOpusWithoutOverridingExplicitChoice() {
        assertEquals(AudioCodec.OPUS, StreamConfiguration.audioCodec("whip", AudioCodec.AAC, false))
        assertEquals(AudioCodec.AAC, StreamConfiguration.audioCodec("rtmp", AudioCodec.AAC, false))
        assertEquals(AudioCodec.G711, StreamConfiguration.audioCodec("whip", AudioCodec.G711, true))
        assertNotNull(StreamConfiguration.validateCodecs("whip", VideoCodec.H264, AudioCodec.AAC))
    }
    @Test fun transportStreamRejectsIncompatibleCodecs() {
        for (protocol in listOf("srt", "udp")) {
            for (video in listOf(VideoCodec.AV1, VideoCodec.VP8, VideoCodec.VP9)) {
                assertNotNull(StreamConfiguration.validateCodecs(protocol, video, AudioCodec.AAC))
            }
            assertNotNull(StreamConfiguration.validateCodecs(protocol, VideoCodec.H264, AudioCodec.G711))
            assertNull(StreamConfiguration.validateCodecs(protocol, VideoCodec.H265, AudioCodec.HE_AAC))
            assertNull(StreamConfiguration.validateCodecs(protocol, VideoCodec.H264, AudioCodec.OPUS))
        }
    }
    @Test fun rtmpAndRtspRetainNewCodecs() {
        for (protocol in listOf("rtmp", "rtsp")) for (video in VideoCodec.entries) for (audio in AudioCodec.entries) {
            assertNull(StreamConfiguration.validateCodecs(protocol, video, audio))
        }
    }
    @Test fun codecSampleRatesMatchCaptureRequirements() {
        assertEquals(48000, StreamConfiguration.sampleRate(AudioCodec.OPUS))
        assertEquals(8000, StreamConfiguration.sampleRate(AudioCodec.G711))
        assertEquals(32000, StreamConfiguration.sampleRate(AudioCodec.HE_AAC))
    }
}
