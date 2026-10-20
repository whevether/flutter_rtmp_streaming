package com.app.rtmp_streaming

import org.junit.Assert.*
import org.junit.Test

class PreviewGeometryTest {
    @Test fun nativeRotationProducesDisplayDimensionsWithoutAdditionalFlutterTurns() {
        assertEquals(720 to 1280, PreviewGeometry.dimensions(1280, 720, 90))
        assertEquals(720 to 1280, PreviewGeometry.dimensions(1280, 720, 270))
        assertEquals(1280 to 720, PreviewGeometry.dimensions(1280, 720, 0))
        assertEquals(1280 to 720, PreviewGeometry.dimensions(1280, 720, 180))
    }

    @Test fun allUncachedViewOperationsRequireMount() {
        val operations = listOf("setOverlayText", "setOverlayImage", "clearOverlay", "setZoom", "tapToFocus",
            "setManualExposure", "setCaptureTelemetry", "getCameraControls", "feedPcmAudio",
            "startMultiStreaming", "stopStreamingDestination", "stopMultiStreaming", "requestKeyFrame")
        operations.forEach { assertTrue(it, it in CameraMethodPolicy.requiresView) }
        listOf("initialize", "dispose", "getCapabilities", "setVideoSettings", "setForceBt709Color").forEach {
            assertFalse(it, it in CameraMethodPolicy.requiresView)
        }
    }
}
