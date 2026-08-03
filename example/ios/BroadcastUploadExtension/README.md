# iOS Broadcast Upload Extension

Template for screen streaming with HaishinKit ReplayKit (based on HaishinKit 2.2.5 Screencast SampleHandler).

## Wire into Xcode

1. Open `Runner.xcworkspace`.
2. File → New → Target → **Broadcast Upload Extension** (name e.g. `BroadcastUploadExtension`).
3. Replace generated `SampleHandler.swift` with [SampleHandler.swift](SampleHandler.swift) from this folder (or add this folder to the target).
4. Use [Info.plist](Info.plist) keys (`RPBroadcastProcessModeSampleBuffer`).
5. Enable **App Groups** on **Runner** and the Extension: `group.com.rtmp_streaming.broadcast`.
6. Add HaishinKit / RTMPHaishinKit / SRTHaishinKit (and optionally RTCHaishinKit) SPM products to the Extension target (same versions as the plugin, 2.2.5).

## Flutter usage

```dart
await controller.prepareScreenBroadcastConfig(
  url: 'rtmp://your-server/live/key',
  protocol: StreamingProtocol.rtmp,
);
// Then: Control Center → Screen Recording → select this Broadcast Extension → Start Broadcast
```

`CameraController.startScreenStreaming` is **Android-only**; on iOS it throws by design.
