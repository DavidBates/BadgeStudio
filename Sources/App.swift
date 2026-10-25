import CoreTransferable
import ImageIO
import Photos
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
  @State private var showLivePhoto = false
  @State private var showMaker = false
  @State private var draft: AnimationDraft?
  @State private var gifURL: URL?
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
          HStack {
            Button {
              showLivePhoto = true
            } label: {
              Label("Live Photo", systemImage: "livephoto")
            }
            Button {
              showMaker = true
            } label: {
              Label("GIF maker", systemImage: "textformat")
            }
          }.buttonStyle(.bordered).tint(accent).disabled(converting || bluetooth.busy)
          if let gifURL {
            ShareLink(item: gifURL) { Label("Share GIF", systemImage: "square.and.arrow.up") }
          }
          VStack(alignment: .leading, spacing: 12) {
            Picker("Framing", selection: $fit) {
              ForEach(FitMode.allCases, id: \.self) { Text($0.rawValue) }
            }.pickerStyle(.segmented).disabled(draft != nil)
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
        .sheet(isPresented: $showLivePhoto) {
          LivePhotoPicker { result in
            showLivePhoto = false
            switch result {
            case .success(let url): if let url { setSource(url) }
            case .failure(let error): message = error.localizedDescription
            }
          }
        }
        .sheet(isPresented: $showMaker) {
          AnimationEditor(initial: draft ?? AnimationDraft()) { value in
            draft = value
            showMaker = false
            convert()
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
    draft = nil
    if let old = source { try? FileManager.default.removeItem(at: old) }
    source = url
    convert()
  }
  func convert() {
    guard source != nil || draft != nil else { return }
    let chosenDraft = draft
    let chosenSource = source
    if let gifURL { try? FileManager.default.removeItem(at: gifURL) }
    gifURL = nil
    conversion?.cancel()
    prepared = nil
    converting = true
    message = "Preparing your media…"
    let chosenFit = fit
    let chosenQuality = quality
    conversion = Task {
      do {
        let worker = Task.detached {
          let media: PreparedMedia
          if let chosenDraft {
            media = try AnimationMaker.prepare(chosenDraft, quality: chosenQuality)
          } else if let chosenSource {
            media = try await MediaConverter.prepare(
              url: chosenSource, fit: chosenFit, quality: chosenQuality)
          } else {
            throw BadgeError("Choose media first.")
          }
          let gif = media.ext == "avi" ? try GIFExporter.export(media) : nil
          return (media, gif)
        }
        let result = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: {
          worker.cancel()
        }
        if Task.isCancelled {
          if let url = result.1 { try? FileManager.default.removeItem(at: url) }
          return
        }
        prepared = result.0
        gifURL = result.1
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

struct LivePhotoPicker: UIViewControllerRepresentable {
  let completion: (Result<URL?, Error>) -> Void
  func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
  func makeUIViewController(context: Context) -> PHPickerViewController {
    var configuration = PHPickerConfiguration()
    configuration.filter = .livePhotos
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .current
    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = context.coordinator
    return picker
  }
  func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}
  final class Coordinator: NSObject, PHPickerViewControllerDelegate {
    let completion: (Result<URL?, Error>) -> Void
    init(completion: @escaping (Result<URL?, Error>) -> Void) { self.completion = completion }
    func finish(_ result: Result<URL?, Error>) {
      DispatchQueue.main.async { self.completion(result) }
    }
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
      guard let item = results.first else {
        finish(.success(nil))
        return
      }
      let spinner = UIActivityIndicatorView(style: .large)
      spinner.translatesAutoresizingMaskIntoConstraints = false
      spinner.backgroundColor = UIColor.black.withAlphaComponent(0.7)
      spinner.layer.cornerRadius = 12
      spinner.accessibilityLabel = "Downloading Live Photo"
      picker.view.addSubview(spinner)
      NSLayoutConstraint.activate([
        spinner.centerXAnchor.constraint(equalTo: picker.view.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: picker.view.centerYAnchor),
        spinner.widthAnchor.constraint(equalToConstant: 80),
        spinner.heightAnchor.constraint(equalToConstant: 80),
      ])
      spinner.startAnimating()
      picker.view.isUserInteractionEnabled = false
      item.itemProvider.loadObject(ofClass: PHLivePhoto.self) { object, error in
        guard let photo = object as? PHLivePhoto,
          let resource = PHAssetResource.assetResources(for: photo).first(where: {
            $0.type == .pairedVideo || $0.type == .fullSizePairedVideo
          })
        else {
          self.finish(
            .failure(
              error
                ?? BadgeError(
                  "Could not read this Live Photo’s motion. Download the original in Photos and try again."
                )))
          return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
          UUID().uuidString + ".mov")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) {
          error in
          if let error {
            try? FileManager.default.removeItem(at: url)
            self.finish(.failure(error))
          } else {
            self.finish(.success(url))
          }
        }
      }
    }
  }
}

struct AnimationEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: AnimationDraft
  @State private var foreground = Color.white
  @State private var background = Color.black
  @State private var photo: PhotosPickerItem?
  @State private var loading = false
  @State private var error = ""
  let completion: (AnimationDraft) -> Void
  init(initial: AnimationDraft, completion: @escaping (AnimationDraft) -> Void) {
    _draft = State(initialValue: initial)
    _foreground = State(initialValue: Color(uiColor: initial.textColor))
    _background = State(initialValue: Color(uiColor: initial.backgroundColor))
    self.completion = completion
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TimelineView(.animation(minimumInterval: 0.1)) { context in
            let phase =
              context.date.timeIntervalSinceReferenceDate.truncatingRemainder(
                dividingBy: draft.duration) / draft.duration
            Image(uiImage: AnimationMaker.image(draft, phase: phase)).resizable().aspectRatio(
              1, contentMode: .fit
            ).clipShape(Circle())
          }.frame(maxWidth: 260).frame(maxWidth: .infinity)
        }
        Section("Text") {
          TextField("Your message", text: $draft.text).onChange(of: draft.text) { _, value in
            draft.text = String(value.prefix(80)).replacingOccurrences(of: "\n", with: " ")
          }
          ColorPicker("Text color", selection: $foreground, supportsOpacity: false).onChange(
            of: foreground
          ) { _, color in draft.textColor = UIColor(color) }
          Slider(value: $draft.fontSize, in: 24...120) { Text("Text size") }
        }
        Section("Background") {
          ColorPicker("Base color", selection: $background, supportsOpacity: false).onChange(
            of: background
          ) { _, color in draft.backgroundColor = UIColor(color) }
          PhotosPicker("Choose background image", selection: $photo, matching: .images)
          if draft.background != nil { Button("Remove image") { draft.background = nil } }
          if loading { ProgressView("Loading image…") }
          if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        Section("Animation") {
          Picker("Effect", selection: $draft.effect) {
            ForEach(TextEffect.allCases, id: \.self) { Text($0.rawValue) }
          }
          Slider(value: $draft.duration, in: 1...6, step: 0.5) { Text("Duration") }
          Text(String(format: "%.1f second loop", draft.duration)).foregroundStyle(.secondary)
        }
      }.navigationTitle("GIF maker").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Use animation") { completion(draft) }.disabled(
            loading || draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }.task(id: photo) {
        guard let photo else { return }
        loading = true
        error = ""
        defer { loading = false }
        do {
          guard let file = try await photo.loadTransferable(type: ImportedFile.self) else {
            throw BadgeError("Could not load image.")
          }
          defer { try? FileManager.default.removeItem(at: file.url) }
          let worker = Task.detached {
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1024,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary)
            else { throw BadgeError("Could not read background image.") }
            return UIImage(cgImage: cg)
          }
          let image = try await worker.value
          try Task.checkCancellation()
          draft.background = image
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
      }
    }
  }
}
