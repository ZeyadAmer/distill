-- =============================================================================
-- Hotstash Transforms Marketplace — Row Level Security
-- Migration 0002: enable RLS + policies
-- =============================================================================
-- Security model (from spec §2.3 / Security Model):
--   * anon  : READ live transforms, their live versions, live reviews, aggregates.
--   * authed: WRITE OWN transforms (but NOT status/is_featured), ratings (one per
--             transform), reviews, reports. May read own pending/removed rows.
--   * admin : full read/write; the ONLY role allowed to set status to
--             live/removed or toggle is_featured (enforced here + via RPC).
--
-- The submit Edge Function uses the SERVICE ROLE key, which bypasses RLS, so it
-- can insert pending/live rows and version history regardless of these policies.
-- These policies govern direct PostgREST access from the app/website.
-- =============================================================================

-- Helper: is the current JWT an admin? SECURITY DEFINER + stable so it can read
-- profiles without recursing through profiles' own RLS.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select coalesce(
        (select p.is_admin from public.profiles p where p.id = auth.uid()),
        false
    );
$$;

comment on function public.is_admin() is
    'True when the current authenticated user has profiles.is_admin = true. Used by RLS policies and admin RPCs.';

-- =============================================================================
-- profiles
-- =============================================================================
alter table public.profiles enable row level security;

-- Anyone (even anon) may read public profile fields — author handles are public.
create policy profiles_select_public
    on public.profiles for select
    using (true);

-- A user may update only their own profile, and may NEVER grant themselves admin.
-- (is_admin is forced to its old value in the WITH CHECK clause.)
create policy profiles_update_own
    on public.profiles for update
    to authenticated
    using (id = auth.uid())
    with check (
        id = auth.uid()
        and is_admin = (select p.is_admin from public.profiles p where p.id = auth.uid())
    );

-- Admins may update any profile (e.g. promote/demote another admin).
create policy profiles_update_admin
    on public.profiles for update
    to authenticated
    using (public.is_admin())
    with check (public.is_admin());

-- =============================================================================
-- transforms
-- =============================================================================
alter table public.transforms enable row level security;

-- Public read: only live transforms are visible to anon / non-owners.
create policy transforms_select_live
    on public.transforms for select
    using (status = 'live');

-- Owners can read their own transforms in any status (pending/removed too) so the
-- "My transforms" surface can show pending/removed badges.
create policy transforms_select_own
    on public.transforms for select
    to authenticated
    using (owner_id = auth.uid());

-- Admins read everything.
create policy transforms_select_admin
    on public.transforms for select
    to authenticated
    using (public.is_admin());

-- Direct owner INSERT is allowed but constrained: an owner may only create rows
-- they own, may NOT self-publish (status must be 'pending'), and may NOT feature
-- themselves. (Routing to 'live' for returning authors happens in the service-role
-- Edge Function, which bypasses RLS.)
create policy transforms_insert_own
    on public.transforms for insert
    to authenticated
    with check (
        owner_id = auth.uid()
        and status = 'pending'
        and is_featured = false
    );

-- Owner UPDATE: may edit descriptive metadata on their own transform, but may NOT
-- change status or is_featured. RLS policies cannot read the OLD row directly, so
-- we forbid privilege changes by pinning the NEW row's status to 'pending'/'live'
-- (an owner can never set 'removed') and is_featured to false. The submit
-- Edge Function (service role) bypasses RLS for the returning-author live route,
-- and admins use transforms_update_admin / RPCs to set status & featuring.
-- `transforms.id` qualifies the OUTER (new) row so the subquery is correlated.
create policy transforms_update_own
    on public.transforms for update
    to authenticated
    using (owner_id = auth.uid())
    with check (
        owner_id = auth.uid()
        and is_featured = false
        and status = (
            select t.status from public.transforms t where t.id = public.transforms.id
        )
    );

-- Admin UPDATE: the only path that can set status live/removed or is_featured.
create policy transforms_update_admin
    on public.transforms for update
    to authenticated
    using (public.is_admin())
    with check (public.is_admin());

-- Admin DELETE (hard delete is rare; prefer status=removed via RPC).
create policy transforms_delete_admin
    on public.transforms for delete
    to authenticated
    using (public.is_admin());

-- =============================================================================
-- transform_versions  (immutable)
-- =============================================================================
alter table public.transform_versions enable row level security;

