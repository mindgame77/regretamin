-- Teardown of founder storage (supabase/migrations/20261121010000_v2_founders.sql).
-- If the founder hand-out is installed, run this first:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261121020000_founderlist.sql
-- Then:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261121010000_v2_founders.sql
-- Drops v2_founders, v2_founder_facts, and the add/lookup functions.
-- Does not change v2_startups rows. A startup delete that was blocked by founder facts works again.
do $undo$
begin
  if to_regprocedure('public.founderlist_finish_founder_startup(uuid, bigint, text, text)') is not null then
    raise exception 'run supabase/rollbacks/20261121020000_founderlist.sql first';
  end if;
  drop function if exists public.v2_founder_add(uuid, bigint, jsonb, jsonb, jsonb);
  drop function if exists public.v2_founder_lookup(uuid, text, text);
  drop table if exists public.v2_founder_facts;
  drop table if exists public.v2_founders;
  drop function if exists public.v2_founder_require_role();
  drop function if exists public.v2_founder_set_norm();
  drop function if exists public.v2_founder_fold(text);
  drop function if exists public.v2_founder_linkedin(text);
end
$undo$;
