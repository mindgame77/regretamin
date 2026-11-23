-- firm_page_signals_with_map_place (design bot, new site). Applied to production by hand on 2026-11-22 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: firm_page_signals_with_map_place skipped';
    return;
  end if;
  execute $designmig$
-- v2_firm_signals_for also returns where the firm sits on the map (from v2_map_firm_places), for the "On the map" card.
-- Only this one function (added today) changes; the keys it already returned stay the same.
create or replace function public.v2_firm_signals_for(p_slug text)
returns json language sql stable security definer
set search_path to 'public', 'pg_temp' set statement_timeout to '3s'
as $fn$
  select json_build_object('signals', coalesce(to_json(g.signals), '[]'::json), 'deals_now', coalesce(g.deals_now, 0),
                           'deals_prev', coalesce(g.deals_prev, 0), 'led_now', coalesce(g.led_now, 0),
                           'place', (select json_build_object('region', p.region, 'level', p.level, 'area', p.area)
                                       from v2_map_firm_places p where p.firm_id = s.firm_id limit 1))
    from firm_summary s left join v2_firm_signals g on g.firm_id = s.firm_id
   where s.listed and s.slug = left(btrim(coalesce(p_slug, '')), 120)
   limit 1
$fn$;
$designmig$;
end
$wrapci$;
