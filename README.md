# Hotstash

A fast, lightweight clipboard history manager for macOS. Lives in your menu bar — out of the way until you need it.

## Features

- **Clipboard history** — automatically saves everything you copy: text, links, code, images
- **Instant access** — global hotkey opens your history from anywhere
- **Quick copy** — select any item and press Return to copy it back, then ⌘V to paste
- **Search** — filter history as you type
- **Pin items** — keep important clips at the top permanently
- **Transform** — uppercase, lowercase, trim, and other text transforms before copying
- **Multi-paste** — combine multiple recent items and copy them joined inline or on new lines
- **Privacy-first** — all data stays on your Mac, nothing is sent anywhere

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
