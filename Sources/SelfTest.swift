#if DEBUG
  import UIKit
  import AVFoundation
  import ImageIO
  import UniformTypeIdentifiers
  import Foundation
  enum AppSelfTest {
    static var output: URL {
      ProcessInfo.processInfo.environment["BADGE_TEST_OUTPUT"].map { URL(fileURLWithPath: $0) }
        ?? URL.documentsDirectory.appendingPathComponent("self-test.txt")
    }
    static func validateJPEG(_ data: Data) throws {
      let b = Array(data)
      guard b.count > 4, b[0] == 255, b[1] == 216 else { throw BadgeError("Missing JPEG header") }
      var i = 2
      var baseline = false
      while i + 4 <= b.count {
        guard b[i] == 255 else { throw BadgeError("Invalid JPEG segment") }
        let marker = b[i + 1]
        if marker == 0xDA { break }
        let length = Int(b[i + 2]) * 256 + Int(b[i + 3])
        guard length >= 2, i + 2 + length <= b.count else {
          throw BadgeError("Truncated JPEG segment")
        }
        guard marker != 0xC2, marker != 0xDD, !(0xE1...0xEF).contains(marker) else {
          throw BadgeError("JPEG contains unsupported progressive, restart, or metadata features")
        }
        if marker == 0xC0 {
          guard length >= 17, b[i + 4] == 8, b[i + 9] == 3 else {
            throw BadgeError("JPEG must be 8-bit three-component baseline")
          }
          baseline = true
        }
        i += 2 + length
      }
      guard baseline else { throw BadgeError("JPEG is not baseline") }
    }
    static func run() async -> String {
      do {
        if let source = ProcessInfo.processInfo.environment["BADGE_TEST_SOURCE"] {
          let photo = try await MediaConverter.prepare(
            url: URL(fileURLWithPath: source), fit: .fill, quality: .compact)
          try photo.data.write(
            to: output.deletingLastPathComponent().appendingPathComponent("encoded-photo.jpg"))
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
          "badge-selftest", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 640, height: 360), format: format)
          .image { c in
            UIColor.red.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
          }
        let png = dir.appendingPathComponent("test.png")
        try image.pngData()!.write(to: png)
        let still = try await MediaConverter.prepare(url: png, fit: .fit, quality: .compact)
        guard still.ext == "jpg", UIImage(data: still.data)?.size == CGSize(width: 368, height: 368)
        else { throw BadgeError("Still conversion failed") }
        try validateJPEG(still.data)
        let gif = dir.appendingPathComponent("test.gif")
        let destination = CGImageDestinationCreateWithURL(
          gif as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        CGImageDestinationSetProperties(
          destination,
          [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for delay in [0.1, 0.3] {
          CGImageDestinationAddImage(
            destination, image.cgImage!,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
          throw BadgeError("GIF fixture failed")
        }
        let animation = try await MediaConverter.prepare(url: gif, fit: .fill, quality: .compact)
        guard animation.ext == "avi", animation.frames.count == 4,
          abs(animation.duration - 0.4) < 0.01
        else { throw BadgeError("GIF timing failed") }
        for frame in animation.frames { try validateJPEG(frame) }
        let movie = dir.appendingPathComponent("test.mp4")
        try? FileManager.default.removeItem(at: movie)
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
        let input = AVAssetWriterInput(
          mediaType: .video,
          outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 128, AVVideoHeightKey: 128,
          ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
          assetWriterInput: input,
          sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 128, kCVPixelBufferHeightKey as String: 128,
          ])
        writer.add(input)
        guard writer.startWriting() else {
          throw writer.error ?? BadgeError("Video fixture failed")
        }
        writer.startSession(atSourceTime: .zero)
        for i in 0..<10 {
          while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
          var buffer: CVPixelBuffer?
          CVPixelBufferCreate(
            kCFAllocatorDefault, 128, 128, kCVPixelFormatType_32ARGB, nil, &buffer)
          guard let buffer else { throw BadgeError("Pixel buffer allocation failed") }
          CVPixelBufferLockBaseAddress(buffer, [])
          memset(
            CVPixelBufferGetBaseAddress(buffer), Int32(i * 20), CVPixelBufferGetDataSize(buffer))
          CVPixelBufferUnlockBaseAddress(buffer, [])
          guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 10))
          else { throw writer.error ?? BadgeError("Video frame failed") }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
          throw writer.error ?? BadgeError("Video fixture incomplete")
        }
        let video = try await MediaConverter.prepare(url: movie, fit: .fit, quality: .compact)
        guard video.ext == "avi", video.frames.count >= 9, video.data.prefix(4) == Data("RIFF".utf8)
        else { throw BadgeError("Video conversion failed") }
        for frame in video.frames { try validateJPEG(frame) }
        var truncated = Data("not media".utf8)
        let invalid = dir.appendingPathComponent("invalid.gif")
        try truncated.write(to: invalid)
        truncated.removeAll()
        var rejected = false
        do {
          _ = try await MediaConverter.prepare(url: invalid, fit: .fit, quality: .compact)
        } catch { rejected = true }
        guard rejected else { throw BadgeError("Invalid file was accepted") }
        let result =
          "PASS: baseline JPEG profile; image 368x368; GIF variable timing; MP4 conversion; invalid file rejected"
        try result.write(to: output, atomically: true, encoding: .utf8)
        return result
      } catch {
        let result = "FAIL: \(error.localizedDescription)"
        try? result.write(to: output, atomically: true, encoding: .utf8)
        return result
      }
    }
  }
#endif
