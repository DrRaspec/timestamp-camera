import AVFoundation
import Flutter
import ImageIO
import UIKit

final class PhotoStamper {
  static let shared = PhotoStamper()

  private let lock = NSLock()
  private var _lines: [String] = []
  // Same default as Android: about half the size of 0.85 with little visible loss.
  private var _quality: CGFloat = 0.6
  // 1 = full size, 2 = half width/height. Same meaning as on Android.
  private var _sampleSize: Int = 1

  var lines: [String] {
    lock.lock(); defer { lock.unlock() }
    return _lines
  }

  var quality: CGFloat {
    lock.lock(); defer { lock.unlock() }
    return _quality
  }

  var isEnabled: Bool {
    lock.lock(); defer { lock.unlock() }
    return !_lines.isEmpty
  }

  var sampleSize: Int {
    lock.lock(); defer { lock.unlock() }
    return _sampleSize
  }

  func set(lines: [String], quality: CGFloat?, sampleSize: Int? = nil) {
    lock.lock()
    _lines = lines.filter { !$0.isEmpty }
    if let quality = quality { _quality = min(max(quality, 0.01), 1.0) }
    if let sampleSize = sampleSize { _sampleSize = max(1, sampleSize) }
    lock.unlock()
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "photo_stamp", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setStampText":
        let args = call.arguments as? [String: Any]
        let lines = (args?["lines"] as? [String]) ?? []
        let q = (args?["quality"] as? Int).map { CGFloat($0) / 100.0 }
        let sampleSize = args?["sampleSize"] as? Int
        PhotoStamper.shared.set(lines: lines, quality: q, sampleSize: sampleSize)
        result(nil)
      case "clearStampText":
        PhotoStamper.shared.set(lines: [], quality: nil)
        result(nil)
      case "awaitStamp":
        // iOS writes the file before takePicture returns, so there is nothing to wait for.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func uiOrientation(fromExif value: UInt32) -> UIImage.Orientation {
    switch value {
    case 2: return .upMirrored
    case 3: return .down
    case 4: return .downMirrored
    case 5: return .leftMirrored
    case 6: return .right
    case 7: return .rightMirrored
    case 8: return .left
    default: return .up
    }
  }

  func stampedJPEG(from photo: AVCapturePhoto) -> Data? {
    let lines = self.lines
    let start = CFAbsoluteTimeGetCurrent()
    guard !lines.isEmpty, let upright = uprightImage(from: photo, sampleSize: sampleSize)
    else { return nil }
    let size = upright.size

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    // Without this, devices with wide-colour screens can get a 16-bit-per-channel context,
    // which is slower to draw and encode and uses twice the memory.
    format.preferredRange = .standard
    let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      upright.draw(at: .zero)

      let fontSize = min(size.width, size.height) * 0.035
      let shadow = NSShadow()
      shadow.shadowBlurRadius = fontSize * 0.2
      shadow.shadowColor = UIColor.black.withAlphaComponent(0.85)
      shadow.shadowOffset = .zero
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .right
      let attrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
        .foregroundColor: UIColor.white,
        .shadow: shadow,
        .paragraphStyle: paragraph,
      ]
      let margin = min(size.width, size.height) * 0.03
      let text = lines.joined(separator: "\n") as NSString
      let bounds = CGSize(width: size.width - 2 * margin, height: .greatestFiniteMagnitude)
      let textRect = text.boundingRect(
        with: bounds, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
      let rect = CGRect(
        x: margin, y: size.height - margin - ceil(textRect.height),
        width: size.width - 2 * margin, height: ceil(textRect.height))
      text.draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
    }

    guard let outImage = rendered.cgImage else { return nil }

    var props = photo.metadata
    props[kCGImagePropertyOrientation as String] = 1
    if var exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
      exif[kCGImagePropertyExifPixelXDimension as String] = outImage.width
      exif[kCGImagePropertyExifPixelYDimension as String] = outImage.height
      props[kCGImagePropertyExifDictionary as String] = exif
    }
    if var tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
      tiff[kCGImagePropertyTIFFOrientation as String] = 1
      props[kCGImagePropertyTIFFDictionary as String] = tiff
    }
    let q = quality
    props[kCGImageDestinationLossyCompressionQuality as String] = q

    let data = NSMutableData()
    guard
      let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(dest, outImage, props as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    NSLog(
      "PhotoStamper: Saved %ldx%ld, %.1f KB, quality %ld, total %ld ms",
      outImage.width, outImage.height, Double(data.length) / 1024, Int((q * 100).rounded()),
      Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    return data as Data
  }

  /// Upright image to draw on. With sampleSize > 1, ImageIO decodes straight to the smaller size
  /// (faster and less memory than decoding full size and scaling), like inSampleSize on Android.
  private func uprightImage(from photo: AVCapturePhoto, sampleSize: Int) -> UIImage? {
    if sampleSize > 1, let data = photo.fileDataRepresentation(),
      let source = CGImageSourceCreateWithData(data as CFData, nil)
    {
      let dims = photo.resolvedSettings.photoDimensions
      let maxSide = max(Int(dims.width), Int(dims.height)) / sampleSize
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,  // applies EXIF orientation
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxSide),
        kCGImageSourceShouldCacheImmediately: true,
      ]
      if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
      }
    }

    guard let cgImage = photo.cgImageRepresentation() else { return nil }
    let rawOrientation =
      (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
    return UIImage(
      cgImage: cgImage, scale: 1, orientation: PhotoStamper.uiOrientation(fromExif: rawOrientation))
  }
}
