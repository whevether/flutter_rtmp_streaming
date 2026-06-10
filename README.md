# rtmp_streaming

## 📖 Overview
`rtmp_streaming` is a Flutter plugin designed to provide unified RTMP streaming and video recording capabilities for **Android** and **iOS**.  
It addresses the lack of suitable Flutter RTMP plugins on pub.dev: existing plugins are either no longer maintained or rely on outdated dependencies, making them unsuitable for modern mobile applications.

---

## ⚙️ Technical Foundation
- **Android**: Based on [`com.github.pedroSG94.RootEncoder:library:2.7.1`](https://github.com/pedroSG94/RootEncoder)  
- **iOS**: Based on [HaishinKit 2.2.5](https://github.com/shogo4405/HaishinKit.swift)  

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
- 🎥 Start local video recording: `startVideoRecording`  
- ⏹️ Stop local video recording: `stopRecording`  
- 📡 Start recording and streaming: `startVideoRecordingAndStreaming`  
- ⏹️ Stop recording or streaming: `stopRecordingOrStreaming`  
- 📡 Start video streaming: `startVideoStreaming`  
- ⏹️ Stop video streaming: `stopStreaming`  
- 🔄 Switch camera: `switchCamera`  
- 🔊 Toggle audio on/off: `switchAudio`  
- 💡 Toggle flashlight on/off: `switchFlashLight`  
- 📊 Get stream statistics: `getStreamStatistics`  
- 🗑️ Dispose plugin: `dispose`  
- 📸 Take snapshot during streaming: `takePicture`  

---

### 🍎 iOS Exclusive Methods
Since HaishinKit supports not only streaming but also **RTMP playback**, iOS provides additional features:

- ⏸️ Pause stream playback: `pauseStream`  
  > Note: This pauses playback, not streaming.  
- ▶️ Resume stream playback: `resumeStream`  
  > Note: This resumes playback, not streaming.  
- 🎚️ Set audio bitrate: `setAudioSettings`  
- 🎞️ Set video settings: `setVideoSettings` (optional `expectedFrameRate`, `bitRateMode` — HaishinKit 2.2.1+ / 2.2.2+)  
- 📱 Multitasking camera access: `setMultitaskingCameraAccessEnabled` (HaishinKit 2.2.5+, iOS 17+ when supported)  
- 🔊 Get temporary mute status: `getHasAudio`  
- 🔊 Set temporary mute: `setHasAudio`  
- 🎥 Get temporary video stop status: `getHasVideo`  
- 🎥 Set temporary video stop: `setHasVideo`  
- 🎬 Set streaming frame rate: `setFrameRate`  
- ⚙️ Set session preset: `setSessionPreset`  
- 🖼️ Set screen dimensions: `setScreenSettings`  

---

### 🤖 Android Exclusive Methods
Android provides additional features during live streaming:

- ⏸️ Pause recording: `pauseVideoRecording`  
- ▶️ Resume recording: `resumeVideoRecording`  
- 🎨 Apply filter: `setFilter`  
  > Filter `type` values correspond to filters defined in source code:  
  > [CameraNativeView.kt](https://github.com/whevether/flutter_rtmp_broadcaster/blob/main/android/src/main/kotlin/com/app/rtmp_streaming/CameraNativeView.kt)  
- ❌ Remove filter: `removeFilter`  
- 🎨 BT.709 encoding hint: `setForceBt709Color` (RootEncoder 2.7.0+)  
- 📶 RTMP ping / RTT: `setRtmpShouldSendPings` (RootEncoder 2.7.0+)  

---

## 📘 Extended API usage (platform-specific)

### Android: `setForceBt709Color(bool enabled)`
- **What it does**: Tells the video encoder to use a BT.709 color matrix for encoded video, which can align colors with players or servers that expect BT.709 for HD content.
- **When to call**: After `initialize`, before starting recording or streaming (or before the next `prepare` path). The plugin applies the flag when preparing video for record/stream.
- **Example**:
```dart
await controller.setForceBt709Color(true);
await controller.startVideoStreaming(url);
```

### Android: `setRtmpShouldSendPings(bool enabled)`
- **What it does**: Enables RTMP ping commands so the server can respond with pong; the client can derive round-trip time (RTT).
- **When to call**: After `initialize`, **before** `startVideoStreaming` (or combined record+stream). Must be set before connect.
- **Related**: Use `getStreamStatistics()` while streaming; when pings are enabled and the server supports them, the map includes `rttMicros` (microseconds) and `bytesSend` (where supported).
- **Example**:
```dart
await controller.setRtmpShouldSendPings(true);
await controller.startVideoStreaming(url);
// later, while streaming:
final stats = await controller.getStreamStatistics();
// stats.rttMicros, stats.bytesSend, ...
```

### iOS: `setVideoSettings({ ... })`
Existing parameters: `bitrate`, `width`, `height`, `frameInterval`, `profileLevel` (iOS only).

**HaishinKit 2.2.1+ / 2.2.2+ extensions** (optional named parameters):

| Parameter | Type | Meaning |
|-----------|------|---------|
| `expectedFrameRate` | `double?` | Encoder hint; also appears in RTMP **onMetaData** as `framerate` (2.2.2+). |
| `bitRateMode` | `String?` | `"average"` (default behavior), `"constant"` (iOS 16+), `"variable"` (iOS 26+ / VideoToolbox VBR). |

- **When to call**: After `initialize`, typically before or early during streaming; follow HaishinKit guidance for changing settings while live.
- **Example**:
```dart
await controller.setVideoSettings(
  expectedFrameRate: 30,
  bitRateMode: 'average',
);
```

### iOS: `setMultitaskingCameraAccessEnabled(bool enabled)`
- **What it does**: When supported, sets `AVCaptureSession.isMultitaskingCameraAccessEnabled` so capture can continue in multitasking / split-screen / PiP-style scenarios (HaishinKit 2.2.5+).
- **Requirements**: **iOS 17+** for the underlying configuration API; device must report `isMultitaskingCameraAccessSupported`.
- **When to call**: After `initialize`, before starting streaming (same session as preview).
- **Example**:
```dart
await controller.setMultitaskingCameraAccessEnabled(true);
await controller.startVideoStreaming(url);
```

---

## 🚀 Conclusion
`rtmp_streaming` provides Flutter developers with a cross-platform, modern RTMP streaming and video recording plugin, addressing the shortcomings of the current ecosystem.  
It is built on Android’s RootEncoder and iOS’s HaishinKit, offering a unified API while extending playback and audio/video controls on iOS, and snapshot and filter features on Android—helping developers quickly build live streaming and recording applications.
