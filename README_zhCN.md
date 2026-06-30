# rtmp_streaming

## 📖 概述
`rtmp_streaming` 是一个 Flutter 插件，旨在为 **Android** 和 **iOS** 提供统一的 RTMP 推流与视频录制能力。  
它解决了 pub.dev 上缺乏合适 Flutter RTMP 插件的问题：现有插件要么长期无人维护，要么依赖包过时，无法满足现代移动应用的需求。

---

## ⚙️ 技术基础
- **Android**：基于 [`com.github.pedroSG94.RootEncoder:library:2.7.5`](https://github.com/pedroSG94/RootEncoder)  
- **iOS**：基于 [HaishinKit 2.2.5](https://github.com/HaishinKit/HaishinKit.swift)  

通过这两个成熟的底层库，`rtmp_streaming` 提供了跨平台一致的 API 接口，简化了开发者的使用成本。

---

## ❓ 为什么要做这个插件
- pub.dev 上没有合适的 Flutter RTMP 插件。  
- 现有插件存在以下问题：  
  - 长期无人维护。  
  - 依赖包过时，无法兼容最新的 Flutter 与平台 SDK。  

因此，`rtmp_streaming` 的目标是提供一个 **现代、稳定、可维护** 的 RTMP 推流解决方案。

---

## 🛠️ 支持的方法

### 🌍 Android 与 iOS 通用方法
- 📷 获取可用摄像头：`availableCameras`  
- ⚙️ 初始化插件：`initialize`  
- 🎬 预准备推流（可选，iOS 建议）：`prepareForVideoStreaming`  
- 🎥 开始本地视频录制：`startVideoRecording`  
- ⏹️ 停止本地视频录制：`stopRecording`  
- 📡 开始录制并推送直播流：`startVideoRecordingAndStreaming`  
- ⏹️ 停止录制或推送直播流：`stopRecordingOrStreaming`  
- 📡 开始推送直播流：`startVideoStreaming`  
- ⏹️ 停止推送直播流：`stopStreaming`  
- 🔄 切换摄像头：`switchCamera`  
- 🔊 切换麦克风采集开/关：`switchAudio`  
- 🔇 推流时临时静音/恢复：`getHasAudio` / `setHasAudio`  
- 🎥 推流时临时停发视频/恢复：`getHasVideo` / `setHasVideo`  
- 🎚️ 音频码率设置：`setAudioSettings`  
- 🎞️ 视频编码设置：`setVideoSettings`  
- 🎬 设置帧率：`setFrameRate`  
- 💡 切换开启/关闭闪光灯：`switchFlashLight`  
- 📊 获取流信息：`getStreamStatistics`  
- 🗑️ 销毁插件：`dispose`  
- 📸 直播时截图：`takePicture`  

---

### 🍎 iOS 平台独有方法
由于 HaishinKit 不仅支持推流，还支持 **RTMP 播放**，因此 iOS 平台提供了额外的功能：

- ⏸️ 暂停直播流播放：`pauseVideoStreamPlay`（`pauseStream`）  
  > 注意：这是暂停 **播放** RTMP 流，不是暂停推流。  
- ▶️ 恢复直播流播放：`resumeVideoStreamPlay`（`resumeStream`）  
- 📱 多任务相机：`setMultitaskingCameraAccessEnabled`（HaishinKit 2.2.5+，iOS 17+ 且设备支持时）  
- ⚙️ 设置直播预设配置：`setSessionPreset`  
- 🖼️ 设置直播屏幕宽高：`setScreenSettings`  
- 🎞️ `setVideoSettings` 扩展参数：`expectedFrameRate`、`bitRateMode`（HaishinKit 2.2.1+ / 2.2.2+）、`profileLevel`  

---

### 🤖 Android 平台独有方法
- ⏸️ 暂停录制：`pauseVideoRecording`  
- ▶️ 恢复录制：`resumeVideoRecording`  
- 🎨 设置滤镜：`setFilter`  
  > 滤镜 `type` 值请查看源码 [CameraNativeView.kt](android/src/main/kotlin/com/app/rtmp_streaminging/CameraNativeView.kt)  
- ❌ 移除滤镜：`removeFilter`  
- 🎨 BT.709 编码：`setForceBt709Color`（RootEncoder 2.7.0+）  
- 📶 RTMP Ping / RTT：`setRtmpShouldSendPings`（RootEncoder 2.7.0+）  

---

## 📘 API 使用说明

### 推荐推流流程（跨平台）

```dart
final cameras = await availableCameras();
final controller = CameraController(
  ResolutionPreset.high,
  enableAudio: true,
);

await controller.initialize(cameras.first);

// iOS 建议：提前准备音频，减少开播时预览卡顿
await controller.prepareForVideoStreaming();

// 编码参数（开播前设置）
await controller.setAudioSettings(128 * 1024); // bps
await controller.setVideoSettings(bitrate: 1500 * 1024);
await controller.setFrameRate(30);

// Android 可选
if (Platform.isAndroid) {
  await controller.setForceBt709Color(true);
  await controller.setRtmpShouldSendPings(true);
}

// iOS 可选：分屏/画中画保持采集
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
- **作用**：为推流预准备采集会话。iOS 会提前 attach 音频，减少 `startVideoStreaming` 时的延迟；Android 为 no-op，可直接调用以保持代码一致。
- **调用时机**：`initialize` 之后、`startVideoStreaming` 之前。

---

### `switchAudio` 与 `setHasAudio` 的区别

| 方法 | 行为 | 典型场景 |
|------|------|----------|
| `switchAudio(false)` | 关闭/开启麦克风**采集**（detach/attach） | 彻底停麦 |
| `setHasAudio(false)` | **临时静音**，仍采集但不送入推流 | 短暂静音、可快速恢复 |

```dart
// 临时静音（双端）
await controller.setHasAudio(false);
final sending = await controller.getHasAudio(); // false

// 关闭麦克风采集（双端）
await controller.switchAudio(false);
```

---

### `getHasVideo` / `setHasVideo`
- **作用**：推流过程中临时停止或恢复发送视频。
- **平台差异**：Android 通过 OpenGL 发送黑帧；iOS 通过混音器静音视频轨。
- **调用时机**：推流进行中。

```dart
await controller.setHasVideo(false); // 停发视频
final hasVideo = await controller.getHasVideo(); // false
await controller.setHasVideo(true);  // 恢复
```

---

### `setAudioSettings(int bitrate)`
- **作用**：设置 AAC 音频编码码率（单位：**bps**）。
- **调用时机**：`initialize` 之后、开始推流/录制**之前**（下次编码准备时生效）。
- **示例**：
```dart
await controller.setAudioSettings(128 * 1024);
await controller.startVideoStreaming(url);
```

---

### `setVideoSettings({ ... })`
| 参数 | 双端 | 说明 |
|------|------|------|
| `bitrate` | ✅ | 视频码率（bps）。Android 推流中可热更新。 |
| `width` / `height` | 部分 | 宜在开播前设置；直播中修改受原生库限制。 |
| `frameInterval` | iOS 为主 | 关键帧间隔（秒）。 |
| `profileLevel` | 仅 iOS | H.264 Profile/Level 字符串。 |
| `expectedFrameRate` | 仅 iOS | 期望帧率；写入 RTMP onMetaData `framerate`（2.2.2+）。 |
| `bitRateMode` | 仅 iOS | `"average"` / `"constant"`（iOS 16+）/ `"variable"`（iOS 26+）。 |

```dart
// 跨平台：码率
await controller.setVideoSettings(bitrate: 1200 * 1024);

// 推流中热更新码率（Android 生效；iOS 遵循 HaishinKit 热更新限制）
await controller.setVideoSettings(bitrate: 800 * 1024);

// iOS 扩展
await controller.setVideoSettings(
  expectedFrameRate: 30,
  bitRateMode: 'average',
  profileLevel: 'H264_Baseline_AutoLevel',
);
```

---

### `setFrameRate(int frameRate)`
- **作用**：设置采集/编码目标帧率。
- **调用时机**：`initialize` 之后、开始推流之前。
- **示例**：
```dart
await controller.setFrameRate(30);
await controller.startVideoStreaming(url);
```

---

### `getStreamStatistics()`
推流过程中获取统计信息。`StreamStatistics` 主要字段：

| 字段 | 说明 |
|------|------|
| `bitrate` | 当前视频码率 |
| `fps` | 当前帧率 |
| `width` / `height` | 流分辨率 |
| `cacheSize` | 发送缓存大小 |
| `sentAudioFrames` / `sentVideoFrames` | 已发送帧数（Android） |
| `droppedAudioFrames` / `droppedVideoFrames` | 丢弃帧数（Android） |
| `isAudioMuted` / `isVideoMuted` | 是否静音（双端，1.0.7+） |
| `rttMicros` | RTMP 往返时延（Android，需 `setRtmpShouldSendPings`） |
| `bytesSend` | 已发送字节数 |

```dart
final stats = await controller.getStreamStatistics();
print('${stats.fps} fps, muted=${stats.isAudioMuted}');
```

---

### Android：`setForceBt709Color(bool enabled)`
- **作用**：编码使用 BT.709 色彩矩阵。
- **调用时机**：`initialize` 之后，开始录制或推流之前。
```dart
await controller.setForceBt709Color(true);
await controller.startVideoStreaming(url);
```

---

### Android：`setRtmpShouldSendPings(bool enabled)`
- **作用**：开启 RTMP 周期 ping，用于测量 RTT。
- **调用时机**：`initialize` 之后、`startVideoStreaming` **之前**。
```dart
await controller.setRtmpShouldSendPings(true);
await controller.startVideoStreaming(url);
final stats = await controller.getStreamStatistics();
print(stats.rttMicros);
```

---

### iOS：`setMultitaskingCameraAccessEnabled(bool enabled)`
- **作用**：分屏、画中画等场景下保持相机采集（HaishinKit 2.2.5+）。
- **要求**：iOS 17+，且设备支持 `isMultitaskingCameraAccessSupported`。
```dart
await controller.setMultitaskingCameraAccessEnabled(true);
await controller.startVideoStreaming(url);
```

---

## 🚀 总结
`rtmp_streaming` 为 Flutter 开发者提供跨平台、现代化的 RTMP 推流与视频录制能力。  
自 **1.0.7** 起，音视频临时静音、编码参数设置、帧率配置等 API 已在双端对齐；iOS 仍保留播放控制与多任务相机等扩展能力，Android 保留滤镜、BT.709、RTT 等扩展能力。
