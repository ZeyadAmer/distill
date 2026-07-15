# AI Transform Generation — Design

**Date:** 2026-07-15
**Status:** Approved (design), pending implementation plan
**Feature:** Let a user describe a transform in plain language plus a worked example, and have the app generate the JavaScript `transform(input)` function automatically.

## Summary

Today, authoring a marketplace transform means hand-writing JavaScript in `TransformBuilderView`. This feature adds an AI assist: the user types a description, an example input, and the expected output; the app generates the JS, verifies it locally against the example, self-corrects on failure, and drops a working function into the existing editor. All existing authoring/testing/saving behavior is unchanged — this only fills the editor faster.

No new code-execution path is introduced. Generated JS runs through the existing isolated `TextTransformEngine` (JavaScriptCore, no network/FS, 250 ms cap, 5 MB output cap). Because the app can run candidate JS locally and compare against the user's expected output, verification is free and local — only text generation crosses the network.

## Decisions (locked)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where inference runs | Supabase Edge Function proxy | Gemini key stays server-side; per-user rate limiting; reuses existing Supabase backend. No key in the binary. |
| Model | Gemini 2.0 Flash | Generous free tier, fast, strong at single-function codegen. Swappable server-side. |
| Generation quality | Self-correcting loop (≤3 attempts) | Uses the free local verifier (isolated JS runner + example output) to retry until the output matches. |
| Gating | Pro-only + ~20/day per-device cap | AI generation becomes a paid-tier perk; caller pool limited to paying users; daily cap bounds shared Gemini quota. |
| Identity for rate limit | Anonymous device id + StoreKit entitlement proof | App has no user accounts. |
| Example input | Required | It is the verification signal for the self-correct loop. |

## App Store compliance

Rule 2.5.2 forbids downloading executable code. This feature **generates** JS on the user's request from a text prompt — it does not download a program from a catalog. The generated code is authored content the user reviews and edits before saving, executed in the same sandboxed interpreter already shipping. This is consistent with the existing marketplace text-transform model, which was already accepted.

## User flow

In `TransformBuilderView`, add a collapsible **"Generate with AI"** panel above the JS editor:

- **Description** — plain language ("convert to kebab-case").
- **Example input** — sample text. Prefilled from the selected clipboard item when the builder is opened from the panel; otherwise empty and editable.
- **Expected output** — what that input should produce.

**Generate** button is disabled until description, example input, and expected output are all non-empty.

On tap:
1. Spinner / progress state; button disabled during generation.
2. On success: generated JS populates the existing editor. Suggested `name`, `description`, `icon`, and `category` also fill their fields (all editable, none overwrite a field the user already edited).
3. A small status badge shows verification result: **Verified ✓** (output matched the example) or **Couldn't verify** (best attempt shown, editor still filled).
4. User reviews, live-tests via the existing test control, and saves as normal.

On failure (network, 403, 429, all attempts exhausted): show a clear inline message. The editor remains fully usable for manual authoring — generation never blocks the existing flow.

## Self-correcting loop (client-side orchestration)

Orchestrated on-device by a new `AITransformGenerator`. Pseudocode:

```
func generate(description, exampleInput, expectedOutput) -> Result {
    var previousJs: String? = nil
    var lastActualOutput: String? = nil
    var lastError: String? = nil

    for attempt in 1...maxAttempts {   // maxAttempts = 3
        let js = try await service.generate(
            description, exampleInput, expectedOutput,
            previousAttempt: previousJs,
            actualOutput: lastActualOutput,
            error: lastError
        )
        let run = TextTransformEngine.run(js: js, input: exampleInput)   // local, free
        if !run.didError && run.output == expectedOutput {
            return .verified(js)                 // ✓ first passing version
        }
        previousJs = js
        lastActualOutput = run.didError ? nil : run.output
        lastError = run.didError ? "script errored or timed out" : nil
    }
    return .unverified(bestJs: previousJs!)      // show best attempt + badge
}
```

- Verification is exact string equality against `expectedOutput`. (Trimming/normalization is out of scope for v1; the example is authoritative.)
- Each retry after the first sends the previous JS plus what it actually produced (or the error) so the model can correct.
- Only `service.generate` hits the network. `TextTransformEngine.run` is local.

## Backend — Supabase Edge Function `generate-transform`

