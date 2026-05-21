# Hotstash — App Store Submission Guide

## What's Built

Complete macOS clipboard manager:
- 30 Swift source files
- 23 transforms (case, whitespace, JSON, encoding, cleanup, wrap)
- Floating panel (CMD+Shift+V), menubar icon, full settings UI
- 14-day trial → StoreKit 2 one-time purchase ($9.99)
- Onboarding flow with accessibility permission request
- App Sandbox enabled, Hardened Runtime enabled

## Step 1 — Install Xcode

Download from the Mac App Store (search "Xcode", it's free, ~15 GB).

## Step 2 — Get Apple Distribution Certificate

Your current cert is **Developer ID Application** (for direct distribution).
App Store requires **Apple Distribution** cert.

1. Open Xcode → Preferences → Accounts → select `zeyad.amer@nawy.com`
2. Click "Manage Certificates…"
3. Click **+** → "Apple Distribution"
4. Xcode creates and installs it automatically

## Step 3 — Create App in App Store Connect

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. My Apps → **+** → New App
   - Platform: **macOS**
   - Name: **Hotstash**
   - Bundle ID: `com.zeyadamer.hotstash`
   - SKU: `hotstash-001`
3. Fill in metadata (copy from plan):
   - Subtitle: `Clipboard history + transforms`
   - Category: Productivity / Developer Tools
   - Description: (from hotstash-plan.md section 8.3)
   - Keywords: `hotstash,clipboard,paste,transform,productivity,developer,JSON,formatter,history,menubar`
4. Privacy: **Data Not Collected** ✓, No Tracking ✓

## Step 4 — Create IAP Product

In App Store Connect → Hotstash → In-App Purchases:
1. **+** → Non-Consumable
2. Reference Name: `Hotstash Pro`
3. Product ID: `com.zeyadamer.hotstash.pro`
4. Price: **$9.99 / Tier 9** (≈ 499 EGP)
5. Display name: `Hotstash Pro`
6. Description: `Unlock full Hotstash — unlimited history and all transforms.`
7. Submit for review with the app

## Step 5 — Open and Build in Xcode

```bash
open /Users/zeyadamer/workspace/personal/hotstash/Hotstash.xcodeproj
```

1. Select the `Hotstash` target
2. Signing & Capabilities → set Team to **Zeyad Amer (4PMSUCCX7P)**
3. Code Signing: Automatic ✓ (Xcode manages provisioning)
4. Build: **Product → Build** (⌘B) — fix any errors

## Step 6 — App Icon

The icon PNG files are generated from the concept in `image.png`.
They are at: `Hotstash/Resources/Assets.xcassets/AppIcon.appiconset/`

For App Store, the 1024×1024 image must have **no alpha channel**:
```bash
sips -s format png --out /tmp/AppIcon-1024-noalpha.png \
  Hotstash/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```
Then replace `AppIcon-512@2x.png` with the no-alpha version if validation fails.

## Step 7 — Archive for App Store

1. In Xcode, select scheme **Hotstash** and destination **Any Mac**
2. **Product → Archive** (takes 1–3 min)
3. Organizer opens → select the archive → **Distribute App**
4. Choose **App Store Connect**
5. Choose **Upload**
6. Follow the wizard (sign with Apple Distribution cert)
7. Wait ~15 min for processing in App Store Connect

## Step 8 — Submit for Review

1. In App Store Connect → Hotstash → prepare a submission
2. Select the uploaded build
3. Fill export compliance: **No encryption** → No
4. Add screenshots:
   - Panel open with clipboard items visible
   - Transform being applied (before/after)
   - Settings window
5. Submit for review

## Known Items to Complete

- [ ] Replace placeholder icon with a polished 1024×1024 no-alpha PNG
- [ ] Add App Store screenshots (1280×800 minimum)
- [ ] Test on a real Mac with Xcode before submitting
- [ ] Grant Accessibility permission when running for first time (needed for paste simulation)
- [ ] Create the IAP product in App Store Connect (Step 4)
- [ ] Complete the StoreKit sandbox test

## Build Configuration

| Setting | Value |
|---------|-------|
| Bundle ID | `com.zeyadamer.hotstash` |
| Team | Zeyad Amer (4PMSUCCX7P) |
| Min macOS | 13.0 Ventura |
| Deployment | Mac App Store |
| IAP Product | `com.zeyadamer.hotstash.pro` |
| Price | $9.99 |
| Sandbox | Enabled |

## Testing the Trial

UserDefaults key `firstLaunchDate` drives the 14-day trial.
To test expired trial quickly:
```swift
// Paste into Xcode console or add temporarily to AppDelegate:
UserDefaults.standard.set(Date().addingTimeInterval(-15 * 86400), forKey: "firstLaunchDate")
```
