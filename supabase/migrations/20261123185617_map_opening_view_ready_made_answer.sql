-- map_opening_view_ready_made_answer (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: map_opening_view_ready_made_answer skipped';
    return;
  end if;
  execute $designmig$
-- The map's opening views, counted ahead of time. The page reads the stored answer instead of making the database count
-- 80,000 deals for every visitor. Views with filters are still counted live. Nothing existing is changed.
create table public.v2_map_cache (
  key text primary key,
  payload jsonb not null,
  refreshed_at timestamptz not null default now()
);
alter table public.v2_map_cache enable row level security;
revoke all on table public.v2_map_cache from anon, authenticated;

create function public.v2_refresh_map_cache() returns void
 language plpgsql security definer set search_path to 'public'
as $fn$
begin
  insert into v2_map_cache (key, payload, refreshed_at) values
    ('summary', v2_map_summary()::jsonb, now()),
    ('hot', v2_map_hot()::jsonb, now()),
    ('updates', v2_map_updates(6)::jsonb, now())
  on conflict (key) do update set payload = excluded.payload, refreshed_at = excluded.refreshed_at;
end
$fn$;
revoke all on function public.v2_refresh_map_cache() from public, anon, authenticated;

-- Returns the stored answer, or null when there is none or it is more than a day old (the page then asks live, as before).
create function public.v2_map_cached(p_key text) returns jsonb
 language sql stable security definer set search_path to 'public'
as $fn$
  select c.payload from v2_map_cache c where c.key = p_key and c.refreshed_at > now() - interval '1 day'
$fn$;
revoke all on function public.v2_map_cached(text) from public;
grant execute on function public.v2_map_cached(text) to anon, authenticated, service_role;

select public.v2_refresh_map_cache();
select cron.schedule('v2-map-cache', '*/15 * * * *', $$select public.v2_refresh_map_cache()$$);
notify pgrst, 'reload schema';
$designmig$;
end
$wrapci$;
