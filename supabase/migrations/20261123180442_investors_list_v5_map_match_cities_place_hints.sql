-- investors_list_v5_map_match_cities_place_hints (design bot, new site). Applied to production by hand on 2026-11-23 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: investors_list_v5_map_match_cities_place_hints skipped';
    return;
  end if;
  execute $designmig$
-- Three new functions for the new site's Investors list. Nothing existing is changed or removed
-- (firm_directory_page_v2, v3 and v4 and every v2_map_* function stay exactly as they are).

-- 1. Which firms the map counts for a place: the same rule as v2_map_firms (its stg, cfg, fp and d parts, copied as they are),
--    returning firm ids instead of a capped list. Used only inside firm_directory_page_v5. KEEP IN STEP WITH v2_map_firms.
create function public.v2_map_firm_ids(p_firms text, p_level text, p_place text, p_from date, p_to date, p_stages text[], p_sectors text[])
 returns setof bigint
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
cfg as (select case when p_firms in ('top', 'focused', 'new') then p_firms else 'all' end mode),
fp as (
  select p.firm_id from v2_map_firm_places p, cfg
  where ((p_level = 'world' and p.region = p_place) or (p_level in ('us', 'eu') and p.level = p_level and p.area = p_place))
    and (cfg.mode <> 'top' or p.firm_id in (select t.firm_id from v2_top_firms t where t.list_year = 2026 and case p_level
          when 'us' then t.us_rank is not null when 'eu' then t.eu_rank is not null else t.world_rank is not null or t.region_rank is not null end))
    and (cfg.mode <> 'focused' or p.firm_id in (
          select x.firm_id from v2_deals x
          where x.firm_id = p.firm_id and x.is_current and x.shown and x.deal_date > current_date - interval '3 years' and x.deal_date <= current_date
          group by x.firm_id
          having count(*) >= 10 and case when p_sectors is null then exists (select 1 from v2_deals y join v2_startup_sectors ss on ss.startup_id = y.startup_id and ss.is_current join v2_sector sc using (sector_id) where y.firm_id = x.firm_id and y.is_current and y.shown and y.deal_date > current_date - interval '3 years' and y.deal_date <= current_date and sc.name <> 'Other' group by sc.name having count(*) > 0.5 * (select count(*) from v2_deals z where z.firm_id = x.firm_id and z.is_current and z.shown and z.deal_date > current_date - interval '3 years' and z.deal_date <= current_date)) else count(*) filter (where exists (
              select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
              where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) > 0.33 * count(*) end))
    and (cfg.mode <> 'new' or (
          select min(x.deal_date) from v2_deals x
          where x.firm_id = p.firm_id and x.is_current and x.shown and x.deal_date is not null and (p_sectors is null or exists (
              select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
              where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors)))) >= coalesce(p_from, date '2021-01-01'))
),
d as (
  select d.firm_id
  from v2_deals d join fp using (firm_id) left join stg on stg.round = d.round::text
  where d.is_current and d.shown
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
  group by d.firm_id
)
select d.firm_id from d
$fn$;
revoke all on function public.v2_map_firm_ids(text, text, text, date, date, text[], text[]) from public, anon, authenticated;

