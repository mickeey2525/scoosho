# Scoosho

macOS native screenshot app focused on capturing specific UI elements with AVIF support.

## Features

- **Element Capture** - Select and capture individual UI elements (sidebar, toolbar, etc.) using Accessibility API
- **Deep Element Capture** - Drill into Web app content with scroll-based depth navigation
- **Window Capture** - Capture entire windows
- **AVIF / PNG** - Save as AVIF (smaller file size) or PNG, configurable in settings
- **Menu Bar App** - Runs in the menu bar, no Dock icon
- **Global Hotkeys** - Capture from anywhere without switching apps

## Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+5` | Element capture |
| `Cmd+Shift+6` | Window capture |
| `Cmd+Shift+7` | Deep element capture (Web) |

### Deep Element Capture

In deep element mode:
- Mouse over to detect the smallest UI element
- **Scroll up** to expand to parent element
- **Scroll down** to narrow to child element
- **Click** to capture, **Escape** to cancel
- Orange highlight with depth indicator badge (e.g. `3/8`)

## Requirements

- macOS 14.0+
- Xcode 16.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Permissions

Scoosho requires:
- **Accessibility** - For UI element detection
- **Screen Recording** - For screen capture

> After rebuilding, screen recording permission may need to be re-granted. Use the helper script:
> ```bash
> ./scripts/reset-permissions.sh
> ```

## Build & Run

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project Scoosho.xcodeproj -scheme Scoosho -configuration Debug build

# Or open in Xcode
open Scoosho.xcodeproj
```

## Settings

Accessible from the menu bar icon > Settings:

- **Image format** - PNG or AVIF (with quality slider)
- **Save location** - Default: Desktop
- **Copy to clipboard** - Auto-copy after capture
- **Show notification** - Notify on save

## Project Structure

```
scoosho/
├── project.yml                     # XcodeGen config
├── scripts/
│   └── reset-permissions.sh        # Reset screen recording permission
└── Scoosho/
    ├── Sources/
    │   ├── ScooshoApp.swift        # App entry point
    │   ├── AppDelegate.swift       # Menu bar, hotkeys
    │   ├── CaptureManager.swift    # Capture, save, AVIF conversion
    │   ├── ElementPicker.swift     # Basic element selection
    │   ├── DeepElementPicker.swift # Web-aware deep element selection
    │   ├── SettingsManager.swift   # UserDefaults settings
    │   └── SettingsView.swift      # Settings UI
    └── Resources/
        ├── Info.plist
        └── Scoosho.entitlements
```

## License

MIT
