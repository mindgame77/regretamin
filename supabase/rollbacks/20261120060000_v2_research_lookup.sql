-- Teardown of the lookup action (supabase/migrations/20261120060000_v2_research_lookup.sql), in one command:
--   psql "$DATABASE_URL" -f supabase/rollbacks/20261120060000_v2_research_lookup.sql
-- Drops the lookup function and its two helpers. Touches no firm, deal, startup or site data.
-- After this, the door action lookup answers "server error" until the door is rolled back too.
do $undo$
begin
  drop function if exists public.v2_research_lookup(uuid, text, text, text);
  drop function if exists public.v2_lookup_name(text, text);
  drop function if exists public.v2_lookup_domain(text);
end
$undo$;
