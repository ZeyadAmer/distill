-- =============================================================================
-- Hotstash Transforms Marketplace — Schema
-- Migration 0001: types, tables, indexes, triggers
-- =============================================================================
-- This migration defines the full relational schema for the marketplace.
-- RLS policies live in 0002_rls.sql; admin/RPC functions live in 0003_rpc.sql.
--
-- Conventions:
--   * All ids are uuid (gen_random_uuid()).
--   * profiles.id maps 1:1 to auth.users.id (Supabase Auth / Sign in with Apple).
--   * Aggregate counters (install_count, rating_avg, rating_count) are maintained
--     by triggers so reads never have to recompute them.
-- =============================================================================

-- pgcrypto provides gen_random_uuid(); present by default on Supabase but
-- declared here so the migration is self-contained.
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- Enums
-- -----------------------------------------------------------------------------
create type transform_kind   as enum ('text', 'image');
create type transform_status as enum ('pending', 'live', 'removed');
create type review_status     as enum ('live', 'removed');
create type report_target     as enum ('transform', 'review');
create type report_status     as enum ('open', 'resolved');

-- -----------------------------------------------------------------------------
-- profiles
-- One row per authenticated user. Created on first sign-in (see handle_new_user
-- trigger below). `is_admin` is the sole privilege flag and is the only way to
-- reach the admin-only RLS branches / RPCs.
-- -----------------------------------------------------------------------------
create table public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    apple_sub    text unique,                         -- Apple `sub` claim, for audit
    display_name text not null default 'Anonymous',   -- public author handle
    is_admin     boolean not null default false,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

comment on table public.profiles is
    'User profiles, 1:1 with auth.users. is_admin gates all moderation paths.';

-- -----------------------------------------------------------------------------
-- transforms
-- The canonical, mutable head record for a published transform. Version bodies
-- are stored immutably in transform_versions; `latest_version` points at the
-- newest live version.
-- -----------------------------------------------------------------------------
create table public.transforms (
    id             uuid primary key default gen_random_uuid(),
    slug           text not null unique,
    owner_id       uuid not null references public.profiles (id) on delete cascade,
    kind           transform_kind not null,
    name           text not null,
    description    text not null default '',
    icon           text not null default 'textformat',
    category       text not null default 'cleanup',
    latest_version integer not null default 1,
    status         transform_status not null default 'pending',
    install_count  integer not null default 0,
    rating_avg     numeric(3,2) not null default 0,    -- 0.00 .. 5.00
    rating_count   integer not null default 0,
    is_featured    boolean not null default false,
    body_hash      text not null,                      -- sha256 of normalized body
    -- Full-text search vector maintained by trigger (generated columns cannot use
    -- the multi-weight setweight() form, so we maintain it explicitly).
    search_vector  tsvector,
    created_at     timestamptz not null default now(),
    updated_at     timestamptz not null default now(),

    constraint transforms_rating_avg_range check (rating_avg >= 0 and rating_avg <= 5),
    constraint transforms_counts_nonneg
        check (install_count >= 0 and rating_count >= 0 and latest_version >= 1)
);

comment on column public.transforms.body_hash is
    'SHA-256 of normalized body. text => sha256("text:"+js); image => sha256("image:"+JSON.stringify(steps with sorted keys)). MUST match the app + submit Edge Function.';
comment on column public.transforms.status is
    'pending=awaiting first-time approval, live=public, removed=taken down. Only admins may transition (enforced in RLS + RPC).';

create index transforms_status_idx      on public.transforms (status);
create index transforms_owner_idx       on public.transforms (owner_id);
create index transforms_category_idx    on public.transforms (category);
create index transforms_featured_idx    on public.transforms (is_featured) where is_featured;
create index transforms_install_idx     on public.transforms (install_count desc);
create index transforms_created_idx     on public.transforms (created_at desc);
-- Dedup lookup: find existing live transforms with a given body hash quickly.
create index transforms_body_hash_idx   on public.transforms (body_hash) where status = 'live';
-- Full-text search.
create index transforms_search_idx      on public.transforms using gin (search_vector);

-- -----------------------------------------------------------------------------
-- transform_versions
-- Immutable append-only history. Each publish/update appends a row. Powers
-- silent auto-update (clients pull `latest_version`) and admin rollback.
-- `body` is the raw manifest body JSON (text => {js}, image => {steps}).
-- -----------------------------------------------------------------------------
create table public.transform_versions (
    id           uuid primary key default gen_random_uuid(),
    transform_id uuid not null references public.transforms (id) on delete cascade,
    version      integer not null,
    body         jsonb not null,
    body_hash    text not null,
    created_at   timestamptz not null default now(),

    constraint transform_versions_unique unique (transform_id, version)
);

comment on table public.transform_versions is
    'Immutable version history. No UPDATE/DELETE policy is granted to anyone except admin rollback via RPC.';

create index transform_versions_transform_idx
    on public.transform_versions (transform_id, version desc);

-- -----------------------------------------------------------------------------
-- installs
-- Optional per-profile install record. install_count is also incremented by
-- anonymous users via the record_install() RPC WITHOUT inserting a row here
-- (see 0003_rpc.sql), so install_count >= count(installs) by design.
-- -----------------------------------------------------------------------------
create table public.installs (
    transform_id uuid not null references public.transforms (id) on delete cascade,
    profile_id   uuid not null references public.profiles (id)   on delete cascade,
    created_at   timestamptz not null default now(),

    primary key (transform_id, profile_id)
);

create index installs_profile_idx on public.installs (profile_id);

