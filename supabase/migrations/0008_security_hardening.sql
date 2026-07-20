-- =============================================================================
-- Migration 0008: security hardening
-- =============================================================================
-- Closes three issues found in review:
--   1. bump_ai_gen was left with the default EXECUTE-to-PUBLIC grant, so anon /
--      authenticated could call it directly via PostgREST and grief any device's
--      daily AI-generation quota (or bypass the Edge Function entirely).
--   2. profiles.apple_sub (the Apple `sub` claim — user PII) was world-readable
--      through the `profiles_select_public` RLS policy.
--   3. Free-text columns written directly through PostgREST had no length cap,
--      allowing multi-megabyte rows (storage-abuse DoS).
-- =============================================================================

-- 1. Lock down the AI-generation rate-limit RPC ------------------------------
-- Only the Edge Function (service role, which bypasses these grants) should ever
-- call this. Match the lock-down pattern used for every other RPC in 0003.
revoke execute on function public.bump_ai_gen(text, int) from public;
revoke execute on function public.bump_ai_gen(text, int) from anon;
revoke execute on function public.bump_ai_gen(text, int) from authenticated;

-- 2. Stop leaking the Apple `sub` identifier --------------------------------
-- Column-level revoke: the public author handle (display_name) stays readable,
-- but apple_sub is no longer selectable by anon/authenticated. It is written
-- server-side by the service role (handle_new_user), which is unaffected.
revoke select (apple_sub) on public.profiles from anon;
revoke select (apple_sub) on public.profiles from authenticated;

-- 3. Cap free-text columns written straight through PostgREST ----------------
-- Generous ceilings — large enough for any legitimate content, small enough to
-- kill the storage-amplification vector.
alter table public.reviews
    add constraint reviews_body_maxlen check (length(body) <= 5000);

alter table public.reports
    add constraint reports_reason_maxlen check (length(reason) <= 2000);

alter table public.profiles
    add constraint profiles_display_name_maxlen check (length(display_name) <= 120);
