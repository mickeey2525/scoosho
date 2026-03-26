# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project (required after adding/removing source files)
xcodegen generate

# Build
xcodebuild -project Scoosho.xcodeproj -scheme Scoosho -configuration Debug build

# Reset screen recording permission and relaunch (needed after every rebuild)
./scripts/reset-permissions.sh
```

There are no tests or linter configured.

## Architecture

Scoosho is a macOS menu bar app (LSUIElement) built with SwiftUI + AppKit. It uses XcodeGen (`project.yml`) to generate the Xcode project — the `.xcodeproj` is gitignored.

**Key flow:** AppDelegate owns SettingsManager and CaptureManager. Hotkeys and menu items trigger capture methods on CaptureManager, which delegates to picker classes for element selection, then captures via ScreenCaptureKit and saves/converts the image.

### Core Components

- **AppDelegate** — Menu bar setup, global hotkeys (Carbon `RegisterEventHotKey`), settings window (manual `NSWindow` + `NSHostingView` since LSUIElement apps can't use SwiftUI `Settings` scene)
- **CaptureManager** — Orchestrates the capture pipeline: picker → `SCScreenshotManager.captureImage` for element captures, `/usr/sbin/screencapture -w` for window captures → PNG/AVIF save → clipboard/notification
- **ElementPicker** — Basic AX element detection via `AXUIElementCopyElementAtPosition`. Blue overlay highlight.
- **DeepElementPicker** — Recursive AX child traversal for Web app support. Scroll up/down to navigate element hierarchy. Orange overlay with depth badge.
- **SettingsManager** — `@AppStorage`-backed preferences (format, save dir, quality, clipboard, notification)

### Important Details

- AVIF encoding uses `CGImageDestinationCreateWithURL` with `public.avif` UTType (macOS 14+), falls back to HEIC
- Hotkey IDs: 1=element (Cmd+Shift+5), 2=window (Cmd+Shift+6), 3=deep element (Cmd+Shift+7)
- Screen coordinates: AX API uses top-left origin, Cocoa uses bottom-left — conversions happen in picker classes
- Entitlements are defined in `project.yml` under `entitlements.properties` — xcodegen regenerates the `.entitlements` file on each run
