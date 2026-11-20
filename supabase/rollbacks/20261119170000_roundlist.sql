-- Teardown of the round list (supabase/migrations/20261119170000_roundlist.sql), in one command:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261119170000_roundlist.sql
-- Drops the three bot entry points and the whole roundlist schema (rounds, events, helpers).
-- Touches nothing else: no firm, deal, startup, submission or site data.
-- After this, the door actions add_round / claim_next_round / finish_round answer "server error".
do $undo$
begin
  drop function if exists public.roundlist_add_round(uuid, jsonb);
  drop function if exists public.roundlist_claim_next_round(uuid, integer);
  drop function if exists public.roundlist_finish_round(uuid, bigint, text, text);
  drop schema if exists roundlist cascade;
end
$undo$;
