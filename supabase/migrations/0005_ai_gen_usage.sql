-- =============================================================================
-- AI transform generation — per-device daily usage cap
-- =============================================================================
-- Backs the `generate-transform` Edge Function's rate limit. Anonymous, keyed by
-- the app's per-install device id (same id as devices/record_app_open). Only the
-- service role (the Edge Function) ever touches this table.
-- =============================================================================

create table if not exists ai_gen_usage (
    device_id text  not null,
    day       date  not null,
    count     int   not null default 0,
    primary key (device_id, day)
);

alter table ai_gen_usage enable row level security;
-- No policies on purpose: RLS denies anon/authenticated; the Edge Function uses
-- the service role, which bypasses RLS.

-- Atomically bump today's counter for a device and report whether the caller is
-- still under the cap. Increments even on the over-cap call (that only makes the
-- limit marginally stricter, and keeps the operation a single atomic upsert).
create or replace function bump_ai_gen(p_device text, p_cap int)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    new_count int;
begin
    insert into ai_gen_usage (device_id, day, count)
    values (p_device, current_date, 1)
    on conflict (device_id, day)
    do update set count = ai_gen_usage.count + 1
    returning count into new_count;

    return new_count <= p_cap;
end;
$$;
