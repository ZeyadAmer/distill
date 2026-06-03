# Hotstash Transforms Marketplace — Supabase Backend

Production-ready Supabase backend for the Hotstash transforms marketplace
(spec: `docs/superpowers/specs/2026-06-03-transforms-marketplace-design.md`,
Module 2). This directory contains everything needed to deploy; it does **not**
self-deploy and makes no network calls.

```
supabase/
├── config.toml                  # project config (Apple auth, functions)
├── migrations/
│   ├── 0001_init.sql            # tables, enums, indexes, triggers, FTS vector
│   ├── 0002_rls.sql             # RLS enable + all policies
│   └── 0003_rpc.sql             # admin RPCs + record_install
└── functions/
    ├── submit/index.ts          # validate + dedup + route + version + notify
    └── notify-owner/index.ts    # owner email (Resend; provider-swappable)
```

## Architecture recap

- **profiles** ↔ `auth.users` (1:1, created on first Sign in with Apple).
- **transforms** = mutable head; **transform_versions** = immutable history.
- **installs / ratings / reviews / reports** with trigger-maintained counters
  (`install_count`, `rating_avg`, `rating_count`).
- **RLS**: anon reads only `live`; authenticated writes own (ratings unique per
  transform via PK); admins (`profiles.is_admin`) are the only role that can set
  `status` or `is_featured`.
- **submit** Edge Function (service role) does all validation/dedup/routing so
  the client is never trusted; first-time authors → `pending`, returning authors
  → `live` + owner notification.
- **notify-owner** Edge Function emails you on pending + returning-author-live.

---

## Deploy steps

### 0. Prerequisites
- Supabase CLI installed (`brew install supabase/tap/supabase`).
- A Supabase project created at <https://supabase.com/dashboard>.
- An Apple Developer account with Sign in with Apple configured.

### 1. Link the project
```bash
supabase login
supabase link --project-ref <YOUR_PROJECT_REF>
```
Then set `project_id` in `config.toml` to `<YOUR_PROJECT_REF>`.

### 2. Push the schema
```bash
supabase db push
```
This applies `0001_init.sql` → `0002_rls.sql` → `0003_rpc.sql` in order.

### 3. Configure Sign in with Apple
1. In Apple Developer: create a **Services ID** (web client id, e.g.
   `app.hotstash.web`), enable Sign in with Apple, add return URL
   `https://<project-ref>.supabase.co/auth/v1/callback`.
2. Create a **Key** (.p8) with Sign in with Apple enabled; note the **Key ID**
   and your **Team ID**.
3. Generate the Apple client secret JWT (Supabase docs: "Login with Apple").
4. In `config.toml`, set `[auth.external.apple].client_id`.
5. Add the macOS app **bundle id** as an additional audience (native Sign in
   with Apple), and ensure the deep link redirect `hotstash://auth-callback`
   is in `additional_redirect_urls`.

### 4. Set secrets
> Never commit real keys. All values below are placeholders.

```bash
# Apple client secret JWT (regenerate before its ~6-month expiry):
supabase secrets set SUPABASE_AUTH_EXTERNAL_APPLE_SECRET="<SET_IN_SUPABASE_SECRETS>"

# Edge Function runtime secrets:
supabase secrets set OWNER_EMAIL="<SET_OWNER_EMAIL>"
supabase secrets set NOTIFY_FROM_EMAIL="Hotstash <notify@hotstash.app>"
supabase secrets set RESEND_API_KEY="<SET_IN_SUPABASE_SECRETS>"
supabase secrets set NOTIFY_SHARED_SECRET="<SET_IN_SUPABASE_SECRETS>"   # optional gate
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected into Edge Functions automatically by the platform — do **not** set
them manually.

### 5. Deploy the Edge Functions
```bash
supabase functions deploy submit
supabase functions deploy notify-owner
# or both at once:
supabase functions deploy submit notify-owner
```

### 6. (Optional) Wire notify-owner via Database Webhook
Instead of (or in addition to) `submit` calling `notify-owner` directly, you can
add a Database Webhook so any INSERT into `public.transforms` fires the email:

- Dashboard → Database → Webhooks → Create.
- Table `public.transforms`, event `INSERT`.
- Type: Supabase Edge Function → `notify-owner`.
- Add header `x-notify-secret: <NOTIFY_SHARED_SECRET>` if you set the gate.

`notify-owner` already normalizes both the direct-call payload and the DB
webhook `{ type, table, record }` shape, so either path works.

### 7. Make yourself an admin
After your first Sign in with Apple (which creates your `profiles` row):
```sql
update public.profiles set is_admin = true where apple_sub = '<YOUR_APPLE_SUB>';
-- or, if you know your auth user id:
update public.profiles set is_admin = true where id = '<YOUR_AUTH_USER_ID>';
```
Run this in the SQL editor (service role). Admin status unlocks all moderation
RPCs and the admin RLS branches.

### 8. Values the macOS app + website need
Copy from Dashboard → Project Settings → API:

| Value | Where used | Notes |
| --- | --- | --- |
| **Project URL** (`https://<ref>.supabase.co`) | app + web | safe to ship |
| **anon public key** | app + web | safe to ship; RLS protects data |
| `submit` function URL (`<url>/functions/v1/submit`) | app + web (publish) | call with the user JWT |

The **service role key is server-only** — never ship it in the app or website.

---

## Secrets / placeholders the human MUST provide

| Placeholder | Set via | Purpose |
| --- | --- | --- |
| `<SET_PROJECT_REF>` (`config.toml` `project_id`) | edit file / `supabase link` | project identity |
| `<SET_APPLE_CLIENT_ID>` (`config.toml`) | edit file | Apple Services ID (web client id) |
| macOS app bundle id (additional audience) | `config.toml` / dashboard | native Sign in with Apple |
| `SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` | `supabase secrets set` | Apple client secret JWT (from .p8 + Key ID + Team ID) |
| `OWNER_EMAIL` | `supabase secrets set` | where owner notifications are sent |
| `NOTIFY_FROM_EMAIL` | `supabase secrets set` | verified sender for the email provider |
| `RESEND_API_KEY` (or other provider key) | `supabase secrets set` | email provider auth |
| `NOTIFY_SHARED_SECRET` (optional) | `supabase secrets set` | gate notify-owner to webhook/service caller |
| Apple **Team ID**, **Key ID**, **.p8 key** | Apple Developer portal | inputs to generate the Apple secret JWT |
| admin user id / apple_sub | SQL `update profiles set is_admin=true` | grant yourself moderation rights |

Auto-injected (do NOT set): `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY`.

---

## Local development
```bash
supabase start                 # spins up Postgres + Studio + functions locally
supabase db reset              # re-applies all migrations from scratch
supabase functions serve submit --no-verify-jwt   # local function dev
```

## Rate limiting note
`record_install` is intentionally callable by anon (vanity install counter).
It only does a guarded `+1` on live transforms, but throttle it at the edge
(Supabase API gateway limits, Cloudflare rule on `/rest/v1/rpc/record_install`,
or an Edge Function with per-IP buckets). Rank primarily on authenticated
`installs` rows if abuse is a concern. The `submit` function should likewise be
rate-limited per user/IP at the gateway.

## body_hash contract (must match the app)
The app and `submit/index.ts` must hash identically:
- text  → `sha256("text:" + js)`
- image → `sha256("image:" + JSON.stringify(steps with keys sorted))`

`submit` implements the sorted-key stringify in `sortedStringify()`. Keep the
Swift normalization byte-for-byte aligned or dedup will silently miss matches.
