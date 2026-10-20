# rtmp_streaming

预览尺寸统一表示**最终显示**的像素宽高，`controller.value.aspectRatio` 为宽÷高。旋转或修改采集预设后，应监听控制器并重建布局。双端原生层已处理摄像头方向（`previewQuarterTurns` 通常为 0），不要再次手工交换 `previewSize` 的宽高或重复旋转。显式编码尺寸会保留；正在进行的输出保持编码尺寸固定，停止后重启才选择新的尺寸。启动、停止、销毁操作串行执行：重复启动返回 `operationInProgress`，停止/销毁会等待已发出的原生启动操作及清理完成。

使用 Xcode 27 构建的宿主 App 须迁移到 UIScene 生命周期，参见 [Flutter 官方迁移说明](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)。示例已通过 `didInitializeImplicitFlutterEngine` 注册插件并使用 `FlutterSceneDelegate`。

## 📖 概述
`rtmp_streaming` 是一个 Flutter 插件，为 **Android** 和 **iOS** 提供统一的推流与视频录制能力。  
它解决了 pub.dev 上缺乏合适 Flutter 推流插件的问题：现有插件要么长期无人维护，要么依赖包过时，无法满足现代移动应用的需求。

### 协议支持

| 协议 | Android | iOS | URL 示例 |
|------|---------|-----|----------|
| RTMP | ✅ | ✅ | `rtmp://host/live/stream` |
| RTSP | ✅ | ❌ | `rtsp://host:8554/live` |
| SRT | ✅ | ✅ | `srt://host:10080?streamid=#!::r=live/livestream,m=publish` |
| UDP | ✅ | ❌ | `udp://host:5004` |
| WHIP | ✅ | ✅ (alpha) | `https://host/whip` |
| WHEP | ❌ | ✅ (alpha) | `https://host/whep` |

通过 `StreamingProtocol` 显式指定协议（默认 `rtmp`）。iOS 的 WHIP/WHEP 基于 `RTCHaishinKit`（H264/OPUS），需启用 Flutter SPM。

---

