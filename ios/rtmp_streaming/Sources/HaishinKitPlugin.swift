#if canImport(Flutter)
import Flutter
#endif
#if canImport(FlutterMacOS)
import FlutterMacOS
#endif
import HaishinKit
import RTMPHaishinKit
import AVFoundation

public final class HaishinKitPlugin: NSObject,FlutterPlugin {
  private static let instance = HaishinKitPlugin()
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    instance.registrar = registrar
    let channel = FlutterMethodChannel(name: "com.rtmp_streaming", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let id = Int(bitPattern: ObjectIdentifier(instance))
    print("id: \(id)")
    let eventChannel = FlutterEventChannel(name: "com.rtmp_streaming.eventchannel/\(id)", binaryMessenger: registrar.messenger())
    
    eventChannel.setStreamHandler(instance)
  }
  
  //  private var handlers: [Int: MethodCallHandler] = [:]
  //
  private(set) var mixer: MediaMixerHandler? {
    didSet {
      oldValue?.stopRunning()
    }
  }
  //订阅消息
  private var subscription: Task<(), Error>? {
    didSet {
      oldValue?.cancel()
    }
  }
  //事件
  private var eventSink: FlutterEventSink?
  //  //事件渠道
  //  private var eventChannel: FlutterEventChannel?
  //纹理
  private var texture: HKStreamFlutterTexture?
  //连接
  private var rtmpConnection: RTMPConnection?
  // rtmpStream直播 流
  private var rtmpStream: RTMPStream?
  // 录制流
  private var recorderStream: StreamRecorder?
  //重试次数
  private var retries: Int = 0
  private var enableAudio: Bool = true
  // 插件注册
  private(set) var registrar: FlutterPluginRegistrar?
  
