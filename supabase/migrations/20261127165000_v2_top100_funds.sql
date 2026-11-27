-- Home page map, the "Top 100" view (founder, 26 Nov 2026), chart "Biggest new funds" (built 27 Nov). Same idea as v2_top100_active, other numbers.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_funds(integer);
--
-- Biggest new funds = each firm's biggest fund announced in the last 12 months (the day after the same date a year ago, up to today),
-- set against its biggest fund announced in the 12 months before that.
--   * source: firm_fund_announcements, only rows that are current, not archived and have a dollar amount (amount_usd)
--   * one fund per firm: the biggest (ties: the newest announcement)
--   * only firms the map counts (v2_map_counted_places)
--   * the rank last year is the firm's place in the same list a year ago; a firm with no fund in those earlier 12 months has no amount
--     and no rank last year (the page draws it grey, "no earlier fund on record")
-- Answer: {asof, firms: [[slug, name, biggest fund in dollars, the biggest fund a year ago or null, last year's rank or null,
-- country or null, announced on (date)], ...]} in rank order, at most p_n firms (1 to 200, default 100).
do $wraptop$
begin
  if to_regclass('public.firm_fund_announcements') is null or to_regclass('public.v2_map_counted_places') is null then
    raise notice 'fund tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_funds(p_n integer default 100)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (
  select current_date as t1, (current_date - interval '1 year')::date as t0, (current_date - interval '2 year')::date as tp,
         greatest(1, least(coalesce(p_n, 100), 200)) as lim
),
counted as materialized (select distinct firm_id from v2_map_counted_places),
a as materialized (
  select a.firm_id, a.amount_usd, a.announced_on, (a.announced_on > cfg.t0) as is_now
  from firm_fund_announcements a cross join cfg
  where a.is_current and not a.archived and a.amount_usd > 0 and a.announced_on is not null
    and a.announced_on > cfg.tp and a.announced_on <= cfg.t1
    and a.firm_id in (select firm_id from counted)
),
now_b as materialized (
  select distinct on (firm_id) firm_id, amount_usd as amt, announced_on as dt from a where is_now order by firm_id, amount_usd desc, announced_on desc
),
prev_b as materialized (
  select distinct on (firm_id) firm_id, amount_usd as amt from a where not is_now order by firm_id, amount_usd desc, announced_on desc
),
nm as materialized (select n.firm_id, n.amt, n.dt, fs.slug, fs.display_name as name, fs.hq_country as cc from now_b n join firm_summary fs on fs.firm_id = n.firm_id),
now_r as materialized (select firm_id, row_number() over (order by amt desc, name, firm_id) as rk from nm),
prev_r as materialized (
  select p.firm_id, row_number() over (order by p.amt desc, fs.display_name, p.firm_id) as rk
  from prev_b p join firm_summary fs on fs.firm_id = p.firm_id
)
select jsonb_build_object(
  'asof', (select t1 from cfg),
  'firms', coalesce((
    select jsonb_agg(jsonb_build_array(nm.slug, nm.name, nm.amt, pb.amt, pr.rk, nm.cc, nm.dt) order by nr.rk)
    from now_r nr join nm using (firm_id) left join prev_b pb using (firm_id) left join prev_r pr using (firm_id)
    where nr.rk <= (select lim from cfg)), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_funds(integer) from public';
  execute 'grant execute on function public.v2_top100_funds(integer) to anon, authenticated';
end $wraptop$;
