# Badge Studio

Native iPhone app for E87/L8 Bluetooth badges. Import an image, GIF, or video from Photos or Files; preview the round screen; choose framing and compression; scan for a badge and upload. Media stays on the phone.

## Install on an iPhone

Open `BadgeStudio.xcodeproj` in Xcode, choose your own development team and a unique bundle identifier in Signing & Capabilities, select your connected iPhone, then Run.

Alternatively, list connected devices with `xcrun devicectl list devices`, then run:

```sh
DEVELOPMENT_TEAM="YOUR_TEAM_ID" BUNDLE_ID="com.example.yourbadgeapp" \
  ./scripts/install-iphone.sh "YOUR_DEVICE_ID"
```

The installer requires an explicit device identifier and signing settings; no personal defaults are stored in the repository. Unlock the iPhone, trust your Mac, and enable Developer Mode if iOS requests it.

In the app:

1. Import media using **Photos** or **Files**. Files is useful for GIFs. Choose **Live Photo** to import its motion, or **GIF maker** to create a text animation.
2. Use **Fit circle** to preserve the complete image or **Fill screen** to crop it. Compact uses 10 fps and stronger JPEG compression; Smooth uses 20 fps.
3. Put the badge in pairing mode and disconnect Zrun. Tap **Scan**, select the badge, then **Upload to badge**.
4. Keep the app open until the badge confirms completion.

Bluetooth identifiers are local to each Apple host, so the Mac's saved badge UUIDs are deliberately not hardcoded into the iPhone app. Select the discovered badge; put only the intended badge in pairing mode when their names are identical.

## Live Photos and GIF maker

**Live Photo** opens a picker limited to Live Photos and imports the paired video, including originals downloaded from iCloud when needed. Conversion is silent and uses the selected framing and quality. Choose **Share GIF** to save or share the looping GIF; **Upload to badge** uses the badge-compatible animation format.

**GIF maker** layers a message over a solid color or a cropped background image. Choose text color, size, a 1–6 second duration, and Grow, Explode, Scroll, or Rotate. Grow pulses the text, Explode scatters and reassembles letters, Scroll moves the message across the screen, and Rotate makes a full turn. The round preview shows the badge crop. Tap **Use animation**, then share the GIF or upload. Reopen the maker to edit your draft. Quality controls frame rate and compression; framing is fixed for the maker’s square canvas.

Text uses native Apple font rendering with custom frame animations so the exported GIF and badge upload show the same effect. GIF exports are 368 × 368 square images; the badge’s physical screen crops them to a circle. GIF color quantization can slightly change colors. No additional Photos library permission is requested: pick only the media you want to use.

## Conversion and limits

- Stills: 368 × 368, 8-bit sRGB baseline JPEG, orientation normalized, quality reduced toward a 16 KB target. Uses the bundled stb encoder without restart markers or embedded metadata.
- GIFs: actual per-frame durations resampled to a fixed 10/20 fps timeline, including repeated frames.
- Videos: AVFoundation handles orientation and samples frames without audio.
- Animations: E87-specific MJPG AVI, matching the desktop uploader's container layout and padding.
- Imports limited to 200 MB, animation duration to 30 seconds, converted output to 8 MB. These are application limits, not claims about badge capacity. Badge storage/firmware can reject much smaller files; Compact or shorter clips may help.
- The source's opaque checkerboard/background stays visible. There is no automatic background removal.
- Independent badges do not provide synchronized playback.
- No storage formatting or deletion commands are exposed.

## Validation

```sh
./scripts/test-protocol.sh
./scripts/test-media.sh
```

Protocol tests cover four authentication vectors, CRC-16/XMODEM, frame parsing, and byte-for-byte comparison of AVI output with the Python uploader. The checked-in AVI fixture contains synthetic bytes solely for container comparison, not a playable video.

Media tests run the same UIKit/AVFoundation conversion code in a Mac Catalyst test build. They create PNG, variable-duration GIF, and H.264 MP4 fixtures; verify output size/timing; and check rejection of invalid media. They also check all four text effects and exported GIF dimensions, timing, and looping. Tests do not connect to badges. Live Photo selection and iCloud retrieval require an on-device check.

The app includes the repair-request fix from the desktop uploader, CoreBluetooth write flow control, finite timeouts, cancellation, and explicit rejection of nonzero completion status. Completion is shown only after FILE_COMPLETE and a successful session close.

Protocol and media conversion checks are provided above. Mac Catalyst can run the conversion checks when an iOS simulator is unavailable. Always verify rendering on a physical badge after encoder or protocol changes.

## Source

- `Sources/App.swift`: import, preview, and upload UI.
- `Sources/Media.swift`: image/GIF/video conversion.
- `Sources/Bluetooth.swift`: discovery, authentication, and upload state machine.
- `Sources/Cipher.swift`, `Sources/Wire.swift`: authentication, framing, CRC, and AVI builder.
- `Sources/SelfTest.swift`: debug-only conversion checks.

Build 3 replaces Apple JPEG encoding with the bundled stb baseline encoder for badge decoder compatibility. Transfer success confirms receipt, not successful rendering; physical display verification is required.

Protocol and cipher work derives from `jumpingmushroom/e87_badge` v0.1.14 and `hybridherbst/web-bluetooth-e87`, under MIT. See `LICENSE` and the in-app credits.
