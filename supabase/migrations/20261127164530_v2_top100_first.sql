-- Home page map, the "Top 100" view (founder, 26 Nov 2026), chart "First in" (built 27 Nov). Same shape as v2_top100_active.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_first(integer);
--
-- First in = the firms that were the first to back the most startups, this year so far (1 January to today), set against the
-- same stretch of days last year (1 January last year to today's date one year back).
--   * a startup's first deal = its earliest shown deal date over ALL firms (not only the map's firms), so a firm only counts as
--     first in when nobody the site knows of backed the startup earlier
--   * firms that share that earliest date all count as first in (about 1 startup in 5 this year has two or more)
--   * a firm counts a startup once; the startup's first deal must fall inside the stretch (this year, or the same days last year)
--   * deals known only by their year sit on 1 January, as in Most active; they can make a firm look first in when the startup's
--     other deals that year have a real date (known limit, same as Most active)
--   * only deals the site shows (is_current and shown) and only firms the map counts (v2_map_counted_places)
-- Answer: {asof, from, prev_from, prev_to, rounds, firms: [[slug, name, startups this year, startups the same days last year,
-- last year's rank or null, country or null], ...]} in rank order, at most p_n firms (1 to 200, default 100).
do $wraptop$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_counted_places') is null or to_regclass('public.v2_events') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_first(p_n integer default 100)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (
  select date_trunc('year', current_date)::date as y0, current_date as t1,
         (date_trunc('year', current_date) - interval '1 year')::date as p0,
         (current_date - interval '1 year')::date as p1,
         greatest(1, least(coalesce(p_n, 100), 200)) as lim
),
counted as materialized (select distinct firm_id from v2_map_counted_places),
e as materialized (
  select startup_id, min(deal_date) as d0
  from v2_deals where is_current and shown and deal_date is not null
  group by startup_id
),
d as materialized (
  select d.firm_id, d.startup_id, (e.d0 >= cfg.y0) as is_now
  from v2_deals d join e on e.startup_id = d.startup_id and e.d0 = d.deal_date cross join cfg
  where d.is_current and d.shown
    and e.d0 >= cfg.p0 and e.d0 <= cfg.t1
    and (e.d0 >= cfg.y0 or e.d0 <= cfg.p1)
    and d.firm_id in (select firm_id from counted)
),
f as materialized (
  select d.firm_id, fs.slug, fs.display_name as name, max(fs.hq_country) as cc,
         count(distinct d.startup_id) filter (where d.is_now) as n,
         count(distinct d.startup_id) filter (where not d.is_now) as p
  from d join firm_summary fs on fs.firm_id = d.firm_id
  group by 1, 2, 3
),
now_r as materialized (select firm_id, row_number() over (order by n desc, name, firm_id) as rk from f where n > 0),
prev_r as materialized (select firm_id, row_number() over (order by p desc, name, firm_id) as rk from f where p > 0)
select jsonb_build_object(
  'asof', (select t1 from cfg), 'from', (select y0 from cfg), 'prev_from', (select p0 from cfg), 'prev_to', (select p1 from cfg),
  'rounds', (select count(*) from v2_events where kind::text = 'round'),
  'firms', coalesce((
    select jsonb_agg(jsonb_build_array(f.slug, f.name, f.n, f.p, pr.rk, f.cc) order by nr.rk)
    from now_r nr join f using (firm_id) left join prev_r pr using (firm_id)
    where nr.rk <= (select lim from cfg)), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_first(integer) from public';
  execute 'grant execute on function public.v2_top100_first(integer) to anon, authenticated';
end $wraptop$;
