import Foundation

assert(
  Cipher.encrypt([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) == [
    229, 128, 126, 136, 123, 222, 7, 99, 11, 77, 14, 113, 91, 62, 137, 145,
  ])
assert(
  Cipher.encrypt([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) == [
    158, 67, 223, 55, 123, 58, 70, 206, 117, 22, 52, 102, 126, 33, 93, 229,
  ])
assert(
  Cipher.encrypt([255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255])
    == [146, 70, 3, 238, 226, 220, 161, 14, 188, 72, 73, 173, 86, 68, 250, 247])
assert(
  Cipher.encrypt([203, 194, 122, 208, 239, 13, 26, 232, 107, 58, 159, 88, 190, 75, 212, 176]) == [
    161, 215, 228, 23, 144, 121, 20, 176, 195, 208, 175, 73, 54, 246, 236, 29,
  ])
assert(crc16(Array("123456789".utf8)) == 0x31C3)
let bytes: [UInt8] = [1, 2, 3]
assert(Frame(Frame.encode(0xC0, 0x27, bytes))?.body == bytes)
assert(Frame([0, 1, 2]) == nil)
let avi = AVI.build(
  [Data([255, 216, 1, 2, 3, 255, 217]), Data([255, 216, 4, 5, 255, 217])], fps: 10)
assert(avi == (try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))))
print("PASS: cipher vectors, CRC, framing, byte-identical AVI")
