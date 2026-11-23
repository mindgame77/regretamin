-- v2_map_summary_chosen_sectors_split (design bot, new site). Applied to production by hand on 2026-11-21 and recorded there
-- under this version, so it is never applied again. The text is the recorded statement, unchanged.
-- On a database without the v2 tables (the test database in CI) this file is a no-op.
do $wrapci$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_firms') is null or to_regclass('public.firm_summary') is null then
    raise notice 'v2 tables missing: v2_map_summary_chosen_sectors_split skipped';
    return;
  end if;
  execute $designmig$
create or replace function public.v2_map_summary(
  p_from date default date '2021-01-01', p_to date default null,
  p_stages text[] default null, p_sectors text[] default null)
returns jsonb language sql stable security definer set search_path = public as $fn$
with stg(round, stage) as (values ('Pre-seed','Pre-seed'),('Seed','Seed'),('Series A','Series A'),('Series B','Series B'),
    ('Series C','Series C+'),('Series D','Series C+'),('Series E','Series C+'),('Series F','Series C+'),('Series G','Series C+'),
    ('Series H','Series C+'),('Series I','Series C+'),('Series J','Series C+'),('Series K','Series C+'),('Series L','Series C+'),('Growth','Growth')),
-- Work out each firm's place once. Without this the metro lookup inside the view runs again for every deal.
fp as materialized (select firm_id, region, level, area from v2_map_firm_places),
-- The deals that pass the filters. One row is one firm's part in one round.
d as materialized (
  select d.startup_id, d.firm_id
  from v2_deals d left join stg on stg.round = d.round::text
  where d.is_current
    and d.firm_id in (select firm_id from fp)
    and d.deal_date >= greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01')
    and d.deal_date <= coalesce(p_to, current_date)
    and (p_stages is null or stg.stage = any(p_stages))
    and (p_sectors is null or exists (
      select 1 from v2_startup_sectors ss join v2_sector sc using (sector_id)
      where ss.startup_id = d.startup_id and ss.is_current and sc.name = any(p_sectors)))
),
-- Count per firm first, then add firms up into places. Much cheaper than counting per place from raw deals.
fd as materialized (select firm_id, count(*) n from d group by 1),
-- When sectors are chosen, the split is among the chosen sectors only (top 5 of them, the rest together).
fs as materialized (
  select d.firm_id, sc.name, count(*) n
  from d join v2_startup_sectors ss on ss.startup_id = d.startup_id and ss.is_current join v2_sector sc using (sector_id)
  where p_sectors is null or sc.name = any(p_sectors)
  group by 1, 2
),
pl as materialized (
  select 'world'::text lvl, region place, firm_id from fp where region is not null
  union all
  select level, area, firm_id from fp where level is not null
),
t as (select pl.lvl, pl.place, sum(fd.n) deals, count(*) firms from pl join fd using (firm_id) group by 1, 2),
s as (select pl.lvl, pl.place, fs.name, sum(fs.n) n from pl join fs using (firm_id) group by 1, 2, 3),
k as (
  select s.*, row_number() over (partition by lvl, place order by n desc, name) rk,
    sum(n) over (partition by lvl, place) tot, sum(n) over (partition by lvl, name) sn, sum(n) over (partition by lvl) alln
  from s
),
x as (
  select lvl, place, max(tot) tot,
    jsonb_agg(jsonb_build_array(name, n) order by rk) filter (where rk <= 5) top,
    (array_agg(name order by (n::float8 / tot) / (sn::float8 / alln) desc, n desc) filter (where rk <= 5))[1] standout
  from k group by 1, 2
),
tt as (select lvl, sum(deals) deals, sum(firms) firms from t group by 1)
select jsonb_build_object(
  'from', greatest(coalesce(p_from, date '2021-01-01'), date '2021-01-01'),
  'to', coalesce(p_to, current_date),
  'totals', coalesce((select jsonb_object_agg(lvl, jsonb_build_object('deals', deals, 'firms', firms)) from tt), '{}'::jsonb),
  -- US cities outside the metro list come out of the view as "City, ST". The map has no spot for them,
  -- so they are counted in the totals above but not sent as places.
  'places', coalesce((
    select jsonb_agg(jsonb_build_object('l', t.lvl, 'p', t.place, 'd', t.deals, 'f', t.firms, 'tot', x.tot, 'top', x.top, 'so', x.standout)
                     order by t.lvl, t.deals desc, t.place)
    from t left join x using (lvl, place)
    where t.place <> '(no city)' and not (t.lvl = 'us' and t.place ~ ', [A-Z]{2}$')), '[]'::jsonb))
$fn$;
$designmig$;
end
$wrapci$;
