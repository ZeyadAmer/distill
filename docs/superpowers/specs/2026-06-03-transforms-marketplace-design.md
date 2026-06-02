# Design: Transforms Marketplace

**Date:** 2026-06-03
**Status:** Approved (pending spec review)
**Scope:** macOS app "Hotstash" + its static website + a new Supabase backend.

## Summary

Let users create their own clipboard transforms, use them locally, and
optionally publish them so other users can discover and install them — "like
Claude skills" for text/image transformation. Transforms are local-first;
publishing is opt-in.

Two execution models behind one manifest format:
- **Text transforms** run author-supplied JavaScript in a sandboxed
  `JSContext` (string in → string out).
- **Image transforms** are a declarative pipeline of whitelisted native ops
  (no code), run via Core Image.

Distribution uses a new **Supabase** backend (the existing website is static
`docs/index.html` on GitHub Pages with no server; CloudKit can't be driven from
a web page, so Supabase is the fit). The macOS app is the full marketplace
(browse / install / create / publish); the website hosts public discovery pages
that deep-link into the app.

This is one spec covering three modules, expected to become **three
implementation plans** built in order: **Engine → Backend → Surfaces**.

## Decisions (locked during brainstorming)

| Decision | Choice |
| --- | --- |
| Build as | One spec, three phased plans (engine, backend, surfaces) |
| Text transform format | Author JavaScript run in sandboxed `JSContext` |
| Image transform format | Declarative whitelisted native step pipeline (no code) |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) |
| Auth | Sign in with Apple only |
| Monetization | All transforms free; transform feature gated behind app purchase (Pro) |
| Moderation | Auto-gate + dedup; first-time authors manual-approve; returning authors auto-publish + notify owner; report/takedown |
| Discovery | Search + categories, install count + sort, star ratings + reviews, featured |
| Updates | Silent auto-update to latest validated version |
| Web vs app | App = full marketplace; web = discovery/landing + author management/upload |
| Installed transforms | Persist in SwiftData; ride existing CloudKit sync across the user's Macs |
| Deep link | `hotstash://transform/<slug>` ("Open in Hotstash") |

## Non-Goals (v1)

- Paid transforms / payouts / revenue share.
- Running transforms anywhere but the macOS app (web is discovery only).
- Image transforms authored in JS (image = declarative steps only).
- iOS (iOS targets remain shelved from the prior cycle).
- Real-time collaboration or transform forking/diffing.

## App Store Compliance Note

Guideline 2.5.2 forbids downloading executable code **except** scripts run by
`JavaScriptCore`/WebKit that do not change the app's advertised purpose. Text
transforms run in `JavaScriptCore` and are squarely within a
clipboard-transform app's purpose, so this is defensible — but a "marketplace of
code" can draw reviewer scrutiny. Mitigations (sandbox with no I/O, execution
time limit, output cap, server-side validation, moderation) are part of the
design. Treat App Store review as a known risk to monitor.

---

## Module 1 — Engine (local foundation)

### 1.1 Transform manifest

One JSON format, two `kind`s. All marketplace/custom transforms are represented
by this manifest, whether local-only or published.

```json
{
  "schemaVersion": 1,
  "id": "0f8c…uuid",
  "slug": "slugify",
  "version": 3,
  "kind": "text",
  "name": "Slugify",
  "description": "Lowercase, replace non-alphanumerics with hyphens.",
  "icon": "textformat",
  "category": "Cleanup",
  "authorId": "apple-sub-or-profile-uuid",
  "authorName": "Zeyad",
  "createdAt": "2026-06-03T00:00:00Z",
  "updatedAt": "2026-06-03T00:00:00Z",
  "body": { "js": "function transform(input){ return input… }" }
}
```

- `kind: "text"` → `body = { "js": "<source>" }`. Source must define a global
  `function transform(input) -> string`.
- `kind: "image"` → `body = { "steps": [ {type, params…}, … ] }` (see 1.3).
- `category` reuses the existing `TransformCategory` raw values plus a new
  `community` bucket is NOT added — authors pick an existing category.
- `slug` is unique per published transform; `id` (UUID) is the stable identity;
  `version` increments on each publish.

