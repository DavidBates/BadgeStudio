import Foundation

struct BadgeError: LocalizedError {
  let message: String
  init(_ s: String) { message = s }
  var errorDescription: String? { message }
}
struct Frame {
  let flag: UInt8
  let command: UInt8
  let body: [UInt8]
  init?(_ d: [UInt8]) {
    guard d.count >= 8, Array(d.prefix(3)) == [254, 220, 186], d.last == 239,
      Int(d[5]) * 256 + Int(d[6]) == d.count - 8
    else { return nil }
    flag = d[3]
    command = d[4]
    body = Array(d[7..<d.count - 1])
  }
  static func encode(_ flag: UInt8, _ cmd: UInt8, _ body: [UInt8]) -> [UInt8] {
    [254, 220, 186, flag, cmd, UInt8((body.count >> 8) & 255), UInt8(body.count & 255)] + body + [
      239
    ]
  }
}
func crc16(_ bytes: [UInt8]) -> UInt16 {
  var crc: UInt16 = 0
  for b in bytes {
    crc ^= UInt16(b) << 8
    for _ in 0..<8 { crc = (crc & 0x8000 != 0) ? (crc &<< 1) ^ 0x1021 : crc &<< 1 }
  }
  return crc
}
func hex(_ s: String) -> [UInt8] {
  stride(from: 0, to: s.count, by: 2).map { i in
    let a = s.index(s.startIndex, offsetBy: i)
    let b = s.index(a, offsetBy: 2)
    return UInt8(s[a..<b], radix: 16)!
  }
}
// Byte-compatible with the upstream E87 MJPG AVI layout (MIT; see LICENSE).
enum AVI {
  static func u32(_ v: Int) -> Data {
    Data((0..<4).map { UInt8(truncatingIfNeeded: v >> ($0 * 8)) })
  }
  static func u16(_ v: Int) -> Data {
    Data([UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)])
  }
  static func words(_ a: [Int]) -> Data { a.reduce(Data()) { $0 + u32($1) } }
  static func text(_ s: String) -> Data { Data(s.utf8) }
  static func chunk(_ id: String, _ data: Data) -> Data {
    text(id) + u32(data.count) + data + (data.count % 2 == 1 ? Data([0]) : Data())
  }
  static func list(_ id: String, _ data: Data) -> Data {
    text("LIST") + u32(data.count + 4) + text(id) + data
  }
  static func build(_ frames: [Data], fps: Int) -> Data {
    precondition(!frames.isEmpty && fps > 0)
    let n = frames.count
    let maxSize = frames.map(\.count).max()!
    let avih = chunk(
      "avih",
      words([
        Int((1_000_000.0 / Double(fps)).rounded()), 25000, 0, 0x0910, n, 0, 1, 0x100000, 368, 368,
        0, 0, 0, 0,
      ]))
    let strhData =
      text("vidsMJPG") + words([0, 0, 0, 1, fps, 0, n, maxSize, 0xFFFF_FFFF, 0]) + u16(0) + u16(0)
      + u16(368) + u16(368)
    let strf =
      words([40, 368, 368]) + u16(1) + u16(24) + text("MJPG") + words([368 * 368 * 3, 0, 0, 0, 0])
    var junk = Data(repeating: 0, count: 4120)
    junk[0] = 4
    junk.replaceSubrange(8..<12, with: text("00dc"))
    let strl = list("strl", chunk("strh", strhData) + chunk("strf", strf) + chunk("JUNK", junk))
    let vprp = chunk(
      "vprp", words([0, 0, fps, 368, 368, 65537, 368, 368, 1, 368, 368, 368, 368, 0, 0, 0, 0]))
    let hdrl = list("hdrl", avih + strl + vprp + chunk("JUNK", Data(repeating: 0, count: 260)))
    let info = list("INFO", chunk("ISFT", text("AviBuilder\0")))
    let align = chunk(
      "JUNK", Data(repeating: 0, count: max(0, 5742 - (12 + hdrl.count + info.count + 8) - 8)))
    var movie = Data()
    var index = Data()
    var offset = 4
    for f in frames {
      movie += chunk("00dc", f)
      index += text("00dc") + words([16, offset, f.count])
      offset += 8 + f.count + (f.count & 1)
    }
    let content = text("AVI ") + hdrl + info + align + list("movi", movie) + chunk("idx1", index)
    return text("RIFF") + u32(content.count) + content
  }
}
