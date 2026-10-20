package com.app.rtmp_streaming

/** Pixel dimensions after RootEncoder has applied display rotation. */
internal object PreviewGeometry {
    fun dimensions(width: Int, height: Int, rotation: Int): Pair<Int, Int> =
        if (rotation % 180 == 0) width to height else height to width
}
