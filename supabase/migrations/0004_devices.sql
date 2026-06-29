-- =============================================================================
-- Hotstash — anonymous active-user tracking
-- Migration 0004: devices table + record_app_open RPC
-- =============================================================================
-- Counts app opens across macOS/iOS without requiring a marketplace login.
-- The client sends a random per-install UUID (no device identifier, no PII)
-- plus platform/version. The table is RLS-locked with NO policies, so neither
-- anon nor authenticated can read or write it directly — all writes flow
-- through the SECURITY DEFINER RPC below, and reads happen via the dashboard /
-- service role only.
--
-- Useful queries (run as postgres in the dashboard):
--   total users            : select count(*) from public.devices;
--   active in last 30 days  : select count(*) from public.devices
--                               where last_seen > now() - interval '30 days';
--   by platform             : select platform, count(*) from public.devices group by 1;
--   new in last 7 days      : select count(*) from public.devices
--                               where first_seen > now() - interval '7 days';
-- =============================================================================

create table if not exists public.devices (
    id          uuid primary key,                          -- random install id from the client
    platform    text not null,                             -- 'macos' | 'ios'
    app_version text,
    os_version  text,
    first_seen  timestamptz not null default now(),
    last_seen   timestamptz not null default now()
);

comment on table public.devices is
    'One row per app install (anonymous). Populated by record_app_open; no PII.';

create index if not exists devices_last_seen_idx on public.devices (last_seen);

alter table public.devices enable row level security;
-- Intentionally NO policies: the table is unreachable via the REST API. Only the
-- SECURITY DEFINER RPC (which bypasses RLS) may touch it.

-- -----------------------------------------------------------------------------
-- record_app_open: upsert this install's row and bump last_seen. Callable by
-- anon so it works before/without any marketplace sign-in.
--
-- RATE-LIMIT NOTE: like record_install, this is intentionally unauthenticated
-- and therefore abusable to inflate counts. Mitigate at the edge (WAF / API
-- gateway rate limit on /rest/v1/rpc/record_app_open), not here. The function
-- only ever upserts a single row keyed by the caller-supplied id.
-- -----------------------------------------------------------------------------
create or replace function public.record_app_open(
    p_device_id   uuid,
    p_platform    text,
    p_app_version text default null,
    p_os_version  text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.devices (id, platform, app_version, os_version, first_seen, last_seen)
    values (p_device_id, p_platform, p_app_version, p_os_version, now(), now())
    on conflict (id) do update
        set last_seen   = now(),
            platform    = excluded.platform,
            app_version = excluded.app_version,
            os_version  = excluded.os_version;
end;
$$;

revoke execute on function public.record_app_open(uuid, text, text, text) from public;
grant  execute on function public.record_app_open(uuid, text, text, text) to anon, authenticated;
