// =============================================================================
// Hotstash Transforms Marketplace — Owner Notification Edge Function
// POST /functions/v1/notify-owner   (service-role / DB webhook only)
// =============================================================================
// Emails the marketplace owner when:
//   * event = "pending"        -> a first-time author submitted (awaits approval)
//   * event = "returning_live" -> a returning author auto-published (spot-check)
//
// Invoked two ways (either works; pick one in deploy):
//   1. By the `submit` function directly (already wired in submit/index.ts).
//   2. By a Supabase Database Webhook on INSERT into public.transforms — see
//      README for the trigger payload mapping.
//
// Email is sent via Resend (https://resend.com). Swap the provider block below
// for SendGrid/Postmark/SES if preferred — only sendEmail() needs to change.
// =============================================================================

// ---- Environment / secrets ---------------------------------------------------
// TODO(human): set these in `supabase secrets set` before deploy. See README.
const OWNER_EMAIL = Deno.env.get("OWNER_EMAIL") ?? ""; // where notifications land
const FROM_EMAIL =
  Deno.env.get("NOTIFY_FROM_EMAIL") ?? "Hotstash <notify@hotstash.app>";
// TODO(human): REAL PROVIDER KEY GOES HERE — create at resend.com and store as a
// secret. Never commit a real key. Placeholder: <SET_IN_SUPABASE_SECRETS>
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
// Optional: gate this function so only the service role / webhook can call it.
const NOTIFY_SHARED_SECRET = Deno.env.get("NOTIFY_SHARED_SECRET") ?? "";

const RESEND_ENDPOINT = "https://api.resend.com/emails";

interface NotifyPayload {
  event?: "pending" | "returning_live";
  // Direct-call shape (from submit):
  transformId?: string;
  slug?: string;
  name?: string;
  authorId?: string;
  version?: number;
  update?: boolean;
  // DB-webhook shape (supabase_functions webhook): { type, table, record, ... }
  type?: string;
  table?: string;
  record?: Record<string, unknown>;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Normalize either invocation shape into a single notification descriptor.
function normalize(p: NotifyPayload): {
  event: "pending" | "returning_live";
  slug: string;
  name: string;
  transformId: string;
  version: number;
  isUpdate: boolean;
} | null {
  // DB webhook form: derive event from the inserted record's status.
  if (p.record && typeof p.record === "object") {
    const r = p.record;
    const status = String(r.status ?? "");
    if (status !== "pending" && status !== "live") return null;
    return {
      event: status === "pending" ? "pending" : "returning_live",
      slug: String(r.slug ?? ""),
      name: String(r.name ?? ""),
      transformId: String(r.id ?? ""),
      version: Number(r.latest_version ?? 1),
      isUpdate: false,
    };
  }
  // Direct-call form from submit().
  if (p.event === "pending" || p.event === "returning_live") {
    return {
      event: p.event,
      slug: p.slug ?? "",
      name: p.name ?? "",
      transformId: p.transformId ?? "",
      version: p.version ?? 1,
      isUpdate: !!p.update,
    };
  }
  return null;
}

function buildEmail(n: NonNullable<ReturnType<typeof normalize>>): {
  subject: string;
  html: string;
} {
  if (n.event === "pending") {
    return {
      subject: `[Hotstash] New submission awaiting approval: ${n.name}`,
      html:
        `<h2>First-time author submission</h2>` +
        `<p><strong>${escapeHtml(n.name)}</strong> (<code>${escapeHtml(n.slug)}</code>) ` +
        `is <strong>pending</strong> your approval.</p>` +
        `<p>Transform ID: <code>${escapeHtml(n.transformId)}</code></p>` +
        `<p>Approve via the admin RPC <code>approve_transform('${escapeHtml(n.transformId)}')</code> ` +
        `or the admin web view.</p>`,
    };
  }
  // returning_live
  const verb = n.isUpdate ? "published an update to" : "auto-published";
  return {
    subject: `[Hotstash] Returning author ${verb}: ${n.name}`,
    html:
      `<h2>Returning-author auto-publish</h2>` +
      `<p><strong>${escapeHtml(n.name)}</strong> (<code>${escapeHtml(n.slug)}</code>) ` +
      `is now <strong>live</strong> (version ${n.version}). This was auto-approved ` +
      `because the author already has live transforms — please spot-check.</p>` +
      `<p>Transform ID: <code>${escapeHtml(n.transformId)}</code></p>` +
      `<p>Remove via <code>remove_transform('${escapeHtml(n.transformId)}')</code> if needed.</p>`,
  };
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

// ---- Provider call (Resend). Swap this function for another provider. -------
async function sendEmail(subject: string, html: string): Promise<boolean> {
  if (!RESEND_API_KEY || !OWNER_EMAIL) {
    // No provider configured — log so the event is not silently lost.
    console.warn(
      "notify-owner: RESEND_API_KEY/OWNER_EMAIL not set; skipping email.",
      { subject },
    );
    return false;
  }
  const res = await fetch(RESEND_ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [OWNER_EMAIL],
      subject,
      html,
    }),
  });
  if (!res.ok) {
    console.error("notify-owner: provider error", res.status, await res.text());
    return false;
  }
  return true;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ ok: false, reason: "method not allowed" }, 405);
  }

  // Auth gate. This endpoint must never be open: an unauthenticated caller
  // could flood the owner's inbox. Accept EITHER the shared secret (if set) OR
  // the service-role bearer token that `submit` sends. If neither is configured
  // nor presented, reject.
  {
    const provided = req.headers.get("x-notify-secret") ?? "";
    const auth = req.headers.get("authorization") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const secretOK = NOTIFY_SHARED_SECRET.length > 0 && provided === NOTIFY_SHARED_SECRET;
    const bearerOK = serviceKey.length > 0 && auth === `Bearer ${serviceKey}`;
    if (!secretOK && !bearerOK) {
      return json({ ok: false, reason: "unauthorized" }, 401);
    }
  }

  let payload: NotifyPayload;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, reason: "invalid JSON" }, 400);
  }

  const n = normalize(payload);
  if (!n) {
    return json({ ok: false, reason: "unrecognized payload / event" }, 422);
  }

  const { subject, html } = buildEmail(n);
  const sent = await sendEmail(subject, html);

  return json({ ok: true, sent, event: n.event });
});
