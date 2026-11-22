-- Indexes so the v2_map_* functions can filter deals on v2_deals.shown and stay fast (2026-11-22, Alex).
-- Without them, adding "and <alias>.shown" made v2_map_summary take ~40-60 s: the planner estimated ~80 rows
-- for current+shown deals (real ~80,000) and picked a nested-loop semi join against the firm places.
-- With these partial indexes the shown-filtered functions run in about the same time as today (summary ~1.4 s).
-- Index only. No function, view, data or site change. Applied live with CREATE INDEX CONCURRENTLY, then ANALYZE.
-- When applying by hand, run each statement on its own (CONCURRENTLY cannot run inside a transaction).
create index concurrently if not exists v2_deals_shown_date_idx
  on public.v2_deals (deal_date, firm_id, startup_id) where is_current and shown;
create index concurrently if not exists v2_deals_shown_firm_date_idx
  on public.v2_deals (firm_id, deal_date) where is_current and shown;
analyze public.v2_deals;
