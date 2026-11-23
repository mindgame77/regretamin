-- Optional: take back the countries and cities written by fill_startup_location.
-- Only a value that is still exactly what the action wrote is cleared; anything changed since is left alone.
-- Run BEFORE supabase/rollbacks/20261121060000_v2_startup_location_fill.sql. Then the source table can be dropped.
do $undo$
begin
  if to_regclass('public.v2_startup_location_sources') is null then return; end if;
  update public.v2_startups s set st_country = null
    from public.v2_startup_location_sources l
   where l.kind = 'fill' and l.status = 'applied' and l.field = 'st_country'
     and l.startup_id = s.startup_id and s.st_country = l.value;
  update public.v2_startups s set st_city = null
    from public.v2_startup_location_sources l
   where l.kind = 'fill' and l.status = 'applied' and l.field = 'st_city'
     and l.startup_id = s.startup_id and s.st_city = l.value;
  insert into public.v2_change_log (actor, firm_id, box, table_name, row_id, submission_id, old_value, new_value, result)
  select 'rollback', null, 'F14', 'v2_startups', l.startup_id, l.submission_id,
         jsonb_build_object(l.field, l.value), jsonb_build_object(l.field, null), 'Undone: location fill rollback'
    from public.v2_startup_location_sources l where l.kind = 'fill' and l.status = 'applied';
  update public.v2_startup_location_sources set status = 'undone' where kind = 'fill' and status = 'applied';
  -- drop table public.v2_startup_location_sources;  -- only after the undo above, when the record is no longer wanted
end
$undo$;
