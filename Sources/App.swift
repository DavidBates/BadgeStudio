import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedFile: Transferable {
  let url: URL
  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .data) { received in
      let name = UUID().uuidString + "." + received.file.pathExtension
      let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try FileManager.default.copyItem(at: received.file, to: dest)
      return ImportedFile(url: dest)
    }
  }
}
@main struct BadgeStudioApp: App { var body: some Scene { WindowGroup { ContentView() } } }
struct ContentView: View {
  @StateObject private var bluetooth = BadgeBluetooth()
  @State private var photo: PhotosPickerItem?
  @State private var importer = false
  @State private var source: URL?
  @State private var prepared: PreparedMedia?
  @State private var fit = FitMode.fit
  @State private var quality = Quality.compact
  @State private var converting = false
  @State private var message = "Images, GIFs, and videos up to 30 seconds."
  @State private var selected: UUID?
  @State private var conversion: Task<Void, Never>?
  @State private var showLicenses = false
  private let accent = Color(red: 0.25, green: 0.88, blue: 0.75)
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 6) {
            Text("A little screen.\nYour whole vibe.").font(.largeTitle.bold())
            Text("Make something worth wearing.").foregroundStyle(.secondary)
          }
          ZStack {
            Circle().fill(Color.black).frame(width: 260, height: 260)
            if let p = prepared {
              TimelineView(.animation(minimumInterval: 1 / Double(p.fps))) { context in
                let index =
                  Int(context.date.timeIntervalSinceReferenceDate * Double(p.fps)) % p.frames.count
                if let image = UIImage(data: p.frames[index]) {
                  Image(uiImage: image).resizable().frame(width: 260, height: 260).clipShape(
                    Circle())
                }
              }
            } else {
              Image(systemName: "sparkles.tv").font(.system(size: 56)).foregroundStyle(accent)
            }
            Circle().stroke(accent.opacity(0.45), lineWidth: 2).frame(width: 264, height: 264)
            if converting {
              ProgressView().tint(.white).padding(20).background(.black.opacity(0.7), in: Circle())
            }
          }.frame(maxWidth: .infinity).padding(.vertical, 8)
          HStack {
            PhotosPicker(
              selection: $photo, matching: .any(of: [.images, .videos]),
              preferredItemEncoding: .current
            ) { Label("Photos", systemImage: "photo.on.rectangle") }
            Button {
              importer = true
            } label: {
              Label("Files", systemImage: "folder")
            }
          }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(
            converting || bluetooth.busy)
          VStack(alignment: .leading, spacing: 12) {
            Picker("Framing", selection: $fit) {
              ForEach(FitMode.allCases, id: \.self) { Text($0.rawValue) }
            }.pickerStyle(.segmented)
            Picker("Quality", selection: $quality) {
              ForEach(Quality.allCases, id: \.self) { Text($0.rawValue) }
            }.pickerStyle(.segmented)
            Text(
              fit == .fit
                ? "Keeps the entire image inside the round screen."
                : "Fills the display; edges may be cropped."
            ).font(.caption).foregroundStyle(.secondary)
            if let p = prepared {
              Text(
                "\(p.name) • \(ByteCountFormatter.string(fromByteCount:Int64(p.data.count),countStyle:.file))"
              ).font(.caption).lineLimit(2)
              if p.ext == "avi" {
                Text(String(format: "%.1f seconds • %d fps • silent loop", p.duration, p.fps)).font(
                  .caption
                ).foregroundStyle(.secondary)
              }
              if p.data.count > 1_000_000 {
                Text("Large file: if your badge rejects it, choose Compact or shorten the clip.")
                  .font(.caption).foregroundStyle(.orange)
              }
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
          }.disabled(converting || bluetooth.busy)
          Divider()
          HStack {
            Text("Nearby badges").font(.title3.bold())
            Spacer()
            Button(bluetooth.scanning ? "Scanning…" : "Scan") { bluetooth.scan() }.disabled(
              bluetooth.busy || bluetooth.scanning)
          }
          ForEach(bluetooth.badges, id: \.identifier) { badge in
            Button {
              selected = badge.identifier
            } label: {
              HStack {
                Image(systemName: selected == badge.identifier ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(accent)
                VStack(alignment: .leading) {
                  Text(badge.name ?? "E87").font(.headline)
                  Text(badge.identifier.uuidString).font(.caption2.monospaced()).foregroundStyle(
                    .secondary)
                }
                Spacer()
              }
            }.buttonStyle(.plain).disabled(bluetooth.busy)
          }
          Text(bluetooth.status).font(.callout).accessibilityIdentifier("badgeStatus")
          if !bluetooth.diagnostics.isEmpty && !bluetooth.busy {
            ShareLink(item: bluetooth.diagnostics) {
              Label("Share transfer log", systemImage: "square.and.arrow.up")
            }
            DisclosureGroup("Transfer details") {
              Text(bluetooth.diagnostics).font(.caption2.monospaced()).textSelection(.enabled)
            }
          }
          if bluetooth.busy {
            ProgressView(value: bluetooth.progress).tint(accent)
            Button("Cancel upload", role: .destructive) { bluetooth.cancel() }
          } else {
            Button {
              if let p = prepared,
                let badge = bluetooth.badges.first(where: { $0.identifier == selected })
              {
                bluetooth.upload(p, to: badge)
              }
            } label: {
              Label("Upload to badge", systemImage: "arrow.up.circle.fill").frame(
                maxWidth: .infinity
              ).padding(.vertical, 8)
            }.buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black).disabled(
              prepared == nil || !bluetooth.badges.contains(where: { $0.identifier == selected })
                || converting)
          }
          Text(
            "Keep the app open during upload. Disconnect the badge from Zrun first. All conversion happens on your iPhone."
          ).font(.footnote).foregroundStyle(.secondary)
        }.padding(24)
      }.background(Color(red: 0.045, green: 0.065, blue: 0.10)).navigationTitle("Badge Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          Button {
            showLicenses = true
          } label: {
            Image(systemName: "info.circle")
          }
        }
        .sheet(isPresented: $showLicenses) {
          NavigationStack {
            ScrollView {
              Text(
                (Bundle.main.url(forResource: "LICENSE", withExtension: "txt").flatMap {
                  try? String(contentsOf: $0)
                }) ?? "E87 protocol: jumpingmushroom and Felix Herbst, MIT License."
              ).font(.caption).padding()
            }.navigationTitle("Open source credits").toolbar {
              Button("Done") { showLicenses = false }
            }
          }
        }
        .fileImporter(
          isPresented: $importer, allowedContentTypes: [.image, .movie],
          allowsMultipleSelection: false
        ) { result in
          do {
            guard let url = try result.get().first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(
              UUID().uuidString + "." + url.pathExtension)
            try FileManager.default.copyItem(at: url, to: dest)
            setSource(dest)
          } catch { message = error.localizedDescription }
        }
        .onChange(of: photo) { _, item in
          guard let item else { return }
          converting = true
          Task {
            do {
              guard let file = try await item.loadTransferable(type: ImportedFile.self) else {
                throw BadgeError("Could not import media. Try choosing it from Files.")
              }
              setSource(file.url)
            } catch {
              message = error.localizedDescription
              converting = false
            }
          }
        }
        .onChange(of: fit) { _, _ in convert() }.onChange(of: quality) { _, _ in convert() }
        .onChange(of: bluetooth.badges.count) { _, count in
          if count == 1 { selected = bluetooth.badges[0].identifier }
        }
    }.preferredColorScheme(.dark)
      .task {
        #if DEBUG
          if ProcessInfo.processInfo.arguments.contains("--self-test") {
            message = await AppSelfTest.run()
            if ProcessInfo.processInfo.environment["BADGE_TEST_OUTPUT"] != nil {
              exit(message.hasPrefix("PASS") ? 0 : 1)
            }
          }
        #endif
      }
  }
  func setSource(_ url: URL) {
    if let old = source { try? FileManager.default.removeItem(at: old) }
    source = url
    convert()
  }
  func convert() {
    guard let source else { return }
    conversion?.cancel()
    prepared = nil
    converting = true
    message = "Preparing your media…"
    let chosenFit = fit
    let chosenQuality = quality
    conversion = Task {
      do {
        let worker = Task.detached {
          try await MediaConverter.prepare(url: source, fit: chosenFit, quality: chosenQuality)
        }
        let result = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        try Task.checkCancellation()
        prepared = result
        message = "Ready to upload."
        converting = false
      } catch {
        if !Task.isCancelled {
          message = error.localizedDescription
          converting = false
        }
      }
    }
  }
}
