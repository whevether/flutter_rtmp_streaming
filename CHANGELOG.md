## 2.3.0

- Fix Android BT.709 configuration after idle preview has prepared its encoder: defer color selection until the next encoder preparation, preserve settings when live changes are rejected, and allow repeated identical settings. Enable the modern Android back callback in the example manifest.
- Add native build/source capability queries, common camera controls, typed capture presets and named Android GPU effects. Keep platform-specific capture and transport APIs explicit.
- Preserve recording when stopping multi-streaming; normalize destination IDs and events, roll back combined starts, make stop-all idempotent, and update pause state only after success.
- Normalize numeric statistics and units; report unavailable metrics as null. Fix iOS settings persistence, SRT bitrate mode, recorder compression settings, active-camera torch, overlay alpha/scale and snapshot framing.
- Add separate iOS PlayerController/PlayerPreview for RTMP/WHEP. Reject unsupported pause, codec, authentication and multitasking requests explicitly.
- Require iOS Swift Package Manager / Swift 6, add FlutterFramework and static binary linker dependencies, migrate example away from Pods, serialize native method requests and clean up initialization/disposal and event subscriptions.
- Deprecate no-op OpenGL/warmup flags, ambiguous audio and canvas names, and integer filter APIs. Audio aliases now mute without detaching capture on both platforms.

## 2.2.0

- Merge PR #14 with fixes for CameraX idle recording, audio preparation, snapshots, encoder/source release, surface loss and independent recording/streaming state.
- Use protocol-specific StreamBase clients so RTMP/RTSP can use AV1, VP8, VP9 and the new audio codecs. Validate URLs and protocol/codec combinations before replacing a session; default WHIP audio to OPUS, with codec-appropriate capture rates.
- Add Android `setRtmpMetadata`, `requestKeyFrame`, `getCameraControls`, `setZoom`, `setAutoFocus`, `tapToFocus`, Camera2 `setManualExposure` and rate-limited `setCaptureTelemetry`.
- Apply custom dimensions and keyframe intervals on prepare; retain mute, filters, overlays and pitch across session recreation. Fix asynchronous video-overlay preparation and player resource leaks. Recreate the queue bitrate adapter using the configured bitrate budget.
- Add the MediaProjection foreground service and handle consent cancellation/revocation. Screen sessions require fresh consent after stopping; do not reuse Android 14+ capture tokens.
- Fix permission result handling, Activity reattachment, pending initialization cleanup and calls before the platform preview mounts. Isolate stale session callbacks and multi-destination retries; preserve `destinationId` in events.
- Enable TLS hostname verification for RTMPS/RTSPS; disable native client logs by default and avoid logging stream URLs/tokens.
- Upgrade AGP to 9.4.1, Gradle to 9.8.1 (with checksum), Kotlin to 2.4.21, AndroidX Annotation to 1.11.0 and compile SDK to 37.2. Keep stable NDK 30.0.16248370 / Build Tools 37.0.0. Update example packages, pin permission_handler and require Flutter >=3.44 / Dart >=3.12. RootEncoder 2.8.1 and HaishinKit SPM 2.2.5 are already current; CocoaPods remains at its latest published HaishinKit 2.0.9 / SRTHaishinKit 2.0.8.
- Expand regression tests and demonstrate the Android controls, codecs, sources and metadata. Hardware capture, live servers and iOS compilation still require device/platform validation.

## 2.1.1

1. **Android**: Fix front camera resetting to rear on `startVideoStreaming` (camera2 / CameraX / WHIP / StreamBase / multi / record).
2. **Android**: Route filters, overlays, mute, pitch, flashlight, AE/WB lock, and tap-to-meter through the active pipeline (GenericCamera2, GenericStream, WhipStream, MultiCamera2).
3. **Android**: `enableBufferAudio` while GenericCamera2 is live migrates the session to StreamBase; `startVideoRecording` / record+stream work on StreamBase/WHIP; WHIP ABR enabled.
4. **Docs**: Clarify `setVideoSource` facing behavior (CameraX front/back; UVC/screen N/A) and idle preview remaining Camera2 until stream start.

## 2.1.0

