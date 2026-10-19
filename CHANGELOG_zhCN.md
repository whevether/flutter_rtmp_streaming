## 2.3.0

- 修复 Android 空闲预览已准备编码器后设置 BT.709 报错：配置延迟到下次编码器准备前应用；运行中拒绝修改且不污染缓存，重复设置相同值安全返回。示例 Manifest 开启新版 Android 返回回调。
- 新增原生构建与当前采集源的能力查询 `getCapabilities`，补齐双端通用相机控制、类型化采集预设及具名 Android GPU 滤镜接口。平台专属采集和传输能力明确声明支持范围。
- 停止多路推流时保留并行录制，统一默认目标 ID 和 `destinationId` 事件；录制与推流同时启动失败时回滚网络，停止全部输出支持重复调用，暂停状态仅在原生操作成功后更新。
- 统一统计数值转换与单位，不可用指标返回 null；修复 iOS 编码配置在新建协议流时丢失、SRT 码率模式未应用、录制压缩配置不完整、手电筒误操作默认后摄、叠加透明度与缩放不一致、截图裁切与预览不一致等问题。
- 新增独立的 iOS `PlayerController` / `PlayerPreview` 及 RTMP/WHEP 播放示例，分离播放与采集状态；补齐设备支持时的手动曝光和采集遥测。对不支持的暂停、编码、认证和多任务相机请求明确报错，避免静默忽略参数。
- iOS 改为必须使用 Swift Package Manager 和支持 Swift 6 的 Xcode，补齐 FlutterFramework 与 SRT/RTC 静态库链接依赖；示例移除旧 CocoaPods 集成。通过主 Actor 与方法队列管理会话，完善初始化、销毁、断线监控、录制错误、事件订阅及纹理尺寸同步。
- 废弃无效的 OpenGL 开关、预热方法、含义不明确的音频与画布命名，以及裸整数滤镜接口，并保留兼容入口。音频开关统一为保留麦克风采集的静音语义；`setOverlayCanvas` 明确表示合成画布，不代表屏幕采集。

## 2.2.0

- 合并 PR #14，并修复 CameraX 空闲预览直接录制时缺少音频准备、截图读取旧渲染器、编码器/视频源未释放、Surface 销毁及录像/推流状态相互误清等问题。
- 单路推流改用各协议专用的 StreamBase 客户端，让 RTMP/RTSP 真正支持 AV1、VP8、VP9 及新增音频编码；在替换会话前校验 URL 和编码组合。WHIP 默认 OPUS，按编码选择采样率与声道。
- Android 新增 `setRtmpMetadata`、`requestKeyFrame`、`getCameraControls`、`setZoom`、`setAutoFocus`、`tapToFocus`，以及基于 Camera2 自定义 CaptureRequest 的 `setManualExposure`、基于采集完成回调的限频 `setCaptureTelemetry`。
- 分辨率与关键帧间隔在 prepare 时实际生效；重建会话后恢复静音、滤镜、叠加层和变调。修复视频叠加异步准备与播放器泄漏，自适应码率使用实际配置的总码率预算。
- 补齐 MediaProjection 前台服务、授权取消/撤销清理；停止屏幕采集后须重新授权，避免 Android 14+ 复用采集令牌。
- 修复权限回调、Activity 重新挂载、初始化中断清理及预览未挂载时调用一直等待的问题。隔离旧会话回调，多路推流分别重试，在事件中保留 `destinationId`。
- 开启 RTMPS/RTSPS 主机名校验，默认关闭原生客户端日志，避免记录推流 URL/令牌。
- 升级 AGP 9.4.1、Gradle 9.8.1（校验和）、Kotlin 2.4.21、AndroidX Annotation 1.11.0、编译 SDK 37.2；保留稳定 NDK 30.0.16248370 / Build Tools 37.0.0。更新示例依赖并固定 permission_handler 范围，最低要求 Flutter 3.44 / Dart 3.12。RootEncoder 2.8.1 和 HaishinKit SPM 2.2.5 已为当前版本；CocoaPods 保留其最新发布的 HaishinKit 2.0.9 / SRTHaishinKit 2.0.8。
- 扩充回归测试和示例中的相机控制、编码、视频源、元数据演示。真机采集、真实服务端互通及 iOS 编译仍需对应设备/平台验证。

## 2.1.1

1. **Android**：修复 `startVideoStreaming` 时前置摄像头被重置为后置（camera2 / CameraX / WHIP / StreamBase / 多路 / 录制）。
2. **Android**：滤镜、水印、静音、变调、闪光灯、曝光/白平衡锁定、点测光统一走当前活跃管线（GenericCamera2、GenericStream、WhipStream、MultiCamera2）。
3. **Android**：推流中开启 `enableBufferAudio` 会迁到 StreamBase；录制 / 录制+推流支持 StreamBase/WHIP；WHIP 启用 ABR。
4. **文档**：补充 `setVideoSource` 朝向说明（CameraX 按前后置；UVC/screen 无朝向）及开流前预览仍为 Camera2 的行为。

