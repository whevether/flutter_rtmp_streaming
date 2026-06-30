## 1.0.7
1. **Dependency upgrades**
   - iOS: `HaishinKit` pod bumped from `2.0.9` to **`2.2.5`** (aligned with Swift Package; Xcode 26.4, multitasking camera, etc.).
   - Android: `com.github.pedroSG94.RootEncoder:library` bumped to **`2.7.5`**.

2. **Cross-platform API alignment** (previously iOS-only or Dart-only without native wiring)
   - `prepareForVideoStreaming()`: iOS pre-attaches audio to reduce start latency; Android no-op.
   - `getHasAudio` / `setHasAudio`: query/set **temporary mute** while streaming (does not detach the mic).
   - `getHasVideo` / `setHasVideo`: query/set **temporary video mute** (Android sends black frames; iOS mixer mute).
   - `setAudioSettings(bitrate)`: audio encoder bitrate in bps; applied on next `prepareAudio`.
   - `setVideoSettings({ bitrate, ... })`: video encoder settings; Android can hot-update `bitrate` via `setVideoBitrateOnFly` while live.
   - `setFrameRate(frameRate)`: target capture/encode frame rate (call before streaming when possible).
   - `switchAudio`: now available on **both Android and iOS** (toggles mic capture; different from `setHasAudio`).

3. **Stream statistics**
   - `StreamStatistics` adds `isVideoMuted`.
   - iOS `getStreamStatistics` now returns `isAudioMuted`, `isVideoMuted`, `bytesSend`, etc.
   - Android `getStreamStatistics` adds `isVideoMuted`.

4. **Documentation**
   - README / README_zhCN updated method lists and cross-platform API usage.


## 1.0.6
1. fix android issue  #8 question
2. update package name


## 1.0.5
1. update HaishinKit.swift to 2.2.5 fix xcode 26.4 build error
2. update com.github.pedroSG94.RootEncoder to 2.7.1

3. **Documentation**: Added usage notes in README / README_zhCN for the following `CameraController` methods:
   - **Android (RootEncoder 2.7.0+)**: `setForceBt709Color`, `setRtmpShouldSendPings` — BT.709 color matrix for encoding; RTMP periodic ping for RTT (see `getStreamStatistics` / `rttMicros` when pings are enabled).
   - **iOS (HaishinKit 2.2.1+ / 2.2.2+ / 2.2.5+)**: `setVideoSettings` — optional `expectedFrameRate` (onMetaData `framerate`) and `bitRateMode` (`average` / `constant` / `variable`); `setMultitaskingCameraAccessEnabled` — multitasking / PiP camera access (iOS 17+ when supported).
4. **CHANGELOG**: This entry records the above API documentation and usage guidance; behavior matches implementations added in plugin development for RootEncoder 2.7.x and HaishinKit 2.2.x.


## 1.0.3
1. fix android permission bug


## 1.0.2
1. update package
2. fix bug not removeFilter


## 1.0.1
1. update package
2. add - 📸 Take snapshot during streaming: `takePicture`


## 1.0.0
1. Updated iOS HaishinKit to version 2.0.0 (stable release).  
2. Completely refactored iOS code, now managing dependencies via Swift Package Manager.  
3. Added numerous new methods for iOS.  
4. Updated examples: revised `camera.dart`, removed redundant fields and duplicate methods.  
5. Upgraded Android Gradle to 9.0, updated RTMP package to the latest version, unified return values with iOS, and improved disposal methods.  
6. Added filter functionality for Android.  


## 0.0.6
1. Updated iOS HaishinKit to version 2.0.0 (preview version, not stable, may contain bugs).  


## 0.0.5
1. Optimized Android example project.  
2. Added pause/resume recording functionality for Android.  


## 0.0.4
1. Fixed Android crash errors when switching cameras. Added camera switching and audio toggle features. Optimized the example project.  
2. Cleaned up unused methods.  


## 0.0.3
1. Upgraded iOS HaishinKit to version 1.9.9.  
2. Rewrote some deprecated methods.  


## 0.0.2
1. Removed redundant Android packages to reduce build size.  


## 0.0.1
1. Completely refactored the Android version. Upgraded Gradle and the RTMP streaming plugin `com.github.pedroSG94.RootEncoder` to the latest version.  
2. Added filters for the Android version.  
3. Improved deprecated methods and fixed crashes caused by camera switching on Android.  
4. Fixed the issue where live recording could not be captured on Android.  
5. Added a toggle for low-light environment settings on Android.  






















