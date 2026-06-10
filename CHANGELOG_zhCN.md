## 0.0.1
1. 完全重构 android 版本。升级gradle与rtmp 推流插件com.github.pedroSG94.RootEncoder到最新版本
2. 安卓版本增加滤镜
3. 安卓版本过时方法，以及切换摄像头导致崩溃改善
4. 安卓版本录直播无法录制问题改善。
5. 增加安卓弱光环境设置开关。

## 0.0.2
1. 移除多余的安卓包。减少打包体积

## 0.0.3
1. 升级 ios HaishinKit 到1.9.9
2. 重写部分过时方法。


## 0.0.4
1. 修复安卓切换崩溃错误。并增加切换摄像头。声音开关。 优化示例，
2. 清理多余用不到方法

## 0.0.5
1. 优化安卓示例
2. 安卓增加暂停/恢复录制
## 0.0.6
1. ios HaishinKit更新到2.0.0，预览版本,不是正式版本。可能有bug

## 1.0.0
1. ios HaishinKit更新到2.0.0，正式版本,
2. iOS代码完全重构。并通过swift包来管理依赖
3. ios 增加众多方法
4. 示例更新。camera.dart方法更新。移除多余字段以及重复方法。
5. android 更新gradle到9.0，rtmp包更新到最新版本, 返回值与ios统一，并处理销毁方法
6. android 增加滤镜功能。

## 1.0.1
1. 更新依赖
2. 添加 截图方法`takePicture`  

## 1.0.2
1. 更新依赖
2. 修复无法移除滤镜问题

## 1.0.3
1. 修复 android 权限bug



## 1.0.5
1. 更新 HaishinKit.swift 到 2.2.5 修复 xcode 26.4 编译错误
2. 更新 com.github.pedroSG94.RootEncoder 到 2.7.1
3. **文档**：在 README / README_zhCN 中补充以下 `CameraController` 的用法说明：
   - **Android（RootEncoder 2.7.0+）**：`setForceBt709Color`、`setRtmpShouldSendPings` — 编码使用 BT.709 色彩矩阵；RTMP 周期 ping 以测量往返时延（配合 `getStreamStatistics` 中的 `rttMicros` 等字段）。
   - **iOS（HaishinKit 2.2.1+ / 2.2.2+ / 2.2.5+）**：`setVideoSettings` — 可选参数 `expectedFrameRate`（写入 RTMP onMetaData 的 `framerate`）、`bitRateMode`（`average` / `constant` / `variable`）；`setMultitaskingCameraAccessEnabled` — 分屏/多任务场景下保持相机（需 iOS 17+ 且设备支持）。
4. 本版本变更日志与上述说明对应，便于查阅与版本对齐。

