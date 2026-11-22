-- UNDONE on 2026-11-22, about three hours after it was applied (migration: map_functions_undo_shown_filter_too_slow).
-- With "and <alias>.shown" added, v2_map_summary took about 40 seconds instead of about 1-2, so the map timed out for
-- visitors (anon statement_timeout is 20 s) and showed empty. The seven functions are back exactly as they were.
-- The gap this was meant to close is small (48 deals). To do it again it needs a plan that stays fast, for example
-- an index on v2_deals that covers shown, or filtering shown inside the view the functions read. For the developer
-- and data owner to decide. The text below is kept as the record of what was tried.
--
-- Map functions count only deals the site shows (v2_deals.shown).
-- Applied to production on 2026-11-22 at the founder's request (migration: map_functions_count_only_shown_deals).
-- For the developer and data owner to review and add to supabase/migrations/.
--
-- Why: the seven v2_map_* functions filtered deals on is_current only. The server's own rule for what the
-- site shows is v2_deals.shown (startups known only from before 2021 are hidden, among other rules).
-- The gap was 48 deals on the day of the change.
--
-- What it does: in every v2_map_* function, each deal filter "<alias>.is_current" (aliases d, x, y, z, all on
-- v2_deals) becomes "<alias>.is_current and <alias>.shown". Sector rows (ss.is_current) are untouched.
do $$
declare r record; o text; s text; n int := 0;
begin
  for r in select p.oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
           where ns.nspname = 'public' and p.proname in ('v2_map_firms','v2_map_hot','v2_map_hot_detail','v2_map_summary','v2_map_updates') loop
    o := pg_get_functiondef(r.oid);
    if o like '%.shown%' then raise exception 'already has shown: %', r.oid::regprocedure; end if;
    s := regexp_replace(o, '\m([dxyz])\.is_current', '\1.is_current and \1.shown', 'g');
    if s = o then raise exception 'nothing changed: %', r.oid::regprocedure; end if;
    execute s; n := n + 1;
  end loop;
  if n <> 7 then raise exception 'expected 7 functions, got %', n; end if;
end $$;
