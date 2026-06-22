<p align="center">
  <img src="Sources/Assets.xcassets/AppIcon.appiconset/app_icon_128.png" width="96" height="96" alt="QPARK Shot app icon">
</p>

<h1 align="center">QPARK Shot for macOS</h1>

<p align="center">
  Native macOS screenshot capture, annotation, watermarking, and local gallery app built with Swift, AppKit, and SwiftUI.
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-12.3%2B-111111">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="Version" src="https://img.shields.io/badge/version-1.1.0-blue">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

## Overview

QPARK Shot is a local-first screenshot utility for macOS. It runs from the menu bar, captures selected areas or the full screen, opens captures in an editor, and lets you annotate, crop, watermark, copy, share, or save the final PNG.

The app is intentionally simple from an infrastructure point of view: no analytics SDKs, no ad networks, no backend services, and no third-party runtime dependencies.

## Features

### Capture

- Capture a selected screen area with the native macOS picker.
- Capture the full screen from the menu-bar item or an optional global hotkey.
- Add a capture delay of 3, 5, or 10 seconds.
- Configure separate hotkeys for selection capture and full-screen capture.

### Edit

- Draw freehand lines, arrows, rectangles, and text annotations.
- Crop screenshots before export.
- Undo and redo annotation changes.
- Preview the exported image before saving.
- Copy the final image directly to the clipboard.
- Share the final image through the native macOS share sheet.

### Watermark

- Add a text watermark with configurable color, opacity, size, and position.
- Add a logo watermark from a user-selected image file.
- Use a single-position watermark or a tiled diagonal layout.
- Preview watermark output before saving.

### Gallery and Storage

- Save PNG files to `~/Pictures/QPARK Shot` by default.
- Choose a custom save folder in Preferences.
- Browse recent screenshots in a local gallery.
- Open, copy, share, drag, or delete saved screenshots from the gallery.
- Keep current-session captures in an optional editor buffer sidebar.
- Automatically clean temporary files based on local cleanup preferences.

## Requirements

- macOS 12.3 or later
- Xcode 15 or later
- Swift 5

## Build and Run

Open the project in Xcode:

```sh
open QPARKShot.xcodeproj
```

Select the **QPARK Shot** scheme, choose **My Mac**, and press **Run**.

Command-line release build:

```sh
xcodebuild -project QPARKShot.xcodeproj \
  -scheme "QPARK Shot" \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  clean build
```

Generated build output is written under `./build`, which is ignored by Git.

## Permissions

QPARK Shot needs macOS **Screen Recording** permission to capture screen content. On first capture, macOS may ask for this permission. If it does not, enable it manually:

```text
System Settings -> Privacy & Security -> Screen & System Audio Recording
```

After changing the permission, quit and reopen QPARK Shot.

If a stale permission remains after rebuilding the app locally, reset it with:

```sh
tccutil reset ScreenCapture com.qpark.shot
```

The app also uses sandbox file entitlements for local image storage:

- `com.apple.security.assets.pictures.read-write` for the default `~/Pictures/QPARK Shot` folder.
- `com.apple.security.files.user-selected.read-write` for custom folders selected by the user.

## Privacy

Screenshots stay on the user's Mac. QPARK Shot does not collect personal data, does not include analytics, and does not transmit captured screen content.

Saved screenshots are written locally to `~/Pictures/QPARK Shot` unless the user chooses another folder. Temporary captures are stored in the system temporary directory and can be cleared by the app's cleanup preferences.

## Project Structure

```text
QPARKShot.xcodeproj/      Xcode project and shared scheme
Sources/                  App source, Info.plist, entitlements, and app icon
```

The public repository intentionally keeps the source tree small. Local helper scripts, local documentation pages, tests, generated build output, packaged apps, archives, signing material, provisioning profiles, private keys, and environment files are excluded by `.gitignore`.

## Before Publishing

Before pushing or tagging a public release, verify the repository contains only source files and public assets:

```sh
git status --short
git check-ignore -v build scripts docs Tests "build/Release/QPARK Shot.app" || true
```

For App Store or notarized distribution, use a production signing configuration and make sure debug-only entitlements such as `com.apple.security.get-task-allow` are not enabled in the release binary.

## License

QPARK Shot for macOS is open source under the [MIT License](LICENSE).

Copyright (c) 2026 QPARK.

## Contact

Questions, bug reports, and security concerns: [work@qpark.io](mailto:work@qpark.io)
