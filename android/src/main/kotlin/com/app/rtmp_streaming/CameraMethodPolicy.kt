package com.app.rtmp_streaming

/** Every method using an existing view must finish with an error before mount. */
internal object CameraMethodPolicy {
    val requiresView = setOf(
        "takePicture", "startVideoRecording", "startVideoStreaming", "startVideoRecordingAndStreaming",
        "stopRecordingOrStreaming", "stopRecording", "stopStreaming", "pauseVideoRecording",
        "resumeVideoRecording", "getStreamStatistics", "switchCamera", "switchFlashLight", "switchAudio",
        "setFilter", "removeFilter", "getHasAudio", "setHasAudio", "getHasVideo", "setHasVideo",
        "prepareForVideoStreaming", "setOverlayText", "setOverlayImage", "clearOverlay", "setPitchShift",
        "lockExposure", "unlockExposure", "isExposureLocked", "lockWhiteBalance", "unlockWhiteBalance",
        "isWhiteBalanceLocked", "tapToMeter", "requestKeyFrame", "setManualExposure", "setCaptureTelemetry",
        "getCameraControls", "setZoom", "setAutoFocus", "tapToFocus", "feedPcmAudio", "startMultiStreaming",
        "stopStreamingDestination", "stopMultiStreaming", "requestScreenCapture"
    )
}
