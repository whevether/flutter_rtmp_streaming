# rtmp_streaming

## 📖 Overview
`rtmp_streaming` is a Flutter plugin that provides unified streaming and video recording for **Android** and **iOS**.

### Protocol support

| Protocol | Android | iOS | Example URL |
|----------|---------|-----|-------------|
| RTMP | ✅ | ✅ | `rtmp://host/live/stream` |
| RTSP | ✅ | ❌ | `rtsp://host:8554/live` |
| SRT | ✅ | ✅ | `srt://host:10080?streamid=#!::r=live/livestream,m=publish` |
| UDP | ✅ | ❌ | `udp://host:5004` |
| WHIP | ✅ | ✅ (alpha) | `https://host/whip` |
| WHEP | ❌ | ✅ (alpha) | `https://host/whep` |

Pass an explicit `StreamingProtocol` (default `rtmp`). iOS WHIP/WHEP use `RTCHaishinKit` (H264/OPUS) and require Flutter SPM.

---

## ⚙️ Technical Foundation
- **Android**: Based on [`com.github.pedroSG94.RootEncoder:library:2.8.1`](https://github.com/pedroSG94/RootEncoder) (+ `extra-sources` for CameraX / UVC)  
- **iOS**: Based on [HaishinKit 2.2.5](https://github.com/HaishinKit/HaishinKit.swift) (includes `SRTHaishinKit`, `RTCHaishinKit` for WHIP/WHEP alpha)  
- **Android build**: AGP **9.4.1**, Gradle **9.8.1**, Kotlin **2.4.21**, compile SDK **37.2** / Build Tools **37.0.0** / NDK **30.0.16248370**

By leveraging these mature libraries, `rtmp_streaming` provides a consistent cross-platform API interface, reducing development complexity.

---

## ❓ Why This Plugin
- No suitable Flutter RTMP plugin exists on pub.dev.  
- Existing plugins suffer from:  
  - Long-term lack of maintenance.  
  - Outdated dependencies, incompatible with the latest Flutter and platform SDKs.  

Therefore, the goal of `rtmp_streaming` is to deliver a **modern, stable, and maintainable** RTMP streaming solution.

---

## 🛠️ Supported Methods

### 🌍 Common Methods (Android & iOS)
- 📷 Get available cameras: `availableCameras`  
- ⚙️ Initialize plugin: `initialize`  
- 🎬 Legacy preparation (deprecated): `prepareForVideoStreaming`
- 🎥 Start local video recording: `startVideoRecording`  
- ⏹️ Stop local video recording: `stopRecording`  
- 📡 Start recording and streaming: `startVideoRecordingAndStreaming`  
- ⏹️ Stop recording or streaming: `stopRecordingOrStreaming`  
- 📡 Start video streaming: `startVideoStreaming` (`url`, `protocol`, `bitrate`; WHIP optional `whipToken`)  
- ⏹️ Stop video streaming: `stopStreaming`  
- 🔄 Switch camera: `switchCamera`  
- 🔊 Mute encoded audio: `setAudioMuted`
- 🔇 Temporary mute while streaming: `getHasAudio` / `setHasAudio`  
- 🎥 Temporary video mute while streaming: `getHasVideo` / `setHasVideo`  
- 🎚️ Audio bitrate: `setAudioSettings`  
- 🎞️ Video encoder settings: `setVideoSettings`  
- 🎬 Frame rate: `setFrameRate`  
- 💡 Toggle flashlight: `switchFlashLight`  
- 📊 Stream statistics: `getStreamStatistics`  
- 🗑️ Dispose plugin: `dispose`  
- 📸 Snapshot while streaming: `takePicture`  
- 🖼️ Overlay text/image: `setOverlayText` / `setOverlayImage` / `clearOverlay`  
- 📡 Multi-streaming: `startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming` (no WHIP/WHEP)  

---

### 🍎 iOS Exclusive Methods
Since HaishinKit supports RTMP **playback** as well as publishing:

- ⏸️ Pause stream playback: `pauseVideoStreamPlay` (`pauseStream`)  
  > Note: pauses **playback**, not publishing.  
- ▶️ Resume stream playback: `resumeVideoStreamPlay` (`resumeStream`)  
- 📱 Multitasking camera: `setMultitaskingCameraAccessEnabled` (HaishinKit 2.2.5+, iOS 17+ when supported)  
- ⚙️ Session preset: `setSessionPreset`  
- 🖼️ Screen dimensions: `setScreenSettings`  
- 🎞️ `setVideoSettings` extras: `expectedFrameRate`, `bitRateMode` (2.2.1+ / 2.2.2+), `profileLevel`  

---

### 🤖 Android Exclusive Methods
- ⏸️ Pause recording: `pauseVideoRecording`  
- ▶️ Resume recording: `resumeVideoRecording`  
- 🎨 Apply filter: `setFilter` — see [CameraNativeView.kt](android/src/main/kotlin/com/app/rtmp_streaming/CameraNativeView.kt) for `type` values  
- ❌ Remove filter: `removeFilter`  
- 🎙️ Pitch shift: `setPitchShift` (RootEncoder `PitchShiftEffect`; `1.0` disables)  
- 🔒 Exposure lock: `lockExposure` / `unlockExposure` / `isExposureLocked` (after preview or streaming starts)  
- 🌡️ White balance lock: `lockWhiteBalance` / `unlockWhiteBalance` / `isWhiteBalanceLocked`  
- 👆 Tap to meter: `tapToMeter` (exposure or white balance)  
- 🎞️ Codecs: `setVideoCodec` / `setAudioCodec` (H264/H265/AV1/VP8/VP9; AAC/HE-AAC/OPUS/G711)  
- 🔇 AEC / NS: `setAudioProcessing`  
- 📷 Video source: `setVideoSource` (`camera2` / `cameraX` / `uvc` / `screen`)
  - Preserves front/back on stream start for `camera2` / `cameraX` (UVC/screen have no facing)
  - Idle preview defaults to CameraX; an explicit Camera2 selection is also used for idle preview. UVC/screen use a camera placeholder before streaming or recording.
  - Filters / mute / flashlight / AE·WB / pitch route to the active StreamBase or WHIP session when live
- 🖥️ Screen capture permission: `requestScreenCapture` (required before `VideoSourceType.screen`)
- 🎤 Custom PCM: `enableBufferAudio` / `feedPcmAudio` (single-destination StreamBase sessions)
- 🎨 BT.709 encoding: `setForceBt709Color` (RootEncoder 2.7.0+)  
- 📶 RTMP ping / RTT: `setRtmpShouldSendPings` (RootEncoder 2.7.0+, RTMP only)  
- 📊 Queue stats in `getStreamStatistics`: `queueBytesOut`, `bytesOutPerSecond`, `queueCongestionPercent`, `totalBytesOut`  

> **WHEP** remains Android-unsupported (RootEncoder is push-only; use iOS for WHEP).

---

## 📘 API Usage

### Recommended streaming flow (cross-platform)

```dart
final cameras = await availableCameras();
final controller = CameraController(
  ResolutionPreset.high,
  enableAudio: true,
);

await controller.initialize(cameras.first);

// Mount CameraPreview in the widget tree (Android needs AndroidView for the native camera)
// setState(() {}); // refresh UI in a StatefulWidget

// iOS: pre-attach audio to reduce start latency
await controller.prepareForVideoStreaming();

// Encoder settings after initialize, before go-live (Android caches if preview is not mounted yet)
await controller.setAudioSettings(128 * 1024); // bps
await controller.setVideoSettings(bitrate: 1500 * 1024);
await controller.setFrameRate(30);

if (Platform.isAndroid) {
  await controller.setForceBt709Color(true);
  await controller.setRtmpShouldSendPings(true);
}

if (Platform.isIOS) {
  await controller.setMultitaskingCameraAccessEnabled(true);
  await controller.setVideoSettings(
    expectedFrameRate: 30,
    bitRateMode: 'average',
  );
}

await controller.startVideoStreaming(
  'rtmp://your-server/live/stream-key',
  protocol: StreamingProtocol.rtmp,
);

// SRT (both platforms)
// await controller.startVideoStreaming(
//   'srt://your-server:10080?streamid=#!::r=live/livestream,m=publish',
//   protocol: StreamingProtocol.srt,
// );

// WHIP (Android + iOS alpha) / WHEP (iOS alpha)
// await controller.startVideoStreaming(
//   'https://your-server/whip',
//   protocol: StreamingProtocol.whip,
//   whipToken: 'optional-bearer-token',
// );
// await controller.startVideoStreaming(
//   'https://your-server/whep',
//   protocol: StreamingProtocol.whep,
// );

// Android RTSP / UDP
// await controller.startVideoStreaming(
//   'rtsp://your-server:8554/live',
//   protocol: StreamingProtocol.rtsp,
// );
```

---

### `prepareForVideoStreaming()`
- **Purpose**: Deprecated compatibility no-op: initialization already prepares capture.
- **When**: After `initialize`, before `startVideoStreaming`.

---

### Audio mute

Use `setAudioMuted(true)` or `setHasAudio(false)` to mute encoded audio while
keeping capture attached. `switchAudio` is deprecated and now has this same
behavior on both platforms. This is not a microphone privacy switch; initialize
with `enableAudio: false` for a video-only session.

---

### `getHasVideo` / `setHasVideo`
- **Purpose**: Temporarily stop or resume sending video while streaming.
- **Platform**: Android sends black frames via OpenGL; iOS uses mixer video mute.
- **When**: While streaming.

```dart
await controller.setHasVideo(false);
final hasVideo = await controller.getHasVideo();
await controller.setHasVideo(true);
```

---

### `setAudioSettings(int bitrate)`
- **Purpose**: AAC encoder bitrate in **bps**.
- **When**: After `initialize`, before starting stream/record.
- **Android**: The native camera view is created with `CameraPreview`. Calls before the preview mounts are cached and applied when the view appears. You still need `CameraPreview` before streaming.

```dart
await controller.setAudioSettings(128 * 1024);
await controller.startVideoStreaming(url);
```

---

### `setVideoSettings({ ... })`
- **Android**: `bitrate` is cached if the preview is not mounted yet, then applied on mount / next prepare; can hot-update while live.

| Parameter | Cross-platform | Notes |
|-----------|----------------|-------|
| `bitrate` | ✅ | Android can hot-update while live via `setVideoBitrateOnFly`. |
| `width` / `height` | ✅ | Positive even dimensions; Android applies them to the next encoding session. |
| `frameInterval` | ✅ | Positive keyframe interval in seconds; Android applies it on the next prepare. |
| `profileLevel` | iOS only | H.264 profile/level string. |
| `expectedFrameRate` | iOS only | RTMP onMetaData `framerate` (2.2.2+). |
| `bitRateMode` | iOS only | `average` / `constant` (iOS 16+) / `variable` (iOS 26+). |

```dart
await controller.setVideoSettings(bitrate: 1200 * 1024);
await controller.setVideoSettings(bitrate: 800 * 1024); // hot update on Android

await controller.setVideoSettings(
  expectedFrameRate: 30,
  bitRateMode: 'average',
  profileLevel: 'H264_Baseline_AutoLevel',
);
```

---

### `setFrameRate(int frameRate)`
- **Purpose**: Target capture/encode frame rate.
- **When**: After `initialize`, before streaming.
- **Android**: Same as `setAudioSettings` — values can be cached before the preview mounts.

```dart
await controller.setFrameRate(30);
await controller.startVideoStreaming(url);
```

---

### `getStreamStatistics()`
Returns `StreamStatistics` while streaming. Key fields:

| Field | Description |
|-------|-------------|
| `bitrate`, `fps`, `width`, `height` | Stream metrics |
| `cacheSize` | Send buffer size |
| `sentAudioFrames` / `sentVideoFrames` | Android |
| `droppedAudioFrames` / `droppedVideoFrames` | Android |
| `isAudioMuted` / `isVideoMuted` | Both platforms (1.0.8+) |
| `rttMicros` | Android RTT (requires `setRtmpShouldSendPings`) |
| `bytesSend` | Bytes sent |
| `queueBytesOut` / `bytesOutPerSecond` / `queueCongestionPercent` / `totalBytesOut` | Android queue / throughput (RootEncoder 2.8.1+) |

```dart
final stats = await controller.getStreamStatistics();
print('${stats.fps} fps, muted=${stats.isAudioMuted}');
```

---

### Android: `setForceBt709Color(bool enabled)`
- **Purpose**: Encode with the BT.709 color matrix.
- **When**: After `initialize`, before record/stream, including while idle preview is running. The value is cached and applied before the next encoder preparation; prepared preview encoders are not modified. Changing the value during streaming or recording fails without changing the cache; setting the same value again is safe.
```dart
await controller.setForceBt709Color(true);
await controller.startVideoStreaming(url);
```

---

### Android: `setPitchShift(double pitch)`
- **Purpose**: Mic PCM pitch shift (RootEncoder `PitchShiftEffect`).
- **Notes**: Native clamps `pitch` to `0.5…3.0`; pass `1.0` to disable.
```dart
await controller.setPitchShift(1.8);
await controller.setPitchShift(1.0); // disable
```

---

### Overlay: `setOverlayText` / `setOverlayImage` / `clearOverlay`
Works on Android and iOS. `fontSize` drives glyph size; `scale` is a % of natural size (`100` = 1:1).
```dart
await controller.setOverlayText(
  text: 'LIVE',
  fontSize: 28,
  colorArgb: 0xFFFF0000,
  position: OverlayPosition.topLeft,
);
await controller.setOverlayImage(
  filePath: '/path/to/logo.png',
  position: OverlayPosition.bottomRight,
);
await controller.clearOverlay();
```

---

### Multi-streaming: `startMultiStreaming`
**Android + iOS.** WHIP/WHEP are not allowed. Example app defaults to one RTMP + one SRT (`dest1` / `dest2`); use **Stop dest1 only** to drop one path.
```dart
await controller.startMultiStreaming([
  StreamDestination(
    url: 'rtmp://a/live/live',
    protocol: StreamingProtocol.rtmp,
    id: 'a',
  ),
  StreamDestination(
    url: 'srt://a:10080?streamid=#!::r=live/livestream,m=publish',
    protocol: StreamingProtocol.srt,
    id: 'b',
  ),
]);
await controller.stopStreamingDestination('a');
await controller.stopMultiStreaming();
```

---

### Android: `setVideoSource` / `enableBufferAudio`

- **`setVideoSource`**: `camera2`, `cameraX` (default), `uvc`, `screen`. Call `requestScreenCapture` before `screen`.
- **Facing**: On `startVideoStreaming`, `camera2` / `cameraX` re-apply the current front/back selection. UVC and screen have no lens facing. `switchCamera` while streaming UVC/screen returns an error.
- **Preview**: Idle preview defaults to CameraX. Camera2 uses its own selected source; UVC/screen return to a camera preview after streaming stops.
- **`enableBufferAudio(true)`**: Replaces microphone PCM in a single-destination session. For `enableAudio: false`, enable buffer audio before starting the stream. Multi streaming does not support buffer audio.

### Android: `lockExposure` / `unlockExposure` / `isExposureLocked`
- **Purpose**: Lock / unlock Camera2 auto-exposure (avoids flicker from faces or lighting changes).
- **When**: After preview or streaming has started.
```dart
final locked = await controller.lockExposure();
final isLocked = await controller.isExposureLocked();
await controller.unlockExposure();
```

---

### Android: `setRtmpShouldSendPings(bool enabled)`
- **Purpose**: Enable periodic RTMP pings to measure RTT.
- **When**: After `initialize`, before `startVideoStreaming`. Cached if `CameraPreview` is not mounted yet.
```dart
await controller.setRtmpShouldSendPings(true);
await controller.startVideoStreaming(url);
final stats = await controller.getStreamStatistics();
print(stats.rttMicros);
```

---

### iOS: `setMultitaskingCameraAccessEnabled(bool enabled)`
- **Purpose**: Keep camera capture in Split View / PiP (HaishinKit 2.2.5+).
- **Requires**: iOS 17+, and the device must support `isMultitaskingCameraAccessSupported`.
```dart
await controller.setMultitaskingCameraAccessEnabled(true);
await controller.startVideoStreaming(url);
```

---

## 🚀 Conclusion
`rtmp_streaming` provides cross-platform streaming and recording for Flutter.  
Since **1.0.8**, temporary audio/video mute, encoder settings, and frame rate APIs are aligned on both platforms; since **2.0.1**, Android can safely set encoder options before `CameraPreview` mounts (cached, then applied). Since **2.1.0**, Android multi-streaming / codecs / video sources ship with RootEncoder 2.8.1, and `CameraValue.isStreaming` replaces `isStreamingVideoRtmp`. **2.1.1** fixes Android front-camera reset on stream start and routes Android-only controls through CameraX / WHIP / StreamBase sessions. iOS retains playback and multitasking extras; Android retains filters, BT.709, RTT, and queue stats.


## Android 2.2 integration and verification

Requires Flutter **3.44+** / Dart **3.12+**. Development checks use Flutter 3.47.7 and Java 21. This release changes Android idle preview to CameraX and uses protocol-specific RootEncoder streams. Select Camera2 for exact camera IDs, AE/WB locks and manual capture controls; CameraX selection preserves front/back facing. Codec support also depends on the device encoder and server.

| Protocol | Video codecs | Audio codecs |
| --- | --- | --- |
| RTMP / RTSP | H264, H265, AV1, VP8, VP9 | AAC, HE-AAC, OPUS, G711 |
| SRT / UDP | H264, H265 | AAC, HE-AAC, OPUS |
| WHIP | RootEncoder-supported WebRTC codecs; server support required | OPUS (default), G711 |

An explicit incompatible codec is rejected. Stop streaming and recording before changing codecs. Prefer H264/AAC for broadly compatible MP4 recording; enumerating a codec does not guarantee recording/container support on every device. WHIP defaults to OPUS unless an audio codec was explicitly selected.

```dart
await controller.setRtmpMetadata({'application': 'my-app', 'session': 42});
final controls = await controller.getCameraControls();
await controller.setZoom(2.0.clamp(controls.minZoom, controls.maxZoom));
await controller.setAutoFocus(true);
await controller.tapToFocus(x: 0.5, y: 0.5);
// Call while streaming or recording:
await controller.requestKeyFrame();

// Camera2 extensions (after its preview is active):
await controller.setVideoSource(VideoSourceType.camera2);
await controller.setManualExposure(iso: 200, exposureTimeNanos: 10000000);
await controller.setCaptureTelemetry(true, intervalMs: 1000);
// controller.value.event: eventType == 'capture_statistics', captureStatistics map.
await controller.setManualExposure(); // restore automatic exposure
await controller.setCaptureTelemetry(false);
```

RTMP metadata accepts strings, booleans and finite numbers, and must be set before streaming. An empty map clears it. New session setup restores mute, filters, overlays and pitch; ISO/exposure must fit the selected Camera2 sensor. Queue adaptation uses the configured video+audio budget. Multi-destination retry/disconnect events carry `destinationId`; stopping one destination preserves the others, and statistics/ABR use the first active destination.

Custom PCM uses signed little-endian PCM16: stereo 32000 Hz for AAC/HE-AAC, stereo 48000 Hz for OPUS, mono 8000 Hz for G711. Supply complete frames while the buffer source is running. The latest RootEncoder IPv6, timestamp, queue and source fixes are inherited; choose an IPv6-capable endpoint/network when using IPv6.

Screen capture requires a mounted `CameraPreview`, foreground Activity and fresh `requestScreenCapture` consent before each session. The plugin owns a MediaProjection foreground service, with microphone service type when microphone capture is enabled. Stopping capture or disposing the preview releases it. Android 14+ authorization tokens are not reused: screen streams without an active recording stop on surface loss and require consent again. Multi streams require an explicit restart after surface loss. Physical-camera recordings are finalized on surface loss; camera streams can resume when the surface returns. This is not an unattended background-camera service.

The example declares and requests Android 17 `ACCESS_LOCAL_NETWORK`; host applications targeting Android 17+ must do the same when connecting to a LAN server. App-private recording does not require external-storage permission. RTMPS/RTSPS enable TLS hostname checks, so use a certificate matching the server hostname.

Validation commands:

```sh
flutter pub get
flutter analyze
flutter test
cd example && flutter test && flutter build apk --debug
cd android && ./gradlew :rtmp_streaming:testDebugUnitTest :rtmp_streaming:lintDebug :app:assembleDebug
```

Tests cover controller state/failure handling, snapshot overlap, event propagation, URL/codec validation and permission callbacks. Builds and lint do not establish camera output, audio/video synchronization, UVC hardware, background recovery or server interoperability. Before publishing an app, test front/back switching, preview → record → stream → stop, audio-disabled capture, screen consent/revocation, activity recreation and multi-destination failures on the target Android devices and servers. iOS compilation was not part of this Android verification.

Dependency sources: [RootEncoder releases](https://github.com/pedroSG94/RootEncoder/releases), [HaishinKit releases](https://github.com/HaishinKit/HaishinKit.swift/releases), [CocoaPods HaishinKit](https://cocoapods.org/pods/HaishinKit), [CocoaPods SRTHaishinKit](https://cocoapods.org/pods/SRTHaishinKit). SPM remains at HaishinKit 2.2.5; CocoaPods installation is unsupported: its final SDK releases lack the RTMP/RTC modules used here. Enable Flutter SPM.

## Cross-platform contract (2.3.0)

**iOS requires Swift Package Manager and Xcode with Swift 6.** Run
`flutter config --enable-swift-package-manager`, `flutter clean`, then
`flutter pub get`. Migrate old host Podfiles and Pods build phases; the example
uses SPM exclusively. HaishinKit is pinned to 2.2.5. CocoaPods fails with an
explicit migration message instead of selecting incompatible SDKs.

Query `await controller.getCapabilities()` after initialization and again after
switching a camera/source. `protocols` describes this native build, `videoCodecs`
and `audioCodecs` describe available backend encoders, and `features` describes
exposed operations (unknown keys are false). Codec/protocol combinations are
still validated when preparing the session; encoder availability does not
promise every combination or resolution works on a device.

| Capability | Android | iOS |
|---|---|---|
| RTMP / SRT publishing, recording, snapshots, overlays, mute | Yes | Yes |
| Zoom, autofocus, focus point, torch in preview | Camera2 / CameraX | Active capture device |
| Exposure / white balance lock | Camera2 | Device dependent |
| H264 / H265 | Hardware dependent | H265 requires iOS 17.4+ hardware query support; WHIP uses H264 |
| RTSP / UDP, UVC, screen capture | Yes (consent/device required) | Unsupported |
| Buffer PCM, AEC/NS, pitch, RTMP ping, GPU effects | Android APIs | Unsupported |
| Manual ISO/exposure and capture telemetry | Camera2/device dependent | Device dependent; telemetry reports ISO/exposure/lens position |
| Recording pause | Yes | Unsupported by StreamRecorder |
| WHIP Bearer header | Yes | Unsupported by HaishinKit 2.2.5; token rejected |
| Multitasking capture | Separate Android lifecycle | Device dependent, iOS 17+ |
| RTMP / WHEP playback | Unsupported | `PlayerController` / `PlayerPreview` |

`stopVideoStreaming` and `stopMultiStreaming` preserve an active recording.
`stopRecordingOrStreaming` stops both and is idempotent. Combined start rolls
back the network if recording fails. Multi-destination IDs default to `dest_0`,
`dest_1`, etc.; explicit IDs must be unique. Read `streamingDestinationIds` to
stop targets by ID. Target events use `destinationId`; statistics describe the
first surviving destination, never a fabricated aggregate. iOS disconnects are
reported as terminal events; application code can reconnect explicitly.

Statistics use pixels, bits/second, frames/second, bytes and microseconds.
`cacheSize` is sender capacity in **packets**, not buffered bytes. Unavailable
values are null. Numeric native values are converted safely. `bitrate` is the
configured encoder target, not a measured network rate. `queueBytesOut` is queued
bytes; transport bytes may include framing/retransmission, so comparisons across
protocols require care.

Use `setCapturePreset(ResolutionPreset...)` while idle to select capture quality;
`setVideoSettings` controls encoding. Set size, keyframe interval and frame rate
before starting; Android applies these on the next encoder preparation. iOS
persists settings across protocol creation and applies recorder compression
settings when recording starts. Existing recordings are not reconfigured. Recording requires average bitrate mode; other recording modes are rejected.
Android accepts positive integer `expectedFrameRate`; explicit rate modes or
profiles fail because these selectors are not exposed. iOS rate modes honor OS availability, including SRT.

Overlay font sizes and image dimensions use output pixels; scale is clamped to
10–400 percent and ARGB alpha is preserved. Adding/clearing overlays does not
change encoder dimensions. iOS snapshots use the preview's aspect-fill framing.
`setOverlayCanvas` replaces the misleading iOS `setScreenSettings` name; it
configures composition, not screen capture. Explicit canvas size survives
subsequent overlay updates.

Prefer `setVideoEffect(VideoEffect.sobel)` over integer filter IDs. Legacy filters
remain compatible; use parameterized overlays instead of demo text/image IDs.
Unknown IDs fail. `androidUseOpenGL` and `prepareForVideoStreaming` are deprecated
no-ops. Legacy playback methods reject unsupported operations instead of pausing
the publishing encoder.

Dispose the camera before initializing `PlayerController` (one native session).
RTMP playback supports remote pause/resume; WHEP supports stop/reconnect and mute.
Publishing and playback keep separate Dart states. Hardware capture, server
interoperability, interruption recovery and media quality need real-device tests.

Playback example: `cd example && flutter run -t lib/playback.dart` (iOS).

Validation: 24 Dart contract/state tests, 15 Android native tests, Android lint
and APK assembly pass. The iOS app and three XCTest cases compile and link for
arm64 simulator. XCTest execution is blocked on this machine by Xcode 27.1's
`invalidDigitCount` simulator/SDK version parsing error; no live-server or
physical-device result is claimed.
