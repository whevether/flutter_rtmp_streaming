import Foundation
#if canImport(Flutter)
import Flutter
#endif
#if canImport(FlutterMacOS)
import FlutterMacOS
#endif
import HaishinKit
import RTMPHaishinKit
import AVFoundation
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

final class MediaMixerHandler: NSObject {
  var texture: HKStreamFlutterTexture?
  private lazy var mixer = MediaMixer(multiTrackAudioMixingEnabled: false)
  private var overlayObject: ScreenObject?
  private var screenConfiguredForOverlay = false
  
  override init() {
    super.init()
#if canImport(UIKit)
    NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
#endif
  }
  
  func addOutput(_ output: any MediaMixerOutput, startRunning: Bool = false) async {
    await mixer.addOutput(output)
    if startRunning {
      await mixer.startRunning()
    }
  }

  func removeOutput(_ output: any MediaMixerOutput) async {
    await mixer.removeOutput(output)
  }
  
  func stopRunning() {
    Task {
      await mixer.stopCapturing()
      await mixer.stopRunning()
    }
  }
  
  func dispose()  async{
    await clearOverlay()
    stopRunning()
    _ = try? await mixer.attachVideo(nil, track: 0)
    _ = try? await mixer.attachAudio(nil, track: 0)
  }
  
#if canImport(UIKit)
  @objc
  private func on(_ notification: Notification) {
    
    var orientation: AVCaptureVideoOrientation?
    
    if #available(iOS 13.0, *) {
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
        orientation = DeviceUtil.videoOrientation(by: windowScene.interfaceOrientation)
      }
    } else {
      orientation = DeviceUtil.videoOrientation(by: UIApplication.shared.statusBarOrientation)
    }
    
    guard let videoOrientation = orientation else { return}
    Task { await mixer.setVideoOrientation(videoOrientation) }
  }
#endif
  // 获取是否开启了声音
  func getHasAudio() async -> Bool{
    let isMuted = await !mixer.audioMixerSettings.isMuted
    return isMuted
  }
  //关闭/开启 声音
  func setHasAudio(hasAudio: Bool?) async {
    if(hasAudio == nil){
      return
    }
    var audioMixerSettings = await mixer.audioMixerSettings
    audioMixerSettings.isMuted = !hasAudio!
    await mixer.setAudioMixerSettings(audioMixerSettings)
  }
  //获取是否有视频
  func getHasVideo()async ->Bool{
    let hasVideo = await !mixer.videoMixerSettings.isMuted
    return hasVideo
  }
  // 关闭/开启 视频
  func setHasVideo(hasVideo: Bool?)async{
    if(hasVideo == nil){
      return
    }
    var videoMixerSettings = await mixer.videoMixerSettings
    videoMixerSettings.isMuted = !hasVideo!
    await mixer.setVideoMixerSettings(videoMixerSettings)
  }
  //设置帧速率
  func setFrameRate(frameRate: NSNumber?) async{
    if(frameRate == nil){
      return
    }
    _ = try? await mixer.setFrameRate(frameRate!.doubleValue)
  }
  //设置分辨率
  func setSessionPreset(sessionPreset: String?) async{
    let preset: AVCaptureSession.Preset = switch sessionPreset {
    case "high": .high
    case "medium": .medium
    case "low": .low
    case "hd1280x720": .hd1280x720
    case "hd1920x1080": .hd1920x1080
    case "hd4K3840x2160": .hd4K3840x2160
    case "vga640x480": .vga640x480
    case "iFrame960x540": .iFrame960x540
    case "iFrame1280x720": .iFrame1280x720
    case "cif352x288": .cif352x288
    default: .hd1280x720
    }
    await mixer.setSessionPreset(preset)
  }
  //附加音频到直播
  func attachAudio(isEnable: Bool?)async{
    if (isEnable == nil || isEnable == false) {
      try? await mixer.attachAudio(nil)
    } else {
      try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
    }
    
  }
  //设置屏幕大小
  @ScreenActor
  func setScreenSettings(width: NSNumber?,height: NSNumber?)->Int64? {
    if(width == nil || height == nil){
      return nil
    }
    mixer.screen.size = CGSize(width: CGFloat(width!.floatValue), height: CGFloat(height!.floatValue))
    return texture?.textureId
  }
  
  /// 与 Android 对齐：同一 resolutionPreset 使用相同的 session preset 与目标分辨率
  private static func sessionPresetString(for resolution: String) -> String? {
    switch resolution {
    case "low": return "cif352x288"
    case "medium": return "vga640x480"
    case "high": return "hd1280x720"
    case "veryHigh": return "hd1920x1080"
    case "ultraHigh": return "hd4K3840x2160"
    case "max": return nil
    default: return "hd1280x720"
    }
  }

  /// 与 Android 对齐：统一目标分辨率 (width x height, landscape)
  private static func targetSize(for resolution: String, device: AVCaptureDevice?) -> CGSize {
    switch resolution {
    case "low": return CGSize(width: 352, height: 288)
    case "medium": return CGSize(width: 640, height: 480)
    case "high": return CGSize(width: 1280, height: 720)
    case "veryHigh": return CGSize(width: 1920, height: 1080)
    case "ultraHigh": return CGSize(width: 3840, height: 2160)
    case "max":
      if let device = device {
        let dimensions = device.activeFormat.highResolutionStillImageDimensions
        return CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
      }
      return CGSize(width: 1920, height: 1080)
    default: return CGSize(width: 1280, height: 720)
    }
  }

  //附加视频到直播
  func attachVideo(resolution: String?, cameraId: String?)async ->CGSize{
    if cameraId == nil {
      try? await mixer.attachVideo(nil, track: 0)
      return .zero
    }
#if os(iOS)
    guard let device = AVCaptureDevice(uniqueID: cameraId!) else { return .zero }
#else
    guard let device = AVCaptureDevice.devices(for: .video).first else { return .zero }
#endif
    try? await mixer.attachVideo(device, track: 0)
    guard let resolution = resolution else { return .zero }

    if let presetString = Self.sessionPresetString(for: resolution) {
      await setSessionPreset(sessionPreset: presetString)
    }
    return Self.targetSize(for: resolution, device: device)
  }

