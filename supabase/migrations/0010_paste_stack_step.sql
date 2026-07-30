-- =============================================================================
-- Tour: Paste Stack step flag
-- =============================================================================
-- Gates the onboarding tour's Paste Stack step. Ships false so the step is
-- dormant in the build; flip to true (dashboard / service role) to reveal it
-- OTA — no new build needed. Read publicly via the existing app_config select.
--
-- NB: app_config was created out-of-band (not via an earlier migration); this
-- file just records the column addition. Idempotent.
-- =============================================================================

alter table app_config
    add column if not exists paste_stack_step_enabled boolean not null default false;
