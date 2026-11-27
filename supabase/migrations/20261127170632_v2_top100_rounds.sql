-- Home page map, the "Top 100" view (founder, 26 Nov 2026), chart "Biggest rounds" (built 27 Nov). A row here is a round, not a firm.
-- New read-only function; nothing existing is changed. Undo: drop function if exists public.v2_top100_rounds(integer);
--
-- Biggest rounds = the 100 biggest funding rounds of this year so far (1 January to today), in dollars.
--   * source: v2_events with kind 'round' and an amount; amounts in other currencies are converted with the latest v2_fx_rates row
--   * IPOs are left out (founder); every other round type stays (Seed to Series H, Growth, Bridge, Debt, Grant, Other)
--   * the same startup, date and dollar amount counts once: the named round wins over "Other", then the one with more investors
--   * the startup's industry group comes from its first-tagged sector: AI (AI models, AI agents), Hardware (Hardware & Robotics, Space),
--     Defense & security (Defense, Security), Climate, Bio & health (Bio, Health), Fintech & crypto, Software (Enterprise software, Developer
--     tools), Other (everything else, e.g. Consumer, Mobility)
--   * "investors we hold" = firms linked to the event in v2_event_firms; "hot" = rounds from the last 30 days
-- Answer: {asof, rounds (all rounds on record), hot (how many of the 100 are from the last 30 days), firms: [[key, startup, dollars, null, null, null,
-- {r: round, d: date, i: sector, n: investors we hold, h: last 30 days, g: industry group}], ...]} in rank order, at most p_n rows (1 to 200, default 100).
do $wraptop$
begin
  if to_regclass('public.v2_events') is null or to_regclass('public.v2_startups') is null or to_regclass('public.v2_fx_rates') is null then
    raise notice 'v2 tables not present, skipping';
    return;
  end if;
  execute $fn$
create or replace function public.v2_top100_rounds(p_n integer default 100)
returns jsonb language sql stable security definer set search_path to 'public' as $body$
with cfg as (
  select date_trunc('year', current_date)::date as y0, current_date as t1, (current_date - 30) as h0,
         greatest(1, least(coalesce(p_n, 100), 200)) as lim
),
fx as materialized (select distinct on (currency) currency, usd_rate from v2_fx_rates order by currency, as_of desc),
sec as materialized (
  select distinct on (startup_id) startup_id, sector_id from v2_startup_sectors
  where is_current and not archived and sector_id is not null order by startup_id, row_id
),
ef as materialized (select event_id, count(distinct firm_id) as n from v2_event_firms where firm_id is not null group by event_id),
r as materialized (
  select e.event_id, e.startup_id, st.startup_name as name, e.round, e.event_date, e.amount * coalesce(fx.usd_rate, case when e.amount_currency is null then 1 end) as usd,
         sc.name as ind, sc.sector_id, coalesce(ef.n, 0) as n
  from v2_events e cross join cfg
  join v2_startups st on st.startup_id = e.startup_id
  left join fx on fx.currency = e.amount_currency
  left join sec on sec.startup_id = e.startup_id
  left join v2_sector sc on sc.sector_id = sec.sector_id
  left join ef on ef.event_id = e.event_id
  where e.kind::text = 'round' and e.event_date >= cfg.y0 and e.event_date <= cfg.t1
    and coalesce(e.round, '') <> 'IPO' and e.amount > 0
),
u as materialized (
  select distinct on (startup_id, event_date, usd) *
  from r where usd is not null
  order by startup_id, event_date, usd, (round = 'Other'), n desc, event_id
),
top as materialized (select u.*, row_number() over (order by usd desc, name, event_id) as rk from u),
pick as materialized (select * from top where rk <= (select lim from cfg))
select jsonb_build_object(
  'asof', (select t1 from cfg),
  'rounds', (select count(*) from v2_events where kind::text = 'round'),
  'hot', (select count(*) from pick, cfg where pick.event_date >= cfg.h0),
  'firms', coalesce((
    select jsonb_agg(jsonb_build_array('e' || pick.event_id, pick.name, round(pick.usd), null, null, null,
      jsonb_build_object('r', pick.round, 'd', pick.event_date, 'i', pick.ind, 'n', pick.n, 'h', pick.event_date >= (select h0 from cfg),
        'g', case when pick.sector_id in (1, 2) then 'AI'
                  when pick.sector_id in (12, 20) then 'Hardware'
                  when pick.sector_id in (10, 19) then 'Defense & security'
                  when pick.sector_id = 6 then 'Climate'
                  when pick.sector_id in (4, 5) then 'Bio & health'
                  when pick.sector_id in (3, 11) then 'Fintech & crypto'
                  when pick.sector_id in (8, 9) then 'Software'
                  else 'Other' end)) order by pick.rk)
    from pick), '[]'::jsonb))
$body$
  $fn$;
  execute 'revoke all on function public.v2_top100_rounds(integer) from public';
  execute 'grant execute on function public.v2_top100_rounds(integer) to anon, authenticated';
end $wraptop$;
