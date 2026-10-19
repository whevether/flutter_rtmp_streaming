#if canImport(Flutter)
import Flutter
#endif
import HaishinKit
import RTMPHaishinKit
import SRTHaishinKit
import libsrt
import Logboard
#if canImport(RTCHaishinKit)
import RTCHaishinKit
#endif
import AVFoundation
import VideoToolbox

@MainActor
public final class HaishinKitPlugin: NSObject, @preconcurrency FlutterPlugin {
  private static let instance = HaishinKitPlugin()
  private static var sessionFactoriesRegistered = false
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    instance.registrar = registrar
    let channel = FlutterMethodChannel(name: "com.rtmp_streaming", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let id = Int(bitPattern: ObjectIdentifier(instance))
    let eventChannel = FlutterEventChannel(name: "com.rtmp_streaming.eventchannel/\(id)", binaryMessenger: registrar.messenger())
    
    eventChannel.setStreamHandler(instance)
    Task {
      await instance.ensureSessionFactoriesRegistered()
    }
  }
  
  //  private var handlers: [Int: MethodCallHandler] = [:]
  //
  private(set) var mixer: MediaMixerHandler? {
    didSet {
      oldValue?.stopRunning()
    }
  }
  //订阅消息
  private var sessionGeneration = 0
  private var subscription: Task<(), Error>? {
    didSet {
      oldValue?.cancel()
    }
  }
  //事件
  private var eventSink: FlutterEventSink?
  //  //事件渠道
  //  private var eventChannel: FlutterEventChannel?

  /// Flutter platform channels require the platform (main) thread.
  private func emitEvent(_ payload: [String: Any]) {
    guard let eventSink else { return }
    if Thread.isMainThread {
      eventSink(payload)
    } else {
      DispatchQueue.main.async {
        eventSink(payload)
      }
    }
  }
  //纹理
  private var texture: HKStreamFlutterTexture?
  //连接
  private var rtmpConnection: RTMPConnection?
  // rtmpStream直播 流
  private var rtmpStream: RTMPStream?
  // SRT
  private var srtConnection: SRTConnection?
  private var srtStream: SRTStream?
  #if canImport(RTCHaishinKit)
  // RTC (WHIP / WHEP) — SPM + HaishinKit 2.2.5+ only
  private var rtcSession: (any Session)?
  private var rtcMonitor: Task<Void, Error>?
  private var rtcStream: (any StreamConvertible)?
  private var whepAudioPlayer: AudioPlayer?
  #endif
  private var currentProtocol: String = "rtmp"
  // 录制流
  private var recorderStream: StreamRecorder?
  private var recorderErrors: Task<Void, Never>?
  // Multi-streaming endpoints (excludes WHIP/WHEP)
  private var multiEndpoints: [MultiEndpoint] = []
  private var enableAudio: Bool = true
  private var isRecording = false
  private var isPlayback = false
  private var playbackAudioPlayer: AudioPlayer?
  private var desiredVideoSettings = VideoCodecSettings()
  private var desiredAudioSettings = AudioCodecSettings()
  private var explicitVideoSize = false
  private var telemetryTimer: Timer?

  // 插件注册
  private(set) var registrar: FlutterPluginRegistrar?
  
  private final class MultiEndpoint {
    let id: String
    let protocolName: String
    var rtmpConnection: RTMPConnection?
    var rtmpStream: RTMPStream?
    var srtConnection: SRTConnection?
    var srtStream: SRTStream?
    var statusTask: Task<(), Error>?
    init(id: String, protocolName: String) {
      self.id = id
      self.protocolName = protocolName
    }
  }
  
  private func ensureSessionFactoriesRegistered() async {
    guard !Self.sessionFactoriesRegistered else { return }
    for name in ["com.haishinkit.HaishinKit", "com.haishinkit.RTMPHaishinKit", "com.haishinkit.SRTHaishinKit", "com.haishinkit.RTCHaishinKit"] {
      LBLogger.with(name).appender = NullAppender.shared
    }
    #if canImport(RTCHaishinKit)
    await SessionBuilderFactory.shared.register(HTTPSessionFactory())
    #endif
    Self.sessionFactoriesRegistered = true
  }

  //销毁所有
  private func dispose()async{
    telemetryTimer?.invalidate()
    telemetryTimer = nil
    subscription = nil
    sessionGeneration += 1
    if isRecording { _ = await stopVideoRecording() }
    await tearDownMultiEndpoints()
    await tearDownRtcSession()
    await tearDownSrtSession()
    try? await rtmpConnection?.close()
    rtmpConnection = nil
    playbackAudioPlayer = nil
    if let newRtmpStream = rtmpStream {
      await mixer?.removeOutput(newRtmpStream)
      if let texture {
        registrar?.textures().unregisterTexture(texture.textureId)
        self.texture = nil
      }
      if let newRecorderStream = recorderStream{
        await mixer?.removeOutput(newRecorderStream)
        recorderStream = nil
      }
      await mixer?.dispose()
      _  = try? await newRtmpStream.close()
      mixer = nil
      rtmpStream = nil
    }else{
      mixer?.stopRunning()
      mixer = nil
    }
  }
  //关闭连接与视频流
  private func stopStreaming()async->FlutterError?{
    do{
      sessionGeneration += 1
      subscription = nil
      if !multiEndpoints.isEmpty {
        await tearDownMultiEndpoints()
      } else if currentProtocol == "srt" {
        await tearDownSrtSession()
      } else if currentProtocol == "whip" || currentProtocol == "whep" {
        await tearDownRtcSession()
      } else {
        try? await rtmpConnection?.close()
        _  = try? await rtmpStream?.close()
      }
      return nil
    }catch{
      return FlutterError(code: "closeConnect Error", message: "catch error", details: nil)
    }
    
  }

  private func tearDownMultiEndpoints() async {
    for endpoint in multiEndpoints {
      endpoint.statusTask?.cancel()
      if let stream = endpoint.srtStream {
        await mixer?.removeOutput(stream)
        _ = try? await stream.close()
      }
      try? await endpoint.srtConnection?.close()
      if let stream = endpoint.rtmpStream {
        // Keep the primary initialize()-owned rtmpStream attached for preview.
        if stream !== rtmpStream {
          await mixer?.removeOutput(stream)
          _ = try? await stream.close()
        } else {
          _ = try? await stream.close()
        }
      }
      try? await endpoint.rtmpConnection?.close()
    }
    multiEndpoints.removeAll()
  }

  private func tearDownSrtSession() async {
    if let stream = srtStream {
      await mixer?.removeOutput(stream)
      _ = try? await stream.close()
    }
    try? await srtConnection?.close()
    srtStream = nil
    srtConnection = nil
  }

  /// Maps SRTHaishinKit errors to actionable Flutter messages.
  private static func describeSrtError(_ error: Error) -> String {
    if let srt = error as? SRTConnection.Error {
      switch srt {
      case .unsupportedUri:
        return "Invalid SRT URL (unsupportedUri). Prefer: srt://host:10080?streamid=#!::r=live/livestream,m=publish — streamid with # is applied as a socket option."
      case .failedToConnect(let reason):
        return "SRT connect rejected: \(reason)"
      case .invalidState:
        return "SRT connection invalid state"
      }
    }
    return error.localizedDescription
  }

