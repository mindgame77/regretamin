-- investors_list_v5_faster_hints_and_deal_filter (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_v5_faster_hints_and_deal_filter skipped';
    return;
  end if;
  execute $designmig$
-- Speed fixes to the two functions added today (same names, same arguments, same results):
-- firm_place_suggest read the map-places view several times per call (1.6 s); it now reads it once, and an empty p_q returns
-- every place so the page can load the list once and match as you type. firm_directory_page_v5 no longer applies the
-- place filter a second time when the deals filter (which already includes the place) is on.
create or replace function public.firm_place_suggest(p_q text, p_limit integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
with q as (select lower(btrim(left(coalesce(p_q, ''), 60))) t),
mp as materialized (select p.firm_id, p.region, p.level, p.area from v2_map_firm_places p),
j as materialized (
  select s.firm_id, btrim(coalesce(s.hq_city, '')) city, mp.region, mp.level, mp.area
  from firm_summary s left join mp on mp.firm_id = s.firm_id where s.listed),
usareas as materialized (select distinct lower(area) a from mp where level = 'us' and area is not null),
hit as (
  select 'region'::text kind, 'world'::text lvl, region p, region name, count(*) n from j where region is not null group by region
  union all
  select 'area', 'us', area, area, count(*) from j where level = 'us' and area is not null group by area
  union all
  select 'city', 'city', min(city), min(city), count(*) from j
  where city <> '' and lower(city) not in (select a from usareas) group by lower(city)
)
select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'level', lvl, 'p', p, 'name', name, 'count', n) order by starts desc, n desc, name), '[]'::jsonb)
from (select h.*, (left(lower(h.name), length(q.t)) = q.t) starts from hit h, q
      where q.t = '' or (length(q.t) >= 2 and (left(lower(h.name), length(q.t)) = q.t or position(' ' || q.t in lower(h.name)) > 0))
      order by (left(lower(h.name), length(q.t)) = q.t) desc, h.n desc, h.name
      limit greatest(1, least(coalesce(p_limit, 6), 3000))) z
$fn$;

do $$
declare s text; n text;
begin
  s := pg_get_functiondef((select oid from pg_proc where proname = 'firm_directory_page_v5' and pronamespace = 'public'::regnamespace));
  n := replace(s, 'and (v_place is null or s.firm_id in (select mp.firm_id', 'and (v_place is null or v_deal or s.firm_id in (select mp.firm_id');
  if n = s or position('v_place is null or v_deal or s.firm_id in' in n) = 0 then
    raise exception 'firm_directory_page_v5 does not have the expected text; nothing was changed';
  end if;
  execute n;
end $$;
notify pgrst, 'reload schema';
$designmig$;
end
$wrapci$;
