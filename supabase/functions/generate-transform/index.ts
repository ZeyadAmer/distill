// =============================================================================
// Hotstash — AI Transform Generation Edge Function
// POST /functions/v1/generate-transform
// =============================================================================
// Turns a plain-language description plus one worked example into a JavaScript
// `transform(input)` function, using Groq. The provider key lives only here.
//
// Gating (spec): Pro-only + per-device daily cap.
//   1. Verify the caller is Pro from the StoreKit entitlement JWS (soft check —
//      see verifyPro).
//   2. Atomically bump a per-device daily counter; refuse over the cap.
//   3. Call the model (Groq) and return { js, name?, description?, icon?, category? }.
//
// The app self-verifies the returned JS locally against the example and may call
// again (a self-correcting retry) with previousAttempt/actualOutput/error set.
// =============================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

// ---- Environment -------------------------------------------------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GROQ_API_KEY = Deno.env.get("GROQ_API_KEY")!;
const GROQ_MODEL = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
const PRO_PRODUCT_ID = Deno.env.get("PRO_PRODUCT_ID") ?? "com.zeyadamer.hotstash.pro";
const DAILY_CAP = Number(Deno.env.get("AI_GEN_DAILY_CAP") ?? "20");
// Optional dev-testing bypass: when set, a caller sending this exact entitlement
// value is treated as Pro. Leave UNSET in production.
const DEV_BYPASS_TOKEN = Deno.env.get("DEV_BYPASS_TOKEN");

// ---- Limits ------------------------------------------------------------------
const MAX_FIELD_LEN = 4000; // description / example fields

// ---- App transform categories (constrains the suggested category) -----------
const CATEGORIES = [
  "Case", "Whitespace", "Lists", "JSON", "Encoding", "Code", "Cleanup", "Wrap",
];

// ---- CORS --------------------------------------------------------------------
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-hotstash-device, x-hotstash-entitlement",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ---- Pro entitlement check ---------------------------------------------------
// Decodes the StoreKit JWS payload and checks the product id, that it isn't
// revoked, and that any expiry is in the future.
//
// ponytail: soft check — decodes the JWS payload WITHOUT verifying Apple's
// signature chain, so a crafted token could pass. The protected resource is a
// free-tier LLM call behind a hard per-device daily cap, so the cap is the real
// cost guard. Upgrade to full x5c-chain / App Store Server API verification if
// abuse shows up.
function verifyPro(jws: string | null): boolean {
  if (!jws) return false;
  const parts = jws.split(".");
  if (parts.length !== 3) return false;
  try {
    const payloadJson = atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"));
    const claims = JSON.parse(payloadJson);
    if (claims.productId !== PRO_PRODUCT_ID) return false;
    if (claims.revocationDate) return false;
    if (typeof claims.expiresDate === "number" && claims.expiresDate < Date.now()) return false;
    return true;
  } catch {
    return false;
  }
}

// ---- Prompt -----------------------------------------------------------
function buildPrompt(body: Record<string, unknown>): string {
  const description = String(body.description ?? "");
  const exampleInput = String(body.exampleInput ?? "");
  const expectedOutput = String(body.expectedOutput ?? "");
  const previousAttempt = body.previousAttempt ? String(body.previousAttempt) : null;
  const actualOutput = body.actualOutput != null ? String(body.actualOutput) : null;
  const error = body.error ? String(body.error) : null;

  let prompt = `You write a single JavaScript function for a text transform.

Rules:
- Output a global function: function transform(input) { ... } that takes a string and returns a string.
- Pure JavaScript only. No network, no DOM, no I/O, no require/import, no comments outside the function.
- transform(${JSON.stringify(exampleInput)}) MUST return exactly ${JSON.stringify(expectedOutput)}.

Task description: ${description}
Example input: ${JSON.stringify(exampleInput)}
Expected output: ${JSON.stringify(expectedOutput)}`;

  if (previousAttempt) {
    prompt += `\n\nA previous attempt did not pass. Fix it.
Previous function:
${previousAttempt}
`;
    if (error) {
      prompt += `It failed to run: ${error}.\n`;
    } else if (actualOutput != null) {
      prompt += `It returned ${JSON.stringify(actualOutput)} instead of ${JSON.stringify(expectedOutput)}.\n`;
    }
  }

  prompt += `\n\nAlso suggest a short name, a one-line description, an emoji icon, and a category (one of: ${CATEGORIES.join(", ")}).`;
  prompt += `\n\nRespond with ONLY a JSON object: {"js": string, "name": string, "description": string, "icon": string, "category": string}. No markdown, no prose outside the JSON.`;
  return prompt;
}

async function callModel(prompt: string): Promise<Record<string, unknown>> {
  // Groq — OpenAI-compatible chat completions, JSON mode. Free tier, global.
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
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Model error (HTTP ${res.status}): ${text.slice(0, 300)}`);
  }
  const data = await res.json();
  const text: string | undefined = data?.choices?.[0]?.message?.content;
  if (!text) throw new Error("Model returned no content.");
  return JSON.parse(text);
}

// ---- Handler -----------------------------------------------------------------
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const device = req.headers.get("x-hotstash-device")?.trim();
  const entitlement = req.headers.get("x-hotstash-entitlement");

  if (!device) return json({ error: "Missing device id" }, 400);
  const isPro = (DEV_BYPASS_TOKEN && entitlement === DEV_BYPASS_TOKEN) || verifyPro(entitlement);
  if (!isPro) return json({ error: "Pro required" }, 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const description = String(body.description ?? "").trim();
  const exampleInput = String(body.exampleInput ?? "");
  const expectedOutput = String(body.expectedOutput ?? "");
  if (!description || !exampleInput || !expectedOutput) {
    return json({ error: "description, exampleInput, and expectedOutput are required" }, 400);
  }
  if (
    description.length > MAX_FIELD_LEN ||
    exampleInput.length > MAX_FIELD_LEN ||
    expectedOutput.length > MAX_FIELD_LEN
  ) {
    return json({ error: "Input too large" }, 400);
  }

  // Rate limit: atomic per-device daily bump.
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: allowed, error: rpcError } = await supabase.rpc("bump_ai_gen", {
    p_device: device,
    p_cap: DAILY_CAP,
  });
  if (rpcError) return json({ error: "Rate-limit check failed" }, 500);
  if (allowed === false) return json({ error: "Daily limit reached" }, 429);

  // Generate.
  try {
    const result = await callModel(buildPrompt(body));
    const js = typeof result.js === "string" ? result.js.trim() : "";
    if (!js) return json({ error: "Model returned no function" }, 502);
    return json({
      js,
      name: result.name ?? null,
      description: result.description ?? null,
      icon: result.icon ?? null,
      category: result.category ?? null,
    });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Generation failed" }, 502);
  }
});
