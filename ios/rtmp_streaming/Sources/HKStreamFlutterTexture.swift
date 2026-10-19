#if canImport(Flutter)
import Flutter
#endif
import Foundation
import HaishinKit
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

final class HKStreamFlutterTexture: NSObject, FlutterTexture {
  private static let defaultOptions: [String: Any] = [
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    kCVPixelBufferIOSurfacePropertiesKey as String: NSDictionary()
  ]
  
  private var storedBounds: CGSize = .zero
  private var storedGravity: AVLayerVideoGravity = .resizeAspectFill
  var bounds: CGSize {
    get { queue.sync { storedBounds } }
    set { queue.sync { storedBounds = newValue } }
  }
  var videoGravity: AVLayerVideoGravity {
    get { queue.sync { storedGravity } }
    set { queue.sync { storedGravity = newValue } }
  }
  private(set) var textureId: Int64 = 0
  private let context = CIContext()
  private let registry: FlutterTextureRegistry
  private var _currentSampleBuffer: CMSampleBuffer?
  private var queue = DispatchQueue(label: "com.haishinkit.HKStreamFlutterTexture")
  
  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
    self.textureId = self.registry.register(self)
  }
//  func registryTextureId(){
//
////    queue.async { [weak self] in
////      guard let self = self else { return }
////      self.id = self.registry.register(self)
////      print("✅ Texture ID registered: \(self.id)")
////      if self.id == 0 {
////        print("❌ Warning: Texture registration returned 0!")
////      }
////    }
//  }
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let bounds = self.bounds
    let videoGravity = self.videoGravity
    guard bounds.width > 0, bounds.height > 0 else { return createPlaceholderPixelBuffer() }
    var buffer: CMSampleBuffer?
    
    // ✅ 使用并发队列的同步读取
    queue.sync {
      buffer = _currentSampleBuffer
    }
    guard
      let currentSampleBuffer = buffer,
      let imageBuffer = CMSampleBufferGetImageBuffer(currentSampleBuffer) else {
      return createPlaceholderPixelBuffer()
    }
    
    let displayImage = CIImage(cvPixelBuffer: imageBuffer)
    var scaleX: CGFloat = 0
    var scaleY: CGFloat = 0
    var translationX: CGFloat = 0
    var translationY: CGFloat = 0
    switch videoGravity {
    case .resize:
      scaleX = bounds.width / displayImage.extent.width
      scaleY = bounds.height / displayImage.extent.height
    case .resizeAspect:
      let scale: CGFloat = min(bounds.width / displayImage.extent.width, bounds.height / displayImage.extent.height)
      scaleX = scale
      scaleY = scale
      translationX = (bounds.width - displayImage.extent.width * scale) / scaleX / 2
      translationY = (bounds.height - displayImage.extent.height * scale) / scaleY / 2
    case .resizeAspectFill:
      let scale: CGFloat = max(bounds.width / displayImage.extent.width, bounds.height / displayImage.extent.height)
      scaleX = scale
      scaleY = scale
      translationX = (bounds.width - displayImage.extent.width * scale) / scaleX / 2
      translationY = (bounds.height - displayImage.extent.height * scale) / scaleY / 2
    default:
      break
    }
    
    let scaledImage: CIImage = displayImage
      .transformed(by: CGAffineTransform(translationX: translationX, y: translationY))
      .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, Int(bounds.width), Int(bounds.height), kCVPixelFormatType_32BGRA, Self.defaultOptions as CFDictionary?, &pixelBuffer)
    
    if let pixelBuffer = pixelBuffer {
      let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: bounds))
      context.render(scaledImage.composited(over: background), to: pixelBuffer)
      return Unmanaged<CVPixelBuffer>.passRetained(pixelBuffer)
    }
    
    return createPlaceholderPixelBuffer()
  }
  private func createPlaceholderPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let width = max(Int(bounds.width), 1)
    let height = max(Int(bounds.height), 1)
    
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width, height,
      kCVPixelFormatType_32BGRA,
      Self.defaultOptions as CFDictionary?,
      &pixelBuffer
    )
    
    return pixelBuffer.map { Unmanaged<CVPixelBuffer>.passRetained($0) }
  }
  
  // 获取当前帧的图片
  func getCurrentImage() -> UIImage? {
    guard queue.sync(execute: { _currentSampleBuffer != nil }) else { return nil }
    guard let buffer = copyPixelBuffer()?.takeRetainedValue() else { return nil }
    let image = CIImage(cvPixelBuffer: buffer)
    guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

extension HKStreamFlutterTexture: StreamOutput {
  // MARK: HKStreamOutput
  func stream(_ stream: some StreamConvertible, didOutput audio: AVAudioBuffer, when: AVAudioTime) {
  }
  
  func stream(_ stream: some StreamConvertible, didOutput video: CMSampleBuffer) {
    queue.async(flags: .barrier) { [weak self] in
      self?._currentSampleBuffer = video
    }
    registry.textureFrameAvailable(textureId)
  }
}
