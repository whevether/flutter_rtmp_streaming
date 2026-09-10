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
- **Android build**: AGP **9.4.0**, Gradle **9.7.1**, Kotlin DSL 

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
- 🎬 Prepare for streaming (optional, recommended on iOS): `prepareForVideoStreaming`  
- 🎥 Start local video recording: `startVideoRecording`  
- ⏹️ Stop local video recording: `stopRecording`  
- 📡 Start recording and streaming: `startVideoRecordingAndStreaming`  
- ⏹️ Stop recording or streaming: `stopRecordingOrStreaming`  
- 📡 Start video streaming: `startVideoStreaming` (`url`, `protocol`, `bitrate`; WHIP optional `whipToken`)  
- ⏹️ Stop video streaming: `stopStreaming`  
- 🔄 Switch camera: `switchCamera`  
- 🔊 Toggle mic capture on/off: `switchAudio`  
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
- 🖥️ Screen capture permission: `requestScreenCapture` (required before `VideoSourceType.screen`)  
- 🎤 Custom PCM: `enableBufferAudio` / `feedPcmAudio`  
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
- **Purpose**: Pre-warm the capture session for streaming. On iOS, attaches audio early; on Android, no-op (safe to call for shared code).
- **When**: After `initialize`, before `startVideoStreaming`.

---

### `switchAudio` vs `setHasAudio`

| Method | Behavior | Use case |
|--------|----------|----------|
| `switchAudio(false)` | Detach / re-attach mic capture | Fully stop mic input |
| `setHasAudio(false)` | **Temporary mute** while still capturing | Quick mute without teardown |

```dart
await controller.setHasAudio(false);
final sending = await controller.getHasAudio(); // false

await controller.switchAudio(false);
```

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
| `width` / `height` | Partial | Prefer before go-live. |
| `frameInterval` | Mostly iOS | Keyframe interval (seconds). |
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
- **When**: After `initialize`, before record/stream. Cached if `CameraPreview` is not mounted yet.
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
Since **1.0.8**, temporary audio/video mute, encoder settings, and frame rate APIs are aligned on both platforms; since **2.0.1**, Android can safely set encoder options before `CameraPreview` mounts (cached, then applied). Since **2.1.0**, Android multi-streaming / codecs / video sources ship with RootEncoder 2.8.1, and `CameraValue.isStreaming` replaces `isStreamingVideoRtmp`. iOS retains playback and multitasking extras; Android retains filters, BT.709, RTT, and queue stats.