### 1.2 Text execution — `TextTransformEngine`

- Runs `body.js` in a fresh `JSContext` per evaluation with **nothing bridged
  in** — no `XMLHttpRequest`, no filesystem, no pasteboard, no host objects. The
  context can only see the input string and standard JS built-ins.
- **Execution time limit:** `JSContextGroupSetExecutionTimeLimit` set to a hard
  cap (default **250 ms**); on timeout the evaluation is aborted.
- **Output cap:** result over a max length (default **5 MB**) is rejected.
- Runs **off the main actor** (the engine is an `actor` or uses a background
  queue); the `apply(to:)` adapter awaits the result with its own wall-clock
  guard.
- **Failure contract:** on any error, timeout, non-string return, or thrown
  exception, return the **original input unchanged** (matches the existing
  `Transform` protocol guarantee that transforms never crash).

```swift
struct TextTransformResult { let output: String; let didError: Bool }

actor TextTransformEngine {
    func run(js: String, input: String,
             timeLimitMs: Int = 250, maxOutputBytes: Int = 5_000_000)
        -> TextTransformResult
}
```

### 1.3 Image execution — `ImageTransformEngine`

- Interprets `body.steps` against native ops. The step `type` whitelist mirrors
  today's built-in image transforms so no new image capability is introduced:
  `resize` (params: scale or maxDim), `grayscale`, `rotate` (params: degrees ∈
  {90,180,270}), `flipHorizontal`, `convertPNG`, `convertWebP`. Unknown step
  types are skipped (forward-compatible) and flagged in validation.
- Operates on `Data` → `Data`, reusing the existing image helpers where possible.
- Same never-crash contract: on failure, return original data.

```swift
struct ImageStep: Codable { let type: String; let params: [String: ParamValue] }

enum ImageTransformEngine {
    static func run(steps: [ImageStep], imageData: Data) -> Data
}
```

### 1.4 Registry integration — `MarketplaceTransform`

An adapter conforming to the existing `Transform` protocol wraps a manifest so
custom/installed transforms slot into `TransformRegistry` alongside built-ins.

```swift
struct MarketplaceTransform: Transform {
    let manifest: TransformManifest
    var id: String { manifest.slug }      // stable, snake/kebab id
    var name: String { manifest.name }
    var icon: String { manifest.icon }
    var category: TransformCategory { TransformCategory(rawValue: manifest.category) ?? .cleanup }
    var applicableTo: [ContentType] { manifest.kind == .image ? [.image] : [] }

    func apply(to input: String) -> String { /* TextTransformEngine, sync-bridged */ }
    func applyToImageData(_ data: Data) -> Data? { /* ImageTransformEngine */ }
}
```

`TransformRegistry` gains a source for custom/installed transforms:
- `var all` stays the built-in list.
- New `var allIncludingCustom: [any Transform]` merges built-ins + installed
  manifests loaded from the store. Existing `orderedAll`/`enabled`/`suggested`
  build on the merged list. Built-in ids and custom slugs share one namespace;
  a custom slug colliding with a built-in id is rejected at install time.

### 1.5 Local persistence — `StoredTransform` (SwiftData)

A SwiftData `@Model` (same CloudKit rules as the prior cycle: defaulted props,
no unique constraints, externalStorage for large blobs) representing a
transform in the local library:

```swift
@Model final class StoredTransform {
    var id: UUID = UUID()
    var slug: String = ""
    var manifestJSON: Data = Data()     // the full manifest
    var origin: String = "local"        // "local" (mine, draft/published) | "installed"
    var installedVersion: Int = 0
    var isPublished: Bool = false
    var updatedAt: Date = .now
}
```

- Drafts + published-by-me + installed all live here.
- Rides the existing `NSPersistentCloudKitContainer`/SwiftData CloudKit sync so a
  user's library follows them across Macs.
- Registry reads installed/local manifests from here at launch.

### 1.6 Authoring & sharing (in-app)

- **Builder UI**: metadata form (name, description, icon picker, category) +
  editor: a JS code editor for `kind: text`, a step picker/orderer for
  `kind: image`. A **live test pane**: sample input → engine → output, showing
  errors/timeouts.
