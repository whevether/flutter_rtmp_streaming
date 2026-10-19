import Foundation
#if canImport(Flutter)
import Flutter
#endif
import HaishinKit
import RTMPHaishinKit
import AVFoundation
import VideoToolbox
#if canImport(UIKit)
import UIKit
#endif

final class MediaMixerHandler: NSObject {
  enum CameraSetupError: Error { case noDevice, invalidValue }
  private(set) var activeVideoDevice: AVCaptureDevice?
  var texture: HKStreamFlutterTexture?
  private lazy var mixer = MediaMixer(multiTrackAudioMixingEnabled: false)
  private var overlayObject: ScreenObject?
  private var screenConfiguredForOverlay = false
  private var lastCaptureSize: CGSize = .zero
  private var explicitCanvas: CGSize?
  
  override init() {
    super.init()
#if canImport(UIKit)
    NotificationCenter.default.addObserver(self, selector: #selector(on(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
#endif
  }
  
  deinit { NotificationCenter.default.removeObserver(self) }

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
    await mixer.stopCapturing()
    await mixer.stopRunning()
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
    
    guard let videoOrientation = orientation else { return }
    Task { [weak self] in
      await self?.applyOrientation(videoOrientation)
    }
    // `windowScene.interfaceOrientation` can lag the physical rotation when the
    // device is held at an angle (the interface only settles once the device is
    // flat or clearly oriented). Re-apply shortly after so the preview canvas
    // ends up matching the settled interface orientation.
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 600_000_000)
      guard let self else { return }
      await self.applyOrientation(Self.currentInterfaceOrientation())
    }
  }

  /// Idempotently aligns the mixer orientation, preview texture canvas and —
  /// when the overlay is active — the offscreen canvas, to `orientation`.
  private func applyOrientation(_ videoOrientation: AVCaptureVideoOrientation) async {
    await mixer.setVideoOrientation(videoOrientation)
    if screenConfiguredForOverlay {
      // Keep offscreen canvas matched to interface orientation while overlay
      // is active, unless the app pinned an explicit canvas size.
      if explicitCanvas == nil {
        await Self.applyOverlayScreenGeometry(
          mixer: mixer,
          texture: texture,
          orientation: videoOrientation
        )
      }
    } else if (texture?.bounds.width ?? 0) > 1 {
      // Keep the preview texture canvas matched to the new orientation so the
      // Flutter-side preview does not squeeze portrait frames into a
      // landscape texture (and vice versa).
      texture?.bounds = await orientedCaptureSize()
    }
  }