-- -----------------------------------------------------------------------------
-- ratings
-- One rating per (transform, profile). Triggers recompute rating_avg/rating_count
-- on the parent transform.
-- -----------------------------------------------------------------------------
create table public.ratings (
    transform_id uuid not null references public.transforms (id) on delete cascade,
    profile_id   uuid not null references public.profiles (id)   on delete cascade,
    stars        smallint not null,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),

    primary key (transform_id, profile_id),
    constraint ratings_stars_range check (stars >= 1 and stars <= 5)
);

create index ratings_transform_idx on public.ratings (transform_id);

-- -----------------------------------------------------------------------------
-- reviews
-- Free-text reviews. status live|removed (moderation). One author may leave
-- multiple reviews over time (not constrained), but RLS limits writes to own rows.
-- -----------------------------------------------------------------------------
create table public.reviews (
    id           uuid primary key default gen_random_uuid(),
    transform_id uuid not null references public.transforms (id) on delete cascade,
    profile_id   uuid not null references public.profiles (id)   on delete cascade,
    body         text not null,
    status       review_status not null default 'live',
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),

    constraint reviews_body_nonempty check (length(btrim(body)) > 0)
);

create index reviews_transform_idx on public.reviews (transform_id, created_at desc);
create index reviews_profile_idx   on public.reviews (profile_id);

-- -----------------------------------------------------------------------------
-- reports
-- Abuse reports against a transform or a review. status open|resolved; resolved
-- only via admin RPC.
-- -----------------------------------------------------------------------------
create table public.reports (
    id          uuid primary key default gen_random_uuid(),
    target_type report_target not null,
    target_id   uuid not null,            -- transform.id or review.id (not FK: polymorphic)
    reporter_id uuid not null references public.profiles (id) on delete cascade,
    reason      text not null default '',
    status      report_status not null default 'open',
    created_at  timestamptz not null default now(),
    resolved_at timestamptz,
    resolved_by uuid references public.profiles (id)
);

create index reports_status_idx on public.reports (status);
create index reports_target_idx on public.reports (target_type, target_id);

-- =============================================================================
-- Triggers & functions (counter maintenance, search vector, timestamps, signup)
-- =============================================================================

-- ---- updated_at maintenance --------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

create trigger profiles_set_updated_at
    before update on public.profiles
    for each row execute function public.set_updated_at();

create trigger transforms_set_updated_at
    before update on public.transforms
    for each row execute function public.set_updated_at();

create trigger ratings_set_updated_at
    before update on public.ratings
    for each row execute function public.set_updated_at();

create trigger reviews_set_updated_at
    before update on public.reviews
    for each row execute function public.set_updated_at();

-- ---- full-text search vector -------------------------------------------------
-- name is weighted 'A' (most relevant), description 'B'.
create or replace function public.transforms_search_vector_update()
returns trigger
language plpgsql
as $$
begin
    new.search_vector :=
        setweight(to_tsvector('english', coalesce(new.name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(new.description, '')), 'B');
    return new;
end;
$$;

create trigger transforms_search_vector_trg
    before insert or update of name, description on public.transforms
    for each row execute function public.transforms_search_vector_update();

-- ---- rating aggregate maintenance -------------------------------------------
-- Recompute rating_avg + rating_count from the ratings table for one transform.
create or replace function public.recompute_transform_rating(p_transform_id uuid)
returns void
language plpgsql
as $$
begin
    update public.transforms t
    set rating_count = sub.cnt,
        rating_avg   = sub.avg
    from (
        select count(*)::int as cnt,
               coalesce(round(avg(stars)::numeric, 2), 0) as avg
        from public.ratings
        where transform_id = p_transform_id
    ) sub
    where t.id = p_transform_id;
end;
$$;

create or replace function public.ratings_after_change()
returns trigger
language plpgsql
as $$
begin
    if (tg_op = 'DELETE') then
        perform public.recompute_transform_rating(old.transform_id);
        return old;
    else
        perform public.recompute_transform_rating(new.transform_id);
        return new;
    end if;
end;
$$;

create trigger ratings_aggregate_trg
    after insert or update or delete on public.ratings
    for each row execute function public.ratings_after_change();

-- ---- install_count maintenance ----------------------------------------------
-- Maintains install_count when per-profile install rows are added/removed.
-- NOTE: anonymous installs increment install_count directly via record_install()
-- RPC (0003) and do NOT pass through this trigger.
create or replace function public.installs_after_change()
returns trigger
language plpgsql
as $$
begin
    if (tg_op = 'INSERT') then
        update public.transforms
        set install_count = install_count + 1
        where id = new.transform_id;
        return new;
    elsif (tg_op = 'DELETE') then
        update public.transforms
        set install_count = greatest(install_count - 1, 0)
        where id = old.transform_id;
        return old;
    end if;
    return null;
end;
$$;

create trigger installs_aggregate_trg
    after insert or delete on public.installs
    for each row execute function public.installs_after_change();

-- ---- auto-create profile on signup ------------------------------------------
-- Runs as the auth trigger owner (SECURITY DEFINER) so it can write into
-- public.profiles regardless of the caller. Pulls display name / apple sub from
-- the new auth.users row metadata where available.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id, apple_sub, display_name)
    values (
        new.id,
        new.raw_user_meta_data ->> 'sub',
        coalesce(
            nullif(new.raw_user_meta_data ->> 'full_name', ''),
            nullif(new.raw_user_meta_data ->> 'name', ''),
            split_part(coalesce(new.email, 'Anonymous'), '@', 1)
        )
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();
