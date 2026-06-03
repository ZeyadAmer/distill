/* ============================================================
   Hotstash Marketplace — shared client module (ES module)

   Loads supabase-js v2 from a CDN and exposes thin helpers that
   the three pages (index / transform / account) consume.

   ⚠️ FILL ME IN: set SUPABASE_URL and SUPABASE_ANON_KEY below.
   The anon key is public/safe to ship (Row Level Security guards
   the data) — but it must still be YOUR project's real value.

   TODO(security): pin the supabase-js CDN import with an SRI
   integrity hash once the exact version is chosen, e.g. host a
   vendored copy under docs/vendor/ or use a Subresource-Integrity
   <script> tag. ESM imports can't carry `integrity` directly, so
   prefer self-hosting the pinned build for production.
   ============================================================ */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── CONFIG — replace both placeholders ───────────────────────
export const SUPABASE_URL = "<SET_ME>";       // e.g. https://abcd1234.supabase.co
export const SUPABASE_ANON_KEY = "<SET_ME>";  // public anon key from Supabase dashboard

// Deep link scheme used by the macOS app. TODO: confirm matches the
// app's registered URL scheme (spec §3.3: hotstash://transform/<slug>).
export const DEEP_LINK_SCHEME = "hotstash";

// Where "Download Hotstash" sends people who don't have the app.
// TODO: point at the App Store / main download URL.
export const DOWNLOAD_URL = "../index.html";

// ─── Schema assumptions (reconcile with backend, spec §2.2) ───
// transforms: id, slug(unique), owner_id, kind('text'|'image'),
//   name, description, icon, category, latest_version, status
//   ('pending'|'live'|'removed'), install_count, rating_avg,
//   rating_count, is_featured, body_hash, created_at, updated_at
// transform_versions: id, transform_id, version, body(jsonb), created_at
// profiles: id, apple_sub, display_name, ...
// We read author display name via an embedded profiles relation:
//   transforms.owner_id -> profiles.id  (FK aliased as `author`).

const TRANSFORM_COLUMNS = `
  id, slug, owner_id, kind, name, description, icon, category,
  latest_version, status, install_count, rating_avg, rating_count,
  is_featured, created_at, updated_at,
  author:profiles!transforms_owner_id_fkey ( display_name )
`;

let _client = null;

/** Lazily create (and reuse) the supabase client. */
export function client() {
  if (_client) return _client;
  if (!isConfigured()) {
    throw new Error(
      "Supabase is not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY in marketplace.js."
    );
  }
  _client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  return _client;
}

/** True once the placeholders have been replaced. */
export function isConfigured() {
  return (
    SUPABASE_URL &&
    SUPABASE_ANON_KEY &&
    !SUPABASE_URL.includes("<SET_ME>") &&
    !SUPABASE_ANON_KEY.includes("<SET_ME>")
  );
}

// ─── Read helpers (anonymous; RLS exposes only status='live') ──

/** Browse live transforms. sort: 'installs' | 'newest'. */
export async function fetchLive({ category = null, sort = "installs" } = {}) {
  let q = client()
    .from("transforms")
    .select(TRANSFORM_COLUMNS)
    .eq("status", "live");

  if (category) q = q.eq("category", category);

  q =
    sort === "newest"
      ? q.order("created_at", { ascending: false })
      : q.order("install_count", { ascending: false });

  const { data, error } = await q.limit(200);
  if (error) throw error;
  return data ?? [];
}

/** Featured live transforms for the top rail. */
export async function fetchFeatured() {
  const { data, error } = await client()
    .from("transforms")
    .select(TRANSFORM_COLUMNS)
    .eq("status", "live")
    .eq("is_featured", true)
    .order("install_count", { ascending: false })
    .limit(12);
  if (error) throw error;
  return data ?? [];
}

/** Client-side text search over name + description of live rows. */
export async function search(term) {
  const clean = (term || "").trim();
  if (!clean) return fetchLive();
  const pattern = `%${clean.replace(/[%_]/g, "")}%`;
  const { data, error } = await client()
    .from("transforms")
    .select(TRANSFORM_COLUMNS)
    .eq("status", "live")
    .or(`name.ilike.${pattern},description.ilike.${pattern}`)
    .order("install_count", { ascending: false })
    .limit(100);
  if (error) throw error;
  return data ?? [];
}