- **Import/Export**: `.hotstashtransform` files (the manifest JSON) for offline
  sharing independent of the marketplace.

---

## Module 2 — Backend (Supabase)

### 2.1 Auth

- **Sign in with Apple** only, via Supabase Auth, used by both the macOS app and
  the website. Browsing/downloading is anonymous; publishing/rating/reporting
  requires sign-in. First sign-in creates a `profiles` row capturing a display
  name (author handle).

### 2.2 Schema (Postgres)

- `profiles(id, apple_sub, display_name, created_at, is_admin)`
- `transforms(id, slug unique, owner_id, kind, name, description, icon,
  category, latest_version, status, install_count, rating_avg, rating_count,
  is_featured, body_hash, created_at, updated_at)`
  - `status ∈ {pending, live, removed}`.
  - `body_hash` = SHA-256 of the normalized body (for dedup).
- `transform_versions(id, transform_id, version, body, created_at)` — immutable
  history; powers silent auto-update and rollback.
- `installs(transform_id, profile_id, created_at)` — drives `install_count`
  (also allow anonymous install increments via Edge Function without a row).
- `ratings(transform_id, profile_id, stars, created_at)` — unique per
  (transform, profile).
- `reviews(id, transform_id, profile_id, body, status, created_at)` —
  `status ∈ {live, removed}`.
- `reports(id, target_type, target_id, reporter_id, reason, status, created_at)`
  — `target_type ∈ {transform, review}`.

### 2.3 RLS policies

- Public (anon) **read**: `transforms.status = 'live'`, their live versions,
  live reviews, aggregate counts.
- Authenticated **write own**: a profile may insert/update its own transforms,
  ratings (one per transform), reviews, reports.
- **Admin** (you, `is_admin`): full read/write; the only role that can set
  `status` to `live`/`removed` or `is_featured`.

### 2.4 Submission Edge Function

`POST /submit` (authenticated). Pipeline:
1. **Validate**: manifest schema valid; `kind` consistent with `body`; for text,
   JS parses and a **sandboxed test-run** on sample input completes within the
   time/output limits; for image, every step `type` is in the whitelist with
   valid params.
2. **Dedup**: compute `body_hash`; reject if an existing **live** transform has
   the same hash (exact duplicate). Near-duplicate `name`/`slug` is flagged
   (not rejected) for owner review.
3. **Route**:
   - Author has **no prior live transform** → insert `status = pending`
     (awaits admin approval).
   - Author **has** prior live transforms → insert `status = live` immediately,
     create the version row, and **email the owner** (you) to spot-check.
4. **Update** (existing transform, new version) → same validate+dedup; on pass,
   append a `transform_versions` row and bump `latest_version`; clients
   auto-pull (Module 1.5 / Module 3).

### 2.5 Notifications & admin

- Owner notification on (a) a pending first-time submission and (b) a returning
  author's auto-published transform — email via a Supabase database webhook /
  Edge Function on insert.
- Admin actions (approve pending, remove, feature, resolve report, roll back a
  version) via authenticated admin-only RPCs; a minimal admin view can live on
  the website behind `is_admin`.

---

## Module 3 — Surfaces

### 3.1 In-app marketplace UI (full experience)

- **Browse**: list of `live` transforms with name, author, install count, rating,
  category badge; **featured** row at top.
- **Search**: full-text over name/description (Postgres `tsvector`); **category**
  filter; **sort** by most-installed / newest.
- **Detail**: description, author, version, rating + reviews, Install button.
- **Install/uninstall**: downloads the manifest into `StoredTransform`
  (`origin = installed`), increments install count; uninstall removes it.
- **My transforms**: manage drafts/published, publish/update, see status
  (pending/live/removed), update badges.
- **Ratings/reviews**: rate 1–5, write a review, report a transform or review.
- **Gating**: install/browse allowed for any user; **using** a transform
  requires the app's Pro entitlement (existing `TrialManager` gate), same as
  built-in transforms today.

### 3.2 Website (static `docs/` + Supabase JS)