-- Public read of versions belonging to a live transform.
create policy transform_versions_select_live
    on public.transform_versions for select
    using (
        exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- Owners may read versions of their own transforms (any status).
create policy transform_versions_select_own
    on public.transform_versions for select
    to authenticated
    using (
        exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.owner_id = auth.uid()
        )
    );

-- Admins read all versions.
create policy transform_versions_select_admin
    on public.transform_versions for select
    to authenticated
    using (public.is_admin());

-- No INSERT/UPDATE/DELETE policies: versions are written exclusively by the
-- service-role Edge Function (submit) and by admin rollback RPC (SECURITY DEFINER).
-- Direct client writes are therefore denied.

-- =============================================================================
-- installs
-- =============================================================================
alter table public.installs enable row level security;

-- A user may see and manage only their own install rows.
create policy installs_select_own
    on public.installs for select
    to authenticated
    using (profile_id = auth.uid());

-- Insert own install row (only against a live transform).
create policy installs_insert_own
    on public.installs for insert
    to authenticated
    with check (
        profile_id = auth.uid()
        and exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- Uninstall: delete own install row.
create policy installs_delete_own
    on public.installs for delete
    to authenticated
    using (profile_id = auth.uid());

-- =============================================================================
-- ratings  (one per transform per profile, enforced by PK)
-- =============================================================================
alter table public.ratings enable row level security;

-- Ratings of live transforms are publicly readable (drives aggregates display).
create policy ratings_select_live
    on public.ratings for select
    using (
        exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- A user may read their own ratings regardless of transform status.
create policy ratings_select_own
    on public.ratings for select
    to authenticated
    using (profile_id = auth.uid());

-- Insert own rating against a live transform. The (transform_id, profile_id) PK
-- guarantees one rating per transform per profile.
create policy ratings_insert_own
    on public.ratings for insert
    to authenticated
    with check (
        profile_id = auth.uid()
        and exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- Update own rating (change stars).
create policy ratings_update_own
    on public.ratings for update
    to authenticated
    using (profile_id = auth.uid())
    with check (profile_id = auth.uid());

-- Delete own rating.
create policy ratings_delete_own
    on public.ratings for delete
    to authenticated
    using (profile_id = auth.uid());

-- =============================================================================
-- reviews
-- =============================================================================
alter table public.reviews enable row level security;

-- Public read: live reviews on live transforms.
create policy reviews_select_live
    on public.reviews for select
    using (
        status = 'live'
        and exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- Authors read their own reviews (even if removed).
create policy reviews_select_own
    on public.reviews for select
    to authenticated
    using (profile_id = auth.uid());

-- Admins read all reviews.
create policy reviews_select_admin
    on public.reviews for select
    to authenticated
    using (public.is_admin());

-- Insert own review (status forced to 'live') against a live transform.
create policy reviews_insert_own
    on public.reviews for insert
    to authenticated
    with check (
        profile_id = auth.uid()
        and status = 'live'
        and exists (
            select 1 from public.transforms t
            where t.id = transform_id and t.status = 'live'
        )
    );

-- Update own review body; may not self-change moderation status. The NEW row's
-- status is pinned to the persisted value via a correlated subquery on the OUTER
-- row (qualified as public.reviews.id). An author therefore cannot set 'removed';
-- only admins (reviews_update_admin) / remove_review() RPC can.
create policy reviews_update_own
    on public.reviews for update
    to authenticated
    using (profile_id = auth.uid())
    with check (
        profile_id = auth.uid()
        and status = (
            select r.status from public.reviews r where r.id = public.reviews.id
        )
    );

-- Admin update (the only path that can set status='removed').
create policy reviews_update_admin
    on public.reviews for update
    to authenticated
    using (public.is_admin())
    with check (public.is_admin());

-- =============================================================================
-- reports
-- =============================================================================
alter table public.reports enable row level security;

-- A reporter may read their own reports.
create policy reports_select_own
    on public.reports for select
    to authenticated
    using (reporter_id = auth.uid());

-- Admins read all reports (moderation queue).
create policy reports_select_admin
    on public.reports for select
    to authenticated
    using (public.is_admin());

-- Any authenticated user may file a report as themselves; status forced to 'open'.
create policy reports_insert_own
    on public.reports for insert
    to authenticated
    with check (
        reporter_id = auth.uid()
        and status = 'open'
    );

-- Only admins may update reports (resolve). Prefer resolve_report() RPC.
create policy reports_update_admin
    on public.reports for update
    to authenticated
    using (public.is_admin())
    with check (public.is_admin());
