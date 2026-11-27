-- Home page map, the "Top 100" view (founder, 26 Nov 2026), first chart: "Most active".
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_active(integer);
--
-- Most active = the firms that backed the most different startups this year so far (1 January to today), set against the
-- same stretch of days last year (1 January last year to today's date one year back).
--   * one startup counts once per firm, however many rounds it raised with that firm
--   * only deals the site shows (is_current and shown). Deals known only by their year ARE counted (founder's picture,
--     26 Nov: Orbit, FJ Labs and Eight Capital are mostly year-only). They sit on 1 January in the data, so they fall in
--     both stretches alike and cannot make a false jump here; the map's Trends view still skips them (v2_map_hot).
--   * only firms the map counts (v2_map_counted_places)
-- Answer: {asof, from, prev_from, prev_to, rounds, firms: [[slug, name, startups this year, startups the same days last
-- year, last year's rank or null], ...]} in rank order, at most p_n firms (1 to 200, default 100). The rank last year is
-- the firm's place in the same count a year ago, so the page can show "up 13", "down 7", "was 178th" and "new".
do $wraptop$
begin
  if to_regclass('public.v2_deals') is null or to_regclass('public.v2_map_counted_places') is null or to_regclass('public.v2_events') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_active(p_n integer default 100)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (
  select date_trunc('year', current_date)::date as y0, current_date as t1,
         (date_trunc('year', current_date) - interval '1 year')::date as p0,
         (current_date - interval '1 year')::date as p1,
         greatest(1, least(coalesce(p_n, 100), 200)) as lim
),
counted as materialized (select distinct firm_id from v2_map_counted_places),
d as materialized (
  select d.firm_id, d.startup_id, (d.deal_date >= cfg.y0) as is_now
  from v2_deals d cross join cfg
  where d.is_current and d.shown
    and d.deal_date >= cfg.p0 and d.deal_date <= cfg.t1
    and (d.deal_date >= cfg.y0 or d.deal_date <= cfg.p1)
    and d.firm_id in (select firm_id from counted)
),
f as materialized (
  select d.firm_id, fs.slug, fs.display_name as name,
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
    select jsonb_agg(jsonb_build_array(f.slug, f.name, f.n, f.p, pr.rk) order by nr.rk)
    from now_r nr join f using (firm_id) left join prev_r pr using (firm_id)
    where nr.rk <= (select lim from cfg)), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_active(integer) from public';
  execute 'grant execute on function public.v2_top100_active(integer) to anon, authenticated';
end $wraptop$;
