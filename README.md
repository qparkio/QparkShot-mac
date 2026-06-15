<p align="center">
  <img src="Sources/Assets.xcassets/AppIcon.appiconset/app_icon_128.png" width="96" height="96" alt="QparkShot-mac logo">
</p>

<h1 align="center">QparkShot-mac</h1>

<p align="center">
  Native macOS screenshot capture, annotation, watermarking, and local gallery app built with Swift, AppKit, and SwiftUI.
</p>

<p align="center">
  <img alt="macOS" src="https://img.shields.io/badge/macOS-12.3%2B-111111">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-blue">
</p>

## Overview

QparkShot-mac is the open-source macOS version of QPARK Shot. It runs as a lightweight menu-bar utility, captures a selected area of the screen with the native macOS picker, and lets you annotate, watermark, copy, share, or save the result.

The app is intentionally local-first: there are no analytics SDKs, backend calls, ad networks, or third-party runtime dependencies in this repository.

## Features

- Capture screenshots with a global hotkey or the menu-bar item.
- Annotate with freehand drawing, arrows, rectangles, text, and crop tools.
- Add text and logo watermarks with single-position or tiled diagonal layouts.
- Manage recent screenshots in a local gallery with copy, share, reveal, and delete actions.
- Export PNG files to `~/Pictures/QPARK Shot` by default, or choose another folder.
- Automatically clean up temporary screenshots based on local preferences.
- Follow the system appearance, or force light/dark mode with native macOS vibrancy.

## Requirements

- macOS 12.3 or later
- Xcode 15 or later

## Build And Run

Open the project in Xcode:

```sh
open QPARKShot.xcodeproj
```

Select the **QPARK Shot** scheme and press **Run**.

Command-line release build:

```sh
xcodebuild -project QPARKShot.xcodeproj -scheme "QPARK Shot" -configuration Release -derivedDataPath build/DerivedData clean build
```

Build output is intentionally written under `./build`, which is ignored by Git. Do not commit `.app`, `.dmg`, `.pkg`, DerivedData, archives, local scripts, local docs, signing material, or private environment files.

## Permissions

QPARK Shot needs macOS **Screen Recording** permission to capture the screen. On first capture, enable the app in:

```text
System Settings -> Privacy & Security -> Screen & System Audio Recording
```

Then quit and reopen the app.

If a stale permission remains after rebuilding, reset it manually:

```sh
tccutil reset ScreenCapture com.qpark.shot
```

## Project Structure

```text
QPARKShot.xcodeproj/      Xcode project and shared scheme
Sources/                  App source, Info.plist, entitlements, app icon
```

Local helper scripts, local documentation pages, tests, and generated build output are intentionally excluded from the public repository.

## Privacy

Screenshots are processed locally on the Mac. The app does not collect personal data, does not include analytics, and does not transmit captured screen content.

The privacy policy is simple: screenshots stay on the user's Mac, and the app has no analytics or network backend.

## Security Before Publishing

Before pushing this repository publicly, verify that the publish set contains only app source, project files, checked-in image assets, and GitHub metadata:

```sh
git status --short
git check-ignore -v build scripts docs Tests "build/Release/QPARK Shot.app" || true
```

The repository `.gitignore` excludes build output, DerivedData, local scripts, local docs, local tests, local IDE state, signing certificates, provisioning profiles, private keys, environment files, and packaged app artifacts.

## License

QparkShot-mac is open source under the [MIT License](LICENSE).

Copyright (c) 2026 QPARK.

## Contact

Questions, bug reports, and security concerns: [work@qpark.io](mailto:work@qpark.io)
