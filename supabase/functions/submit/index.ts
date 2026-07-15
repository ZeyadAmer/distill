// =============================================================================
// Hotstash Transforms Marketplace — Submission Edge Function
// POST /functions/v1/submit   (authenticated)
// =============================================================================
// Pipeline (spec §2.4):
//   1. Validate  — manifest schema; kind matches body; text JS parse heuristic;
//                  image step whitelist + param validation.
//   2. Dedup     — compute body_hash; reject exact LIVE duplicate; flag near-dup
//                  name (not rejected).
//   3. Route     — EVERY new transform => pending (admin must approve before it
//                  goes live). No author is auto-published.
//   4. Update    — existing transform + new version => validate+dedup, append a
//                  transform_versions row, bump latest_version, set status back
//                  to pending so the new code is re-reviewed before it's public.
//
// Runs with the SERVICE ROLE key (bypasses RLS) but ALWAYS verifies the caller's
// JWT first and forces owner_id = the authenticated user. Never trust the client.
//
// Returns JSON: { status: 'pending' | 'live' | 'rejected', reason?, transformId?,
//                 version?, nearDuplicate? }
// =============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// ---- Environment -------------------------------------------------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Anon key is used only to validate the incoming user JWT.
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
// notify-owner function is invoked for pending + returning-author-live events.
const NOTIFY_FUNCTION_URL =
  Deno.env.get("NOTIFY_FUNCTION_URL") ??
  `${SUPABASE_URL}/functions/v1/notify-owner`;

// ---- Limits / whitelist (mirror Module 1 engine) ----------------------------
const MAX_JS_BYTES = 256 * 1024; // 256 KB source cap (sanity, not the 5MB output cap)
const MAX_NAME_LEN = 80;
const MAX_DESC_LEN = 2000;
const MAX_STEPS = 32;

const IMAGE_STEP_WHITELIST = new Set([
  "resize",
  "grayscale",
  "rotate",
  "flipHorizontal",
  "convertPNG",
  "convertWebP",
]);
const ROTATE_DEGREES = new Set([90, 180, 270]);

// ---- CORS --------------------------------------------------------------------
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// =============================================================================
// Body hashing — MUST match the macOS app's normalization exactly.
//   text  -> sha256("text:" + js)
//   image -> sha256("image:" + JSON.stringify(steps with sorted keys))
// =============================================================================
function sortedStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(sortedStringify).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    const obj = value as Record<string, unknown>;
    const keys = Object.keys(obj).sort();
    const entries = keys.map(
      (k) => `${JSON.stringify(k)}:${sortedStringify(obj[k])}`,
    );
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value);
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function computeBodyHash(
  kind: "text" | "image",
  body: ManifestBody,
): Promise<string> {
  if (kind === "text") {
    return sha256Hex("text:" + (body.js ?? ""));
  }
  return sha256Hex("image:" + sortedStringify(body.steps ?? []));
}

// =============================================================================
// Types
// =============================================================================
interface ManifestBody {
  js?: string;
  steps?: Array<{ type: string; params?: Record<string, unknown> }>;
}

interface Manifest {
  schemaVersion?: number;
  id?: string;
  slug?: string;
  version?: number;
  kind?: "text" | "image";
  name?: string;
  description?: string;
  icon?: string;
  category?: string;
  body?: ManifestBody;
}

interface ValidationResult {
  ok: boolean;
  reason?: string;
}

// =============================================================================
// Validation
// =============================================================================
function validateManifestSchema(m: Manifest): ValidationResult {
  if (typeof m !== "object" || m === null) {
    return { ok: false, reason: "manifest must be an object" };
  }
  if (m.schemaVersion !== 1) {
    return { ok: false, reason: "unsupported schemaVersion (expected 1)" };
  }
  if (m.kind !== "text" && m.kind !== "image") {
    return { ok: false, reason: "kind must be 'text' or 'image'" };
  }
  if (typeof m.slug !== "string" || !/^[a-z0-9][a-z0-9-]{1,63}$/.test(m.slug)) {
    return {
      ok: false,
      reason: "slug must be lowercase kebab-case, 2-64 chars",
    };
  }
  if (typeof m.name !== "string" || m.name.trim().length === 0) {
    return { ok: false, reason: "name is required" };
  }
  if (m.name.length > MAX_NAME_LEN) {
    return { ok: false, reason: `name exceeds ${MAX_NAME_LEN} chars` };
  }
  if (typeof m.description === "string" && m.description.length > MAX_DESC_LEN) {
    return { ok: false, reason: `description exceeds ${MAX_DESC_LEN} chars` };
  }
  if (typeof m.body !== "object" || m.body === null) {
    return { ok: false, reason: "body is required" };
  }
  return { ok: true };
}