  //销毁所有
  private func dispose()async{
    subscription = nil
    rtmpConnection = nil
    if let newRtmpStream = rtmpStream {
      mixer?.removeOutput(newRtmpStream)
      if let texture {
        registrar?.textures().unregisterTexture(texture.textureId)
        self.texture = nil
      }
      if let newRecorderStream = recorderStream{
        mixer?.removeOutput(newRecorderStream)
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
      subscription = nil
      try? await rtmpConnection?.close()
      _  = try? await rtmpStream?.close()
      return nil
    }catch{
      return FlutterError(code: "closeConnect Error", message: "catch error", details: nil)
    }
    
  }
  //publish
  private func publish(name: String) async{
    _ = try? await rtmpStream?.publish(name)
  }
  // play
  private func play(url: String) async{
    _ = try? await rtmpStream?.play(url)
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
    if enableAudio {
      await newMixer.attachAudio(isEnable: true)
    }
    return nil
  }

  //初始化 HaishinKit
  private func initialize(cameraId: String,enableAudio: Bool,resolution: String) async ->[String: Any]?{
    self.enableAudio = enableAudio
    rtmpConnection = RTMPConnection()
    if let connection = rtmpConnection{
      let stream = RTMPStream(connection: connection)
      if mixer == nil {
        mixer = MediaMixerHandler()
      }
      mixer?.addOutput(stream,startRunning: false)
      rtmpStream = stream
      let recorder = StreamRecorder()
      mixer?.addOutput(recorder,startRunning: true)
      recorderStream = recorder
      await mixer?.attachAudio(isEnable: enableAudio)
      guard
        let size: CGSize = await mixer?.attachVideo(resolution: resolution,cameraId: cameraId),
        let registry = registrar?.textures()
      else {
        return nil
      }
      let eventId = Int(bitPattern: ObjectIdentifier(self))
      if let texture {
        return [
          "textureId": texture.textureId,
          "eventId": eventId,
          "previewWidth": size.width,
          "previewHeight": size.height
        ]
      } else {
        print("size \(size.width),\(size.height)")
        let textureResult = HKStreamFlutterTexture(registry: registry)
        // ✅ 关键：设置初始尺寸
        textureResult.bounds = size  // 设置合理的默认值
        
        texture = textureResult
        mixer?.texture = textureResult
        await rtmpStream?.addOutput(textureResult)
        print("textureId ssss \(texture?.textureId)")
        
        print("id111: \(eventId)")
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
  
  // 连接 rtmp
  private func startVideoStreaming(url: String,frameRate: NSNumber, isPlay: Bool?) async -> FlutterError?{
    do {
      guard let newRtmpConnection = rtmpConnection else { return FlutterError(code: "startVideoStreamingError", message: "connect error", details: nil)}
      //订阅连接状态事件
      let uri = URL(string: url)
      let name = uri?.pathComponents.last
      var bits = url.components(separatedBy: "/")
      bits.removeLast()
      let newUrl = bits.joined(separator: "/")
      guard
        let newName = name as? String else {
        return FlutterError(code: "startVideoStreamingError", message: "publish name error", details: nil)
      }
      subscription = Task { [weak self] in
        guard let self else { return }
        for await status in await newRtmpConnection.status {
          print("connect status: \(status.code)")
          switch status.code {
          case RTMPConnection.Code.connectSuccess.rawValue:
            // 在主线程执行 UI 更新
            //            await MainActor.run {
            if let isPlay {
              Task { await self.play(url: newName) }
            } else {
              Task { await self.publish(name: newName) }
            }
            self.eventSink?(["eventType": "success",
                             "errorDescription": "connection success"])
            //            }
            
          case RTMPConnection.Code.connectFailed.rawValue:
            guard retries <= 3 else {
              //              await MainActor.run {
              self.eventSink?(["eventType": "error",
                               "errorDescription": "connection failed " + status.code])
              //              }
              return
            }
            retries += 1
            // 异步延迟，避免阻塞主线程
            try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
            try await newRtmpConnection.connect(newUrl)
            //            await MainActor.run {
            self.eventSink?(["eventType": "rtmp_retry",
                             "errorDescription": "connection failed " + status.code])
            //            }
          case RTMPConnection.Code.connectClosed.rawValue:
            self.eventSink?(["eventType": "camera_closing",
                             "errorDescription": "connection error " + status.code])
          default:
            self.eventSink?(["eventType": "error",
                             "errorDescription": "connection error " + status.code])
            break
          }
        }
      }
      await setVideoSettings(
        bitrate: frameRate,
        width: nil,
        height: nil,
        frameInterval: nil,
        profileLevel: nil,
        expectedFrameRate: nil,
        bitRateMode: nil
      )
      
      try await newRtmpConnection.connect(newUrl)
      return nil
    }catch {
      eventSink?(["eventType" : "rtmp_stopped",
                  "errorDescription" : "rtmp disconnected"])
      return FlutterError(code: "startVideoStreamingError", message: "catch error", details: nil)
    }
  }
  //录制本地视频
  private func startVideoRecording(filePath: String) async -> FlutterError?{
    do{
      guard let newRecorderStream = recorderStream else { return FlutterError(code: "startVideoRecordingError", message: "recorder Stream error", details: nil)}
      _ = try await newRecorderStream.startRecording(URL(fileURLWithPath: filePath))
      print("startVideoRecording:\(filePath)")
      return nil
    }catch{
      return FlutterError(code: "startVideoRecordingError", message: "catch error", details: nil)
    }
  }
  //停止录制
  private func stopVideoRecording()async->FlutterError?{
    do{
      guard let newRecorderStream = recorderStream else { return FlutterError(code: "stopVideoRecordingError", message: "recorder Stream error", details: nil)}
      _ = try await newRecorderStream.stopRecording()
      return nil
    }catch{
      print("stopVideoRecordingError",error)
      return FlutterError(code: "stopVideoRecordingError", message: "catch error", details: nil)
    }
  }
  //直播与录制到本地
  private func startVideoRecordingAndStreaming(filePath : String,url:String,frameRate: NSNumber)async ->FlutterError?{
    do{
      let startVideoStreamingRes = await startVideoStreaming(url: url,frameRate: frameRate, isPlay: nil)
      if(startVideoStreamingRes != nil){
        return startVideoStreamingRes
      }
      let startVideoRecordingRes = await startVideoRecording(filePath: filePath)
      if(startVideoRecordingRes != nil){
        return startVideoRecordingRes
      }
      return nil
    }catch{
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
      guard let newRtmpStream = rtmpStream else { return FlutterError(code: "pauseStreamError", message: "rtmp Stream error", details: nil)}
      _ = try await newRtmpStream.pause(true)
      return nil
    }catch{
      print("pauseStream",error)
      return FlutterError(code: "pauseStreamError", message: "catch error", details: nil)
    }
  }
  //恢复直播
  private func resumeStream()async->FlutterError?{
    do{
      guard let newRtmpStream = rtmpStream else { return FlutterError(code: "resumeStreamError", message: "rtmp Stream error", details: nil)}
      _ = try await newRtmpStream.pause(false)
      return nil
    }catch{
      print("resumeStream",error)
      return FlutterError(code: "resumeStream", message: "catch error", details: nil)
    }
  }
  //开启闪光灯 只有后摄像头有
  private func onFlashLight() -> FlutterError? {
    
    do {
      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), device.hasTorch else {
        
        return FlutterError(code: "onFlashLight", message: "device error", details: nil)
      }
      try device.lockForConfiguration()
      try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      device.unlockForConfiguration()
      return nil
    } catch {
      return FlutterError(code: "onFlashLight", message: "catch error", details: nil)
    }
  }
  //关闭闪光灯 只有后摄像头有
  private func offFlashLight() -> FlutterError? {
    
    do {
      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), device.hasTorch else { return FlutterError(code: "offFlashLight", message: "device error", details: nil) }
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
    do{
      guard let newRtmpStream = rtmpStream, let newTexture = texture else{
        return [:]
      }
      let info = await newRtmpStream.info
      let currentFps = await newRtmpStream.currentFPS
      let bitRate = await newRtmpStream.videoSettings.bitRate
      let hasAudio = await mixer?.getHasAudio() ?? true
      let hasVideo = await mixer?.getHasVideo() ?? true
      return [
        "fps": currentFps,
        "cacheSize": info.byteCount,
        "width": newTexture.bounds.width,
        "height": newTexture.bounds.height,
        "bitrate": bitRate > 0 ? bitRate : info.currentBytesPerSecond * 8,
        "bytesSend": info.byteCount,
        "sentAudioFrames": nil,
        "sentVideoFrames": nil,
        "droppedAudioFrames": nil,
        "droppedVideoFrames": nil,
        "isAudioMuted": !hasAudio,
        "isVideoMuted": !hasVideo
      ]
    }catch{
      return [:]
    }
  }
  //设置音频
  private func setAudioSettings(bitrate: NSNumber) async -> FlutterError?{
    do{
      guard let newRtmpStream = rtmpStream else { return FlutterError(code: "setAudioSettingsError", message: "rtmp Stream error", details: nil)}
      var audioSettings = await newRtmpStream.audioSettings
      audioSettings.bitRate = bitrate.intValue
      _ = try? await newRtmpStream.setAudioSettings(audioSettings)
      return nil
    }catch{
      return FlutterError(code: "setAudioSettingsError", message: "catch error", details: nil)
    }
  }
  //设置视频（含 HaishinKit 2.2.1+ 码率模式、2.2.2+ expectedFrameRate → RTMP onMetaData framerate）
  private func setVideoSettings(
    bitrate: NSNumber?,
    width: NSNumber?,
    height: NSNumber?,
    frameInterval: NSNumber?,
    profileLevel: String?,
    expectedFrameRate: NSNumber?,
    bitRateMode: String?
  ) async -> FlutterError? {
    do {
      guard let newRtmpStream = rtmpStream else {
        return FlutterError(code: "setVideoSettingsError", message: "rtmp Stream error", details: nil)
      }
      var videoSettings = await newRtmpStream.videoSettings
      if let bitrate {
        videoSettings.bitRate = bitrate.intValue
      }
      if let width, let height {
        videoSettings.videoSize = CGSize(width: .init(width.intValue), height: .init(height.intValue))
      }
      if let frameInterval {
        videoSettings.maxKeyFrameIntervalDuration = frameInterval.int32Value
      }
      if let profileLevel {
        videoSettings.profileLevel = ProfileLevel(rawValue: profileLevel)?.kVTProfileLevel ?? ProfileLevel.H264_Baseline_AutoLevel.kVTProfileLevel
      }
      if let expectedFrameRate {
        videoSettings.expectedFrameRate = expectedFrameRate.doubleValue
      }
      if let bitRateMode {
        switch bitRateMode.lowercased() {
        case "average":
          videoSettings.bitRateMode = .average
        case "constant":
          if #available(iOS 16.0, *) {
            videoSettings.bitRateMode = .constant
          } else {
            return FlutterError(code: "setVideoSettingsError", message: "constant bit rate requires iOS 16+", details: nil)
          }
        case "variable":
          if #available(iOS 26.0, *) {
            videoSettings.bitRateMode = .variable
          } else {
            return FlutterError(code: "setVideoSettingsError", message: "variable bit rate requires iOS 26+", details: nil)
          }
        default:
          break
        }
      }
      try await newRtmpStream.setVideoSettings(videoSettings)
      return nil
    } catch {
      return FlutterError(code: "setVideoSettingsError", message: error.localizedDescription, details: nil)
    }
  }

  #if os(iOS)
  private func setMultitaskingCameraAccessEnabled(enabled: Bool) async -> FlutterError? {
    guard let newMixer = mixer else {
      return FlutterError(code: "setMultitaskingCameraAccessEnabledError", message: "mixer empty", details: nil)
    }
    if #available(iOS 17.0, *) {
      await newMixer.setMultitaskingCameraAccessEnabled(enabled)
      return nil
    }
    return FlutterError(code: "setMultitaskingCameraAccessEnabledError", message: "Requires iOS 17+", details: nil)
  }
  #endif
  //方法句柄
  // MARK: FlutterPlugin
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
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
      
