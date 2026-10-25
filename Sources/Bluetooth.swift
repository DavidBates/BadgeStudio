import Combine
import CoreBluetooth
import Foundation
import UIKit

@MainActor
final class BadgeBluetooth: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate,
  @preconcurrency CBPeripheralDelegate
{
  @Published var badges: [CBPeripheral] = []
  @Published var status = "Turn on a badge and tap Scan."
  @Published var progress = 0.0
  @Published var busy = false
  @Published var scanning = false
  @Published var diagnostics = ""
  var stage = "connection"
  var pendingServices = Set<CBUUID>()
  var pendingNotifications = Set<CBUUID>()
  func log(_ text: String) {
    diagnostics += "[\(Date().formatted(date: .omitted, time: .standard))] \(text)\n"
    if diagnostics.count > 60000 { diagnostics = String(diagnostics.suffix(50000)) }
    try? diagnostics.write(
      to: URL.documentsDirectory.appendingPathComponent("badge-transfer.log"), atomically: true,
      encoding: .utf8)
  }
  func phase(_ text: String) {
    stage = text
    status = text
    log(text)
  }
  var central: CBCentralManager!
  var active: CBPeripheral?
  var characteristics: [String: CBCharacteristic] = [:]
  var packets: [[UInt8]] = []
  var failure: Error?
  var task: Task<Void, Never>?
  let ae = "AE01", notify = "AE02", fd = "C2E6FD02-E966-1000-8000-BEF9C223DF6A"
  override init() {
    super.init()
    if !ProcessInfo.processInfo.arguments.contains("--self-test") {
      central = CBCentralManager(delegate: self, queue: .main)
    }
  }
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn: status = "Bluetooth ready. Put your badge in pairing mode."
    case .unauthorized: status = "Allow Bluetooth access in iPhone Settings."
    case .poweredOff: status = "Turn on Bluetooth in Settings."
    default: status = "Bluetooth is unavailable."
    }
  }
  func scan() {
    guard central.state == .poweredOn, !busy else { return }
    badges = []
    scanning = true
    status = "Looking for E87 badges…"
    central.scanForPeripherals(withServices: nil)
    Task {
      try? await Task.sleep(for: .seconds(10))
      self.central.stopScan()
      self.scanning = false
      if !self.busy {
        self.status =
          self.badges.isEmpty
          ? "No badges found. Enable pairing mode and disconnect Zrun." : "Choose a badge below."
      }
    }
  }
  func centralManager(
    _ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any],
    rssi: NSNumber
  ) {
    let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? ""
    let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    if name.uppercased().contains("E87") || services.contains(CBUUID(string: "AE00")) {
      if !badges.contains(where: { $0.identifier == p.identifier }) { badges.append(p) }
    }
  }
  func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
    log("Connected; max write = \(p.maximumWriteValueLength(for: .withoutResponse)) bytes")
    p.discoverServices(nil)
  }
  func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?)
  { failure = error ?? BadgeError("Could not connect.") }
  func centralManager(
    _ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?
  ) {
    if busy { failure = error ?? BadgeError("Badge disconnected. Keep it nearby and try again.") }
  }
  func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
    if let error {
      failure = error
      return
    }
    pendingServices = Set((p.services ?? []).map(\.uuid))
    for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
  }
  func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
    if let error {
      failure = error
      return
    }
    pendingServices.remove(s.uuid)
    for c in s.characteristics ?? [] {
      characteristics[c.uuid.uuidString.uppercased()] = c
      if c.uuid == CBUUID(string: notify)
        || [
          "C2E6FD01-E966-1000-8000-BEF9C223DF6A", "C2E6FD03-E966-1000-8000-BEF9C223DF6A",
          "C2E6FD05-E966-1000-8000-BEF9C223DF6A",
        ].contains(c.uuid.uuidString.uppercased())
      {
        if c.properties.contains(.notify) || c.properties.contains(.indicate) {
          pendingNotifications.insert(c.uuid)
          p.setNotifyValue(true, for: c)
        }
      }
    }
  }
  func peripheral(
    _ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?
  ) {
    pendingNotifications.remove(c.uuid)
    log("Notifications \(c.uuid): \(c.isNotifying ? "ready" : "not ready")")
    if let error { failure = error }
  }
  func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
    if let error {
      failure = error
      return
    }
    if let data = c.value {
      let bytes = Array(data)
      if let f = Frame(bytes) {
        log(
          String(format: "RX cmd %02X flag %02X body ", f.command, f.flag)
            + f.body.prefix(16).map { String(format: "%02X", $0) }.joined())
      } else {
        log("RX \(c.uuid) \(data.count) bytes")
      }
      packets.append(bytes)
      if packets.count > 2048 { packets.removeFirst(1024) }
    }
  }
  func check() throws {
    try Task.checkCancellation()
    if let failure { throw failure }
  }
  func pause(_ seconds: Double) async throws {
    try await Task.sleep(for: .seconds(seconds))
    try check()
  }
  func wait(_ seconds: Double = 10, label: String? = nil, predicate: @escaping () -> Bool)
    async throws
  {
    let end = Date().addingTimeInterval(seconds)
    while !predicate() {
      try check()
      guard Date() < end else {
        throw BadgeError(
          "Timed out during \(label ?? stage). Keep the badge nearby and disconnect Zrun. Share the transfer log if it repeats."
        )
      }
      try await pause(0.02)
    }
  }
  func receive(
    _ seconds: Double = 30, label: String? = nil, _ predicate: @escaping ([UInt8]) -> Bool
  ) async throws
    -> [UInt8]
  {
    try await wait(seconds, label: label) { self.packets.contains(where: predicate) }
    return packets.remove(at: packets.firstIndex(where: predicate)!)
  }
  func frame(_ cmd: UInt8, timeout: Double = 8) async throws -> Frame {
    let raw = try await receive(
      timeout, label: String(format: "%@ / command 0x%02X acknowledgement", stage, cmd)
    ) { Frame($0)?.command == cmd }
    return Frame(raw)!
  }
  func write(_ bytes: [UInt8], to key: String? = nil) async throws {
    try check()
    guard let p = active, let c = characteristics[key ?? ae], p.state == .connected else {
      throw BadgeError("Badge connection is not ready.")
    }
    guard c.properties.contains(.writeWithoutResponse) else {
      throw BadgeError("This badge does not support the expected write mode.")
    }
    guard bytes.count <= p.maximumWriteValueLength(for: .withoutResponse) else {
      throw BadgeError("Badge Bluetooth packet size is too small.")
    }
    try await wait(10, label: "Bluetooth write flow control") { p.canSendWriteWithoutResponse }
    p.writeValue(Data(bytes), for: c, type: .withoutResponse)
    // Yield between writes so the peripheral can process the window reliably.
    try await pause(0.01)
  }
  func send(_ cmd: UInt8, _ body: [UInt8], flag: UInt8 = 0xC0) async throws {
    if cmd != 1 { log(String(format: "TX cmd %02X (%d bytes)", cmd, body.count)) }
    try await write(Frame.encode(flag, cmd, body))
  }
  func control(_ value: String) async throws { try await write(hex(value), to: fd) }
  func cancel() { task?.cancel() }
  func upload(_ media: PreparedMedia, to p: CBPeripheral) {
    guard !busy else { return }
    diagnostics = "Badge Studio build 3\n"
    log("Upload \(media.ext), \(media.data.count) bytes to \(p.identifier)")
    pendingServices = []
    pendingNotifications = []
    busy = true
    progress = 0
    failure = nil
    packets = []
    characteristics = [:]
    active = p
    central.stopScan()
    scanning = false
    task = Task {
      UIApplicationBridge.keepAwake(true)
      defer {
        UIApplicationBridge.keepAwake(false)
        central.cancelPeripheralConnection(p)
        active = nil
        busy = false
      }
      do {
        phase("Connecting to \(p.name ?? "E87")…")
        p.delegate = self
        central.connect(p)
        try await wait(20) {
          self.characteristics[self.ae] != nil && self.characteristics[self.fd] != nil
            && self.characteristics[self.notify]?.isNotifying == true
            && self.pendingServices.isEmpty && self.pendingNotifications.isEmpty
        }
        try await pause(0.2)
        packets = []
        phase("Authenticating…")
        let challenge = (0..<16).map { _ in UInt8.random(in: 0...255) }
        try await write([0] + challenge)
        _ = try await receive(5) { $0.count == 17 && $0[0] == 1 }
        try await write([2] + Array("pass".utf8))
        let request = try await receive(5) { $0.count == 17 && $0[0] == 0 }
        try await write([1] + Cipher.encrypt(Array(request.dropFirst())))
        _ = try await receive(5) { $0.count >= 5 && Array($0.prefix(5)) == [2, 112, 97, 115, 115] }
        packets = []
        phase("Preparing badge storage…")
        try await transfer(Array(media.data), ext: media.ext)
        progress = 1
        phase("Upload complete — confirmed by badge.")
      } catch {
        if let c = characteristics[ae], p.state == .connected, p.canSendWriteWithoutResponse {
          p.writeValue(Data(Frame.encode(0xC0, 0x1C, [0, 0])), for: c, type: .withoutResponse)
        }
        status = error is CancellationError ? "Upload cancelled." : error.localizedDescription
        log(status)
      }
    }
  }
  func transfer(_ data: [UInt8], ext: String) async throws {
    try await send(6, [2, 0, 1])
    try await control("9EBD0B600D0003")
    _ = try? await frame(6, timeout: 3)
    let now = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
    let year = now.year ?? 2026
    try await write(
      [
        158, 69, 8, 2, 7, 0, UInt8(year & 255), UInt8(year >> 8), UInt8(now.month ?? 1),
        UInt8(now.day ?? 1), 0, UInt8(now.hour ?? 0), UInt8(now.minute ?? 0),
      ], to: fd)
    try await pause(0.02)
    try await control("9E200816010001")
    try await pause(0.02)
    try await control("9EB50B29010080")
    try await pause(0.2)
    try await send(3, [1, 255, 255, 255, 255, 1])
    try await control("9ED30BC6010001")
    try await pause(0.02)
    try await control("9E3008200200FF07")
    _ = try? await frame(3, timeout: 3)
    try await send(7, [2, 255, 255, 255, 255, 255])
    try await control("9E2B08FF02002200")
    try await pause(0.04)
    try await control("9E2D08FF02002400")
    _ = try? await frame(7, timeout: 3)
    try await control("9EB50B29010080")
    try await pause(0.4)
    try await control("9ED30BC6010001")
    _ = try? await receive(3) { $0.count >= 5 && $0[0] == 158 && ($0[3] == 199 || $0[2] == 199) }
    try await control("9EF40BDC01000C")
    _ = try? await receive(3) { $0.count >= 4 && $0[0] == 158 && $0[1] == 230 }
    phase("Starting upload session")
    try await send(0x21, [3, 0])
    _ = try await frame(0x21)
    phase("Negotiating transfer parameters")
    try await send(0x27, [4, 0, 0, 0, 0, 2, 1])
    _ = try await frame(0x27)
    phase("Sending file metadata")
    let crc = crc16(data)
    let n = data.count
    let name = String(UUID().uuidString.prefix(6)).lowercased() + "." + ext
    let length = (0..<4).reversed().map { UInt8(truncatingIfNeeded: n >> ($0 * 8)) }
    try await send(
      0x1B,
      [5] + length + [
        UInt8(crc >> 8), UInt8(crc & 255), UInt8.random(in: 0...255), UInt8.random(in: 0...255),
      ] + Array(name.utf8) + [0])
    let meta = try await frame(0x1B)
    let hint = meta.body.count >= 4 ? Int(meta.body[2]) * 256 + Int(meta.body[3]) : 490
    let maxPacket = (active?.maximumWriteValueLength(for: .withoutResponse) ?? 20) - 13
    let chunk = min(hint > 0 && hint <= 4096 ? hint : 490, maxPacket)
    guard chunk > 0 else { throw BadgeError("Bluetooth packet size is unsupported.") }
    log("Badge chunk hint \(hint), actual payload \(chunk), max packet \(maxPacket + 13)")
    phase("Waiting for first data request")
    var seq: UInt8 = 6
    var requests = 0
    var highest = 0
    var complete = false
    let deadline = Date().addingTimeInterval(600)
    while Date() < deadline {
      let raw = try await receive(30) {
        if let f = Frame($0) {
          return (f.command == 0x1D && f.flag == 0x80) || f.command == 0x20 || f.command == 0x1C
        }
        return false
      }
      guard let f = Frame(raw) else { continue }
      if f.command == 0x1C {
        let status = f.body.count > 1 ? f.body[1] : 255
        try await send(0x1C, [0, f.body.first ?? 0], flag: 0)
        guard status == 0, complete else {
          throw BadgeError(
            "Badge rejected the upload (code \(status)). Try Compact quality or a shorter animation."
          )
        }
        return
      }
      if f.command == 0x20 && f.flag == 0xC0 {
        complete = true
        let date = DateFormatter()
        date.dateFormat = "yyyyMMddHHmmss"
        let path = "\u{555C}" + date.string(from: Date()) + "." + ext
        let bytes = path.utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }
        try await send(0x20, [0, f.body.first ?? seq] + bytes + [0, 0], flag: 0)
        phase("Waiting for badge confirmation…")
        continue
      }
      guard f.body.count >= 8, f.body[1] == 0 else {
        throw BadgeError("Badge returned an invalid transfer request.")
      }
      let window = Int(f.body[2]) * 256 + Int(f.body[3])
      let offset = f.body[4..<8].reduce(0) { ($0 << 8) | Int($1) }
      guard offset <= data.count, window <= 65535 else {
        throw BadgeError("Badge requested an invalid file offset.")
      }
      if highest >= data.count {
        requests += 1
        guard requests <= 8 else {
          throw BadgeError("Badge repeatedly requested missing data. Please retry.")
        }
      }
      var sent = 0
      var slot: UInt8 = 0
      while sent < window && offset + sent < data.count {
        let count = min(chunk, min(window - sent, data.count - offset - sent))
        let payload = Array(data[offset + sent..<offset + sent + count])
        let checksum = crc16(payload)
        try await send(
          1, [seq, 0x1D, slot, UInt8(checksum >> 8), UInt8(checksum & 255)] + payload, flag: 0x80)
        seq &+= 1
        slot = (slot + 1) & 7
        sent += count
      }
      highest = max(highest, offset + sent)
      progress = min(0.99, Double(highest) / Double(data.count))
      status = "Uploading… \(Int(progress*100))%"
      stage = "data acknowledgement at \(highest)/\(data.count) bytes"
    }
    throw BadgeError("Transfer took too long. Please retry.")
  }
}
@MainActor enum UIApplicationBridge {
  static func keepAwake(_ enabled: Bool) { UIApplication.shared.isIdleTimerDisabled = enabled }
}
