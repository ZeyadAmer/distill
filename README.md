# Hotstash

A fast, lightweight clipboard history manager for macOS. Lives in your menu bar — out of the way until you need it.

## Features

- **Clipboard history** — automatically saves everything you copy: text (with formatting), links, code, images, and files
- **Instant access** — global hotkey opens your history from anywhere
- **Direct paste** — Return or double-click pastes straight into the app you were using; ⇧Return pastes as plain text
- **Paste Stack** — ⌘-click several items, then every ⌘V pastes the next one in sequence
- **Search everything** — including text inside copied screenshots (OCR) and page titles of copied links
- **Pin items** — keep important clips at the top permanently
- **Transform** — uppercase, lowercase, trim, JSON formatting, and a community marketplace of transforms
- **Multi-paste** — combine multiple recent items and copy them joined inline or on new lines
- **Excluded apps** — never record copies from apps you choose (password managers are skipped automatically)
- **Drag out** — drag any history item straight into another app
- **iCloud sync** — history follows you across your Macs (private database)

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Hotstash.xcodeproj
```

Then build with ⌘B or **Product → Run**.

## Usage

1. Launch Hotstash — a flame icon appears in the menu bar
2. Copy anything as normal (⌘C)
3. Press the global hotkey (set in Settings) or click the menu bar icon to open history
4. Arrow keys or mouse to browse, Return to copy the selected item
5. Press ⌘V in your target app to paste

## Project Structure

```
Hotstash/
├── App/                  # AppDelegate, app entry point
├── Core/                 # ClipboardMonitor, ClipboardStore, ClipboardItem
├── Monetization/         # PurchaseManager, TrialManager (StoreKit 2)
├── Resources/            # Assets, Info.plist, entitlements
└── UI/
    ├── MenuBar/          # MenuBarManager (status item)
    ├── MultiPaste/       # MultiPastePanel
    ├── Onboarding/       # First-launch onboarding
    ├── Panel/            # ClipboardPanel, ClipboardPanelVC, PasteEngine
    ├── Settings/         # SettingsWindowController
    └── Transforms/       # Text transform definitions and picker
```

## License

MIT © 2026 Zeyad Amer