## 2.1.0

1. **Android 构建**：AGP **9.4.0**、Gradle **9.7.1**，插件 `android/` 改为 Kotlin DSL（`.gradle.kts`）。移除插件侧 `gradle/wrapper` 与 `gradle.properties`（由宿主 / example 决定 Gradle 与 AndroidX）。
2. **RootEncoder 2.8.1**：`library` + `extra-sources`；叠字滤镜类重命名（`GifFilterRender` / `ImageFilterRender` / `TextFilterRender`）；`SpriteGestureController.setSprite`；队列感知 ABR（`QueueAwareBitrateAdapter`）。
3. **Android 编解码 / 音频**：`setVideoCodec` / `setAudioCodec`；`setAudioProcessing`（回声消除 + 降噪）。
4. **Android 相机控制**：白平衡锁定；`tapToMeter`（曝光 / 白平衡）。
5. **Android 多路推流**：`startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming`，经 `MultiCamera2` 与 iOS Dart API 对齐（不含 WHIP/WHEP）。
6. **Android 视频源**：`setVideoSource`（`camera2` / `cameraX` / `uvc` / `screen`）、`requestScreenCapture`、`enableBufferAudio` / `feedPcmAudio`（非 camera2 走 StreamBase 路径）。
7. **统计**：`StreamStatistics` 新增 `queueBytesOut`、`bytesOutPerSecond`、`queueCongestionPercent`、`totalBytesOut`。
8. **加固**：dispose 不再重复完成 MethodChannel；MediaProjection 在替换/dispose 时 stop；GenericStream 重试/编解码/码率/BT.709 对齐；推流中再次 start 改为重启；pending 缓存覆盖编解码/视频源/AEC。
9. **破坏性变更**：`CameraValue.isStreamingVideoRtmp` 重命名为 `isStreaming`（覆盖全部协议）；移除 Android 空 `close()` 兼容桩。
10. **WHEP**：Android 仍不支持 ❌（RootEncoder 仅有 WHIP）。

## 2.0.1

1. **Android**：修复 `initialize` 之后、`CameraPreview` 尚未挂载时调用编码参数 API 报 `Camera not initialized` 的问题。
   - `setAudioSettings` / `setVideoSettings` / `setFrameRate` / `setForceBt709Color` / `setRtmpShouldSendPings` 会先缓存参数，在原生 View 创建时应用（预览重建时也会保留）。
2. **文档**：补充 Android 上上述 API 的调用时机说明；推流前仍需挂载 `CameraPreview`。


## 2.0.0

1. **多协议推流**
   - 新增 `StreamingProtocol`（`rtmp` / `rtsp` / `srt` / `udp` / `whip` / `whep`），供 `startVideoStreaming` 使用。
   - Android（RootEncoder **2.8.0**）：RTMP、RTSP、SRT、UDP、WHIP。
   - iOS（HaishinKit **2.2.5**）：RTMP、SRT；WHIP/WHEP 经 `RTCHaishinKit`（alpha，需 Flutter SPM）。

2. **叠字 / 水印**（Android + iOS）
   - `setOverlayText` / `setOverlayImage` / `clearOverlay`。
   - iOS：开启叠字后画布与编码尺寸随横竖屏对齐，避免预览被压扁/拉伸。

3. **多路推流**（仅 iOS；Android 自 **2.1.0** 起支持）
   - `startMultiStreaming` / `stopStreamingDestination` / `stopMultiStreaming`（不含 WHIP/WHEP）。
   - Example 默认一路 RTMP + 一路 SRT。

4. **SRT URL 兼容**（iOS）
   - `SrtURLHelper` 支持 SRS/ZLMediaKit 风格地址，例如  
     `srt://host:10080?streamid=#!::r=live/livestream,m=publish`  
     （`#` 经 `SRTO_STREAMID` 设置，不再被当成 URL fragment）。
   - 更明确的 SRT 连接错误信息（`unsupportedUri` / 服务端拒绝原因）。

5. **iOS EventChannel**
   - 原生向 Flutter 发送事件统一切到平台主线程，避免非主线程通道告警。

6. **Android 扩展**
   - `setPitchShift`（RootEncoder 变调；`1.0` 关闭）。
   - `lockExposure` / `unlockExposure` / `isExposureLocked`（预览或推流启动后调用）。
   - 工程与工具链更新（如 compileSdk 37、AGP 9.x）。

