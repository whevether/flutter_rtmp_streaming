import AVFoundation
import HaishinKit
import ReplayKit
import RTMPHaishinKit
import SRTHaishinKit
#if canImport(RTCHaishinKit)
import RTCHaishinKit
#endif

/// Broadcast Upload Extension SampleHandler adapted from HaishinKit
/// `Examples/iOS/Screencast/SampleHandler.swift` (2.2.5).
///
/// Setup:
/// 1. Add a Broadcast Upload Extension target in Xcode (e.g. `BroadcastUploadExtension`).
/// 2. Replace its SampleHandler with this file (or copy these contents).
/// 3. Enable App Group `group.com.rtmp_streaming.broadcast` on Runner + Extension.
/// 4. From Flutter call `prepareScreenBroadcastConfig(url: ...)` then start Live Broadcast.
final class SampleHandler: RPBroadcastSampleHandler {
  private static let appGroupId = "group.com.rtmp_streaming.broadcast"
  private var session: (any Session)?
  private var mixer = MediaMixer(captureSessionMode: .manual, multiTrackAudioMixingEnabled: true)
  private var needVideoConfiguration = true

  override init() {
    super.init()
    Task {
      await SessionBuilderFactory.shared.register(RTMPSessionFactory())
      await SessionBuilderFactory.shared.register(SRTSessionFactory())
      #if canImport(RTCHaishinKit)
      await SessionBuilderFactory.shared.register(HTTPSessionFactory())
      #endif
    }
  }

  override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
    Task {
      do {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        let urlString = defaults?.string(forKey: "rtmp_streaming.broadcast.url")
          ?? PreferenceFallback.uri
        guard let url = URL(string: urlString) else {
          finishBroadcastWithError(NSError(
            domain: "BroadcastUploadExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing broadcast URL in App Group"]
          ))
          return
        }

        session = try await SessionBuilderFactory.shared.make(url)
          .setMode(.publish)
          .build()
        await session?.stream.setVideoInputBufferCounts(5)
        var videoSetting = await mixer.videoMixerSettings
        videoSetting.mode = .passthrough
        await mixer.setVideoMixerSettings(videoSetting)
        await mixer.startRunning()
        if let session {
          await mixer.addOutput(session.stream)
          try await session.connect { }
        }
      } catch {
        finishBroadcastWithError(error as NSError)
      }
    }
  }

  override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
    switch sampleBufferType {
    case .video:
      Task {
        if needVideoConfiguration, let dimensions = sampleBuffer.formatDescription?.dimensions {
          var videoSettings = await session?.stream.videoSettings
          videoSettings?.videoSize = .init(
            width: CGFloat(dimensions.width),
            height: CGFloat(dimensions.height)
          )
          if let videoSettings {
            try? await session?.stream.setVideoSettings(videoSettings)
          }
          needVideoConfiguration = false
        }
        await mixer.append(sampleBuffer)
      }
    case .audioMic, .audioApp:
      Task { await mixer.append(sampleBuffer) }
    @unknown default:
      break
    }
  }

  override func broadcastFinished() {
    Task {
      try? await session?.close()
      await mixer.stopRunning()
      session = nil
    }
  }
}

private enum PreferenceFallback {
  static let uri = "rtmp://192.168.1.15/live/live"
}
