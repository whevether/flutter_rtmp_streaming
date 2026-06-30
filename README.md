# rtmp_streaming

## 📖 Overview
`rtmp_streaming` is a Flutter plugin designed to provide unified RTMP streaming and video recording capabilities for **Android** and **iOS**.  
It addresses the lack of suitable Flutter RTMP plugins on pub.dev: existing plugins are either no longer maintained or rely on outdated dependencies, making them unsuitable for modern mobile applications.

---

## ⚙️ Technical Foundation
- **Android**: Based on [`com.github.pedroSG94.RootEncoder:library:2.7.5`](https://github.com/pedroSG94/RootEncoder)  
- **iOS**: Based on [HaishinKit 2.2.5](https://github.com/HaishinKit/HaishinKit.swift)  

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
- 📡 Start video streaming: `startVideoStreaming`  
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
- 🎨 BT.709 encoding: `setForceBt709Color` (RootEncoder 2.7.0+)  
- 📶 RTMP ping / RTT: `setRtmpShouldSendPings` (RootEncoder 2.7.0+)  

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

await controller.startVideoStreaming('rtmp://your-server/live/stream-key');
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
| `isAudioMuted` / `isVideoMuted` | Both platforms (1.0.7+) |
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
Since **1.0.7**, temporary audio/video mute, encoder settings, and frame rate APIs are aligned on both platforms; iOS retains playback and multitasking extras, Android retains filters, BT.709, and RTT.
