# Transforms Marketplace — Next Steps / Deploy Checklist

The marketplace is **built, compiling, and unit-tested**, and merged to `main`.
The macOS app runs **fully today against an offline mock** (no backend needed) —
you can create transforms, use them locally, import/export, and browse a sample
storefront. The pieces below are what's required to take it **live** and ship to
the App Store. None could be done in this environment (no Supabase project, no
code-signing/provisioning, no second Mac).

## What works right now (no setup)
- Author text (JS) and image (declarative step) transforms in Settings → Marketplace → My Transforms.
- Use them from the transform picker alongside built-ins (Pro-gated like existing transforms).
- Import/export `.hotstashtransform` files.
- Browse/search/install against the built-in **mock** storefront.
- 66 unit tests pass: manifest codec, JS sandbox (timeout/output/error), image engine, registry merge, library CRUD, DTO decoding, config fallback.

---

## 1. Stand up Supabase (backend → live)
See `supabase/README.md` for the full runbook. Summary:
1. Create a Supabase project.
2. `supabase db push` the migrations in `supabase/migrations/` (schema, RLS, RPCs).
3. `supabase functions deploy submit notify-owner`.
4. Set secrets (the human must provide — none are committed):
   - `OWNER_EMAIL`, `NOTIFY_FROM_EMAIL`, `RESEND_API_KEY` (or other email provider).
   - **`NOTIFY_SHARED_SECRET`** — now effectively required; `notify-owner` rejects calls without it OR the service-role bearer (security fix). Set it.
   - Apple OAuth: `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` (+ client id / Services ID).
5. Promote your account to admin: `update profiles set is_admin = true where ...`.
6. Fill the app + website config:
   - App: edit `Hotstash/Resources/Supabase.plist` → real `SupabaseURL` + `SupabaseAnonKey` (until then the app uses the mock automatically).
   - Website: edit `docs/marketplace/marketplace.js` → `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `DEEP_LINK_SCHEME` (`hotstash`), `DOWNLOAD_URL`.

## 2. Sign in with Apple
- The entitlement `com.apple.developer.applesignin` is in `project.yml`/entitlements.
- Enable "Sign in with Apple" capability for the App ID in the Apple Developer portal, and configure the Apple provider in Supabase Auth (Services ID, key, team id).
- Web sign-in needs the Apple Services ID + return URL pointed at Supabase.

## 3. CloudKit (carried over from the storage cycle — still pending)
- Deploy the CloudKit schema (record types `ClipboardItem`, `StoredTransform`) Dev→Production in the CloudKit Dashboard before App Store release. `StoredTransform` now also syncs, so confirm it's in the deployed schema.

## 4. Code signing / device
- This Mac isn't registered in the developer account, so signed builds fail here. Register the device (or use a provisioning profile) and build with `-allowProvisioningUpdates`.

## 5. App Store review risks (decide before submission)
- **JavaScriptCore marketplace (2.5.2):** downloaded JS runs in `JSContext` and matches the app's purpose (text transforms), which is the explicit 2.5.2 carve-out — but a "marketplace of code" can draw scrutiny. Be ready to explain the sandbox (no I/O, time/output limits) to review.
- **Private SPI:** `JSContextGroupSetExecutionTimeLimit` (via `HotstashJSCore.h`) is private JavaScriptCore SPI used to kill runaway scripts. Widely used in shipping apps but technically SPI — a possible rejection vector. Alternative if rejected: a watchdog-thread interrupt (less reliable against tight loops) or restricting authored JS expressiveness.

## 6. Security follow-ups before public launch (from the security review)
Applied already: strict PostgREST escaping (Finding 1), client image-scale cap (Finding 3), `notify-owner` auth gate (Finding 4).
Still recommended (hardening, not blocking — backend not yet live):
- **Finding 2:** Move `ratings`/`reviews`/`reports` inserts behind `SECURITY DEFINER` RPCs that set `profile_id := auth.uid()` server-side, instead of the client sending a JWT-decoded `profile_id` (RLS currently enforces correctness, but this removes the field from the attack surface).
- **Finding 5:** Add a per-author submission rate limit / cooldown in the `submit` Edge Function so a compromised returning-author account can't spam `live` transforms.
- **Website SRI:** self-host a pinned `supabase-js` build under `docs/vendor/` instead of the CDN ESM import (SRI can't be applied to dynamic ESM imports).

## 7. Manual verification once live (can't be automated here)
- End-to-end: create → publish (first-time → pending → you approve) → install on another Mac → rate/review → report → admin remove → version auto-update pulls.
- Deep link: `open hotstash://transform/<slug>` opens Settings → Marketplace → that transform.
- Sign in with Apple on both app and website.
- Concealed-copy + CloudKit two-Mac checks still pending from the storage cycle.

## Architecture map (for future work)
- Engine: `Hotstash/Transforms/Marketplace/` — `TransformManifest`, `TextTransformEngine` (JS), `ImageTransformEngine` (steps), `MarketplaceTransform` (Transform adapter), `StoredTransform` (SwiftData), `MarketplaceLibrary` (local CRUD + import/export), `Networking/` (service protocol + Supabase REST + mock).
- UI: `Hotstash/UI/Marketplace/` — storefront, detail, builder, my-transforms, auth, router; Settings → Marketplace tab.
- Backend: `supabase/`. Website: `docs/marketplace/`.
- Spec: `docs/superpowers/specs/2026-06-03-transforms-marketplace-design.md`.