/** Fetch one transform + its latest version body for the detail page. */
export async function fetchBySlug(slug) {
  if (!slug) throw new Error("Missing slug");
  const { data: t, error } = await client()
    .from("transforms")
    .select(TRANSFORM_COLUMNS)
    .eq("slug", slug)
    .eq("status", "live")
    .single();
  if (error) throw error;

  // Latest immutable version row carries the body (spec §2.2).
  const { data: ver, error: vErr } = await client()
    .from("transform_versions")
    .select("version, body, created_at")
    .eq("transform_id", t.id)
    .order("version", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (vErr) throw vErr;

  return { ...t, body: ver?.body ?? null, version: ver?.version ?? t.latest_version };
}

// ─── Auth ─────────────────────────────────────────────────────

export async function signIn() {
  const { error } = await client().auth.signInWithOAuth({
    provider: "apple",
    options: { redirectTo: window.location.href.split("#")[0] },
  });
  if (error) throw error;
}

export async function signOut() {
  const { error } = await client().auth.signOut();
  if (error) throw error;
}

export async function currentSession() {
  const { data, error } = await client().auth.getSession();
  if (error) throw error;
  return data.session ?? null;
}

export function onAuthChange(cb) {
  return client().auth.onAuthStateChange((_event, session) => cb(session));
}

// ─── Author area ──────────────────────────────────────────────

/** Transforms owned by the signed-in author (any status). RLS = write/read own. */
export async function fetchMyTransforms() {
  const session = await currentSession();
  if (!session) throw new Error("Not signed in");
  const { data, error } = await client()
    .from("transforms")
    .select(
      "id, slug, name, kind, category, status, latest_version, install_count, updated_at"
    )
    .eq("owner_id", session.user.id)
    .order("updated_at", { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/**
 * Submit a manifest to the `submit` Edge Function (spec §2.4).
 * Server re-validates, dedups, and routes (pending vs live).
 * Passes the user's access token as a bearer credential.
 */
export async function submitTransform(manifest) {
  const session = await currentSession();
  if (!session) throw new Error("Sign in before submitting");

  const { data, error } = await client().functions.invoke("submit", {
    body: manifest,
    headers: { Authorization: `Bearer ${session.access_token}` },
  });
  if (error) {
    // Surface the function's JSON error body when present.
    let detail = error.message;
    try {
      const ctx = await error.context?.json?.();
      if (ctx?.error) detail = ctx.error;
    } catch (_) { /* ignore parse failure */ }
    throw new Error(detail);
  }
  return data;
}

// ─── Client-side manifest validation (pre-check only) ─────────

const VALID_KINDS = ["text", "image"];
const IMAGE_STEP_TYPES = [
  "resize", "grayscale", "rotate", "flipHorizontal", "convertPNG", "convertWebP",
];
const REQUIRED_FIELDS = ["schemaVersion", "slug", "kind", "name", "category", "body"];

/**
 * Validate a manifest object locally before submit. Mirrors the
 * server gate loosely (spec §2.4) — the Edge Function is the source
 * of truth; this is just fast UX feedback.
 * Returns { ok, errors: string[] }.
 */
export function validateManifest(manifest) {
  const errors = [];
  if (typeof manifest !== "object" || manifest === null) {
    return { ok: false, errors: ["Manifest must be a JSON object."] };
  }

  for (const f of REQUIRED_FIELDS) {
    if (manifest[f] === undefined || manifest[f] === null || manifest[f] === "") {
      errors.push(`Missing required field: ${f}`);
    }
  }

  if (manifest.kind && !VALID_KINDS.includes(manifest.kind)) {
    errors.push(`kind must be one of: ${VALID_KINDS.join(", ")}`);
  }

  if (manifest.slug && !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(manifest.slug)) {
    errors.push("slug must be lowercase kebab-case (a-z, 0-9, hyphens).");
  }

  if (manifest.kind === "text") {
    const js = manifest.body?.js;
    if (typeof js !== "string" || !js.trim()) {
      errors.push("Text transforms need body.js (a non-empty source string).");
    } else {
      if (!/function\s+transform\s*\(/.test(js) && !/transform\s*=/.test(js)) {
        errors.push("body.js must define a global `function transform(input)`.");
      }
      try {
        // Parse-only check: never executes the source.
        new Function(js);
      } catch (e) {
        errors.push(`body.js does not parse: ${e.message}`);
      }
    }
  }

  if (manifest.kind === "image") {
    const steps = manifest.body?.steps;
    if (!Array.isArray(steps) || steps.length === 0) {
      errors.push("Image transforms need a non-empty body.steps array.");
    } else {
      steps.forEach((s, i) => {
        if (!s || !IMAGE_STEP_TYPES.includes(s.type)) {
          errors.push(`Step ${i + 1}: unknown type "${s?.type}".`);
        }
      });
      errors.push(
        "Note: image transforms are authored in the Hotstash app; web only accepts pre-built manifests."
      );
    }
  }

  // Drop the informational image note from the hard-fail decision.
  const hardErrors = errors.filter((e) => !e.startsWith("Note:"));
  return { ok: hardErrors.length === 0, errors };
}

/** Parse + validate a pasted/exported manifest JSON string. */
export function parseManifest(jsonText) {
  let manifest;
  try {
    manifest = JSON.parse(jsonText);
  } catch (e) {
    return { ok: false, manifest: null, errors: [`Invalid JSON: ${e.message}`] };
  }
  const { ok, errors } = validateManifest(manifest);
  return { ok, manifest, errors };
}

/**
 * Build a minimal text-transform manifest from the simple web editor.
 * The server assigns id/version/timestamps; we send the authoring fields.
 */
export function buildTextManifest({ slug, name, description, category, icon, js }) {
  return {
    schemaVersion: 1,
    slug: (slug || "").trim().toLowerCase(),
    kind: "text",
    name: (name || "").trim(),
    description: (description || "").trim(),
    category: (category || "").trim(),
    icon: (icon || "textformat").trim(),
    body: { js: js ?? "" },
  };
}

// ─── Tiny formatting helpers shared by pages ──────────────────

export function formatCount(n) {
  const v = Number(n) || 0;
  if (v >= 1000) return (v / 1000).toFixed(v >= 10000 ? 0 : 1) + "k";
  return String(v);
}

export function starString(avg) {
  const r = Math.round((Number(avg) || 0) * 2) / 2;
  const full = Math.floor(r);
  const half = r - full >= 0.5;
  return "★".repeat(full) + (half ? "½" : "") + "☆".repeat(5 - full - (half ? 1 : 0));
}

/** Escape text for safe insertion into innerHTML contexts. */
export function escapeHtml(str) {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