#endif

  /// Map a normalized aspect-fill preview point to the unrotated sensor space.
  func captureDevicePoint(x: Double, y: Double) -> CGPoint {
    let portrait = Self.isPortrait(Self.currentInterfaceOrientation())
    let source = portrait ? CGSize(width: lastCaptureSize.height, height: lastCaptureSize.width) : lastCaptureSize
    let viewport = texture?.bounds ?? source
    guard source.width > 0, source.height > 0, viewport.width > 0, viewport.height > 0 else { return CGPoint(x: x, y: y) }
    let scale = max(viewport.width / source.width, viewport.height / source.height)
    var px = (CGFloat(x) * viewport.width + (source.width * scale - viewport.width) / 2) / (source.width * scale)
    let py = (CGFloat(y) * viewport.height + (source.height * scale - viewport.height) / 2) / (source.height * scale)
    if activeVideoDevice?.position == .front { px = 1 - px }
    switch Self.currentInterfaceOrientation() {
    case .portrait: return CGPoint(x: py, y: 1 - px)
    case .portraitUpsideDown: return CGPoint(x: 1 - py, y: px)
    case .landscapeLeft: return CGPoint(x: 1 - px, y: 1 - py)
    default: return CGPoint(x: px, y: py)
    }
  }

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
  func setFrameRate(frameRate: NSNumber?) async throws {
    if(frameRate == nil){
      return
    }
    guard frameRate!.doubleValue.isFinite, frameRate!.doubleValue > 0 else { throw CameraSetupError.invalidValue }
    try await mixer.setFrameRate(frameRate!.doubleValue)
  }
  //设置分辨率
  func setSessionPreset(sessionPreset: String?) async throws {
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
    default: throw CameraSetupError.invalidValue
    }
    try await mixer.configuration { session in
      guard session.canSetSessionPreset(preset) else { throw CameraSetupError.invalidValue }
    }
    await mixer.setSessionPreset(preset)
  }
  //附加音频到直播
  func attachAudio(isEnable: Bool?) async throws {
    if (isEnable == nil || isEnable == false) {
      try await mixer.attachAudio(nil)
    } else {
      guard let device = AVCaptureDevice.default(for: .audio) else { throw CameraSetupError.noDevice }
      try await mixer.attachAudio(device)
    }
    
  }
  //设置屏幕大小
  @ScreenActor
  func setScreenSettings(width: NSNumber?,height: NSNumber?)->Int64? {
    if(width == nil || height == nil){
      return nil
    }
    let size = CGSize(width: CGFloat(width!.floatValue), height: CGFloat(height!.floatValue))
    guard size.width > 0, size.height > 0 else { return nil }
    explicitCanvas = size
    mixer.screen.size = size
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
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        return CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
      }
      return CGSize(width: 1920, height: 1080)
    default: return CGSize(width: 1280, height: 720)
    }
  }

  //附加视频到直播
  func attachVideo(resolution: String?, cameraId: String?) async throws -> CGSize {
    if cameraId == nil {
      try await mixer.attachVideo(nil, track: 0)
      return .zero
    }
#if os(iOS)
    guard let device = AVCaptureDevice(uniqueID: cameraId!) else { throw CameraSetupError.noDevice }
#else
    guard let device = AVCaptureDevice.devices(for: .video).first else { throw CameraSetupError.noDevice }
#endif
#if canImport(UIKit)
    // A fresh MediaMixer defaults to portrait and attachVideo applies that to
    // the capture connection. When the camera is (re)initialized while the
    // interface is already landscape, no orientation notification follows, so
    // the preview would stay rotated in a landscape texture until the device
    // moves again.
    let orientation = await MainActor.run { Self.currentInterfaceOrientation() }
    await mixer.setVideoOrientation(orientation)
#endif
    try await mixer.attachVideo(device, track: 0)
    activeVideoDevice = device
    guard let resolution = resolution else { return lastCaptureSize }

    if let presetString = Self.sessionPresetString(for: resolution) {
      try await setSessionPreset(sessionPreset: presetString)
    } else if resolution == "max" {
      guard let format = device.formats.filter({ format in
        format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
      }).max(by: { lhs, rhs in
        let a = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
        let b = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
        return Int64(a.width) * Int64(a.height) < Int64(b.width) * Int64(b.height)
      }) else { throw CameraSetupError.invalidValue }
      await mixer.setSessionPreset(.inputPriority)
      try device.lockForConfiguration()
      device.activeFormat = format
      device.unlockForConfiguration()
    }
    let size = Self.targetSize(for: resolution, device: device)
    lastCaptureSize = size
    return await orientedCaptureSize()
  }

  /// The canonical capture size oriented to the current interface orientation.
  ///
  /// `lastCaptureSize` is always landscape (long x short). Portrait interfaces
  /// get the sides swapped so both the Flutter preview texture and the encoded
  /// stream match what the user sees on screen.
  func orientedCaptureSize() async -> CGSize {
    let base = lastCaptureSize
    guard base.width > 1, base.height > 1 else { return base }
#if canImport(UIKit)
    let isPortrait = await MainActor.run { Self.interfaceIsPortrait() }
    let shortSide = min(base.width, base.height)
    let longSide = max(base.width, base.height)
    return isPortrait
      ? CGSize(width: shortSide, height: longSide)
      : CGSize(width: longSide, height: shortSide)
#else
    return base
#endif
  }

#if canImport(UIKit)
  /// Whether the interface is currently portrait.
  ///
  /// Preferred source is the key window's bounds: they settle exactly when the
  /// layout rotates, whereas `windowScene.interfaceOrientation` can lag the
  /// physical rotation and report a stale value mid-transition.
  private static func interfaceIsPortrait() -> Bool {
    if #available(iOS 15.0, *),
       let scene = UIApplication.shared.connectedScenes.first(where: {
         ($0 as? UIWindowScene)?.activationState == .foregroundActive
       }) as? UIWindowScene,
       let window = scene.keyWindow {
      return window.bounds.height >= window.bounds.width
    }
    return isPortrait(currentInterfaceOrientation())
  }
#endif

#if os(iOS)
  /// HaishinKit 2.2.5+：分屏、画中画等场景下保持相机采集（需设备支持 `isMultitaskingCameraAccessSupported`）。
  /// 通过 `MediaMixer.configuration` 写入底层 `AVCaptureSession`（iOS 17+ 与 HaishinKit API 一致）。
  func supportsMultitasking() async -> Bool {
    // AVCaptureSession configuration returns Void; use a synchronized box.
    let support = CapabilityFlag()
    if #available(iOS 17.0, *) {
      await mixer.configuration { session in support.value = session.isMultitaskingCameraAccessSupported }
    }
    return support.value
  }
  private final class CapabilityFlag: @unchecked Sendable { var value = false }

  func setMultitaskingCameraAccessEnabled(_ enabled: Bool) async -> Bool {
    guard await supportsMultitasking() else { return false }
    if #available(iOS 17.0, *) {
      await mixer.configuration { session in session.isMultitaskingCameraAccessEnabled = enabled }
      return true
    }
    return false
  }

