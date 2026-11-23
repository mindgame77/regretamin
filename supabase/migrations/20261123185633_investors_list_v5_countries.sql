-- investors_list_v5_countries (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_v5_countries skipped';
    return;
  end if;
  execute $designmig$
-- Countries for the Investors list's search hints and filter (same function names and arguments as before):
-- firm_place_suggest also returns the countries that have a listed firm (kind 'country', the two-letter code; the page
-- shows the country's name), and firm_directory_page_v5 accepts p_place_level = 'country' with the code in p_place.
create or replace function public.firm_place_suggest(p_q text, p_limit integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
with q as (select lower(btrim(left(coalesce(p_q, ''), 60))) t),
mp as materialized (select p.firm_id, p.region, p.level, p.area from v2_map_firm_places p),
j as materialized (
  select s.firm_id, btrim(coalesce(s.hq_city, '')) city, upper(btrim(coalesce(s.hq_country, ''))) country, mp.region, mp.level, mp.area
  from firm_summary s left join mp on mp.firm_id = s.firm_id where s.listed),
usareas as materialized (select distinct lower(area) a from mp where level = 'us' and area is not null),
hit as (
  select 'region'::text kind, 'world'::text lvl, region p, region name, count(*) n from j where region is not null group by region
  union all
  select 'area', 'us', area, area, count(*) from j where level = 'us' and area is not null group by area
  union all
  select 'city', 'city', min(city), min(city), count(*) from j
  where city <> '' and lower(city) not in (select a from usareas) group by lower(city)
  union all
  select 'country', 'country', country, country, count(*) from j where country ~ '^[A-Z]{2}$' group by country
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
  n := replace(s, E'  v_mregions text[] := ''{}'';\n', E'  v_mregions text[] := ''{}'';\n  v_country text := case when p_place_level = ''country'' and upper(btrim(coalesce(p_place, ''''))) ~ ''^[A-Z]{2}$'' then upper(btrim(p_place)) end;\n');
  n := replace(n, 'v_narrow := v_place is not null or', 'v_narrow := v_place is not null or v_country is not null or');
  n := replace(n, E'       and (cardinality(v_cities) = 0 or lower(btrim(s.hq_city)) = any(v_cities))\n', E'       and (cardinality(v_cities) = 0 or lower(btrim(s.hq_city)) = any(v_cities))\n       and (v_country is null or upper(btrim(s.hq_country)) = v_country)\n');
  if position('v_country text :=' in n) = 0 or position('v_place is not null or v_country is not null or' in n) = 0 or position('upper(btrim(s.hq_country)) = v_country' in n) = 0 then
    raise exception 'firm_directory_page_v5 does not have the expected text; nothing was changed';
  end if;
  execute n;
end $$;
notify pgrst, 'reload schema';
$designmig$;
end
$wrapci$;
