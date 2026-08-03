# rtmp_streaming

## 📖 Overview
`rtmp_streaming` is a Flutter plugin that provides unified streaming and video recording for **Android** and **iOS**.

### Protocol support

| Protocol | Android | iOS | Example URL |
|----------|---------|-----|-------------|
| RTMP | ✅ | ✅ | `rtmp://host/live/stream` |
| RTSP | ✅ | ❌ | `rtsp://host:8554/live` |
| SRT | ✅ | ✅ | `srt://host:9000` |
| UDP | ✅ | ❌ | `udp://host:5004` |
| WHIP | ✅ | ✅ (alpha) | `https://host/whip` |
| WHEP | ❌ | ✅ (alpha) | `https://host/whep` |

Pass an explicit `StreamingProtocol` (default `rtmp`). iOS WHIP/WHEP use `RTCHaishinKit` (H264/OPUS) and require Flutter SPM.

---

## ⚙️ Technical Foundation
- **Android**: Based on [`com.github.pedroSG94.RootEncoder:library:2.8.0`](https://github.com/pedroSG94/RootEncoder)  
- **iOS**: Based on [HaishinKit 2.2.5](https://github.com/HaishinKit/HaishinKit.swift) (includes `SRTHaishinKit`, `RTCHaishinKit` for WHIP/WHEP alpha)  

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
- 🖼️ Overlay text/image: `setOverlayText` / `setOverlayImage` / `clearOverlay` (iOS + Android)  
- 📡 Multi-streaming: `startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming` (no WHIP/WHEP; Android MultiStream experimental)  
- 🖥️ Screen streaming: `startScreenStreaming` / `stopScreenStreaming` (Android); iOS via Broadcast Extension + `prepareScreenBroadcastConfig`  
- 🎙️ Pitch shift: `setPitchShift` (RootEncoder `PitchShiftEffect`; `1.0` disables)  
- 🔒 Exposure lock: `lockExposure` / `unlockExposure` / `isExposureLocked` (after preview or streaming starts)  
- 🎨 BT.709 encoding: `setForceBt709Color` (RootEncoder 2.7.0+)  
- 📶 RTMP ping / RTT: `setRtmpShouldSendPings` (RootEncoder 2.7.0+, RTMP only)  

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

// iOS: pre-attach audio to reduce start latency
await controller.prepareForVideoStreaming();

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
//   'srt://your-server:9000',
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

```dart
await controller.setAudioSettings(128 * 1024);
await controller.startVideoStreaming(url);
```

---

### `setVideoSettings({ ... })`

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
);
```

---

### `setFrameRate(int frameRate)`
- **Purpose**: Target capture/encode frame rate.
- **When**: After `initialize`, before streaming.

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

```dart
final stats = await controller.getStreamStatistics();
```

---

### Android: `setForceBt709Color(bool enabled)`
```dart
await controller.setForceBt709Color(true);
await controller.startVideoStreaming(url);
```

---

### Android: `setPitchShift(double pitch)`
```dart
// Raise pitch (chipmunk). Pass 1.0 to disable.
await controller.setPitchShift(1.8);
```

---

### Overlay: `setOverlayText` / `setOverlayImage` / `clearOverlay`
Works on Android and iOS.
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
WHIP/WHEP are not allowed. Android uses experimental RootEncoder `MultiStream`.
```dart
await controller.startMultiStreaming([
  StreamDestination(url: 'rtmp://a/live/1', protocol: StreamingProtocol.rtmp, id: 'a'),
  StreamDestination(url: 'srt://b:9000', protocol: StreamingProtocol.srt, id: 'b'),
]);
await controller.stopStreamingDestination('a');
await controller.stopMultiStreaming();
```

---

### Screen streaming
**Android**
```dart
await controller.startScreenStreaming(url, protocol: StreamingProtocol.rtmp);
await controller.stopScreenStreaming();
```
**iOS**: use Broadcast Upload Extension — see [example/ios/BroadcastUploadExtension/README.md](example/ios/BroadcastUploadExtension/README.md).
```dart
await controller.prepareScreenBroadcastConfig(url: url);
// Then start Live Broadcast from Control Center.
```

---

### Android: `lockExposure` / `unlockExposure` / `isExposureLocked`
Call after preview or streaming has started.
```dart
final locked = await controller.lockExposure();
final isLocked = await controller.isExposureLocked();
await controller.unlockExposure();
```

---

### Android: `setRtmpShouldSendPings(bool enabled)`
```dart
await controller.setRtmpShouldSendPings(true);
await controller.startVideoStreaming(url);
final stats = await controller.getStreamStatistics();
print(stats.rttMicros);
```

---

### iOS: `setMultitaskingCameraAccessEnabled(bool enabled)`
```dart
await controller.setMultitaskingCameraAccessEnabled(true);
await controller.startVideoStreaming(url);
```

---

## 🚀 Conclusion
`rtmp_streaming` provides cross-platform RTMP streaming and recording for Flutter.  
Since **1.0.8**, temporary audio/video mute, encoder settings, and frame rate APIs are aligned on both platforms; iOS retains playback and multitasking extras, Android retains filters, BT.709, and RTT.
