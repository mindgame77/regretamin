-- v2_map_who_filter (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_who_filter skipped';
    return;
  end if;
  execute $designmig$
create or replace function public.v2_map_hot(
  p_firms text, p_days int default 90, p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path = public as $fn$
with cfg as (select greatest(30, least(coalesce(p_days, 90), 366)) days,
  case when p_firms = 'top' then 'top' when p_firms in ('focused', 'new') and p_sectors is not null then p_firms else 'all' end mode),
top as materialized (select firm_id, (world_rank is not null or region_rank is not null) w, us_rank is not null u, eu_rank is not null e
  from v2_top_firms where list_year = 2026 and (select mode from cfg) = 'top'),
foc as materialized (
  select x.firm_id from v2_deals x
  where (select mode from cfg) = 'focused' and x.is_current and x.deal_date > current_date - interval '3 years' and x.deal_date <= current_date
  group by x.firm_id
  having count(*) >= 5 and count(*) filter (where exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) > 0.25 * count(*)),
fst as materialized (
  select x.firm_id, min(x.deal_date) fdate from v2_deals x
  where (select mode from cfg) = 'new' and x.is_current and x.deal_date is not null and exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))
  group by x.firm_id),
stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
fp as materialized (select firm_id, region, level, area from v2_map_firm_places),
d as materialized (
  select d.startup_id, d.firm_id, (d.deal_date > current_date - cfg.days) is_now
  from v2_deals d cross join cfg left join stg on stg.round = d.round::text
  where d.is_current
    and d.firm_id in (select firm_id from fp)
    and d.deal_date_precision::text <> 'year'
    and d.deal_date > current_date - 2 * cfg.days and d.deal_date <= current_date
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
    and (cfg.mode <> 'focused' or d.firm_id in (select firm_id from foc))
    and (cfg.mode <> 'new' or exists (select 1 from fst where fst.firm_id = d.firm_id
         and fst.fdate > current_date - case when d.deal_date > current_date - cfg.days then cfg.days else 2 * cfg.days end))
),
fd as materialized (select firm_id, count(*) filter (where is_now) n, count(*) filter (where not is_now) p from d group by 1),
fs as materialized (
  select d.firm_id, sc.name, count(*) filter (where is_now) n, count(*) filter (where not is_now) p
  from d join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current join v2_sector sc using (sector_id)
  where sc.name <> 'Other' and (p_sectors is null or sc.name = any(p_sectors))
  group by 1, 2
),
pl as materialized (
  select 'world'::text lvl, region place, firm_id from fp where region is not null
    and ((select mode from cfg) <> 'top' or firm_id in (select firm_id from top where w))
  union all
  select level, area, firm_id from fp where level is not null
    and ((select mode from cfg) <> 'top' or firm_id in (select firm_id from top where (fp.level = 'us' and u) or (fp.level = 'eu' and e)))
),
t as (select pl.lvl, pl.place, sum(fd.n) n, sum(fd.p) p, count(*) filter (where fd.n > 0) firms from pl join fd using (firm_id) group by 1, 2),
s as (select pl.lvl, pl.place, fs.name, sum(fs.n) n, sum(fs.p) p from pl join fs using (firm_id) group by 1, 2, 3),
hot as (select distinct on (lvl, place) lvl, place, jsonb_build_array(name, n, p) j from s where n >= 8 and n > p
        order by lvl, place, (n - p)::float8 / greatest(p, 3) desc, n desc),
cold as (select distinct on (lvl, place) lvl, place, jsonb_build_array(name, n, p) j from s where p >= 8 and n < p
         order by lvl, place, (n - p)::float8 / greatest(p, 3) asc, p desc),
