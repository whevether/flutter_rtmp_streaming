package com.app.rtmp_streaming

import org.junit.Assert.*
import org.junit.Test

class CameraPermissionsTest {
    private fun listener(onResult: (String?) -> Unit) =
        CameraPermissions.CameraRequestPermissionsListener(object : ResultCallback {
            override fun onResult(errorCode: String?, errorDescription: String?) = onResult(errorCode)
        })
    @Test fun videoOnlyPermissionSucceeds() {
        var called = false
        listener { assertNull(it); called = true }
            .onRequestPermissionsResult(9796, arrayOf("android.permission.CAMERA"), intArrayOf(0))
        assertTrue(called)
    }
    @Test fun reorderedDeniedMicrophoneIsNotMistakenForCameraGrant() {
        var error: String? = null
        listener { error = it }.onRequestPermissionsResult(9796,
            arrayOf("android.permission.RECORD_AUDIO", "android.permission.CAMERA"), intArrayOf(-1, 0))
        assertEquals("cameraPermission", error)
    }
    @Test fun cancelledAndTruncatedResultsFail() {
        for (results in listOf(intArrayOf(), intArrayOf(0))) {
            var error: String? = null
            listener { error = it }.onRequestPermissionsResult(9796,
                arrayOf("android.permission.CAMERA", "android.permission.RECORD_AUDIO"), results)
            assertNotNull(error)
        }
    }
    @Test fun unrelatedAndDuplicateCallbacksAreIgnored() {
        var calls = 0
        val listener = listener { calls++ }
        assertFalse(listener.onRequestPermissionsResult(1, emptyArray(), intArrayOf()))
        assertTrue(listener.onRequestPermissionsResult(9796, arrayOf("camera"), intArrayOf(0)))
        assertFalse(listener.onRequestPermissionsResult(9796, arrayOf("camera"), intArrayOf(0)))
        assertEquals(1, calls)
    }
}
