import AVFoundation
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct PreparedMedia {
  let data: Data
  let ext: String
  let frames: [Data]
  let fps: Int
  let name: String
  var duration: Double { ext == "jpg" ? 0 : Double(frames.count) / Double(fps) }
}
enum FitMode: String, CaseIterable {
  case fit = "Fit circle"
  case fill = "Fill screen"
}
enum Quality: String, CaseIterable {
  case compact = "Compact"
  case smooth = "Smooth"
  var fps: Int { self == .compact ? 10 : 20 }
  var jpeg: CGFloat { self == .compact ? 0.45 : 0.7 }
}
enum MediaConverter {
  static func render(_ image: UIImage, fit: FitMode, quality: CGFloat) throws -> Data {
    guard image.size.width > 0, image.size.height > 0 else {
      throw BadgeError("Image has no dimensions.")
    }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    format.preferredRange = .standard
    let size = image.size
    let scale: CGFloat =
      fit == .fit
      ? 352 / sqrt(size.width * size.width + size.height * size.height)
      : max(368 / size.width, 368 / size.height)
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let result = UIGraphicsImageRenderer(size: CGSize(width: 368, height: 368), format: format)
      .image { ctx in
        UIColor.black.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 368, height: 368))
        image.draw(
          in: CGRect(
            x: (368 - target.width) / 2, y: (368 - target.height) / 2, width: target.width,
            height: target.height))
      }
    guard let cg = result.cgImage, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw BadgeError("Could not render image.")
    }
    var rgba = [UInt8](repeating: 0, count: 368 * 368 * 4)
    return try rgba.withUnsafeMutableBytes { pixels in
      guard
        let context = CGContext(
          data: pixels.baseAddress, width: 368, height: 368,
          bitsPerComponent: 8, bytesPerRow: 368 * 4, space: colorSpace,
          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue)
      else {
        throw BadgeError("Could not create sRGB image.")
      }
      context.draw(cg, in: CGRect(x: 0, y: 0, width: 368, height: 368))
      var length = 0
      guard
        let output = badge_jpeg_encode(
          pixels.baseAddress?.assumingMemoryBound(to: UInt8.self),
          368, 368, Int32(max(1, min(100, Int(quality * 100)))), &length)
      else {
        throw BadgeError("Could not encode badge JPEG.")
      }
      defer { badge_jpeg_free(output) }
      return Data(bytes: output, count: length)
    }
  }
  static func prepare(url: URL, fit: FitMode, quality: Quality) async throws -> PreparedMedia {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard (attrs[.size] as? NSNumber)?.intValue ?? 0 <= 200_000_000 else {
      throw BadgeError("Choose a file smaller than 200 MB.")
    }
    let name = url.lastPathComponent
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0
    {
      let count = CGImageSourceGetCount(source)
      guard count > 0 else { throw BadgeError("No image frames found.") }
      if count == 1 {
        let opts: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 1024,
          kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
          throw BadgeError("Could not read this image.")
        }
        // Match the desktop uploader's 16 KB still-image target.
        let levels: [CGFloat] =
          quality == .compact
          ? [0.72, 0.64, 0.56, 0.48, 0.40, 0.34, 0.25]
          : [0.88, 0.80, 0.72, 0.64, 0.56, 0.48, 0.40, 0.34, 0.25]
        var jpeg = Data()
        for level in levels {
          jpeg = try render(UIImage(cgImage: cg), fit: fit, quality: level)
          if jpeg.count <= 16000 { break }
        }
        return PreparedMedia(data: jpeg, ext: "jpg", frames: [jpeg], fps: 1, name: name)
      }
      guard count <= 2000 else {
        throw BadgeError("This animation has too many frames. Use a shorter clip.")
      }
      var durations = [Double]()
      for i in 0..<count {
        let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
        let gif = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay =
          (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
          ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        durations.append(delay > 0 ? delay : 0.1)
      }
      let duration = durations.reduce(0, +)
      guard duration <= 30 else { throw BadgeError("Choose an animation up to 30 seconds long.") }
      var frames = [Data]()
      var index = 0
      var end = durations[0]
      var cacheIndex = -1
      var cached = Data()
      for n in 0..<max(1, Int((duration * Double(quality.fps)).rounded())) {
        try Task.checkCancellation()
        let t = Double(n) / Double(quality.fps)
        while t >= end && index < count - 1 {
          index += 1
          end += durations[index]
        }
        if index != cacheIndex {
          guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            throw BadgeError("Could not decode GIF frame \(index).")
          }
          cached = try autoreleasepool {
            try render(UIImage(cgImage: cg), fit: fit, quality: quality.jpeg)
          }
          cacheIndex = index
        }
        frames.append(cached)
      }
      return try packaged(frames, fps: quality.fps, name: name)
    }
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0, duration <= 30 else {
      throw BadgeError("Choose a video up to 30 seconds long.")
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 736, height: 736)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = CMTime(
      seconds: 1 / Double(quality.fps), preferredTimescale: 600)
    var frames = [Data]()
    for n in 0..<max(1, Int((duration * Double(quality.fps)).rounded())) {
      try Task.checkCancellation()
      let result = try await generator.image(
        at: CMTime(seconds: Double(n) / Double(quality.fps), preferredTimescale: 600))
      frames.append(
        try autoreleasepool {
          try render(UIImage(cgImage: result.image), fit: fit, quality: quality.jpeg)
        })
    }
    return try packaged(frames, fps: quality.fps, name: name)
  }
  static func packaged(_ frames: [Data], fps: Int, name: String) throws -> PreparedMedia {
    let data = AVI.build(frames, fps: fps)
    guard data.count <= 8_000_000 else {
      throw BadgeError("Converted animation exceeds 8 MB. Use Compact quality or a shorter clip.")
    }
    return PreparedMedia(data: data, ext: "avi", frames: frames, fps: fps, name: name)
  }
}