**Request** (`POST`, JSON body):
```json
{
  "description": "string",
  "exampleInput": "string",
  "expectedOutput": "string",
  "previousAttempt": "string | null",
  "actualOutput": "string | null",
  "error": "string | null"
}
```
Headers: device id, StoreKit entitlement proof (transaction / signed receipt).

**Checks (fail fast):**
1. Validate Pro entitlement from the receipt/transaction proof → `403` if absent/invalid.
2. Per-device daily counter in Postgres table `ai_gen_usage` (`device_id`, `day`, `count`); increment; `429` if over `DAILY_CAP` (~20).
3. Basic input validation (non-empty description/example, length bounds).

**Generation:**
- Call Gemini 2.0 Flash REST with a fixed system prompt:
  > Return ONLY a single JavaScript function `function transform(input) { ... }` that takes a string and returns a string. No markdown fences, no comments outside the function, no network, DOM, or I/O. Given the description and example, make `transform(exampleInput)` equal `expectedOutput`. When a previous attempt and its actual output are provided, fix the discrepancy.
- Strip code fences / stray prose defensively; return `{ "js": "..." }`.
- Gemini API key stored in Supabase secrets, never shipped in the app.

**Rate-limit table:**
```sql
create table ai_gen_usage (
  device_id text not null,
  day date not null,
  count int not null default 0,
  primary key (device_id, day)
);
```

## Files

| File | Change |
|------|--------|
| `Hotstash/UI/Marketplace/TransformBuilderView.swift` | Add the "Generate with AI" panel UI; wire fields and Generate action to `AITransformGenerator`; render verified/unverified badge; prefill example input from context. |
| `Hotstash/Transforms/Marketplace/AITransformGenerator.swift` | **New.** Orchestrates the self-correct loop: calls the service, runs `TextTransformEngine.run`, compares to expected output, retries ≤3×, returns verified/unverified result. `@MainActor`, injectable service. |
| `Hotstash/Transforms/Marketplace/Networking/AIGenerationService.swift` | **New.** `AIGenerationService` protocol + `SupabaseAIGenerationService` (calls the edge function, attaches device id + entitlement proof) + `MockAIGenerationService` (deterministic, for tests/previews). Mirrors the existing `MarketplaceService` / provider pattern. |
| `Hotstash/Monetization/PurchaseManager` | Reuse existing Pro check; expose the receipt/transaction proof needed for the request header. No behavior change beyond surfacing the proof. |
| Supabase project | **New** edge function `generate-transform`; **new** table `ai_gen_usage`; Gemini key in secrets. |
| `HotstashTests/AITransformGeneratorTests.swift` | **New.** Loop logic with `MockAIGenerationService`: verified-on-first, verified-after-retry, all-fail→unverified, error passthrough, disabled-state guards. |
| `HotstashTests/AIGenerationServiceTests.swift` | **New.** Request shaping / header attachment / decode, using a stubbed transport. |

## Reuse / non-negotiables

- **No second JS execution path.** Verification goes through the existing `TextTransformEngine.run` choke point.
- Mirror the existing `MarketplaceService` protocol + `MarketplaceServiceProvider` pattern for `AIGenerationService`, including a mock implementation for tests and SwiftUI previews.
- Reuse the polymorphic `icon: String` convention and `TransformManifest` fields for any suggested metadata — no new schema.
- **Fail-safe:** every failure mode (network, 403, 429, unverified, exhausted retries) leaves the editor usable for manual authoring. Generation is additive, never a gate.
- Do not add host-bridged objects to the JS sandbox. Generated code runs with the same zero-bridge isolation as all other transforms.

## Out of scope (v1, YAGNI)

- Output normalization/fuzzy matching in verification (exact equality only).
- Multiple example pairs (single input/output pair).
- Streaming generation UI.
- Image-transform (`kind == .image`) generation — text transforms only.
- Server-side caching of identical prompts.
- User accounts (device-scoped identity is sufficient for rate limiting).

## Testing

- **Unit (loop):** `AITransformGeneratorTests` with `MockAIGenerationService` returning scripted candidates — cover verified-first, verified-after-N, all-fail, script-error passthrough, and input-guard/disabled states.
- **Unit (service):** request body + headers shaped correctly; response decode; error mapping (403/429/network).
- **Existing coverage** for `TextTransformEngine` and the marketplace path is unchanged and continues to guard the execution/verification substrate.
- Manual: end-to-end against the real edge function on a signed build (Pro entitlement + daily-cap behavior).
