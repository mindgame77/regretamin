-- Indexes so the v2_map_* functions can filter deals on v2_deals.shown and stay fast (2026-11-22, Alex).
-- Without them, adding "and <alias>.shown" made v2_map_summary take ~40-60 s: the planner estimated ~80 rows
-- for current+shown deals (real ~80,000) and picked a nested-loop semi join against the firm places.
-- With these partial indexes the shown-filtered functions run in about the same time as today (summary ~1.4 s).
-- Index only. No function, view, data or site change. Applied live with CREATE INDEX CONCURRENTLY, then ANALYZE.
-- When applying by hand, run each statement on its own (CONCURRENTLY cannot run inside a transaction).
-- On a database without v2_deals (the test database in CI) this file is a no-op. Inside this block the indexes are
-- built the plain way, because CONCURRENTLY cannot run in a transaction; production already has them (built CONCURRENTLY).
do $mig$
begin
  if to_regclass('public.v2_deals') is null then
    raise notice 'v2_deals missing: shown indexes skipped';
    return;
  end if;
  execute 'create index if not exists v2_deals_shown_date_idx on public.v2_deals (deal_date, firm_id, startup_id) where is_current and shown';
  execute 'create index if not exists v2_deals_shown_firm_date_idx on public.v2_deals (firm_id, deal_date) where is_current and shown';
  execute 'analyze public.v2_deals';
end
$mig$;
