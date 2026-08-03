## 2.0.0

1. **多协议推流**
   - 新增 `StreamingProtocol`（`rtmp` / `rtsp` / `srt` / `udp` / `whip` / `whep`），供 `startVideoStreaming` 使用。
   - Android（RootEncoder **2.8.0**）：RTMP、RTSP、SRT、UDP、WHIP。
   - iOS（HaishinKit **2.2.5**）：RTMP、SRT；WHIP/WHEP 经 `RTCHaishinKit`（alpha，需 Flutter SPM）。

2. **叠字 / 水印**（Android + iOS）
   - `setOverlayText` / `setOverlayImage` / `clearOverlay`。
   - iOS：开启叠字后画布与编码尺寸随横竖屏对齐，避免预览被压扁/拉伸。

3. **多路推流**（仅 iOS）
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



























