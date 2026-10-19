package com.app.rtmp_streaming

import org.junit.Assert.*
import org.junit.Test

class EncoderColorSettingsTest {
    // Model RootEncoder's guard: color changes after prepareVideo throw.
    private class Encoder {
        var prepared = false
        var bt709 = false
        fun setColor(enabled: Boolean) {
            check(!prepared) { "Encoder already prepared" }
            bt709 = enabled
        }
    }

    @Test fun idlePreviewDefersColorUntilANewEncoderIsPrepared() {
        val settings = EncoderColorSettings()
        val preview = Encoder()
        settings.applyBeforePrepare(preview::setColor)
        preview.prepared = true

        assertTrue(settings.update(true, captureActive = false))
        assertFalse(preview.bt709)
        for (session in listOf("stream", "record", "multi")) {
            val fresh = Encoder()
            settings.applyBeforePrepare(fresh::setColor)
            fresh.prepared = true
            assertTrue(session, fresh.bt709)
        }
    }

    @Test fun rejectedLiveChangePreservesTheNextSessionConfiguration() {
        val settings = EncoderColorSettings()
        settings.update(true, captureActive = false)
        assertThrows(IllegalStateException::class.java) {
            settings.update(false, captureActive = true)
        }
        val fresh = Encoder()
        settings.applyBeforePrepare(fresh::setColor)
        assertTrue(fresh.bt709)
    }

    @Test fun repeatedLiveSettingDoesNotRequireAnEncoderRebuild() {
        val settings = EncoderColorSettings()
        assertFalse(settings.update(false, captureActive = true))
        settings.update(true, captureActive = false)
        assertFalse(settings.update(true, captureActive = true))
    }

    @Test fun lastIdleSelectionSurvivesRepeatedSessionCreation() {
        val settings = EncoderColorSettings()
        settings.update(true, captureActive = false)
        settings.update(false, captureActive = false)
        repeat(2) {
            val fresh = Encoder()
            settings.applyBeforePrepare(fresh::setColor)
            fresh.prepared = true
            assertFalse(fresh.bt709)
        }
    }
}
