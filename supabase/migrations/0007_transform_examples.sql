-- =============================================================================
-- Migration 0007: worked-example columns on transforms
-- =============================================================================
-- Adds an optional example input/output pair shown on a transform's detail page.
-- Authored in the app's transform builder, carried over from the AI generator,
-- or backfilled for existing rows by the `backfill-examples` Edge Function.
-- Nullable, no default: NULL means "no example available".
-- =============================================================================

alter table public.transforms
    add column if not exists example_input  text,
    add column if not exists example_output text;

comment on column public.transforms.example_input is
    'Optional worked-example input shown on the detail page. NULL if unknown.';
comment on column public.transforms.example_output is
    'Optional worked-example output paired with example_input. NULL if unknown.';