1. **Android build**: AGP **9.4.0**, Gradle **9.7.1**, plugin `android/` converted to Kotlin DSL (`.gradle.kts`). Plugin-level `gradle/wrapper` and `gradle.properties` removed (host/example owns Gradle/AndroidX). 
2. **RootEncoder 2.8.1**: `library` + `extra-sources`; overlay filter renames (`GifFilterRender` / `ImageFilterRender` / `TextFilterRender`); `SpriteGestureController.setSprite`; queue-aware ABR via `QueueAwareBitrateAdapter`.
3. **Android codecs / audio**: `setVideoCodec` / `setAudioCodec`; `setAudioProcessing` (echo cancel + noise suppressor).
4. **Android camera controls**: white-balance lock; `tapToMeter` (exposure / WB).
5. **Android multi-streaming**: `startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming` via `MultiCamera2` (aligned with iOS Dart API; WHIP/WHEP excluded).
6. **Android sources**: `setVideoSource` (`camera2` / `cameraX` / `uvc` / `screen`), `requestScreenCapture`, `enableBufferAudio` / `feedPcmAudio` (StreamBase path for non-camera2).
7. **Stats**: `StreamStatistics` adds `queueBytesOut`, `bytesOutPerSecond`, `queueCongestionPercent`, `totalBytesOut`.
8. **Hardening**: dispose no longer double-completes MethodChannel; MediaProjection stopped on replace/dispose; GenericStream parity for retry/codecs/bitrate/BT.709; start-while-streaming restarts; pending cache for codecs/source/AEC.
9. **Breaking**: `CameraValue.isStreamingVideoRtmp` renamed to `isStreaming` (covers all protocols). Empty Android `close()` stub removed.
10. **WHEP**: still Android ❌ (RootEncoder has WHIP only).

## 2.0.1

1. **Android**: Fix `Camera not initialized` when calling encoder settings after `initialize` but before `CameraPreview` mounts.
   - `setAudioSettings` / `setVideoSettings` / `setFrameRate` / `setForceBt709Color` / `setRtmpShouldSendPings` now cache values and apply them when the platform view is created (and keep the cache on remount).
2. **Docs**: Clarify Android timing for these APIs and that `CameraPreview` is still required before starting a stream.


## 2.0.0

1. **Multi-protocol streaming**
   - Added `StreamingProtocol` (`rtmp` / `rtsp` / `srt` / `udp` / `whip` / `whep`) for `startVideoStreaming`.
   - Android (RootEncoder **2.8.0**): RTMP, RTSP, SRT, UDP, WHIP.
   - iOS (HaishinKit **2.2.5**): RTMP, SRT; WHIP/WHEP via `RTCHaishinKit` (alpha, Flutter SPM).

2. **Overlay / watermark** (Android + iOS)
   - `setOverlayText` / `setOverlayImage` / `clearOverlay`.
   - iOS: when overlay is enabled, canvas / encoder size follows portrait or landscape (avoids stretched/shrunk preview).

3. **Multi-streaming** (iOS only; Android since **2.1.0**)
   - `startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming` (WHIP/WHEP not allowed).
   - Example defaults to one RTMP + one SRT destination.

4. **SRT URL compatibility** (iOS)
   - `SrtURLHelper` supports SRS/ZLMediaKit-style URLs such as  
     `srt://host:10080?streamid=#!::r=live/livestream,m=publish`  
     (`#` is applied via `SRTO_STREAMID`, not as a URL fragment).
   - Clearer SRT connect error messages (`unsupportedUri` / reject reason).

5. **iOS EventChannel**
   - Native → Flutter events are always posted on the platform (main) thread.

6. **Android extras**
   - `setPitchShift` (RootEncoder pitch effect; `1.0` disables).
   - `lockExposure` / `unlockExposure` / `isExposureLocked` (after preview/stream start).
   - Target / toolchain updates (e.g. compileSdk 37, AGP 9.x).

7. **Docs & example**
   - README / README_zhCN and example app updated for protocols, overlay, and iOS multi-streaming.


## 1.0.8

1. Fixed an error in the prepareVideo parameter that could cause compilation errors.


## 1.0.7
1. **Dependency upgrades**
   - iOS: `HaishinKit` pod bumped from `2.0.9` to **`2.2.5`** (aligned with Swift Package; Xcode 26.4, multitasking camera, etc.).
   - Android: `com.github.pedroSG94.RootEncoder:library` bumped to **`2.7.5`**.

