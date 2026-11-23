-- Rollback for 20261122230957_v2_deals_shown_indexes: drop the two partial indexes.
-- Do this only while the v2_map_* functions do NOT filter on shown, or the map will time out again.
-- Run each statement on its own.
drop index concurrently if exists public.v2_deals_shown_date_idx;
drop index concurrently if exists public.v2_deals_shown_firm_date_idx;
