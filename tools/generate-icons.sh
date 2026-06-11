#!/bin/bash
# Regenerates the macOS AppIcon.appiconset from tools/render-icon.swift
set -euo pipefail

cd "$(dirname "$0")/.."
ICONSET="Hotstash/Resources/Assets.xcassets/AppIcon.appiconset"
MASTER="$ICONSET/AppIcon-1024.png"

swift tools/render-icon.swift "$MASTER"

scale() { sips -z "$1" "$1" "$MASTER" --out "$ICONSET/$2" >/dev/null; }

scale 16   AppIcon-16.png
scale 32   AppIcon-16@2x.png
scale 32   AppIcon-32.png
scale 64   AppIcon-32@2x.png
scale 64   AppIcon-64.png
scale 128  AppIcon-64@2x.png
scale 128  AppIcon-128.png
scale 256  AppIcon-128@2x.png
scale 256  AppIcon-256.png
scale 512  AppIcon-256@2x.png
scale 512  AppIcon-512.png
cp "$MASTER" "$ICONSET/AppIcon-512@2x.png"

# iOS: single full-bleed opaque 1024 (system masks the corners itself)
IOS_ICONSET="HotstashIOS/Assets.xcassets/AppIcon.appiconset"
swift tools/render-icon.swift "$IOS_ICONSET/AppIcon-1024.png" --ios

echo "iconsets regenerated: $ICONSET, $IOS_ICONSET"
