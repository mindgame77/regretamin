-- Home page map, the "Pathfinders" view (founder, 25 Nov: "who follows whom ... small companies that are being followed
-- by the top 100", shown on the map). New read-only function; nothing existing is changed.
-- A small firm "is followed" in a startup when a firm on the Top 100 list makes its first dated deal in that startup
-- later than the small firm's own first dated deal there. Small = not on the list and at most p_max_deals deals since 2021.
--   p_from / p_to        the stretch of time the timeline shows: the day the top firm came in
--   p_stages / p_sectors the map's own names: the round the top firm joined, the startup's sectors
--   p_level / p_place    with a place: only that place's firms (the map's zoom and the place as the map names it)
-- Without a place: every place of all three zooms ('places': l, p, f firms, d startups followed), the totals per zoom and
-- the 30 most followed firms per zoom ('lists': [slug, name, startups, [[top firm, startups] x3], place]).
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_counted_places') is null or to_regclass('public.v2_top_firms') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_map_pathfinders(p_from date default '2021-01-01'::date, p_to date default null, p_stages text[] default null, p_sectors text[] default null, p_level text default null, p_place text default null, p_max_deals integer default 50)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
top as materialized (
  select t.firm_id from v2_top_firms t
  where t.list_year = (select max(list_year) from v2_top_firms) and t.world_rank is not null
),
small as materialized (  -- not on the Top 100 list, and at most p_max_deals deals since 2021
  select d.firm_id from v2_deals d
  where d.is_current and d.shown and d.deal_date >= date '2021-01-01' and d.deal_date <= current_date
    and not exists (select 1 from top where top.firm_id = d.firm_id)
  group by 1 having p_max_deals is null or count(*) <= p_max_deals
),
early as materialized (  -- a small firm's first dated deal in each startup
  select d.firm_id, d.startup_id, min(d.deal_date) as d
  from v2_deals d join small using (firm_id)
  where d.is_current and d.shown and d.deal_date is not null and d.deal_date_precision <> 'year' and d.deal_date <= current_date
  group by 1, 2
),
later as materialized (  -- a Top 100 firm's first dated deal in a startup, when it falls in the period, stage and sector asked for
  select x.firm_id, x.startup_id, x.d
  from (select distinct on (d.firm_id, d.startup_id) d.firm_id, d.startup_id, d.deal_date as d, d.round::text as round
        from v2_deals d join top using (firm_id)
        where d.is_current and d.shown and d.deal_date is not null and d.deal_date_precision <> 'year' and d.deal_date <= current_date
        order by d.firm_id, d.startup_id, d.deal_date) x
  left join stg on stg.round = x.round
  where x.d >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01') and x.d <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
fol as materialized (
  select a.firm_id as early, a.startup_id, b.firm_id as later
  from early a join later b on b.startup_id = a.startup_id and b.d > a.d
),
per as materialized (select f.early as firm_id, count(distinct f.startup_id) as n from fol f group by 1),
tops as materialized (select f.early as firm_id, f.later, count(distinct f.startup_id) as c from fol f group by 1, 2),
pl as materialized (  -- where a firm sits, as each zoom of the map names it
  select 'world'::text as l, p.region as p, p.firm_id from v2_map_counted_places p where p.region is not null
  union all
  select p.level, p.area, p.firm_id from v2_map_counted_places p where p.level in ('us', 'eu') and p.area is not null
),
ranked as materialized (
  select pl.l, pl.p, per.firm_id, per.n, fs.slug, fs.display_name as name,
         row_number() over (partition by pl.l order by per.n desc, fs.display_name) as k,
         row_number() over (partition by pl.l, pl.p order by per.n desc, fs.display_name) as kp
  from per join pl using (firm_id) join firm_summary fs on fs.firm_id = per.firm_id
),
shown as (
  select r.l, r.p, r.k, r.kp, jsonb_build_array(r.slug, r.name, r.n,
      coalesce((select jsonb_agg(jsonb_build_array(z.nm, z.c) order by z.c desc, z.nm)
                from (select n2.display_name as nm, t.c from tops t join firm_summary n2 on n2.firm_id = t.later
                      where t.firm_id = r.firm_id order by t.c desc, n2.display_name limit 3) z), '[]'::jsonb), r.p) as j
  from ranked r
  where (p_place is null and r.k <= 30) or (p_place is not null and r.l = p_level and r.p = p_place and r.kp <= 30)
)
select case when p_place is null then jsonb_build_object(
    'places', coalesce((select jsonb_agg(jsonb_build_object('l', x.l, 'p', x.p, 'f', x.f, 'd', x.d))
                        from (select l, p, count(*) as f, sum(n) as d from ranked group by 1, 2) x), '[]'::jsonb),
    'totals', coalesce((select jsonb_object_agg(x.l, jsonb_build_object('firms', x.f, 'follows', x.d))
                        from (select l, count(*) as f, sum(n) as d from ranked group by 1) x), '{}'::jsonb),
    'lists', coalesce((select jsonb_object_agg(x.l, x.j) from (select l, jsonb_agg(j order by k) as j from shown group by 1) x), '{}'::jsonb))
  else jsonb_build_object(
    'firms', (select count(*) from ranked r where r.l = p_level and r.p = p_place),
    'list', coalesce((select jsonb_agg(j order by kp) from shown), '[]'::jsonb)) end
$body$
  $fn$;
  execute 'revoke all on function public.v2_map_pathfinders(date, date, text[], text[], text, text, integer) from public';
  execute 'grant execute on function public.v2_map_pathfinders(date, date, text[], text[], text, text, integer) to anon, authenticated';
end $wrapci$;