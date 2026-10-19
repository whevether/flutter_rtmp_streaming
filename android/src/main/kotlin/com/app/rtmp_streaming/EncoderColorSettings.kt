package com.app.rtmp_streaming

/** Color options belong to encoder preparation, not to the running preview. */
internal class EncoderColorSettings {
    private var forceBt709 = false

    /** Return whether a new encoder is needed; reject live changes atomically. */
    fun update(enabled: Boolean, captureActive: Boolean): Boolean {
        if (enabled == forceBt709) return false
        check(!captureActive) { "Stop streaming and recording before changing BT.709 color" }
        forceBt709 = enabled
        return true
    }

    /** Call only when configuring a fresh, unprepared encoder. */
    fun applyBeforePrepare(apply: (Boolean) -> Unit) {
        apply(forceBt709)
    }
}
