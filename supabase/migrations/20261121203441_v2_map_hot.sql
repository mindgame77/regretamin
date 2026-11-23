-- v2_map_hot (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_hot skipped';
    return;
  end if;
  execute $designmig$
-- "Hot right now" view of the map: deals in the last p_days days against the p_days before, per place and per sector.
-- Read-only. Only deals whose day or month is known are counted: a deal known only by its year sits on 1 January
-- in the data and would create a false jump, so it is left out here (deals with no date at all are never counted).
create or replace function public.v2_map_hot(
  p_days int default 90, p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path = public as $fn$
with cfg as (select greatest(30, least(coalesce(p_days, 90), 366)) days),
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
  union all
  select level, area, firm_id from fp where level is not null
),
t as (select pl.lvl, pl.place, sum(fd.n) n, sum(fd.p) p, count(*) filter (where fd.n > 0) firms from pl join fd using (firm_id) group by 1, 2),
s as (select pl.lvl, pl.place, fs.name, sum(fs.n) n, sum(fs.p) p from pl join fs using (firm_id) group by 1, 2, 3),
-- a place's fastest riser and fastest faller among sectors with enough deals to mean something
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

grant execute on function public.v2_map_hot(int, text[], text[]) to anon, authenticated;
$designmig$;
end
$wrapci$;
