-- Teardown of the founder hand-out (supabase/migrations/20261121020000_founderlist.sql), in one command:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261121020000_founderlist.sql
-- Drops the two bot entry points and the whole founderlist schema (startups, events, helpers).
-- Touches nothing else: founder rows, startups, deals and the site stay.
-- After this, claim_next_founder_startups / finish_founder_startup answer "server error".
do $undo$
begin
  drop function if exists public.founderlist_claim_next_founder_startups(uuid, integer);
  drop function if exists public.founderlist_finish_founder_startup(uuid, bigint, text, text);
  drop schema if exists founderlist cascade;
end
$undo$;