#if os(iOS)
  /// HaishinKit 2.2.5+：分屏、画中画等场景下保持相机采集（需设备支持 `isMultitaskingCameraAccessSupported`）。
  /// 通过 `MediaMixer.configuration` 写入底层 `AVCaptureSession`（iOS 17+ 与 HaishinKit API 一致）。
  func setMultitaskingCameraAccessEnabled(_ enabled: Bool) async {
    if #available(iOS 17.0, *) {
      await mixer.configuration { session in
        if session.isMultitaskingCameraAccessSupported {
          session.isMultitaskingCameraAccessEnabled = enabled
        }
      }
    }
  }
#endif

  private func ensureOverlayScreenConfigured() async {
    guard !screenConfiguredForOverlay else { return }
    var videoMixerSettings = await mixer.videoMixerSettings
    videoMixerSettings.mode = .offscreen
    await mixer.setVideoMixerSettings(videoMixerSettings)
    let size = await mixer.screen.size
    if size == .zero {
      await mixer.screen.size = CGSize(width: 720, height: 1280)
    }
    screenConfiguredForOverlay = true
  }

  private func applyPosition(_ object: ScreenObject, position: String?) {
    switch position {
    case "topLeft":
      object.horizontalAlignment = .left
      object.verticalAlignment = .top
    case "topRight":
      object.horizontalAlignment = .right
      object.verticalAlignment = .top
    case "bottomLeft":
      object.horizontalAlignment = .left
      object.verticalAlignment = .bottom
    case "bottomRight":
      object.horizontalAlignment = .right
      object.verticalAlignment = .bottom
    default:
      object.horizontalAlignment = .center
      object.verticalAlignment = .middle
    }
  }

  func setOverlayText(
    text: String,
    fontSize: CGFloat,
    colorArgb: UInt32,
    position: String?,
    scale: CGFloat
  ) async throws {
    await ensureOverlayScreenConfigured()
    if let existing = overlayObject {
      try? await mixer.screen.removeChild(existing)
      overlayObject = nil
    }
    let textObject = TextScreenObject()
    textObject.string = text
    let uiColor = Self.uiColor(argb: colorArgb)
    textObject.attributes = [
      .font: UIFont.boldSystemFont(ofSize: fontSize),
      .foregroundColor: uiColor
    ]
    let dim = max(scale * 2, 40)
    textObject.size = CGSize(width: dim * 4, height: dim)
    applyPosition(textObject, position: position)
    try await mixer.screen.addChild(textObject)
    overlayObject = textObject
  }

  func setOverlayImage(filePath: String, position: String?, scale: CGFloat) async throws {
    await ensureOverlayScreenConfigured()
    if let existing = overlayObject {
      try? await mixer.screen.removeChild(existing)
      overlayObject = nil
    }
    guard let image = UIImage(contentsOfFile: filePath)?.cgImage else {
      throw NSError(domain: "setOverlayImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
    }
    let imageObject = ImageScreenObject()
    imageObject.cgImage = image
    let w = max(scale * 2, 40)
    imageObject.size = CGSize(width: w, height: w)
    applyPosition(imageObject, position: position)
    try await mixer.screen.addChild(imageObject)
    overlayObject = imageObject
  }

  func clearOverlay() async {
    if let existing = overlayObject {
      try? await mixer.screen.removeChild(existing)
      overlayObject = nil
    }
  }

  private static func uiColor(argb: UInt32) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xff) / 255.0
    let r = CGFloat((argb >> 16) & 0xff) / 255.0
    let g = CGFloat((argb >> 8) & 0xff) / 255.0
    let b = CGFloat(argb & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a == 0 ? 1 : a)
  }
}