#endif

  private static func currentInterfaceOrientation() -> AVCaptureVideoOrientation {
#if canImport(UIKit)
    if #available(iOS 13.0, *),
       let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let orientation = DeviceUtil.videoOrientation(by: windowScene.interfaceOrientation) {
      return orientation
    }
#endif
    return .portrait
  }

  private static func isPortrait(_ orientation: AVCaptureVideoOrientation) -> Bool {
    orientation == .portrait || orientation == .portraitUpsideDown
  }

  /// Align offscreen canvas with capture size + phone orientation (HaishinKit sample uses 720x1280 in portrait).
  @ScreenActor
  private static func applyOverlayScreenGeometry(
    mixer: MediaMixer,
    texture: HKStreamFlutterTexture?,
    orientation: AVCaptureVideoOrientation
  ) async {
    var base = texture?.bounds ?? .zero
    if base.width < 2 || base.height < 2 {
      base = CGSize(width: 720, height: 1280)
    }
    let shortSide = min(base.width, base.height)
    let longSide = max(base.width, base.height)
    let screenSize = isPortrait(orientation)
      ? CGSize(width: shortSide, height: longSide)
      : CGSize(width: longSide, height: shortSide)
    mixer.screen.size = screenSize
    texture?.bounds = screenSize
  }

  @ScreenActor
  private func ensureOverlayScreenConfigured() async {
    guard !screenConfiguredForOverlay else { return }
    let orientation = Self.currentInterfaceOrientation()
    await mixer.setVideoOrientation(orientation)

    // Prefer capture target size when texture bounds are still unset.
    if (texture?.bounds.width ?? 0) < 2, lastCaptureSize.width > 1 {
      texture?.bounds = lastCaptureSize
    }
    if let explicitCanvas {
      mixer.screen.size = explicitCanvas
      texture?.bounds = explicitCanvas
    } else {
      await Self.applyOverlayScreenGeometry(mixer: mixer, texture: texture, orientation: orientation)
    }

    var videoMixerSettings = await mixer.videoMixerSettings
    videoMixerSettings.mode = .offscreen
    await mixer.setVideoMixerSettings(videoMixerSettings)
    screenConfiguredForOverlay = true
  }

  @ScreenActor
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

  /// Current offscreen canvas size (valid after overlay is configured).
  @ScreenActor
  func overlayOutputSize() -> CGSize {
    mixer.screen.size
  }

  @ScreenActor
  func setOverlayText(
    text: String,
    fontSize: CGFloat,
    colorArgb: UInt32,
    position: String?,
    scale: CGFloat
  ) async throws {
    guard !text.isEmpty, fontSize.isFinite, fontSize > 0, fontSize <= 1024, scale.isFinite else { throw CameraSetupError.invalidValue }
    await ensureOverlayScreenConfigured()
    if let existing = overlayObject {
      try? await mixer.screen.removeChild(existing)
      overlayObject = nil
    }
    let textObject = TextScreenObject()
    textObject.string = text
    let uiColor = Self.uiColor(argb: colorArgb)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: fontSize),
      .foregroundColor: uiColor
    ]
    textObject.attributes = attributes
    let measured = (text as NSString).size(withAttributes: attributes)
    let factor = min(max(scale / 100.0, 0.1), 4.0)
    textObject.size = CGSize(
      width: max(measured.width * factor, fontSize),
      height: max(measured.height * factor, fontSize)
    )
    applyPosition(textObject, position: position)
    try await mixer.screen.addChild(textObject)
    overlayObject = textObject
  }

  @ScreenActor
  func setOverlayImage(filePath: String, position: String?, scale: CGFloat) async throws {
    guard scale.isFinite else { throw CameraSetupError.invalidValue }
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
    let factor = min(max(scale / 100.0, 0.1), 4.0)
    let w = CGFloat(image.width) * factor
    let h = CGFloat(image.height) * factor
    imageObject.size = CGSize(width: max(w, 1), height: max(h, 1))
    applyPosition(imageObject, position: position)
    try await mixer.screen.addChild(imageObject)
    overlayObject = imageObject
  }

  @ScreenActor
  func clearOverlay() async {
    if let existing = overlayObject {
      try? await mixer.screen.removeChild(existing)
      overlayObject = nil
    }
    // Restore passthrough so preview returns to pre-overlay framing.
    if screenConfiguredForOverlay {
      var videoMixerSettings = await mixer.videoMixerSettings
      videoMixerSettings.mode = .passthrough
      await mixer.setVideoMixerSettings(videoMixerSettings)
      let orientedSize = await orientedCaptureSize()
      if orientedSize.width > 1 {
        texture?.bounds = orientedSize
      }
      screenConfiguredForOverlay = false
    }
  }

  private static func uiColor(argb: UInt32) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xff) / 255.0
    let r = CGFloat((argb >> 16) & 0xff) / 255.0
    let g = CGFloat((argb >> 8) & 0xff) / 255.0
    let b = CGFloat(argb & 0xff) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