7. **文档与示例**
   - 更新 README / README_zhCN 与 example，覆盖协议、叠字、iOS 多路推流说明。


## 1.0.8
1. 修复prepareVideo参数存在错误。会导致编译错误.

## 1.0.7
1. **依赖升级**
   - iOS：`HaishinKit` pod 从 `2.0.9` 升级至 **`2.2.5`**（与 Swift Package 一致；支持 Xcode 26.4、多任务相机等）。
   - Android：`com.github.pedroSG94.RootEncoder:library` 升级至 **`2.7.5`**。

2. **跨平台 API 对齐（原多为 iOS 独有或 Dart 未接原生）**
   - `prepareForVideoStreaming()`：iOS 提前 attach 音频以减少开播延迟；Android 为 no-op。
   - `getHasAudio` / `setHasAudio`：推流时查询/设置**临时静音**（不卸麦克风）。
   - `getHasVideo` / `setHasVideo`：推流时查询/设置**临时停发视频**（Android 发黑帧，iOS 混音静音）。
   - `setAudioSettings(bitrate)`：设置音频编码码率（bps），下次 `prepareAudio` 生效。
   - `setVideoSettings({ bitrate, ... })`：设置视频参数；Android 推流中可通过 `bitrate` 热更新（`setVideoBitrateOnFly`）。
   - `setFrameRate(frameRate)`：设置目标帧率（宜在开播前调用）。
   - `switchAudio`：现 **Android / iOS 双端可用**（切换麦克风采集，语义与 `setHasAudio` 不同）。

3. **流统计增强**
   - `StreamStatistics` 新增 `isVideoMuted`。
   - iOS `getStreamStatistics` 补充 `isAudioMuted`、`isVideoMuted`、`bytesSend` 等字段。
   - Android `getStreamStatistics` 补充 `isVideoMuted`。

4. **文档**
   - README / README_zhCN 更新方法列表与跨平台 API 使用说明。


## 1.0.6
1. 修改安卓下面#8问题
2. 修改包名符合规范


## 1.0.5
1. 更新 HaishinKit.swift 到 2.2.5 修复 xcode 26.4 编译错误
2. 更新 com.github.pedroSG94.RootEncoder 到 2.7.1
3. **文档**：在 README / README_zhCN 中补充以下 `CameraController` 的用法说明：
   - **Android（RootEncoder 2.7.0+）**：`setForceBt709Color`、`setRtmpShouldSendPings` — 编码使用 BT.709 色彩矩阵；RTMP 周期 ping 以测量往返时延（配合 `getStreamStatistics` 中的 `rttMicros` 等字段）。
   - **iOS（HaishinKit 2.2.1+ / 2.2.2+ / 2.2.5+）**：`setVideoSettings` — 可选参数 `expectedFrameRate`（写入 RTMP onMetaData 的 `framerate`）、`bitRateMode`（`average` / `constant` / `variable`）；`setMultitaskingCameraAccessEnabled` — 分屏/多任务场景下保持相机（需 iOS 17+ 且设备支持）。
4. 本版本变更日志与上述说明对应，便于查阅与版本对齐。


## 1.0.3
1. 修复 android 权限bug


## 1.0.2
1. 更新依赖
2. 修复无法移除滤镜问题


## 1.0.1
1. 更新依赖
2. 添加 截图方法`takePicture`  


## 1.0.0
1. ios HaishinKit更新到2.0.0，正式版本,
2. iOS代码完全重构。并通过swift包来管理依赖
3. ios 增加众多方法
4. 示例更新。camera.dart方法更新。移除多余字段以及重复方法。
5. android 更新gradle到9.0，rtmp包更新到最新版本, 返回值与ios统一，并处理销毁方法
6. android 增加滤镜功能。


## 0.0.6
1. ios HaishinKit更新到2.0.0，预览版本,不是正式版本。可能有bug


## 0.0.5
1. 优化安卓示例
2. 安卓增加暂停/恢复录制

## 0.0.4
1. 修复安卓切换崩溃错误。并增加切换摄像头。声音开关。 优化示例，
2. 清理多余用不到方法


## 0.0.3
1. 升级 ios HaishinKit 到1.9.9
2. 重写部分过时方法。


## 0.0.2
1. 移除多余的安卓包。减少打包体积



## 0.0.1
1. 完全重构 android 版本。升级gradle与rtmp 推流插件com.github.pedroSG94.RootEncoder到最新版本
2. 安卓版本增加滤镜
3. 安卓版本过时方法，以及切换摄像头导致崩溃改善
4. 安卓版本录直播无法录制问题改善。
5. 增加安卓弱光环境设置开关。



























