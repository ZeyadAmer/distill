-- =============================================================================
-- Hotstash Transforms Marketplace — RPC functions
-- Migration 0003: admin RPCs + record_install
-- =============================================================================
-- Admin RPCs are SECURITY DEFINER and each begins with an is_admin() guard so
-- they run with elevated privilege ONLY for verified admins. record_install is
-- callable by anon and increments the public counter without exposing a way to
-- mutate anything else.
--
-- Execution is revoked from PUBLIC and granted explicitly so the surface is tight.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- approve_transform: move a pending first-time submission to live.
-- Creates/ensures the version-1 row already exists (submit fn writes the version
-- on insert; here we just flip status). Idempotent for already-live rows.
-- -----------------------------------------------------------------------------
create or replace function public.approve_transform(p_transform_id uuid)
returns public.transforms
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.transforms;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    update public.transforms
    set status = 'live'
    where id = p_transform_id and status = 'pending'
    returning * into result;

    if not found then
        raise exception 'transform % not found or not pending', p_transform_id
            using errcode = 'P0002';
    end if;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- remove_transform: take a transform down (soft remove). Reversible by re-approve
-- only via admin; clients stop seeing it immediately (RLS hides non-live).
-- -----------------------------------------------------------------------------
create or replace function public.remove_transform(p_transform_id uuid)
returns public.transforms
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.transforms;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    update public.transforms
    set status = 'removed', is_featured = false
    where id = p_transform_id
    returning * into result;

    if not found then
        raise exception 'transform % not found', p_transform_id using errcode = 'P0002';
    end if;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- remove_review: hide a review (moderation).
-- -----------------------------------------------------------------------------
create or replace function public.remove_review(p_review_id uuid)
returns public.reviews
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.reviews;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    update public.reviews
    set status = 'removed'
    where id = p_review_id
    returning * into result;

    if not found then
        raise exception 'review % not found', p_review_id using errcode = 'P0002';
    end if;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- set_featured: toggle the featured flag (only live transforms can be featured).
-- -----------------------------------------------------------------------------
create or replace function public.set_featured(p_transform_id uuid, p_featured boolean)
returns public.transforms
language plpgsql
security definer
set search_path = public
as $$
declare
    result public.transforms;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    update public.transforms
    set is_featured = p_featured
    where id = p_transform_id
      and (p_featured = false or status = 'live')   -- can only feature live ones
    returning * into result;

    if not found then
        raise exception 'transform % not found or cannot be featured (must be live)',
            p_transform_id using errcode = 'P0002';
    end if;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- resolve_report: mark a report resolved and stamp who/when. Optionally also
-- takes down the target in one call when p_action is 'remove'.
--   p_action: 'dismiss' (default) | 'remove'
-- -----------------------------------------------------------------------------
create or replace function public.resolve_report(p_report_id uuid, p_action text default 'dismiss')
returns public.reports
language plpgsql
security definer
set search_path = public
as $$
declare
    rec    public.reports;
    result public.reports;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    select * into rec from public.reports where id = p_report_id;
    if not found then
        raise exception 'report % not found', p_report_id using errcode = 'P0002';
    end if;

    if p_action = 'remove' then
        if rec.target_type = 'transform' then
            perform public.remove_transform(rec.target_id);
        elsif rec.target_type = 'review' then
            perform public.remove_review(rec.target_id);
        end if;
    elsif p_action <> 'dismiss' then
        raise exception 'invalid action %, expected dismiss|remove', p_action
            using errcode = '22023';
    end if;

    update public.reports
    set status      = 'resolved',
        resolved_at = now(),
        resolved_by = auth.uid()
    where id = p_report_id
    returning * into result;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- rollback_transform_version: point latest_version + body_hash at an earlier
-- immutable version. Does NOT delete history; it re-publishes an existing version
-- as the new head by appending a fresh version row that copies the target body.
-- This keeps transform_versions strictly append-only.
-- -----------------------------------------------------------------------------
create or replace function public.rollback_transform_version(
    p_transform_id uuid,
    p_target_version integer
)
returns public.transforms
language plpgsql
security definer
set search_path = public
as $$
declare
    src       public.transform_versions;
    new_ver   integer;
    result    public.transforms;
begin
    if not public.is_admin() then
        raise exception 'permission denied: admin only' using errcode = '42501';
    end if;

    select * into src
    from public.transform_versions
    where transform_id = p_transform_id and version = p_target_version;

    if not found then
        raise exception 'version % not found for transform %',
            p_target_version, p_transform_id using errcode = 'P0002';
    end if;

    -- Append a new version that re-uses the target body (append-only history).
    select coalesce(max(version), 0) + 1 into new_ver
    from public.transform_versions
    where transform_id = p_transform_id;

    insert into public.transform_versions (transform_id, version, body, body_hash)
    values (p_transform_id, new_ver, src.body, src.body_hash);

    update public.transforms
    set latest_version = new_ver,
        body_hash      = src.body_hash
    where id = p_transform_id
    returning * into result;

    return result;
end;
$$;

-- -----------------------------------------------------------------------------
-- record_install: safely increment install_count for a LIVE transform without
-- requiring a row in installs. Callable by anon (default install path per spec
-- Open Items: anonymous increment, no row).
--
-- RATE-LIMIT NOTE: This RPC is intentionally unauthenticated, so it is abusable
-- by a script hammering it to inflate counts. Mitigate at the edge, NOT here:
--   * Put the Supabase API behind a rate limiter / WAF (e.g. Cloudflare rule on
--     /rest/v1/rpc/record_install, or Supabase's built-in API gateway limits).
--   * Optionally front this with an Edge Function that throttles per-IP via a
--     short-TTL KV/Redis bucket before calling the RPC.
--   * Consider only counting authenticated installs (installs table) for ranking
--     and treating this counter as a soft/vanity metric.
-- The function itself only ever does a guarded +1 on a live transform.
-- -----------------------------------------------------------------------------
create or replace function public.record_install(p_transform_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    update public.transforms
    set install_count = install_count + 1
    where id = p_transform_id and status = 'live';
    -- Silent no-op if the transform is not live; do not leak existence.
end;
$$;

-- -----------------------------------------------------------------------------
-- Execution grants: lock down, then open exactly what each role needs.
-- -----------------------------------------------------------------------------
revoke execute on function public.approve_transform(uuid)            from public;
revoke execute on function public.remove_transform(uuid)             from public;
revoke execute on function public.remove_review(uuid)                from public;
revoke execute on function public.set_featured(uuid, boolean)        from public;
revoke execute on function public.resolve_report(uuid, text)         from public;
revoke execute on function public.rollback_transform_version(uuid, integer) from public;
revoke execute on function public.record_install(uuid)               from public;

-- Admin RPCs: only authenticated users may invoke (the is_admin() guard inside
-- each function blocks non-admins at runtime).
grant execute on function public.approve_transform(uuid)            to authenticated;
grant execute on function public.remove_transform(uuid)             to authenticated;
grant execute on function public.remove_review(uuid)                to authenticated;
grant execute on function public.set_featured(uuid, boolean)        to authenticated;
grant execute on function public.resolve_report(uuid, text)         to authenticated;
grant execute on function public.rollback_transform_version(uuid, integer) to authenticated;

-- record_install: anonymous + authenticated install increments.
grant execute on function public.record_install(uuid) to anon, authenticated;
