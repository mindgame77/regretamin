-- Home page map, the "Top 100" view, chart "Biggest rounds": the Map button for this chart (founder, 27 Nov 2026: "startup country").
-- Replaces v2_top100_rounds (made earlier today, same name and arguments) with the same answer plus the startup's place on every row.
-- Read-only; nothing else is changed. Undo: apply 20261127170632_v2_top100_rounds.sql again (the version without the place), or drop function if exists public.v2_top100_rounds(integer);
-- The place of a startup: only its country (st_country) and city (st_city) are known, no state. Outside the US the country gives the zoom places (world region, and the
-- country itself on the Europe map). A US startup is placed by its city: the metro that our firms in the same city are placed in (v2_map_firm_places), which is how the other maps place firms;
-- a city no firm sits in, or a startup with no country, has no place (it is counted in the list, not on the map).
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
-- {r: round, d: date, i: sector, n: investors we hold, h: last 30 days, g: industry group, c: startup country, p: world-map region or null, l: 'us' | 'eu' | null (the zoom the
-- startup has a place on), a: its place on that zoom (US metro, or the country code)}], ...]} in rank order, at most p_n rows (1 to 200, default 100).
do $wraptop$
begin
  if to_regclass('public.v2_events') is null or to_regclass('public.v2_startups') is null or to_regclass('public.v2_fx_rates') is null or to_regclass('public.v2_map_firm_places') is null or to_regclass('public.firm_summary') is null then
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
cl as materialized (
  select distinct on (lc) lc, region, area from (
    select lower(btrim(f.hq_city::text)) as lc, p.region, p.area, count(*) as n
    from v2_map_firm_places p join firm_summary f on f.firm_id = p.firm_id
    where f.hq_country = 'US' and p.level = 'us' and f.hq_city is not null and p.area !~ ', '
    group by 1, 2, 3
  ) x order by lc, n desc
),
r as materialized (
  select e.event_id, e.startup_id, st.startup_name as name, e.round, e.event_date, e.amount * coalesce(fx.usd_rate, case when e.amount_currency is null then 1 end) as usd,
         sc.name as ind, sc.sector_id, coalesce(ef.n, 0) as n, upper(btrim(st.st_country::text)) as cc, lower(btrim(st.st_city::text)) as cty
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
pick0 as materialized (select * from top where rk <= (select lim from cfg)),
pick as materialized (
  select p0.*,
    case when p0.cc = 'US' then cl.region
         when p0.cc in ('GB','DE','FR','NL','PL','CH','BE','ES','SE','CZ','DK','UA','LU','IT','PT','FI','NO','GR','AT','EE','HU','BG','IE','LT','CY','RO','LV','IS','SK','RS','MT','HR','SI','MC','LI','AD','GG','JE','IM') then 'Europe'
         when p0.cc = 'IL' then 'Israel'
         when p0.cc in ('AE','SA','TR','OM','KW','JO','BH','QA','LB','IQ') then 'Middle East'
         when p0.cc in ('ZA','KE','NG','EG','MU','MA','GH','SN','TN','RW','ZW','TZ','UG','AO','DZ','NE','ET','BW','NA','MG','ML','CI','SO','GN','CM','CV') then 'Africa'
         when p0.cc in ('BR','CL','MX','AR','CO','PE','GT','UY','BO','CR','VE','SV','EC','PY','HN') then 'Latin America'
         when p0.cc = 'IN' then 'India'
         when p0.cc = 'KR' then 'South Korea'
         when p0.cc = 'JP' then 'Japan'
         when p0.cc in ('CN','HK','TW') then 'China, HK, Taiwan'
         when p0.cc in ('SG','MY','TH','PH','VN','ID') then 'Southeast Asia'
         when p0.cc = 'CA' then 'Canada'
         when p0.cc in ('AU','NZ') then 'Australia and NZ'
         when p0.cc in ('KZ','UZ','AZ','AM','GE') then 'Central Asia and Caucasus'
         when p0.cc in ('KY','VG','BM') then 'Caribbean'
    end as wreg,
    case when p0.cc = 'US' and cl.area is not null then 'us'
         when p0.cc in ('GB','DE','FR','NL','PL','CH','BE','ES','SE','CZ','DK','UA','LU','IT','PT','FI','NO','GR','AT','EE','HU','BG','IE','LT','CY','RO','LV','IS','SK','RS','MT','HR','SI','MC','LI','AD','GG','JE','IM') then 'eu'
    end as zl,
    case when p0.cc = 'US' then cl.area
         when p0.cc in ('GG','JE','IM') then 'GB'
         else p0.cc end as zarea
  from pick0 p0 left join cl on p0.cc = 'US' and cl.lc = p0.cty
)
select jsonb_build_object(
  'asof', (select t1 from cfg),
  'rounds', (select count(*) from v2_events where kind::text = 'round'),
  'hot', (select count(*) from pick, cfg where pick.event_date >= cfg.h0),
  'firms', coalesce((
    select jsonb_agg(jsonb_build_array('e' || pick.event_id, pick.name, round(pick.usd), null, null, null,
      jsonb_build_object('r', pick.round, 'd', pick.event_date, 'i', pick.ind, 'n', pick.n, 'h', pick.event_date >= (select h0 from cfg), 'c', pick.cc, 'p', pick.wreg, 'l', pick.zl, 'a', case when pick.zl is null then null else pick.zarea end,
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