- Per-transform discovery pages `/t/<slug>`: name, description, author, install
  count, rating, a read-only preview of the transform, and an **"Open in
  Hotstash"** button → `hotstash://transform/<slug>` deep link.
- Author area (Sign in with Apple): manage my transforms, upload (uploading an
  exported manifest / a simple text-JS editor), see status. (Image pipeline
  authoring stays in-app; web upload accepts already-built manifests.)
- Implemented as additional static pages + JS calling Supabase directly; no
  server added.

### 3.3 Deep link

- Register `hotstash://` URL scheme. `hotstash://transform/<slug>` opens the app
  to that transform's detail (fetched from Supabase), offering Install.

### 3.4 Updates

- On launch and periodically, the app compares each installed transform's
  `installedVersion` to the backend `latest_version` and **silently pulls** the
  newer validated version into `StoredTransform`. Each pulled version was
  gate-validated server-side. Rollback is possible because versions are
  immutable in `transform_versions`.

---

## Security Model

- **Text sandbox**: `JSContext` with no bridged host objects → no network, no
  filesystem, no pasteboard. Hard execution time limit + output-size cap, run
  off the main actor. Worst case of a malicious/buggy transform = wrong output
  or a caught timeout; **no data exfiltration is possible**.
- **Image**: only whitelisted native ops with validated params; no code.
- **Silent auto-update risk**: a compromised author account could change a
  transform's behavior on installed machines. Bounded by the sandbox (no I/O),
  re-validated server-side on every version, owner notification, report/takedown,
  and version rollback.
- **Backend**: RLS enforces public-read-of-live / write-own / admin-only status
  changes. Validation + dedup run server-side in the Edge Function (never trust
  the client). Sign in with Apple is the only identity.
- **Gating**: transform execution requires Pro; marketplace browsing does not.

## Testing Strategy

**Engine (unit, Swift Testing, in-memory):**
- Manifest codec round-trip (text + image).
- `TextTransformEngine`: correct output; timeout aborts; infinite loop killed;
  output-cap rejection; non-string return → input unchanged; thrown error →
  input unchanged.
- `ImageTransformEngine`: each whitelisted step; unknown step skipped; bad params
  → input unchanged.
- `body_hash` normalization + dedup equality.
- Registry merge (built-in + installed); slug/id collision rejected; gating.

**Backend:**
- RLS policy tests (anon read live only; write-own; admin-only status changes).
- Submission Edge Function: validation pass/fail cases; dedup rejection;
  first-timer→pending vs returning→live routing; update appends version.

**Manual (cannot be unit-tested here):**
- End-to-end: create → publish → (first-time) approve → install on another Mac →
  rate/review → report → remove → version update auto-pulls.
- Deep link `hotstash://transform/<slug>` opens detail.
- Sign in with Apple on app + web.
- App Store review outcome for the JavaScriptCore marketplace.

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| App Store 2.5.2 rejection (code marketplace) | JavaScriptCore exception; transforms match app purpose; sandbox + moderation; monitor review, be ready to argue/limit. |
| Malicious/runaway JS | No-I/O sandbox, execution time limit, output cap, off-main-actor. |
| Silent auto-update abuse | Server-side re-validation per version, owner notify, report/takedown, rollback. |
| Solo-dev moderation load | Auto-gate + dedup; only first-time authors block on you; returning authors async-notify. |
| Supabase cost/abuse | Anonymous read only; authenticated writes; rate-limit submit Edge Function. |
| Review spam | Reviews carry their own report/takedown + status. |
| CloudKit-synced installed JS across Macs | Same sandbox guarantees apply on every device. |

## Open Items for Implementation Plans

- Exact JS editor component for the in-app builder (start with a plain
  monospaced `NSTextView`; syntax highlighting optional later).
- Whether anonymous installs increment `install_count` via Edge Function or
  require sign-in (default: allow anonymous increment, no row).
- Featured curation surface (admin web view vs direct DB).
- Rate-limit thresholds for the submit Edge Function.
- Phasing detail: Engine plan must ship a usable local "custom transforms"
  feature before Backend/ Surfaces plans begin.