## ⚙️ 技术基础
- **Android**：基于 [`com.github.pedroSG94.RootEncoder:library:2.8.1`](https://github.com/pedroSG94/RootEncoder)（含 `extra-sources`：CameraX / UVC）  
- **iOS**：基于 [HaishinKit 2.2.5](https://github.com/HaishinKit/HaishinKit.swift)（含 `SRTHaishinKit`，以及用于 WHIP/WHEP alpha 的 `RTCHaishinKit`）  
- **Android 构建**：AGP **9.4.1**、Gradle **9.8.1**、Kotlin DSL

通过这两个成熟的底层库，`rtmp_streaming` 提供了跨平台一致的 API 接口，简化了开发者的使用成本。

---

## ❓ 为什么要做这个插件
- pub.dev 上没有合适的 Flutter RTMP 插件。  
- 现有插件存在以下问题：  
  - 长期无人维护。  
  - 依赖包过时，无法兼容最新的 Flutter 与平台 SDK。  

因此，`rtmp_streaming` 的目标是提供一个 **现代、稳定、可维护** 的推流解决方案。

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
- 📡 开始推送直播流：`startVideoStreaming`（参数：`url`、`protocol`、`bitrate`；WHIP 可选 `whipToken`）  
- ⏹️ 停止推送直播流：`stopStreaming`  
- 🔄 切换摄像头：`switchCamera`  
- 🔊 编码音频静音：`setAudioMuted`
- 🔇 推流时临时静音/恢复：`getHasAudio` / `setHasAudio`  
- 🎥 推流时临时停发视频/恢复：`getHasVideo` / `setHasVideo`  
- 🎚️ 音频码率设置：`setAudioSettings`  
- 🎞️ 视频编码设置：`setVideoSettings`  
- 🎬 设置帧率：`setFrameRate`  
- 💡 切换开启/关闭闪光灯：`switchFlashLight`  
- 📊 获取流信息：`getStreamStatistics`  
- 🗑️ 销毁插件：`dispose`  
- 📸 直播时截图：`takePicture`  
- 🖼️ 叠字/水印：`setOverlayText` / `setOverlayImage` / `clearOverlay`  
- 📡 多路推流：`startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming`（不含 WHIP/WHEP）  

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
  > 滤镜 `type` 值请查看源码 [CameraNativeView.kt](android/src/main/kotlin/com/app/rtmp_streaming/CameraNativeView.kt)  
- ❌ 移除滤镜：`removeFilter`  
- 🎙️ 变调：`setPitchShift`（RootEncoder `PitchShiftEffect`；传 `1.0` 关闭）  
- 🔒 曝光锁定：`lockExposure` / `unlockExposure` / `isExposureLocked`（须在预览或推流启动后）  
- 🌡️ 白平衡锁定：`lockWhiteBalance` / `unlockWhiteBalance` / `isWhiteBalanceLocked`  
- 👆 点击测光：`tapToMeter`（曝光或白平衡）  
- 🎞️ 编解码器：`setVideoCodec` / `setAudioCodec`（H264/H265/AV1/VP8/VP9；AAC/HE-AAC/OPUS/G711）  
- 🔇 回声消除 / 降噪：`setAudioProcessing`  
- 📷 视频源：`setVideoSource`（`camera2` / `cameraX` / `uvc` / `screen`）
  - `camera2` / `cameraX` 开流时保持当前前后置（UVC/screen 无镜头朝向）
  - 默认空闲预览为 CameraX；显式选择 Camera2 时预览也使用 Camera2。UVC/screen 在采集前使用相机占位预览。
  - 推流中滤镜 / 静音 / 闪光灯 / 曝光·白平衡 / 变调会接到当前 StreamBase 或 WHIP 会话
- 🖥️ 屏幕采集授权：`requestScreenCapture`（`VideoSourceType.screen` 前必调）
- 🎤 自定义 PCM：`enableBufferAudio` / `feedPcmAudio`（单路 StreamBase 会话）
- 🎨 BT.709 编码：`setForceBt709Color`（RootEncoder 2.7.0+）  
- 📶 RTMP Ping / RTT：`setRtmpShouldSendPings`（RootEncoder 2.7.0+，仅 RTMP）  
- 📊 队列统计：`getStreamStatistics` 的 `queueBytesOut`、`bytesOutPerSecond`、`queueCongestionPercent`、`totalBytesOut`  

> **WHEP** 在 Android 仍不支持（RootEncoder 仅推流；WHEP 请用 iOS）。  

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

// 界面需挂载 CameraPreview（Android 依赖 AndroidView 创建原生相机）
// setState(() {}); // 若在 StatefulWidget 中请刷新 UI

// iOS 建议：提前准备音频，减少开播时预览卡顿
await controller.prepareForVideoStreaming();

// 编码参数（initialize 之后、开播前；Android 在预览未挂载时也会先缓存）
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

await controller.startVideoStreaming(
  'rtmp://your-server/live/stream-key',
  protocol: StreamingProtocol.rtmp,
);

// SRT 示例（双端）
// await controller.startVideoStreaming(
//   'srt://your-server:10080?streamid=#!::r=live/livestream,m=publish',
//   protocol: StreamingProtocol.srt,
// );

// WHIP（Android + iOS alpha）/ WHEP（仅 iOS alpha）
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
- **作用**：为推流预准备采集会话。iOS 会提前 attach 音频，减少 `startVideoStreaming` 时的延迟；Android 为 no-op，可直接调用以保持代码一致。
- **调用时机**：`initialize` 之后、`startVideoStreaming` 之前。

---

### 音频静音

统一使用 `setAudioMuted(true)` 或 `setHasAudio(false)`。双端都保留采集，仅静音编码音频。
`switchAudio` 已废弃并作为相同语义的兼容别名；它不再代表麦克风 detach。
需要无音频轨道的会话时，应以 `enableAudio: false` 初始化。

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
- **Android 说明**：原生相机 View 随 `CameraPreview` 创建；预览未挂载时调用会先缓存，挂载后自动应用。推流前仍需显示 `CameraPreview`。
- **示例**：
```dart
await controller.setAudioSettings(128 * 1024);
await controller.startVideoStreaming(url);
```

---

### `setVideoSettings({ ... })`
- **Android 说明**：`bitrate` 在预览未挂载时会先缓存，挂载/`prepare` 后生效；推流中可热更新。

| 参数 | 双端 | 说明 |
|------|------|------|
| `bitrate` | ✅ | 视频码率（bps）。Android 推流中可热更新。 |
| `width` / `height` | ✅ | 正偶数；Android 于下一次编码会话生效。 |
| `frameInterval` | ✅ | 正数，单位秒；Android 于下一次 prepare 生效。 |
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
- **Android 说明**：与 `setAudioSettings` 相同，预览未挂载时可先缓存。
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
| `bitrate` / `fps` / `width` / `height` | 流指标 |
| `cacheSize` | 发送缓存大小 |
| `sentAudioFrames` / `sentVideoFrames` | 已发送帧数（Android） |
| `droppedAudioFrames` / `droppedVideoFrames` | 丢弃帧数（Android） |
| `isAudioMuted` / `isVideoMuted` | 是否静音（双端，1.0.8+） |
| `rttMicros` | RTMP 往返时延（Android，需 `setRtmpShouldSendPings`） |
| `bytesSend` | 已发送字节数 |
| `queueBytesOut` / `bytesOutPerSecond` / `queueCongestionPercent` / `totalBytesOut` | 队列 / 吞吐（Android，RootEncoder 2.8.1+） |

```dart
final stats = await controller.getStreamStatistics();
print('${stats.fps} fps, muted=${stats.isAudioMuted}');
```

---

### Android：`setForceBt709Color(bool enabled)`
- **作用**：编码使用 BT.709 色彩矩阵。
- **调用时机**：`initialize` 之后、开始录制或推流之前，空闲预览已运行时也可调用。设置先缓存，等下次编码器准备前应用，不修改已准备好的预览编码器。推流或录制中修改会报错且保留原缓存；重复设置相同值安全返回。
```dart
await controller.setForceBt709Color(true);
await controller.startVideoStreaming(url);
```

---

### Android：`setPitchShift(double pitch)`
- **作用**：麦克风 PCM 变调（RootEncoder `PitchShiftEffect`）。
- **说明**：原生侧将 `pitch` 限制在 `0.5…3.0`；传 `1.0` 关闭变调。
```dart
await controller.setPitchShift(1.8);
await controller.setPitchShift(1.0); // 关闭
```

---

### 叠字/水印：`setOverlayText` / `setOverlayImage` / `clearOverlay`
双端可用。`fontSize` 控制字形大小；`scale` 为相对自然尺寸的百分比（`100` = 1:1）。
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

### 多路推流：`startMultiStreaming`
**Android + iOS**。不含 WHIP/WHEP。Example 默认一路 RTMP + 一路 SRT（`dest1` / `dest2`），可用 **Stop dest1 only** 只停一路。
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

### Android：`setVideoSource` / `enableBufferAudio`

- **`setVideoSource`**：`camera2`、`cameraX`（默认）、`uvc`、`screen`。使用 `screen` 前须先 `requestScreenCapture`。
- **朝向**：`startVideoStreaming` 时，`camera2` / `cameraX` 会重新应用当前前后置；UVC、screen 无镜头朝向。UVC/screen 推流中调用 `switchCamera` 会报错。
- **预览**：默认空闲预览为 CameraX；显式选择 Camera2 时预览也使用 Camera2。UVC/screen 在采集前使用相机占位预览。。
- **`enableBufferAudio(true)`**：在单路会话中替换麦克风 PCM。`enableAudio: false` 时须在开流前启用；多路推流不支持缓冲音频。

### Android：`lockExposure` / `unlockExposure` / `isExposureLocked`
- **作用**：锁定 / 解锁 Camera2 自动曝光（避免人脸或光线导致曝光跳动）。
- **调用时机**：预览或推流**已启动之后**。
```dart
final locked = await controller.lockExposure();
final isLocked = await controller.isExposureLocked();
await controller.unlockExposure();
```

---

### Android：`setRtmpShouldSendPings(bool enabled)`
- **作用**：开启 RTMP 周期 ping，用于测量 RTT。
- **调用时机**：`initialize` 之后、`startVideoStreaming` **之前**（预览未挂载时会先缓存）。
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
`rtmp_streaming` 为 Flutter 开发者提供跨平台推流与视频录制能力。  
自 **1.0.8** 起，音视频临时静音、编码参数设置、帧率配置等 API 已在双端对齐；**2.0.1** 起 Android 可在 `CameraPreview` 挂载前安全设置编码参数（先缓存后应用）；**2.1.0** 起 Android 多路推流 / 编解码 / 视频源基于 RootEncoder 2.8.1，且 `CameraValue.isStreaming` 取代 `isStreamingVideoRtmp`。**2.1.1** 修复 Android 开流时前置被重置，并将 Android 独有控制接到 CameraX / WHIP / StreamBase 会话。iOS 仍保留播放控制与多任务相机等扩展能力，Android 保留滤镜、BT.709、RTT 与队列统计等扩展能力。


## Android 2.2 升级与验证

最低要求 Flutter **3.44** / Dart **3.12**；本次开发验证使用 Flutter 3.47.7 / Java 21。Android 构建依赖为 AGP 9.4.1、Gradle 9.8.1、Kotlin 2.4.21、AndroidX Annotation 1.11.0、SDK 37.2、Build Tools 37.0.0、NDK 30.0.16248370。RootEncoder 2.8.1、HaishinKit SPM 2.2.5 已是当前发布版本；iOS 必须使用 SPM；CocoaPods 最后发布的旧版不包含当前源码需要的 RTMP/RTC 模块。

默认预览切换到 CameraX。需要精确 Camera ID、曝光/白平衡锁定或手动传感器控制时，请选择 Camera2；CameraX 仅保证前后置朝向。单路推流使用各协议专用客户端，不再受 GenericStream 的公共编码子集限制。

| 协议 | 视频编码 | 音频编码 |
| --- | --- | --- |
| RTMP / RTSP | H264、H265、AV1、VP8、VP9 | AAC、HE-AAC、OPUS、G711 |
| SRT / UDP | H264、H265 | AAC、HE-AAC、OPUS |
| WHIP | RootEncoder 支持的 WebRTC 编码，须服务端配合 | 默认 OPUS，也可 G711 |

不兼容组合会返回错误。修改编码前须停止推流与录像；硬件编码器、服务端及录制容器也必须支持所选编码。MP4 录像优先使用兼容性较好的 H264/AAC。未显式选择音频编码时，WHIP 自动使用 OPUS。

```dart
await controller.setRtmpMetadata({'application': 'my-app', 'session': 42});
final controls = await controller.getCameraControls();
await controller.setZoom(2.0.clamp(controls.minZoom, controls.maxZoom));
await controller.setAutoFocus(true);
await controller.tapToFocus(x: 0.5, y: 0.5);
// 已在录像/推流时：
await controller.requestKeyFrame();

// Camera2 新扩展，须相应预览已启动，数值须在设备支持范围内：
await controller.setVideoSource(VideoSourceType.camera2);
await controller.setManualExposure(iso: 200, exposureTimeNanos: 10000000);
await controller.setCaptureTelemetry(true, intervalMs: 1000);
// controller.value.event 中 eventType 为 capture_statistics，数据在 captureStatistics 中。
await controller.setManualExposure(); // 恢复自动曝光
await controller.setCaptureTelemetry(false);
```

RTMP 元数据须在开流前设置，只接受字符串、布尔值和有限数值，空 map 清除。重建会话后恢复静音、滤镜、叠加层和变调；队列自适应按实际配置的视频＋音频码率预算工作。多路重试/断开事件携带 `destinationId`，单一路径失败不会误停其他路径；统计和自适应由首个活动目标驱动。

自定义 PCM 为有符号小端 PCM16：AAC/HE-AAC 为 32000 Hz 双声道、OPUS 为 48000 Hz 双声道、G711 为 8000 Hz 单声道，须发送完整采样帧。RootEncoder 的 IPv6、时间戳、队列和源管理修复随依赖生效；IPv6 仍需网络和目标服务端支持。

屏幕采集须先挂载 CameraPreview，Activity 在前台，并于每次新会话前重新调用 `requestScreenCapture`。插件提供 MediaProjection 前台服务，启用麦克风时同时声明/使用 microphone 服务类型；停止采集或释放预览会清理服务。Android 14+ 不复用授权令牌：没有正在录像的屏幕推流在 Surface 丢失后结束，重启须重新授权。多路推流在 Surface 丢失后需要显式重启。物理摄像头录像在 Surface 丢失时结束并保存文件，摄像头推流可在 Surface 恢复后重启；本插件不提供无人值守的后台摄像头服务。

示例已声明并请求 Android 17 的 `ACCESS_LOCAL_NETWORK`；宿主应用以 Android 17+ 为目标并连接局域网服务端时，也须声明和动态申请。保存应用私有目录不需要外部存储权限。RTMPS/RTSPS 已启用主机名校验，应使用与主机名匹配的证书。

验证命令与英文说明一致：根目录 `flutter analyze`、`flutter test`，示例目录 `flutter test`，以及示例 Android 工程的 `:rtmp_streaming:testDebugUnitTest :rtmp_streaming:lintDebug :app:assembleDebug`。自动化覆盖状态/错误恢复、截图并发、事件传播、URL/编码组合和权限回调。编译通过不代表真机采集质量或服务端互通已验证；发布前仍须在目标设备上验证前后置切换、预览→录像→推流→停止、无音频、屏幕授权/撤销、Activity 重建、后台恢复与多路故障。此次未验证 iOS 编译。

## 3.0.0 双端对齐与迁移

**iOS 改为仅支持 SPM，要求支持 Swift 6 的 Xcode。** 执行
`flutter config --enable-swift-package-manager`、`flutter clean`、`flutter pub get`，
并迁移宿主旧 Podfile、Pods 构建阶段和 xcconfig 引用。示例已迁移到纯 SPM。
CocoaPods 安装会明确提示迁移，不再选择无法编译的旧 SDK。

初始化后调用 `await controller.getCapabilities()`；切换相机或采集源后重新查询。
协议来自实际原生构建，编码器列表反映底层能力，`features` 表示已开放操作，未知项按 false 处理。
相机/硬件和协议仍会约束编码组合、分辨率及帧率，能力列表不保证所有组合都可用。

| 功能 | Android | iOS |
|---|---|---|
| RTMP/SRT 推流、录制、截图、叠加、静音 | 支持 | 支持 |
| 变焦、自动对焦、点按对焦、预览手电筒 | Camera2/CameraX | 当前采集设备 |
| 曝光/白平衡锁 | Camera2 | 设备支持时可用 |
| H264/H265 | 取决于硬件 | H265 需 iOS 17.4+ 硬件查询支持；WHIP 使用 H264 |
| RTSP/UDP、UVC、屏幕采集 | 保留，需授权/外设 | 明确不支持 |
| PCM、AEC/NS、变调、RTMP ping、GPU 滤镜 | 保留专属接口 | 明确不支持 |
| 手动 ISO/曝光及采集遥测 | Camera2/设备支持时 | 设备支持时；遥测报告 ISO/曝光/镜头位置 |
| 录制暂停 | 支持 | StreamRecorder 不支持 |
| WHIP Bearer Token | 支持 | 上游无注入接口，传入会报错 |
| 多任务相机 | Android 独立生命周期 | iOS 17+ 且设备支持 |
| RTMP/WHEP 播放 | 不支持 | 独立 PlayerController/PlayerPreview |

停止单路或多路推流都保留并行录制；`stopRecordingOrStreaming` 停止全部，重复停止安全。
同时启动录制和推流时，录制失败会回滚网络连接。多路目标默认 ID 为 `dest_0`、`dest_1` 等，
显式 ID 必须非空且唯一；通过 `streamingDestinationIds` 取得目标。
事件统一使用 `destinationId`，统计取首个存活目标，不伪造总和。iOS 断线为终止事件，应用可显式重连。

统计单位为像素、bps、fps、字节和微秒。`cacheSize` 为发送队列容量（包数），不是缓冲字节；
不支持的指标返回 null。`bitrate` 为目标编码码率，实际传输速率使用独立指标。
协议统计可能包含协议头和重传，不能把不同传输的累计字节直接当成同一媒体量。

空闲时用 `setCapturePreset(ResolutionPreset...)` 选择采集质量；`setVideoSettings` 设置编码。
尺寸、关键帧间隔、帧率应在启动前设置，Android 于下次编码准备时应用。
iOS 配置在新建协议流时保留，录制压缩配置于开始录制时应用，正在写入的文件不改参数；录制仅支持 average 码率模式，其他录制模式明确拒绝。
Android 期望帧率须为正整数；无法应用的码率模式/profile 明确报错；iOS 的 SRT 也遵循码率模式和系统版本限制。

叠加文字和图片以输出像素为单位，缩放限制为 10–400%，保留 ARGB 透明度。
添加/清除叠加不会改写编码尺寸；iOS 截图使用与预览相同的 aspect-fill 裁切。
`setOverlayCanvas` 是旧 `setScreenSettings` 的明确命名，表示合成画布而非屏幕采集；显式画布尺寸不会被后续叠加覆盖。

使用 `setVideoEffect(VideoEffect.sobel)` 替代裸整数滤镜；文字/图片使用带参数的 overlay API。
保留旧接口兼容，未知滤镜报错。`androidUseOpenGL` 和 `prepareForVideoStreaming` 标记废弃且无副作用。
播放移到独立控制器：先 dispose 相机，再 initialize PlayerController；RTMP 可远程暂停，WHEP 支持停止/重连及静音。
旧播放暂停接口会校验协议和播放状态，不会再误操作推流编码器。

真机相机质量、直播服务器兼容性、前后台中断和外设仍需真机验收；编译与接口测试不能替代这些验证。

独立播放示例：`cd example && flutter run -t lib/playback.dart`（iOS）。

本轮验证：24 项 Dart 接口/状态测试、15 项 Android 原生测试、Android lint 和 APK 构建通过。
iOS 应用及 3 项 XCTest 已通过 arm64 模拟器编译与链接；本机 Xcode 27.1 的
`invalidDigitCount` 版本解析故障阻止 XCTest 执行，因此不将其记为运行通过。
未进行真机或直播服务器验收。