2. **Cross-platform API alignment** (previously iOS-only or Dart-only without native wiring)
   - `prepareForVideoStreaming()`: iOS pre-attaches audio to reduce start latency; Android no-op.
   - `getHasAudio` / `setHasAudio`: query/set **temporary mute** while streaming (does not detach the mic).
   - `getHasVideo` / `setHasVideo`: query/set **temporary video mute** (Android sends black frames; iOS mixer mute).
   - `setAudioSettings(bitrate)`: audio encoder bitrate in bps; applied on next `prepareAudio`.
   - `setVideoSettings({ bitrate, ... })`: video encoder settings; Android can hot-update `bitrate` via `setVideoBitrateOnFly` while live.
   - `setFrameRate(frameRate)`: target capture/encode frame rate (call before streaming when possible).
   - `switchAudio`: now available on **both Android and iOS** (toggles mic capture; different from `setHasAudio`).

3. **Stream statistics**
   - `StreamStatistics` adds `isVideoMuted`.
   - iOS `getStreamStatistics` now returns `isAudioMuted`, `isVideoMuted`, `bytesSend`, etc.
   - Android `getStreamStatistics` adds `isVideoMuted`.

4. **Documentation**
   - README / README_zhCN updated method lists and cross-platform API usage.


## 1.0.6
1. fix android issue  #8 question
2. update package name


## 1.0.5
1. update HaishinKit.swift to 2.2.5 fix xcode 26.4 build error
2. update com.github.pedroSG94.RootEncoder to 2.7.1

3. **Documentation**: Added usage notes in README / README_zhCN for the following `CameraController` methods:
   - **Android (RootEncoder 2.7.0+)**: `setForceBt709Color`, `setRtmpShouldSendPings` — BT.709 color matrix for encoding; RTMP periodic ping for RTT (see `getStreamStatistics` / `rttMicros` when pings are enabled).
   - **iOS (HaishinKit 2.2.1+ / 2.2.2+ / 2.2.5+)**: `setVideoSettings` — optional `expectedFrameRate` (onMetaData `framerate`) and `bitRateMode` (`average` / `constant` / `variable`); `setMultitaskingCameraAccessEnabled` — multitasking / PiP camera access (iOS 17+ when supported).
4. **CHANGELOG**: This entry records the above API documentation and usage guidance; behavior matches implementations added in plugin development for RootEncoder 2.7.x and HaishinKit 2.2.x.


## 1.0.3
1. fix android permission bug


## 1.0.2
1. update package
2. fix bug not removeFilter


## 1.0.1
1. update package
2. add - 📸 Take snapshot during streaming: `takePicture`


## 1.0.0
1. Updated iOS HaishinKit to version 2.0.0 (stable release).  
2. Completely refactored iOS code, now managing dependencies via Swift Package Manager.  
3. Added numerous new methods for iOS.  
4. Updated examples: revised `camera.dart`, removed redundant fields and duplicate methods.  
5. Upgraded Android Gradle to 9.0, updated RTMP package to the latest version, unified return values with iOS, and improved disposal methods.  
6. Added filter functionality for Android.  


## 0.0.6
1. Updated iOS HaishinKit to version 2.0.0 (preview version, not stable, may contain bugs).  


## 0.0.5
1. Optimized Android example project.  
2. Added pause/resume recording functionality for Android.  


## 0.0.4
1. Fixed Android crash errors when switching cameras. Added camera switching and audio toggle features. Optimized the example project.  
2. Cleaned up unused methods.  


## 0.0.3
1. Upgraded iOS HaishinKit to version 1.9.9.  
2. Rewrote some deprecated methods.  


## 0.0.2
1. Removed redundant Android packages to reduce build size.  


## 0.0.1
1. Completely refactored the Android version. Upgraded Gradle and the RTMP streaming plugin `com.github.pedroSG94.RootEncoder` to the latest version.  
2. Added filters for the Android version.  
3. Improved deprecated methods and fixed crashes caused by camera switching on Android.  
4. Fixed the issue where live recording could not be captured on Android.  
5. Added a toggle for low-light environment settings on Android.  






















