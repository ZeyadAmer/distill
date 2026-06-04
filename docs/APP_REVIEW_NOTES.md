# App Review Notes — Hotstash 5.0

Paste this (or adapt it) into **App Store Connect → Version → App Review Information → Notes** when submitting 5.0.

---

## Why Hotstash requests Accessibility permission

Hotstash is a clipboard manager. Its single most-requested feature — and the
core reason people install a third-party clipboard tool at all — is being able
to pick a past clipboard item and have it dropped **directly into the document
or text field they were just working in**, without manually switching back and
pressing ⌘V.

Delivering that one-keystroke paste requires synthesizing a ⌘V keystroke into
the previously-focused application. macOS only allows this when the user has
granted **Accessibility** permission (System Settings → Privacy & Security →
Accessibility). This is the same mechanism every other clipboard manager,
text-expander, and automation utility on the Mac uses for this exact purpose.

### How we use it

- **Only** to post a ⌘V key event into the app the user was using, immediately
  after they choose an item (press Return, double-click, or trigger a Quick
  Transform shortcut).
- We never read the contents of other apps, never observe keystrokes, and never
  monitor the system in the background. We hold no AX observers — we only post a
  single paste event on an explicit user action.

### It is strictly opt-in and degrades gracefully

- The permission is requested only when the user first invokes a paste action,
  with the standard system prompt.
- If the user declines, **nothing breaks**: the selected item is still placed on
  the system clipboard, and the user simply presses ⌘V themselves. The app is
  fully functional without the permission.
- A clear status row in Settings → General → "Direct Paste" explains what the
  permission does and links to the System Settings pane.

### Sandbox

The app remains fully sandboxed (`com.apple.security.app-sandbox`). No new
sandbox exceptions or private entitlements are used — Accessibility is a
user-granted TCC permission, not an entitlement.

---

## What's new in 5.0 (for reviewers)

1. **Return / double-click to paste** — direct paste into the focused app (the
   Accessibility feature above).
2. **Arrow-key navigation** — ↑/↓ move through history while typing still
   searches.
3. **Quick Transform shortcuts** — up to five user-defined global shortcuts that
   apply a text transform (e.g. UPPERCASE) to the clipboard and paste the
   result. Same opt-in Accessibility paste.
4. **Update reminder** — on launch the app checks the public iTunes lookup API
   for its own App Store version and, if a newer one exists, shows a prompt that
   links to the App Store listing. The app does **not** self-update; it only
   directs the user to the store.

## Network usage

The only outbound network call at launch is to
`https://itunes.apple.com/lookup?bundleId=com.zeyadamer.hotstash` to compare the
installed version against the App Store version. No personal data is sent.