      do{
        guard
          let arguments = call.arguments as? [String: Any?],
          let enableAudio = arguments["enableAudio"] as? Bool,
          let resolution = arguments["resolutionPreset"] as? String,
          let cameraId = arguments["cameraName"] as? String else {
          result(nil)
          return
        }
        Task {
          print("enableAudio \(enableAudio)")
          print("resolution \(resolution)")
          //        print("cameraId \(arguments["cameraId"] as? String)")
          
          let res = await initialize(cameraId: cameraId, enableAudio: enableAudio, resolution: resolution)
          result(res)   // 返回给 Flutter
          
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
        let res = await startVideoRecordingAndStreaming(filePath: filePath, url: url,frameRate: bitrate)
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
      Task {
        print("connect Url \(url)")
        let res = await startVideoStreaming(url: url,frameRate: bitrate ,isPlay: arguments["isPlay"] as? Bool)
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
          await newMixer.attachVideo(resolution: nil, cameraId: cameraId)
          result(nil)
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
          await newMixer.attachAudio(isEnable: isEnable)
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
          await newMixer.setFrameRate(frameRate: frameRate)
          result(nil)
        }
      }catch{
        result(FlutterError(
          code: "setFrameRateError",
          message: "catch error",
          details: nil
        ))
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
          await newMixer.setSessionPreset(sessionPreset: sessionPreset)
          result(nil)
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
    case "getPlatformVersion":
      result(kHaishinKitIdentifier)
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


extension HaishinKitPlugin: FlutterStreamHandler {
  // MARK: FlutterStreamHandler
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil
  }
}

