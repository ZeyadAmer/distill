// =============================================================================
// Hotstash — Backfill Worked Examples (one-off admin op)
// POST /functions/v1/backfill-examples
// =============================================================================
// Reads live TEXT transforms that have no example yet, asks the model to read
// each transform(input) function and produce a representative input/output pair,
// and writes it back to transforms.example_input / example_output.
//
// Auth: a single shared secret in the `x-backfill-token` header must equal the
// BACKFILL_TOKEN env var. This is a maintenance endpoint, not a user API.
//
// Idempotent: only touches rows where example_input IS NULL, so it's safe to
// re-run until it reports remaining = 0.
//
// ponytail: model-computed pair (not executed) — the model reads the JS and
// states input+output. Good enough for a display hint on already admin-approved
// transforms. Run the JS in a sandbox instead if accuracy ever matters.
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY")!;
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
const BACKFILL_TOKEN = Deno.env.get("BACKFILL_TOKEN");

// Rows per invocation. Keeps us under the Edge Function wall-clock limit and the
// Groq free-tier rate limit; re-invoke until `remaining` is 0.
const BATCH = Number(Deno.env.get("BACKFILL_BATCH") ?? "25");
const MAX_LEN = 4000; // clamp stored example strings

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface VersionRow {
  version: number;
  body: { js?: string };
}
interface TransformRow {
  id: string;
  name: string;
  description: string;
  latest_version: number;
  transform_versions: VersionRow[];
}

interface Example {
  exampleInput: string;
  exampleOutput: string;
}

function buildPrompt(name: string, description: string, js: string): string {
  return `You are given a JavaScript text transform. Read the function and produce ONE short, realistic worked example that a user browsing a transforms marketplace would find illustrative.

Transform name: ${name}
Description: ${description}
Function:
${js}

Determine exampleInput (a natural short input string for this transform) and exampleOutput (exactly what transform(exampleInput) returns — trace the code precisely, do not guess).

Respond with ONLY a JSON object: {"exampleInput": string, "exampleOutput": string}. No markdown, no prose.`;
}

async function callModel(prompt: string): Promise<Example | null> {
  const res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${GROQ_API_KEY}`,
    },
    body: JSON.stringify({
      model: GROQ_MODEL,
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) throw new Error(`Model HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`);
  const data = await res.json();
  const text: string | undefined = data?.choices?.[0]?.message?.content;
  if (!text) return null;
  const parsed = JSON.parse(text);
  const input = typeof parsed.exampleInput === "string" ? parsed.exampleInput : "";
  const output = typeof parsed.exampleOutput === "string" ? parsed.exampleOutput : "";
  if (!input || !output) return null;
  return { exampleInput: input.slice(0, MAX_LEN), exampleOutput: output.slice(0, MAX_LEN) };
}

function latestJS(row: TransformRow): string | null {
  const versions = row.transform_versions ?? [];
  const match = versions.find((v) => v.version === row.latest_version) ?? versions[0];
  const js = match?.body?.js;
  return typeof js === "string" && js.trim() ? js : null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!BACKFILL_TOKEN || req.headers.get("x-backfill-token") !== BACKFILL_TOKEN) {
    return json({ error: "Forbidden" }, 403);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Live text transforms still missing an example, newest first.
  const { data: rows, error } = await supabase
    .from("transforms")
    .select("id,name,description,latest_version,transform_versions(version,body)")
    .eq("status", "live")
    .eq("kind", "text")
    .is("example_input", null)
    .order("created_at", { ascending: false })
    .limit(BATCH);

  if (error) return json({ error: `Query failed: ${error.message}` }, 500);

  let updated = 0;
  const skipped: { id: string; reason: string }[] = [];

  for (const row of (rows ?? []) as TransformRow[]) {
    const js = latestJS(row);
    if (!js) {
      skipped.push({ id: row.id, reason: "no js body" });
      continue;
    }
    try {
      const example = await callModel(buildPrompt(row.name, row.description ?? "", js));
      if (!example) {
        skipped.push({ id: row.id, reason: "model returned no example" });
        continue;
      }
      const { error: upErr } = await supabase
        .from("transforms")
        .update({
          example_input: example.exampleInput,
          example_output: example.exampleOutput,
        })
        .eq("id", row.id);
      if (upErr) {
        skipped.push({ id: row.id, reason: `update failed: ${upErr.message}` });
        continue;
      }
      updated++;
    } catch (e) {
      skipped.push({ id: row.id, reason: e instanceof Error ? e.message : "error" });
    }
  }

  // How many still lack an example after this batch.
  const { count: remaining } = await supabase
    .from("transforms")
    .select("id", { count: "exact", head: true })
    .eq("status", "live")
    .eq("kind", "text")
    .is("example_input", null);

  return json({ updated, skipped, remaining: remaining ?? null });
});