  private func tearDownRtcSession() async {
    #if canImport(RTCHaishinKit)
    rtcMonitor?.cancel()
    rtcMonitor = nil
    if let stream = rtcStream {
      await mixer?.removeOutput(stream)
      if let texture {
        await stream.removeOutput(texture)
      }
      await stream.attachAudioPlayer(nil)
    }
    try? await rtcSession?.close()
    rtcSession = nil
    rtcStream = nil
    whepAudioPlayer = nil
    #endif
  }
  //获取可用摄像头
  private func availableCameras() -> [[String: Any]] {
    let discovery = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTripleCamera],
      mediaType: .video,
      position: .unspecified
    )
    var cameras: [[String: Any]] = []
    for device in discovery.devices {
      var position = "external"
      switch device.position {
      case .front: position = "front"
      case .back: position = "back"
      case .unspecified: position = "external"
      @unknown default: position = "external"
      }
      cameras.append([
//        "cameraId": device.uniqueID,
        "name": device.uniqueID,
        "lensFacing": position,
        "sensorOrientation": 90
      ])
    }
    return cameras
  }
  
  private func prepareForVideoStreaming() async -> FlutterError? {
    guard let newMixer = mixer else {
      return FlutterError(code: "prepareForVideoStreamingError", message: "mixer empty", details: nil)
    }
    _ = newMixer // Capture is already prepared by initialize.
    return nil
  }

  //初始化 HaishinKit
  private func initialize(cameraId: String,enableAudio: Bool,resolution: String) async throws -> [String: Any]? {
    guard mixer == nil, rtmpStream == nil, texture == nil else { throw ConfigurationError.unsupported }
    await dispose()
    self.enableAudio = enableAudio
    rtmpConnection = RTMPConnection()
    if let connection = rtmpConnection{
      let stream = RTMPStream(connection: connection)
      if mixer == nil {
        mixer = MediaMixerHandler()
      }
      await mixer?.addOutput(stream, startRunning: false)
      rtmpStream = stream
      let recorder = StreamRecorder()
      await mixer?.addOutput(recorder, startRunning: true)
      recorderStream = recorder
      try await mixer?.attachAudio(isEnable: enableAudio)
      guard
        let size: CGSize = try await mixer?.attachVideo(resolution: resolution,cameraId: cameraId),
        let registry = registrar?.textures()
      else {
        return nil
      }
      if !explicitVideoSize { desiredVideoSettings.videoSize = size }
      try await applySettings(to: stream)
      let eventId = Int(bitPattern: ObjectIdentifier(self))
      if let texture {
        return [
          "textureId": texture.textureId,
          "eventId": eventId,
          "previewWidth": size.width,
          "previewHeight": size.height
        ]
      } else {
        let textureResult = HKStreamFlutterTexture(registry: registry)
        // ✅ 关键：设置初始尺寸
        textureResult.bounds = size  // 设置合理的默认值
        
        texture = textureResult
        mixer?.texture = textureResult
        await rtmpStream?.addOutput(textureResult)
        
        return [
          "textureId": texture?.textureId,
          "eventId": eventId,
          "previewWidth": size.width,
          "previewHeight": size.height
        ]
      }
    }else {
      return nil
    }
  }
  
  // 连接推流（RTMP / SRT / WHIP / WHEP）
  private func startVideoStreaming(
    url: String,
    frameRate: NSNumber,
    protocolName: String,
    isPlay: Bool?,
    whipToken: String?
  ) async -> FlutterError? {
    if let token = whipToken, !token.isEmpty {
      return FlutterError(code: "unsupportedOperation", message: "HaishinKit 2.2.5 cannot inject WHIP/WHEP Bearer headers", details: nil)
    }
    isPlayback = isPlay == true || protocolName == "whep"
    let protocolLower = protocolName.lowercased()
    switch protocolLower {
    case "rtsp", "udp":
      return FlutterError(
        code: "unsupportedProtocol",
        message: "StreamingProtocol.\(protocolLower) is not supported on iOS.",
        details: nil
      )
    case "whip":
      #if canImport(RTCHaishinKit)
      return await startRtcStreaming(
        url: url,
        frameRate: frameRate,
        mode: .publish,
        protocolName: "whip",
        whipToken: whipToken
      )
      #else
      return FlutterError(
        code: "unsupportedProtocol",
        message: "StreamingProtocol.whip requires RTCHaishinKit (Flutter SPM).",
        details: nil
      )
      #endif
    case "whep":
      #if canImport(RTCHaishinKit)
      return await startRtcStreaming(
        url: url,
        frameRate: frameRate,
        mode: .playback,
        protocolName: "whep",
        whipToken: whipToken
      )
      #else
      return FlutterError(
        code: "unsupportedProtocol",
        message: "StreamingProtocol.whep requires RTCHaishinKit (Flutter SPM).",
        details: nil
      )
      #endif
    case "srt":
      return await startSrtStreaming(url: url, frameRate: frameRate)
    case "rtmp":
      return await startRtmpStreaming(url: url, frameRate: frameRate, isPlay: isPlay)
    default:
      return FlutterError(
        code: "unsupportedProtocol",
        message: "Unknown protocol: \(protocolName)",
        details: nil
      )
    }
  }

  private func startRtmpStreaming(url: String, frameRate: NSNumber, isPlay: Bool?) async -> FlutterError? {
    do {
      currentProtocol = "rtmp"
      await tearDownSrtSession()
      await tearDownRtcSession()
      guard let newRtmpConnection = rtmpConnection else {
        return FlutterError(code: "startVideoStreamingError", message: "connect error", details: nil)
      }
      let uri = URL(string: url)
      let name = uri?.pathComponents.last
      var bits = url.components(separatedBy: "/")
      bits.removeLast()
      let newUrl = bits.joined(separator: "/")
      guard let newName = name else {
        return FlutterError(code: "startVideoStreamingError", message: "publish name error", details: nil)
      }
      if !isPlayback, let error = await setVideoSettings(
        bitrate: frameRate,
        width: nil,
        height: nil,
        frameInterval: nil,
        profileLevel: nil,
        expectedFrameRate: nil,
        bitRateMode: nil
      ) { return error }
      
      try await newRtmpConnection.connect(newUrl)
      guard let stream = rtmpStream else { throw ConfigurationError.invalidValue }
      if isPlay == true { _ = try await stream.play(newName) }
      else { _ = try await stream.publish(newName) }
      subscription = Task { [weak self] in
        for await status in await newRtmpConnection.status {
          guard let self, !Task.isCancelled else { return }
          if [RTMPConnection.Code.connectClosed.rawValue, RTMPConnection.Code.connectFailed.rawValue].contains(status.code) {
            self.emitEvent(["eventType": "rtmp_stopped", "errorDescription": "RTMP disconnected"])
            _ = await self.stopStreaming()
            return
          }
        }
      }
      emitEvent(["eventType": "success", "errorDescription": "Connected"])
      return nil
    } catch {
      _ = await stopStreaming()
      emitEvent(["eventType" : "rtmp_stopped",
                  "errorDescription" : "rtmp disconnected"])
      return FlutterError(code: "startVideoStreamingError", message: "catch error", details: nil)
    }
  }

  #if canImport(RTCHaishinKit)
  private func startRtcStreaming(
    url: String,
    frameRate: NSNumber,
    mode: SessionMode,
    protocolName: String,
    whipToken: String?
  ) async -> FlutterError? {
    do {
      currentProtocol = protocolName
      await tearDownRtcSession()
      await tearDownSrtSession()
      try? await rtmpConnection?.close()
      await ensureSessionFactoriesRegistered()

      // Token support is checked before creating or tearing down sessions.

      guard let sessionUrl = URL(string: url),
            let scheme = sessionUrl.scheme?.lowercased(),
            scheme == "http" || scheme == "https" else {
        return FlutterError(
          code: "startVideoStreamingError",
          message: "URL must be http:// or https:// for \(protocolName.uppercased())",
          details: nil
        )
      }

      guard let session = try await SessionBuilderFactory.shared.make(sessionUrl)
        .setMode(mode)
        .build() else {
        return FlutterError(
          code: "startVideoStreamingError",
          message: "Failed to build \(protocolName.uppercased()) session",
          details: nil
        )
      }

      let stream = await session.stream
      rtcSession = session
      rtcStream = stream

      if mode == .publish {
        try await applySettings(to: stream)
        await mixer?.addOutput(stream, startRunning: false)
        if let error = await setVideoSettings(
          bitrate: frameRate,
          width: nil,
          height: nil,
          frameInterval: nil,
          profileLevel: nil,
          expectedFrameRate: nil,
          bitRateMode: nil
        ) { await tearDownRtcSession(); return error }
      } else {
        if let texture {
          await stream.addOutput(texture)
        }
        let player = AudioPlayer(audioEngine: AVAudioEngine())
        whepAudioPlayer = player
        await stream.attachAudioPlayer(player)
      }

      sessionGeneration += 1
      let generation = sessionGeneration
      subscription = Task { [weak self] in
        guard let self else { return }
        for await readyState in await session.readyState {
          guard !Task.isCancelled, self.sessionGeneration == generation else { return }
          switch readyState {
          case .open:
            self.emitEvent(["eventType": "success",
                             "errorDescription": "connection success"])
          case .closed:
            self.emitEvent(["eventType": "rtmp_stopped",
                             "errorDescription": "\(protocolName) closed"])
          default:
            break
          }
        }
      }

      try await session.connect { [weak self] in
        Task { @MainActor in
          guard let self, self.sessionGeneration == generation else { return }
          self.emitEvent(["eventType": "rtmp_stopped", "errorDescription": "\(protocolName) disconnected"])
        }
      }
      rtcMonitor = Task { [weak self] in
        var connectedOnce = false
        let deadline = Date().addingTimeInterval(30)
        while !Task.isCancelled {
          try await Task.sleep(nanoseconds: 1_000_000_000)
          guard let self, !Task.isCancelled, self.sessionGeneration == generation else { return }
          if await session.connected { connectedOnce = true }
          else if connectedOnce || Date() >= deadline {
            self.emitEvent(["eventType": "rtmp_stopped", "errorDescription": "RTC connection lost or timed out"])
            await self.tearDownRtcSession()
            return
          }
        }
      }
      return nil
    } catch {
      emitEvent(["eventType": "rtmp_stopped",
                  "errorDescription": "\(protocolName) disconnected"])
      await tearDownRtcSession()
      return FlutterError(
        code: "startVideoStreamingError",
        message: error.localizedDescription,
        details: nil
      )
    }
  }
  #endif

  private func startSrtStreaming(url: String, frameRate: NSNumber) async -> FlutterError? {
    do {
      currentProtocol = "srt"
      await tearDownSrtSession()
      await tearDownRtcSession()
      try? await rtmpConnection?.close()

      guard url.lowercased().hasPrefix("srt") else {
        return FlutterError(
          code: "startVideoStreamingError",
          message: "URL must start with srt://",
          details: nil
        )
      }
      guard let parsed = SrtURLHelper.parse(url) else {
        return FlutterError(
          code: "startVideoStreamingError",
          message: "Invalid SRT URL. Use e.g. srt://host:10080?streamid=#!::r=live/livestream,m=publish",
          details: nil
        )
      }

      let connection = SRTConnection()
      let stream = SRTStream(connection: connection)
      srtConnection = connection
      srtStream = stream
      await mixer?.addOutput(stream, startRunning: false)

      if !isPlayback, let error = await setVideoSettings(
        bitrate: frameRate,
        width: nil,
        height: nil,
        frameInterval: nil,
        profileLevel: nil,
        expectedFrameRate: nil,
        bitRateMode: nil
      ) { await tearDownSrtSession(); return error }

      for option in parsed.preOptions {
        try await connection.setSocketOption(option)
      }
      try await connection.connect(parsed.connectURL)
      await stream.publish()
      subscription = monitorSrt(connection, destinationId: nil)
      emitEvent(["eventType": "success",
                 "errorDescription": "connection success"])
      return nil
    } catch {
      let message = Self.describeSrtError(error)
      emitEvent(["eventType": "rtmp_stopped",
                 "errorDescription": "srt disconnected: \(message)"])
      await tearDownSrtSession()
      return FlutterError(
        code: "startVideoStreamingError",
        message: message,
        details: nil
      )
    }
  }

  private func startMultiStreaming(
    destinations: [[String: Any]],
    frameRate: NSNumber
  ) async -> FlutterError? {
    guard !destinations.isEmpty else { return FlutterError(code: "invalidArgument", message: "No destinations", details: nil) }
    var ids = Set<String>()
    for (index, dest) in destinations.enumerated() {
      let proto = (dest["protocol"] as? String) ?? "rtmp"
      let id = (dest["id"] as? String) ?? "dest_\(index)"
      guard let url = dest["url"] as? String, let uri = URL(string: url),
            uri.host != nil, ["rtmp", "srt"].contains(proto),
            (proto == "rtmp" ? ["rtmp", "rtmps"].contains(uri.scheme ?? "") : uri.scheme == "srt"),
            !id.isEmpty, ids.insert(id).inserted else {
        return FlutterError(code: "invalidArgument", message: "Invalid destination URL, protocol or duplicate ID", details: id)
      }
    }
    await tearDownMultiEndpoints()
    await tearDownSrtSession()
    await tearDownRtcSession()
    try? await rtmpConnection?.close()
    desiredVideoSettings.bitRate = frameRate.intValue

    for (index, dest) in destinations.enumerated() {
      guard let url = dest["url"] as? String else {
        return FlutterError(code: "startMultiStreamingError", message: "url empty", details: nil)
      }
      let protocolName = ((dest["protocol"] as? String) ?? "rtmp").lowercased()
      if protocolName == "whip" || protocolName == "whep" || protocolName == "rtsp" || protocolName == "udp" {
        return FlutterError(
          code: "unsupportedProtocol",
          message: "StreamingProtocol.\(protocolName) is not allowed in iOS multi-streaming.",
          details: nil
        )
      }
      let id = (dest["id"] as? String) ?? "dest_\(index)"
      let endpoint = MultiEndpoint(id: id, protocolName: protocolName)
      multiEndpoints.append(endpoint)
      do {
        if protocolName == "srt" {
          guard let parsed = SrtURLHelper.parse(url) else {
            await tearDownMultiEndpoints()
            return FlutterError(
              code: "startMultiStreamingError",
              message: "Invalid SRT URL. Use e.g. srt://host:10080?streamid=#!::r=live/livestream,m=publish",
              details: nil
            )
          }
          let connection = SRTConnection()
          let stream = SRTStream(connection: connection)
          endpoint.srtConnection = connection
          endpoint.srtStream = stream
          try await applySettings(to: stream)
        await mixer?.addOutput(stream, startRunning: false)
          for option in parsed.preOptions {
            try await connection.setSocketOption(option)
          }
          try await connection.connect(parsed.connectURL)
          await stream.publish()
          endpoint.statusTask = monitorSrt(connection, destinationId: id)
        } else {
          guard let uri = URL(string: url), let name = uri.pathComponents.last else {
            await tearDownMultiEndpoints()
            return FlutterError(code: "startMultiStreamingError", message: "Invalid RTMP URL", details: nil)
          }
          var bits = url.components(separatedBy: "/")
          bits.removeLast()
          let connectUrl = bits.joined(separator: "/")
          let connection = RTMPConnection()
          let stream = RTMPStream(connection: connection)
          endpoint.rtmpConnection = connection
          endpoint.rtmpStream = stream
          try await applySettings(to: stream)
        await mixer?.addOutput(stream, startRunning: false)
          try await connection.connect(connectUrl)
          _ = try await stream.publish(name)
          endpoint.statusTask = Task { [weak self, weak endpoint] in
            for await status in await connection.status {
              guard !Task.isCancelled, let self, let endpoint else { return }
              if [RTMPConnection.Code.connectClosed.rawValue, RTMPConnection.Code.connectFailed.rawValue].contains(status.code) {
                self.emitEvent(["eventType": "rtmp_stopped", "destinationId": endpoint.id,
                  "errorDescription": "Destination disconnected"])
                _ = await self.stopStreamingDestination(id: endpoint.id)
                return
              }
            }
          }
        }
        emitEvent([
          "eventType": "success",
          "errorDescription": "connection success",
          "destinationId": id
        ])
      } catch {
        await tearDownMultiEndpoints()
        return FlutterError(
          code: "startMultiStreamingError",
          message: Self.describeSrtError(error),
          details: id
        )
      }
    }
    currentProtocol = "multi"
    return nil
  }

  private func monitorSrt(_ connection: SRTConnection, destinationId: String?) -> Task<(), Error> {
    Task { [weak self] in
      while !Task.isCancelled {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        guard let self, !Task.isCancelled else { return }
        let stateOption = SRTSocketOption.Name(rawValue: "state", symbol: SRTO_STATE, restriction: nil, type: .int32)
        let state = try? await connection.getSocketOption(stateOption)
        if state?.intValue != Int(SRTS_CONNECTED.rawValue) {
          var event: [String: Any] = ["eventType": "rtmp_stopped", "errorDescription": "SRT disconnected"]
          if let destinationId { event["destinationId"] = destinationId }
          self.emitEvent(event)
          if let destinationId { _ = await self.stopStreamingDestination(id: destinationId) }
          return
        }
      }
    }
  }

  private func stopStreamingDestination(id: String) async -> FlutterError? {
    guard let index = multiEndpoints.firstIndex(where: { $0.id == id }) else {
      return FlutterError(code: "stopStreamingDestinationError", message: "id not found", details: id)
    }
    let endpoint = multiEndpoints.remove(at: index)
    endpoint.statusTask?.cancel()
    if let stream = endpoint.srtStream {
      await mixer?.removeOutput(stream)
      _ = try? await stream.close()
    }
    try? await endpoint.srtConnection?.close()
    if let stream = endpoint.rtmpStream {
      await mixer?.removeOutput(stream)
      _ = try? await stream.close()
    }
    try? await endpoint.rtmpConnection?.close()
    if multiEndpoints.isEmpty {
      currentProtocol = "rtmp"
      emitEvent(["eventType": "rtmp_stopped", "errorDescription": "All destinations stopped"])
    }
    return nil
  }

  //录制本地视频
  private func startVideoRecording(filePath: String) async -> FlutterError?{
    do{
      guard let newRecorderStream = recorderStream else { return FlutterError(code: "startVideoRecordingError", message: "recorder Stream error", details: nil)}
      guard !isRecording else { return FlutterError(code: "alreadyRecording", message: "Recording is active", details: nil) }
      guard desiredVideoSettings.bitRateMode == .average else {
        return FlutterError(code: "unsupportedOperation", message: "Recording supports average bit rate mode only", details: nil)
      }
      var settings = StreamRecorder.defaultSettings
      var compression: [String: any Sendable] = [
        AVVideoAverageBitRateKey: desiredVideoSettings.bitRate,
        AVVideoMaxKeyFrameIntervalDurationKey: Int(desiredVideoSettings.maxKeyFrameIntervalDuration),
        AVVideoProfileLevelKey: desiredVideoSettings.profileLevel
      ]
      if let frameRate = desiredVideoSettings.expectedFrameRate {
        compression[AVVideoExpectedSourceFrameRateKey] = frameRate
      }
      settings[.video]?[AVVideoWidthKey] = Int(desiredVideoSettings.videoSize.width)
      settings[.video]?[AVVideoHeightKey] = Int(desiredVideoSettings.videoSize.height)
      settings[.video]?[AVVideoCodecKey] = desiredVideoSettings.profileLevel.contains("HEVC") ? AVVideoCodecType.hevc : AVVideoCodecType.h264
      settings[.video]?[AVVideoCompressionPropertiesKey] = compression
      settings[.audio]?[AVEncoderBitRateKey] = desiredAudioSettings.bitRate
      if !enableAudio { settings.removeValue(forKey: .audio) }
      let errors = await newRecorderStream.error
      try await newRecorderStream.startRecording(URL(fileURLWithPath: filePath), settings: settings)
      isRecording = true
      recorderErrors?.cancel()
      recorderErrors = Task { [weak self] in
        for await error in errors {
          guard !Task.isCancelled, let self else { return }
          _ = await self.stopVideoRecording()
          self.emitEvent(["eventType": "recording_stopped", "errorDescription": String(describing: error)])
          return
        }
      }
      return nil
    }catch{
      return FlutterError(code: "startVideoRecordingError", message: "catch error", details: nil)
    }
  }
  //停止录制
  private func stopVideoRecording()async->FlutterError?{
    guard isRecording else { return nil }
    recorderErrors?.cancel()
    recorderErrors = nil
    do{
      guard let newRecorderStream = recorderStream else { return FlutterError(code: "stopVideoRecordingError", message: "recorder Stream error", details: nil)}
      _ = try await newRecorderStream.stopRecording()
      isRecording = false
      return nil
    }catch{
      isRecording = await recorderStream?.isRecording ?? false
      return FlutterError(code: "stopVideoRecordingError", message: error.localizedDescription, details: nil)
    }
  }
  //直播与录制到本地
  private func startVideoRecordingAndStreaming(
    filePath: String,
    url: String,
    frameRate: NSNumber,
    protocolName: String,
    whipToken: String?
  ) async -> FlutterError? {
    do {
      let startVideoStreamingRes = await startVideoStreaming(
        url: url,
        frameRate: frameRate,
        protocolName: protocolName,
        isPlay: nil,
        whipToken: whipToken
      )
      if startVideoStreamingRes != nil {
        return startVideoStreamingRes
      }
      let startVideoRecordingRes = await startVideoRecording(filePath: filePath)
      if startVideoRecordingRes != nil {
        _ = await stopStreaming()
        return startVideoRecordingRes
      }
      return nil
    } catch {
      return FlutterError(code: "startVideoRecordingAndStreamingError", message: "catch error", details: nil)
    }
  }
  // 停止直播与录制到本地
  private func stopVideoRecordingOrStreaming()async -> FlutterError?{
    let stopStreamingRes = await stopStreaming()
    if(stopStreamingRes != nil){
      return stopStreamingRes
    }
    let stopVideoRecordingRes = await stopVideoRecording()
    if(stopVideoRecordingRes != nil){
      return stopVideoRecordingRes
    }
    return nil
  }
  //暂停直播
  private func pauseStream()async->FlutterError?{
    do{
      guard isPlayback && currentProtocol == "rtmp", let newRtmpStream = rtmpStream else { return FlutterError(code: "unsupportedOperation", message: "rtmp Stream error", details: nil)}
      _ = try await newRtmpStream.pause(true)
      return nil
    }catch{
      return FlutterError(code: "pauseStreamError", message: "catch error", details: nil)
    }
  }
  //恢复直播
  private func resumeStream()async->FlutterError?{
    do{
      guard isPlayback && currentProtocol == "rtmp", let newRtmpStream = rtmpStream else { return FlutterError(code: "unsupportedOperation", message: "rtmp Stream error", details: nil)}
      _ = try await newRtmpStream.pause(false)
      return nil
    }catch{
      return FlutterError(code: "resumeStream", message: "catch error", details: nil)
    }
  }
  //开启闪光灯 只有后摄像头有
  private func onFlashLight() -> FlutterError? {
    
    do {
      guard let device = mixer?.activeVideoDevice, device.hasTorch else {
        
        return FlutterError(code: "onFlashLight", message: "device error", details: nil)
      }
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      return nil
    } catch {
      return FlutterError(code: "onFlashLight", message: "catch error", details: nil)
    }
  }
  //关闭闪光灯 只有后摄像头有
  private func offFlashLight() -> FlutterError? {
    
    do {
      guard let device = mixer?.activeVideoDevice, device.hasTorch else { return FlutterError(code: "offFlashLight", message: "device error", details: nil) }
      try device.lockForConfiguration()
      device.torchMode = .off
      device.unlockForConfiguration()
      return nil
    } catch {  return FlutterError(code: "offFlashLight", message: "catch error", details: nil) }
  }
  // 拍照
  private func takePicture(filePath: String) async -> FlutterError? {
    guard let texture = texture else {
      return FlutterError(code: "takePictureError", message: "Texture not initialized", details: nil)
    }
    
    guard let image = texture.getCurrentImage() else {
      return FlutterError(code: "takePictureError", message: "Failed to capture image", details: nil)
    }
    
    guard let imageData = image.jpegData(compressionQuality: 1.0) else {
      return FlutterError(code: "takePictureError", message: "Failed to convert image to JPEG", details: nil)
    }
    
    do {
      let url = URL(fileURLWithPath: filePath)
      let directory = url.deletingLastPathComponent()
      
      // 确保目录存在
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
      
      // 保存图片
      try imageData.write(to: url)
      return nil
    } catch {
      return FlutterError(code: "IOError", message: "Failed saving image: \(error.localizedDescription)", details: nil)
    }
  }
  
  //获取直播流信息
  private func getStreamStatistics() async -> [String: Any?] {
    let first = multiEndpoints.first
    let activeRtmp = currentProtocol == "multi" ? first?.rtmpStream : (currentProtocol == "rtmp" ? rtmpStream : nil)
    let activeSrt = currentProtocol == "multi" ? first?.srtStream : (currentProtocol == "srt" ? srtStream : nil)
    var active: (any StreamConvertible)? = activeRtmp
    if let activeSrt { active = activeSrt }
    #if canImport(RTCHaishinKit)
    if currentProtocol == "whip" || currentProtocol == "whep" { active = rtcStream }
    #endif
    guard let active else { return [:] }
    let settings = await active.videoSettings
    let hasAudio = await mixer?.getHasAudio() ?? true
    let hasVideo = await mixer?.getHasVideo() ?? true
    var stats: [String: Any?] = [
      "width": Int(settings.videoSize.width), "height": Int(settings.videoSize.height),
      "bitrate": settings.bitRate, "isAudioMuted": !hasAudio, "isVideoMuted": !hasVideo
    ]
    if let activeRtmp {
      let info = await activeRtmp.info
      stats["fps"] = await activeRtmp.currentFPS
      stats["bytesSend"] = info.byteCount
      stats["bytesOutPerSecond"] = info.currentBytesPerSecond
    }
    let connection = currentProtocol == "multi" ? first?.srtConnection : srtConnection
    if activeSrt != nil, let connection, let performance = await connection.performanceData {
      stats["bytesSend"] = Int64(clamping: performance.byteSentTotal)
      stats["queueBytesOut"] = Int(performance.byteSndBuf)
      stats["rttMicros"] = Int(performance.msRTT * 1000)
    }
    return stats
  }
  //设置音频
  private func configuredStreams() -> [any StreamConvertible] {
    var streams: [any StreamConvertible] = []
    if let stream = rtmpStream { streams.append(stream) }
    if let stream = srtStream { streams.append(stream) }
    #if canImport(RTCHaishinKit)
    if let stream = rtcStream, currentProtocol != "whep" { streams.append(stream) }
    #endif
    for endpoint in multiEndpoints {
      if let stream = endpoint.rtmpStream { streams.append(stream) }
      if let stream = endpoint.srtStream { streams.append(stream) }
    }
    return streams
  }

  private func applySettings(to stream: any StreamConvertible) async throws {
    try await stream.setVideoSettings(desiredVideoSettings)
    var audio = await stream.audioSettings
    audio.bitRate = desiredAudioSettings.bitRate
    try await stream.setAudioSettings(audio)
  }

  private func setAudioSettings(bitrate: NSNumber) async -> FlutterError? {
    guard bitrate.intValue > 0 else { return FlutterError(code: "invalidArgument", message: "bitrate must be positive", details: nil) }
    do {
      var settings = desiredAudioSettings
      settings.bitRate = bitrate.intValue
      for stream in configuredStreams() {
        var audio = await stream.audioSettings
        audio.bitRate = settings.bitRate
        try await stream.setAudioSettings(audio)
      }
      desiredAudioSettings = settings
      return nil
    } catch {
      return FlutterError(code: "setAudioSettingsError", message: error.localizedDescription, details: nil)
    }
  }

  private func setVideoSettings(
    bitrate: NSNumber?, width: NSNumber?, height: NSNumber?, frameInterval: NSNumber?,
    profileLevel: String?, expectedFrameRate: NSNumber?, bitRateMode: String?
  ) async -> FlutterError? {
    do {
      var settings = desiredVideoSettings
      if let bitrate {
        guard bitrate.intValue > 0 else { throw ConfigurationError.invalidValue }
        settings.bitRate = bitrate.intValue
      }
      guard (width == nil) == (height == nil) else { throw ConfigurationError.invalidValue }
      if let width, let height {
        guard width.intValue > 0, height.intValue > 0, width.intValue % 2 == 0, height.intValue % 2 == 0 else { throw ConfigurationError.invalidValue }
        settings.videoSize = CGSize(width: width.intValue, height: height.intValue)
      }
      if let frameInterval {
        guard frameInterval.intValue > 0 else { throw ConfigurationError.invalidValue }
        settings.maxKeyFrameIntervalDuration = frameInterval.int32Value
      }
      if let profileLevel {
        guard let profile = ProfileLevel(rawValue: profileLevel) else { throw ConfigurationError.invalidValue }
        settings.profileLevel = profile.kVTProfileLevel
      }
      if let expectedFrameRate {
        guard expectedFrameRate.doubleValue.isFinite, expectedFrameRate.doubleValue > 0 else { throw ConfigurationError.invalidValue }
        settings.expectedFrameRate = expectedFrameRate.doubleValue
      }
      if let bitRateMode {
        switch bitRateMode {
        case "average": settings.bitRateMode = .average
        case "constant":
          if #available(iOS 16.0, *) { settings.bitRateMode = .constant }
          else { throw ConfigurationError.unsupported }
        case "variable":
          if #available(iOS 26.0, *) { settings.bitRateMode = .variable }
          else { throw ConfigurationError.unsupported }
        default: throw ConfigurationError.invalidValue
        }
      }
      for stream in configuredStreams() { try await stream.setVideoSettings(settings) }
      desiredVideoSettings = settings
      if width != nil { explicitVideoSize = true }
      return nil
    } catch {
      return FlutterError(code: "setVideoSettingsError", message: error.localizedDescription, details: nil)
    }
  }

  private enum ConfigurationError: Error { case invalidValue, unsupported }

  #if os(iOS)
  private func setMultitaskingCameraAccessEnabled(enabled: Bool) async -> FlutterError? {
    guard let newMixer = mixer else {
      return FlutterError(code: "setMultitaskingCameraAccessEnabledError", message: "mixer empty", details: nil)
    }
    if #available(iOS 17.0, *) {
      if await newMixer.setMultitaskingCameraAccessEnabled(enabled) { return nil }
      return FlutterError(code: "unsupportedOperation", message: "This device does not support multitasking camera access", details: nil)
    }
    return FlutterError(code: "setMultitaskingCameraAccessEnabledError", message: "Requires iOS 17+", details: nil)
  }
  #endif
  private static func supportsHevcEncoder() -> Bool {
    guard #available(iOS 17.4, *) else { return false }
    var properties: CFDictionary?
    let specification = [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary
    return VTCopySupportedPropertyDictionaryForEncoder(width: 1280, height: 720,
      codecType: kCMVideoCodecType_HEVC, encoderSpecification: specification,
      encoderIDOut: nil, supportedPropertiesOut: &properties) == noErr
  }

  private func cameraControl(_ call: FlutterMethodCall) -> Any? {
    guard let device = mixer?.activeVideoDevice else {
      return FlutterError(code: "noCamera", message: "No active capture device", details: nil)
    }
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      switch call.method {
      case "getCameraControls":
        return ["zoom": device.videoZoomFactor, "minZoom": device.minAvailableVideoZoomFactor,
          "maxZoom": device.maxAvailableVideoZoomFactor,
          "autoFocus": device.focusMode != .locked, "exposure": Int(device.exposureTargetBias),
          "torch": device.torchMode == .on]
      case "setManualExposure":
        if args["iso"] == nil || args["iso"] is NSNull {
          guard args["exposureTimeNanos"] == nil || args["exposureTimeNanos"] is NSNull,
            device.isExposureModeSupported(.continuousAutoExposure) else { throw ConfigurationError.invalidValue }
          device.exposureMode = .continuousAutoExposure
        } else {
          guard device.isExposureModeSupported(.custom), let iso = args["iso"] as? NSNumber,
            let nanos = args["exposureTimeNanos"] as? NSNumber,
            iso.floatValue >= device.activeFormat.minISO, iso.floatValue <= device.activeFormat.maxISO,
            nanos.int64Value > 0 else { throw ConfigurationError.invalidValue }
          let duration = CMTime(value: nanos.int64Value, timescale: 1_000_000_000)
          guard CMTimeCompare(duration, device.activeFormat.minExposureDuration) >= 0,
            CMTimeCompare(duration, device.activeFormat.maxExposureDuration) <= 0 else { throw ConfigurationError.invalidValue }
          device.setExposureModeCustom(duration: duration, iso: iso.floatValue)
        }
      case "setZoom":
        guard let n = args["zoom"] as? NSNumber, n.doubleValue.isFinite,
          CGFloat(n.doubleValue) >= device.minAvailableVideoZoomFactor,
          CGFloat(n.doubleValue) <= device.maxAvailableVideoZoomFactor else { throw ConfigurationError.invalidValue }
        device.videoZoomFactor = CGFloat(n.doubleValue)
      case "setAutoFocus":
        guard let enabled = args["enabled"] as? Bool else { throw ConfigurationError.invalidValue }
        let mode: AVCaptureDevice.FocusMode = enabled ? .continuousAutoFocus : .locked
        guard device.isFocusModeSupported(mode) else { throw ConfigurationError.unsupported }
        device.focusMode = mode
      case "tapToFocus", "tapToMeter":
        let x = (args["x"] as? NSNumber)?.doubleValue ?? 0.5
        let y = (args["y"] as? NSNumber)?.doubleValue ?? 0.5
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { throw ConfigurationError.invalidValue }
        let point = mixer?.captureDevicePoint(x: x, y: y) ?? CGPoint(x: x, y: y)
        if call.method == "tapToFocus" {
          guard device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) else { return false }
          device.focusPointOfInterest = point
          device.focusMode = .autoFocus
        } else {
          guard (args["mode"] as? String ?? "exposure") == "exposure",
            device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) else { return false }
          device.exposurePointOfInterest = point
          device.exposureMode = .continuousAutoExposure
        }
        return true
      case "lockExposure", "unlockExposure":
        let mode: AVCaptureDevice.ExposureMode = call.method == "lockExposure" ? .locked : .continuousAutoExposure
        guard device.isExposureModeSupported(mode) else { throw ConfigurationError.unsupported }
        device.exposureMode = mode
        return call.method == "lockExposure" ? true : nil
      case "isExposureLocked": return device.exposureMode == .locked
      case "lockWhiteBalance", "unlockWhiteBalance":
        let mode: AVCaptureDevice.WhiteBalanceMode = call.method == "lockWhiteBalance" ? .locked : .continuousAutoWhiteBalance
        guard device.isWhiteBalanceModeSupported(mode) else { throw ConfigurationError.unsupported }
        device.whiteBalanceMode = mode
        return call.method == "lockWhiteBalance" ? true : nil
      case "isWhiteBalanceLocked": return device.whiteBalanceMode == .locked
      default: throw ConfigurationError.unsupported
      }
      return nil
    } catch {
      return FlutterError(code: "cameraControlError", message: error.localizedDescription, details: call.method)
    }
  }

  //方法句柄
  // MARK: FlutterPlugin
  private var pendingCalls: [(FlutterMethodCall, FlutterResult)] = []
  private var handlingCall = false

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    pendingCalls.append((call, result))
    drainCalls()
  }

  private func drainCalls() {
    guard !handlingCall, !pendingCalls.isEmpty else { return }
    handlingCall = true
    let (call, callback) = pendingCalls.removeFirst()
    perform(call) { [weak self] value in
      DispatchQueue.main.async {
        callback(value)
        self?.handlingCall = false
        self?.drainCalls()
      }
    }
  }

  private func perform(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initializePlayback":
      Task {
        guard mixer == nil, rtmpStream == nil, texture == nil, let registry = registrar?.textures() else {
          result(FlutterError(code: "sessionBusy", message: "Dispose the active camera/player before initializing playback", details: nil))
          return
        }
        let connection = RTMPConnection()
        rtmpConnection = connection
        let stream = RTMPStream(connection: connection)
        rtmpStream = stream
        let output = HKStreamFlutterTexture(registry: registry)
        output.bounds = CGSize(width: 1280, height: 720)
        output.videoGravity = .resizeAspect
        texture = output
        await stream.addOutput(output)
        let player = AudioPlayer(audioEngine: AVAudioEngine())
        playbackAudioPlayer = player
        await stream.attachAudioPlayer(player)
        result(["textureId": output.textureId, "eventId": Int(bitPattern: ObjectIdentifier(self))])
      }
    case "startPlayback":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let url = args["url"] as? String,
        let proto = args["protocol"] as? String, ["rtmp", "whep"].contains(proto),
        mixer == nil, texture != nil else {
        result(FlutterError(code: "invalidState", message: "Initialize PlayerController before playback", details: nil))
        return
      }
      Task { result(await startVideoStreaming(url: url, frameRate: 0,
        protocolName: proto, isPlay: true, whipToken: args["whipToken"] as? String)) }
    case "setPlaybackMuted":
      guard isPlayback, let args = call.arguments as? [String: Any], let muted = args["muted"] as? Bool else {
        result(FlutterError(code: "invalidState", message: "No active playback", details: nil)); return
      }
      Task {
        let sound = SoundTransform(volume: muted ? 0 : 1)
        if currentProtocol == "rtmp" { await rtmpStream?.setSoundTransform(sound) }
        #if canImport(RTCHaishinKit)
        if currentProtocol == "whep" { await rtcStream?.setSoundTransform(sound) }
        #endif
        result(nil)
      }
    case "getCapabilities":
      Task {
        let device = mixer?.activeVideoDevice
        let multi = await mixer?.supportsMultitasking() ?? false
        result([
          "backend": "HaishinKit/2.2.5 (SPM)",
          "protocols": ["rtmp", "srt", "whip", "whep"],
          "videoCodecs": Self.supportsHevcEncoder() ? ["h264", "h265"] : ["h264"], "audioCodecs": ["aac", "opus"],
          "features": ["recordingPause": false, "zoom": device != nil,
            "focus": device?.isFocusModeSupported(.autoFocus) ?? false,
            "torch": device?.hasTorch ?? false, "overlays": true, "filters": false,
            "screenCapture": false, "uvc": false, "pcmInput": false,
            "whipBearerToken": false, "playback": true, "playbackPause": true,
            "multitaskingCameraAccess": multi, "rtmpPing": false,
            "captureTelemetry": device != nil,
            "manualExposure": device?.isExposureModeSupported(.custom) ?? false,
            "bitRateMode": true, "microphoneDetach": false]
        ])
      }
    case "setVideoCodec":
      let args = call.arguments as? [String: Any] ?? [:]
      guard !isRecording else { result(FlutterError(code: "invalidState", message: "Stop recording before changing codecs", details: nil)); return }
      let name = args["name"] as? String
      guard name == "h264" || (name == "h265" && Self.supportsHevcEncoder()) else {
        result(FlutterError(code: "unsupportedCodec", message: "This device exposes H264/H265 encoding only", details: nil)); return
      }
      Task {
        var settings = desiredVideoSettings
        settings.profileLevel = name == "h265" ? kVTProfileLevel_HEVC_Main_AutoLevel as String : kVTProfileLevel_H264_Baseline_AutoLevel as String
        do {
          for stream in configuredStreams() { try await stream.setVideoSettings(settings) }
          desiredVideoSettings = settings
          result(nil)
        } catch { result(FlutterError(code: "setVideoCodecError", message: error.localizedDescription, details: nil)) }
      }
    case "setAudioCodec":
      let args = call.arguments as? [String: Any] ?? [:]
      result(args["name"] as? String == "aac" ? nil : FlutterError(code: "unsupportedCodec", message: "iOS selects AAC for RTMP/SRT and Opus for WHIP automatically", details: nil))
    case "setCaptureTelemetry":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let enabled = args["enabled"] as? Bool,
        let interval = args["intervalMs"] as? NSNumber, interval.intValue >= 100 else {
        result(FlutterError(code: "invalidArgument", message: "Telemetry interval must be at least 100ms", details: nil)); return
      }
      telemetryTimer?.invalidate()
      telemetryTimer = nil
      if enabled {
        guard mixer?.activeVideoDevice != nil else {
          result(FlutterError(code: "noCamera", message: "Telemetry requires a capture device", details: nil)); return
        }
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: interval.doubleValue / 1000, repeats: true) { [weak self] _ in
          Task { @MainActor in
          guard let self, let device = self.mixer?.activeVideoDevice else { return }
          let duration = CMTimeGetSeconds(device.exposureDuration)
          guard duration.isFinite, duration >= 0 else { return }
          self.emitEvent(["eventType": "capture_statistics", "captureStatistics": [
            "iso": device.iso,
            "exposureTimeNanos": Int64(duration * 1_000_000_000),
            "focusLensPosition": device.lensPosition
          ]])
          }
        }
      }
      result(nil)
    case "setManualExposure":
      result(cameraControl(call))
    case "getCameraControls", "setZoom", "setAutoFocus", "tapToFocus",
         "lockExposure", "unlockExposure", "isExposureLocked", "lockWhiteBalance",
         "unlockWhiteBalance", "isWhiteBalanceLocked", "tapToMeter":
      result(cameraControl(call))
    case "availableCameras":
      do{
        result(availableCameras())
      }catch{
        result(FlutterError(
          code: "availableCamerasError",
          message: "availableCameras catch error",
          details: nil
        ))
      }
    case "initialize":
      guard mixer == nil, rtmpStream == nil, texture == nil else {
        result(FlutterError(code: "sessionBusy", message: "Dispose the current session before reinitializing", details: nil)); return
      }
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let enableAudio = arguments["enableAudio"] as? Bool,
          let resolution = arguments["resolutionPreset"] as? String,
          let cameraId = arguments["cameraName"] as? String else {
          result(FlutterError(code: "invalidArgument", message: "cameraName, resolutionPreset and enableAudio are required", details: nil))
          return
        }
        Task {
          do {
            let res = try await initialize(cameraId: cameraId, enableAudio: enableAudio, resolution: resolution)
            guard let res else { throw ConfigurationError.invalidValue }
            result(res)
          } catch {
            await dispose()
            result(FlutterError(code: "initializeError", message: error.localizedDescription, details: nil))
          }   // 返回给 Flutter
          
        }
      }catch{
        result(FlutterError(
          code: "initializeError",
          message: "initialize catch error",
          details: nil
        ))
      }
      
    case "prepareForVideoStreaming":
      Task {
        let res = await prepareForVideoStreaming()
        result(res)
      }
    case "takePicture":
      guard
        let arguments = call.arguments as? [String: Any?],
        let filePath = arguments["path"] as? String else {
        result(FlutterError(code: "takePictureError", message: "Must specify a filePath.", details: nil))
        return
      }
      
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: filePath) {
        result(FlutterError(
          code: "fileExists",
          message: "File at path '\(filePath)' already exists. Cannot overwrite.",
          details: nil
        ))
        return
      }
      
      Task {
        let error = await takePicture(filePath: filePath)
        result(error)
      }
    case "pauseVideoRecording":
      result(FlutterError(code: "pauseVideoRecordingError", message: "pauseVideoRecording unrealized", details: nil))
    case "resumeVideoRecording":
      result(FlutterError(code: "resumeVideoRecordingError", message: "resumeVideoRecording unrealized", details: nil))
    case "startVideoRecording":
      guard
        let arguments = call.arguments as? [String: Any?],
        let filePath = arguments["filePath"] as? String else {
        result(FlutterError(code: "startVideoRecordingError", message: "Must specify a filePath.", details: nil))
        return
      }
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: filePath) {
        result(FlutterError(
          code: "startVideoRecordingError",
          message: "File at path '\(filePath)' already exists. Cannot overwrite.",
          details: nil
        ))
        return
      }
      Task{
        let res = await startVideoRecording(filePath: filePath)
        result(res)
      }
    case "stopRecording":
      Task{
        let res = await stopVideoRecording()
        result(res)
      }
    case "startVideoRecordingAndStreaming":
      guard
        let arguments = call.arguments as? [String: Any?],
        let filePath = arguments["filePath"] as? String,
        let url = arguments["url"] as? String,
        let bitrate = arguments["bitrate"] as? NSNumber else {
        result(FlutterError(code: "startVideoRecordingAndStreamingError", message: "params Empty", details: nil))
        return
      }
      let protocolName = (arguments["protocol"] as? String) ?? "rtmp"
      let whipToken = arguments["whipToken"] as? String
      let fileManager = FileManager.default
      if fileManager.fileExists(atPath: filePath) {
        result(FlutterError(
          code: "startVideoRecordingAndStreamingError",
          message: "File at path '\(filePath)' already exists. Cannot overwrite.",
          details: nil
        ))
        return
      }
      Task{
        let res = await startVideoRecordingAndStreaming(
          filePath: filePath,
          url: url,
          frameRate: bitrate,
          protocolName: protocolName,
          whipToken: whipToken
        )
        result(res)
      }
    case "stopRecordingOrStreaming":
      Task{
        let res = await stopVideoRecordingOrStreaming()
        result(res)
      }
    case "startVideoStreaming":
      guard
        let arguments = call.arguments as? [String: Any?],
        let url = arguments["url"] as? String,
        let bitrate = arguments["bitrate"] as? NSNumber else {
        result(FlutterError(
          code: "startVideoStreamingError",
          message: "url empty",
          details: nil
        ))
        return
      }
      let protocolName = (arguments["protocol"] as? String) ?? "rtmp"
      let whipToken = arguments["whipToken"] as? String
      Task {
        let res = await startVideoStreaming(
          url: url,
          frameRate: bitrate,
          protocolName: protocolName,
          isPlay: arguments["isPlay"] as? Bool,
          whipToken: whipToken
        )
        result(res)
      }
      
    case "stopStreaming":
      //停止直播
      Task{
        let res = await stopStreaming()
        result(res)
      }
    case "pauseStream":
      Task{
        let res = await pauseStream()
        result(res)
      }
    case "resumeStream":
      Task{
        let res = await resumeStream()
        result(res)
      }
    case "switchCamera":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let cameraId = arguments["cameraName"] as? String else {
          result(FlutterError(
            code: "switchCameraError",
            message: "cameraId empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "switchCameraError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          do { _ = try await newMixer.attachVideo(resolution: nil, cameraId: cameraId); result(nil) }
          catch { result(FlutterError(code: "switchCameraError", message: error.localizedDescription, details: nil)) }
        }
      }catch{
        result(FlutterError(
          code: "switchCameraError",
          message: "catch error",
          details: nil
        ))
      }
    case "switchAudio":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let isEnable = arguments["isEnable"] as? Bool else {
          result(FlutterError(
            code: "switchAudioError",
            message: "isEnable empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "switchAudioError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          await newMixer.setHasAudio(hasAudio: isEnable)
          result(nil)
        }
      }catch{
        result(FlutterError(
          code: "switchAudioError",
          message: "catch error",
          details: nil
        ))
      }
    case "switchFlashLight":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let isEnable = arguments["isEnable"] as? Bool else {
          result(FlutterError(
            code: "switchFlashLightError",
            message: "isEnable empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "switchFlashLightError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          if(isEnable){
            let res = onFlashLight()
            result(res)
          }else{
            let res = offFlashLight()
            result(res)
          }
        }
      }catch{
        result(FlutterError(
          code: "switchFlashLightError",
          message: "catch error",
          details: nil
        ))
      }
    case "getStreamStatistics":
      Task{
        let res = await getStreamStatistics()
        result(res)
      }
    case "setAudioSettings":
      guard
        let arguments = call.arguments as? [String: Any?],
        let bitrate = arguments["bitrate"] as? NSNumber else {
        result(FlutterError(
          code: "setAudioSettingsError",
          message: "arguments empty",
          details: nil
        ))
        return
      }
      Task{
        let res = await setAudioSettings(bitrate: bitrate)
        result(res)
      }
    case "setVideoSettings":
      guard
        let arguments = call.arguments as? [String: Any?] else {
        result(FlutterError(
          code: "setVideoSettingsError",
          message: "arguments empty",
          details: nil
        ))
        return
      }
      Task{
        let res = await setVideoSettings(
          bitrate: arguments["bitrate"] as? NSNumber,
          width: arguments["width"] as? NSNumber,
          height: arguments["height"] as? NSNumber,
          frameInterval: arguments["frameInterval"] as? NSNumber,
          profileLevel: arguments["profileLevel"] as? String,
          expectedFrameRate: arguments["expectedFrameRate"] as? NSNumber,
          bitRateMode: arguments["bitRateMode"] as? String
        )
        result(res)
      }
    case "setMultitaskingCameraAccessEnabled":
      #if os(iOS)
      guard
        let arguments = call.arguments as? [String: Any?],
        let enabled = arguments["enabled"] as? Bool else {
        result(FlutterError(
          code: "setMultitaskingCameraAccessEnabledError",
          message: "enabled missing",
          details: nil
        ))
        return
      }
      Task {
        let res = await setMultitaskingCameraAccessEnabled(enabled: enabled)
        result(res)
      }
      #else
      result(FlutterMethodNotImplemented)
      #endif
    case "getHasAudio":
      do{
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "getHasAudioError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          let res = await newMixer.getHasAudio()
          result(res)
        }
      }catch{
        result(FlutterError(
          code: "getHasAudioError",
          message: "catch error",
          details: nil
        ))
      }
    case "setHasAudio":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let isEnable = arguments["isEnable"] as? Bool else {
          result(FlutterError(
            code: "setHasAudioError",
            message: "isEnable empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "setHasAudioError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          await newMixer.setHasAudio(hasAudio: isEnable)
          result(nil)
        }
      }catch{
        result(FlutterError(
          code: "setHasAudioError",
          message: "catch error",
          details: nil
        ))
      }
    case "getHasVideo":
      do{
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "getHasVideoError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          let res = await newMixer.getHasVideo()
          result(res)
        }
      }catch{
        result(FlutterError(
          code: "getHasVideoError",
          message: "catch error",
          details: nil
        ))
      }
    case "setHasVideo":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let isEnable = arguments["isEnable"] as? Bool else {
          result(FlutterError(
            code: "setHasVideoError",
            message: "isEnable empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "setHasVideoError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          await newMixer.setHasVideo(hasVideo: isEnable)
          result(nil)
        }
      }catch{
        result(FlutterError(
          code: "setHasVideoError",
          message: "catch error",
          details: nil
        ))
      }
    case "setFrameRate":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let frameRate = arguments["frameRate"] as? NSNumber else {
          result(FlutterError(
            code: "setFrameRateError",
            message: "frameRate empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "setFrameRateError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          do { try await newMixer.setFrameRate(frameRate: frameRate); result(nil) }
          catch { result(FlutterError(code: "setFrameRateError", message: error.localizedDescription, details: nil)) }
        }
      }catch{
        result(FlutterError(
          code: "setFrameRateError",
          message: "catch error",
          details: nil
        ))
      }
    case "setCapturePreset":
      guard let args = call.arguments as? [String: Any], let preset = args["preset"] as? String,
        ["low", "medium", "high", "veryHigh", "ultraHigh", "max"].contains(preset),
        let mixer, let device = mixer.activeVideoDevice, !isRecording else {
        result(FlutterError(code: "invalidState", message: "An idle camera and valid preset are required", details: nil)); return
      }
      Task {
        do {
          let size = try await mixer.attachVideo(resolution: preset, cameraId: device.uniqueID)
          var settings = desiredVideoSettings
          settings.videoSize = size
          for stream in configuredStreams() { try await stream.setVideoSettings(settings) }
          desiredVideoSettings = settings
          explicitVideoSize = false
          texture?.bounds = size
          result(nil)
        } catch { result(FlutterError(code: "setCapturePresetError", message: error.localizedDescription, details: nil)) }
      }
    case "setSessionPreset":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let sessionPreset = arguments["sessionPreset"] as? String else {
          result(FlutterError(
            code: "setSessionPresetError",
            message: "sessionPreset empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "setSessionPresetError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          do { try await newMixer.setSessionPreset(sessionPreset: sessionPreset); result(nil) }
          catch { result(FlutterError(code: "setSessionPresetError", message: error.localizedDescription, details: nil)) }
        }
      }catch{
        result(FlutterError(
          code: "setSessionPresetError",
          message: "catch error",
          details: nil
        ))
      }
    case "setScreenSettings":
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let width = arguments["width"] as? NSNumber,
          let height = arguments["height"] as? NSNumber else {
          result(FlutterError(
            code: "setScreenSettingsError",
            message: "width and height empty",
            details: nil
          ))
          return
        }
        guard
          let newMixer = mixer else{
          result(FlutterError(
            code: "setScreenSettingsError",
            message: "mixer empty",
            details: nil
          ))
          return
        }
        Task{
          await newMixer.setScreenSettings(width: width, height: height)
          result(nil)
        }
      }catch{
        result(FlutterError(
          code: "setScreenSettingsError",
          message: "catch error",
          details: nil
        ))
      }
    case "setOverlayText":
      guard
        let arguments = call.arguments as? [String: Any?],
        let text = arguments["text"] as? String,
        let mixer else {
        result(FlutterError(code: "setOverlayTextError", message: "params empty", details: nil))
        return
      }
      let fontSize = (arguments["fontSize"] as? NSNumber)?.doubleValue ?? 22
      let colorArgb: UInt32 = {
        if let n = arguments["colorArgb"] as? NSNumber {
          return UInt32(truncatingIfNeeded: n.int64Value)
        }
        return 0xFFFF0000
      }()
      let position = arguments["position"] as? String
      let scale = (arguments["scale"] as? NSNumber)?.doubleValue ?? 100
      Task {
        do {
          try await mixer.setOverlayText(
            text: text,
            fontSize: CGFloat(fontSize),
            colorArgb: colorArgb,
            position: position,
            scale: CGFloat(scale)
          )
          result(nil)
        } catch {
          result(FlutterError(code: "setOverlayTextError", message: error.localizedDescription, details: nil))
        }
      }
    case "setOverlayImage":
      guard
        let arguments = call.arguments as? [String: Any?],
        let filePath = arguments["filePath"] as? String,
        let mixer else {
        result(FlutterError(code: "setOverlayImageError", message: "params empty", details: nil))
        return
      }
      let position = arguments["position"] as? String
      let scale = (arguments["scale"] as? NSNumber)?.doubleValue ?? 100
      Task {
        do {
          try await mixer.setOverlayImage(filePath: filePath, position: position, scale: CGFloat(scale))
          result(nil)
        } catch {
          result(FlutterError(code: "setOverlayImageError", message: error.localizedDescription, details: nil))
        }
      }
    case "clearOverlay":
      guard let mixer else {
        result(FlutterError(code: "clearOverlayError", message: "mixer empty", details: nil))
        return
      }
      Task {
        await mixer.clearOverlay()
        result(nil)
      }
    case "startMultiStreaming":
      guard
        let arguments = call.arguments as? [String: Any?],
        let destinations = arguments["destinations"] as? [[String: Any]],
        let bitrate = arguments["bitrate"] as? NSNumber else {
        result(FlutterError(code: "startMultiStreamingError", message: "params empty", details: nil))
        return
      }
      Task {
        let res = await startMultiStreaming(destinations: destinations, frameRate: bitrate)
        result(res)
      }
    case "stopStreamingDestination":
      guard
        let arguments = call.arguments as? [String: Any?],
        let id = arguments["id"] as? String else {
        result(FlutterError(code: "stopStreamingDestinationError", message: "id empty", details: nil))
        return
      }
      Task {
        let res = await stopStreamingDestination(id: id)
        result(res)
      }
    case "dispose":
      Task{
        await dispose()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}


extension HaishinKitPlugin: @preconcurrency FlutterStreamHandler {
  // MARK: FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