// Text body validation. We CANNOT run a JSContext here, so we apply a parse
// heuristic: source is non-empty, within size cap, syntactically parseable, and
// defines a global `function transform`. Authoritative sandboxed execution still
// happens client-side (Module 1.2) on every run.
function validateTextBody(body: ManifestBody): ValidationResult {
  const js = body.js;
  if (typeof js !== "string" || js.trim().length === 0) {
    return { ok: false, reason: "text body.js must be a non-empty string" };
  }
  if (js.length > MAX_JS_BYTES) {
    return { ok: false, reason: `js source exceeds ${MAX_JS_BYTES} bytes` };
  }

  // Must define a global function named `transform`. Accept declarations and
  // assignment forms: `function transform(`, `transform = function`,
  // `var/let/const transform = (...) =>` etc.
  const definesTransform =
    /\bfunction\s+transform\s*\(/.test(js) ||
    /\btransform\s*=\s*function\b/.test(js) ||
    /\b(?:var|let|const)\s+transform\s*=\s*(?:async\s*)?\(?[^=]*=>/.test(js);
  if (!definesTransform) {
    return {
      ok: false,
      reason: "text source must define a global `function transform(input)`",
    };
  }

  // Syntax check via the JS parser without executing: wrapping in `Function`
  // compiles but does not run the body. Throws SyntaxError on malformed source.
  try {
    // deno-lint-ignore no-new-func
    new Function(js);
  } catch (e) {
    return {
      ok: false,
      reason: `js failed to parse: ${(e as Error).message}`,
    };
  }

  return { ok: true };
}

// Image body validation: every step.type whitelisted with valid params.
function validateImageBody(body: ManifestBody): ValidationResult {
  const steps = body.steps;
  if (!Array.isArray(steps) || steps.length === 0) {
    return { ok: false, reason: "image body.steps must be a non-empty array" };
  }
  if (steps.length > MAX_STEPS) {
    return { ok: false, reason: `too many steps (max ${MAX_STEPS})` };
  }

  for (let i = 0; i < steps.length; i++) {
    const step = steps[i];
    if (typeof step?.type !== "string") {
      return { ok: false, reason: `step ${i}: missing type` };
    }
    if (!IMAGE_STEP_WHITELIST.has(step.type)) {
      return { ok: false, reason: `step ${i}: type '${step.type}' not allowed` };
    }
    const p = step.params ?? {};

    switch (step.type) {
      case "resize": {
        const scale = p.scale as number | undefined;
        const maxDim = p.maxDim as number | undefined;
        const hasScale = typeof scale === "number" && scale > 0 && scale <= 10;
        const hasMaxDim =
          typeof maxDim === "number" && maxDim > 0 && maxDim <= 10000;
        if (!hasScale && !hasMaxDim) {
          return {
            ok: false,
            reason: `step ${i} (resize): needs scale (0-10) or maxDim (1-10000)`,
          };
        }
        break;
      }
      case "rotate": {
        const degrees = p.degrees as number | undefined;
        if (typeof degrees !== "number" || !ROTATE_DEGREES.has(degrees)) {
          return {
            ok: false,
            reason: `step ${i} (rotate): degrees must be 90, 180 or 270`,
          };
        }
        break;
      }
      // grayscale, flipHorizontal, convertPNG, convertWebP take no params.
      case "grayscale":
      case "flipHorizontal":
      case "convertPNG":
      case "convertWebP":
        break;
    }
  }
  return { ok: true };
}

function validateManifest(m: Manifest): ValidationResult {
  const schema = validateManifestSchema(m);
  if (!schema.ok) return schema;
  return m.kind === "text"
    ? validateTextBody(m.body!)
    : validateImageBody(m.body!);
}

// =============================================================================
// Notification (fire-and-forget; never blocks the response)
// =============================================================================
async function notifyOwner(
  event: "pending" | "returning_live",
  payload: Record<string, unknown>,
): Promise<void> {
  try {
    await fetch(NOTIFY_FUNCTION_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
      body: JSON.stringify({ event, ...payload }),
    });
  } catch (e) {
    // Notification failures must not fail the submission.
    console.error("notify-owner failed:", (e as Error).message);
  }
}

// =============================================================================
// Handler
// =============================================================================
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ status: "rejected", reason: "method not allowed" }, 405);
  }

  // ---- AuthN: verify the caller's JWT --------------------------------------
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json({ status: "rejected", reason: "missing authorization" }, 401);
  }

  const userClient: SupabaseClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return json({ status: "rejected", reason: "invalid session" }, 401);
  }

  // ---- Parse + validate manifest -------------------------------------------
  let manifest: Manifest;
  try {
    const parsed = await req.json();
    manifest = (parsed?.manifest ?? parsed) as Manifest;
  } catch {
    return json({ status: "rejected", reason: "invalid JSON body" }, 400);
  }

  const validation = validateManifest(manifest);
  if (!validation.ok) {
    return json({ status: "rejected", reason: validation.reason }, 422);
  }

  const kind = manifest.kind!;
  const body = manifest.body!;
  const bodyHash = await computeBodyHash(kind, body);

  // Service-role client for privileged writes (bypasses RLS; owner forced below).
  const admin: SupabaseClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ---- Dedup: reject exact LIVE duplicate by body_hash ---------------------
  const { data: dup, error: dupErr } = await admin
    .from("transforms")
    .select("id, slug, owner_id")
    .eq("status", "live")
    .eq("body_hash", bodyHash)
    .limit(1)
    .maybeSingle();
  if (dupErr) {
    return json({ status: "rejected", reason: "dedup lookup failed" }, 500);
  }

  // ---- Is this an update to an EXISTING transform owned by the caller? -----
  // Match by slug; only the owner may push a new version.
  const { data: existing, error: existErr } = await admin
    .from("transforms")
    .select("id, owner_id, latest_version, status, body_hash")
    .eq("slug", manifest.slug!)
    .maybeSingle();
  if (existErr) {
    return json({ status: "rejected", reason: "slug lookup failed" }, 500);
  }

  // Exact live duplicate that is NOT the same transform being updated => reject.
  if (dup && (!existing || dup.id !== existing.id)) {
    return json(
      { status: "rejected", reason: "an identical transform is already live" },
      409,
    );
  }

  // Near-duplicate NAME flag (informational, not a rejection).
  let nearDuplicate = false;
  if (!existing) {
    const { data: nameMatches } = await admin
      .from("transforms")
      .select("id")
      .eq("status", "live")
      .ilike("name", manifest.name!.trim())
      .limit(1);
    nearDuplicate = !!(nameMatches && nameMatches.length > 0);
  }

  // =========================================================================
  // UPDATE path: existing transform, new version.
  // =========================================================================
  if (existing) {
    if (existing.owner_id !== user.id) {
      return json(
        { status: "rejected", reason: "slug owned by another author" },
        403,
      );
    }

    // Body unchanged: still apply metadata edits (name/description/icon/category)
    // without creating a new version. body_hash only covers the executable body.
    if (existing.body_hash === bodyHash) {
      const { error: metaErr } = await admin
        .from("transforms")
        .update({
          kind,
          name: manifest.name,
          description: manifest.description ?? "",
          icon: manifest.icon ?? "textformat",
          category: manifest.category ?? "cleanup",
        })
        .eq("id", existing.id);
      if (metaErr) {
        return json({ status: "rejected", reason: "failed to update metadata" }, 500);
      }
      return json({
        status: existing.status,
        reason: "metadata updated (body unchanged)",
        transformId: existing.id,
        version: existing.latest_version,
      });
    }

    const nextVersion = existing.latest_version + 1;

    const { error: verErr } = await admin.from("transform_versions").insert({
      transform_id: existing.id,
      version: nextVersion,
      body,
      body_hash: bodyHash,
    });
    if (verErr) {
      return json({ status: "rejected", reason: "failed to append version" }, 500);
    }

    // Every new version must be re-reviewed before it goes public, so the
    // transform is set back to pending. This closes the "approve v1, then push
    // a malicious v2 that auto-publishes" bypass. Users who already installed
    // keep their local copy; the listing hides until an admin re-approves.
    const { error: updErr } = await admin
      .from("transforms")
      .update({
        kind,
        name: manifest.name,
        description: manifest.description ?? "",
        icon: manifest.icon ?? "textformat",
        category: manifest.category ?? "cleanup",
        latest_version: nextVersion,
        status: "pending",
        body_hash: bodyHash,
      })
      .eq("id", existing.id);
    if (updErr) {
      return json({ status: "rejected", reason: "failed to update head" }, 500);
    }

    // Notify admin that an updated transform is awaiting review.
    await notifyOwner("pending", {
      transformId: existing.id,
      slug: manifest.slug,
      name: manifest.name,
      authorId: user.id,
      version: nextVersion,
      update: true,
    });

    return json({
      status: "pending",
      transformId: existing.id,
      version: nextVersion,
      nearDuplicate,
    });
  }

  // =========================================================================
  // NEW transform path: every new transform requires admin review.
  // =========================================================================
  const { data: inserted, error: insErr } = await admin
    .from("transforms")
    .insert({
      slug: manifest.slug,
      owner_id: user.id, // forced — never trust client-provided owner
      kind,
      name: manifest.name,
      description: manifest.description ?? "",
      icon: manifest.icon ?? "textformat",
      category: manifest.category ?? "cleanup",
      latest_version: 1,
      status: "pending",
      body_hash: bodyHash,
    })
    .select("id")
    .single();
  if (insErr || !inserted) {
    // Unique violation on slug => slug taken.
    const reason = insErr?.code === "23505" ? "slug already taken" : "insert failed";
    return json({ status: "rejected", reason }, insErr?.code === "23505" ? 409 : 500);
  }

  const { error: ver1Err } = await admin.from("transform_versions").insert({
    transform_id: inserted.id,
    version: 1,
    body,
    body_hash: bodyHash,
  });
  if (ver1Err) {
    return json({ status: "rejected", reason: "failed to write version 1" }, 500);
  }

  // Notify admin that a new transform is awaiting review.
  await notifyOwner("pending", {
    transformId: inserted.id,
    slug: manifest.slug,
    name: manifest.name,
    authorId: user.id,
    version: 1,
    update: false,
  });

  return json({
    status: "pending",
    transformId: inserted.id,
    version: 1,
    nearDuplicate,
  });
});
