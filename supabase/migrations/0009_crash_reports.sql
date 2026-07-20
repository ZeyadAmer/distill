-- =============================================================================
-- Hotstash — crash reporting
-- Migration 0009: crash_reports table + record_crash RPC
-- =============================================================================
-- Collects crash diagnostics gathered on-device by MetricKit and forwarded by
-- the app on the next launch after a crash. The client sends the random
-- per-install UUID (same as record_app_open; no PII), version/OS/model, a few
-- extracted fields for easy filtering, and the full MetricKit crash payload
-- (call stacks + metadata only — never clipboard content).
--
-- Like devices, the table is RLS-locked with NO policies: it is unreachable via
-- the REST API. All writes flow through the SECURITY DEFINER RPC below; reads
-- happen via the dashboard / service role only.
--
-- Useful queries (run as postgres in the dashboard):
--   recent crashes        : select created_at, app_version, os_version,
--                             exception_type, signal, device_model
--                             from public.crash_reports order by created_at desc limit 50;
--   crashes by version    : select app_version, count(*) from public.crash_reports group by 1 order by 2 desc;
--   top crash signatures  : select exception_type, signal, count(*)
--                             from public.crash_reports group by 1,2 order by 3 desc;
--   full stack for a row  : select payload from public.crash_reports where id = '...';
-- =============================================================================

create table if not exists public.crash_reports (
    id                 uuid primary key default gen_random_uuid(),
    device_id          uuid,                 -- random install id (matches devices.id)
    platform           text not null,        -- 'macos' | 'ios'
    app_version        text,
    os_version         text,
    device_model       text,
    exception_type     text,
    signal             text,
    termination_reason text,
    crash_count        int,
    payload            jsonb not null,        -- full MetricKit crash diagnostic
    created_at         timestamptz not null default now()
);

comment on table public.crash_reports is
    'MetricKit crash diagnostics forwarded by the app. No PII, no clipboard content. Populated by record_crash.';

create index if not exists crash_reports_created_at_idx  on public.crash_reports (created_at desc);
create index if not exists crash_reports_app_version_idx on public.crash_reports (app_version);

alter table public.crash_reports enable row level security;
-- Intentionally NO policies: unreachable via REST. Only the SECURITY DEFINER
-- RPC (which bypasses RLS) may insert.

-- -----------------------------------------------------------------------------
-- record_crash: insert one crash report. Callable by anon so it works without a
-- marketplace sign-in.
--
-- RATE-LIMIT NOTE: like record_app_open, this is intentionally unauthenticated
-- and therefore abusable. Mitigate at the edge (WAF / gateway rate limit on
-- /rest/v1/rpc/record_crash). The size guard below caps a single row's payload
-- so a caller can't store arbitrarily large blobs.
-- -----------------------------------------------------------------------------
create or replace function public.record_crash(
    p_device_id          uuid,
    p_platform           text,
    p_payload            jsonb,
    p_app_version        text default null,
    p_os_version         text default null,
    p_device_model       text default null,
    p_exception_type     text default null,
    p_signal             text default null,
    p_termination_reason text default null,
    p_crash_count        int  default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    -- Drop obviously oversized payloads (~256 KB of JSON text) rather than store them.
    if p_payload is null or length(p_payload::text) > 262144 then
        return;
    end if;

    insert into public.crash_reports (
        device_id, platform, app_version, os_version, device_model,
        exception_type, signal, termination_reason, crash_count, payload
    )
    values (
        p_device_id, p_platform, p_app_version, p_os_version, p_device_model,
        p_exception_type, p_signal, p_termination_reason, p_crash_count, p_payload
    );
end;
$$;

revoke execute on function public.record_crash(uuid, text, jsonb, text, text, text, text, text, text, int) from public;
grant  execute on function public.record_crash(uuid, text, jsonb, text, text, text, text, text, text, int) to anon, authenticated;
