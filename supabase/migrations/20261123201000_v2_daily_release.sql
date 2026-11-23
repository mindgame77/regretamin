-- Daily release (2026-11-23, Alex): at 3 AM PT (11:00 UTC) every day, free stuck bot holds.
-- Calls founderlist.release_expired() and founderlist.loc_release_expired(), and deletes section holds
-- that were never checked and are older than 2 hours. Went live 2026-11-23 12:10 PM PT.
-- Undo: select cron.unschedule('v2-daily-release'); drop function public.v2_daily_release();

-- On a database without the v2 tables (the test database in CI) this whole file is a no-op, like the other v2 data
-- migrations. It ran in production on 2026-11-23 as written below; the wrapper only lets a fresh test database skip it.
do $ci_wrap$
begin
  if to_regclass('public.v2_firms') is null then
    raise notice 'v2 tables missing: daily release skipped';
    return;
  end if;
  execute $ci_body$
create or replace function public.v2_daily_release()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'founderlist', 'pg_catalog'
as $f$
declare
  v_founders integer;
  v_locations integer;
  v_sections integer;
begin
  v_founders := founderlist.release_expired();
  v_locations := founderlist.loc_release_expired();
  with d as (
    delete from public.v2_section_holds
     where checked_at is null and claimed_at <= now() - interval '2 hours'
    returning 1
  ) select count(*) into v_sections from d;
  return jsonb_build_object('founder_startups', v_founders, 'location_startups', v_locations, 'section_holds', v_sections, 'at', now());
end
$f$;
revoke all on function public.v2_daily_release() from public, anon, authenticated;
select cron.schedule('v2-daily-release', '0 11 * * *', 'select public.v2_daily_release()');
$ci_body$;
end
$ci_wrap$;