sl as (select pl.lvl, fs.name, sum(fs.n) n, sum(fs.p) p from (select distinct lvl, firm_id from pl) pl join fs using (firm_id) group by 1, 2),
tt as (select lvl, sum(n) n, sum(p) p, sum(firms) firms from t group by 1)
select jsonb_build_object(
  'days', (select days from cfg),
  'totals', coalesce((select jsonb_object_agg(lvl, jsonb_build_object('deals', n, 'prev', p, 'firms', firms)) from tt), '{}'::jsonb),
  'sectors', coalesce((select jsonb_object_agg(lvl, rows) from (
      select lvl, jsonb_agg(jsonb_build_array(name, n, p) order by n desc, name) rows from sl where n + p > 0 group by lvl) q), '{}'::jsonb),
  'places', coalesce((
    select jsonb_agg(jsonb_build_object('l', t.lvl, 'p', t.place, 'd', t.n, 'pv', t.p, 'f', t.firms, 'hot', hot.j, 'cold', cold.j)
                     order by t.lvl, t.n desc, t.place)
    from t left join hot using (lvl, place) left join cold using (lvl, place)
    where t.place <> '(no city)' and not (t.lvl = 'us' and t.place ~ ', [A-Z]{2}$')), '[]'::jsonb))
$fn$;

create or replace function public.v2_map_firms(
  p_firms text, p_level text, p_place text,
  p_from date default date '2021-01-01', p_to date default null,
  p_stages text[] default null, p_sectors text[] default null, p_limit int default 200)
returns jsonb language sql stable security definer set search_path = public as $fn$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
cfg as (select case when p_firms = 'top' then 'top' when p_firms in ('focused', 'new') and p_sectors is not null then p_firms else 'all' end mode),
fp as (
  select p.firm_id from v2_map_firm_places p, cfg
  where ((p_level = 'world' and p.region = p_place) or (p_level in ('us', 'eu') and p.level = p_level and p.area = p_place))
    and (cfg.mode <> 'top' or p.firm_id in (select t.firm_id from v2_top_firms t where t.list_year = 2026 and case p_level
          when 'us' then t.us_rank is not null when 'eu' then t.eu_rank is not null else t.world_rank is not null or t.region_rank is not null end))
    and (cfg.mode <> 'focused' or p.firm_id in (
          select x.firm_id from v2_deals x
          where x.firm_id = p.firm_id and x.is_current and x.deal_date > current_date - interval '3 years' and x.deal_date <= current_date
          group by x.firm_id
          having count(*) >= 5 and count(*) filter (where exists (
              select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
              where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) > 0.25 * count(*)))
    and (cfg.mode <> 'new' or (
          select min(x.deal_date) from v2_deals x
          where x.firm_id = p.firm_id and x.is_current and x.deal_date is not null and exists (
              select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
              where ss.startup_id = x.startup_id and ss.is_current and sc.name = any(p_sectors))) >= coalesce(p_from, date '2021-01-01'))
),
d as (
  select d.firm_id, count(*) deals, count(*) filter (where d.lead::text = 'yes') led
  from v2_deals d join fp using (firm_id) left join stg on stg.round = d.round::text
  where d.is_current
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
  group by d.firm_id
),
w as (select case when extract(month from current_date) <= 5
                  then (date_trunc('year', current_date) - interval '1 year')::date
                  else date_trunc('year', current_date)::date end ws)
select jsonb_build_object(
  'count', (select count(*) from d),
  'firms', coalesce((
    select jsonb_agg(z order by (z->>'deals')::int desc, z->>'name') from (
      select jsonb_build_object('slug', f.slug, 'name', f.display_name, 'deals', d.deals, 'led', d.led,
        'last', (select max(x.deal_date) from v2_deals x where x.firm_id = d.firm_id and x.is_current and x.deal_date <= current_date),
        'status', (select case when count(*) >= 3 then 'Active' when count(*) >= 1 then 'Low activity' else 'Not active' end
                   from v2_deals x, w where x.firm_id = d.firm_id and x.is_current and x.deal_date >= w.ws and x.deal_date <= current_date)) z
      from d join firm_summary f using (firm_id)
      order by d.deals desc, f.display_name limit greatest(1, least(coalesce(p_limit, 200), 500))) q), '[]'::jsonb))
$fn$;

grant execute on function public.v2_map_hot(text, int, text[], text[]) to anon, authenticated;
grant execute on function public.v2_map_firms(text, text, text, date, date, text[], text[], int) to anon, authenticated;
$designmig$;
end
$wrapci$;