-- 2. Investors list, version 5: firm_directory_page_v3's text with more optional filters.
--    p_place_level + p_place: a place on the map. p_map_region: the map's regions, several at once ('Not disclosed' = no region).
--    p_city: the firm's own city. p_deal_from (with a place): only the firms the map counts there, by deals done in the period
--    (p_deal_to, p_deal_stages, p_deal_sectors, p_deal_firms are the map's own arguments). Facets also carry map_region counts.
do $$
declare s text; n text;
begin
  s := pg_get_functiondef((select oid from pg_proc where proname = 'firm_directory_page_v3' and pronamespace = 'public'::regnamespace));
  n := replace(s, 'public.firm_directory_page_v3(', 'public.firm_directory_page_v5(');
  n := replace(n, 'p_deals_year text DEFAULT NULL::text)', 'p_deals_year text DEFAULT NULL::text, p_place_level text DEFAULT NULL::text, p_place text DEFAULT NULL::text, p_map_region text[] DEFAULT NULL::text[], p_city text[] DEFAULT NULL::text[], p_deal_from date DEFAULT NULL::date, p_deal_to date DEFAULT NULL::date, p_deal_stages text[] DEFAULT NULL::text[], p_deal_sectors text[] DEFAULT NULL::text[], p_deal_firms text DEFAULT NULL::text)');
  n := replace(n, E'  v_facets json := null;\nbegin', E'  v_facets json := null;\n  v_plevel text := case when p_place_level in (''world'', ''us'', ''eu'') then p_place_level end;\n  v_place text := case when p_place_level in (''world'', ''us'', ''eu'') then nullif(btrim(coalesce(p_place, '''')), '''') end;\n  v_mregions text[] := ''{}'';\n  v_cities text[] := ''{}'';\n  v_deal boolean := false;\n  v_dstages text[] := case when cardinality(coalesce(p_deal_stages, ''{}''::text[])) = 0 then null else p_deal_stages end;\n  v_dsectors text[] := case when cardinality(coalesce(p_deal_sectors, ''{}''::text[])) = 0 then null else p_deal_sectors end;\nbegin\n  v_deal := v_place is not null and p_deal_from is not null;');
  n := replace(n, E'  select coalesce(array_agg(distinct btrim(t)), ''{}'') into v_regions', E'  select coalesce(array_agg(distinct btrim(t)), ''{}'') into v_mregions\n    from unnest(coalesce(p_map_region, ''{}''::text[])) t where btrim(coalesce(t, '''')) <> '''';\n  select coalesce(array_agg(distinct lower(btrim(t))), ''{}'') into v_cities\n    from unnest(coalesce(p_city, ''{}''::text[])) t where btrim(coalesce(t, '''')) <> '''';\n  select coalesce(array_agg(distinct btrim(t)), ''{}'') into v_regions');
  n := replace(n, 'v_narrow := cardinality(v_signals) > 0 or', 'v_narrow := v_place is not null or cardinality(v_mregions) > 0 or cardinality(v_cities) > 0 or cardinality(v_signals) > 0 or');
  n := replace(n, E'     where s.listed\n       and (cardinality(v_signals) = 0', E'     where s.listed\n       and (v_place is null or s.firm_id in (select mp.firm_id from v2_map_firm_places mp where (v_plevel = ''world'' and mp.region = v_place) or (v_plevel in (''us'', ''eu'') and mp.level = v_plevel and mp.area = v_place)))\n       and (cardinality(v_mregions) = 0 or s.firm_id in (select mp.firm_id from v2_map_firm_places mp where mp.region = any(v_mregions) or (mp.region is null and ''Not disclosed'' = any(v_mregions))))\n       and (cardinality(v_cities) = 0 or lower(btrim(s.hq_city)) = any(v_cities))\n       and (not v_deal or s.firm_id in (select v2_map_firm_ids(p_deal_firms, v_plevel, v_place, p_deal_from, p_deal_to, v_dstages, v_dsectors)))\n       and (cardinality(v_signals) = 0');
  n := replace(n, E'      ''industry'', coalesce((', E'      ''map_region'', coalesce((\n        select json_agg(json_build_object(''value'', region, ''count'', n))\n          from (select coalesce(mp.region, ''Not disclosed'') as region, count(*) as n from v2_map_firm_places mp join live lv on lv.firm_id = mp.firm_id group by 1) mr\n      ), ''[]''::json),\n      ''industry'', coalesce((');
  if position('firm_directory_page_v5(' in n) = 0 or position('p_deal_firms text DEFAULT' in n) = 0 or position('v_dsectors text[] :=' in n) = 0
     or position('v_deal := v_place is not null' in n) = 0 or position('into v_mregions' in n) = 0 or position('into v_cities' in n) = 0
     or position('cardinality(v_cities) > 0 or' in n) = 0 or position('select v2_map_firm_ids(' in n) = 0
     or position('''map_region'', coalesce' in n) = 0 then
    raise exception 'firm_directory_page_v3 no longer has the expected text; v5 was not created';
  end if;
  execute n;
end $$;
revoke all on function public.firm_directory_page_v5(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[], text[], text, text, text, text[], text[], date, date, text[], text[], text) from public;
grant execute on function public.firm_directory_page_v5(integer, integer, text, boolean, text[], text[], text[], text[], text[], text[], text[], text[], text, text, text, text[], text[], date, date, text[], text[], text) to anon, authenticated, service_role;

-- 3. Place hints for the search bar: the map's regions, the map's US areas (a city with the towns around it) and,
--    for everything else, the city on the firm's own profile. Only places with at least one listed firm, each with its count.
create function public.firm_place_suggest(p_q text, p_limit integer default 6)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $fn$
with q as (select lower(btrim(left(coalesce(p_q, ''), 60))) t),
hit as (
  select 'region'::text kind, 'world'::text lvl, mp.region p, mp.region name, count(*) n
  from v2_map_firm_places mp join firm_summary s on s.firm_id = mp.firm_id and s.listed, q
  where mp.region is not null and length(q.t) >= 2
    and (left(lower(mp.region), length(q.t)) = q.t or position(' ' || q.t in lower(mp.region)) > 0)
  group by mp.region
  union all
  select 'area', 'us', mp.area, mp.area, count(*)
  from v2_map_firm_places mp join firm_summary s on s.firm_id = mp.firm_id and s.listed, q
  where mp.level = 'us' and mp.area is not null and length(q.t) >= 2
    and (left(lower(mp.area), length(q.t)) = q.t or position(' ' || q.t in lower(mp.area)) > 0)
  group by mp.area
  union all
  select 'city', 'city', min(btrim(s.hq_city)), min(btrim(s.hq_city)), count(*)
  from firm_summary s, q
  where s.listed and btrim(coalesce(s.hq_city, '')) <> '' and length(q.t) >= 2
    and (left(lower(btrim(s.hq_city)), length(q.t)) = q.t or position(' ' || q.t in lower(btrim(s.hq_city))) > 0)
    and not exists (select 1 from v2_map_firm_places a where a.level = 'us' and lower(a.area) = lower(btrim(s.hq_city)))
  group by lower(btrim(s.hq_city))
)
select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'level', lvl, 'p', p, 'name', name, 'count', n) order by starts desc, n desc, name), '[]'::jsonb)
from (select h.*, (left(lower(h.name), length(q.t)) = q.t) starts from hit h, q
      order by (left(lower(h.name), length(q.t)) = q.t) desc, h.n desc, h.name
      limit greatest(1, least(coalesce(p_limit, 6), 10))) z
$fn$;
revoke all on function public.firm_place_suggest(text, integer) from public;
grant execute on function public.firm_place_suggest(text, integer) to anon, authenticated, service_role;
notify pgrst, 'reload schema';
$designmig$;
end
$wrapci$;
