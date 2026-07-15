-- =============================================================================
-- Developer-triggered update notice
-- =============================================================================
-- A single row per platform that the app reads on launch. Set `enabled = true`
-- and bump `min_version` when you publish a build you want users to move to —
-- the app shows an update popup immediately, without waiting for the iTunes
-- lookup version to propagate. Optional custom `message`; `force = true` makes it
-- a re-every-launch "Update Required" nag (MAS can't hard-block self-updates).
--
-- Publicly readable (no secrets). Writes happen in the Supabase dashboard / via
-- the service role only.
-- =============================================================================

create table if not exists app_update_notice (
    platform     text        primary key,   -- 'macos' | 'ios'
    enabled      boolean     not null default false,
    min_version  text        not null default '0',   -- show when installed < this
    message      text,                                -- optional custom body
    force        boolean     not null default false,  -- re-prompt every launch, no "Later"
    listing_url  text,                                -- optional App Store link override
    updated_at   timestamptz not null default now()
);

alter table app_update_notice enable row level security;

create policy app_update_notice_read
    on app_update_notice for select
    using (true);

insert into app_update_notice (platform, enabled)
values ('macos', false), ('ios', false)
on conflict (platform) do nothing;
